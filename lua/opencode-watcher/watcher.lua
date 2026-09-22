local M = {}

local config = require("opencode-watcher.config")
local ui = require("opencode-watcher.ui")

local job_id = nil
local loop_active = false
local loop_exit_pending = false
local idle_hide_timer = nil

local function resolve_dir()
	-- auto only: git root else cwd (same logic as tail script)
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
	loop_active = false
	ui.clear()

	job_id = vim.fn.jobstart(cmd, {
		on_stdout = function(_, data, _)
			for _, line in ipairs(data) do
				if line == "" then
					goto continue
				end
				-- detect error to pin window (never auto-hide on error)
				local is_err = line:match("%sERR%s") ~= nil
					or line:match("stream error") ~= nil
					or line:match("aborted") ~= nil
					or line:match("cancelled") ~= nil
					or line:match("ERR%s+stream") ~= nil
				-- update loop_active
				local active = is_loop_active(line)
				if is_err then
					-- pin window on error: cancel any pending hide and keep visible
					ui.cancel_hide()
					if idle_hide_timer then
						vim.fn.timer_stop(idle_hide_timer)
						idle_hide_timer = nil
					end
					ui.ensure_window()
				elseif active == true then
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
						-- not looping: show briefly then auto-hide after 5s (unless pinned by error above)
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

-- expose dir resolver for prompt/server
M.resolve_dir = resolve_dir
M.get_dir = resolve_dir
function M.is_running()
	return job_id and job_id > 0
end

return M
