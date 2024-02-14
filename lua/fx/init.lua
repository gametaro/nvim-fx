local M = {}

M.ns = vim.api.nvim_create_namespace('fx')

M.decors = {} ---@type table<string, fun(buf: integer, file: string, line: integer)>
M.bufs = {} ---@type table<integer, boolean>

function M.decors.stat(buf, file, line)
  ---@type vim.api.keyset.set_extmark
  local opts_highlight = { end_col = #file, hl_mode = 'combine' }
  ---@type vim.api.keyset.set_extmark
  local opts_indicator = { end_col = #file - 1, virt_text_pos = 'inline' }

  local type_hlgroup = {
    block = 'FxBlock',
    char = 'FxChar',
    directory = 'FxDirectory',
    fifo = 'FxFifo',
    link = 'FxLink',
    socket = 'FxSocket',
    unknown = 'FxUnknown',
  }

  local type_virttext = {
    directory = { { '/' } },
    fifo = { { '|' } },
    socket = { { '=' } },
    -- link = { { '@' } },
    -- door = { { '>' } },
  }

  local path = vim.fs.joinpath(vim.bo.path, file)
  local stat = vim.uv.fs_lstat(path)
  if stat then
    local type = stat.type
    opts_highlight.hl_group = type_hlgroup[type]
    opts_indicator.virt_text = type_virttext[type]

    if type == 'file' then
      if require('bit').band(stat.mode, tonumber('111', 8)) ~= 0 then
        opts_indicator.virt_text = { { '*' } }
        opts_highlight.hl_group = 'FxExecutable'
      end
    elseif type == 'directory' then
      if require('bit').band(stat.mode, tonumber('1000', 8)) ~= 0 then
        opts_highlight.hl_group = 'FxStickybit'
      end
    elseif type == 'link' then
      local link = vim.uv.fs_readlink(path)
      local link_hlgroup
      if link then
        local link_stat = vim.uv.fs_lstat(link)
        if link_stat then link_hlgroup = type_hlgroup[link_stat.type] end
      end
      opts_highlight.virt_text = {
        { link and string.format('-> %s', link) or '', link and link_hlgroup or 'FxLinkBroken' },
      }
    end

    vim.api.nvim_buf_set_extmark(buf, M.ns, line, #file, opts_indicator)
    vim.api.nvim_buf_set_extmark(buf, M.ns, line, 0, opts_highlight)
  end
end

---@param buf integer?
function M.resolve_buf(buf)
  return (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
end

---@param buf? integer
function M.render(buf)
  buf = M.resolve_buf(buf)
  local files = vim.iter.map(
    function(name, _) return name end,
    vim.fs.dir(vim.api.nvim_buf_get_name(buf))
  )
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, #files == 0 and { '..' } or files)
  vim.bo.modified = false
end

---@param buf? integer
---@param from integer
---@param to integer
function M.decorate(buf, from, to)
  buf = M.resolve_buf(buf)
  local min = 0
  local max = vim.api.nvim_buf_line_count(buf)
  from = M.clamp(from, min, max)
  to = M.clamp(to, min, max)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, from, to)
  vim
    .iter(vim.api.nvim_buf_get_lines(buf, from, to, true))
    :filter(function(file) return file and file ~= '' end)
    :enumerate()
    :each(function(line, file)
      vim.iter(M.decors):each(function(_, decor) decor(buf, file, from + line - 1) end)
    end)
end

function M.on_lines(_, buf, _, first, last_old, last_new)
  if not M.bufs[buf] then return true end
  local last = math.max(last_old, last_new)
  M.decorate(buf, first, last)
end

function M.on_reload(_, buf)
  if not M.bufs[buf] then return true end
end

function M.on_detach(_, buf)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  M.bufs[buf] = false
end

---@param x integer
---@param min integer?
---@param max integer?
function M.clamp(x, min, max) return math.max(math.min(x, max), min or 0) end

---@param buf? integer
function M.attach(buf)
  buf = M.resolve_buf(buf)
  if M.bufs[buf] then return end
  M.bufs[buf] = vim.api.nvim_buf_attach(buf, false, {
    on_lines = M.on_lines,
    on_reload = M.on_reload,
    on_detach = M.on_detach,
  })
  vim.bo[buf].filetype = 'fx'
end

return M
