# TOOLBOX — every built tool has a home (template)

Before writing any script or reaching for a model: `grep -i <word> TOOLBOX.md` — the tool
probably exists. Classes: WIRED (called by code or a gate) · HAND (you run it) · SCHEDULED ·
ARCHIVE (dead; keep only for logic worth harvesting).

| tool | class | what it does | run | proof it works |
|---|---|---|---|---|
| `fw-boot.sh` | HAND | fresh-session digest: NOW · git · next · risks · cached gate | `bash fw-boot.sh` | `tests/roundtrip.sh` |
| `fw-verify.sh` | WIRED | the ship-gate; generic checks + `.fw-checks.sh`; ONE final line | `bash fw-verify.sh` | `tests/roundtrip.sh` |
| `fw-handoff.sh` | HAND | writes NOW/SESSION-LOG/INDEX, runs the gate, commits | `bash fw-handoff.sh "<line>"` | `tests/roundtrip.sh` |
| `agent-ops-lib.sh` | WIRED | shared helpers (dates, lock-proof commit, CLAUDE.md sync) | (sourced) | `bash -n agent-ops-lib.sh` |
| `fw-drift-check.sh` | WIRED | every copy of the scripts matches `fw-manifest.sha256` | `bash fw-drift-check.sh` | itself |
| `examples/fw-claims-lint.js` | HAND | example per-project check: lints copy for forbidden claims | `node examples/fw-claims-lint.js` | `node --check` |

Add a row the moment a tool exists. A tool with no row is an orphan; an orphan gets rebuilt.
