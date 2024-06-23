vim.bo.bufhidden = 'hide'
vim.bo.buflisted = false
vim.bo.buftype = 'nofile'
vim.bo.swapfile = false

vim.wo[0][0].cursorline = true
vim.wo[0][0].wrap = false

require('fx').attach()
