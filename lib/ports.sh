#!/usr/bin/env bash
# ports.sh - port-whisperer-style port/process inspection for Agent Broom.
#
# Human-first CLI, agent-callable JSON, dry-run cleanup by default.
#
# Usage:
#   ports.sh [--all] [--json]
#   ports.sh <port> [--json]
#   ports.sh ps [--all] [--json]
#   ports.sh kill [--apply] [--force] <port|pid|range>...
#   ports.sh clean [--apply] [--json]
#   ports.sh logs <port|pid> [--lines N] [--follow]
#   ports.sh watch [--all] [--interval SEC] [--json]
set -uo pipefail
shopt -s nocasematch

PROTECT_RE='Cursor|Code Helper|Electron|/MacOS/Code|Codex|codex|ChatGPT\.app|cua_node|node_repl|extension-host|chrome-devtools-mcp|playwright-mcp|@playwright/mcp|cursor-server|(^|/)mcp/|mcp/server\.mjs'
SELF_PGID="$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ')"

usage() {
  sed -n '2,15p' "$0"
}

has() { command -v "$1" >/dev/null 2>&1; }

json_escape() {
  awk 'BEGIN {
    s = ARGV[1]; ARGV[1] = "";
    gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); gsub(/\t/,"\\t",s); gsub(/\r/,"\\r",s); gsub(/\n/,"\\n",s);
    printf "%s", s
  }' "$1"
}

print_json_string() {
  printf '"%s"' "$(json_escape "${1:-}")"
}

command_for() {
  ps -o command= -p "$1" 2>/dev/null | sed 's/^[[:space:]]*//'
}

field_for() {
  local fmt="$1" pid="$2"
  ps -o "$fmt"= -p "$pid" 2>/dev/null | awk '{$1=$1; print}'
}

cwd_for() {
  lsof -a -p "$1" -d cwd -Fn 2>/dev/null | awk 'sub(/^n/,""){print; exit}'
}

project_root_for() {
  local cwd="$1"
  [ -n "$cwd" ] || return 0
  git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$cwd"
}

project_name_for() {
  local root="$1"
  [ -n "$root" ] || { printf '—\n'; return; }
  basename "$root"
}

is_protected_pid() {
  local cmd
  cmd="$(command_for "$1")"
  is_protected_command "$cmd"
}

is_protected_command() {
  local cmd="${1:-}"
  case "$cmd" in
    *Cursor*|*"Code Helper"*|*Electron*|*"/MacOS/Code"*|*Codex*|*codex*|*"ChatGPT.app"*|*cua_node*|*node_repl*|*extension-host*|*chrome-devtools-mcp*|*playwright-mcp*|*"@playwright/mcp"*|*cursor-server*|*/mcp/*|*"mcp/server.mjs"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_dev_process() {
  local name cmd
  name="${1:-}"
  cmd="${2:-}"

  case "$name" in
    spotify*|raycast*|tableplus*|postman*|linear*|cursor*|controlce*|rapportd*|slack*|discord*|firefox*|chrome*|google*|safari*|figma*|notion*|zoom*|teams*|code*|iterm2*|warp*|arc*|launchd|systemd|sshd|cron|dbus-daemon|svchost|explorer)
      return 1
      ;;
    node|python|python3|ruby|java|go|cargo|deno|bun|php|uvicorn|gunicorn|flask|rails|npm|npx|yarn|pnpm|tsx|turbo|jest|vitest|mocha|pytest|cypress|playwright|dotnet)
      return 0
      ;;
  esac

  [[ "$cmd" =~ (^|[[:space:]/])(next|vite|nuxt|astro|remix|webpack|uvicorn|fastapi|django|rails|tsx|vite-node|wrangler|cargo[[:space:]]run|python[[:space:]]-m[[:space:]]http\.server|npm[[:space:]]run[[:space:]]dev|pnpm[[:space:]]dev|yarn[[:space:]]dev|bun.*dev)([[:space:]:/]|$) ]]
}

framework_for() {
  local name="$1" cmd="$2" root="$3"
  case "$cmd" in
    *next*) echo "Next.js"; return ;;
    *vite*) echo "Vite"; return ;;
    *astro*) echo "Astro"; return ;;
    *remix*) echo "Remix"; return ;;
    *uvicorn*|*fastapi*) echo "FastAPI"; return ;;
    *django*) echo "Django"; return ;;
    *rails*) echo "Rails"; return ;;
    *wrangler*) echo "Cloudflare"; return ;;
  esac
  if [ -n "$root" ] && [ -f "$root/package.json" ]; then
    grep -q '"next"' "$root/package.json" 2>/dev/null && { echo "Next.js"; return; }
    grep -q '"vite"' "$root/package.json" 2>/dev/null && { echo "Vite"; return; }
    grep -q '"astro"' "$root/package.json" 2>/dev/null && { echo "Astro"; return; }
    grep -q '"remix"' "$root/package.json" 2>/dev/null && { echo "Remix"; return; }
  fi
  case "$name" in
    node|npm|npx|pnpm|yarn|bun) echo "Node.js" ;;
    python|python3) echo "Python" ;;
    ruby|rails) echo "Ruby" ;;
    cargo) echo "Rust" ;;
    docker|com.docke*) echo "Docker" ;;
    *) echo "—" ;;
  esac
}

listeners() {
  if ! has lsof; then
    echo "lsof is required for port inspection" >&2
    exit 2
  fi
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null \
    | awk 'NR > 1 {
      name=$1; pid=$2; user=$3; addr=$9;
      n=split(addr, parts, ":"); port=parts[n];
      if (port ~ /^[0-9]+$/) print port "\t" name "\t" pid "\t" user "\t" addr
    }' \
    | sort -n -k1,1 -u
}

emit_port_rows() {
  local show_all="$1" row port name pid user addr cmd ppid pgid stat cpu rss etime cwd root project framework status
  while IFS=$'\t' read -r port name pid user addr; do
    [ -n "${pid:-}" ] || continue
    cmd="$(command_for "$pid")"
    if [ "$show_all" -ne 1 ] && ! is_dev_process "$name" "$cmd"; then
      continue
    fi
    ppid="$(field_for ppid "$pid")"
    pgid="$(field_for pgid "$pid")"
    stat="$(field_for stat "$pid")"
    cpu="$(field_for %cpu "$pid")"
    rss="$(field_for rss "$pid")"
    etime="$(field_for etime "$pid")"
    cwd="$(cwd_for "$pid")"
    root="$(project_root_for "$cwd")"
    project="$(project_name_for "$root")"
    framework="$(framework_for "$name" "$cmd" "$root")"
    status="healthy"
    printf '%s\n' "$stat" | grep -q Z && status="zombie"
    if [ "${ppid:-0}" = "1" ] && is_dev_process "$name" "$cmd"; then status="orphaned"; fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$port" "$name" "$pid" "$ppid" "$pgid" "$cpu" "${rss:-0}" "$etime" "$status" "$project" "$framework" "$root" "$addr" "$cmd"
  done < <(listeners)
}

ports_json() {
  local show_all="$1" first=1 port name pid ppid pgid cpu rss etime status project framework root addr cmd
  printf '{"ok":true,"ports":['
  while IFS=$'\t' read -r port name pid ppid pgid cpu rss etime status project framework root addr cmd; do
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"port":%s,"process":' "$port"; print_json_string "$name"
    printf ',"pid":%s,"ppid":%s,"pgid":%s,"cpu":' "$pid" "${ppid:-0}" "${pgid:-0}"; print_json_string "$cpu"
    printf ',"rssKb":%s,"uptime":' "${rss:-0}"; print_json_string "$etime"
    printf ',"status":'; print_json_string "$status"
    printf ',"project":'; print_json_string "$project"
    printf ',"framework":'; print_json_string "$framework"
    printf ',"root":'; print_json_string "$root"
    printf ',"address":'; print_json_string "$addr"
    printf ',"command":'; print_json_string "$cmd"
    printf '}'
  done < <(emit_port_rows "$show_all")
  printf ']}\n'
}

ports_table() {
  local show_all="$1" count=0 port name pid ppid pgid cpu rss etime status project framework root addr cmd
  printf '\nAgent Broom ports%s\n\n' "$([ "$show_all" -eq 1 ] && echo ' (--all)' || echo '')"
  printf '%-7s %-14s %-7s %-18s %-12s %-10s %s\n' PORT PROCESS PID PROJECT FRAMEWORK UPTIME STATUS
  while IFS=$'\t' read -r port name pid ppid pgid cpu rss etime status project framework root addr cmd; do
    count=$((count + 1))
    printf ':%-6s %-14.14s %-7s %-18.18s %-12.12s %-10s %s\n' "$port" "$name" "$pid" "$project" "$framework" "$etime" "$status"
  done < <(emit_port_rows "$show_all")
  [ "$count" -gt 0 ] || echo "  (none)"
  echo
  echo "$count port$([ "$count" -eq 1 ] || echo s) active · agent-broom port <number> for details · --all to show everything"
}

port_detail() {
  local want="$1" as_json="$2" row found=0 port name pid ppid pgid cpu rss etime status project framework root addr cmd
  while IFS=$'\t' read -r port name pid ppid pgid cpu rss etime status project framework root addr cmd; do
    [ "$port" = "$want" ] || continue
    found=1
    if [ "$as_json" -eq 1 ]; then
      printf '{"ok":true,"port":%s,"process":' "$port"; print_json_string "$name"
      printf ',"pid":%s,"ppid":%s,"pgid":%s,"cpu":' "$pid" "${ppid:-0}" "${pgid:-0}"; print_json_string "$cpu"
      printf ',"rssKb":%s,"uptime":' "${rss:-0}"; print_json_string "$etime"
      printf ',"status":'; print_json_string "$status"
      printf ',"project":'; print_json_string "$project"
      printf ',"framework":'; print_json_string "$framework"
      printf ',"root":'; print_json_string "$root"
      printf ',"address":'; print_json_string "$addr"
      printf ',"command":'; print_json_string "$cmd"
      printf '}\n'
    else
      echo "Port :$port"
      echo "  process:   $name"
      echo "  pid/pgid:  $pid / ${pgid:-?}"
      echo "  status:    $status"
      echo "  project:   $project"
      echo "  framework: $framework"
      echo "  cwd/root:  ${root:-—}"
      echo "  address:   $addr"
      echo "  command:   $cmd"
    fi
    return 0
  done < <(emit_port_rows 1)
  if [ "$as_json" -eq 1 ]; then
    printf '{"ok":false,"error":{"code":"port_not_found","message":"no listener on port %s"}}\n' "$want"
  else
    echo "no listener on port $want" >&2
  fi
  return 1
}

pid_for_port() {
  local want="$1" port name pid user addr
  while IFS=$'\t' read -r port name pid user addr; do
    [ "$port" = "$want" ] && { echo "$pid"; return 0; }
  done < <(listeners)
  return 1
}

expand_targets() {
  local arg start end n
  for arg in "$@"; do
    if [[ "$arg" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
      if [ "$start" -gt "$end" ] || [ "$end" -gt 65535 ] || [ $((end - start)) -gt 1000 ]; then
        echo "invalid range: $arg" >&2
        return 2
      fi
      for ((n=start; n<=end; n++)); do echo "$n"; done
    else
      echo "$arg"
    fi
  done
}

kill_targets() {
  local apply=0 force=0 target pid pgid signal killed=0 empty=0 skipped=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply|--kill) apply=1; shift ;;
      --force|-f) force=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      -*) echo "unknown kill arg: $1" >&2; exit 2 ;;
      *) break ;;
    esac
  done
  [ $# -gt 0 ] || { echo "kill needs <port|pid|range> (dry-run; pass --apply to act)" >&2; exit 2; }
  signal="$([ "$force" -eq 1 ] && echo KILL || echo TERM)"
  echo "$([ "$apply" -eq 1 ] && echo APPLY || echo 'DRY RUN') — kill targets with SIG$signal"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    pid="$(pid_for_port "$target" 2>/dev/null || true)"
    [ -n "$pid" ] || { ps -p "$target" >/dev/null 2>&1 && pid="$target"; }
    if [ -z "$pid" ]; then
      echo "  empty: $target"
      empty=$((empty + 1))
      continue
    fi
    pgid="$(field_for pgid "$pid")"
    if [ -z "$pgid" ] || [ "$pgid" = "$SELF_PGID" ] || is_protected_pid "$pid"; then
      echo "  protect/skip pid $pid target $target"
      skipped=$((skipped + 1))
      continue
    fi
    echo "  $([ "$apply" -eq 1 ] && echo kill || echo 'would kill') pid $pid pgid $pgid target $target: $(command_for "$pid")"
    if [ "$apply" -eq 1 ]; then
      kill "-$signal" -"$pgid" 2>/dev/null || kill "-$signal" "$pid" 2>/dev/null || true
    fi
    killed=$((killed + 1))
  done < <(expand_targets "$@")
  echo "summary: $killed target$([ "$killed" -eq 1 ] || echo s), $empty empty, $skipped protected/skipped"
}

ps_command() {
  local show_all="$1" as_json="$2" rows first=1 pid ppid pgid cpu rss etime rest
  rows="$(ps -Ao pid,ppid,pgid,%cpu,rss,etime,command 2>/dev/null || true)"
  if [ "$as_json" -eq 1 ]; then
    printf '{"ok":true,"processes":['
    echo "$rows" | awk 'NR > 1' | while read -r pid ppid pgid cpu rss etime rest; do
      [ -n "$pid" ] || continue
      proc="${rest%% *}"
      proc="${proc##*/}"
      if [ "$show_all" -ne 1 ] && is_protected_command "$rest"; then
        continue
      fi
      if [ "$show_all" -ne 1 ] && ! is_dev_process "$proc" "$rest"; then
        continue
      fi
      [ "$first" -eq 1 ] || printf ','
      first=0
      printf '{"pid":%s,"ppid":%s,"pgid":%s,"cpu":' "$pid" "$ppid" "$pgid"; print_json_string "$cpu"
      printf ',"rssKb":%s,"uptime":' "$rss"; print_json_string "$etime"
      printf ',"command":'; print_json_string "$rest"
      printf '}'
    done
    printf ']}\n'
    return
  fi
  echo
  echo "Agent Broom ps"
  printf '  %-7s %-7s %-7s %-6s %-8s %-10s %s\n' PID PPID PGID CPU RSS ELAPSED COMMAND
  echo "$rows" | awk 'NR > 1' | while read -r pid ppid pgid cpu rss etime rest; do
    [ -n "$pid" ] || continue
    proc="${rest%% *}"
    proc="${proc##*/}"
    if [ "$show_all" -ne 1 ] && is_protected_command "$rest"; then
      continue
    fi
    if [ "$show_all" -ne 1 ] && ! is_dev_process "$proc" "$rest"; then
      continue
    fi
    printf '  %-7s %-7s %-7s %-6s %-8s %-10s %.100s\n' "$pid" "$ppid" "$pgid" "$cpu" "$rss" "$etime" "$rest"
  done
}

clean_command() {
  local apply=0 as_json=0 pids="" port name pid ppid pgid cpu rss etime status project framework root addr cmd
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply|--kill) apply=1; shift ;;
      --json) as_json=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "unknown clean arg: $1" >&2; exit 2 ;;
    esac
  done
  while IFS=$'\t' read -r port name pid ppid pgid cpu rss etime status project framework root addr cmd; do
    case "$status" in orphaned|zombie) pids="$pids $pid" ;; esac
  done < <(emit_port_rows 0)
  pids="$(printf '%s\n' "$pids" | xargs 2>/dev/null || true)"
  if [ "$as_json" -eq 1 ]; then
    printf '{"ok":true,"apply":%s,"pids":[' "$([ "$apply" -eq 1 ] && echo true || echo false)"
    first=1
    for pid in $pids; do [ "$first" -eq 1 ] || printf ','; first=0; printf '%s' "$pid"; done
    printf ']}\n'
  else
    echo "$([ "$apply" -eq 1 ] && echo APPLY || echo 'DRY RUN') — orphaned/zombie dev listeners"
    [ -n "$pids" ] || { echo "  (none)"; return 0; }
    for pid in $pids; do echo "  $([ "$apply" -eq 1 ] && echo kill || echo 'would kill') pid $pid: $(command_for "$pid")"; done
  fi
  if [ "$apply" -eq 1 ]; then
    for pid in $pids; do
      is_protected_pid "$pid" && continue
      pgid="$(field_for pgid "$pid")"
      [ -n "$pgid" ] && [ "$pgid" != "$SELF_PGID" ] && kill -TERM -"$pgid" 2>/dev/null || true
    done
  fi
}

logs_command() {
  local target="${1:-}" lines=50 follow=0 pid files
  [ -n "$target" ] || { echo "logs needs <port|pid>" >&2; exit 2; }
  shift || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --lines|-n) lines="${2:?}"; shift 2 ;;
      --follow|-f) follow=1; shift ;;
      *) echo "unknown logs arg: $1" >&2; exit 2 ;;
    esac
  done
  pid="$(pid_for_port "$target" 2>/dev/null || true)"
  [ -n "$pid" ] || pid="$target"
  ps -p "$pid" >/dev/null 2>&1 || { echo "no process for $target" >&2; exit 1; }
  files="$(lsof -p "$pid" 2>/dev/null | awk '$4 ~ /^[12][uw]?$/ && $9 ~ /^\// {print $9}' | sort -u | head -2)"
  [ -n "$files" ] || { echo "no redirected stdout/stderr log files found for pid $pid" >&2; exit 1; }
  for f in $files; do
    echo "==> $f <=="
    if [ "$follow" -eq 1 ]; then tail -f -n "$lines" "$f"; else tail -n "$lines" "$f"; fi
  done
}

watch_command() {
  local show_all=0 as_json=0 interval=2 before after
  while [ $# -gt 0 ]; do
    case "$1" in
      --all|-a) show_all=1; shift ;;
      --json) as_json=1; shift ;;
      --interval) interval="${2:?}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "unknown watch arg: $1" >&2; exit 2 ;;
    esac
  done
  before="$(emit_port_rows "$show_all" | awk -F '\t' '{print $1":"$3}' | sort)"
  echo "watching ports every ${interval}s (Ctrl-C to stop)"
  while sleep "$interval"; do
    after="$(emit_port_rows "$show_all" | awk -F '\t' '{print $1":"$3}' | sort)"
    [ "$before" = "$after" ] && continue
    if [ "$as_json" -eq 1 ]; then ports_json "$show_all"; else ports_table "$show_all"; fi
    before="$after"
  done
}

show_all=0
as_json=0
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --all|-a) show_all=1; shift ;;
    --json) as_json=1; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) args+=("$1"); shift ;;
  esac
done

cmd="${args[0]:-}"
case "$cmd" in
  "")
    [ "$as_json" -eq 1 ] && ports_json "$show_all" || ports_table "$show_all"
    ;;
  ps)
    ps_command "$show_all" "$as_json"
    ;;
  kill)
    kill_targets "${args[@]:1}"
    ;;
  clean)
    if [ "$as_json" -eq 1 ]; then
      clean_command "${args[@]:1}" --json
    else
      clean_command "${args[@]:1}"
    fi
    ;;
  logs)
    logs_command "${args[@]:1}"
    ;;
  watch)
    watch_args=("${args[@]:1}")
    [ "$show_all" -eq 1 ] && watch_args+=(--all)
    [ "$as_json" -eq 1 ] && watch_args+=(--json)
    watch_command "${watch_args[@]}"
    ;;
  *)
    if [[ "$cmd" =~ ^[0-9]+$ ]]; then
      port_detail "$cmd" "$as_json"
    else
      echo "unknown command: $cmd" >&2
      usage
      exit 2
    fi
    ;;
esac
