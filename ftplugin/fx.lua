-- FIXME: don't work
-- vim.opt_local.isfname:append('32')

vim.bo.bufhidden = 'hide'
vim.bo.buflisted = false
vim.bo.buftype = 'nofile'
vim.bo.swapfile = false

vim.wo[0][0].concealcursor = 'nc'
vim.wo[0][0].conceallevel = 2
vim.wo[0][0].cursorline = true
vim.wo[0][0].wrap = false

vim.keymap.set('n', '<cr>', 'gf', { buffer = true })
vim.keymap.set('n', '<c-l>', function() vim.cmd.edit('%:p:h') end, { buffer = true })
vim.keymap.set('n', '-', '<cmd>edit %:p:h:h<cr>', { buffer = true })
