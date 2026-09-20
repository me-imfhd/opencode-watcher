#!/usr/bin/env bash
# opencode-log-tail.sh — tail & pretty-print opencode.log
set -u
LOG_DEFAULT="$HOME/.local/share/opencode/log/opencode.log"
if [[ -n "${XDG_DATA_HOME:-}" ]]; then XDG_LOG="$XDG_DATA_HOME/opencode/log/opencode.log"; else XDG_LOG=""; fi
RAW_ALL=0; RAW_TYPES=""; LINES=50; FOLLOW=1; LOG=""; EXCLUDE_TYPES=""; TARGET_DIR=""; SHOW_ALL=0
_append_csv() { local var="$1" val="$2"; [[ -z "$val" ]] && return; if [[ -z "${!var}" ]]; then printf -v "$var" '%s' "$val"; else printf -v "$var" '%s,%s' "${!var}" "$val"; fi; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw) if [[ $# -gt 1 && "$2" != -* && "$2" == *","* ]]; then _append_csv RAW_TYPES "$2"; shift 2; elif [[ $# -gt 1 && "$2" != -* && "$2" =~ ^[A-Za-z,]+$ && "$2" != *.log && "$2" != /* ]]; then case "${2^^}" in BOOT|WATCH|CFG|FILE|SYNC|LLM|PERM|LOOP|MSG|SESS|CMD|EVT|CLEAN|MISC|LOG|ERR|RAW) _append_csv RAW_TYPES "$2"; shift 2 ;; *) RAW_ALL=1; shift ;; esac; else RAW_ALL=1; shift; fi ;;
    --raw=*) _append_csv RAW_TYPES "${1#*=}"; shift ;;
    --raw-types|--raw-type|--raw-tags|--raw-tag) _append_csv RAW_TYPES "$2"; shift 2 ;;
    --raw-types=*|--raw-type=*|--raw-tags=*|--raw-tag=*) _append_csv RAW_TYPES "${1#*=}"; shift ;;
    --no-follow) FOLLOW=0; shift ;;
    -n|--lines) LINES="$2"; shift 2 ;;
    --lines=*) LINES="${1#*=}"; shift ;;
    --exclude) _append_csv EXCLUDE_TYPES "$2"; shift 2 ;;
    --exclude=*) _append_csv EXCLUDE_TYPES "${1#*=}"; shift ;;
    --exclude-types|--exclude-type|--exclude-tags|--exclude-tag) _append_csv EXCLUDE_TYPES "$2"; shift 2 ;;
    --exclude-types=*|--exclude-type=*|--exclude-tags=*|--exclude-tag=*) _append_csv EXCLUDE_TYPES "${1#*=}"; shift ;;
    --dir|--directory|--filter-dir|--filter-directory) TARGET_DIR="$2"; shift 2 ;;
    --dir=*|--directory=*|--filter-dir=*|--filter-directory=*) TARGET_DIR="${1#*=}"; shift ;;
    --all) SHOW_ALL=1; TARGET_DIR=""; shift ;;
    -h|--help) echo "Usage: $0 [--raw] [--no-follow] [--lines N] [--exclude TYPES] [--dir DIR] [logfile]"; echo "  --raw                also print raw line (dim) after pretty line (all tags)"; echo "  --raw=TYPES          only print raw for given tags (e.g. --raw=MSG,LLM)"; echo "  --no-follow          cat existing lines and exit (no tail -F)"; echo "  --lines N            initial lines to show (default 50)"; echo "  --exclude TYPES      comma-separated tags to hide (e.g. PERM,LLM or PERM:eval)"; echo "                       PERM sub-types: eval, asking, replied, bash, read, edit, write, grep, glob, etc. (e.g. --exclude bash or --exclude perm:bash)"; echo "  --dir DIR            only show logs for DIR (manual override). Default: current git root, else pwd."; exit 0 ;;
    --) shift; break ;;
    -*) echo "unknown flag: $1" >&2; exit 1 ;;
    *) LOG="$1"; shift ;;
  esac
done
IFS=',' read -ra EXCLUDE_TAGS_ARRAY <<< "$EXCLUDE_TYPES"
_tmp=(); for _e in "${EXCLUDE_TAGS_ARRAY[@]}"; do _e=$(echo "$_e" | xargs); [[ -z "$_e" ]] && continue; _tmp+=("$(echo "$_e" | tr '[:lower:]' '[:upper:]')"); done; EXCLUDE_TAGS_ARRAY=("${_tmp[@]}")
IFS=',' read -ra RAW_TAGS_ARRAY <<< "$RAW_TYPES"
_tmp=(); for _e in "${RAW_TAGS_ARRAY[@]}"; do _e=$(echo "$_e" | xargs); [[ -z "$_e" ]] && continue; _tmp+=("$(echo "$_e" | tr '[:lower:]' '[:upper:]')"); done; RAW_TAGS_ARRAY=("${_tmp[@]}")
[[ ${#RAW_TAGS_ARRAY[@]} -gt 0 ]] && RAW_ALL=0
unset _e _tmp; unset -f _append_csv
if [[ $RAW_ALL -eq 1 || ${#RAW_TAGS_ARRAY[@]} -gt 0 ]]; then RAW_ENABLED=1; else RAW_ENABLED=0; fi
if [[ $SHOW_ALL -eq 1 ]]; then TARGET_DIR=""
else
  if [[ -z "$TARGET_DIR" ]]; then
    if _git_root=$(git rev-parse --show-toplevel 2>/dev/null); then TARGET_DIR="$_git_root"
    else TARGET_DIR="$(pwd -P 2>/dev/null || pwd)"; fi
  elif [[ "$TARGET_DIR" == "all" || "$TARGET_DIR" == "*" ]]; then TARGET_DIR=""
  else
    if [[ -d "$TARGET_DIR" ]]; then TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd -P)"
    elif command -v realpath >/dev/null 2>&1; then TARGET_DIR="$(realpath -m "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")"; fi
  fi
fi
[[ -n "$TARGET_DIR" && "$TARGET_DIR" != "/" ]] && TARGET_DIR="${TARGET_DIR%/}"
if [[ -n "$TARGET_DIR" ]]; then TARGET_BASENAME="${TARGET_DIR##*/}"; [[ -z "$TARGET_BASENAME" ]] && TARGET_BASENAME="/"; else TARGET_BASENAME=""; fi
if [[ -z "$LOG" ]]; then
  if [[ -f "$LOG_DEFAULT" ]]; then LOG="$LOG_DEFAULT"
  elif [[ -n "$XDG_LOG" && -f "$XDG_LOG" ]]; then LOG="$XDG_LOG"
  else LOG="$LOG_DEFAULT"; fi
fi
if [[ ! -e "$LOG" ]]; then echo "log not found: $LOG" >&2; exit 1; fi
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'; C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'
else C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_MAGENTA=""; C_CYAN=""; C_BOLD=""; fi
CUR_DIR=""
pretty() {
  local tag="$1" col="$2" msg="$3"
  if [[ ${#EXCLUDE_TAGS_ARRAY[@]} -gt 0 ]]; then
    local _up="${tag^^}"
    for _ex in "${EXCLUDE_TAGS_ARRAY[@]}"; do
      [[ "$_up" == "$_ex" ]] && return
      # allow sub-type filtering for PERM: eval/asking/replied via --exclude eval, --exclude perm:eval, etc.
      # and inner perm types like bash/read/edit via --exclude bash, --exclude perm:bash, --exclude read etc.
      if [[ "$_up" == "PERM" ]]; then
        case "$_ex" in
          EVAL|EVALUATED|PERM:EVAL|PERM:EVALUATED)
            [[ "$msg" == "eval  perm="* ]] && return
            ;;
          ASK|ASKING|PERM:ASK|PERM:ASKING)
            [[ "$msg" == "asking"* ]] && return
            ;;
          REPLY|REPLIED|PERM:REPLY|PERM:REPLIED)
            [[ "$msg" == "replied"* ]] && return
            ;;
        esac
        # inner perm types for evaluated: bash, read, edit, write, grep, glob, etc.
        if [[ "$msg" == "eval  perm="* ]]; then
          local _inner=$(echo "$msg" | grep -o 'perm=[^ ]*' | head -n1 | cut -d= -f2 | tr '[:lower:]' '[:upper:]')
          if [[ -n "$_inner" ]]; then
            # match --exclude bash, --exclude perm:bash, --exclude read etc.
            if [[ "$_ex" == "$_inner" ]] || [[ "$_ex" == "PERM:$_inner" ]]; then
              return
            fi
          fi
          unset _inner
        fi
      fi
    done
    unset _up _ex
  fi
  local dir="${LINE_DIR:-${CUR_DIR:-?}}"
  if [[ -n "${TARGET_DIR:-}" ]]; then
    [[ "$dir" == "?" ]] && return
    [[ "$dir" != "$TARGET_DIR" && "$dir" != "$TARGET_DIR"/* ]] && return
  fi
  local base="${dir##*/}"
  [[ -z "$base" ]] && base="$dir"
  local lvl_mark=""
  if [[ "$LVL" == "ERROR" ]]; then lvl_mark="${C_RED}!${C_RESET} "
  elif [[ "$LVL" == "WARN" ]]; then lvl_mark="${C_YELLOW}!${C_RESET} "
  fi
  if [[ "$msg" == *"dir="* ]]; then
    printf "%s %b%-14s%b %b%-5s%b %s%s\n" "$TS" "$C_CYAN" "[$base]" "$C_RESET" "$col" "$tag" "$C_RESET" "${lvl_mark}${msg}" ""
  else
    printf "%s %b%-14s%b %b%-5s%b %s\n" "$TS" "$C_CYAN" "[$base]" "$C_RESET" "$col" "$tag" "$C_RESET" "${lvl_mark}${msg}"
  fi
  if [[ ${RAW_ENABLED:-0} -eq 1 ]]; then
    local _should_raw=0
    if [[ ${RAW_ALL:-0} -eq 1 ]]; then _should_raw=1
    else
      local _up2="${tag^^}"
      for _rt in "${RAW_TAGS_ARRAY[@]}"; do
        [[ "$_up2" == "$_rt" ]] && _should_raw=1 && break
      done
      unset _up2 _rt
    fi
    if [[ $_should_raw -eq 1 && -n "${CURRENT_RAW_LINE:-}" ]]; then
      printf "  %b%s%b\n" "$C_DIM" "$CURRENT_RAW_LINE" "$C_RESET"
    fi
    unset _should_raw
  fi
}
handle_line() {
  local line="$1"
  CURRENT_RAW_LINE="$line"
  if [[ "$line" =~ timestamp=([^[:space:]]+) ]]; then
    local raw_ts="${BASH_REMATCH[1]}"
    TS="${raw_ts#*T}"
    TS="${TS%%.*}"
    TS="${TS%%Z*}"
  else
    TS="??:??:??"
  fi
  if [[ "$line" =~ level=([^[:space:]]+) ]]; then
    LVL="${BASH_REMATCH[1]}"
  else
    LVL="INFO"
  fi
  local msg=""
  if [[ "$line" =~ message=\"([^\"]+)\" ]]; then
    msg="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ message=([^[:space:]]+) ]]; then
    msg="${BASH_REMATCH[1]}"
  else
    pretty "RAW" "$C_DIM" "$line"
    return
  fi
  kv() {
    local key="$1"
    if [[ "$line" =~ $key=\"([^\"]+)\" ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
    elif [[ "$line" =~ $key=([^[:space:]]+) ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
    fi
  }
  if [[ "$msg" == "evaluated" || "$msg" == "asking" || "$msg" == "replied" ]]; then
    LINE_DIR="${CUR_DIR:-?}"
  else
    _line_nopat=$(echo "$line" | sed -E 's/ pattern="[^"]*"//g; s/ pattern=[^ ]*//g')
    _kv_nopat() {
      local key="$1"
      if [[ "$_line_nopat" =~ $key=\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
      elif [[ "$_line_nopat" =~ $key=([^[:space:]]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
      fi
    }
    LINE_DIR=""
    _d=$(_kv_nopat directory)
    if [[ -n "$_d" ]]; then
      LINE_DIR="$_d"
      CUR_DIR="$_d"
    else
      _d=$(_kv_nopat cwd)
      if [[ -n "$_d" ]]; then
        LINE_DIR="$_d"
        CUR_DIR="$_d"
      else
        _d=$(kv file)
        if [[ -n "$_d" ]]; then
          if [[ -n "$CUR_DIR" && "$CUR_DIR" != "?" ]]; then
            LINE_DIR="$CUR_DIR"
          else
            LINE_DIR="${_d%/*}"
            [[ "$LINE_DIR" == "$_d" ]] && LINE_DIR="."
            [[ -z "$CUR_DIR" ]] && CUR_DIR="$LINE_DIR"
          fi
        else
          _d=$(kv path)
          if [[ -n "$_d" ]]; then
            if [[ -n "$CUR_DIR" && "$CUR_DIR" != "?" ]]; then
              LINE_DIR="$CUR_DIR"
            else
              LINE_DIR="${_d%/*}"
              [[ "$LINE_DIR" == "$_d" ]] && LINE_DIR="."
            fi
          else
            _d=$(kv arg)
            if [[ -n "$_d" ]]; then
              if [[ -n "$CUR_DIR" && "$CUR_DIR" != "?" ]]; then
                LINE_DIR="$CUR_DIR"
              else
                LINE_DIR="${_d%/*}"
                [[ "$LINE_DIR" == "$_d" ]] && LINE_DIR="."
              fi
            else
              _d=$(kv resolved)
              if [[ -n "$_d" ]]; then
                if [[ -n "$CUR_DIR" && "$CUR_DIR" != "?" ]]; then
                  LINE_DIR="$CUR_DIR"
                else
                  LINE_DIR="${_d%/*}"
                  [[ "$LINE_DIR" == "$_d" ]] && LINE_DIR="."
                fi
              else
                LINE_DIR="${CUR_DIR:-?}"
              fi
            fi
          fi
        fi
      fi
    fi
    unset _line_nopat 2>/dev/null || true
    unset -f _kv_nopat 2>/dev/null || true
  fi
  case "$msg" in
    "creating instance") pretty "BOOT" "$C_CYAN" "creating instance" ;;
    "fromDirectory") pretty "BOOT" "$C_CYAN" "fromDirectory" ;;
    "bootstrapping") pretty "BOOT" "$C_CYAN" "bootstrapping" ;;
    "watcher backend")
      local b p
      b=$(kv backend); p=$(kv platform)
      pretty "WATCH" "$C_BLUE" "watcher backend    backend=${b:-?} platform=${p:-?}" ;;
    "booting location services")
      local w; w=$(kv workspaceID)
      pretty "BOOT" "$C_CYAN" "location services  workspace=${w:-?}" ;;
    "all LSPs are disabled"|"all formatters are disabled") pretty "CFG" "$C_DIM" "$msg" ;;
    "touching file") local f; f=$(kv file); pretty "FILE" "$C_YELLOW" "touching  ${f:-?}" ;;
    "formatting") local f; f=$(kv file); pretty "FILE" "$C_YELLOW" "formatting ${f:-?}" ;;
    "resolved path") local a r; a=$(kv arg); r=$(kv resolved); pretty "FILE" "$C_YELLOW" "resolved  ${a:-?} -> ${r:-?}" ;;
    "loading tui config"|"applying tui config"|"project copy refresh started"|"project copy refresh done"|"removing gitignored files from snapshot"|"full sync"|"creating share"|"running migration")
      local extra=""
      if [[ "$line" =~ projectID=([^[:space:]]+) ]]; then extra=" project=${BASH_REMATCH[1]}"; fi
      if [[ "$line" =~ updated=([^[:space:]]+) ]]; then extra+=" updated=${BASH_REMATCH[1]}"; fi
      pretty "SYNC" "$C_DIM" "$msg$extra" ;;
    "shell tool using shell") local sh; sh=$(kv shell); pretty "CFG" "$C_DIM" "shell  ${sh:-?}" ;;
    "llm runtime selected")
      local rt prov mod; rt=$(kv llm.runtime); prov=$(kv llm.provider); mod=$(kv llm.model)
      [[ -z "$prov" ]] && prov=$(kv providerID)
      [[ -z "$mod" ]] && mod=$(kv modelID)
      pretty "LLM" "$C_MAGENTA" "runtime ${rt:-?} provider=${prov:-?} model=${mod:-?}" ;;
    "stream error")
      local prov mod err; prov=$(kv providerID); mod=$(kv modelID); local err_msg=""
      if [[ "$line" =~ error\.error=\"([^\"]+)\" ]]; then err_msg="${BASH_REMATCH[1]}"
      elif [[ "$line" =~ error=([^[:space:]]+) ]]; then err_msg="${BASH_REMATCH[1]}"; fi
      pretty "ERR" "$C_RED" "stream error provider=${prov:-?} model=${mod:-?} ${err_msg:0:120}" ;;
    "event connected"|"event disconnected"|"global event connected"|"global event disconnected") pretty "EVT" "$C_DIM" "$msg" ;;
    "disposing instance"|"disposing all instances"|"cleanup failed"|"failed to load plugin"|"failed to sync share"|"failed to add snapshot files"|"duplicate skill name"|"failed to initialize fff"|"Failed to fetch models.dev"|"subtask execution failed") pretty "EVT" "$C_DIM" "$msg" ;;
    "file did not exist in snapshot, deleting") local f; f=$(kv file); pretty "SYNC" "$C_YELLOW" "delete missing  ${f:-?}" ;;
    init)
      if [[ "$line" =~ count=([^[:space:]]+) ]]; then pretty "BOOT" "$C_CYAN" "init  count=${BASH_REMATCH[1]}"
      else pretty "BOOT" "$C_CYAN" "init"; fi ;;
    loading) local p; p=$(kv path); pretty "CFG" "$C_DIM" "loading  ${p:-?}" ;;
    created)
      local sid slug title; sid=$(kv id); slug=$(kv slug); title=$(kv title)
      [[ -z "$title" && "$line" =~ title=\"([^\"]+)\" ]] && title="${BASH_REMATCH[1]}"
      pretty "SESS" "$C_GREEN" "created  ${slug:-?} (${sid:-?}) title=${title:-?}" ;;
    command) local sess cmd ag; sess=$(kv session.id); cmd=$(kv command); ag=$(kv agent); pretty "CMD" "$C_GREEN" "command=${cmd:-?} session=${sess:-?} agent=${ag:-?}" ;;
    asking) local qid perm pats; qid=$(kv id); perm=$(kv permission); pats=$(kv patterns); [[ -z "$perm" ]] && perm=$(kv permission); pretty "PERM" "$C_YELLOW" "asking  id=${qid:-?} perm=${perm:-?} patterns=${pats:-?}" ;;
    replied) local qid ans; qid=$(kv requestID); [[ -z "$qid" ]] && qid=$(kv id); if [[ "$line" =~ answers=([^[:space:]]+) ]]; then ans="${BASH_REMATCH[1]}"; else ans=""; fi; pretty "PERM" "$C_GREEN" "replied id=${qid:-?} ${ans:0:80}" ;;
    evaluated) local perm pat; perm=$(kv permission); pat=$(kv pattern); local a_perm a_pat a_act; a_perm=$(kv action.permission); a_pat=$(kv action.pattern); a_act=$(kv action.action)
      # for pat that looks like a file path, show only basename + extension
      if [[ "$pat" == *"/"* ]]; then
        if [[ "$pat" != *" "* ]]; then
          pat="${pat##*/}"
        else
          _first_path=$(echo "$pat" | grep -oE '[^ ]*/[^ ]*' | head -n1)
          if [[ -n "$_first_path" ]]; then
            _base="${_first_path##*/}"
            [[ -n "$_base" ]] && pat="${pat//$_first_path/$_base}"
          fi
          unset _first_path _base
        fi
      fi
      [[ "$perm" == "bash" && ${#pat} -gt 60 ]] && pat="${pat:0:60}..."
      # yellow for edit needing permission (ask)
      local col="$C_DIM"
      if [[ "$perm" == "edit" || "$a_act" == "ask" ]]; then col="$C_YELLOW"; fi
      pretty "PERM" "$col" "eval  perm=${perm:-?} pat=${pat:-?} -> ${a_act:-?} (${a_perm:-?}:${a_pat:-?})" ;;
    loop) local sess step; sess=$(kv session.id); step=$(kv step); pretty "LOOP" "$C_DIM" "loop  session=${sess:-?} step=${step:-?}" ;;
    process)
      local sess mid; sess=$(kv session.id); mid=$(kv messageID)
      # handle error returned by opencode or aborted
      if [[ "$line" =~ error=Aborted || "$line" =~ error\.error= ]]; then
        local err; err=$(kv error); [[ -z "$err" ]] && err=$(echo "$line" | grep -o 'error\.error="[^"]*"' | head -n1 | cut -d'"' -f2)
        [[ -z "$err" ]] && err="Aborted"
        # truncate long error
        [[ ${#err} -gt 80 ]] && err="${err:0:80}..."
        pretty "ERR" "$C_RED" "aborted  session=${sess:-?} msg=${mid:-?} err=${err}"
      elif [[ "$LVL" == "ERROR" ]]; then
        pretty "ERR" "$C_RED" "process  session=${sess:-?} msg=${mid:-?} [error]"
      else
        pretty "MSG" "$C_DIM" "process  session=${sess:-?} msg=${mid:-?}"
      fi ;;
    stream) local prov mod sess small ag mode; prov=$(kv providerID); mod=$(kv modelID); sess=$(kv session.id); small=$(kv small); ag=$(kv agent); mode=$(kv mode); pretty "LLM" "$C_MAGENTA" "stream provider=${prov:-?} model=${mod:-?} sess=${sess:-?} agent=${ag:-?} mode=${mode:-?} small=${small:-?}" ;;
    tracking) local h cwd git; h=$(kv hash); cwd=$(kv cwd); git=$(kv git); pretty "SYNC" "$C_DIM" "tracking hash=${h:0:12} cwd=${cwd:-?}" ;;
    cleanup) local prune; prune=$(kv prune); pretty "CLEAN" "$C_DIM" "cleanup prune=${prune:-?}" ;;
    cancel|cancel\') local sess; sess=$(kv session.id); pretty "ERR" "$C_YELLOW" "cancelled by user  session=${sess:-?}" ;;
    reverting|restore|unreverting|upgraded|initialized|rejected|file) pretty "MISC" "$C_DIM" "$msg  ${line#*message=}" ;;
    "exiting loop") local sess; sess=$(kv session.id); pretty "LOOP" "$C_BLUE" "exit  session=${sess:-?}" ;;
    *) local extra=""; local f; f=$(kv file); [[ -n "$f" ]] && extra+=" file=$f"; if [[ "$LVL" == "ERROR" ]]; then pretty "ERR" "$C_RED" "$msg$extra"; else pretty "LOG" "$C_DIM" "$msg$extra"; fi ;;
  esac
}
if [[ -s "$LOG" ]]; then
  _total=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  if [[ "$_total" -gt "$LINES" ]]; then
    _prefix_lines=$((_total - LINES))
    _seed=$(head -n "$_prefix_lines" "$LOG" 2>/dev/null | grep -v 'message=evaluated' | grep -E 'directory=| cwd=' | tail -n1 | grep -oE '(directory|cwd)=[^ ]+' | head -n1 | cut -d= -f2-)
    [[ -z "$_seed" ]] && _seed=$(grep -v 'message=evaluated' "$LOG" 2>/dev/null | grep -E 'directory=| cwd=' | tail -n1 | grep -oE '(directory|cwd)=[^ ]+' | head -n1 | cut -d= -f2-)
    [[ -n "$_seed" ]] && CUR_DIR="$_seed"
  else
    _seed=$(grep -v 'message=evaluated' "$LOG" 2>/dev/null | grep -E 'directory=| cwd=' | head -n1 | grep -oE '(directory|cwd)=[^ ]+' | head -n1 | cut -d= -f2-)
    [[ -n "$_seed" ]] && CUR_DIR="$_seed"
  fi
  unset _total _prefix_lines _seed
fi
if [[ $FOLLOW -eq 1 ]]; then
  if [[ ${RAW_ENABLED:-0} -eq 1 ]]; then if [[ ${RAW_ALL:-0} -eq 1 ]]; then _raw_info="all"; else _raw_info="$RAW_TYPES"; fi; else _raw_info="off"; fi
  echo "${C_DIM}# tailing $LOG  (lines=$LINES, raw=$_raw_info, --no-follow to exit)${C_RESET}" >&2
  echo "${C_DIM}# every line shows [basename] at front (basename of directory=/cwd=/file dirname)${C_RESET}" >&2
  if [[ -n "$TARGET_DIR" ]]; then echo "${C_DIM}# filtering for dir: $TARGET_DIR [$TARGET_BASENAME] (override with --dir DIR or --all)${C_RESET}" >&2
  else echo "${C_DIM}# showing all directories (default is current git root/pwd; use --dir DIR to filter)${C_RESET}" >&2; fi
  echo "${C_DIM}# BOOT=file/dir boot | SESS=session | FILE=touch/format | PERM=permission | LLM=model | WATCH=watcher | LOOP=agent loop${C_RESET}" >&2
  [[ ${#EXCLUDE_TAGS_ARRAY[@]} -gt 0 ]] && echo "${C_DIM}# excludes: tags=${EXCLUDE_TYPES:-none}${C_RESET}" >&2
  [[ ${RAW_ENABLED:-0} -eq 1 ]] && { if [[ ${RAW_ALL:-0} -eq 1 ]]; then echo "${C_DIM}# raw: below every pretty line (dim)${C_RESET}" >&2; else echo "${C_DIM}# raw: below pretty lines for tags: $RAW_TYPES${C_RESET}" >&2; fi; }
  unset _raw_info
  tail -n "$LINES" -F --retry "$LOG" 2>/dev/null | while IFS= read -r ln; do handle_line "$ln"; done
else
  tail -n "$LINES" "$LOG" 2>/dev/null | while IFS= read -r ln; do handle_line "$ln"; done
fi
