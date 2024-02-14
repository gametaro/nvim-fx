-- FIXME: don't work
-- vim.opt_local.isfname:append('32')

vim.bo.bufhidden = 'hide'
vim.bo.buflisted = false
vim.bo.buftype = 'nofile'
vim.bo.swapfile = false
local path = vim.fn.expand('%:p')
if path ~= '' then vim.bo.path = path end

vim.wo[0][0].concealcursor = 'nc'
vim.wo[0][0].conceallevel = 2
vim.wo[0][0].cursorline = true
vim.wo[0][0].wrap = false

vim.keymap.set('n', '<CR>', 'gf', { buffer = true })
vim.keymap.set('n', '<C-l>', '<Cmd>nohlsearch<Bar>edit!<Bar>normal! <C-l><CR>', { buffer = true })
vim.keymap.set('n', '-', '<cmd>edit %:p:h:h<cr>', { buffer = true })
