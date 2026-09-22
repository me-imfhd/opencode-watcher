local M = {}

local server_job = nil

local function log(level, msg)
	local ok, logger = pcall(require, "opencode-watcher.logger")
	if ok and logger then
		logger.log(level, msg)
	end
end

local function get_cfg()
	local opts = require("opencode-watcher.config").options
	local p = opts.prompt or {}
	local s = p.server or {}
	return {
		hostname = s.hostname or s.host or "127.0.0.1",
		port = s.port or 4096,
		auto_approve = s.auto_approve ~= false,
		model = s.model,
		variant = s.variant,
		thinking = s.thinking,
		agent = s.agent,
		timeout_ms = s.timeout_ms or s.timeout or 30000,
	}
end
local sessions = {} -- dir -> sessionID
local active_runs = {} -- dir -> job_id
local sessions_file = vim.fn.stdpath("data") .. "/opencode-watcher/sessions.json"
-- per-session model/variant (only for session, not globally)
local session_models = {} -- dir -> {id, providerID, variant}
local session_models_file = vim.fn.stdpath("data") .. "/opencode-watcher/session_models.json"

local function normalize_dir(dir)
	if not dir or dir == "" then
		return ""
	end
	local norm = vim.fn.fnamemodify(dir, ":p")
	if #norm > 1 and norm:sub(-1) == "/" then
		norm = norm:sub(1, -2)
	end
	return norm
end

local function load_sessions()
	local ok, data = pcall(vim.fn.readfile, sessions_file)
	if not ok or not data or #data == 0 then
		return
	end
	local content = table.concat(data, "\n")
	local ok2, decoded = pcall(vim.json.decode, content)
	if ok2 and type(decoded) == "table" then
		sessions = decoded
	end
end
local function save_sessions()
	pcall(vim.fn.mkdir, vim.fn.fnamemodify(sessions_file, ":h"), "p")
	local ok, encoded = pcall(vim.json.encode, sessions)
	if ok and encoded then
		pcall(vim.fn.writefile, vim.split(encoded, "\n"), sessions_file)
	end
end
pcall(load_sessions)

local function load_session_models()
	local ok, data = pcall(vim.fn.readfile, session_models_file)
	if not ok or not data or #data == 0 then
		return
	end
	local content = table.concat(data, "\n")
	local ok2, decoded = pcall(vim.json.decode, content)
	if ok2 and type(decoded) == "table" then
		session_models = decoded
	end
end
local function save_session_models()
	pcall(vim.fn.mkdir, vim.fn.fnamemodify(session_models_file, ":h"), "p")
	local ok, encoded = pcall(vim.json.encode, session_models)
	if ok and encoded then
		pcall(vim.fn.writefile, vim.split(encoded, "\n"), session_models_file)
	end
end
pcall(load_session_models)

local function get_session(dir)
	dir = normalize_dir(dir)
	return sessions[dir]
end

local function set_session(dir, id)
	dir = normalize_dir(dir)
	if not dir or dir == "" or not id or id == "" then
		return
	end
	sessions[dir] = id
	save_sessions()
	log("INFO", string.format("session tracked for %s -> %s", dir, id))
end

function M.get_session(dir)
	return get_session(dir)
end
function M.clear_session(dir)
	dir = normalize_dir(dir or "")
	if dir and dir ~= "" then
		sessions[dir] = nil
		save_sessions()
	else
		sessions = {}
		save_sessions()
	end
end

local function get_session_model(dir)
	dir = normalize_dir(dir)
	return session_models[dir]
end

local function set_session_model(dir, model_ref)
	dir = normalize_dir(dir)
	if not dir or dir == "" or not model_ref or not model_ref.id then
		return
	end
	session_models[dir] = model_ref
	save_session_models()
	log(
		"INFO",
		string.format(
			"session model for %s -> %s/%s variant=%s",
			dir,
			model_ref.providerID,
			model_ref.id,
			tostring(model_ref.variant)
		)
	)
end

function M.get_session_model(dir)
	return get_session_model(dir)
end
function M.set_session_model(dir, model_ref)
	if not model_ref or not model_ref.id then
		return
	end
	set_session_model(dir, model_ref)
	local sid = get_session(dir)
	if sid and sid ~= "" then
		M.switch_model(sid, model_ref)
	end
end
function M.clear_session_model(dir)
	dir = normalize_dir(dir or "")
	if dir and dir ~= "" then
		session_models[dir] = nil
		save_session_models()
	else
		session_models = {}
		save_session_models()
	end
end
-- switch model for an existing session via API (per-session, not global)
function M.switch_model(session_id, model_ref)
	if not session_id or session_id == "" or not model_ref or not model_ref.id then
		return false
	end
	local cfg = get_cfg()
	local url = string.format("http://%s:%d/api/session/%s/model", cfg.hostname, cfg.port, session_id)
	log(
		"INFO",
		string.format(
			"switching session %s model to %s/%s variant=%s",
			session_id,
			model_ref.providerID,
			model_ref.id,
			tostring(model_ref.variant)
		)
	)
	local tmp = vim.fn.tempname()
	vim.fn.writefile({ vim.json.encode({ model = model_ref }) }, tmp)
	local out = vim.fn.system({
		"curl",
		"-s",
		"-X",
		"POST",
		url,
		"-H",
		"Content-Type: application/json",
		"-d",
		"@" .. tmp,
		"--connect-timeout",
		"5",
	})
	vim.fn.delete(tmp)
	log("DEBUG", string.format("switch model curl out: %s", out:sub(1, 200)))
	return true
end

function M.get_config()
	return get_cfg()
end

function M.url(host, port)
	host = host or get_cfg().hostname
	port = port or get_cfg().port
	return string.format("http://%s:%d", host, port)
end

function M.is_running(host, port)
	local cfg = get_cfg()
	host = host or cfg.hostname
	port = port or cfg.port
	local url = string.format("http://%s:%d/doc", host, port)
	local out = vim.fn.system({ "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "1", url })
	local code = vim.trim and vim.trim(out or "") or (out or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if code == "200" then
		return true
	end
	local url2 = string.format("http://%s:%d/global/health", host, port)
	local out2 =
		vim.fn.system({ "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "1", url2 })
	local code2 = vim.trim and vim.trim(out2 or "") or (out2 or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if code2 == "200" then
		return true
	end
	log("DEBUG", string.format("is_running %s:%d -> /doc=%s /health=%s", host, port, code, code2))
	return false
end

function M.ensure_server(cb)
	local cfg = get_cfg()
	if M.is_running(cfg.hostname, cfg.port) then
		if cb then
			cb(true)
		end
		return true
	end
	if vim.fn.executable("opencode") ~= 1 then
		vim.notify("opencode watcher: opencode binary not found in PATH", vim.log.levels.ERROR)
		log("ERROR", "opencode binary not found in PATH")
		if cb then
			cb(false)
		end
		return false
	end
	local cmd = { "opencode", "serve", "--port", tostring(cfg.port), "--hostname", cfg.hostname, "--print-logs" }
	log("INFO", string.format("starting server at %s:%d cmd=%s", cfg.hostname, cfg.port, table.concat(cmd, " ")))
	if server_job and server_job > 0 then
		pcall(vim.fn.jobstop, server_job)
		server_job = nil
	end
	server_job = vim.fn.jobstart(cmd, {
		detach = true,
		on_exit = function(_, code, _)
			log("INFO", string.format("serve on_exit code=%s", tostring(code)))
			if code ~= 0 and code ~= nil then
				server_job = nil
			end
		end,
		on_stderr = function(_, data, _)
			for _, line in ipairs(data or {}) do
				if line ~= "" then
					log("ERROR", "serve stderr: " .. line)
				end
			end
		end,
	})
	if not server_job or server_job <= 0 then
		vim.notify("opencode watcher: failed to start opencode serve", vim.log.levels.ERROR)
		log("ERROR", "failed to start opencode serve cmd=" .. table.concat(cmd, " "))
		if cb then
			cb(false)
		end
		return false
	end
	log("INFO", "serve job started id=" .. tostring(server_job))
	local timeout = 10000
	local interval = 500
	local waited = 0
	local timer = nil
	timer = vim.fn.timer_start(interval, function()
		waited = waited + interval
		if M.is_running(cfg.hostname, cfg.port) then
			if timer then
				vim.fn.timer_stop(timer)
			end
			log("INFO", string.format("server ready at %s:%d after %dms", cfg.hostname, cfg.port, waited))
			if cb then
				cb(true)
			end
			return
		end
		if waited >= timeout then
			if timer then
				vim.fn.timer_stop(timer)
			end
			log("WARN", string.format("server not ready within %dms at %s:%d", timeout, cfg.hostname, cfg.port))
			if cb then
				cb(false)
			end
		end
	end, { ["repeat"] = -1 })
	return true
end

function M.abort(dir, opts)
	dir = dir or require("opencode-watcher.watcher").resolve_dir()
	local norm = normalize_dir(dir)
	local cfg = get_cfg()
	opts = opts or {}
	local should_refresh = opts.refresh ~= false -- default true: abort should also refresh to new session
	local sid = sessions[norm]
	local job = active_runs[norm]
	local did_abort = false
	if job and job > 0 then
		pcall(vim.fn.jobstop, job)
		active_runs[norm] = nil
		log("INFO", string.format("aborted local run job %d for %s", job, norm))
		did_abort = true
	end
	if sid and sid ~= "" then
		local url = string.format("http://%s:%d/api/session/%s/interrupt", cfg.hostname, cfg.port, sid)
		vim.fn.jobstart({ "curl", "-s", "-X", "POST", url }, {
			on_exit = function(_, code, _)
				log("INFO", string.format("interrupt session %s -> curl exit %s", sid, tostring(code)))
			end,
		})
		log("INFO", string.format("requested interrupt for session %s dir %s", sid, norm))
		did_abort = true
		-- also refresh session so next request goes to new session (queued request fix)
		-- and delete the session on server to discard any queued prompts
		if should_refresh then
			M.clear_session(dir)
			local del_url = string.format("http://%s:%d/api/session/%s", cfg.hostname, cfg.port, sid)
			vim.fn.jobstart({ "curl", "-s", "-X", "DELETE", del_url }, {
				on_exit = function(_, code, _)
					log("INFO", string.format("delete session %s -> curl exit %s", sid, tostring(code)))
				end,
			})
			log("INFO", string.format("cleared and deleted session for %s after abort (refresh)", norm))
		end
		return true
	end
	local active_url = string.format("http://%s:%d/api/session/active", cfg.hostname, cfg.port)
	local out = vim.fn.system({ "curl", "-s", active_url })
	if out and out ~= "" then
		local ok, decoded = pcall(vim.json.decode, out)
		if ok and decoded and type(decoded) == "table" then
			local target = nil
			if decoded.sessionID then
				target = decoded.sessionID
			elseif decoded[1] and decoded[1].sessionID then
				target = decoded[1].sessionID
			elseif decoded[1] and decoded[1].id then
				target = decoded[1].id
			end
			if target then
				local url2 = string.format("http://%s:%d/api/session/%s/interrupt", cfg.hostname, cfg.port, target)
				vim.fn.jobstart({ "curl", "-s", "-X", "POST", url2 }, {})
				log("INFO", string.format("interrupt active session %s", target))
				if should_refresh then
					M.clear_session(dir)
					local del_url2 = string.format("http://%s:%d/api/session/%s", cfg.hostname, cfg.port, target)
					vim.fn.jobstart({ "curl", "-s", "-X", "DELETE", del_url2 }, {})
					log("INFO", string.format("deleted active session %s after abort", target))
				end
				return true
			end
		end
	end
	if should_refresh and sid then
		M.clear_session(dir)
	end
	return did_abort or job ~= nil
end

function M.get_session_id_for_tui(dir)
	dir = dir or require("opencode-watcher.watcher").resolve_dir()
	return get_session(dir)
end

function M.send(dir, content, cb)
	if not dir or dir == "" then
		dir = require("opencode-watcher.watcher").resolve_dir()
	end
	if not content or content:match("^%s*$") then
		log("WARN", "empty prompt not sending dir=" .. tostring(dir))
		if cb then
			cb(false)
		end
		return
	end
	local cfg = get_cfg()
	local function do_send(retry)
		local url = M.url(cfg.hostname, cfg.port)
		local preview2 = content:gsub("\n", "\\n"):sub(1, 200)
		log("INFO", string.format("send prompt dir=%s url=%s content_len=%d preview=%s", dir, url, #content, preview2))
		if not M.is_running(cfg.hostname, cfg.port) then
			vim.notify("opencode watcher: server not running at " .. url, vim.log.levels.ERROR)
			log("ERROR", "server not running at " .. url)
			if cb then
				cb(false)
			end
			return
		end
		local cmd = { "opencode", "run", "--attach", url, "--dir", dir, "--format", "json" }
		if cfg.auto_approve then
			table.insert(cmd, "--auto")
		end
		local norm_dir = normalize_dir(dir)
		-- harden: validate existing session still exists on server before reuse
		local existing = sessions[norm_dir]
		if existing and existing ~= "" then
			local check_url = string.format("http://%s:%d/api/session/%s", cfg.hostname, cfg.port, existing)
			local code_out =
				vim.fn.system({ "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "1", check_url })
			local code = vim.trim and vim.trim(code_out or "") or (code_out or ""):gsub("^%s+", ""):gsub("%s+$", "")
			if code ~= "200" then
				log("WARN", string.format("session %s not found on server (code %s), clearing", existing, tostring(code)))
				M.clear_session(dir)
				existing = nil
			end
		end
		local sess_model = session_models[norm_dir]
		local eff_model = sess_model and sess_model.id and (sess_model.providerID .. "/" .. sess_model.id) or cfg.model
		local eff_variant = sess_model and sess_model.variant or cfg.variant
		local eff_thinking = sess_model and sess_model.thinking or cfg.thinking
		if sess_model and sess_model.id and existing and existing ~= "" then
			M.switch_model(existing, sess_model)
		end
		if eff_model and eff_model ~= "" then
			table.insert(cmd, "--model")
			table.insert(cmd, eff_model)
		end
		if eff_variant and eff_variant ~= "" then
			table.insert(cmd, "--variant")
			table.insert(cmd, eff_variant)
		end
		if eff_thinking then
			table.insert(cmd, "--thinking")
		end
		if cfg.agent and cfg.agent ~= "" then
			table.insert(cmd, "--agent")
			table.insert(cmd, cfg.agent)
		end
		if existing and existing ~= "" then
			table.insert(cmd, "--session")
			table.insert(cmd, existing)
			log("INFO", string.format("reusing session %s for %s", existing, norm_dir))
		else
			log("INFO", string.format("no session yet for %s, will create new", norm_dir))
		end
		table.insert(cmd, content)
		log("INFO", string.format("sending prompt to %s dir=%s", url, dir))
		local pending_session = nil
		-- ensure watcher is running so loop is visible (dir is always auto git root else cwd)
		pcall(function()
			local watcher = require("opencode-watcher.watcher")
			local is_running = watcher.is_running and watcher.is_running() or false
			if not is_running then
				watcher.start()
				log("INFO", string.format("watcher started for %s", dir))
			end
		end)
		local run_job = vim.fn.jobstart(cmd, {
			cwd = dir,
			stdin = "null",
			on_stdout = function(_, data, _)
				for _, line in ipairs(data) do
					if line ~= "" then
						log("INFO", "run stdout: " .. line:sub(1, 500))
						if not sessions[norm_dir] or sessions[norm_dir] == "" then
							local ok, decoded = pcall(vim.json.decode, line)
							if ok and decoded then
								local sid = decoded.sessionID
									or (decoded.part and decoded.part.sessionID)
									or decoded.sessionId
									or decoded.id
								if sid and sid ~= "" then
									pending_session = sid
								end
							end
						end
					end
				end
			end,
			on_stderr = function(_, data, _)
				for _, line in ipairs(data) do
					if line ~= "" then
						log("ERROR", "run stderr: " .. line)
					end
				end
			end,
			on_exit = function(_, code, _)
				active_runs[norm_dir] = nil
				log("INFO", string.format("run on_exit code=%s", tostring(code)))
				if code == 0 then
					if pending_session and pending_session ~= "" then
						set_session(dir, pending_session)
					end
					log("INFO", "server run completed ok")
					if cb then
						cb(true)
					end
				else
					if code == 143 or code == 130 or code == 137 then
						log(
							"INFO",
							string.format("run aborted code=%s, keeping session %s", tostring(code), tostring(existing))
						)
						if cb then
							cb(false)
						end
						return
					end
					if not retry and existing and existing ~= "" then
						log(
							"WARN",
							string.format("run failed with session %s, clearing and retrying without session", existing)
						)
						M.clear_session(dir)
						do_send(true)
						return
					end
					log("ERROR", string.format("server run exited code %d", code))
					if cb then
						cb(false)
					end
				end
			end,
			pty = false,
		})
		if run_job and run_job > 0 then
			active_runs[norm_dir] = run_job
		end
		if not run_job or run_job <= 0 then
			vim.notify("opencode watcher: failed to start opencode run", vim.log.levels.ERROR)
			log("ERROR", "failed to start opencode run")
			if cb then
				cb(false)
			end
			return run_job
		end
		return run_job
	end
	if M.is_running(cfg.hostname, cfg.port) then
		do_send()
	else
		M.ensure_server(function(ok)
			if ok then
				do_send()
			else
				if cb then
					cb(false)
				end
			end
		end)
	end
end

function M.stop()
	if server_job and server_job > 0 then
		pcall(vim.fn.jobstop, server_job)
		server_job = nil
	end
end

-- per-session model picker (only for session, not global)
function M.pick_model(dir, arg)
	dir = dir or require("opencode-watcher.watcher").resolve_dir()
	dir = normalize_dir(dir)
	if arg and arg ~= "" then
		local prov, mod, var = arg:match("^([^/]+)/([^:]+):?(.*)$")
		if mod then
			local ref = { providerID = prov, id = mod, variant = var ~= "" and var or nil }
			set_session_model(dir, ref)
			local sid = get_session(dir)
			if sid then
				M.switch_model(sid, ref)
			end
			return
		end
	end
	local models = {}
	-- use `opencode models` to fill the list (as requested)
	local cli_out = vim.fn.system({ "opencode", "models" })
	if cli_out and cli_out ~= "" then
		for line in cli_out:gmatch("[^\r\n]+") do
			line = vim.trim(line)
			if line:match("/") then
				local prov, mod = line:match("^([^/]+)/(.+)$")
				if prov and mod then
					-- try to get variants for this model via API for thinking level
					local variants = {}
					-- fetch variants via API for this specific model if needed
					-- we can lazily fetch via `opencode models --verbose` or API, but for now try API
					local cfg2 = get_cfg()
					local vurl = string.format("http://%s:%d/api/model", cfg2.hostname, cfg2.port)
					local vout = vim.fn.system({ "curl", "-s", vurl })
					if vout and vout ~= "" then
						local ok2, dec2 = pcall(vim.json.decode, vout)
						if ok2 and dec2 and dec2.data then
							for _, mm in ipairs(dec2.data) do
								if mm.id == mod and mm.providerID == prov and mm.variants then
									variants = mm.variants
									break
								end
							end
						end
					end
					table.insert(
						models,
						{
							label = line .. (variants and next(variants) and " (*)" or ""),
							id = mod,
							providerID = prov,
							variants = variants,
						}
					)
				end
			end
		end
	end
	-- fallback to API if opencode models failed
	if #models == 0 then
		local cfg2 = get_cfg()
		local url = string.format("http://%s:%d/api/model", cfg2.hostname, cfg2.port)
		local out = vim.fn.system({ "curl", "-s", url })
		if out and out ~= "" then
			local ok, decoded = pcall(vim.json.decode, out)
			if ok and decoded and decoded.data then
				for _, m in ipairs(decoded.data) do
					if m.id and m.providerID then
						table.insert(
							models,
							{
								label = m.providerID
									.. "/"
									.. m.id
									.. (m.variants and next(m.variants) and " (*)" or ""),
								id = m.id,
								providerID = m.providerID,
								variants = m.variants,
							}
						)
					end
				end
			end
		end
	end
	if #models == 0 then
		vim.notify("opencode: no models found", vim.log.levels.ERROR)
		return
	end
	table.sort(models, function(a, b)
		return a.label < b.label
	end)
	table.insert(models, 1, { label = "(clear per-session model, use global)", id = "__clear__", providerID = "" })
	vim.ui.select(models, {
		prompt = "Select model for session " .. vim.fn.fnamemodify(dir, ":t") .. " (only this session):",
		format_item = function(item)
			return item.label
		end,
	}, function(choice)
		if not choice then
			return
		end
		if choice.id == "__clear__" then
			M.clear_session_model(dir)
			return
		end
		local var = nil
		if choice.variants and next(choice.variants) then
			local vars = {}
			for k, v in pairs(choice.variants) do
				table.insert(vars, k)
			end
			table.insert(vars, "(no variant)")
			vim.ui.select(vars, {
				prompt = "Select thinking level / variant for " .. choice.id .. ":",
				format_item = function(v)
					return v
				end,
			}, function(var_choice)
				if var_choice and var_choice ~= "(no variant)" then
					var = var_choice
				end
				local ref = { providerID = choice.providerID, id = choice.id, variant = var }
				set_session_model(dir, ref)
				local sid = get_session(dir)
				if sid then
					M.switch_model(sid, ref)
				end
			end)
		else
			local ref = { providerID = choice.providerID, id = choice.id, variant = nil }
			set_session_model(dir, ref)
			local sid = get_session(dir)
			if sid then
				M.switch_model(sid, ref)
			end
		end
	end)
end

return M
