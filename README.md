# 1TimeAi

Solve a thing with AI **once**, prove it over a few real uses, then lock it in as a deterministic
script and catalog it — so nothing already solved is ever re-derived, and every project gets faster
and cheaper over time. This repo is the operating loop that makes that a habit instead of a hope:

    bash fw-boot.sh                       # BOOT   — where are we (NOW · git · next · risks · cached gate)
    bash fw-verify.sh                     # GATE   — honesty checks; ONE final line: ALL GREEN or RED
    bash fw-handoff.sh "<one line>"       # HANDOFF — NOW.md + SESSION-LOG + INDEX regen + gate + commit
    bash fw-drift-check.sh                # DRIFT  — every copy of these scripts still matches the manifest

The doctrine behind it: `DOCTRINE.md`. The catalog that stops re-building: `TOOLBOX.md`.

## Install into a project

    cp fw-boot.sh fw-handoff.sh fw-verify.sh agent-ops-lib.sh <your-repo>/
    cp .fw-config.example  <your-repo>/.fw-config      # edit
    cp .fw-checks.sh.example <your-repo>/.fw-checks.sh # add the checks only that project needs
    # your CLAUDE.md (or any agent instructions file) needs the sync block:
    #   <!-- AUTO:NOW -->
    #   <!-- /AUTO:NOW -->

## Prove it

    bash tests/roundtrip.sh   # blank project → boot → handoff → NOW/SESSION-LOG/INDEX on disk → gate GREEN → committed

`examples/fw-claims-lint.js` is one real per-project check (a marketing-copy lint) to copy the
shape from. This tree was produced by a deterministic exporter; `MANIFEST.sha256` lists every file.
