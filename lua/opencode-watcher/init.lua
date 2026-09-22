local config = require("opencode-watcher.config")
local watcher = require("opencode-watcher.watcher")
local ui = require("opencode-watcher.ui")

local M = {}

function M.setup(opts)
	config.setup(opts or {})
	local logger = require("opencode-watcher.logger")
	logger.setup(config.options.logger or {})
	local prompt = require("opencode-watcher.prompt")
	-- minimal commands: OpencodePrompt, OpencodeWatcherStart/Stop, OpencodeWatcherLogs (pretty)
	vim.api.nvim_create_user_command("OpencodeWatcherStart", function()
		watcher.start()
	end, { desc = "Start opencode watcher" })
	vim.api.nvim_create_user_command("OpencodeWatcherStop", function()
		watcher.stop()
	end, { desc = "Stop opencode watcher" })
	vim.api.nvim_create_user_command("OpencodePrompt", function(cmd_opts)
		local arg = cmd_opts.args
		if arg == "vsplit" or arg == "split" or arg == "float" then
			prompt.open({ win = "vsplit" })
		else
			prompt.open()
		end
	end, { desc = "Open opencode prompt (vsplit)", nargs = "?", complete = function()
		return { "vsplit" }
	end })
	-- OpencodeWatcherLogs now shows pretty opencode logs (filtered via bash script), not debug logs
	-- For detailed debugging, tail these files directly:
	--   plugin debug log (when debug=true):  ~/.local/state/nvim/opencode-watcher-debug.log  (or stdpath("log")/opencode-watcher-debug.log)
	--   opencode server log:                 ~/.local/share/opencode/log/opencode.log
	--   pretty log on-demand:                opencode-log-tail.sh --dir <project> --lines 50  (or :OpencodeWatcherLogs)
	--   rest (sessions, etc):                use bash script or exposed functions (watcher.resolve_dir(), server.is_running(), etc.) – no separate storing needed
	vim.api.nvim_create_user_command("OpencodeWatcherLogs", function(opts)
		local dir = require("opencode-watcher.watcher").resolve_dir()
		local lines = opts.args ~= "" and opts.args or "50"
		local script = require("opencode-watcher.config").options.tail_script
		vim.cmd("vsplit | terminal " .. vim.fn.shellescape(script) .. " --dir " .. vim.fn.shellescape(dir) .. " --lines " .. vim.fn.shellescape(lines))
	end, { desc = "Open opencode pretty logs (filtered tail)", nargs = "?" })
	vim.api.nvim_create_user_command("OpencodeWatcherDebugLogs", function()
		require("opencode-watcher.logger").show()
	end, { desc = "Open plugin debug logs (opencode-watcher-debug.log, only when debug=true)" })
	vim.api.nvim_create_user_command("OpencodeRefresh", function()
		local dir = require("opencode-watcher.watcher").resolve_dir()
		-- abort any looping agent first, then refresh session and clear logs
		pcall(function() require("opencode-watcher.server").abort(dir) end)
		require("opencode-watcher.server").clear_session(dir)
		require("opencode-watcher.ui").clear()
		local prompt = require("opencode-watcher.prompt")
		local b = prompt.get_buf()
		if b and vim.api.nvim_buf_is_valid(b) then
			vim.api.nvim_buf_set_lines(b, 0, -1, false, {})
			vim.api.nvim_buf_set_option(b, "modified", false)
		end
	end, { desc = "Refresh inline edits - next prompt will use new session and clear watcher logs" })
	vim.api.nvim_create_user_command("OpencodeAbort", function()
		local dir = require("opencode-watcher.watcher").resolve_dir()
		local ok = require("opencode-watcher.server").abort(dir)
		if ok then
			require("opencode-watcher.ui").clear()
		else
			vim.notify("opencode watcher: no looping agent to abort for " .. dir, vim.log.levels.ERROR)
		end
	end, { desc = "Abort any looping agent in project directory (also refreshes to new session)" })
	vim.api.nvim_create_user_command("OpencodeSession", function()
		local dir = require("opencode-watcher.watcher").resolve_dir()
		local sid = require("opencode-watcher.server").get_session(dir)
		if sid and sid ~= "" then
			local cmd = string.format('opencode -s "%s"', sid)
			vim.fn.setreg("+", cmd)
			vim.fn.setreg('"', cmd)
			-- print without notify (only error notify kept per minimal notify policy, but this is useful info)
			-- use echo for copyable output
			vim.api.nvim_echo({ { cmd, "String" } }, true, {})
			-- also log to debug file if enabled
			pcall(function() require("opencode-watcher.logger").info("session for " .. dir .. " -> " .. sid) end)
		else
			vim.notify("opencode watcher: no inline session yet for " .. dir .. " (send a prompt first)", vim.log.levels.ERROR)
		end
	end, { desc = "Print opencode -s \"session-id\" for current inline edits session (copy to clipboard)" })
	vim.api.nvim_create_user_command("OpencodeModel", function(opts)
		local dir = require("opencode-watcher.watcher").resolve_dir()
		require("opencode-watcher.server").pick_model(dir, opts.args)
	end, { desc = "Change model and thinking level for current session only (not global)", nargs = "?" })

	-- keymaps for prompt: Ctrl-. to open / yank
	local prompt_cfg = config.options.prompt or {}
	if prompt_cfg.enabled ~= false and prompt_cfg.key and prompt_cfg.key ~= "" then
		local key = prompt_cfg.key
		vim.keymap.set("n", key, function()
			prompt.open_or_yank(false)
		end, { desc = "Opencode prompt: open", silent = true })
		vim.keymap.set("x", key, function()
			prompt.open_or_yank(true)
		end, { desc = "Opencode prompt: yank selection", silent = true })
	end

	vim.defer_fn(function()
		local log = vim.fn.expand("$HOME/.local/share/opencode/log/opencode.log")
		if vim.fn.filereadable(log) == 1 then
			watcher.start()
		end
	end, 500)

	prompt.setup()
end

M.start = watcher.start
M.stop = watcher.stop
M.restart = watcher.restart
M.toggle = watcher.toggle
M.ui = ui
M.prompt = require("opencode-watcher.prompt")

return M
