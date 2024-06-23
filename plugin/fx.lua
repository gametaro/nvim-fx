local group = vim.api.nvim_create_augroup('fx', {})

local function set_hl()
  local highlights = {
    FxFile = '',
    FxBlock = 'CurSearch',
    FxChar = 'WarningMsg',
    FxDirectory = 'Directory',
    FxFifo = 'Search',
    FxLink = 'Underlined',
    FxLinkBroken = 'Error',
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
      require('fx').render(buf)
    end
  end,
})

vim.api.nvim_create_autocmd('ColorScheme', {
  group = group,
  callback = set_hl,
})

set_hl()
