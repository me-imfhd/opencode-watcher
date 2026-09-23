# opencode-watcher.nvim

Neovim watcher for `opencode` - streams `opencode.log` human-friendly per project, shows agent progress, handles inline edits via `opencode serve`.

## Viewing Opencode Events in Neovim sharing same directory
<video src="https://github.com/user-attachments/assets/d1c2ef24-703c-4ac4-ad03-692d0d4c7c66" controls autoplay loop muted playsinline width="100%"></video>
See [Events per Directory](#1-events-per-directory) for [How it works](#how-it-works)

## Send quick inline requests to opencode with visual selection
Use `<C-.>` to yank the visual selected text to over opencode://prompt buffer
Save the buffer `:w` to send the request
<video src="https://github.com/user-attachments/assets/3fdba692-b867-4c86-aacd-8f4e550f94eb" controls autoplay loop muted playsinline width="100%"></video>
See [Inline Edits](#2-inline-edits) for [How it works](#how-it-works)

> For author's original notes and design rationale, see [`author_notes.txt`](./author_notes.txt).

## Goals

1.  **Utilize `opencode` events** - touching/editing files, tool execution, looping, permission stuck, failure, progress across tasks, buffer refresh on format.
2.  **Inline edits** - visual yank via `getregion()`, `File: line` header, vsplit prompt, save to send, session reuse per project.
3.  `:OpencodeWatcherLogs` - prettified live log per project (persistent terminal).
4.  `:OpencodeRefresh` - clear logs + new session.
5.  `:OpencodeModel` - change model per session.
6.  `:OpencodeDebugLogs` - plugin debug log.

## Install (lazy.nvim)

```lua
{
  "me-imfhd/opencode-watcher.nvim",
  config = function()
    require("opencode-watcher").setup({
      exclude = "MSG,SYNC,LLM,PERM:bash,read,edit",
      prompt = {
        key = "<C-.>",
        win = "vsplit",
        instructions = "Keep loop/tool calls as few as possible. Just focus on fixing the task at hand and nothing else. No need to explain when the task is done. You are expected to give results fast, short and accurate, not long, unless specified in the prompt.",
        server = { auto_approve = true },
      },
    })
  end,
}
```

All other options default: `debug=false`, floating `top-right 42x12`, `lines=0` live, `hide_delay=2500`, `max_lines=100`, `server 127.0.0.1:4096`.

## Options

```lua
require("opencode-watcher").setup({
  debug = false, -- false: only INFO/WARN/ERROR to stdpath("log")/opencode-watcher-debug.log
  position = "top-right", -- "bottom-right"
  width = 42, height = 12, border = "rounded",
  tail_script = nil, -- auto <plugin>/opencode-log-tail.sh
  exclude = nil, -- nil = show all; e.g. "MSG,SYNC,LLM,PERM:bash" hide noisy
  lines = 0, -- 0 live only, 50 with history
  hide_delay = 2500, -- ms after LOOP exit
  max_lines = 100,
  prompt = {
    enabled = true,
    key = "<C-.>", -- n: open, x: yank selection
    win = "vsplit", -- vsplit only
    vsplit = { width = 60 },
    close_on_submit = true,
    clear_on_submit = true,
    instructions = "Keep loop...", -- prepended to every prompt
    server = {
      hostname = "127.0.0.1", port = 4096,
      auto_approve = true, -- --auto
      model = nil, agent = nil, timeout_ms = 30000,
    },
  },
  logger = { level = "INFO", path = nil },
  icons = { BOOT="󰚩", FILE="󰈙", PERM="󰌾", LLM="󰧑", LOOP="󰑃", ... },
  highlights = { BOOT="Special", FILE="Directory", LOOP="Statement", ERR="ErrorMsg", ... },
})
```

## How it works

### 1. Events per directory

*   Source `~/.local/share/opencode/log/opencode.log` JSON lines (`timestamp`, `level`, `message`, `directory`/`cwd`/`file`/`session.id`).
*   Dir resolved auto `git rev-parse --show-toplevel` else `pwd` `watcher.lua:resolve_dir` same as `opencode-log-tail.sh:40`.
*   `opencode-log-tail.sh:127` classifies into TAGS: `BOOT WATCH CFG FILE SYNC LLM PERM LOOP MSG SESS CMD EVT CLEAN MISC LOG ERR RAW`
    *   `PERM` `eval: perm=<type> pat=<pattern> -> ask|allow` (`read/write/edit/bash/grep/glob`), `asking: perm= patterns=`, `replied` `opencode-log-tail.sh:275`
    *   `FILE` `touching: file=`, `formatting: file=` `opencode-log-tail.sh:242`
    *   `LOOP` `loop: started` (`step=0`), `loop: step=<n>`, `exit/completed` `opencode-log-tail.sh:294`
    *   All events show `[basename]` at front `opencode-log-tail.sh:106`, filtered `LINE_DIR == TARGET_DIR` `opencode-log-tail.sh:96`. Multiple sessions sharing same dir interleave - no per-session filter by design.
*   `watcher.lua:85` starts `jobstart({ tail_script, "--dir", dir, "--lines", "0" })` (`tail -F --retry` `opencode-log-tail.sh:341`), optional `--exclude`.
*   `watcher.lua:on_stdout` `watcher.lua:94` handles tags:
    *   `LOOP step=0` -> `loop_active=true`, `ui.cancel_hide()`, `ui.ensure_window()`
    *   `LOOP exit` -> `loop_active=false`, `ui.hide_delayed()` 2500ms
    *   `ERR/aborted/cancelled/stream error` -> pin `ui.cancel_hide()` + `ensure_window()` (no auto-hide) `watcher.lua:99`
    *   Otherwise non-loop -> `ensure_window()` + `idle_hide_timer 5000ms` `watcher.lua:146` then `ui.hide()` which clears `ui.lua:82`.
*   `ui.lua:humanize` `ui.lua:224` maps to icons `󰚩 󰈙 󰌾 󰧑 󰑃` and truncates word-aware `>30` to `…`. `--exclude` opts out `MSG`/`SYNC`/`LLM` duplicates.
*   `ui.lua:push_raw` `ui.lua:372` refreshes visible buffers on `FILE formatting` or `reverting/unreverting/restore` (debounced 150ms) via `checktime` + `e!` for `!modified` windows `ui.lua:186`.

Usage: `:OpencodeWatcherLogs` live detailed pretty log in terminal (persistent), floating window ephemeral cleaner view; filter by directory + `--exclude` for cleaner view.

### 2. Inline edits

*   `prompt.lua:233` `getregion()` visual selection (fallback to `nvim_buf_get_lines`), `capture_context()` `prompt.lua:363` adds `File: rel:line` + fenced ` ```ft` header for file buffers (quickfix/trouble stays raw by design).
*   `Ctrl+.` `init.lua:90` `prompt.open_or_yank(false)` / `(true)` -> `vsplit 60` `prompt.lua:165` (`opencode://prompt` `acwrite` `prompt.lua:17`), `startinsert` `prompt.lua:219`.
*   Type instructions, `:w` (`BufWriteCmd`) `prompt.lua:33` triggers `M.submit()` `prompt.lua:491` which saves other `!modified` file bufs `silent! write`, prepends `instructions` `prompt.lua:526`, then `server.send` `server.lua:381`.
*   `server.lua:229` `ensure_server()` checks `http://127.0.0.1:4096/doc` else `opencode serve --port 4096 --hostname 127.0.0.1 --print-logs` (`detach` `server.lua:251`, poll 10s). Validates existing session via `GET /api/session/<id>` `server.lua:413` then `opencode run --attach http://host:port --dir <dir> --format json --auto --session <id> <prompt>` `server.lua:405`, captures `sessionID` from stdout JSON `server.lua:477` -> `stdpath("data")/sessions.json` per `normalize_dir` `server.lua:34` for reuse, `active_runs` tracked for `abort`.
*   When opencode executes, it streams events into `opencode.log` which watcher visualizes and refreshes buffers.

DB note: `session`/`message`/`part` tables (`part.json: type step-start/tool/text, state.input.filepath, metadata.diff`), useful for `:OpencodeSession` `opencode -s "id"` inspection.

## Commands

```
:OpencodeWatcherStart        start watcher (tail filtered by git root)
:OpencodeWatcherStop         stop watcher
:OpencodePrompt              open prompt vsplit (Ctrl-. to yank)
:OpencodeWatcherLogs [N]     pretty log in terminal --lines N (default 50) `opencode-log-tail.sh --dir <project> --lines N`
:OpencodeWatcherDebugLogs    plugin debug log (stdpath("log")/opencode-watcher-debug.log)
:OpencodeRefresh             abort loop + clear session + clear logs + clear prompt (next prompt new session)
:OpencodeAbort               abort looping agent for project (also new session)
:OpencodeSession             echo `opencode -s "id"` for inline session (yanks to +)
:OpencodeModel [provider/model:variant]  change model per session only
```

Debug logs (when `debug=false` only `INFO/WARN/ERROR` via `vim.notify` errors):
```
-- plugin debug:  stdpath("log")/opencode-watcher-debug.log  (~/.local/state/nvim/...)
-- opencode log:  ~/.local/share/opencode/log/opencode.log
-- pretty: opencode-log-tail.sh --dir <project> --lines 50 --exclude MSG,SYNC,LLM
-- sessions: curl http://127.0.0.1:4096/api/session?directory=<project>
```

## Files

*   `opencode-log-tail.sh:1` - pretty tail, `[basename]` front, dir filter
*   `lua/opencode-watcher/{watcher,ui,prompt,server,config,logger}.lua` - nvim integration

## Tail script flags

`--dir DIR` (auto git root/pwd), `--lines N`, `--exclude TYPES` (`PERM:eval`, `bash`, `read` etc `opencode-log-tail.sh:60`), `--raw` / `--raw=MSG` `opencode-log-tail.sh:60`.

## Disclaimer

This project was assisted by AI
