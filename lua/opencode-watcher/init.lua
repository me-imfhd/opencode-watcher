local config = require("opencode-watcher.config")
local watcher = require("opencode-watcher.watcher")
local ui = require("opencode-watcher.ui")

local M = {}

function M.setup(opts)
	config.setup(opts or {})
	local prompt = require("opencode-watcher.prompt")
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

	-- prompt commands (vsplit only)
	vim.api.nvim_create_user_command("OpencodePrompt", function(cmd_opts)
		local arg = cmd_opts.args
		-- vsplit only per spec; float arg is legacy and maps to vsplit
		if arg == "vsplit" or arg == "split" or arg == "float" then
			prompt.open({ win = "vsplit" })
		else
			prompt.open()
		end
	end, { desc = "Open opencode prompt (vsplit)", nargs = "?", complete = function()
		return { "vsplit" }
	end })
	vim.api.nvim_create_user_command("OpencodePromptToggle", function()
		prompt.toggle()
	end, { desc = "Toggle opencode prompt" })
	vim.api.nvim_create_user_command("OpencodePromptClose", function()
		prompt.close()
	end, { desc = "Close opencode prompt" })
	vim.api.nvim_create_user_command("OpencodePromptClear", function()
		local b = prompt.get_buf()
		if b then
			vim.api.nvim_buf_set_lines(b, 0, -1, false, {})
			vim.api.nvim_buf_set_option(b, "modified", false)
		end
	end, { desc = "Clear opencode prompt" })
	vim.api.nvim_create_user_command("OpencodePromptSend", function()
		prompt.submit()
	end, { desc = "Send opencode prompt" })

	-- keymaps for prompt: Ctrl-. to open / yank
	local prompt_cfg = config.options.prompt or {}
	if prompt_cfg.enabled ~= false and prompt_cfg.key and prompt_cfg.key ~= "" then
		local key = prompt_cfg.key
		-- normal mode: open prompt (no yank)
		vim.keymap.set("n", key, function()
			prompt.open_or_yank(false)
		end, { desc = "Opencode prompt: open", silent = true })
		-- visual mode: yank selection into prompt
		vim.keymap.set("x", key, function()
			-- visual mode mapping needs to capture selection before leaving visual
			-- Use schedule to ensure marks '< '> are set after leaving visual mode
			-- but we also try immediate getregion via v and .
			-- We handle both via prompt.open_or_yank(true) which checks v/. first
			prompt.open_or_yank(true)
		end, { desc = "Opencode prompt: yank selection", silent = true })
	end

	-- auto start if dir exists
	-- delay to let nvim fully start
	vim.defer_fn(function()
		-- only auto-start if opencode log exists
		local log = vim.fn.expand("$HOME/.local/share/opencode/log/opencode.log")
		if vim.fn.filereadable(log) == 1 then
			watcher.start()
		end
	end, 500)

	-- init prompt module
	prompt.setup()
end

-- expose for manual
M.start = watcher.start
M.stop = watcher.stop
M.restart = watcher.restart
M.toggle = watcher.toggle
M.ui = ui
M.prompt = require("opencode-watcher.prompt")

return M
