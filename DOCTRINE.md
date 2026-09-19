# 1TimeAi — the doctrine

**One time AI.** Use a model to figure something out once. Prove it on a few real uses. Then lock
it in as a deterministic tool — a script, a check, a rule — and write it down where the next
session will look. After that, the model never solves it again; it runs the tool.

## The loop

1. **Try it with AI.** Unknown problem, no tool yet → let the model explore. Cheap to start.
2. **Prove it.** Use the result on real work more than once. If it holds, it earns a tool.
3. **Lock it in.** Turn it into a zero-token script with a real check that can fail.
4. **Catalog it.** Add it to `TOOLBOX.md` with what it does, how to run it, and its proof.
5. **Never re-derive.** Before building or reasoning anything out, `grep TOOLBOX.md` first.

## The rules that keep it honest

- **Prose is never proof.** A claim is backed by a command someone else can re-run, and the
  record says which machine it ran on.
- **Wired ≠ verified.** "Done" means the gate is GREEN *and* you read the output.
- **A check that cannot fail is not a check.** Every frozen lesson gets an executable check; a
  lesson without one is still just a note.
- **UNKNOWN stays UNKNOWN.** Say what could not be verified; never round it up to fine.
- **Close every loop.** Search for prior art before building from scratch; run the gate; freeze
  the lesson; hand off through the script, not by hand.
- **Handoffs live on disk.** The next session must be able to rebuild the state from the repo
  alone — `NOW.md`, `SESSION-LOG.md`, `INDEX.md`, git — never from chat memory.
- **Don't back-fill history.** If it wasn't recorded when it happened, leave the gap visible.
- **One chat, one task.** End the session when the task closes; the next one boots in seconds.

## The words

- **BOOT** → `bash fw-boot.sh` — trust its digest.
- **HANDOFF** → `bash fw-handoff.sh "<one line>" [--note "<details>"]`.
- **GATE** → `bash fw-verify.sh` — generic honesty checks + `.fw-checks.sh` for this project.
- **DRIFT** → `bash fw-drift-check.sh` — the scripts themselves must not silently fork.
