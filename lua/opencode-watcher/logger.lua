local M = {}

local log_path = nil
local function get_path()
	if log_path then
		return log_path
	end
	-- prefer stdpath log, use debug log name
	local ok, std = pcall(vim.fn.stdpath, "log")
	if ok and std and std ~= "" and vim.fn.isdirectory(std) == 1 then
		log_path = std .. "/opencode-watcher-debug.log"
	else
		-- fallback to state
		local ok2, st = pcall(vim.fn.stdpath, "state")
		if ok2 and st and st ~= "" then
			log_path = st .. "/opencode-watcher-debug.log"
		else
			log_path = vim.fn.expand("~/.local/share/opencode-watcher-debug.log")
		end
	end
	return log_path
end

local function ensure_dir()
	local p = get_path()
	local dir = vim.fn.fnamemodify(p, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	return p
end

local level_names = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3 }
local current_level = level_names.INFO

function M.setup(opts)
	opts = opts or {}
	local lvl = opts.level or opts.log_level or "INFO"
	lvl = tostring(lvl):upper()
	if level_names[lvl] then
		current_level = level_names[lvl]
	end
	if opts.path then
		log_path = vim.fn.expand(opts.path)
	end
	ensure_dir()
end

local function should_log(lvl)
	-- respect global debug flag: when debug=false, still log INFO/WARN/ERROR, only suppress DEBUG
	local ok, cfg = pcall(require, "opencode-watcher.config")
	if ok and cfg and cfg.options and cfg.options.debug == false then
		if lvl == "DEBUG" then
			return false
		end
		-- allow INFO/WARN/ERROR even when debug=false for critical events (like submit)
		return level_names[lvl] >= level_names.INFO
	end
	return level_names[lvl] >= current_level
end

function M.log(level, msg)
	level = tostring(level):upper()
	if not should_log(level) then
		return
	end
	local path = ensure_dir()
	local ts = os.date("%Y-%m-%d %H:%M:%S")
	local line = string.format("[%s] %-5s %s", ts, level, tostring(msg))
	-- also split multiline
	for _, l in ipairs(vim.split(line, "\n", { plain = true })) do
		-- skip empty? keep
		local f = io.open(path, "a")
		if f then
			f:write(l .. "\n")
			f:close()
		end
	end
end

function M.debug(msg) M.log("DEBUG", msg) end
function M.info(msg) M.log("INFO", msg) end
function M.warn(msg) M.log("WARN", msg) end
function M.error(msg) M.log("ERROR", msg) end

function M.get_path()
	return get_path()
end

function M.show()
	local path = get_path()
	if vim.fn.filereadable(path) == 1 then
		vim.cmd("vsplit " .. vim.fn.fnameescape(path))
	else
		-- create empty and open (no notify, only error if fails is handled elsewhere)
		ensure_dir()
		local f = io.open(path, "a")
		if f then f:close() end
		vim.cmd("vsplit " .. vim.fn.fnameescape(path))
	end
end

function M.clear()
	local path = get_path()
	local f = io.open(path, "w")
	if f then
		f:write("")
		f:close()
	else
		vim.notify("failed to clear log: " .. path, vim.log.levels.ERROR)
	end
end

function M.tail(n)
	n = n or 50
	local path = get_path()
	if vim.fn.filereadable(path) == 0 then
		return {}
	end
	local lines = vim.fn.readfile(path)
	if #lines > n then
		local out = {}
		for i = #lines - n + 1, #lines do table.insert(out, lines[i]) end
		return out
	end
	return lines
end

return M
