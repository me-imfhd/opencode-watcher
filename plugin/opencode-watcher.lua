-- auto-load opencode-watcher if setup is called elsewhere, otherwise lazy
if vim.g.loaded_opencode_watcher == 1 then
  return
end
vim.g.loaded_opencode_watcher = 1

-- create an autocmd to refresh on FocusGained (helps after opencode formats)
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  group = vim.api.nvim_create_augroup("OpencodeWatcherRefresh", { clear = true }),
  callback = function()
    -- checktime is already handled by ui.refresh, but also ensure
    vim.cmd("silent! checktime")
  end,
})
