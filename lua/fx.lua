local M = {}

local ns = vim.api.nvim_create_namespace('fx')
local decors = {} ---@type table<string, fun(buf: integer, file: string, line: integer, opts?: table)>
local bufs = {} ---@type table<integer, boolean>

local type_hlgroup = {
  block = 'FxBlock',
  char = 'FxChar',
  directory = 'FxDirectory',
  fifo = 'FxFifo',
  file = 'FxFile',
  link = 'FxLink',
  socket = 'FxSocket',
  unknown = 'FxUnknown',
}

local type_indicator = {
  block = '#',
  char = '%',
  directory = '/',
  fifo = '|',
  file = '',
  link = '@',
  socket = '=',
  unknown = '?',
}

---@param buf? integer
local function resolve_buf(buf)
  return (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
end

---@param x integer
---@param min integer
---@param max integer
local function clamp(x, min, max)
  return math.max(math.min(x, max), min)
end

---@param stat uv.fs_stat.result
local function is_executable(stat)
  return require('bit').band(stat.mode, tonumber('111', 8)) ~= 0
end

---@param stat uv.fs_stat.result
local function has_stickybit(stat)
  return require('bit').band(stat.mode, tonumber('1000', 8)) ~= 0
end

---@param stat? uv.fs_stat.result
local function get_file_indicator(stat)
  if not stat then
    return '?'
  end

  local indicator = type_indicator[stat.type] or '?'
  if stat.type == 'file' and is_executable(stat) then
    return '*'
  end

  return indicator
end

---@param stat? uv.fs_stat.result
local function get_file_hl_group(stat)
  if not stat then
    return 'FxUnknown'
  end

  local hl_group = type_hlgroup[stat.type] or 'FxUnknown'

  if stat.type == 'file' and is_executable(stat) then
    return 'FxExecutable'
  elseif stat.type == 'directory' and has_stickybit(stat) then
    return 'FxStickybit'
  end

  return hl_group
end

---@param path string
local function get_link_indicator_and_hl(path)
  local stat = vim.uv.fs_stat(path)
  local link = vim.fn.resolve(path)

  if stat then
    local indicator = get_file_indicator(stat)
    local hl_group = get_file_hl_group(stat)
    return 'FxLink',
      {
        { type_indicator.link },
        { ' -> ' },
        { link, hl_group },
        { indicator, hl_group },
      }
  else
    return 'FxLinkBroken',
      {
        { type_indicator.link },
        { ' -> ' },
        { link, 'FxLinkBroken' },
      }
  end
end

---@param stat? uv.fs_stat.result
---@param path string
local function stat_ext(stat, path)
  if stat and stat.type == 'link' then
    return get_link_indicator_and_hl(path)
  end

  local indicator = get_file_indicator(stat)
  local hl_group = get_file_hl_group(stat)
  return hl_group, { { indicator, hl_group } }
end

function decors.stat(buf, file, line, opts)
  local path = vim.fs.joinpath(vim.api.nvim_buf_get_name(0), file)
  ---@diagnostic disable-next-line: param-type-mismatch
  local stat = vim.uv.fs_lstat(path)

  local hl_group, virt_text = stat_ext(stat, path)
  if opts.indicator then
    vim.api.nvim_buf_set_extmark(buf, ns, line, #file, {
      end_col = #file - 1,
      virt_text = virt_text,
      virt_text_pos = 'inline',
    })
  end
  if opts.highlight then
    vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
      end_col = #file,
      hl_group = hl_group,
      hl_mode = 'combine',
    })
  end
end

---@param file string
local function sanitize(file)
  return vim.trim(file)
end

---@param buf? integer
---@param first? integer
---@param last? integer
local function decorate(buf, first, last)
  buf = resolve_buf(buf)
  local min = 0
  local max = vim.api.nvim_buf_line_count(buf)
  first = first and clamp(first, min, max) or min
  last = last and clamp(last, min, max) or max
  vim.api.nvim_buf_clear_namespace(buf, ns, first, last)
  vim
    .iter(vim.api.nvim_buf_get_lines(buf, first, last, true))
    :map(sanitize)
    :enumerate()
    :each(function(line, file)
      -- NOTE: cannot use Iter:filter() due to loss of index information
      if file and file ~= '' then
        decors.stat(buf, file, first + line - 1, { highlight = true, indicator = false })
      end
    end)
end

---@param _ any
---@param buf integer
---@param _ any
---@param first integer
---@param last_old integer
---@param last_new integer
local function on_lines(_, buf, _, first, last_old, last_new)
  if not bufs[buf] then
    return true
  end
  local last = math.max(last_old, last_new)
  decorate(buf, first, last)
end

---@param _ any
---@param buf integer
local function on_reload(_, buf)
  if not bufs[buf] then
    return true
  end
end

---@param _ any
---@param buf integer
local function on_detach(_, buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  bufs[buf] = false
end

---@param buf? integer
function M.attach(buf)
  buf = resolve_buf(buf)
  if bufs[buf] then
    return
  end
  bufs[buf] = vim.api.nvim_buf_attach(buf, false, {
    on_lines = on_lines,
    on_reload = on_reload,
    on_detach = on_detach,
  })
end

---@param buf? integer
function M.render(buf)
  buf = resolve_buf(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  vim.api.nvim_buf_set_name(buf, path)
  local files = vim
    .iter(vim.fs.dir(path))
    :map(function(name)
      return name
    end)
    :totable()
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, #files == 0 and { '..' } or files)
  vim.bo.modified = false
end

return M
