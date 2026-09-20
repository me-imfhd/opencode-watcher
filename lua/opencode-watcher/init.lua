local config = require("opencode-watcher.config")
local watcher = require("opencode-watcher.watcher")
local ui = require("opencode-watcher.ui")

local M = {}

function M.setup(opts)
	config.setup(opts or {})
	-- create commands
	vim.api.nvim_create_user_command("OpencodeWatcherStart", function()
		watcher.start()
	end, { desc = "Start opencode watcher" })
	vim.api.nvim_create_user_command("OpencodeWatcherStop", function()
		watcher.stop()
	end, { desc = "Stop opencode watcher" })
	vim.api.nvim_create_user_command("OpencodeWatcherRestart", function()
		watcher.restart()
	end, { desc = "Restart opencode watcher" })
	vim.api.nvim_create_user_command("OpencodeWatcherToggle", function()
		watcher.toggle()
	end, { desc = "Toggle opencode watcher" })
	vim.api.nvim_create_user_command("OpencodeWatcherClear", function()
		ui.clear()
	end, { desc = "Clear opencode watcher" })

	-- auto start if dir exists
	-- delay to let nvim fully start
	vim.defer_fn(function()
		-- only auto-start if opencode log exists
		local log = vim.fn.expand("$HOME/.local/share/opencode/log/opencode.log")
		if vim.fn.filereadable(log) == 1 then
			watcher.start()
		end
	end, 500)
end

-- expose for manual
M.start = watcher.start
M.stop = watcher.stop
M.restart = watcher.restart
M.toggle = watcher.toggle
M.ui = ui

return M
