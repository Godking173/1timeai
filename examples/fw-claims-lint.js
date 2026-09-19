#!/usr/bin/env node
/* fw-claims-lint.js — CROA claims gate for a marketing funnel.            v1.0 (2026-08-15)

   L03 CLOSED WITH THIS FILE. The funnel — what EVERY PROSPECT sees — had no
   claims/compliance gate (RISKS.md #27, Hard Stop #1) while the CRM has had
   cc-claims-lint.js on the paid deliverable since 2026-08-04. Sonar sweep
   2026-08-14 (artifact: scout/cc-sonar-results/marketing-claims-*) confirmed
   across 310 repos that NO off-the-shelf CROA/claims linter exists — the
   correct move was always porting our own. This is that port: the same
   negation-aware rules, aimed at the funnel's client-facing source instead of
   the app's HTML file.

   WHAT IT SCANS: every .tsx/.ts under src/app EXCEPT src/app/api (server
   routes; the compliance engine legitimately names forbidden phrases there in
   order to prohibit them — same reason the CRM linter skips vendor blocks).

   ALLOWLIST MARKER: a line ending in  // claims-ok: <who> <date> <why>
   is skipped and COUNTED — deliberate, attributed exceptions (e.g. the operator's
   2026-08-09 decision to keep score-point language WITH the disclaimer,
   see RISKS #27 / boot doctrine) stay visible, never silent. The marker count
   prints on every run so an exception can't hide.

   KNOWN LIMITATION, on purpose: this lints STATIC copy in the source tree.
   Copy assembled at runtime from data is the audit page generator's job
   (cc-funnel-honesty-test.ts gates the false-presence class). Two gates, two
   failure classes.

   Run: node fw-claims-lint.js        (exit 0 clean / 1 violations)          */
const fs = require("fs");
const path = require("path");

const ROOT = __dirname;
const SCAN_ROOT = path.join(ROOT, "src", "app");
const SKIP_DIRS = new Set(["api", "node_modules"]);
const ALLOW = /\/\/\s*claims-ok:\s*\S+/;

const DENY = [
  { re: /bureaus show this account the same way/i, why: "hardcoded 'all bureaus agree' claim — must be computed from data" },
  { re: /\bpaid on time\b/i,                        why: "asserts payment timeliness as static copy — must be data-driven" },
  { re: /help(s|ing)? (the|your)( \w+){0,2} score/i, why: "score-impact claim (CROA) — never assert something is helping the score" },
  // negatable:true — skipped when the line is a NEGATED/disclaimer use ("we do not promise or
  // guarantee..."). Same principle as the CRM linter and frozen lesson L26 ("personal guarantee"
  // false positive): required legal disclaimers legitimately NAME the forbidden promise in order
  // to disclaim it. Positive uses still fire — the negation list is the SCORE.neg vocabulary.
  { re: /\bguaranteed?\b.{0,40}\b(deletion|removal|approval|approved|results?|score|repair)\b/i, why: "CROA: outcome guarantee in static copy", negatable: true },
  { re: /\b100%\s+guaranteed?\b/i,                  why: "CROA: absolute outcome guarantee", negatable: true },
  { re: /\b(remove|delete)\b.{0,30}\b(all|any|every)\b.{0,30}\b(negative|derogatory|collection)/i, why: "CROA: promise to remove all/any negative items", negatable: true },
  // v1.2 (2026-08-15) — gap-probe additions, each demonstrated escaping v1.1 first:
  // reversed word order ("results guaranteed") and first-person removal promises without the
  // legit dispute qualifier (removing INACCURATE/erroneous items is lawful FCRA language — exempt).
  { re: /\b(results?|removals?|deletions?|approvals?)\s+(is |are )?guaranteed\b/i, why: "CROA: outcome guarantee (reversed order)", negatable: true },
  { re: /\b(we|our team|let us)\b.{0,20}\b(remove|erase|delete)\b.{0,30}\b(collections?|negative items?|bad credit|charge-?offs?|late payments?)\b/i, why: "CROA: removal promise without inaccuracy qualifier", negatable: true, exempt: /\b(inaccurate|erroneous|incorrect|unverifiable|error)\b/i },
  { re: /\berase\b.{0,20}\b(bad credit|negative|derogatory)\b/i, why: "CROA: 'erase bad credit' class promise", negatable: true },
];
const SCORE = { re: /(raise|boost|increase|improve)\s+(your|their|the)(\s+\w+){0,2}\s+score/i, // {0,2}: catches "your CREDIT score", "your FICO score"
  neg: /\b(never|no|not|n['’]t|cannot|can['’]t|won['’]t|without|prohibit|isn['’]t|aren['’]t|don['’]t|doesn['’]t|illegal)\b/i,
  why: "CROA §404: no positive score-raise promise in static copy" };

function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name)) out.push(...walk(path.join(dir, e.name))); }
    else if (/\.(tsx?|jsx?)$/.test(e.name)) out.push(path.join(dir, e.name));
  }
  return out;
}

let hits = 0, allowed = 0, files = 0;
for (const f of walk(SCAN_ROOT)) {
  files++;
  const rel = path.relative(ROOT, f);
  fs.readFileSync(f, "utf8").split("\n").forEach((ln, i) => {
    const flag = (why) => {
      if (ALLOW.test(ln)) { allowed++; return; }
      hits++; console.log(`  ✗ ${rel}:${i + 1}: ${why}\n      ${ln.trim().slice(0, 120)}`);
    };
    for (const d of DENY) if (d.re.test(ln) && !(d.negatable && SCORE.neg.test(ln)) && !(d.exempt && d.exempt.test(ln))) flag(d.why);
    if (SCORE.re.test(ln) && !SCORE.neg.test(ln)) flag(SCORE.why);
  });
}

console.log(`fw-claims-lint: scanned ${files} client-facing file(s)` +
  (allowed ? ` · ${allowed} attributed claims-ok exception(s) (visible, not silent)` : ""));
if (hits === 0) console.log("fw-claims-lint: clean — no hardcoded factual/score claims in funnel copy");
else console.log(`\nfw-claims-lint: ${hits} forbidden claim(s) found — fix the copy, never mute the check`);
process.exit(hits ? 1 : 0);
