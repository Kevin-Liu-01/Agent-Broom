#!/usr/bin/env bash
# agent-hygiene.sh - one script entrypoint for agent process tracking, audit,
# and cleanup. The skill should route here instead of reimplementing logic in
# prompt text.
#
# Usage:
#   agent-hygiene.sh list
#   agent-hygiene.sh audit
#   agent-hygiene.sh add --pid 123 --kind dev --port 3000 --purpose "verify UI" -- pnpm dev website
#   agent-hygiene.sh stop [--kill]
#   agent-hygiene.sh artifacts [clean-artifacts args...]
#   agent-hygiene.sh devclean [--deep] [--optimize] [--disk] [--apply]
#   agent-hygiene.sh doctor
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  sed -n '2,13p' "$0"
}

cmd="${1:-}"
[ -n "$cmd" ] || { usage; exit 2; }
shift || true

case "$cmd" in
  list)
    exec "$DIR/process-ledger.sh" list "$@"
    ;;
  add)
    exec "$DIR/process-ledger.sh" add "$@"
    ;;
  stop)
    exec "$DIR/process-ledger.sh" stop "$@"
    ;;
  prune)
    exec "$DIR/process-ledger.sh" prune "$@"
    ;;
  audit)
    "$DIR/process-ledger.sh" list "$@"
    "$DIR/audit-processes.sh"
    ;;
  artifacts)
    exec "$DIR/clean-artifacts.sh" "$@"
    ;;
  devclean)
    exec "$DIR/devclean.sh" "$@"
    ;;
  doctor)
    "$DIR/process-ledger.sh" list
    "$DIR/audit-processes.sh"
    "$DIR/clean-artifacts.sh"
    "$DIR/devclean.sh"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "unknown command: $cmd" >&2
    usage
    exit 2
    ;;
esac
