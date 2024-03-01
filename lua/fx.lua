local M = {}

M.ns = vim.api.nvim_create_namespace('fx')

M.decors = {} ---@type table<string, fun(buf: integer, file: string, line: integer)>
M.bufs = {} ---@type table<integer, boolean>

---@param buf integer?
function M.resolve_buf(buf)
  return (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
end

---@param buf? integer
function M.render(buf)
  buf = M.resolve_buf(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  vim.api.nvim_buf_set_name(buf, path)
  local files = vim.iter.map(function(name)
    return name
  end, vim.fs.dir(path))
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, #files == 0 and { '..' } or files)
  vim.bo.modified = false
end

---@param x integer
---@param min integer
---@param max integer
function M.clamp(x, min, max)
  return math.max(math.min(x, max), min)
end

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

local type_virttext = {
  block = { { '' } },
  char = { { '' } },
  directory = { { '/' } },
  fifo = { { '|' } },
  file = { { '' } },
  link = { { '@' } },
  socket = { { '=' } },
  unknown = { { '' } },
}

---@param stat uv.fs_stat.result
local function is_executable(stat)
  return require('bit').band(stat.mode, tonumber('111', 8)) ~= 0
end

---@param stat uv.fs_stat.result
local function has_stickybit(stat)
  return require('bit').band(stat.mode, tonumber('1000', 8)) ~= 0
end

---@param stat uv.fs_stat.result
---@param path string
local function extra_decors(stat, path)
  local hl_group = type_hlgroup[stat.type]
  local virt_text = type_virttext[stat.type]

  if stat.type == 'file' and is_executable(stat) then
    hl_group = 'FxExecutable'
    virt_text = { { '*' } }
  elseif stat.type == 'directory' and has_stickybit(stat) then
    hl_group = 'FxStickybit'
  elseif stat.type == 'link' then
    local _stat = vim.uv.fs_stat(path)
    local link = vim.fn.resolve(path)
    if _stat then
      local link_stat = vim.uv.fs_stat(link)
      if link_stat then
        local link_hl_group, link_virt_text = extra_decors(link_stat, path)
        virt_text = {
          { ' -> ' },
          { link, link_hl_group },
          unpack(link_virt_text),
        }
      end
    else
      hl_group = 'FxLinkBroken'
      virt_text = {
        { ' -> ' },
        { link, 'FxLinkBroken' },
      }
    end
  end

  return hl_group, virt_text
end

function M.decors.stat(buf, file, line)
  ---@type vim.api.keyset.set_extmark
  local opts_highlight = { end_col = #file, hl_mode = 'combine' }
  ---@type vim.api.keyset.set_extmark
  local opts_indicator = { end_col = #file - 1, virt_text_pos = 'inline' }

  local path = vim.fs.joinpath(vim.api.nvim_buf_get_name(0), file)
  ---@diagnostic disable-next-line: param-type-mismatch
  local stat = vim.uv.fs_lstat(path)
  if not stat then
    return
  end

  opts_highlight.hl_group, opts_indicator.virt_text = extra_decors(stat, path)

  vim.api.nvim_buf_set_extmark(buf, M.ns, line, #file, opts_indicator)
  vim.api.nvim_buf_set_extmark(buf, M.ns, line, 0, opts_highlight)
end

---@param file string
---@return string
function M.sanitize(file)
  return vim.trim(file)
end

---@param buf integer?
---@param first integer?
---@param last integer?
function M.decorate(buf, first, last)
  buf = M.resolve_buf(buf)
  local min = 0
  local max = vim.api.nvim_buf_line_count(buf)
  local start = M.clamp(first or min, min, max)
  local end_ = M.clamp(last or max, min, max)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, start, end_)
  vim
    .iter(vim.api.nvim_buf_get_lines(buf, start, end_, true))
    :map(M.sanitize)
    :enumerate()
    :each(function(line, file)
      vim.iter(M.decors):each(function(_, decor)
        -- NOTE: cannot use Iter:filter() due to loss of index information
        if file and file ~= '' then
          decor(buf, file, start + line - 1)
        end
      end)
    end)
end

function M.on_lines(_, buf, _, first, last_old, last_new)
  if not M.bufs[buf] then
    return true
  end
  local last = math.max(last_old, last_new)
  M.decorate(buf, first, last)
end

function M.on_reload(_, buf)
  if not M.bufs[buf] then
    return true
  end
end

function M.on_detach(_, buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  M.bufs[buf] = false
end

---@param buf? integer
function M.attach(buf)
  buf = M.resolve_buf(buf)
  if M.bufs[buf] then
    return
  end
  M.bufs[buf] = vim.api.nvim_buf_attach(buf, false, {
    on_lines = M.on_lines,
    on_reload = M.on_reload,
    on_detach = M.on_detach,
  })
end

function M.setup()
  local group = vim.api.nvim_create_augroup('fx', {})
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'fx',
    callback = function()
      -- FIXME: don't work
      -- vim.opt_local.isfname:append('32')
      vim.bo.bufhidden = 'hide'
      vim.bo.buflisted = false
      vim.bo.buftype = 'nofile'
      vim.bo.swapfile = false
      local name = vim.api.nvim_buf_get_name(0)
      if vim.fn.isdirectory(name) == 1 then
        vim.opt_local.path:prepend(name)
      end

      vim.wo[0][0].concealcursor = 'nc'
      vim.wo[0][0].conceallevel = 2
      vim.wo[0][0].cursorline = true
      vim.wo[0][0].wrap = false

      M.attach()
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufEnter' }, {
    group = group,
    callback = function(a)
      --- @type integer
      local buf = a.buf
      if
        vim.api.nvim_buf_is_valid(buf)
        and vim.bo[buf].modifiable
        and vim.fn.isdirectory(vim.api.nvim_buf_get_name(buf)) == 1
      then
        vim.bo[buf].filetype = 'fx'
        M.render(buf)
      end
    end,
  })

  vim
    .iter({
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
    })
    :each(function(dst, src)
      local opts = vim.api.nvim_get_hl(0, { name = src })
      opts.default = true
      if dst ~= 'FxFile' then
        opts.bold = true
      end
      vim.api.nvim_set_hl(0, dst, opts)
    end)
end

return M
