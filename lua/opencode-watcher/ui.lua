local M = {}

local buf = nil
local win = nil
local lines = {}
local config = nil
local hide_timer = nil

local function resolve_config()
	config = require("opencode-watcher.config").options
end

local function get_position()
	resolve_config()
	local width = config.width
	local height = config.height
	local cols = vim.o.columns
	local rows = vim.o.lines
	local col = cols - width - 2
	local row
	if config.position == "bottom-right" then
		row = rows - height - 4 -- above cmdline
	else -- top-right
		row = 1
	end
	-- clamp
	if col < 0 then
		col = 0
	end
	if row < 0 then
		row = 0
	end
	return row, col, width, height
end

function M.is_visible()
	return win and vim.api.nvim_win_is_valid(win)
end

function M.ensure_window()
	resolve_config()
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
		vim.api.nvim_buf_set_option(buf, "filetype", "opencode-watcher")
	end
	if not win or not vim.api.nvim_win_is_valid(win) then
		local row, col, width, height = get_position()
		win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			row = row,
			col = col,
			width = width,
			height = height,
			style = "minimal",
			border = config.border,
			title = " opencode ",
			title_pos = "center",
			zindex = 50,
		})
		vim.api.nvim_win_set_option(win, "wrap", true)
		vim.api.nvim_win_set_option(win, "linebreak", true)
		vim.api.nvim_win_set_option(win, "breakindent", true)
		vim.api.nvim_win_set_option(win, "cursorline", false)
		vim.api.nvim_win_set_option(win, "winblend", 12)
		-- subtle highlight
		pcall(vim.api.nvim_win_set_option, win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")
	end
	return buf, win
end

function M.hide()
	if hide_timer then
		vim.fn.timer_stop(hide_timer)
		hide_timer = nil
	end
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
		win = nil
	end
	-- whenever floating window is hidden, clear all text so next show is fresh
	M.clear()
end

function M.hide_delayed()
	resolve_config()
	if hide_timer then
		vim.fn.timer_stop(hide_timer)
	end
	hide_timer = vim.fn.timer_start(config.hide_delay, function()
		-- only hide if loop not active (caller checks)
		M.hide()
	end)
end

function M.cancel_hide()
	if hide_timer then
		vim.fn.timer_stop(hide_timer)
		hide_timer = nil
	end
end

function M.append(line, hl)
	-- use highlights from config alongside icons
	if not hl then
		resolve_config()
		local hls = config.highlights or {}
		-- detect tag from line prefix like "󰌾 perm - edit" or "󰅚 err - aborted"
		if line:match("perm.*edit") or line:match("edit %-") then
			hl = hls.PERM_EDIT or hls.PERM or "WarningMsg"
		elseif line:match("aborted") or line:match("cancelled") then
			hl = hls.ERR_ABORT or hls.ERR or "ErrorMsg"
		elseif line:match("stream error") then
			hl = hls.ERR or "ErrorMsg"
		elseif line:match("perm") then
			hl = hls.PERM or "Directory"
		elseif line:match("llm") then
			hl = hls.LLM or "Special"
		elseif line:match("loop") then
			hl = hls.LOOP or "Statement"
		elseif line:match("sync") then
			hl = hls.SYNC or "Comment"
		elseif line:match("boot") then
			hl = hls.BOOT or "Special"
		elseif line:match("reading") or line:match("editing") then
			hl = hls.FILE or "Directory"
		elseif line:match("file") then
			hl = hls.FILE or "Directory"
		elseif line:match("session") then
			hl = hls.SESS or "Identifier"
		elseif line:match("watch") then
			hl = hls.WATCH or "Directory"
		elseif line:match("cfg") then
			hl = hls.CFG or "Comment"
		elseif line:match("msg") then
			hl = hls.MSG or "Normal"
		elseif line:match("ERR") or line:match("err") then
			hl = hls.ERR or "ErrorMsg"
		else
			hl = hls.DEFAULT or "Normal"
		end
	end
	table.insert(lines, { text = line, hl = hl })
	if #lines > (config and config.max_lines or 100) then
		table.remove(lines, 1)
	end
	M.render()
end

function M.render()
	local b, w = M.ensure_window()
	-- build display lines
	local display = {}
	for _, entry in ipairs(lines) do
		table.insert(display, entry.text)
	end
	vim.api.nvim_buf_set_option(b, "modifiable", true)
	vim.api.nvim_buf_set_lines(b, 0, -1, false, display)
	vim.api.nvim_buf_set_option(b, "modifiable", false)
	-- apply highlights per line
	for i, entry in ipairs(lines) do
		if entry.hl then
			pcall(vim.api.nvim_buf_add_highlight, b, -1, entry.hl, i - 1, 0, -1)
		end
	end
	-- keep cursor at bottom
	if w and vim.api.nvim_win_is_valid(w) then
		local count = vim.api.nvim_buf_line_count(b)
		vim.api.nvim_win_set_cursor(w, { math.min(count, vim.api.nvim_buf_line_count(b)), 0 })
	end
end

function M.clear()
	lines = {}
	if buf and vim.api.nvim_buf_is_valid(buf) then
		local ok, mod = pcall(vim.api.nvim_buf_get_option, buf, "modifiable")
		local was_mod = ok and mod or false
		pcall(vim.api.nvim_buf_set_option, buf, "modifiable", true)
		pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, {})
		if not was_mod then
			pcall(vim.api.nvim_buf_set_option, buf, "modifiable", false)
		end
	end
end

function M.refresh_visible_buffers()
	-- refresh visible buffers when opencode formats a file
	vim.schedule(function()
		-- checktime for all
		vim.cmd("silent! checktime")
		-- for each visible window, reload if file changed
		for _, winid in ipairs(vim.api.nvim_list_wins()) do
			local b = vim.api.nvim_win_get_buf(winid)
			if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_option(b, "modified") == false then
				local name = vim.api.nvim_buf_get_name(b)
				if name ~= "" and vim.fn.filereadable(name) == 1 then
					-- only if file was changed outside (checktime already did, but force for formatted)
					vim.api.nvim_buf_call(b, function()
						vim.cmd("silent! e!")
					end)
				end
			end
		end
	end)
end

-- helper: truncate at word boundary, not mid-word, with ellipsis
local function truncate_word_aware(str, max_len)
	if #str <= max_len then
		return str
	end
	-- try to cut at last space before max_len
	local cut = str:sub(1, max_len)
	local last_space = cut:match(".*() ")
	if last_space and last_space > max_len * 0.6 then
		return cut:sub(1, last_space - 1) .. "…"
	else
		return cut .. "…"
	end
end

-- human friendly formatter: maps raw tail line to short message
-- no time, no LOG, just "type - detail" with word-aware wrapping
function M.humanize(raw)
	resolve_config()
	local icons = config.icons or {}
	-- raw is like "18:25:10 [opencode-watcher.nvim] FILE  touching  /path"
	-- extract tag and msg after [basename]
	local tag, msg = raw:match("%] (%S+)%s+(.+)$")
	if not tag then
		tag = raw:match("%] (%S+)") or "LOG"
		msg = raw:match("%] %S+%s+(.+)$") or raw
	end
	tag = tag:upper()
	-- hide LOG entirely - map to subtle
	if tag == "LOG" then
		tag = "INFO"
	end
	local icon = icons[tag] or icons.DEFAULT or "•"

	-- pretty per type, without time, without LOG word
	if tag == "FILE" then
		local f = msg:match("touching%s+(.+)$") or msg:match("formatting%s+(.+)$") or msg:match("resolved%s+(.+)$")
		if f then
			f = vim.fn.fnamemodify(f:match("([^%s]+)%s*$") or f, ":t")
			if msg:match("touching") then
				return string.format("%s reading %s", icon, f)
			elseif msg:match("formatting") then
				return string.format("%s editing %s", icon, f)
			else
				return string.format("%s %s", icon, truncate_word_aware(f, 32))
			end
		end
	end
	if tag == "SYNC" then
		-- sync - project, started, completed
		local proj = msg:match("project=([^ ]+)")
		if msg:match("started") then
			if proj and proj ~= "" then
				return string.format("%s sync - %s started", icon, proj)
			end
			return string.format("%s sync - started", icon)
		elseif msg:match("done") or msg:match("refresh done") then
			if proj and proj ~= "" then
				return string.format("%s sync - %s completed", icon, proj)
			end
			return string.format("%s sync - completed", icon)
		else
			if proj then
				return string.format("%s sync - %s", icon, truncate_word_aware(proj, 24))
			end
			return string.format("%s sync", icon)
		end
	end
	if tag == "LOOP" then
		if msg:match("step=0") then
			return string.format("%s loop - started", icon)
		elseif msg:match("exit") then
			return string.format("%s loop - completed", icon)
		else
			local step = msg:match("step=(%d+)")
			if step then
				return string.format("%s loop - step %s", icon, step)
			end
		end
	end
	if tag == "PERM" then
		local perm = msg:match("perm=([^ ]+)")
		local pat = msg:match("pat=([^ ]+)")
		if perm and pat then
			pat = pat:gsub("%.%.%.$", "")
			-- pat is already basename from tail script, keep as is
			return string.format("%s %s - %s", icon, perm, truncate_word_aware(pat, 28))
		elseif perm then
			return string.format("%s perm - %s", icon, perm)
		end
	end
	if tag == "LLM" then
		local model = msg:match("model=([^ ]+)") or msg:match("provider=([^ ]+)")
		if msg:match("stream") then
			if model and model ~= "" then
				return string.format("%s llm - %s", icon, truncate_word_aware(model, 20))
			else
				return string.format("%s llm - streaming", icon)
			end
		elseif msg:match("runtime") then
			if model and model ~= "" then
				return string.format("%s llm - %s", icon, truncate_word_aware(model, 20))
			else
				return string.format("%s llm - runtime", icon)
			end
		end
	end
	if tag == "BOOT" then
		if msg:match("creating") then
			return icon .. " boot - created"
		elseif msg:match("bootstrapping") then
			return icon .. " boot - bootstrapping"
		elseif msg:match("init") then
			local cnt = msg:match("count=%d+")
			if cnt then
				return string.format("%s boot - init %s", icon, cnt)
			end
			return icon .. " boot - init"
		elseif msg:match("location") then
			return icon .. " boot - ready"
		end
	end
	if tag == "MSG" then
		-- show short msg id, not full
		return string.format("%s msg - processing", icon)
	end
	if tag == "SESS" then
		local slug = msg:match("created%s+(%S+)")
		if slug then
			return string.format("%s session - %s", icon, truncate_word_aware(slug, 20))
		end
		return string.format("%s session", icon)
	end
	if tag == "WATCH" then
		local backend = msg:match("backend=([^ ]+)")
		if backend then
			return string.format("%s watch - %s", icon, backend)
		end
		return string.format("%s watch", icon)
	end
	if tag == "CFG" then
		if msg:match("LSP") then
			return icon .. " cfg - lsp"
		elseif msg:match("formatter") then
			return icon .. " cfg - formatter"
		elseif msg:match("loading") then
			local p = msg:match("loading%s+(.+)$")
			if p then
				p = vim.fn.fnamemodify(p, ":t")
				return string.format("%s cfg - %s", icon, p)
			end
		end
		return string.format("%s cfg", icon)
	end
	-- fallback: show tag lowercased - detail, word-aware truncated, no LOG word
	local detail = msg:gsub("^%s+", "")
	-- remove noisy prefixes like "eval  perm=" keep just perm:pat part already handled above, this is fallback
	if tag == "LOG" or tag == "INFO" or tag == "RAW" or tag == "MISC" or tag == "CLEAN" or tag == "EVT" then
		-- hide LOG/RAW entirely, show detail only
		return string.format("%s %s", icon, truncate_word_aware(detail, 36))
	end
	return string.format("%s %s - %s", icon, tag:lower(), truncate_word_aware(detail, 30))
end

local refresh_debounce = nil
function M.push_raw(raw)
	local human = M.humanize(raw)
	-- only real mutations: formatting and reverting/restore/unreverting (loop exit no refresh per user)
	local should_refresh = false
	if raw:match("FILE%s+formatting") or raw:match("formatting") then
		should_refresh = true
	elseif raw:match("reverting") or raw:match("restore") or raw:match("unreverting") then
		should_refresh = true
	end
	if should_refresh then
		if refresh_debounce then
			vim.fn.timer_stop(refresh_debounce)
		end
		refresh_debounce = vim.fn.timer_start(150, function()
			M.refresh_visible_buffers()
			refresh_debounce = nil
		end)
		human = human .. "  ↻"
	end
	M.append(human)
end

return M
