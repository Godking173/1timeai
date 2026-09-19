#!/usr/bin/env bash
# fw-verify.sh — FW v2 · the ship-gate. IDENTICAL file in every project folder.
# ══════════════════════════════════════════════════════════════════════════════════
# Generic honesty checks every project needs + a per-project hook (.fw-checks.sh)
# for the checks only THIS project needs. Prints ✓/✗ per check and ONE final line:
#   fw-verify: ALL GREEN (N checks)   ← exit 0
#   fw-verify: RED — k failed         ← exit 1
# Result is cached to .fw/gate-last so fw-boot shows it without re-running the suite.
# Hook API (.fw-checks.sh):   fw_check "<label>" <command...>
#   e.g.  fw_check "package.json parses" node -e 'require("./package.json")'
#         fw_check "no tracked .env" bash -c '! git ls-files | grep -qE "(^|/)\.env"'
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
. "$DIR/agent-ops-lib.sh"
[ -f "$DIR/.fw-config" ] && . "$DIR/.fw-config"
PASS=0; FAIL=0

fw_check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1)); echo "  ✓ $label"
  else
    FAIL=$((FAIL+1)); echo "  ✗ $label"
  fi
}

_now_fresh() {
  local f="NOW.md" d1 d2 e1 e2 d
  [ -f "$f" ] || return 1
  d1="$(aol_extract_date "$f" first || true)"; d2="$(aol_extract_date "$f" last || true)"
  e1="$(aol_to_epoch "${d1:-1970-01-01}")"; e2="$(aol_to_epoch "${d2:-1970-01-01}")"
  if [ "${e1:-0}" -ge "${e2:-0}" ]; then d="$d1"; else d="$d2"; fi
  [ -n "${d:-}" ] || return 1
  local days; days="$(aol_days_since "$d")"
  [ "$days" != "?" ] && [ "$days" -le 7 ]
}

_no_stale_locks() {
  [ -d .git ] || return 0
  [ -z "$(find .git -maxdepth 2 -name '*.lock' -mmin +1 2>/dev/null)" ]
}

_no_tracked_secrets() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  # .env.example / .sample / .template are safe by convention — real env/keys are not
  ! git ls-files 2>/dev/null | grep -vE '\.(example|sample|template)(\.[a-z]+)?$' \
    | grep -qE '(^|/)(\.env(\..+)?|secrets\.env|.+\.pem|.+_secret.*)$'
}

echo "── fw-verify · $(basename "$DIR") · $(date '+%Y-%m-%d %H:%M') ──"
fw_check "NOW.md has an entry ≤7d old" _now_fresh
fw_check "CLAUDE.md exists (auto-loads every chat)" test -f CLAUDE.md
fw_check "CLAUDE.md has the AUTO:NOW sync block" grep -q 'AUTO:NOW' CLAUDE.md
fw_check "fw scripts parse (bash -n)" bash -c 'for s in fw-boot.sh fw-handoff.sh fw-verify.sh agent-ops-lib.sh; do bash -n "$s" || exit 1; done'
fw_check "no stale .git locks (>60s)" _no_stale_locks
fw_check "no secrets tracked by git" _no_tracked_secrets

# per-project checks
if [ -f .fw-checks.sh ]; then . ./.fw-checks.sh; fi

mkdir -p .fw
if [ "$FAIL" -eq 0 ]; then
  printf 'GREEN @ %s' "$(date '+%Y-%m-%d %H:%M')" > .fw/gate-last
  echo "fw-verify: ALL GREEN ($PASS checks)"
  exit 0
else
  printf 'RED @ %s' "$(date '+%Y-%m-%d %H:%M')" > .fw/gate-last
  echo "fw-verify: RED — $FAIL failed, $PASS passed. Fix the ✗ lines (never mute the check)."
  exit 1
fi
