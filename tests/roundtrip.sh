#!/usr/bin/env bash
# tests/roundtrip.sh — the 1TimeAi acceptance test. A blank project must: boot, hand off, leave
# NOW.md / SESSION-LOG.md / INDEX.md on disk, get a GREEN gate, and end up committed — with no
# conversation memory involved anywhere. ONE final line.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; L="$(mktemp -d)"
trap 'rm -rf "$T" "$L"' EXIT
fail() { echo "roundtrip: RED — $1"; [ -f "$L/last.log" ] && sed 's/^/    /' "$L/last.log" | tail -25; exit 1; }
cd "$T" || exit 1
git init -q . && git config user.email "test@localhost" && git config user.name "roundtrip" || fail "git init"
for f in fw-boot.sh fw-handoff.sh fw-verify.sh agent-ops-lib.sh; do cp "$HERE/$f" . || fail "copy $f"; done
cp "$HERE/.fw-config.example" .fw-config
cp "$HERE/.fw-checks.sh.example" .fw-checks.sh
printf '# Demo project\n\n<!-- AUTO:NOW -->\n<!-- /AUTO:NOW -->\n' > CLAUDE.md
printf '# ROADMAP\n\n- [ ] first task\n' > ROADMAP.md
printf '# NOW — ground truth\n\n%s · project created · last: init · next: first task\n' "$(date +%Y-%m-%d)" > NOW.md
printf '# demo\n' > README.md
git add -A && git commit -qm "init" || fail "initial commit"

bash fw-boot.sh > "$L/last.log" 2>&1 || fail "fw-boot exited non-zero"
grep -q "BOOT" "$L/last.log" || fail "fw-boot printed no BOOT digest"

bash fw-handoff.sh "roundtrip handoff" --note "written by tests/roundtrip.sh" > "$L/last.log" 2>&1 || fail "fw-handoff exited non-zero"
grep -q "roundtrip handoff" NOW.md         || fail "NOW.md does not carry the handoff line"
grep -q "roundtrip handoff" SESSION-LOG.md || fail "SESSION-LOG.md does not carry the handoff line"
[ -f INDEX.md ]                            || fail "INDEX.md was not generated"
grep -q "roundtrip handoff" CLAUDE.md      || fail "CLAUDE.md AUTO:NOW block was not synced"
grep -q "GREEN" .fw/gate-last              || fail "gate not GREEN: $(cat .fw/gate-last 2>/dev/null)"
git log -1 --format=%s | grep -q "handoff" || fail "handoff did not commit"
[ -z "$(git status --porcelain)" ]         || fail "working tree dirty after handoff: $(git status --porcelain | tr '\n' ' ')"

bash fw-verify.sh > "$L/last.log" 2>&1 || fail "fw-verify RED after handoff"
echo "roundtrip: ALL GREEN — boot → handoff → NOW/SESSION-LOG/INDEX/CLAUDE synced → gate GREEN → committed ($(git rev-parse --short HEAD))"
