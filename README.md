# opencode-watcher.nvim

<video src="assets/demo.mp4" controls autoplay loop muted playsinline width="100%"></video>

Neovim floating window that streams `opencode.log` human-friendly, filtered by project *basename* (shared directory). Keeps visible while `LOOP` active, auto-refreshes visible buffers when opencode formats a file.

`opencode-log-tail.sh` already shows `[basename]` at front `opencode-log-tail.sh:303` and filters by `TARGET_DIR` git-root/pwd `opencode-log-tail.sh:124`.

## Install (lazy.nvim)

```lua
{
  "me-imfhd/opencode-watcher.nvim",
  config = function()
    require("opencode-watcher").setup({
      dir = nil, -- nil = auto (git root else cwd), or "opencode-watcher.nvim" basename, or "/full/path"
      position = "top-right", -- or "bottom-right"
      width = 50,
      height = 12,
      border = "rounded",
      exclude = "MSG,SYNC,LLM,PERM:bash,read,edit", -- hide noisy eval; use "PERM" to hide all perm, "LLM" etc.
      lines = 0, -- 0 = live only, 50 = with history
      auto_refresh = true,
      hide_delay = 2500,
    })
  end,
}
```

## How it works

* `watcher.lua` resolves `dir`:
  * `dir=nil` → `git rev-parse --show-toplevel` else `pwd` `watcher.lua:resolve_dir`
  * `dir="opencode-watcher.nvim"` (no `/`) → tries git root basename match, then `find $HOME/dev -name <basename>` `watcher.lua:resolve_dir`, fallback `cwd`
  * `dir="/full/path"` → used directly (canonicalized `opencode-log-tail.sh:124`)

* Starts `jobstart({ tail_script, "--dir", dir, "--lines", "0", "--exclude", exclude })` `watcher.lua:start` (`tail -F --retry` `opencode-log-tail.sh:800`).

* Parses each pretty line `18:25:10 [basename] TAG  msg` `watcher.lua:on_stdout`:
  * `LOOP loop step=0` → `loop_active=true`, `ui.cancel_hide()`, `ui.ensure_window()` `watcher.lua:is_loop_active`
  * `LOOP exit` / `exiting loop` → `loop_active=false`, `ui.hide_delayed()` `watcher.lua:hide_delayed`
  * While `loop_active` keeps window visible until exit + `hide_delay`.

* Human view `ui.lua:humanize`:
  * `FILE touching /long/path/file.sh` → `󰈙 touching file.sh`
  * `LOOP step=0` → `󰑃 loop started`, `exit` → `loop finished`
  * `PERM perm=bash` → `󰌾 perm bash:opencode-log-tail.sh`
  * `LLM stream` → `󰧑 LLM stream`
  * Truncates `>38` to `…`.

* Auto refresh `ui.lua:refresh_visible_buffers` on `FILE formatting` `ui.lua:push_raw`:
  ```lua
  vim.cmd("silent! checktime")
  -- for each visible win with !modified, e!
  ```

## Commands

```
:OpencodeWatcherStart
:OpencodeWatcherStop
:OpencodeWatcherRestart
:OpencodeWatcherToggle
:OpencodeWatcherClear
```

## Manual test

```vim
:lua require("opencode-watcher").setup({dir="opencode-watcher.nvim", position="bottom-right"})
" trigger opencode formatting a file, buffer should reload
```

## Files

* `opencode-log-tail.sh:1` — pretty tail, `[basename]` front `opencode-log-tail.sh:303`, `TARGET_DIR` filter
* `opencode-db-query.sh:1` — `sessions`/`messages` (12-word preview)/`edits` (`+add -del`)/`touches`/`stats`
* `lua/opencode-watcher/*` — nvim integration

## Tail script flags used

`--dir DIR` `opencode-log-tail.sh:24` (auto git root/pwd), `--lines N`, `--exclude TYPES` (`PERM:eval`, `bash`, `read` `opencode-log-tail.sh:60`), `--raw` / `--raw=MSG` `opencode-log-tail.sh:60`.

## Disclaimer
This is a personal project, heavily written by AI, and checked by me.
