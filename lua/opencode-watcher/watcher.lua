local M = {}

local config = require("opencode-watcher.config")
local ui = require("opencode-watcher.ui")

local job_id = nil
local loop_active = false
local loop_exit_pending = false
local idle_hide_timer = nil

local function resolve_dir()
	local opts = config.options
	if opts.dir and opts.dir ~= "" then
		-- if basename only (no /), try to find git root with that basename or use cwd
		if not opts.dir:match("/") then
			local basename = opts.dir
			-- try git root
			local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
			local git_root = handle and handle:read("*l")
			if handle then
				handle:close()
			end
			if git_root and git_root ~= "" then
				local git_base = git_root:match("([^/]+)$")
				if git_base == basename then
					return git_root
				end
			end
			-- try find under HOME/dev
			local found = vim.fn.systemlist(
				"find "
					.. vim.fn.expand("$HOME/dev")
					.. " -maxdepth 4 -type d -name "
					.. vim.fn.shellescape(basename)
					.. " 2>/dev/null | head -n1"
			)
			if found[1] and found[1] ~= "" then
				return found[1]
			end
			-- fallback to cwd
			return vim.fn.getcwd()
		else
			return opts.dir
		end
	else
		-- auto: git root else cwd (same logic as tail script)
		local handle = io.popen("git rev-parse --show-toplevel 2>/dev/null")
		local git_root = handle and handle:read("*l")
		if handle then
			handle:close()
		end
		if git_root and git_root ~= "" then
			return git_root
		end
		return vim.fn.getcwd()
	end
end

local function is_loop_active(line)
	-- loop step 0 -> active, exit -> inactive
	if line:match("LOOP%s+loop") and line:match("step=0") then
		return true
	end
	if line:match("LOOP%s+exit") or line:match("exiting loop") then
		return false
	end
	return nil -- no change
end

function M.start()
	if job_id and job_id > 0 then
		vim.fn.jobstop(job_id)
		job_id = nil
	end
	local opts = config.options
	local dir = resolve_dir()
	local script = opts.tail_script
	-- ensure script exists
	if vim.fn.filereadable(script) ~= 1 then
		vim.notify("opencode-watcher: tail script not found: " .. script, vim.log.levels.ERROR)
		return
	end
	local basename = vim.fn.fnamemodify(dir, ":t")
	-- build command: tail script with dir filter, lines 0 (live only), exclude noisy by default
	local cmd = { script, "--dir", dir, "--lines", tostring(opts.lines or 0) }
	if opts.exclude and opts.exclude ~= "" then
		table.insert(cmd, "--exclude")
		table.insert(cmd, opts.exclude)
	end
	-- we want to see human friendly, so not too noisy
	vim.notify("opencode-watcher: watching [" .. basename .. "] " .. dir, vim.log.levels.INFO)

	loop_active = false
	ui.clear()

	job_id = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data, _)
			for _, line in ipairs(data) do
				if line == "" then
					goto continue
				end
				-- update loop_active
				local active = is_loop_active(line)
				if active == true then
					loop_active = true
					loop_exit_pending = false
					ui.cancel_hide()
					if idle_hide_timer then
						vim.fn.timer_stop(idle_hide_timer)
						idle_hide_timer = nil
					end
					ui.ensure_window()
				elseif active == false then
					loop_active = false
					loop_exit_pending = true
					if idle_hide_timer then
						vim.fn.timer_stop(idle_hide_timer)
						idle_hide_timer = nil
					end
					ui.hide_delayed()
				else
					if loop_active then
						ui.cancel_hide()
						if idle_hide_timer then
							vim.fn.timer_stop(idle_hide_timer)
							idle_hide_timer = nil
						end
						ui.ensure_window()
					else
						-- not looping: show briefly then auto-hide after 5s
						ui.ensure_window()
						if idle_hide_timer then
							vim.fn.timer_stop(idle_hide_timer)
						end
						idle_hide_timer = vim.fn.timer_start(5000, function()
							if not loop_active then
								ui.hide()
							end
							idle_hide_timer = nil
						end)
					end
				end

				ui.push_raw(line)

				::continue::
			end
		end,
		on_stderr = function(_, data, _)
			-- tail script prints headers to stderr, ignore or show once
			for _, line in ipairs(data) do
				if line:match("tailing") or line:match("filtering") then
					-- show as info once
					-- vim.notify(line, vim.log.levels.DEBUG)
				end
			end
		end,
		on_exit = function(_, code, _)
			job_id = nil
			if code ~= 0 then
				vim.notify("opencode-watcher: tail exited code " .. code, vim.log.levels.WARN)
			end
		end,
		pty = false,
	})

	if job_id <= 0 then
		vim.notify("opencode-watcher: failed to start tail", vim.log.levels.ERROR)
		job_id = nil
	end
end

function M.stop()
	if job_id and job_id > 0 then
		vim.fn.jobstop(job_id)
		job_id = nil
	end
	if idle_hide_timer then
		vim.fn.timer_stop(idle_hide_timer)
		idle_hide_timer = nil
	end
	ui.hide()
	loop_active = false
end

function M.restart()
	M.stop()
	vim.defer_fn(function()
		M.start()
	end, 200)
end

function M.toggle()
	if job_id and job_id > 0 then
		M.stop()
	else
		M.start()
	end
end

-- auto-refresh helper exposed
function M.refresh()
	ui.refresh_visible_buffers()
end

return M
