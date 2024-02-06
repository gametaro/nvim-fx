local fx = require('fx')

local group = vim.api.nvim_create_augroup('fx', {})

vim.api.nvim_create_autocmd('BufWinEnter', {
  group = group,
  callback = function(a)
    --- @type integer?
    local buf = a.buf
    fx.attach(buf)
    fx.render(buf)
  end,
})

local highlights = {
  -- FxFile = '',
  FxBlock = 'WarningMsg',
  FxChar = 'WarningMsg',
  FxDirectory = 'Directory',
  -- FIXME: more better colour
  FxFifo = 'Search',
  FxLink = 'Identifier',
  FxSocket = 'String',
  FxUnknown = 'NonText',
}

vim.iter(highlights):each(function(dst, src)
  local opts = vim.api.nvim_get_hl(0, { name = src })
  opts.bold = true
  vim.api.nvim_set_hl(0, dst, opts)
end)
