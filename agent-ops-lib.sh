#!/usr/bin/env bash
# agent-ops-lib.sh — shared BOOT/HANDOFF hardening, assembled from the best pattern in
# CALL AIOS). One vendored copy per project (same pattern each project already uses for
# its own helper scripts) — source it, then call the functions with YOUR project's
# filenames. Nothing here is destructive; every function is safe to call repeatedly.
#
# WHERE EACH IDEA CAME FROM:
#   aol_extract_date / aol_is_recent   — ps-boot.sh's UTC-tolerant today-or-yesterday math
#   aol_enforce_recorded               — ps-handoff.sh's fail-closed "don't let boot go stale"
#   aol_safe_commit                    — cc-safe-commit.sh's FUSE/virtiofs stale-lock clearing
#                                         + verify-the-commit-landed + one retry (most battle-
#                                         tested commit logic across the 4 repos)
#   aol_sync_claude_snapshot           — ps-handoff.sh's <!-- AUTO:NAME --> splice, generalized
#                                         so any project's CLAUDE.md can self-sync a status line
#   aol_doc_budget                     — nd-boot.sh / cc-resume.sh's context-budget guard
#                                         generalized so every project can feed a future scout
#
# Requires: bash, git (optional — functions degrade gracefully without it), python3
# (optional — only aol_sync_claude_snapshot needs it; warns and no-ops without it).

# ── date helpers (portable: GNU `date -d` and BSD `date -v`/`-j -f` both handled) ──

aol_today() { date +%Y-%m-%d; }

# aol_to_epoch <YYYY-MM-DD> — prints epoch seconds, or empty on parse failure.
aol_to_epoch() {
  date -j -f "%Y-%m-%d" "$1" "+%s" 2>/dev/null || date -d "$1" "+%s" 2>/dev/null
}

# aol_extract_date <file> [first|last] — an ISO date (YYYY-MM-DD) from the file.
# mode=last (DEFAULT) takes the LAST date found — correct for append-only logs where
# "first line" here, see cc-resume.sh fix).
# NOW.md/SESSION-LOG.md are explicitly documented + written newest-entry-on-top.
# Always pass the mode explicitly per-project; don't rely on the default across repos.
aol_extract_date() {
  local file="$1" mode="${2:-last}"
  [ -f "$file" ] || return 1
  if [ "$mode" = "first" ]; then
    # head -1 guards against the matched line containing MORE than one date token
    # (e.g. an entry note mentions another YYYY-MM-DD date on the same line as its
    # own leading timestamp) -- -m1 only limits which LINE grep stops scanning at,
    # -o still prints every match found ON that line, so without head -1 this can
    # return 2+ dates joined by a newline and silently break aol_to_epoch downstream,
    # which silently fails the NOW.md-freshness gate check with no useful error
    # (2026-07-20 fix-datebug, found when a handoff note mentioning a past date in
    # its own body broke fw-verify.sh RED with no explanation of which check/why).
    grep -m1 -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$file" 2>/dev/null | head -1
  else
    grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$file" 2>/dev/null | tail -1
  fi
}

# aol_days_since <YYYY-MM-DD> — integer days between the date and today (abs value).
# Prints "?" if either date fails to parse.
aol_days_since() {
  local d="$1" today de te
  today="$(aol_today)"
  de="$(aol_to_epoch "$d")"; te="$(aol_to_epoch "$today")"
  if [ -z "$de" ] || [ -z "$te" ]; then echo "?"; return 1; fi
  local diff=$(( (te - de) / 86400 )); [ "$diff" -lt 0 ] && diff=$(( -diff ))
  echo "$diff"
}

# aol_is_recent <YYYY-MM-DD> <max_days> — true if the date is within max_days of today.
# max_days=1 reproduces ps-boot's "today OR yesterday" UTC-tolerance (sandbox runs UTC,
# so a same-day-locally entry can read a day off here — 1 absorbs that without letting
# real staleness through).
aol_is_recent() {
  local days; days="$(aol_days_since "$1")" || return 1
  [ "$days" != "?" ] && [ "$days" -le "${2:-1}" ]
}

# ── fail-closed staleness enforcement (ps-handoff's core safety idea) ──

# aol_enforce_recorded <max_days> <file1[:label1[:mode]]> [file2[:label2[:mode]]] ...
# Checks that every listed file's newest date is within max_days of today. mode is
# "first" or "last" (default last — see aol_extract_date). Prints a 🔴 line per
# failure. Returns 0 only if ALL files pass — call this BEFORE a commit and abort the
# handoff on nonzero, so an unrecorded session can never look "saved."
aol_enforce_recorded() {
  local max="$1"; shift
  local ok=0 spec parts file label mode date days
  for spec in "$@"; do
    IFS=':' read -r -a parts <<< "$spec"
    file="${parts[0]}"
    label="${parts[1]:-$file}"
    mode="${parts[2]:-last}"
    date="$(aol_extract_date "$file" "$mode")"
    if [ -z "$date" ]; then
      echo "🔴 $label: no dated entry found (need a YYYY-MM-DD within ${max}d of today)."
      ok=1; continue
    fi
    days="$(aol_days_since "$date")"
    if [ "$days" = "?" ] || [ "$days" -gt "$max" ]; then
      echo "🔴 $label: newest date is $date (${days}d old, need ≤${max}d). Update it before handoff."
      ok=1
    else
      echo "   ✅ $label recorded $date (${days}d old)"
    fi
  done
  return $ok
}

# ── hardened commit (cc-safe-commit's logic, generalized to any repo) ──

# aol_safe_commit <message> <path1> [path2 ...]
# Clears a genuinely-stale .git/index.lock (age-gated, never touches a live lock),
# commits, then VERIFIES the hash advanced AND the message landed — retrying once.
# Returns: 0 committed-and-verified · 9 nothing to commit (already saved) · 2 not a
# git repo (skip, not a failure — matches nd-handoff's git-optional design) · 1 FAIL
# (could not verify after retry — print stays loud, never silently swallowed).
aol_safe_commit() {
  local msg="$1"; shift
  local paths=("$@")
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "  · no git repo here — state saved to files only (git-optional, not an error)"
    return 2
  fi
  local root; root="$(git rev-parse --show-toplevel)"
  local lock="$root/.git/index.lock"
  local stale_secs="${AOL_LOCK_STALE_SECS:-5}"

  _aol_clear_lock() {
    [ -e "$lock" ] || return 0
    local age; age=$(( $(date +%s) - $(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$stale_secs" ]; then
      echo "  · .git/index.lock is only ${age}s old — a commit may be live; waiting…"
      sleep "$stale_secs"
      [ -e "$lock" ] || return 0
    fi
    if rm -f "$lock" 2>/dev/null && [ ! -e "$lock" ]; then
      echo "  · cleared stale .git/index.lock"; return 0
    fi
    if mv -f "$lock" "$lock.stale-$(date +%s)" 2>/dev/null && [ ! -e "$lock" ]; then
      echo "  · stale lock could not be deleted (mount denied unlink) — renamed aside"; return 0
    fi
    echo "  ✗ COULD NOT clear stale .git/index.lock — mount denied both unlink and rename."
    echo "    Remove it by hand on the native shell: rm -f '$lock'"
    return 1
  }

  _aol_attempt() {
    git add -- "${paths[@]}" 2>&1 | grep -vE 'unable to unlink|Operation not permitted$|Device or resource busy' >&2
    if git diff --cached --quiet 2>/dev/null; then return 9; fi
    local before after
    before="$(git rev-parse HEAD 2>/dev/null || echo none)"
    git commit -q -m "$msg" >/dev/null 2>&1 || true
    after="$(git rev-parse HEAD 2>/dev/null || echo none)"
    if [ "$after" != "$before" ] && git log -1 --pretty=%s 2>/dev/null | grep -qF -- "$msg"; then
      return 0
    fi
    return 1
  }

  ( cd "$root" && _aol_clear_lock )
  ( cd "$root" && _aol_attempt ); local rc=$?
  if [ "$rc" -eq 9 ]; then echo "  · nothing to commit — already saved."; return 9; fi
  if [ "$rc" -ne 0 ]; then
    echo "  ⟳ first commit didn't verify — clearing lock and retrying once…"
    ( cd "$root" && _aol_clear_lock )
    ( cd "$root" && _aol_attempt ); rc=$?
  fi
  case "$rc" in
    9) echo "  · nothing to commit — already saved."; return 9 ;;
    0) echo "  ✓ committed + verified: $(cd "$root" && git log -1 --oneline)"; return 0 ;;
    *) echo "  ✗ FAIL — commit did not land/verify. Newest commit is still: $(cd "$root" && git log -1 --oneline)"
       echo "    Check for a pre-commit guard blocking it, or a lock the mount won't release."
       return 1 ;;
  esac
}

# ── CLAUDE.md snapshot auto-sync (ps-handoff's splice, generalized) ──

# aol_sync_claude_snapshot <claude_md_file> <marker_name> <content_line>
# Finds "<!-- AUTO:<marker_name> ... -->" ... "<!-- /AUTO:<marker_name> -->" in the
# file, keeps the opening marker line, writes ONE fresh content line right after it,
# then resumes at the closing marker. Idempotent — never accumulates old lines.
aol_sync_claude_snapshot() {
  local file="$1" marker="$2" content="$3"
  [ -f "$file" ] || { echo "  ⚠ $file missing — snapshot not synced"; return 1; }
  if ! grep -q "AUTO:${marker}" "$file"; then
    echo "  ⚠ no <!-- AUTO:${marker} --> block in $file — add one so this can auto-sync:"
    echo "      <!-- AUTO:${marker} -->"
    echo "      **NOW (auto-synced — do not edit by hand):** ..."
    echo "      <!-- /AUTO:${marker} -->"
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  ⚠ python3 not found — $file snapshot NOT synced (install python3, or edit by hand)"
    return 1
  fi
  AOL_FILE="$file" AOL_MARKER="$marker" AOL_CONTENT="$content" python3 - <<'PY'
import os
f = os.environ["AOL_FILE"]; marker = os.environ["AOL_MARKER"]; content = os.environ["AOL_CONTENT"]
s = open(f).read()
i = s.find(f"<!-- AUTO:{marker}")
j = s.find(f"<!-- /AUTO:{marker} -->")
if i >= 0 and j > i:
    k = s.find("\n", i)
    s = s[:k+1] + content + "\n" + s[j:]
    open(f, "w").write(s)
PY
  echo "  ✅ $file snapshot synced (marker: AUTO:${marker})"
}

# ── context-budget guard (nd-boot / cc-resume's doctrine-size check) ──

# aol_doc_budget <budget_lines> <file1> [file2 ...]
# Sums line counts across the given doctrine files and warns if over budget.
aol_doc_budget() {
  local budget="$1"; shift
  local total=0 f sz
  for f in "$@"; do
    if [ -f "$f" ]; then sz=$(wc -l < "$f" | tr -d ' '); total=$((total + sz)); fi
  done
  if [ "$total" -gt "$budget" ]; then
    echo "  ⚠ doctrine = ${total} lines (> ${budget}). Grep the section you need — don't read all."
  else
    echo "  ✓ doctrine = ${total}/${budget} lines — read just-in-time."
  fi
}


# aol_friction_log <journal_file> <friction_text> [scout_want_text]
# Appends a timestamped, greppable friction entry any project can accumulate — so a
aol_friction_log() {
  local journal="$1" friction="$2" scout="${3:-}"
  local ts; ts="$(date -u +'%Y-%m-%d %H:%M UTC')"
  touch "$journal"
  {
    printf '\n- %s\n' "$ts"
    [ -n "$friction" ] && printf '  FRICTION: %s\n' "$friction"
    [ -n "$scout" ] && printf '  SCOUT-WANT: %s\n' "$scout"
  } >> "$journal"
  echo "  ✓ friction logged to $journal"
}
