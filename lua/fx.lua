local M = {
  ns = vim.api.nvim_create_namespace('fx'),
  decors = {}, ---@type table<string, fun(buf: integer, file: string, line: integer)>
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

---@param buf integer?
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

---@param stat uv.fs_stat.result?
---@param path string
local function stat_ext(stat, path)
  if not stat then
    return 'FxUnknown', { { '?', 'FxUnknown' } }
  end

  local hl_group = type_hlgroup[stat.type] or 'FxUnknown'
  local virt_text = { { type_indicator[stat.type] or '?' } }

  if stat.type == 'file' and is_executable(stat) then
    hl_group = 'FxExecutable'
    virt_text = { { '*' } }
  elseif stat.type == 'directory' and has_stickybit(stat) then
    hl_group = 'FxStickybit'
  elseif stat.type == 'link' then
    local link_stat = vim.uv.fs_stat(path)
    local link = vim.fn.resolve(path)
    if link_stat then
      local link_hl_group, link_virt_text = stat_ext(link_stat, path)
      virt_text = {
        { type_indicator[stat.type] },
        { ' -> ' },
        { link, link_hl_group },
        unpack(link_virt_text),
      }
    else
      hl_group = 'FxLinkBroken'
      virt_text = {
        { type_indicator[stat.type] },
        { ' -> ' },
        { link, 'FxLinkBroken' },
      }
    end
  end

  return hl_group, virt_text
end

function M.decors.stat(buf, file, line)
  local path = vim.fs.joinpath(vim.api.nvim_buf_get_name(0), file)
  ---@diagnostic disable-next-line: param-type-mismatch
  local stat = vim.uv.fs_lstat(path)

  local hl_group, virt_text = stat_ext(stat, path)
  vim.api.nvim_buf_set_extmark(buf, M.ns, line, #file, {
    end_col = #file - 1,
    virt_text = virt_text,
    virt_text_pos = 'inline',
  })
  vim.api.nvim_buf_set_extmark(buf, M.ns, line, 0, {
    end_col = #file,
    hl_group = hl_group,
    hl_mode = 'combine',
  })
end

---@param file string
---@return string
local function sanitize(file)
  return vim.trim(file)
end

---@param buf integer?
---@param first integer?
---@param last integer?
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
      vim.iter(M.decors):each(function(_, decor)
        -- NOTE: cannot use Iter:filter() due to loss of index information
        if file and file ~= '' then
          decor(buf, file, first + line - 1)
        end
      end)
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

---@param buf integer?
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

  vim.iter(highlights):each(function(dst, src)
    local opts = vim.api.nvim_get_hl(0, { name = src })
    opts.bold = dst ~= 'FxFile'
    opts.default = true
    ---@diagnostic disable-next-line: param-type-mismatch
    vim.api.nvim_set_hl(0, dst, opts)
  end)
end

---@param buf integer?
function M.render(buf)
  buf = resolve_buf(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  vim.api.nvim_buf_set_name(buf, path)
  local files = vim.iter.map(function(name)
    return name
  end, vim.fs.dir(path))
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
