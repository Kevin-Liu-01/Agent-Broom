#!/usr/bin/env bash
# audit-processes.sh — find (and optionally kill) stray agent-spawned processes
# that linger after a task and burn CPU/RAM: test/watch runners, dev servers, and
# automation browsers. Default is a DRY-RUN report. Killing requires --kill and a
# category. Kills happen by process GROUP (pgid) so the whole pnpm->node->worker tree
# dies together, and a hardcoded protect-list keeps IDEs/agent-runtimes/MCP servers
# safe.
#
# Usage:
#   audit-processes.sh                      # report all categories (dry run)
#   audit-processes.sh --kill tests         # kill runaway test/watch groups
#   audit-processes.sh --kill dev --keep 87239   # kill dev servers except pgid 87239
#   audit-processes.sh --kill browser       # kill automation Chrome (never MCP servers)
#   audit-processes.sh --kill tests,dev     # multiple categories
#
# Exit codes: 0 ok · 2 usage error.
set -uo pipefail

# --- constants ---------------------------------------------------------------
# Never signal these: editors, agent runtimes, and IDE-managed MCP servers whose
# death breaks live tool connections in this or other sessions.
PROTECT_RE='Cursor|Code Helper|Electron|/MacOS/Code|Codex|node_repl|extension-host|chrome-devtools-mcp|playwright-mcp|@playwright/mcp|cursor-server'

# Category patterns (extended regex, matched against the full command string).
TESTS_RE='vitest|jest|mocha|jasmine|ava |pnpm test|npm test|yarn test|vitest run|pnpm exec vitest'
DEV_RE='next dev|next start|nodemon|astro dev|remix vite|vite($| )|webpack.*serve|turbo.*dev|pnpm dev|pnpm start|npm run dev|npm run start|yarn dev|bun.*dev|deno task.*dev|ng serve|rails server|flask run|fastapi dev|uvicorn|python -m http.server'
BROWSER_RE='(Google Chrome|Chromium|Chrome Helper|headless_shell).*(remote-debugging|ms-playwright|mcp-chrome|puppeteer)|playwright.*(chromium|firefox|webkit)'
LOCALHOST_RE='^(node|bun|deno|python|uvicorn|ruby|rails|go|cargo|java|next|vite|webpack|cloudflared)[[:space:]]|:3000|:3001|:3002|:5173|:5174|:8000|:8080|:8787'

SELF_PID=$$
SELF_PGID=$(ps -o pgid= -p "$SELF_PID" 2>/dev/null | tr -d ' ')

# --- helpers -----------------------------------------------------------------
# Print matching processes for a category, excluding protected and self.
list_matches() {
  local re="$1"
  ps -Ao pid,ppid,pgid,%cpu,etime,command 2>/dev/null \
    | rg -i -- "$re" \
    | rg -iv -- "$PROTECT_RE" \
    | rg -v -- "audit-processes.sh" \
    | awk -v self="$SELF_PGID" '$3 != self'
}

# Print a human report for a category.
report() {
  local label="$1" re="$2" rows
  rows=$(list_matches "$re" || true)
  printf '\n=== %s ===\n' "$label"
  if [ -z "$rows" ]; then
    echo "  (none)"
    return
  fi
  printf '  %-7s %-7s %-7s %-6s %-10s %s\n' PID PPID PGID %CPU ELAPSED COMMAND
  echo "$rows" | while IFS= read -r line; do
    echo "$line" | awk '{printf "  %-7s %-7s %-7s %-6s %-10s ", $1,$2,$3,$4,$5; for(i=6;i<=NF && i<=14;i++) printf "%s ", $i; print ""}'
  done
}

report_localhost() {
  printf '\n=== Localhost listeners (ports that may be active dev servers) ===\n'
  if ! command -v lsof >/dev/null 2>&1; then
    echo "  lsof unavailable"
    return
  fi
  rows=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null \
    | awk 'NR > 1 && /127\.0\.0\.1|localhost|\[::1\]|\*:/' \
    | rg -i -- "$LOCALHOST_RE" \
    | rg -iv -- "$PROTECT_RE" || true)
  if [ -z "$rows" ]; then
    echo "  (none)"
    return
  fi
  echo "  COMMAND     PID     USER   FD   TYPE DEVICE SIZE/OFF NODE NAME"
  echo "$rows" | awk '{print "  " $0}'
}

# Distinct pgids for a category, minus any in the keep-list.
pgids_for() {
  local re="$1" keep="$2"
  list_matches "$re" | awk '{print $3}' | sort -u | while read -r pg; do
    [ -z "$pg" ] && continue
    case ",$keep," in *",$pg,"*) continue ;; esac
    echo "$pg"
  done
}

# SIGTERM then SIGKILL a process group.
kill_group() {
  local pg="$1"
  kill -TERM -"$pg" 2>/dev/null && echo "  SIGTERM -> pgid $pg"
  sleep 2
  if ps -Ao pgid= 2>/dev/null | tr -d ' ' | rg -q "^${pg}$"; then
    kill -KILL -"$pg" 2>/dev/null && echo "  SIGKILL -> pgid $pg (straggler)"
  fi
}

category_re() {
  case "$1" in
    tests) echo "$TESTS_RE" ;;
    dev) echo "$DEV_RE" ;;
    browser) echo "$BROWSER_RE" ;;
    *) echo "" ;;
  esac
}

# --- main --------------------------------------------------------------------
KILL_CATS="" KEEP=""
while [ $# -gt 0 ]; do
  case "$1" in
    --kill) KILL_CATS="${2:-}"; shift 2 ;;
    --keep) KEEP="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$KILL_CATS" ]; then
  echo "DRY RUN — reporting stray processes (use --kill <tests|dev|browser> to act)"
  report_localhost
  report "Test / watch runners (usually safe to kill)" "$TESTS_RE"
  report "Dev servers (keep the one you are actively using)" "$DEV_RE"
  report "Automation browsers (close via the browser tool first)" "$BROWSER_RE"
  echo
  echo "Protected (never killed): $PROTECT_RE"
  exit 0
fi

IFS=','
for cat in $KILL_CATS; do
  re=$(category_re "$cat")
  if [ -z "$re" ]; then echo "unknown category: $cat (use tests|dev|browser)" >&2; exit 2; fi
  echo "Killing category '$cat' (keep: ${KEEP:-none})"
  pgs=$(pgids_for "$re" "$KEEP")
  if [ -z "$pgs" ]; then echo "  nothing to kill"; continue; fi
  for pg in $pgs; do kill_group "$pg"; done
done
unset IFS
echo "done"
