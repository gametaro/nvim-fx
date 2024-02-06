local M = {}
--- @type table<string, fun(buf: integer, file: string, line: integer)>
M.decors = {}

local ns = vim.api.nvim_create_namespace('fx')
local bufs = {} ---@type table<integer, boolean>
local path_type = {} ---@type table<string, string>

---@param path string
---@return string[]
local function list(path)
  return vim
    .iter(vim.fs.dir(path))
    :map(function(name, type)
      local fullname = vim.fs.joinpath(path, name)
      path_type[fullname] = type
      return fullname
    end)
    :totable()
end

function M.decors.conceal(buf, file, line)
  ---@type vim.api.keyset.set_extmark
  local opts = { hl_mode = 'combine', conceal = '' }

  local path = vim.api.nvim_buf_get_name(buf)
  local joined = vim.fs.joinpath(path, '/')
  local _, end_col = file:find(joined, 1, true)
  opts.end_col = end_col

  vim.api.nvim_buf_set_extmark(buf, ns, line, 0, opts)
end

function M.decors.highlight(buf, file, line)
  ---@type vim.api.keyset.set_extmark
  local opts = { end_col = #file, hl_mode = 'combine' }

  local type = path_type[file]
  local type_hlgroup = {
    block = 'FxBlock',
    char = 'FxChar',
    directory = 'FxDirectory',
    fifo = 'FxFifo',
    link = 'FxLink',
    socket = 'FxSocket',
    unknown = 'FxUnknown',
  }
  opts.hl_group = type_hlgroup[type]

  vim.api.nvim_buf_set_extmark(buf, ns, line, 0, opts)
end

function M.decors.indicator(buf, file, line)
  ---@type vim.api.keyset.set_extmark
  local opts = { end_col = #file - 1, hl_mode = 'combine', virt_text_pos = 'inline' }

  local type_virttext = {
    directory = { { '/' } },
    fifo = { { '|' } },
    socket = { { '=' } },
    -- link = { { '@' } },
    -- door = { { '>' } },
  }

  local stat = vim.uv.fs_lstat(file)
  if stat then
    local type = stat.type
    opts.virt_text = type_virttext[type]
    if type == 'file' then
      if require('bit').band(stat.mode, tonumber('111', 8)) ~= 0 then opts.virt_text = { { '*' } } end
    elseif type == 'link' then
      local link = vim.uv.fs_readlink(file)
      opts.virt_text = { { link and string.format(' -> %s', link) or '', link and 'Comment' or 'ErrorMsg' } }
    end

    vim.api.nvim_buf_set_extmark(buf, ns, line, #file, opts)
  end
end

---@param files string[]
---@param f? fun(file: string): string[]
---@return string[]
function M.filter(files, f)
  if type(f) == 'function' then
    return vim.iter(files):filter(f):totable()
  else
    return files
  end
end

---@param files string[]
---@param f? fun(file: string): string[]
---@return string[]
function M.sort(files, f)
  if type(f) == 'function' then
    local sorted = vim.deepcopy(files)
    table.sort(sorted, f)
    return sorted
  else
    return files
  end
end

---@param buf integer?
function M.ensure(buf)
  if buf == nil or buf == 0 then buf = vim.api.nvim_get_current_buf() end
  return vim.bo[buf].buftype == ''
    and vim.bo[buf].modifiable
    and vim.fn.isdirectory(vim.api.nvim_buf_get_name(buf)) == 1
end

---@param buf? integer
function M.render(buf)
  if not M.ensure(buf) then return end
  local path = vim.api.nvim_buf_get_name(buf)
  local files = list(path)
  files = M.filter(files)
  files = M.sort(files)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, #files == 0 and { '..' } or files)
  vim.bo.modified = false
  vim.bo.filetype = 'fx'
end

---@param buf integer
---@param line integer
function M.on_change(buf, line)
  local file = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1]
  vim.iter(M.decors):each(function(_, decor) decor(buf, file, line) end)
end

---@param buf? integer
function M.attach(buf)
  if not M.ensure(buf) or bufs[buf] then return end
  bufs[buf] = vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, _buf, _, first, last_old, last_new)
      local last = math.max(last_old, last_new)
      for line = first, last - 1 do
        M.on_change(_buf, line)
      end
    end,
    on_reload = function(_, _buf)
      vim.api.nvim_buf_clear_namespace(_buf, ns, 0, -1)
      M.render(_buf)
    end,
    on_detach = function(_, _buf)
      vim.api.nvim_buf_clear_namespace(_buf, ns, 0, -1)
      bufs[_buf] = false
      path_type = {}
    end,
  })
end

return M
