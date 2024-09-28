vim.opt.rtp:prepend('.')

vim.g.loaded_netrwPlugin = 1

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('fx_mappings', {}),
  pattern = 'fx',
  callback = function(a)
    vim.bo.bufhidden = 'unload'

    local dir = vim.api.nvim_buf_get_name(a.buf)
    local buf = a.buf --- @type integer

    vim.keymap.set('n', '<cr>', function()
      vim.cmd.edit(vim.fs.joinpath(dir, vim.api.nvim_get_current_line()))
    end, { buffer = buf })
    vim.keymap.set('n', '<2-LeftMouse>', function()
      vim.cmd.edit(vim.fs.joinpath(dir, vim.api.nvim_get_current_line()))
    end, { buffer = buf })
    vim.keymap.set('n', '-', '<cmd>edit %:h<cr>', { buffer = buf })
    vim.keymap.set(
      'n',
      '<c-l>',
      '<cmd>nohlsearch<bar>edit!<bar>normal! <C-l><cr>',
      { buffer = buf }
    )
    vim.keymap.set('n', 'D', function()
      local file = vim.api.nvim_get_current_line()
      vim.ui.select({ 'Yes', 'No' }, {
        prompt = string.format('Delete "%s"?: ', file),
      }, function(choice)
        if choice and choice == 'Yes' then
          vim.fn.delete(vim.fs.joinpath(dir, file), 'rf')
          vim.cmd.edit()
        end
      end)
    end)
    vim.keymap.set('n', 'R', function()
      local file = vim.api.nvim_get_current_line()
      vim.ui.input({
        completion = 'file',
        default = file,
        prompt = string.format('Rename "%s" to: ', file),
      }, function(input)
        if input and input ~= '' then
          vim.fn.rename(vim.fs.joinpath(dir, file), vim.fs.joinpath(dir, input))
          vim.cmd.edit()
        end
      end)
    end)
  end,
})
