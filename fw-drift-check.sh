#!/usr/bin/env bash
# fw-drift-check.sh — the scripts must not silently fork. Verifies every file listed in
# fw-manifest.sha256 against what is on disk. ONE final line: ALL GREEN or RED.
#   bash fw-drift-check.sh            # check this folder
#   bash fw-drift-check.sh <dir>      # check a project that received copies of these scripts
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$HERE}"
MANIFEST="$HERE/fw-manifest.sha256"
[ -f "$MANIFEST" ] || { echo "fw-drift-check: RED — no fw-manifest.sha256 next to this script"; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then SUM="sha256sum"; else SUM="shasum -a 256"; fi
FAIL=0; N=0
while read -r want file; do
  [ -n "${file:-}" ] || continue
  N=$((N+1))
  if [ ! -f "$TARGET/$file" ]; then echo "  ✗ $file (missing in $TARGET)"; FAIL=1; continue; fi
  have="$($SUM "$TARGET/$file" | awk '{print $1}')"
  if [ "$have" = "$want" ]; then echo "  ✓ $file"; else echo "  ✗ $file (DRIFTED from the manifest)"; FAIL=1; fi
done < "$MANIFEST"
if [ "$FAIL" -eq 0 ]; then echo "fw-drift-check: ALL GREEN ($N files match)"; exit 0; fi
echo "fw-drift-check: RED — a copy drifted. Re-copy from the canonical set, or regenerate the manifest on purpose."
exit 1
