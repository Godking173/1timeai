#!/usr/bin/env bash
# fw-boot.sh — FW v2 · universal flywheel BOOT. IDENTICAL file in every project folder.
# ══════════════════════════════════════════════════════════════════════════════════
# One script, six repos, zero drift: every fix lands everywhere with one `cp`.
# Prints a ≤25-line digest and nothing more (boot output is a token cost — cap it):
#   NOW (newest entry — auto-detects newest-on-TOP *and* append-BOTTOM conventions)
#   · freshness alarm · GIT health incl ⚠ UNPUSHED commits + stale locks (both bit us)
#   · NEXT · RISKS · GATE (cached — boot never runs the test suite; old boots did and
#   were slow) · arms pointer. READ-ONLY: boot never mutates the repo (old cc-boot
#   rebuilt graphs and rewrote CLAUDE.md at boot). Absorbs the clock: stamps session
#   start in /tmp; fw-handoff prints honest elapsed time.
#
#   bash fw-boot.sh          # boot this project
#   bash fw-boot.sh --gate   # boot + run the gate live (slower, on demand)
#   bash fw-boot.sh --line   # this project as one status line
#   bash fw-boot.sh --all    # EMPIRE SWEEP: one line per project across all folders
# Config (optional .fw-config): FW_PROJECT FW_NOW FW_NEXT_FILE FW_GATE FW_NOW_CHARS
# Fleet for --all: $FW_FLEET file > ~/.fw-fleet > ./.fw-fleet > sibling-dir scan.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
. "$DIR/agent-ops-lib.sh"
[ -f "$DIR/.fw-config" ] && . "$DIR/.fw-config"
PROJECT="${FW_PROJECT:-$(basename "$DIR")}"
NOWFILE="${FW_NOW:-NOW.md}"
[ -f "$NOWFILE" ] || { [ -f STATE.md ] && NOWFILE="STATE.md"; }
NEXTFILE="${FW_NEXT_FILE:-ROADMAP.md}"
CHARS="${FW_NOW_CHARS:-500}"
MODE="${1:-}"

# newest dated line of a file, whichever convention (top-newest OR bottom-newest) is newer.
newest_entry() { # $1=file → prints "DATE<TAB>LINE" (empty if none)
  local f="$1" first last fd ld fe le
  [ -f "$f" ] || return 1
  first="$(grep -m1 -E '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null || true)"
  last="$(grep -E '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null | tail -1 || true)"
  fd="$(printf '%s' "$first" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
  ld="$(printf '%s' "$last" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true)"
  [ -z "$fd" ] && [ -z "$ld" ] && return 1
  fe="$(aol_to_epoch "${fd:-1970-01-01}")"; le="$(aol_to_epoch "${ld:-1970-01-01}")"
  if [ "${fe:-0}" -ge "${le:-0}" ]; then printf '%s\t%s' "$fd" "$first"; else printf '%s\t%s' "$ld" "$last"; fi
}

git_line() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "no git — files are the save (handoff still works)"; return; }
  local br dirty ahead locks msg
  br="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  ahead="$(git rev-list --count @{u}..HEAD 2>/dev/null || echo '?')"
  locks="$(find .git -maxdepth 2 -name '*.lock' 2>/dev/null | wc -l | tr -d ' ')"
  msg="$br · ${dirty} uncommitted"
  if [ "$ahead" = "?" ]; then msg="$msg · no upstream"
  elif [ "$ahead" -gt 0 ]; then msg="$msg · ⚠ ${ahead} UNPUSHED — git push from the Mac"
  else msg="$msg · pushed ✓"; fi
  [ "${locks:-0}" -gt 0 ] && msg="$msg · ⚠ ${locks} stale .git lock(s) — fw-handoff clears them"
  echo "$msg"
}

one_line() { # $1=dir → single empire-sweep status line
  local d="$1" nf="" c e dt ln days icon g="" gate="-"
  for c in NOW.md STATE.md; do [ -f "$d/$c" ] && nf="$d/$c" && break; done
  [ -z "$nf" ] && return 1
  e="$(newest_entry "$nf" || true)"
  dt="$(printf '%s' "$e" | cut -f1)"; ln="$(printf '%s' "$e" | cut -f2- | sed 's/^[#* ]*//')"
  days="$(aol_days_since "${dt:-1970-01-01}" 2>/dev/null || echo '?')"
  if [ "$days" != "?" ] && [ "$days" -le 1 ]; then icon="🟢"
  elif [ "$days" != "?" ] && [ "$days" -le 3 ]; then icon="🟡"; else icon="🔴"; fi
  if (cd "$d" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    local dirty ahead
    dirty="$(cd "$d" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    ahead="$(cd "$d" && git rev-list --count @{u}..HEAD 2>/dev/null || echo '-')"
    g=" git:${dirty}Δ/${ahead}↑"
  fi
  [ -f "$d/.fw/gate-last" ] && gate="$(cat "$d/.fw/gate-last")"
  printf '%s %-20.20s %s(%sd)%s gate:%s · %.60s\n' "$icon" "$(basename "$d")" "${dt:-????}" "$days" "$g" "$gate" "$ln"
}

if [ "$MODE" = "--line" ]; then one_line "$DIR"; exit 0; fi

if [ "$MODE" = "--all" ]; then
  echo "═══ FW EMPIRE SWEEP · $(date '+%Y-%m-%d %H:%M') ═══"
  dirs=""
  for flt in "${FW_FLEET:-}" "$HOME/.fw-fleet" "$DIR/.fw-fleet"; do
    [ -n "$flt" ] && [ -f "$flt" ] || continue
    while IFS= read -r p; do
      case "$p" in ''|'#'*) continue;; esac
      [ -d "$p" ] && dirs="$dirs$p"$'\n'
    done < "$flt"
    [ -n "$dirs" ] && break
  done
  if [ -z "$dirs" ]; then # fallback: sibling folders (works in the sandbox where all mounts share a parent)
    for p in "$(dirname "$DIR")"/*/; do
      p="${p%/}"
      { [ -f "$p/NOW.md" ] || [ -f "$p/STATE.md" ]; } && dirs="$dirs$p"$'\n'
    done
  fi
  printf '%s' "$dirs" | while IFS= read -r p; do [ -n "$p" ] && one_line "$p"; done
  echo "── legend: 🟢≤1d 🟡≤3d 🔴stale · Δ=uncommitted ↑=unpushed · boot one: bash <dir>/fw-boot.sh"
  exit 0
fi

# ── standard single-project boot ──
echo "═══ $PROJECT · BOOT · $(date '+%Y-%m-%d %H:%M') ═══"
CK="$(printf '%s' "$DIR" | cksum | cut -d' ' -f1)"; STAMP="/tmp/.fw-clock-$CK"
[ -f "$STAMP" ] || date +%s > "$STAMP"

E="$(newest_entry "$NOWFILE" || true)"
if [ -n "$E" ]; then
  DT="$(printf '%s' "$E" | cut -f1)"; LN="$(printf '%s' "$E" | cut -f2-)"
  echo "▸ NOW ($NOWFILE · newest entry):"
  printf '   %s\n' "$(printf '%s' "$LN" | cut -c1-"$CHARS")"
  [ "${#LN}" -gt "$CHARS" ] && echo "   …(truncated — full: $NOWFILE)"
  if aol_is_recent "$DT" 1; then echo "   🟢 fresh — $DT (today: $(aol_today))"
  else echo "   ⚠️  STALE: newest entry is $DT (~$(aol_days_since "$DT")d old) — verify live state before acting."; fi
else
  echo "▸ NOW: ⚠ no dated entry found in $NOWFILE — run fw-handoff to start the record."
fi
if [ -f STATE.md ] && [ "$NOWFILE" != "STATE.md" ]; then
  SD="$(aol_extract_date STATE.md first || true)"
  [ -n "${SD:-}" ] && echo "▸ STATE.md (machine-swept): last sweep $SD ($(aol_days_since "$SD")d ago)"
fi
echo "▸ GIT: $(git_line)"
if [ -f "$NEXTFILE" ]; then
  NEXTLINES="$(grep -E '^ *- \[ \]' "$NEXTFILE" 2>/dev/null | head -3)"
  [ -z "$NEXTLINES" ] && NEXTLINES="$(grep -E '^[0-9]+\. ' "$NEXTFILE" 2>/dev/null | head -3)"   # numbered-roadmap repos (numbered roadmaps)
  if [ -n "$NEXTLINES" ]; then echo "▸ NEXT (top of $NEXTFILE):"; printf '%s\n' "$NEXTLINES" | cut -c1-110 | sed 's/^/   /'; fi
fi
if [ -f RISKS.md ]; then RC="$(grep -cE '^- ' RISKS.md 2>/dev/null)"; echo "▸ RISKS: ${RC:-0} open (RISKS.md)"; fi
GATECMD="${FW_GATE:-}"; [ -z "$GATECMD" ] && [ -f fw-verify.sh ] && GATECMD="bash fw-verify.sh"
if [ "$MODE" = "--gate" ] && [ -n "$GATECMD" ]; then
  echo "▸ GATE (live · $GATECMD):"; bash -c "$GATECMD" 2>&1 | tail -3 | sed 's/^/   /'
elif [ -f .fw/gate-last ]; then
  echo "▸ GATE: last result $(cat .fw/gate-last) · live: ${GATECMD:-none}"
else
  echo "▸ GATE: no cached result yet · run: ${GATECMD:-bash fw-verify.sh}"
fi
[ -f CAPABILITIES.md ] && echo "▸ ARMS: CAPABILITIES.md (live — never ask 'do we have X'; deferred tool = LOAD via ToolSearch)"
[ -n "${FW_BOOT_EXTRA:-}" ] && { echo "▸ EXTRA ($PROJECT):"; bash -c "$FW_BOOT_EXTRA" 2>&1 | head -10 | sed 's/^/   /'; }
echo "⏱  session clock running — fw-handoff prints elapsed."
echo "Rules: trust this digest · grep INDEX.md, don't re-read the tree · one chat = one task."
