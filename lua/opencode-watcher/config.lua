local M = {}

M.defaults = {
	-- shared directory: basename like "opencode-watcher.nvim" or full path; nil = auto (git root else cwd)
	dir = nil,
	-- position: "top-right" | "bottom-right"
	position = "top-right",
	width = 42,
	height = 12,
	border = "rounded",
	-- tail script path (relative to plugin root or absolute)
	tail_script = nil, -- auto-detected
	-- extra args for tail script
	exclude = "PERM:bash,read,edit", -- sensible default to reduce noise, set to nil to show all
	lines = 0, -- 0 = only live, 50 = show history
	-- auto refresh visible buffers when opencode formats a file
	auto_refresh = true,
	-- how long to keep window after loop exit (ms)
	hide_delay = 2500,
	-- max lines kept in floating window
	max_lines = 100,
	-- icons for human friendly view
	icons = {
		BOOT = "󰚩",
		FILE = "󰈙",
		PERM = "󰌾",
		LLM = "󰧑",
		LOOP = "󰑃",
		SESS = "󰆚",
		SYNC = "󰓦",
		WATCH = "󰈙",
		MSG = "󰍡",
		CFG = "",
		EVT = "󰇧",
		CLEAN = "󰃢",
		ERR = "󰅚",
		DEFAULT = "󰧑",
	},
	-- highlights alongside icons (put that alongside config)
	highlights = {
		BOOT = "Special", -- purple
		FILE = "Directory", -- blue
		PERM = "WarningMsg", -- yellow for perm edit (needs enable)
		PERM_EDIT = "WarningMsg", -- yellow for edit specifically
		PERM_ASK = "WarningMsg",
		LLM = "Special", -- magenta
		LOOP = "Statement", -- yellow/brown
		SESS = "Identifier", -- cyan
		SYNC = "Comment", -- grey
		WATCH = "Directory",
		MSG = "Normal",
		CFG = "Comment",
		EVT = "Comment",
		CLEAN = "Comment",
		ERR = "ErrorMsg", -- red
		ERR_ABORT = "ErrorMsg",
		DEFAULT = "Normal", -- white
	},
}

M.options = {}

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
	-- resolve tail script
	if not M.options.tail_script then
		-- try plugin root + opencode-log-tail.sh
		local cur = debug.getinfo(1, "S").source:sub(2)
		local plugin_root = vim.fn.fnamemodify(cur, ":h:h:h")
		local candidate = plugin_root .. "/opencode-log-tail.sh"
		if vim.fn.filereadable(candidate) == 1 then
			M.options.tail_script = candidate
		else
			-- fallback to $HOME/dev/opencode-watcher.nvim
			local home = vim.fn.expand("$HOME/dev/opencode-watcher.nvim/opencode-log-tail.sh")
			if vim.fn.filereadable(home) == 1 then
				M.options.tail_script = home
			else
				M.options.tail_script = "opencode-log-tail.sh"
			end
		end
	end
	return M.options
end

return M
