local M = {}

local buf = nil
local win = nil
local aug = nil

local function get_config()
	return require("opencode-watcher.config").options
end

-- create or get prompt buffer
local function ensure_buf()
	if buf and vim.api.nvim_buf_is_valid(buf) then
		return buf
	end
	buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "opencode://prompt")
	vim.api.nvim_buf_set_option(buf, "buftype", "acwrite")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "buflisted", false)
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(buf, "undolevels", 1000)
	-- start empty, not modified
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	vim.api.nvim_buf_set_option(buf, "modified", false)

	-- intercept :w
	if aug then
		pcall(vim.api.nvim_del_augroup_by_id, aug)
	end
	aug = vim.api.nvim_create_augroup("OpencodePromptBuffer" .. buf, { clear = true })
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		group = aug,
		buffer = buf,
		callback = function()
			M.submit()
		end,
		desc = "opencode prompt submit on save",
	})
	-- also allow :w to be triggered via <C-s> etc
	vim.api.nvim_buf_set_option(buf, "modifiable", true)
	return buf
end

local function is_win_valid()
	return win and vim.api.nvim_win_is_valid(win)
end

function M.get_buf()
	if buf and vim.api.nvim_buf_is_valid(buf) then
		return buf
	end
	return nil
end

function M.get_win()
	if is_win_valid() then
		return win
	end
	return nil
end

local function close_win_only()
	if is_win_valid() then
		vim.api.nvim_win_close(win, true)
		win = nil
	end
end

function M.close()
	close_win_only()
	-- keep buf hidden for reuse unless user wants wipe
end

function M.wipe()
	close_win_only()
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
		buf = nil
	end
	if aug then
		pcall(vim.api.nvim_del_augroup_by_id, aug)
		aug = nil
	end
end

-- float geometry
local function open_float(b)
	local cfg = get_config()
	local p = cfg.prompt or {}
	local f = p.float or {}
	local width = f.width or 80
	local height = f.height or 20
	local border = f.border or cfg.border or "rounded"
	local title = f.title or " opencode prompt (save :w to send) "
	-- if width/height are <1 treat as percentage
	if width > 0 and width < 1 then
		width = math.floor(vim.o.columns * width)
	end
	if height > 0 and height < 1 then
		height = math.floor(vim.o.lines * height)
	end
	width = math.min(width, vim.o.columns - 4)
	height = math.min(height, vim.o.lines - 4)
	local row = math.floor((vim.o.lines - height) / 2 - 1)
	local col = math.floor((vim.o.columns - width) / 2)
	if row < 0 then
		row = 0
	end
	if col < 0 then
		col = 0
	end
	win = vim.api.nvim_open_win(b, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = border,
		title = title,
		title_pos = "center",
		zindex = 50,
	})
	vim.api.nvim_win_set_option(win, "wrap", true)
	vim.api.nvim_win_set_option(win, "linebreak", true)
	vim.api.nvim_win_set_option(win, "breakindent", true)
	vim.api.nvim_win_set_option(win, "cursorline", false)
	vim.api.nvim_win_set_option(win, "winblend", 0)
	vim.api.nvim_win_set_option(win, "conceallevel", 0)
	-- allow closing with q
	vim.keymap.set("n", "q", function()
		M.close()
	end, { buffer = b, nowait = true, desc = "close opencode prompt" })
end

local function open_vsplit(b)
	local cfg = get_config()
	local p = cfg.prompt or {}
	local v = p.vsplit or {}
	local width = v.width or 60
	-- reuse existing win if valid and is vsplit? simplest: check is our win a vsplit (not floating)
	-- we already closed float win if any via close_win_only, but we treat any existing win as reuse
	if is_win_valid() then
		vim.api.nvim_set_current_win(win)
		vim.api.nvim_win_set_buf(win, b)
		return
	end
	vim.cmd("vsplit")
	win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, b)
	if width and width > 0 then
		pcall(vim.api.nvim_win_set_width, win, width)
	end
	vim.api.nvim_win_set_option(win, "wrap", true)
	vim.api.nvim_win_set_option(win, "linebreak", true)
	vim.api.nvim_win_set_option(win, "breakindent", true)
	vim.api.nvim_win_set_option(win, "winblend", 0)
	vim.keymap.set("n", "q", function()
		M.close()
	end, { buffer = b, nowait = true, desc = "close opencode prompt" })
end

--- Open prompt window. Always vsplit (floating deprecated).
function M.open(opts)
	opts = opts or {}
	local cfg = get_config()
	local p = cfg.prompt or {}
	local win_type = opts.win or p.win or "vsplit"
	-- enforce vsplit only per spec: floating window not used
	if win_type == "float" then
		win_type = "vsplit"
	end
	if win_type ~= "vsplit" and win_type ~= "split" then
		win_type = "vsplit"
	end
	local b = ensure_buf()
	-- if already visible, focus it
	if is_win_valid() then
		-- check if existing win type matches requested; if mismatched, close and reopen
		local is_float = vim.api.nvim_win_get_config(win).relative ~= ""
		local want_float = win_type == "float"
		if is_float ~= want_float then
			close_win_only()
		else
			vim.api.nvim_set_current_win(win)
			return b, win
		end
	end
	if win_type == "float" then
		open_float(b)
	else
		open_vsplit(b)
	end
	-- ensure buffer is modifiable and enter insert-ish normal mode
	vim.api.nvim_buf_set_option(b, "modifiable", true)
	-- set modified false if empty
	local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
	if #lines == 1 and lines[1] == "" then
		vim.api.nvim_buf_set_option(b, "modified", false)
	end
	return b, win
end

function M.toggle(opts)
	if is_win_valid() then
		M.close()
	else
		M.open(opts)
	end
end

-- robust visual selection extractor, works from any buffer including quickfix/trouble
function M.get_visual_selection()
	-- prefer getregion if available (nvim 0.10+)
	if vim.fn.exists("*getregion") == 1 then
		local mode = vim.fn.mode()
		-- if still in visual mode, use v and .
		if mode:match("[vV\22]") then
			local s = vim.fn.getpos("v")
			local e = vim.fn.getpos(".")
			local t = mode
			if t == "V" then
				t = "V"
			elseif t == "\22" then
				t = "\22"
			else
				t = "v"
			end
			local ok, region = pcall(vim.fn.getregion, s, e, { type = t })
			if ok and region and #region > 0 then
				return table.concat(region, "\n")
			end
		else
			local s = vim.fn.getpos("'<")
			local e = vim.fn.getpos("'>")
			if s[2] ~= 0 and e[2] ~= 0 then
				local vmode = vim.fn.visualmode()
				if vmode == "" then
					vmode = "v"
				end
				local ok, region = pcall(vim.fn.getregion, s, e, { type = vmode })
				if ok and region and #region > 0 then
					return table.concat(region, "\n")
				end
			end
		end
	end

	-- fallback path
	local mode = vim.fn.mode()
	if mode:match("[vV\22]") then
		local s = vim.fn.getpos("v")
		local e = vim.fn.getpos(".")
		local srow, scol = s[2], s[3]
		local erow, ecol = e[2], e[3]
		if srow > erow or (srow == erow and scol > ecol) then
			srow, erow = erow, srow
			scol, ecol = ecol, scol
		end
		if mode == "V" then
			local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
			return table.concat(lines, "\n")
		else
			local ok, txt = pcall(vim.api.nvim_buf_get_text, 0, srow - 1, scol - 1, erow - 1, ecol, {})
			if ok then
				return table.concat(txt, "\n")
			end
			local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
			if #lines == 0 then
				return ""
			end
			if #lines == 1 then
				return lines[1]:sub(scol, ecol)
			else
				lines[1] = lines[1]:sub(scol)
				lines[#lines] = lines[#lines]:sub(1, ecol)
				return table.concat(lines, "\n")
			end
		end
	else
		local s = vim.fn.getpos("'<")
		local e = vim.fn.getpos("'>")
		if s[2] == 0 or e[2] == 0 then
			return nil
		end
		local srow, scol = s[2], s[3]
		local erow, ecol = e[2], e[3]
		if srow > erow or (srow == erow and scol > ecol) then
			srow, erow = erow, srow
			scol, ecol = ecol, scol
		end
		local vmode = vim.fn.visualmode()
		-- visualmode() may return empty if not in visual; assume linewise if col is huge
		if vmode == "V" then
			local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
			return table.concat(lines, "\n")
		elseif vmode == "\22" or vmode == "" then
			-- try to detect linewise: in linewise visual, start col 1 and end col is 2147483647
			if scol == 1 and ecol >= 2147483647 then
				local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
				return table.concat(lines, "\n")
			end
			-- otherwise if unknown, try get_text then fallback
			local ok, txt = pcall(vim.api.nvim_buf_get_text, 0, srow - 1, scol - 1, erow - 1, ecol, {})
			if ok then
				return table.concat(txt, "\n")
			end
			local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
			if #lines == 0 then
				return nil
			end
			if #lines == 1 then
				return lines[1]:sub(scol, ecol)
			else
				lines[1] = lines[1]:sub(scol)
				lines[#lines] = lines[#lines]:sub(1, ecol)
				return table.concat(lines, "\n")
			end
		else
			-- charwise v
			local ok, txt = pcall(vim.api.nvim_buf_get_text, 0, srow - 1, scol - 1, erow - 1, ecol, {})
			if ok then
				return table.concat(txt, "\n")
			end
			local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
			if #lines == 0 then
				return nil
			end
			if #lines == 1 then
				return lines[1]:sub(scol, ecol)
			else
				lines[1] = lines[1]:sub(scol)
				lines[#lines] = lines[#lines]:sub(1, ecol)
				return table.concat(lines, "\n")
			end
		end
	end
end

-- capture file context for yank: filename + line range, only for real file buffers
local function capture_context()
	local src_buf = vim.api.nvim_get_current_buf()
	if src_buf == buf then
		return nil
	end
	local bt = vim.api.nvim_buf_get_option(src_buf, "buftype")
	if bt ~= "" then
		return nil
	end
	local name = vim.api.nvim_buf_get_name(src_buf)
	if name == "" or name:match("^opencode://") then
		return nil
	end
	local srow, erow
	local mode = vim.fn.mode()
	if mode:match("[vV\22]") then
		local s = vim.fn.getpos("v")
		local e = vim.fn.getpos(".")
		srow = s[2]
		erow = e[2]
	else
		local s = vim.fn.getpos("'<")
		local e = vim.fn.getpos("'>")
		if s[2] == 0 or e[2] == 0 then
			return nil
		end
		srow = s[2]
		erow = e[2]
	end
	if srow > erow then
		srow, erow = erow, srow
	end
	local rel = vim.fn.fnamemodify(name, ":~:.")
	if rel == "" then
		rel = name
	end
	local ft = vim.api.nvim_buf_get_option(src_buf, "filetype")
	if ft == "" then
		ft = vim.fn.fnamemodify(name, ":e")
	end
	return { filename = rel, full = name, srow = srow, erow = erow, filetype = ft or "", buf = src_buf }
end

local function format_yank(text, ctx)
	if not ctx or not ctx.filename or ctx.filename == "" then
		return text
	end
	local header
	if ctx.srow == ctx.erow then
		header = string.format("File: %s:%d", ctx.filename, ctx.srow)
	else
		header = string.format("File: %s:%d-%d", ctx.filename, ctx.srow, ctx.erow)
	end
	local fence = ctx.filetype or ""
	-- sanitize fence to avoid injection
	if fence ~= "" and not fence:match("^[%w_+-]+$") then
		fence = ""
	end
	return string.format("%s\n```%s\n%s\n```", header, fence, text)
end

function M.append_text(text)
	if not text or text == "" then
		return false
	end
	local b = ensure_buf()
	-- ensure window is open; caller decides win type but we reuse existing or open default
	if not is_win_valid() then
		M.open()
	else
		-- focus window if already open? keep focus
	end
	vim.api.nvim_buf_set_option(b, "modifiable", true)
	local lines = vim.split(text, "\n", { plain = true })
	local cur = vim.api.nvim_buf_get_lines(b, 0, -1, false)
	local is_empty = #cur == 1 and cur[1] == ""
	if is_empty then
		vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
	else
		local insert_at = #cur
		-- add separator blank line if last line not empty
		if cur[#cur] ~= "" then
			table.insert(lines, 1, "")
		end
		vim.api.nvim_buf_set_lines(b, insert_at, insert_at, false, lines)
	end
	vim.api.nvim_buf_set_option(b, "modified", true)
	if is_win_valid() then
		local count = vim.api.nvim_buf_line_count(b)
		pcall(vim.api.nvim_win_set_cursor, win, { count, 0 })
	end
	return true
end

-- main handler for Ctrl-.
-- is_visual = true when invoked from visual mode mapping
function M.open_or_yank(is_visual)
	local sel = nil
	local ctx = nil
	if is_visual then
		-- capture file context + selection before leaving visual and before switching buffer
		ctx = capture_context()
		sel = M.get_visual_selection()
		if vim.fn.mode():match("[vV\22]") then
			pcall(vim.cmd, "normal! \27")
		end
	end
	-- open prompt (vsplit default) and focus
	M.open()
	if sel and sel ~= "" then
		local formatted = format_yank(sel, ctx)
		M.append_text(formatted)
	end
end

-- alternative handler that also considers previous visual marks when called from normal mode
-- keeps simple: normal mode just opens, visual mode yanks
function M.handle_key()
	local mode = vim.fn.mode()
	if mode:match("[vV\22]") then
		M.open_or_yank(true)
	else
		-- check if there is a lingering visual selection that hasn't been yanked?
		-- We keep spec simple: normal opens without yanking
		M.open()
	end
end

function M.submit()
	local b = ensure_buf()
	local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
	local content = table.concat(lines, "\n")
	if content:match("^%s*$") then
		vim.notify("opencode prompt: empty, nothing to send", vim.log.levels.WARN)
		vim.api.nvim_buf_set_option(b, "modified", false)
		return
	end
	-- placeholder for future opencode integration: send via job / TUI
	-- for now just notify
	vim.notify("prompt sent to opencode", vim.log.levels.INFO)
	-- fire User autocmd so users can hook real send
	pcall(vim.api.nvim_exec_autocmds, "User", {
		pattern = "OpencodePromptSubmit",
		data = { content = content, buf = b },
	})
	local cfg = get_config()
	local p = cfg.prompt or {}
	if p.clear_on_submit then
		vim.api.nvim_buf_set_lines(b, 0, -1, false, {})
		vim.api.nvim_buf_set_option(b, "modified", false)
	else
		vim.api.nvim_buf_set_option(b, "modified", false)
	end
	if p.close_on_submit then
		M.close()
	end
end

function M.setup()
	-- nothing to do here now, config already set
	-- ensure highlight for prompt?
end

return M
