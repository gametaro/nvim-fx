local M = {
  ns = vim.api.nvim_create_namespace('fx'),
  decors = {}, ---@type table<string, fun(buf: integer, file: string, line: integer, opts?: table)>
  bufs = {}, ---@type table<integer, boolean>
}

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
  local link_stat = vim.uv.fs_stat(path)
  local link = vim.fn.resolve(path)

  if link_stat then
    local link_indicator = get_file_indicator(link_stat)
    local link_hl_group = get_file_hl_group(link_stat)
    return 'FxLink',
      {
        { type_indicator.link },
        { ' -> ' },
        { link, link_hl_group },
        { link_indicator, link_hl_group },
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

function M.decors.stat(buf, file, line, opts)
  local path = vim.fs.joinpath(vim.api.nvim_buf_get_name(0), file)
  ---@diagnostic disable-next-line: param-type-mismatch
  local stat = vim.uv.fs_lstat(path)

  local hl_group, virt_text = stat_ext(stat, path)
  if opts.indicator then
    vim.api.nvim_buf_set_extmark(buf, M.ns, line, #file, {
      end_col = #file - 1,
      virt_text = virt_text,
      virt_text_pos = 'inline',
    })
  end
  if opts.highlight then
    vim.api.nvim_buf_set_extmark(buf, M.ns, line, 0, {
      end_col = #file,
      hl_group = hl_group,
      hl_mode = 'combine',
    })
  end
end

---@param file string
---@return string
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
  vim.api.nvim_buf_clear_namespace(buf, M.ns, first, last)
  vim
    .iter(vim.api.nvim_buf_get_lines(buf, first, last, true))
    :map(sanitize)
    :enumerate()
    :each(function(line, file)
      -- NOTE: cannot use Iter:filter() due to loss of index information
      if file and file ~= '' then
        M.decors.stat(buf, file, first + line - 1, { highlight = true, indicator = false })
      end
    end)
end

local function on_lines(_, buf, _, first, last_old, last_new)
  if not M.bufs[buf] then
    return true
  end
  local last = math.max(last_old, last_new)
  decorate(buf, first, last)
end

local function on_reload(_, buf)
  if not M.bufs[buf] then
    return true
  end
end

local function on_detach(_, buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  M.bufs[buf] = false
end

---@param buf? integer
function M.attach(buf)
  buf = resolve_buf(buf)
  if M.bufs[buf] then
    return
  end
  M.bufs[buf] = vim.api.nvim_buf_attach(buf, false, {
    on_lines = on_lines,
    on_reload = on_reload,
    on_detach = on_detach,
  })
end

local function set_hl()
  local highlights = {
    FxFile = '',
    FxBlock = 'CurSearch',
    FxChar = 'WarningMsg',
    FxDirectory = 'Directory',
    FxFifo = 'Visual',
    FxLink = 'Underlined',
    FxLinkBroken = 'ErrorMsg',
    FxSocket = 'Identifier',
    FxUnknown = 'NonText',
    FxExecutable = 'String',
    FxStickybit = 'DiffAdd',
  }

  ---@param dst string
  ---@param src string
  local function inherit(dst, src)
    local highlight = vim.api.nvim_get_hl(0, { name = src })
    highlight.bold = dst ~= 'FxFile'
    highlight.default = true
    return dst, highlight
  end

  ---@param name string
  ---@param highlight vim.api.keyset.highlight
  local function hi(name, highlight)
    return vim.api.nvim_set_hl(0, name, highlight)
  end

  vim.iter(highlights):map(inherit):each(hi)
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

function M.setup()
  local group = vim.api.nvim_create_augroup('fx', {})
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'fx',
    callback = function()
      vim.bo.bufhidden = 'hide'
      vim.bo.buflisted = false
      vim.bo.buftype = 'nofile'
      vim.bo.swapfile = false

      vim.wo[0][0].cursorline = true
      vim.wo[0][0].wrap = false

      M.attach()
    end,
  })

  vim.api.nvim_create_autocmd('BufEnter', {
    group = group,
    callback = function(a)
      local buf = a.buf ---@type integer
      if
        vim.api.nvim_buf_is_valid(buf)
        and vim.bo[buf].modifiable
        and vim.fn.isdirectory(a.file) == 1
      then
        vim.bo[buf].filetype = 'fx'
        M.render(buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = set_hl,
  })

  set_hl()
end

return M
