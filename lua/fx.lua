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

---@param path string
---@param stat? uv.fs_stat.result
local function stat_ext(path, stat)
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

  local hl_group, virt_text = stat_ext(path, stat)
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

function decors.icon(buf, file, line)
  local path = vim.fs.joinpath(vim.api.nvim_buf_get_name(0), file)
  local ok, devicons = pcall(require, 'nvim-web-devicons')
  if ok then
    local text, hl_group = devicons.get_icon(path)
    if not text then
      text = ''
    end
    if not hl_group then
      hl_group = 'Directory'
    end
    vim.api.nvim_buf_set_extmark(buf, ns, line, #file, {
      sign_text = text,
      sign_hl_group = hl_group,
    })
  end
end

---@param buf integer
---@param first? integer
---@param last? integer
local function decorate(buf, first, last)
  local min = 0
  local max = vim.api.nvim_buf_line_count(buf)
  first = first and clamp(first, min, max) or min
  last = last and clamp(last, min, max) or max
  vim.api.nvim_buf_clear_namespace(buf, ns, first, last)
  vim
    .iter(vim.api.nvim_buf_get_lines(buf, first, last, true))
    :map(vim.trim)
    :enumerate()
    :each(function(line, file)
      -- NOTE: cannot use Iter:filter() due to loss of index information
      if file and file ~= '' then
        decors.stat(buf, file, first + line - 1, { highlight = true, indicator = false })
        decors.icon(buf, file, first + line - 1)
      end
    end)
end

---@param buf integer
function M.attach(buf)
  vim.validate('buf', buf, 'number')
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  if bufs[buf] then
    return
  end
  bufs[buf] = vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _buf, _, first, last_old, last_new)
      if not bufs[_buf] then
        return true
      end
      local last = math.max(last_old, last_new)
      decorate(_buf, first, last)
    end,
    on_reload = function(_, _buf)
      if not bufs[_buf] then
        return true
      end
    end,
    on_detach = function(_, _buf)
      vim.api.nvim_buf_clear_namespace(_buf, ns, 0, -1)
      bufs[_buf] = false
    end,
  })
end

---@param buf integer
function M.render(buf)
  vim.validate('buf', buf, 'number')
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
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
