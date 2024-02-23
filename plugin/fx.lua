vim.api.nvim_create_autocmd('BufWinEnter', {
  group = vim.api.nvim_create_augroup('fx', {}),
  callback = function(a)
    --- @type integer
    local buf = a.buf
    if
      vim.api.nvim_buf_is_valid(buf)
      and vim.bo[buf].modifiable
      and vim.fn.isdirectory(vim.api.nvim_buf_get_name(buf)) == 1
    then
      local ok, fx = pcall(require, 'fx')
      if ok then
        fx.attach(buf)
      end
    end
  end,
})

local highlights = {
  FxFile = '',
  FxBlock = 'WarningMsg',
  FxChar = 'WarningMsg',
  FxDirectory = 'Directory',
  FxFifo = 'DiffChange',
  FxLink = 'Underlined',
  FxLinkBroken = 'SpellBad',
  FxSocket = 'Identifier',
  FxUnknown = 'NonText',

  FxExecutable = 'String',
  FxStickybit = 'Search',
}

vim.iter(highlights):each(function(dst, src)
  local opts = vim.api.nvim_get_hl(0, { name = src })
  if
    vim.iter({ 'FxChar', 'FxDirectory', 'FxExecutable' }):any(function(name)
      return name == dst
    end)
  then
    opts.bold = true
  end
  vim.api.nvim_set_hl(0, dst, opts)
end)
