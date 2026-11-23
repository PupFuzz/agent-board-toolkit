#!/usr/bin/env python3
r"""pr-body-lint.selftest.py — the PR-body lint's own controls (card#9073).

LOCAL EDIT — agent-board-toolkit only, NOT the framework's bytes (card#13778). This copy is coord
0.77.0's `templates/bin/pr-body-lint.selftest.py` with the changes below, each marked `LOCAL EDIT` at
its site, because this repo vendors the lint in `.github/pr-body-lint/` rather than `bin/` (`PIN`
there says why):
  1. `_pr_checkout` (arm i step 10, re-run by arm k) writes the fixture repos' lint at
     `VENDORED_LINT_REL`, the path this repo's workflow reads the base copy from, instead of
     `bin/pr-body-lint.py`; the comments naming that path say so too.
  2. arm m's `DESIGN_APPROVED_ID_RE` guard prints a NOTICE and skips when no `coord-ask-operator`
     sits beside this file, instead of failing: this repo deliberately ships no copy of it.
Every other line is the framework's. Drop this edit and re-copy the file unchanged once card#13778
lets the framework's selftest take the lint's path as an input; `PIN` records the edit.

THE FAILURE THIS GUARDS IS SILENT, WHICH IS WHY EVERY ROW IS RED-THEN-GREEN. A lint that has
stopped reding is byte-indistinguishable from a body that complies: both print one OK line and
exit 0. So no rule here is trusted because it passed — each is driven against a body built to
break it, and each is additionally driven through a MUTANT of the shipped file with that one rule
disabled, which must flip the answer. A rule whose mutant still reds was never what produced the
red.

THERE IS ONE SUCH PAIR PER RULING, each keyed in `FIXTURES` below. Each is a REAL BODY OF A REAL PR
BEFORE AND AFTER IT, except where its negative is HAND-BUILT and says so below (`pr-body-lint-
fixtures/README.md` owns their provenance and the sha256 pins are in `FIXTURES`). The fw#847 pair —
its v0.50.0 body — is the commentary ruling:

  * the KNOWN POSITIVE — fw#847's v0.50.0 body as the operator read it, which must RED, and must
    red on the two rows the operator named BY NAME, not merely somewhere;
  * the KNOWN NEGATIVE — the same body after the rewrite, which must PASS.

The fw#891 pair — its v0.51.0 body — is the ATTRIBUTION-LINE ruling (operator, 2026-09-11,
card#9229 → card#9073 leg E: a PR body carries no `FROM:` / `TO:` line, on any repo). Its positive
is the body at `2026-09-10T14:08:53Z`, which opened on `FROM: pm`; its negative is the same body
after the line was struck. `arm_f` drives it, and it drives the same pair through a mutant with the
rule unwired, because the positive ALSO reds on `heading-not-allowed` — "it reds" would therefore
have been true of that body before this rule existed at all.

The fw#873 pair — its body — is the LIVE-STATE READING rule (card#9073 comment 4102, leg B-2).
Its positive is the body as first published (`2026-09-08T20:59:57Z`), whose `CI has not run on this
head. The branch is not pushed` and `2 commits behind origin/dev` lines are the instance the rule
was minted on. ⛔ ITS NEGATIVE IS HAND-BUILT, not a later revision: fw#873 never rewrote those lines
into derivations (its later revisions restated readings), so no real negative exists. The warning
below applies to it, and what answers that warning is an assertion rather than trust: `arm_g`
requires the negative to be BYTE-IDENTICAL to the real positive on every line but exactly the lines
the rule reds on, each replaced by the command that re-derives it and its pass conditions. And
`arm_g` drives the pair through a mutant with the rule unwired, because the positive ALSO reds on
older rules.

`arm_h` is the BOT-AUTHOR exemption (card#9927) and it has no PR pair, because its subject is not a
body at all — it is WHO authored one. Its positive and negative are therefore the same body under
two author types, and the arm's long half is the negative side: every value that is not the exact
string GitHub emits must leave the two audit rows required, the author LOGIN spellings a
login-based discriminator would have keyed on included.

`arm_i` is the RELEASE SCOPE (card#10493), and like `arm_h` its pair is not two bodies but one body
under two TITLES: a feature title must not judge a feature repo's own `## Summary` against the
release allow-set, and a release title must still red on it — while the OUT table's content rules
still red on a feature PR, fw#873's own body under its own feature title included. Its controls force
the one predicate, `judged_as_release`, each way, plus a copy that reads a blank title as a feature
PR, and two copies that move rules BEHIND the predicate: the content rules, and every rule.

`arm_j` is `ai-attribution` (card#10673). Its known positive is a REAL body: fw#891's live body
ends on the harness's `Generated with [Claude Code]` footer. Its negative is that body with that one
line removed by its literal text, never by the matcher under test. Every shape is driven red on a
line the harness actually writes (or `coord-post` wrote, before card#10673 retired its stamp), and each has a near miss that must pass — a
placeholder, or the same words mid-line in prose. Its control unwires the rule, and fw#891's footer
must then pass.

`arm_o` is `merge-instruction` (card#13034), a RELEASE-only rule. Its known positive is
AIMLA-org/platform#467's line as card#13034 quotes it; PupFuzz/kanban-board#592's struck line could
not be read, so its rows are RECONSTRUCTED from the release-body template that PR was drafted from,
and say so. Its negatives are lines naming squash as a subject, the generated `## Bundled` list, and
the same positive line on a feature PR. Its controls unwire the rule, run it on every PR, drop the
`## Bundled` skip, disable each shape, and drop the clause-opening narrowing.

A rule that reds on both is measuring length, not the standard. The pair is what tells them apart,
and it is why a hand-written "compliant body" fixture is present as well but is not the whole of
the negative side: a body someone wrote to pass the lint they just wrote proves nothing about a
body someone wrote to ship a release.

⛔ THE MUTANTS ARE ASSERTED TO HAVE APPLIED. A substitution that matched nothing yields an
unmutated copy that passes every assertion and reads exactly like a control that ran (this repo's
own measured lesson — `coord-review.selftest.py`'s `MUTANTS` table states it). Every mutation here
is checked for having changed the bytes before its result is believed.

⛔ AND THE SHIPPED FILE IS NEVER TOUCHED. Mutants are written into a temp directory; the original's
sha256 is taken before the first row and re-taken after the last, and a difference is a FAILURE of
this suite rather than a note — a guard that edits the thing it guards has no way to say so.

HERMETIC: no network, no `$HOME`, no coordination config. Everything it reads is in this
directory, except ONE file: the workflow that runs the lint in CI, which `arm_i` step (9) reads to
check that it passes the PR title (card#10493), and step (10) runs — its lint step's script, with
`bash`, in throwaway local `git` repos shaped as a PR's merge-commit checkout — to check that a PR
is judged by its BASE's copy of the lint (card#12387). The lint itself also reads a repo's declared release
headings from the directory it runs in (card#12387); every CLI row runs it in an empty directory
of its own, except `arm_n`'s, which build the file they mean.

WHERE THAT WORKFLOW IS, IS AN INPUT (card#10719). In this plugin it sits at
`templates/workflows/pr-body-lint.yml`, beside this file's `bin/`, and that is the default. A repo
that vendors the lint and this selftest into its own `bin/` keeps the workflow at
`.github/workflows/<its name>.yml`, so it names the file:

    python3 bin/pr-body-lint.selftest.py --workflow .github/workflows/pr-body-lint.yml
    PR_BODY_LINT_WORKFLOW=.github/workflows/pr-body-lint.yml python3 bin/pr-body-lint.selftest.py

`--workflow` wins over the variable. A workflow that cannot be read is a FAILURE of arm i that names
the path it tried and these two ways to point it elsewhere; every other arm still runs and reports.
It is never a skip: a vendored install that could not find its workflow would otherwise never
check its own gate. `arm_k` builds a vendored copy and runs it both ways: with no input, and with
`--workflow`.

`arm_n` is the REPO-DECLARED RELEASE HEADINGS (card#12387): a release body carrying a heading the
adopting repo declares passes; the same body with no file reds `heading-not-allowed` (its control);
an undeclared heading, and a near miss of a declared one, still red with the file present; a line
written with the `## ` marker is a fault; and a feature PR's verdict does not move.

`arm_l` is the VERSION CLASSIFICATION (card#9748): every rule id derived from this lint's own
`Finding("<id>", …)` sites carries a `VERSION_CLASSIFICATION` row, and a planted rule with no row
is seen unclassified.
"""
from __future__ import annotations

import argparse
import hashlib
import ast
import importlib.machinery
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# card#11746: pin UTF-8 + `backslashreplace` on stdout/stderr, so on a cp1252 seat a character the
# code page cannot encode costs its own glyph, never this suite's verdict.
if __name__ == "__main__":
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except Exception:
            pass

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "pr-body-lint.py")
FIXTURE_DIR = os.path.join(HERE, "pr-body-lint-fixtures")
# The plugin's own layout. A vendored install overrides it — see the module docstring.
DEFAULT_WORKFLOW = os.path.join(HERE, "..", "workflows", "pr-body-lint.yml")
WORKFLOW_ENV = "PR_BODY_LINT_WORKFLOW"
# Set on the copies `arm_k` runs, so a copy does not run `arm_k` again.
NESTED_ENV = "PR_BODY_LINT_SELFTEST_NESTED"
# The repo-declared release headings file, relative to the directory the lint runs in (`arm_n`).
RELEASE_HEADINGS_REL = ".github/pr-body-lint-release-headings.txt"
# The directory every CLI row runs in unless it names one: an EMPTY directory made in `main`, so no
# row reads a declared-headings file from wherever this suite happened to be started (a vendored
# run from an adopting repo's root would otherwise judge every CLI row under that repo's extras).
EMPTY_CWD = None


def resolve_workflow(arg, environ):
    """The workflow `arm_i` step (9) reads, and where that path came from: `--workflow` over the
    variable over the plugin's own layout. A variable set to nothing is a value, not an absence —
    it names no file, and the failure line says so rather than reading some other file."""
    if arg is not None:
        return arg, "--workflow"
    if WORKFLOW_ENV in environ:
        return environ[WORKFLOW_ENV], WORKFLOW_ENV
    return DEFAULT_WORKFLOW, "the default, this plugin's own layout"


WORKFLOW = DEFAULT_WORKFLOW
WORKFLOW_SOURCE = "the default, this plugin's own layout"

# ⛔ THE PINS ARE LOAD-BEARING, NOT DECORATION, AND THEY ARE THE ONE PLACE A FIGURE IS WRITTEN
# DOWN IN THIS FILE. "The known positive" is a CLAIM about WHICH revision of a real PR body this
# suite is run against — the live body at #847 is the rewritten one and passes — so the claim
# needs a check a second reader can re-run (`sha256sum`), not a filename that could name anything.
# Every other quantity here is derived at run time.
# ⛔ AND THEY ARE `.md.txt`, NOT `.md`, WHICH IS A CLAIM ABOUT WHAT THEY ARE. A captured PR body
# is DATA — another document's history, preserved verbatim — not a document of this tree, and this
# repo's markdown guards walk `*.md` over the whole tree and grade what they find. The positive
# fixture's own prose NAMES this repo's doc-ownership tag, in the elliptical form that repo's
# convention does not accept — so `doc-crossref-drift` read the release body as making a
# malformed ownership claim and reported it by name. The finding was true about a file nobody
# may edit: fixing it would mean editing the evidence. The extension keeps the fixtures out of
# every `*.md` population at once, and that guard's whole-tree arm carries a declared skip for
# the one file, beside the one it already carries for itself and for the same stated reason.
FIXTURES = {
    "positive": ("fw847-v0.50.0-body-2026-09-08T220229Z.md.txt",
                 "31cfc5649c34f09601c76aaed5817c62d413cd5a5a1e6b8ae2456b3c751a8be4"),
    "negative": ("fw847-v0.50.0-body-rewritten.md.txt",
                 "85c244b7d3fbfa4bf79d2718c28ed902cb490e1ab16b3d4cd4196d98cb0fb21a"),
    # The attribution-line pair — fw#891, the same PR either side of the 2026-09-11 ruling.
    "attr_positive": ("fw891-v0.51.0-body-2026-09-10T140853Z.md.txt",
                      "7f269aeb45243018829929c80c9c76a460bad26e1e237f229fca19707a225331"),
    "attr_negative": ("fw891-v0.51.0-body-rewritten.md.txt",
                      "63ca4812628c7055faa5d2c8ca5e922b3cfa28904e2c1869deaa48e9c7c4c8eb"),
    # The live-state-reading pair — fw#873 as first published, and a HAND-BUILT negative.
    "live_positive": ("fw873-body-2026-09-08T205957Z.md.txt",
                      "bfb44759b25a3cbea31a63ecddadea35c9065fae9d5c0e4c6a1c56414783d3f9"),
    "live_negative": ("fw873-body-hand-built-derivations.md.txt",
                      "4ec27d315998a93c41658a0f08437561ae009d01574e0d75c7051cac6a132656"),
}

# A body written to the IN table, by hand — the second negative. It carries the machine-read rows
# in BOTH spellings the audit-row grammar accepts (bold and plain), a fenced example QUOTING four
# things the lint reds on — including the `FROM:` / `TO:` lines card#9073 leg E now refuses — and
# an H3 inside `## Highlights`, so a green here is also a statement that none of those is a false
# accusation. ⛔ IT OPENS ON ITS SCOPE LINE. It used to open on `FROM: impl` / `TO: pm`, which was
# the standard then and is a finding now; a fixture kept in the old shape would have made this
# suite's own "compliant" body red on the rule it ships.
COMPLIANT_BODY = """**`dev → main` release PR — v1.4.0.** Bundles the commits since `v1.3.0`, enumerated in `## Bundled`.

**Built:** dispatched (coder ×1 / mechanic ×0)
**Coordinated in:** acme/coordination#412
Origin: bundle

## Highlights

- `acme-sync` refuses a config whose `retry.window` is unset, where it used to start and stall.

### For anyone running the daemon

- The unit file now reads `/etc/acme/sync.env`; an install that kept its keys in the unit itself
  moves them before the upgrade.

## Upgrade warnings

1. Run `acme-sync migrate` BEFORE restarting the daemon — the new schema is not read by v1.3.0.

## Bundled (generated — do not hand-edit)

- #310 — refuse an unset retry window
- #311 — read the env file

<!-- release-manifest:shipped-refs=310,311 -->

The lint's own rules, quoted rather than claimed — this block must not red:

```
## Correlation gaps
### Why MINOR (1.3.0 → 1.4.0)
Built: dispatched (coder ×9 / mechanic ×9)
Coordinated in: evil/repo#1
FROM: evil
TO: all
```
"""

CHECKS = 0
FAILURES: list[str] = []
SEEN_RED: list[str] = []


def check(name, cond, detail=""):
    global CHECKS
    CHECKS += 1
    if not cond:
        FAILURES.append("%s: %s" % (name, detail))
    return bool(cond)


def seen_red(name):
    SEEN_RED.append(name)


def sha256_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def load_tool(path=TOOL):
    """Load a copy of the lint as a module. NEVER under the name `__main__` — the file is
    script-shaped and would run its CLI on import."""
    spec = importlib.util.spec_from_file_location(
        "pr_body_lint_under_test_%s" % re.sub(r"\W", "_", path), path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ── card#11037: the provenance rows, and the arms written before them ─────────────────────────────
# Every body this suite judged before card#11037 declares no `Origin:`, and that card made the line
# required on every PR. An arm about some OTHER rule still asserts "this body passes", so the
# harness judges such a body WITH a declared origin added (`declared`), through `rules_on` and
# `run_cli` alike — the arm then measures the rule it was written for, and its "passes" means what
# it meant. `arm_m_provenance` drives the provenance rows themselves with `raw=True`, so nothing is
# added there. The line is `Origin: bundle` because most of these bodies are release bodies; it is
# appended at the END, so no line a finding quotes moves.
DECLARED_ORIGIN = "Origin: bundle"


def declared(body):
    """`body` with `DECLARED_ORIGIN` appended when it carries no `Origin:` line of its own."""
    if mod_main.field_values(body, "Origin"):
        return body
    return body.rstrip("\r\n") + "\n\n" + DECLARED_ORIGIN + "\n"


def rules_on(mod, body, author_type=None, title=None, raw=False):
    """The set of RULE NAMES `mod` reports on `body`, for a PR whose author account type is
    `author_type` (`None` = the caller has none, which is every caller but CI) and whose TITLE is
    `title`. `title=None` passes NO title at all, which is how every arm but `arm_i` calls it — and
    that is deliberate: those arms keep driving the no-title path, which is judged as a RELEASE body
    (the behaviour before card#10493), so the whole release standard stays pinned by them."""
    kw = {} if title is None else {"title": title}
    return sorted({f.rule for f in mod.findings(body if raw else declared(body), author_type, **kw)})


def read_fixture(key):
    name, want = FIXTURES[key]
    path = os.path.join(FIXTURE_DIR, name)
    got = sha256_file(path)
    check("fixture `%s` is the revision this suite claims (sha256 pinned; "
          "`pr-body-lint-fixtures/README.md` owns which revision that is)" % name,
          got == want, "sha256 %s, pinned %s" % (got, want))
    with open(path, encoding="utf-8") as fh:
        return fh.read()


# ══════════════════════════════════════════════════════════════════════════════════════════════
# A — THE TWO CONTROLS
# ══════════════════════════════════════════════════════════════════════════════════════════════
def arm_a_the_controls(mod):
    positive = read_fixture("positive")
    negative = read_fixture("negative")

    got = rules_on(mod, positive)
    # The operator named two things. Both must be among the findings BY RULE — "it reds" is not
    # the claim; "it reds on the commentary the operator pointed at" is.
    check("A the KNOWN POSITIVE reds", got, "no finding on fw#847's v0.50.0 body")
    check("A ...on `## Correlation gaps` (heading-not-allowed)",
          "heading-not-allowed" in got, got)
    check("A ...and on `### Why MINOR (0.49.0 → 0.50.0)` (banned-opener)",
          "banned-opener" in got, got)
    lines = {f.rule: f.text for f in mod.findings(positive)}
    check("A ...and each finding quotes the offending line rather than a tally",
          "Correlation gaps" in lines.get("heading-not-allowed", "")
          and "Why MINOR" in lines.get("banned-opener", ""), lines)

    check("A the KNOWN NEGATIVE — the SAME body, rewritten to the standard — passes",
          rules_on(mod, negative) == [], rules_on(mod, negative))
    check("A the hand-written compliant body passes, fenced counter-examples and all",
          rules_on(mod, COMPLIANT_BODY) == [], rules_on(mod, COMPLIANT_BODY))


# ══════════════════════════════════════════════════════════════════════════════════════════════
# B — EVERY RULE, DRIVEN ON A BODY BUILT TO BREAK IT
# ══════════════════════════════════════════════════════════════════════════════════════════════
def arm_b_each_rule(mod):
    def without(line_filter):
        return "\n".join(l for l in COMPLIANT_BODY.split("\n") if not line_filter(l))

    rows = [
        ("scope-line", "## Highlights\n\nBuilt: dispatched (coder ×1 / mechanic ×0)\n"
                       "Coordinated in: acme/coordination#412\n",
         "a body that opens on a heading has no scope line"),
        ("heading-not-allowed", COMPLIANT_BODY + "\n## Review round 2\n",
         "a section the OUT table homes elsewhere"),
        ("banned-opener", COMPLIANT_BODY + "\nVerification: the suite is green at this head.\n",
         "self-review narration, at the start of a line"),
        ("built-missing", without(lambda l: l.startswith("**Built:")),
         "the machine-read row the IN table names"),
        ("coordinated-missing", without(lambda l: l.startswith("**Coordinated in:")),
         "the PR ↔ thread audit anchor"),
    ]
    for rule, body, why in rows:
        got = rules_on(mod, body)
        check("B `%s` reds on %s" % (rule, why), rule in got, got)

    # ⛔ AND THE DECORATION ARM, because `### Why` and `- **Why**` are the shapes that actually
    # ship — a rule that only matches a bare word at column 0 would have passed the very body
    # this card was minted against.
    # ⛔ `__Why__` AND `_Why_` ARE IN THIS LIST BECAUSE THEY PASSED. The decoration stripper
    # strips the LEADING `__`, so the phrase arrived at the opener pattern as `Why__ MINOR`, and a
    # `(?![\w-])` lookahead refused it — `_` is a `\w` character. The rule's coverage turned on
    # which of two equivalent markdown bold spellings the author typed (fw#898 r1, M2). The row
    # below is the one this list could not have been written from reading the code.
    for lead in ("Why", "### Why", "- Why", "  - **Why**", "> Why", "1. Why", "#### **Why**",
                 "__Why__", "_Why_", "> __Why__"):
        body = COMPLIANT_BODY + "\n%s this release is MINOR.\n" % lead
        check("B `banned-opener` sees through markdown decoration (%r)" % lead,
              "banned-opener" in rules_on(mod, body), rules_on(mod, body))

    # …and does NOT fire mid-line, which is the other half of a rule that discriminates.
    body = COMPLIANT_BODY + "\n- The daemon explains why it refused, in its own log.\n"
    check("B `banned-opener` does not fire on the word mid-line",
          "banned-opener" not in rules_on(mod, body), rules_on(mod, body))

    # …and the hyphen half of the lookahead is UNCHANGED by the class narrowing above: a rule that
    # gained `__Why__` by also convicting `Why-not` would be a nuisance, not a fix.
    for lead in ("Why-not this release is MINOR", "Whyever it happened", "Controls-Plane moved"):
        body = COMPLIANT_BODY + "\n%s.\n" % lead
        check("B `banned-opener` still does NOT fire on %r" % lead,
              "banned-opener" not in rules_on(mod, body), rules_on(mod, body))

    # ⛔ `Release artifacts` IS IN THE ALLOWLIST AND THE GENERATOR'S OTHER TWO H2s ARE NOT — the
    # operator's ruling on fw#898 r1, driven rather than asserted in prose. Arm D plants the
    # removal and requires this green to flip.
    arts = COMPLIANT_BODY + "\n## Release artifacts\n\n- [ ] SBOM regenerated for v1.4.0\n"
    check("B `## Release artifacts` — the IN table's release-artifacts checklist row, emitted by "
          "`release-pr-body` — PASSES", rules_on(mod, arts) == [], rules_on(mod, arts))
    for heading in ("## Card coverage", "## Correlation gaps"):
        body = COMPLIANT_BODY + "\n%s\n" % heading
        check("B `%s` still reds — leg A's defect is the GENERATOR's, not a widened allowlist"
              % heading, "heading-not-allowed" in rules_on(mod, body), rules_on(mod, body))

    # ⛔ `re.IGNORECASE` IS A SHIPPED PROPERTY AND NOTHING BOUND IT (fw#898 r1, m1): the reviewer
    # dropped the flag from `_BANNED_RE` and this whole suite stayed rc 0. The row asserts the
    # lower-case spelling reds; arm D's mutant is what makes it a control rather than a row that
    # happens to be true.
    lower = COMPLIANT_BODY + "\n## why minor\n"
    check("B `banned-opener` is CASE-INSENSITIVE — `## why minor` reds on the opener, not only on "
          "the heading rule", "banned-opener" in rules_on(mod, lower), rules_on(mod, lower))


# ══════════════════════════════════════════════════════════════════════════════════════════════
# C — THE FENCE RULE, WHICH IS WHAT KEEPS THE LINT FROM MANUFACTURING FINDINGS
# ══════════════════════════════════════════════════════════════════════════════════════════════
def arm_c_fences(mod, td):
    fenced_only = ("**`dev → main` release PR — v1.4.0.** Bundles the commits since `v1.3.0`.\n\n"
                   "Built: dispatched (coder ×1 / mechanic ×0)\n"
                   "Coordinated in: acme/coordination#412\n\n"
                   "```\n## Correlation gaps\n### Why MINOR\n```\n")
    check("C a heading and an opener that exist only INSIDE A FENCE are payload, not findings",
          rules_on(mod, fenced_only) == [], rules_on(mod, fenced_only))

    # THE CONTROL: fence-blind, the same body must red on both. Without this the row above is
    # equally consistent with a lint that has stopped seeing headings at all.
    blind = mutant(td, "fence-blind",
                   ("    flags, fence_char, fence_len = [], None, 0",
                    "    flags, fence_char, fence_len = [], None, 0\n"
                    "    return [False] * len(text.split(chr(10)))"))
    got = rules_on(blind, fenced_only)
    if check("C CONTROL: a FENCE-BLIND lint reds on the very same body — the fence rule is what "
             "withheld those findings, not their absence",
             "heading-not-allowed" in got and "banned-opener" in got, got):
        seen_red("C the fence rule, driven red by a fence-blind mutant that reads a quoted "
                 "example as the body's own claim")

    # The audit rows are read through the same tracker: a body whose ONLY `Built:` line is fenced
    # reads as ABSENT — the fail-safe direction, and the card#9047 r2 defect in this file's copy.
    check("C an audit row that exists only inside a fence reads as ABSENT, never as present",
          "built-missing" in rules_on(mod, fenced_only + "\n```\nBuilt: forged\n```\n")
          or mod.audit_fields("```\nBuilt: forged\n```\n")["Built"] is None,
          mod.audit_fields("```\nBuilt: forged\n```\n"))

    arm_c_html_comments(mod, td)


# An HTML comment is not rendered, so a PR template's guidance comments are no more the body's own
# claim than a fenced example is (card#12387 item 3). Each body below is the COMPLIANT body plus
# comment lines that, read as content, red on a rule.
TEMPLATE_COMMENT_BLOCK = ("<!--\n"
                          "Why: say what changed for someone installing it.\n"
                          "## Notes\n"
                          "CI is green at this head — do not write that line.\n"
                          "-->\n")
TEMPLATE_COMMENT_LINE = "<!-- CI is green at this head? Then delete this line. -->\n"


def arm_c_html_comments(mod, td):
    for name, comment in (("multi-line", TEMPLATE_COMMENT_BLOCK),
                          ("single-line", TEMPLATE_COMMENT_LINE)):
        body = COMPLIANT_BODY + "\n" + comment
        check("C a %s HTML comment is not rendered, so the lines inside it are not findings"
              % name, rules_on(mod, body) == [], rules_on(mod, body))

    # THE CONTROL: comment-blind, the same body reds on the rules the comment's lines break.
    blind = mutant(td, "comment-blind",
                   ("_HTML_COMMENT_OPEN_RE = re.compile(r'^ {0,3}<!--')",
                    "_HTML_COMMENT_OPEN_RE = re.compile(r'(?!)')"))
    got = rules_on(blind, COMPLIANT_BODY + "\n" + TEMPLATE_COMMENT_BLOCK)
    if check("C CONTROL: a COMMENT-BLIND lint reds on the template comment's lines — the comment "
             "rule is what withheld them",
             {"banned-opener", "heading-not-allowed", "live-state-reading"} <= set(got), got):
        seen_red("C the HTML-comment rule, driven red by a comment-blind mutant that reads a "
                 "template's guidance comment as the body's own lines")

    # Masking is not only lenient: a scope line that exists only inside a comment is not rendered,
    # so the body has none.
    hidden_scope = ("<!--\nDescribe the range this merges.\n-->\n\n"
                    "Built: dispatched (coder ×1 / mechanic ×0)\n"
                    "Coordinated in: acme/coordination#412\n\n## Highlights\n\n- x\n")
    check("C a scope line that exists only inside an HTML comment is no scope line",
          "scope-line" in rules_on(mod, hidden_scope), rules_on(mod, hidden_scope))

    # The comment ends on the first line holding `-->`, and what follows is content again.
    after = COMPLIANT_BODY + "\n" + TEMPLATE_COMMENT_BLOCK + "Why this release is MINOR.\n"
    check("C the line after a comment's `-->` line is content again",
          rules_on(mod, after) == ["banned-opener"], rules_on(mod, after))

    # A `<!--` that does not OPEN a line is not a comment block: quoted in backticks mid-line, as
    # this repo's own bodies quote markers, it hides nothing after it.
    quoted = COMPLIANT_BODY + "\nA line opening `<!--` is skipped.\nWhy this release is MINOR.\n"
    check("C a `<!--` quoted mid-line opens no comment — the next line is still judged",
          "banned-opener" in rules_on(mod, quoted), rules_on(mod, quoted))

    # A `<!--` inside a fence is the fence's payload, not a comment that runs on past it.
    fenced_open = COMPLIANT_BODY + "\n```\n<!--\n```\n\n## Correlation gaps\n"
    check("C a `<!--` inside a fence opens no comment — a heading after the fence is still judged",
          "heading-not-allowed" in rules_on(mod, fenced_open), rules_on(mod, fenced_open))

    # And the converse: a fence line inside a comment is the comment's text, not a fence that runs
    # on past the `-->` and hides the rest of the body. Both blocks are tracked in ONE loop
    # (`fenced_flags`), which is what makes this hold; a comment pass layered over the fence flags
    # would leave everything after this comment unjudged.
    comment_fence = (COMPLIANT_BODY + "\n<!--\nQuote an example in a fence:\n```\n-->\n\n"
                     "## Correlation gaps\n")
    check("C a fence line inside an HTML comment opens no fence — a heading after the comment is "
          "still judged", rules_on(mod, comment_fence) == ["heading-not-allowed"],
          rules_on(mod, comment_fence))

    # The attribution rules judge what the body CARRIES, and a comment carries its text into the
    # squash message the body becomes. The context stamp IS a comment.
    for rule, line in (("ai-attribution", "<!-- CTX: 47% | 94200tok -->"),
                       ("attribution-line", "<!--\nFROM: pm\n-->")):
        body = COMPLIANT_BODY + "\n" + line + "\n"
        check("C `%s` still reds inside an HTML comment" % rule,
              rules_on(mod, body) == [rule], rules_on(mod, body))


# ══════════════════════════════════════════════════════════════════════════════════════════════
# D — THE MUTANTS: each rule disabled in a COPY, and the answer must flip
# ══════════════════════════════════════════════════════════════════════════════════════════════
def mutant(td, name, substitution, count=1):
    """A copy of the shipped lint with ONE property removed, asserted to have APPLIED, loaded as a
    module. `count=-1` replaces EVERY occurrence — for a property spelled once per shape it applies
    to."""
    return load_tool(mutant_path(td, name, substitution, count))


def mutant_path(td, name, substitution, count=1):
    """`mutant`'s copy as a FILE, for a row that runs it as a program. The shipped path when the
    anchor is gone — with the failure recorded, so no row's green over it is believed."""
    old, new = substitution
    with open(TOOL, encoding="utf-8") as fh:
        src = fh.read()
    if old not in src:
        FAILURES.append("MUTANT `%s`: its anchor is no longer in %s, so the copy is UNMUTATED and "
                        "every assertion over it would be a green over the shipped code."
                        % (name, TOOL))
        return TOOL
    path = os.path.join(td, "pr-body-lint.%s.py" % name)
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(src.replace(old, new, count))
    if sha256_file(path) == sha256_file(TOOL):
        FAILURES.append("MUTANT `%s`: the copy is byte-identical to the shipped file." % name)
    return path


def arm_d_mutants(td):
    positive = read_fixture("positive")

    opened = mutant(td, "allowlist-opened",
                    ('ALLOWED_H2 = ("Highlights", "Upgrade warnings", "Bundled", "Release artifacts")',
                     'ALLOWED_H2 = ("",)'))
    if check("D CONTROL: with the H2 allowlist OPENED, the known positive stops reding on its "
             "`## Correlation gaps` — that rule is what produced the red",
             "heading-not-allowed" not in rules_on(opened, positive), rules_on(opened, positive)):
        seen_red("D the heading allowlist, driven red by an opened allowlist that lets the "
                 "operator's own example through")

    emptied = mutant(td, "openers-emptied",
                     ('BANNED_OPENERS = ("Why", "Worth reading", "Not included", "Still to do", '
                      '"Seen to fail",\n                  "Verification", "Controls", '
                      '"Review round")',
                      'BANNED_OPENERS = ("zzzz-no-such-opener",)'))
    if check("D CONTROL: with the banned-opener table EMPTIED, the known positive stops reding on "
             "`### Why MINOR`", "banned-opener" not in rules_on(emptied, positive),
             rules_on(emptied, positive)):
        seen_red("D the banned-opener table, driven red by an emptied table that lets `Why MINOR` "
                 "through")

    narrowed = mutant(td, "allowlist-narrowed",
                      ('ALLOWED_H2 = ("Highlights", "Upgrade warnings", "Bundled", "Release artifacts")',
                       'ALLOWED_H2 = ()'))
    if check("D CONTROL: with the allowlist NARROWED TO NOTHING, the COMPLIANT body reds — the "
             "rule reads the set, not the shape of a heading",
             "heading-not-allowed" in rules_on(narrowed, COMPLIANT_BODY),
             rules_on(narrowed, COMPLIANT_BODY)):
        seen_red("D the allowlist's membership test, driven red on a compliant body by an empty "
                 "allowlist")

    dropped = mutant(td, "artifacts-dropped",
                     ('ALLOWED_H2 = ("Highlights", "Upgrade warnings", "Bundled", '
                      '"Release artifacts")',
                      'ALLOWED_H2 = ("Highlights", "Upgrade warnings", "Bundled")'))
    arts = COMPLIANT_BODY + "\n## Release artifacts\n\n- [ ] SBOM regenerated for v1.4.0\n"
    if check("D CONTROL: with `Release artifacts` DROPPED from the allowlist, a body carrying the "
             "generator's artifacts checklist REDS — the tuple's membership is what admitted it",
             "heading-not-allowed" in rules_on(dropped, arts)
             and rules_on(mod_main, arts) == [], (rules_on(dropped, arts),
                                                  rules_on(mod_main, arts))):
        seen_red("D the `Release artifacts` row of the allowlist, driven red by a copy that drops "
                 "it and then reds on the section `release-pr-body` generates")

    cased = mutant(td, "ignorecase-dropped",
                   ('|".join(re.escape(p) for p in BANNED_OPENERS),\n'
                    '                        re.IGNORECASE)',
                    '|".join(re.escape(p) for p in BANNED_OPENERS))'))
    lower = COMPLIANT_BODY + "\n## why minor\n"
    upper = COMPLIANT_BODY + "\nWhy MINOR (1.3.0 -> 1.4.0)\n"
    if check("D CONTROL: with `re.IGNORECASE` DROPPED, `## why minor` stops reding on "
             "`banned-opener` while `Why MINOR` still does — the flag is what produced the red, "
             "and the mutant disabled one property rather than the rule",
             "banned-opener" not in rules_on(cased, lower)
             and "banned-opener" in rules_on(cased, upper),
             (rules_on(cased, lower), rules_on(cased, upper))):
        seen_red("D `re.IGNORECASE` on the opener pattern, driven red by a case-SENSITIVE copy "
                 "that lets a lower-cased narration heading through")

    underscored = mutant(td, "underscore-lookahead",
                         ('_BANNED_RE = re.compile(r"(?:%s)(?![A-Za-z0-9-])"',
                          '_BANNED_RE = re.compile(r"(?:%s)(?![\\w-])"'))
    und_body = COMPLIANT_BODY + "\n__Why__ this release is MINOR.\n"
    if check("D CONTROL: with the PRE-FIX `(?![\\w-])` lookahead back, `__Why__` stops reding — "
             "`_` is a `\\w` character, and that is the whole of the M2 defect",
             "banned-opener" not in rules_on(underscored, und_body)
             and "banned-opener" in rules_on(mod_main, und_body),
             (rules_on(underscored, und_body), rules_on(mod_main, und_body))):
        seen_red("D the opener lookahead's character class, driven red by the shipped `(?![\\w-])` "
                 "spelling that let an underscore-emphasised `__Why__` through")

    spanning = mutant(td, "audit-row-spanning",
                      (r'pattern = r"^(?:\*\*%(n)s:\*\*|%(n)s:)[ \t]*(?P<v>\S.*)$"',
                       r'pattern = r"^(?:\*\*%(n)s:\*\*|%(n)s:)\s*(?P<v>\S.*)$"'))
    spanning_body = "Scope line.\n\nBuilt:\ndispatched (coder ×1 / mechanic ×0)\n"
    if check("D CONTROL: with `\\s` back in the audit-row separator, a `Built:` line with NOTHING "
             "after it takes the NEXT line as its value — the `[ \\t]` narrowing is what refuses "
             "that", spanning.audit_fields(spanning_body)["Built"] is not None
             and mod_main.audit_fields(spanning_body)["Built"] is None,
             (spanning.audit_fields(spanning_body), mod_main.audit_fields(spanning_body))):
        seen_red("D the `[ \\t]` separator, driven red by the pre-narrowing `\\s` spelling, which "
                 "reads the line BELOW an empty field as its value")


# ══════════════════════════════════════════════════════════════════════════════════════════════
# F — `attribution-line`: THE RULE THAT REFUSES A LINE THE STANDARD USED TO REQUIRE
# ══════════════════════════════════════════════════════════════════════════════════════════════
def arm_f_attribution(mod, td):
    positive = read_fixture("attr_positive")
    negative = read_fixture("attr_negative")

    got = rules_on(mod, positive)
    check("F the ATTRIBUTION POSITIVE — fw#891's body as the operator read it — reds on "
          "`attribution-line`", "attribution-line" in got, got)
    hit = [f for f in mod.findings(positive) if f.rule == "attribution-line"]
    check("F ...on its FIRST line, quoting the offending line rather than a tally",
          len(hit) == 1 and hit[0].line == 1 and hit[0].text.strip() == "FROM: pm",
          [(f.line, f.text) for f in hit])
    # The negative passes every rule that EXISTED when it was captured. It ends on the harness's
    # `Generated with [Claude Code]` footer, which `ai-attribution` (card#10673) now reds — that is
    # `arm_j`'s known positive, so it is excluded here BY NAME rather than by editing the evidence.
    check("F the ATTRIBUTION NEGATIVE — the same body after the line was struck — passes every "
          "rule but `ai-attribution` (arm_j's positive)",
          rules_on(mod, negative) == ["ai-attribution"], rules_on(mod, negative))

    # Both rows of the family, and the indent the protocol's own parser tolerates. `parse_body` /
    # the Action's `parseBody` TRIM each line before `startswith`, so an indented attribution line
    # is an attribution line to every consumer that reads one — this rule reads the same population.
    for lead in ("FROM: pm", "TO: pm", "  FROM: pm", "\tTO: pm, impl"):
        body = COMPLIANT_BODY + "\n%s\n" % lead
        check("F `attribution-line` reds on %r" % lead,
              "attribution-line" in rules_on(mod, body), rules_on(mod, body))

    # …and NOT on a quotation of somebody else's attribution, which is the other half of a rule
    # that discriminates (the approval-marker fragment owns that distinction and was measured on
    # it: an indented/quoted `FROM:` is what a QUOTED post looks like).
    quoted = COMPLIANT_BODY + "\n> FROM: pm\n"
    check("F `attribution-line` does not fire on a BLOCK-QUOTED attribution line",
          "attribution-line" not in rules_on(quoted and mod, quoted), rules_on(mod, quoted))

    # …and not on a fenced one: the compliant body above carries `FROM: evil` / `TO: all` inside
    # its fence, so `arm_a`'s green already says this — driven here explicitly, on the smallest
    # body that can say it, because THIS rule is the newest consumer of the fence scan.
    fenced_only = ("**`dev → main` release PR — v1.4.0.** Bundles the commits since `v1.3.0`.\n\n"
                   "Built: dispatched (coder ×1 / mechanic ×0)\n"
                   "Coordinated in: acme/coordination#412\n\n"
                   "```\nFROM: pm\nTO: impl\n```\n")
    check("F an attribution line that exists only INSIDE A FENCE is payload, not a finding",
          rules_on(mod, fenced_only) == [], rules_on(mod, fenced_only))

    # ⛔ THE CONTROL. The positive reds on `heading-not-allowed` as well, so "the positive reds"
    # was TRUE OF THAT BODY BEFORE THIS RULE EXISTED. Unwire the rule from the one entry point and
    # the attribution finding must be the thing that disappears.
    unwired = mutant(td, "attribution-unwired",
                     ("+ rule_attribution_line(rows) + rule_ai_attribution(rows)",
                      "+ rule_ai_attribution(rows)"))
    got_u = rules_on(unwired, positive)
    if check("F CONTROL: with `rule_attribution_line` UNWIRED, the attribution positive stops "
             "reding on `attribution-line` — and still reds on its other row, so the mutant "
             "disabled one rule rather than the program",
             "attribution-line" not in got_u and "heading-not-allowed" in got_u, got_u):
        seen_red("F the attribution-line rule, driven red by an unwired copy that lets fw#891's "
                 "own `FROM: pm` line through")

    # ⛔ AND THE MACHINE-LINE FAMILY NO LONGER CONTAINS `FROM`/`TO`, WHICH IS A SEPARATE CLAIM
    # FROM "the new rule reds". `_MACHINE_LINE_RE` is what `rule_scope_line` SKIPS, and while it
    # carried the attribution rows this body — an attribution line plus the two audit rows, and no
    # prose at all — reported `scope-line` (every content row was skipped, so the rule fell through
    # to its no-scope-line finding). Now the attribution line is ordinary content: the body reds on
    # `attribution-line` ALONE, and deleting the line is what re-exposes the scope-line question.
    # Pinned on the pattern as well as the behaviour, because a regexp that quietly regained the
    # two names would restore the skip while every rule above stayed green.
    only_attr = "FROM: pm\n\nBuilt: x\nCoordinated in: acme/coordination#1\n"
    check("F a body of an attribution line + the audit rows reds on `attribution-line` and nothing "
          "else — the line is CONTENT now, not a skipped machine row",
          rules_on(mod, only_attr) == ["attribution-line"], rules_on(mod, only_attr))
    check("F ...and `_MACHINE_LINE_RE` — the set `rule_scope_line` skips — no longer matches "
          "`FROM:` / `TO:`, while it still matches the audit rows it does own",
          mod._MACHINE_LINE_RE.match("FROM: pm") is None
          and mod._MACHINE_LINE_RE.match("TO: pm") is None
          and mod._MACHINE_LINE_RE.match("Built: x") is not None
          and mod._MACHINE_LINE_RE.match("**Coordinated in:** acme/coordination#1") is not None,
          "the machine-line family is wrong")


# ══════════════════════════════════════════════════════════════════════════════════════════════
# G — `live-state-reading`: A CLOSED TABLE OF LIVE CI / PUSH / BASE READINGS (card#9073 leg B-2)
# ══════════════════════════════════════════════════════════════════════════════════════════════
# One example line per shape ALTERNATIVE, and every row pins ONE shape only — which is what lets
# each per-shape mutant below be read: when that shape is disabled, exactly its rows go quiet.
LIVE_ROWS = (
    ("ci-not-run", "- CI has not run on this head."),
    ("ci-not-run", "- CI has not run at `69dc8992ee78`."),
    ("ci-state-at", "- CI is green at `0a3536fea5cc208992daebe3206a777dd0c05927`."),
    ("ci-state-at", "- CI queued at this head."),
    # fw#901's live body carries this cell (upper-case, which is what the IGNORECASE mutant reads).
    ("ci-state-at", "| fix-4 | coder | **CI RED at `9f5fe2365476f893ae2c0f797aa5ee0496456af4`** |"),
    ("branch-push", "- The branch is not pushed."),
    ("branch-push", "- 4 commits, `dev` merged, all four pushed."),
    ("branch-push", "- `69dc8992ee78` is not pushed."),
    ("behind-base", "- The branch is 2 commits behind `origin/dev`."),
    ("behind-base", "- 3 commits ahead of main."),
    ("behind-base", "- 1 commit behind origin/main"),
    ("behind-base", "- 4 commits ahead of `dev`."),
    # fw#820's body, verbatim.
    ("runs-success", "* **CI at this head: 5 runs, all `conclusion == success`**"),
)

# Lines the rule must NOT red on: the header's NAMED residues — not judged by design, pinned here so
# the header's list is a measured claim — and the near misses a closed table exists to leave alone,
# a derivation (what the finding asks for) among them. Each row says which it is.
LIVE_NOT_JUDGED = (
    ("a base other than `dev` / `main` (pm ruling)", "- The branch is 3 commits behind `release`."),
    ("emphasis between a shape's words", "- CI is **green** at `0a3536fe`."),
    ("a reading split across table cells", "| CI at `69dc899` | **CLEAN**, rc 0 |"),
    ("a derivation with its pass conditions",
     "- CI at this head: `ci-read --sha <full 40-character head>`; a pass is a non-empty run set, "
     "every run terminal, every conclusion `success`."),
    ("the word CI with no head or sha", "- The daemon logs when CI is green but the cache is cold."),
    ("an installer-facing push", "- `acme-sync` now pushes the image to your registry on restart."),
    ("an all-letter word where a sha would be", "- CI is green at `defaced`."),
    ("a reading whose opening token follows a word — the clause-opening narrowing's residue",
     "- Note CI is green at `0a3536fe`."),
    # fw#910 r1 M1. More than one narrowing below withholds this line (a digit-only token AND a
    # token that follows a word), so no single mutant flips it; it is pinned here instead.
    ("a digit-only tag in words (fw#910 r1 M1)", "- Tag 2026091 pushed"),
)

# ⛔ THE NARROWINGS fw#910 r1 (M1, m1) FORCED, EACH AS A CONTROL. The shapes used to red on lines
# that are not readings: the pass conditions the finding tells the author to write, descriptions
# of what a tool does, a decimal number taken for a sha, and a base that merely BEGINS with `dev` or
# `main`. Each row is `(what the narrowing refuses, (its shipped spelling, the pre-fix spelling),
# the lines it ALONE withholds)`. Every line must PASS on the shipped lint and RED on a copy with
# that one narrowing reverted at EVERY occurrence — so each narrowing is shown to be what keeps its
# lines quiet, rather than some other shape happening not to match them.
LIVE_NARROWINGS = (
    ("a count of ZERO is not judged — a pass condition and a reading share the shape, so the "
     "zero-count reading is a named residue",
     (r"\b[1-9]\d* commits?", r"\b\d+ commits?"),
     ("- A pass is 0 commits behind `dev`.",
      "- the release script refuses unless the branch is 0 commits ahead of `main`",
      # fw#627's merged body, verbatim: a REAL base reading, withheld all the same — the residue.
      "`37d1c367` → exit 1. 0 commits behind `origin/dev` (`bcdc12bb`).")),
    ("a run count of ZERO is not judged, the same residue on `runs-success`",
     (r"\b[1-9]\d* runs?", r"\b\d+ runs?"),
     ("- A pass is never `0 runs, all success`.",)),
    ("a base is `dev` / `main` exactly, never a base whose name begins with one (m1)",
     (r"(?:dev|main)(?![\w/-]|\.\w)", r"(?:dev|main)\b"),
     ("- The branch is 3 commits behind `dev-next`.", "- 1 commit ahead of main-v2.",
      "- 2 commits behind origin/main-lts.", "- 2 commits behind dev/feature.")),
    ("a sha carries a hex LETTER, so a decimal number is not a sha",
     (r"(?=[0-9]*[a-f])", ""),
     ("- `2026091` is pushed as the release tag.",)),
    ("a shape OPENS ITS CLAUSE: the token it opens on does not follow a word",
     (r"(?<!\w )", ""),
     ("- A pass means CI is green at this head for every required workflow.",
      "- `coord-release` waits until all tags are pushed, then publishes.",
      "- after 12 runs all jobs report success",
      "- `coord-release` refuses when the branch is not pushed.",
      "- `ci-read` exits 3 while CI has not run on this head.",
      "- `coord-verify` waits until `69dc8992ee78` is pushed.",
      # fw#871's live body, verbatim: illustrative shas in a description of a tool's behaviour.
      "(`` `a1b2c3d` and `d4e5f6a` NOT pushed ``) the farther sha is skipped and its claim stops "
      "being",
      "* `` head `8673e93` PUSHED (s698) = fix-pass-3 on `c04de15` `` — pre-fix **both** shas "
      "were claimed")),
)


# ⛔ THE NAMED FALSE REDS (fw#910 r2 m-B, r3 m-2): lines that are NOT readings and red all the same,
# pinned RED so the header's claim is measured — a false red the header names with no row here is
# unchecked. `behind-base` does not open its clause (its own reading puts
# a word before the count), so no shape separates a tool description with a non-zero count from a
# reading. Each row is `(the shape it reds on, the line)`.
LIVE_KNOWN_FALSE_REDS = (
    ("behind-base", "- `coord-release` refuses when the branch is 5 commits behind `dev`."),
    ("behind-base", "- `coord-release` warns when the branch is 3 commits ahead of `main`."),
)


def _shapes_named(mod, finding):
    return [s for s, _ in mod.LIVE_STATE_READINGS if "`%s`" % s in finding.message]


def _live_hits(mod, line):
    """The shapes `mod` names on `line` appended to the compliant body — `[]` when it does not red."""
    body = COMPLIANT_BODY + "\n%s\n" % line
    hits = [f for f in mod.findings(body) if f.rule == "live-state-reading"]
    return _shapes_named(mod, hits[0]) if hits else []


def arm_g_live_state(mod, td):
    positive = read_fixture("live_positive")
    negative = read_fixture("live_negative")

    # THE POSITIVE, ON THE LINES COMMENT 4102 NAMED. The expected lines are DERIVED from the
    # fixture by their text, never written down as numbers.
    claimed = ("CI has not run on this head", "commits behind `origin/dev`")
    want = [n for n, t, fenced in mod.scan(positive)
            if not fenced and any(c in t for c in claimed)]
    hits = [f for f in mod.findings(positive) if f.rule == "live-state-reading"]
    check("G the LIVE-STATE POSITIVE — fw#873's body as first published — reds on "
          "`live-state-reading`", hits, rules_on(mod, positive))
    check("G ...on exactly the lines carrying comment 4102's claims, and no other line",
          want and [f.line for f in hits] == want, ([f.line for f in hits], want))
    named = {f.line: _shapes_named(mod, f) for f in hits}
    check("G ...naming `ci-not-run` + `branch-push` on the CI line and `behind-base` on the base line",
          sorted(named.values()) == [["behind-base"], ["ci-not-run", "branch-push"]], named)

    # THE HAND-BUILT NEGATIVE IS ASSERTED TO BE WHAT IT CLAIMS: the real positive, byte for byte,
    # except exactly the lines the rule reds on.
    pl, nl = positive.split("\n"), negative.split("\n")
    changed = [i + 1 for i, (a, b) in enumerate(zip(pl, nl)) if a != b]
    check("G the HAND-BUILT negative differs from the real positive on exactly those lines",
          len(pl) == len(nl) and changed == want, (len(pl), len(nl), changed, want))
    check("G ...and does not red on `live-state-reading`",
          "live-state-reading" not in rules_on(mod, negative), rules_on(mod, negative))
    check("G ...while every OTHER rule the positive reds on still reds — the pair differs by this "
          "rule and nothing else", set(rules_on(mod, positive)) - set(rules_on(mod, negative))
          == {"live-state-reading"}, (rules_on(mod, positive), rules_on(mod, negative)))

    for shape, line in LIVE_ROWS:
        check("G `%s` reds on %r, naming that shape alone" % (shape, line),
              _live_hits(mod, line) == [shape], _live_hits(mod, line))
    for why, line in LIVE_NOT_JUDGED:
        body = COMPLIANT_BODY + "\n%s\n" % line
        check("G NOT judged — %s: %r" % (why, line), rules_on(mod, body) == [], rules_on(mod, body))
    for why, (shipped, pre_fix), lines in LIVE_NARROWINGS:
        for line in lines:
            body = COMPLIANT_BODY + "\n%s\n" % line
            check("G NOT judged — %s: %r" % (why, line), rules_on(mod, body) == [],
                  rules_on(mod, body))
    for shape, line in LIVE_KNOWN_FALSE_REDS:
        check("G a FALSE RED the header names — a tool description — reds on `%s` alone: %r"
              % (shape, line), _live_hits(mod, line) == [shape], _live_hits(mod, line))

    # A QUOTED READING COUNTS (pm ruling): fw#873's final body quotes its first revision this way.
    quoted = ('Revision 1 asserted "CI has not run on this head; the branch is not pushed" and '
              '"2 commits behind `dev`" — both false at the head they described.')
    check("G a QUOTED reading reds — the ruling's case, fw#873's final body",
          _live_hits(mod, quoted) == ["ci-not-run", "branch-push", "behind-base"],
          _live_hits(mod, quoted))
    fenced = COMPLIANT_BODY + "\n```\nCI has not run on this head.\n```\n"
    check("G a reading that exists only INSIDE A FENCE is payload, not a finding",
          rules_on(mod, fenced) == [], rules_on(mod, fenced))

    # ⛔ THE CONTROLS. The positive reds on older rules too, so "the positive reds" was true
    # before this rule existed: unwire it, and the live-state finding must be what disappears.
    unwired = mutant(td, "live-state-unwired",
                     ("rule_banned_openers(rendered) + rule_live_state_reading(rendered)\n",
                      "rule_banned_openers(rendered)\n"))
    got_u = rules_on(unwired, positive)
    if check("G CONTROL: with `rule_live_state_reading` UNWIRED, fw#873's reading lines stop reding on "
             "`live-state-reading` — and every other rule still reds, so the mutant disabled one "
             "rule rather than the program",
             "live-state-reading" not in got_u
             and set(got_u) == set(rules_on(mod, positive)) - {"live-state-reading"}, got_u):
        seen_red("G the live-state-reading rule, driven red by an unwired copy that lets fw#873's "
                 "`CI has not run on this head` and `2 commits behind origin/dev` through")

    for shape, _ in mod.LIVE_STATE_READINGS:
        off = mutant(td, "shape-%s-disabled" % shape,
                     ('("%s",\n     r"(?:' % shape, '("%s",\n     r"(?!)(?:' % shape))
        own = [line for s, line in LIVE_ROWS if s == shape]
        others = [line for s, line in LIVE_ROWS if s != shape]
        if check("G CONTROL: with shape `%s` DISABLED, its own rows stop reding while every other "
                 "shape's rows still red" % shape,
                 own and all(_live_hits(off, l) == [] for l in own)
                 and all(_live_hits(off, l) for l in others),
                 ([_live_hits(off, l) for l in own], [_live_hits(off, l) for l in others])):
            seen_red("G shape `%s`, driven red by a copy whose pattern can never match" % shape)

    cased = mutant(td, "live-state-ignorecase-dropped",
                   ("re.compile(pattern, re.IGNORECASE)", "re.compile(pattern)"))
    upper = next(line for _, line in LIVE_ROWS if "CI RED at" in line)
    lower = next(line for _, line in LIVE_ROWS if "CI is green at" in line)
    if check("G CONTROL: with `re.IGNORECASE` DROPPED from the shape table, fw#901's `CI RED at "
             "<sha>` stops reding while the lower-case `CI is green at <sha>` still does",
             _live_hits(cased, upper) == [] and _live_hits(cased, lower) == ["ci-state-at"]
             and _live_hits(mod, upper) == ["ci-state-at"],
             (_live_hits(cased, upper), _live_hits(cased, lower))):
        seen_red("G `re.IGNORECASE` on the shape table, driven red by a case-sensitive copy that "
                 "lets an upper-case `CI RED at <sha>` through")

    # ⛔ AND EACH NARROWING, REVERTED IN A COPY, MUST RE-RED ITS OWN LINES — while every shape's
    # true-positive rows still red on that shape alone, so the copy reverted one narrowing rather
    # than the rule.
    for i, (why, (shipped, pre_fix), lines) in enumerate(LIVE_NARROWINGS):
        rev = mutant(td, "live-narrowing-%d-reverted" % i, (shipped, pre_fix), count=-1)
        if check("G CONTROL: with the narrowing REVERTED (%s), its lines red again while every "
                 "true-positive row still reds" % why,
                 all(_live_hits(rev, l) for l in lines)
                 and all(_live_hits(rev, l) == [s] for s, l in LIVE_ROWS),
                 ([_live_hits(rev, l) for l in lines],
                  [(s, _live_hits(rev, l)) for s, l in LIVE_ROWS if _live_hits(rev, l) != [s]])):
            seen_red("G narrowing — %s — driven red by a copy with its pre-fix spelling back" % why)

    proc = run_cli(["--body-file", os.path.join(FIXTURE_DIR, FIXTURES["live_positive"][0])])
    check("G the CLI exits 1 on the live-state positive and names the rule",
          proc.returncode == 1 and "live-state-reading" in proc.stdout, proc.stdout[-400:])


# ══════════════════════════════════════════════════════════════════════════════════════════════
# H — THE BOT-AUTHOR EXEMPTION (card#9927): TWO ROWS WAIVED, FOR AN AUTHOR THE EVENT PROVES IS A BOT
# ══════════════════════════════════════════════════════════════════════════════════════════════
# ⛔ THIS ARM IS A SECURITY ARM, NOT A CONVENIENCE ARM, AND ITS TWO SIDES ARE NOT THE SAME CLAIM.
# "A bot PR passes" is the defect being closed (every Dependabot PR redded on `built-missing` +
# `coordinated-missing`, so an adopter gating self-merge on this workflow could not land a security
# bump without a person hand-editing the bot's body). "NOTHING ELSE passes" is the property that
# keeps closing it from opening a hole in a body-PROVENANCE check, and it is the side with the long
# row list: every value that is not the exact string GitHub emits must leave the two rows required,
# because the alternative is a body that sheds its audit trail by naming a variable the lint could
# not read.
#
# EVERY VALUE BELOW IS A VALUE, NEVER A LOGIN. The discriminator is the event payload's
# `user.type`, measured on this repo's own Dependabot PR (`PupFuzz/agent-board-framework#426`:
# `user.login` `dependabot[bot]`, `user.type` `Bot`) — which is why the two real dependabot LOGIN
# spellings appear in the NOT-a-bot list below. They are what a login-based discriminator would
# have keyed on, and this program must not accept them from this field.

# Values that must NOT win the exemption. `None` is the absent author every non-CI caller passes —
# a `--body-file` run from a terminal, and `review-prep.py`.
NOT_A_BOT = (
    (None, "no author at all — a terminal run over a file, and review-prep's digest"),
    ("", "an environment variable set to nothing"),
    ("   ", "whitespace only"),
    ("bot", "the right word, the wrong casing — GitHub emits `Bot`"),
    ("BOT", "upper-cased"),
    ("User", "the account type a human, and every fleet agent on the shared PAT, reports"),
    ("Organization", "the third member of GitHub's own enum"),
    ("Bot account", "a value that CONTAINS the token — a substring test would accept this"),
    ("dependabot[bot]", "the author LOGIN, from the REST / webhook payload"),
    ("app/dependabot", "the author LOGIN as `gh`'s projection renders it"),
    ("true", "a boolean-ish value from a caller wiring the flag to something else"),
)


def _body_without_audit_rows():
    """The compliant body with BOTH audit rows struck — and nothing else touched, so any finding
    on it is one of the two this exemption waives."""
    return "\n".join(l for l in COMPLIANT_BODY.split("\n")
                     if not (l.startswith("**Built:") or l.startswith("**Coordinated in:")))


def arm_h_bot_author(mod, td):
    no_rows = _body_without_audit_rows()
    both = ["built-missing", "coordinated-missing"]

    # THE BASELINE, FIRST: the body is one that reds on exactly the two rows and nothing else.
    # Without this the green below is equally consistent with a body that was never a positive.
    check("H the audit-row-less body reds on exactly the two rows when no author is given — the "
          "pre-change behaviour, unchanged", rules_on(mod, no_rows) == both, rules_on(mod, no_rows))

    check("H a BOT-authored body missing BOTH audit rows PASSES — the card#9927 defect, closed",
          rules_on(mod, no_rows, "Bot") == [], rules_on(mod, no_rows, "Bot"))

    # …and the transport's whitespace is absorbed, because a value read from a file or a shell can
    # carry a newline and that is the same value.
    for raw in ("Bot\n", " Bot", "\tBot  "):
        check("H ...and %r is the same value once its transport is stripped" % raw,
              rules_on(mod, no_rows, raw) == [], rules_on(mod, no_rows, raw))

    for value, why in NOT_A_BOT:
        check("H NOT a bot — %s (%r): both audit rows are still required" % (why, value),
              rules_on(mod, no_rows, value) == both, rules_on(mod, no_rows, value))

    # ⛔ ONLY THOSE TWO ROWS. Each row here is a body that ALSO lacks both audit rows, so the
    # equality is two claims at once: the waiver fired, and the other rule survived it.
    others = (
        # ⛔ `## Correlation gaps`, NOT `## Review round 2`: the latter is ALSO a banned
        # opener, and a row asserting "this rule ALONE" cannot be written on a line that
        # breaks two rules.
        ("heading-not-allowed", no_rows + "\n## Correlation gaps\n"),
        ("banned-opener", no_rows + "\nVerification: the suite is green at this head.\n"),
        ("attribution-line", no_rows + "\nFROM: pm\n"),
        ("live-state-reading", no_rows + "\n- CI has not run on this head.\n"),
        ("scope-line", "## Highlights\n\n- the daemon reads `/etc/acme/sync.env`.\n"),
    )
    for rule, body in others:
        check("H a BOT-authored body still reds on `%s`, and on that ALONE — the waiver reaches "
              "the two audit rows and no further rule" % rule,
              rules_on(mod, body, "Bot") == [rule], rules_on(mod, body, "Bot"))

    # …and the same bodies, from a human, red on that rule AND both audit rows — which is what
    # says the rows above were WAIVED rather than never triggered.
    for rule, body in others:
        want = sorted([rule] + both)
        check("H ...while the SAME body from a human reds on `%s` and both audit rows" % rule,
              rules_on(mod, body, "User") == want, rules_on(mod, body, "User"))

    # ⛔ CONTROL 1 — the waiver itself. Unwire the early return and the bot body must red on both
    # rows again: the exemption is what produced the green, not a body that satisfied the rule.
    unwired = mutant(td, "bot-exemption-unwired",
                     ("    if author_is_bot(author_type):\n        return []\n", ""))
    if check("H CONTROL: with the bot exemption UNWIRED, the bot-authored body reds on both audit "
             "rows again — while a human-authored body is unchanged, so the mutant removed the "
             "waiver rather than a rule",
             rules_on(unwired, no_rows, "Bot") == both
             and rules_on(unwired, no_rows, "User") == both,
             (rules_on(unwired, no_rows, "Bot"), rules_on(unwired, no_rows, "User"))):
        seen_red("H the bot-author exemption, driven red by a copy with the waiver removed, which "
                 "reds a Dependabot body on `built-missing` + `coordinated-missing` — the exact "
                 "measurement card#9927 was minted on")

    # ⛔ CONTROL 2 — the DISCRIMINATOR, which is the security half and a different claim. Open it
    # to "any non-empty value" and the rows this suite pins as NOT-a-bot must start passing. A
    # green on the rows above is otherwise equally consistent with a lint that waives for anybody
    # who passes anything at all.
    opened = mutant(td, "bot-discriminator-open",
                    ('    return (author_type or "").strip() == BOT_AUTHOR_TYPE',
                     '    return bool((author_type or "").strip())'))
    leaked = [v for v, _ in NOT_A_BOT if v and v.strip()
              and rules_on(opened, no_rows, v) == []]
    still = [v for v, _ in NOT_A_BOT if not (v or "").strip()
             and rules_on(opened, no_rows, v) != both]
    if check("H CONTROL: with the discriminator OPENED to any non-empty value, every non-empty "
             "NOT-a-bot value — the author LOGIN spellings among them — wins the exemption, while "
             "the empty ones still do not: the EXACT compare is what refuses them",
             len(leaked) == len([v for v, _ in NOT_A_BOT if v and v.strip()]) and not still,
             (leaked, still)):
        seen_red("H the exact `== BOT_AUTHOR_TYPE` compare, driven red by an opened discriminator "
                 "that hands the waiver to `User`, `bot`, `dependabot[bot]` and `app/dependabot`")

    # THE CLI — what CI actually runs, including the `--env` + `--author-type-env` pair the shipped
    # workflow invokes and the UNSET case an adopter on the old workflow will hit.
    path = os.path.join(td, "no-audit-rows.md")
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(no_rows)

    proc = run_cli(["--body-file", path])
    check("H CLI: with NO `--author-type-env` at all, the body reds on both rows (exit 1)",
          proc.returncode == 1 and "built-missing" in proc.stdout
          and "coordinated-missing" in proc.stdout, (proc.returncode, proc.stdout[-300:]))

    proc = run_cli(["--body-file", path, "--author-type-env", "COORD_PR_AUTHOR_TYPE"],
                   env={"COORD_PR_AUTHOR_TYPE": "Bot"})
    check("H CLI: `--author-type-env` naming a variable set to `Bot` exits 0 and SAYS the two rows "
          "were waived — a silent exemption is the one a later reader mis-reads as a clean body",
          proc.returncode == 0 and "author type is `Bot`" in proc.stdout
          and "NOT required" in proc.stdout, (proc.returncode, proc.stdout[-400:]))

    proc = run_cli(["--body-file", path, "--author-type-env", "COORD_PR_AUTHOR_TYPE"],
                   env={"COORD_PR_AUTHOR_TYPE": "User"})
    check("H CLI: the same flag with `User` exits 1 on both rows",
          proc.returncode == 1 and "built-missing" in proc.stdout, (proc.returncode,
                                                                    proc.stdout[-300:]))

    # ⛔ AN UNSET AUTHOR VARIABLE IS NOT A FAULT, WHICH IS THE OPPOSITE OF `--env`'s ANSWER FOR THE
    # BODY — and the asymmetry is deliberate: an unread BODY has no correct verdict, an unread
    # AUTHOR has one (not provably a bot). An adopter who copies the new lint and keeps the old
    # workflow lands exactly here, and must get the PRE-CHANGE behaviour rather than a hard error.
    proc = run_cli(["--body-file", path, "--author-type-env", "COORD_PR_AUTHOR_TYPE"])
    check("H CLI: an UNSET author variable is NOT a bot and NOT a fault — exit 1 on the two rows, "
          "never exit 2", proc.returncode == 1 and "not set" not in proc.stderr,
          (proc.returncode, proc.stderr[:200], proc.stdout[-200:]))

    # The exact pair the shipped workflow runs, both values through the environment.
    proc = run_cli(["--env", "COORD_PR_BODY", "--author-type-env", "COORD_PR_AUTHOR_TYPE"],
                   env={"COORD_PR_BODY": no_rows, "COORD_PR_AUTHOR_TYPE": "Bot"})
    check("H CLI: the shipped workflow's invocation — body and author type BOTH through `env:` — "
          "exits 0 on a Dependabot-shaped body", proc.returncode == 0,
          (proc.returncode, proc.stdout[-300:], proc.stderr[-200:]))

    # …and the note is on the FAIL path too: a bot PR that reds on another rule must not look like
    # a bot PR that was never exempted at all.
    other_path = os.path.join(td, "no-audit-rows-plus-heading.md")
    with open(other_path, "w", encoding="utf-8", newline="") as fh:
        fh.write(no_rows + "\n## Correlation gaps\n")
    proc = run_cli(["--body-file", other_path, "--author-type-env", "COORD_PR_AUTHOR_TYPE"],
                   env={"COORD_PR_AUTHOR_TYPE": "Bot"})
    check("H CLI: a bot body that breaks ANOTHER rule exits 1 on that rule, and still states the "
          "waiver", proc.returncode == 1 and "heading-not-allowed" in proc.stdout
          and "author type is `Bot`" in proc.stdout
          and "built-missing" not in proc.stdout, (proc.returncode, proc.stdout[-400:]))

    proc = run_cli(["--body-file", path, "--author-type-env", "COORD_PR_AUTHOR_TYPE", "--json"],
                   env={"COORD_PR_AUTHOR_TYPE": "Bot"})
    check("H CLI: `--json` exits 0 and carries the author type it decided on, RAW",
          proc.returncode == 0 and '"author_type": "Bot"' in proc.stdout
          and '"clean": true' in proc.stdout, proc.stdout[:400])
    proc = run_cli(["--body-file", path, "--json"])
    check("H CLI: `--json` with no author source carries `null` and the two findings",
          proc.returncode == 1 and '"author_type": null' in proc.stdout
          and '"clean": false' in proc.stdout, proc.stdout[:400])


# ══════════════════════════════════════════════════════════════════════════════════════════════
# I — THE RELEASE SCOPE (card#10493): the release standard judges RELEASE PRs, and only them
# ══════════════════════════════════════════════════════════════════════════════════════════════
# THE KNOWN POSITIVE IS A SHAPE card#10493 MEASURED, NOT ONE INVENTED HERE — the measurement is the
# card author's (sola-pm), cited, not re-taken. `BWtek-Medical/sola-device` mandates
# `## Summary`, `## SaMD boundary check` and `## CI action-pin resync check` on its feature PRs (its
# own PR template and `pr_body_shape_guard.py`), and each of its PRs card#10493 lists spent a
# review finding on this lint's `heading-not-allowed` rows for exactly those headings. The body
# below carries them — the SECTION CONTENT under them is hand-written, because that repo is not
# readable from this seat, and the rows below assert on headings and audit rows only.
FEATURE_BODY = """## Summary

Adds the retry window to the sync daemon.

## SaMD boundary check

No change to the SaMD boundary.

## CI action-pin resync check

No workflow touched.

Built: dispatched (coder ×1 / mechanic ×0)
**Coordinated in:** acme/coordination#412
"""
FEATURE_TITLE = "feat(sync): refuse an unset retry window"
RELEASE_TITLE = "release: v1.4.0"
# fw#873's title, verbatim as `gh pr view 873 --json title` returns it: the live-state positive's
# PR is a FEATURE PR (base `dev`), and this is the title CI hands the lint for it.
FW873_TITLE = ("fix(ci-read): a `continue-on-error` step that FAILED is invisible to every "
               "conclusion-only gate — declare the limit, and scan for it (card#8935)")


def arm_i_release_scope(mod, td):
    # (1) THE DEFECT, CLOSED — a feature PR in its own repo's shape is not judged against the
    # release allow-set, and says nothing about `## Summary`.
    got = rules_on(mod, FEATURE_BODY, title=FEATURE_TITLE)
    check("I a FEATURE PR's body carrying its own repo's `## Summary` / `## SaMD boundary check` / "
          "`## CI action-pin resync check` is NOT red — the release allow-set does not reach it",
          got == [], got)

    # (2) …AND THE RELEASE STANDARD IS UNCHANGED FOR A RELEASE PR. The same `## Summary`, on a body
    # whose title declares a release, reds on the heading rule, and the message names the heading.
    rel = COMPLIANT_BODY + "\n## Summary\n"
    found = [f for f in mod.findings(rel, None, title=RELEASE_TITLE)
             if f.rule == "heading-not-allowed"]
    check("I a RELEASE PR's body with a disallowed H2 (`## Summary`) is STILL red on "
          "`heading-not-allowed`, and the finding names the heading and the allowed set",
          len(found) == 1 and "`## Summary` is not one of the sections" in found[0].message
          and "`Highlights`" in found[0].message and found[0].text == "## Summary",
          [(f.rule, f.text, f.message[:80]) for f in found])

    # (3) NO TITLE IS NOT A NON-RELEASE PR. With nothing to prove the PR is not a release, the body
    # is judged by the full release standard — the pre-card#10493 answer, and the stricter one.
    got = rules_on(mod, FEATURE_BODY)
    check("I with NO title the feature-shaped body is judged as a RELEASE body — `heading-not-"
          "allowed` and `scope-line` red exactly as before card#10493",
          "heading-not-allowed" in got and "scope-line" in got, got)
    for blank in ("", "   ", "\n"):
        check("I a BLANK title (%r) is no title — judged as a release body" % blank,
              "heading-not-allowed" in rules_on(mod, FEATURE_BODY, title=blank),
              rules_on(mod, FEATURE_BODY, title=blank))

    # (4) THE TITLE PREDICATE — its prefix, its case and its transport.
    for title in ("release: v1.4.0", "Release: v1.4.0", "RELEASE: v1.4.0", "  release: v1.4.0",
                  "release: post-aimla-v1.0.0"):
        check("I title %r is a RELEASE PR" % title, mod.judged_as_release(title) is True,
              mod.judged_as_release(title))
    for title in ("feat: add release notes", "fix(release-pr): scope the claim", "releases: x",
                  "sync: merge main into dev post-v1.4.0 (Rule E)", "chore: release prep",
                  "release v1.4.0"):
        check("I title %r is NOT a release PR" % title, mod.judged_as_release(title) is False,
              mod.judged_as_release(title))

    # (5) WHAT A NON-RELEASE PR IS STILL HELD TO — the rows whose owner is NOT § PR body's release
    # standard, each red ALONE so the row says which rule fired.
    still = (
        ("built-missing", FEATURE_BODY.replace("Built: dispatched (coder ×1 / mechanic ×0)\n", "")),
        ("coordinated-missing", FEATURE_BODY.replace("**Coordinated in:** acme/coordination#412\n",
                                                     "")),
        ("attribution-line", "FROM: impl\n" + FEATURE_BODY),
    )
    for rule, body in still:
        got = rules_on(mod, body, title=FEATURE_TITLE)
        check("I a NON-release body still reds on `%s`, and on that alone — its owner is fleet-wide, "
              "not the release standard" % rule, got == [rule], got)

    # (5b) THE BODY `live-state-reading` WAS MINTED ON IS A FEATURE PR'S, AND IT STILL REDS AS ONE.
    # fw#873 is a `fix(ci-read): …` PR into `dev`, so a scope that dropped the OUT table's content
    # rules for non-release titles would stop reding on the very instance the rule exists for.
    live = read_fixture("live_positive")
    got = rules_on(mod, live, title=FW873_TITLE)
    check("I fw#873's body under its REAL feature title still reds on `live-state-reading` and "
          "`banned-opener` — the OUT table binds every PR body — and on nothing release-only",
          got == ["banned-opener", "live-state-reading"], got)

    # (6) WHERE THE LINE IS DRAWN: only the release-only rules the lint's header names are scoped.
    # The OUT table's content rules — a narration opener, a live-state reading — bind every PR body,
    # so the same two lines red under a feature title as under a release one; on this body the
    # release title adds `scope-line` and `heading-not-allowed`, the release-only rules it breaks.
    extra = (FEATURE_BODY + "\nVerification: the suite is green at this head.\n"
             "- CI has not run on this head.\n")
    got_feat = rules_on(mod, extra, title=FEATURE_TITLE)
    got_rel = rules_on(mod, extra, title=RELEASE_TITLE)
    check("I a NON-release body reds on `banned-opener` + `live-state-reading` and nothing else, "
          "while the SAME body titled as a release adds exactly `scope-line` + "
          "`heading-not-allowed`",
          got_feat == ["banned-opener", "live-state-reading"]
          and set(got_rel) - set(got_feat) == {"scope-line", "heading-not-allowed"},
          (got_feat, got_rel))

    # (7) THE CONTROLS — the predicate is what produced each answer above, in both directions.
    always = mutant(td, "release-scope-always",
                    ("    return not t or t.lower().startswith(RELEASE_TITLE_PREFIX)",
                     "    return True"))
    got = [f for f in always.findings(FEATURE_BODY, None, title=FEATURE_TITLE)
           if f.rule == "heading-not-allowed"]
    if check("I CONTROL: with the scope predicate forced to RELEASE — the pre-card#10493 lint — the "
             "feature body reds on `heading-not-allowed` for `## Summary`, the finding each "
             "sola-device PR card#10493 lists carried", any(f.text == "## Summary" for f in got),
             [f.text for f in got]):
        seen_red("I the release scope, driven red by a copy that judges every PR as a release and "
                 "reds a feature body's own `## Summary`")
    never = mutant(td, "release-scope-never",
                   ("    return not t or t.lower().startswith(RELEASE_TITLE_PREFIX)",
                    "    return False"))
    got = rules_on(never, rel, title=RELEASE_TITLE)
    if check("I CONTROL: with the scope predicate forced to NON-release, the RELEASE body's "
             "`## Summary` PASSES — the release judgement is what produced row (2)'s red",
             "heading-not-allowed" not in got, got):
        seen_red("I the release judgement, driven red by a copy that judges no PR as a release and "
                 "lets a release body's disallowed H2 through")
    blank_open = mutant(td, "release-scope-blank-is-feature",
                        ("    return not t or t.lower().startswith(RELEASE_TITLE_PREFIX)",
                         "    return t.lower().startswith(RELEASE_TITLE_PREFIX)"))
    got = rules_on(blank_open, FEATURE_BODY, title="")
    if check("I CONTROL: with the no-title arm removed, a BLANK title lets the feature-shaped body "
             "pass — the `not t` arm is what keeps a missing title on the strict side",
             got == [], got):
        seen_red("I the no-title arm, driven red by a copy that reads a blank title as a feature PR")

    # ⛔ AND THE OTHER HALF OF THE SPLIT — WHICH RULES SIT OUTSIDE THE GATE. The three predicate
    # mutants above cannot move a rule that runs whatever the predicate says, so rows (5), (5b) and
    # (6) get their own controls: a copy that puts the rule back BEHIND the gate.
    gate_anchor = ("        out += rule_scope_line(rendered) + rule_headings(rendered, "
                   "release_headings)\n")
    content_gated = mutant(td, "content-rules-release-only",
                           (gate_anchor, gate_anchor + "    else:\n        out = [f for f in out "
                            "if f.rule not in (\"banned-opener\", \"live-state-reading\")]\n"))
    got_live = rules_on(content_gated, live, title=FW873_TITLE)
    got_extra = rules_on(content_gated, extra, title=FEATURE_TITLE)
    if check("I CONTROL: with `banned-opener` / `live-state-reading` moved behind the release "
             "predicate — card#10493's first-round shape — fw#873's body under its own feature "
             "title comes back clean, and so does row (6)'s opener + reading",
             got_live == [] and got_extra == [], (got_live, got_extra)):
        seen_red("I the OUT table's content rules on every PR, driven red by a copy that scopes "
                 "them to release PRs and lets fw#873's live-state readings through")
    all_gated = mutant(td, "every-pr-rows-gated",
                       (gate_anchor, gate_anchor + "    else:\n        out = []\n"))
    got = {rule: rules_on(all_gated, body, title=FEATURE_TITLE) for rule, body in still}
    if check("I CONTROL: with EVERY rule behind the release predicate, row (5)'s three bodies each "
             "stop reding on their own rule under a feature title",
             all(v == [] for v in got.values()), got):
        seen_red("I the every-PR rows (`built-missing`, `coordinated-missing`, `attribution-line`), "
                 "driven red by a copy that runs them on release PRs only")

    # (8) THE CLI — what the shipped workflow runs, title through `env:` beside body and author.
    fpath = os.path.join(td, "feature-body.md")
    with open(fpath, "w", encoding="utf-8", newline="") as fh:
        fh.write(FEATURE_BODY)
    proc = run_cli(["--env", "COORD_PR_BODY", "--author-type-env", "COORD_PR_AUTHOR_TYPE",
                    "--title-env", "COORD_PR_TITLE"],
                   env={"COORD_PR_BODY": FEATURE_BODY, "COORD_PR_AUTHOR_TYPE": "User",
                        "COORD_PR_TITLE": FEATURE_TITLE})
    check("I CLI: the shipped workflow's invocation on a feature PR exits 0 and SAYS it judged a "
          "NON-release body, naming the rows it checked",
          proc.returncode == 0 and "NOT a release PR" in proc.stdout
          and "heading-not-allowed" not in proc.stdout, (proc.returncode, proc.stdout[-500:]))
    proc = run_cli(["--body-file", fpath, "--title", RELEASE_TITLE])
    check("I CLI: `--title` naming a release judges the same body by the release standard — exit 1 "
          "on `heading-not-allowed`, quoting `## Summary`",
          proc.returncode == 1 and "heading-not-allowed" in proc.stdout
          and "> ## Summary" in proc.stdout, (proc.returncode, proc.stdout[-500:]))
    proc = run_cli(["--body-file", fpath])
    check("I CLI: NO title source judges it as a release body AND says why, so a feature author who "
          "forgot `--title` sees the cause, not only the red",
          proc.returncode == 1 and "no PR title was given" in proc.stdout
          and "heading-not-allowed" in proc.stdout, (proc.returncode, proc.stdout[:500]))
    proc = run_cli(["--body-file", fpath, "--title-env", "COORD_PR_TITLE"])
    check("I CLI: an UNSET title variable is no title — judged as a release body, exit 1, never "
          "exit 2", proc.returncode == 1 and "no PR title was given" in proc.stdout,
          (proc.returncode, proc.stderr[:200], proc.stdout[:300]))
    proc = run_cli(["--body-file", fpath, "--title", FEATURE_TITLE, "--json"])
    check("I CLI: `--json` carries the title it decided on, RAW",
          proc.returncode == 0 and ('"title": "%s"' % FEATURE_TITLE) in proc.stdout
          and '"clean": true' in proc.stdout, proc.stdout[:400])
    proc = run_cli(["--body-file", fpath, "--title", "x", "--title-env", "COORD_PR_TITLE"])
    check("I CLI: `--title` and `--title-env` together are a usage fault — one source, as for the "
          "body", proc.returncode == 2, (proc.returncode, proc.stderr[:200]))

    # (9) THE SHIPPED WORKFLOW PASSES THE TITLE. The lint cannot scope a PR nobody named, and a
    # workflow that does not pass it runs every PR as a release — the defect, reinstated silently.
    # WHICH workflow is an input (card#10719); one that cannot be read fails THIS step by name,
    # and the arms after this one still run.
    wf = WORKFLOW
    try:
        with open(wf, encoding="utf-8") as fh:
            wf_text = fh.read()
    except OSError as exc:
        check("I the workflow that runs the lint could be read", False,
              "could not read %r (from %s): %s. A repo that vendors this selftest keeps the "
              "workflow elsewhere: pass `--workflow PATH` or set %s=PATH, e.g. "
              "`--workflow .github/workflows/pr-body-lint.yml`"
              % (wf, WORKFLOW_SOURCE, exc.strerror or exc, WORKFLOW_ENV))
        return
    check("I the shipped workflow passes the PR TITLE through `env:` and names it to the lint",
          "COORD_PR_TITLE: ${{ github.event.pull_request.title }}" in wf_text
          and re.search(r"--title-env COORD_PR_TITLE\b", wf_text) is not None, wf)

    # (10) THE WORKFLOW JUDGES A PR WITH THE BASE'S COPY OF THE LINT (card#12387 item 5).
    workflow_judges_with_base_copy(td, wf, wf_text)


# A narration body under a feature title: the real lint reds it on `banned-opener` and nothing else.
WF_RED_BODY = ("Fixes the retry window.\n\nBuilt: inline (trivial)\nCoordinated in: card#1\n"
               "Origin: bug-fix card#1\n\nWhy we did it: the daemon stalled.\n")
# What a PR that edits the lint to wave itself through would put in `VENDORED_LINT_REL` (LOCAL EDIT).
WF_LENIENT_LINT = "import sys\nprint('lenient copy: everything passes')\nsys.exit(0)\n"


def _workflow_step_script(wf_text):
    """The `run: |` block of the workflow's lint step, dedented — the script CI runs."""
    lines = wf_text.split("\n")
    start = next(i for i, l in enumerate(lines) if "- name: Lint the PR body" in l)
    run_at = next(i for i in range(start, len(lines)) if re.match(r"^\s+run: \|\s*$", lines[i]))
    indent = len(lines[run_at]) - len(lines[run_at].lstrip())
    block = []
    for l in lines[run_at + 1:]:
        if l.strip() and len(l) - len(l.lstrip()) <= indent:
            break
        block.append(l)
    width = min(len(l) - len(l.lstrip()) for l in block if l.strip())
    return "\n".join(l[width:] for l in block) + "\n"


# The fixture builds real repositories, so it must not inherit a hook's GIT_DIR (card fw#823).
# VENDOR-BEGIN(git-env)
# GENERATED — do not edit; source: plugins/coord/_vendor/git-env.py.txt; regenerate (framework repo only): python3 tools/gen-vendored.py; fragment-sha256: 537972ca69e8e779
# jscpd:ignore-start
def git_env(base=None, **overrides):
    """An environment for a git aimed at a repository OTHER than the ambient one: every
    inherited `GIT_*` variable dropped, then `overrides` layered on top.

    WHY IT EXISTS. `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE`, `GIT_PREFIX` and their
    siblings OUTRANK both the child's working directory and an explicit `git -C <dir>`, so
    the target written at the call site does not win the argument. Git EXPORTS them to its
    own hooks, and in a LINKED WORKTREE it exports an ABSOLUTE `GIT_DIR`
    (`…/.git/worktrees/<name>`) — so every nested git call made from a worktree hook lands
    in the HOOK'S repository rather than the one the caller named:

        $ GIT_DIR=<other>/.git git -C <fresh-dir> init -q -b b
        warning: re-init: ignored --initial-branch=b        <- it RE-INIT'd <other>

    A NON-worktree checkout exports no `GIT_DIR` and only a RELATIVE `.git/index`, which is
    why this stays invisible from a main checkout and green on every hand run.

    THE WHOLE `GIT_` PREFIX, NEVER AN ENUMERATED LIST. A list can only name the variables
    that have already bitten someone, so it is permanently one variable behind; the prefix
    is the namespace git itself reserves, and it covers the next variable with no edit.

    NOTHING INHERITED SURVIVES — the keep-list is EMPTY, and that is a decision taken WITH
    the population that would have survived, not for want of one. Measured on git 2.53
    against `git -C <dir> rev-parse --show-toplevel`:

      GIT_CEILING_DIRECTORIES  A ceiling stops only discovery that must ASCEND, and that
        bound is the whole of its reach. With a ceiling on the target's own repo root,
        `git -C <root>` still answers with the toplevel — the start directory holds the
        `.git` itself, so nothing is walked upward — while `git -C <root>/sub` from the
        identical environment is `fatal: not a git repository`, rc 128. (Re-measured on git
        2.43 for card#8617, with the two forms as the control for each other; the wording
        here previously claimed the rc 128 for both.) Dropping the variable can therefore
        ADD the true answer for a caller whose path sits BELOW the repo root, and can never
        redirect one — so the keep-list stays empty on its own argument either way.
      GIT_CONFIG_GLOBAL        Load-bearing in the OPPOSITE direction: on a repo git judges
        dubiously owned, the `safe.directory` exception lives in whichever global config is
        in force. Dropping the variable returns git to the user's own `~/.gitconfig`, where
        the exception is found or it is not — and when it is not the answer is rc 128, an
        honest refusal rather than a wrong answer.
      GIT_EXEC_PATH            Not load-bearing, PROBED rather than reasoned: aimed at an
        empty directory it leaves `rev-parse` answering normally (a builtin) while
        `git submodule` from the same environment dies with "is not a git command" and
        recovers the instant the variable is unset — so the probe was shown capable of the
        other answer before its null result was believed.

    NEITHER LOAD-BEARING VARIABLE CAN PRODUCE A FALSE ANSWER, which is the only outcome this
    contract cannot survive. Add a survivor here only with a measurement showing that
    dropping it answers WRONGLY, never merely that it answers less often.

    SCRUB THEN LAYER, AND THE ORDER IS STRUCTURAL RATHER THAN A CONVENTION. A caller that
    deliberately sets a `GIT_*` value — `GIT_TERMINAL_PROMPT=0` so a credential-less clone
    fails instead of stalling on a prompt no terminal will answer, `GIT_AUTHOR_DATE` for a
    reproducible fixture commit — passes it as an `overrides` keyword and it is applied
    AFTER the drop. The inverse order silently deletes exactly the value the caller meant
    to set, and `git_env(GIT_TERMINAL_PROMPT="0")` cannot be written in that order. An
    INHERITED value is by definition not a deliberate one, which is why no keep-list is
    needed to protect the deliberate case.

    `base` is the mapping to scrub, defaulting to `os.environ`. A caller that has already
    built a child environment passes it here rather than scrubbing afterwards, so the drop
    is never applied to a dict that a later `dict(...)` re-widens.

    A COPY, never an in-place edit: the caller's own AMBIENT git calls — a hook asking
    about the repository it was invoked for — must keep the environment they were handed,
    and that environment is exactly what this function refuses to hand onward.

    WINDOWS IS REASONED, NOT MEASURED, and is recorded as such: Windows Python upper-cases
    every `os.environ` key and git's own variables are already upper-case, so a
    `startswith("GIT_")` filter matches there by construction.
    """
    src = os.environ if base is None else base
    env = {k: v for k, v in src.items() if not k.startswith("GIT_")}
    env.update(overrides)
    return env
# jscpd:ignore-end
# VENDOR-END(git-env)


def git(cwd, *args):
    """`git` in the fixture repository `cwd`, its stdout. A failure RAISES (`check=True`), so no
    call here reads an empty answer as a measurement."""
    return subprocess.run(["git", "-c", "user.name=selftest", "-c", "user.email=selftest@invalid",
                           "-c", "init.defaultBranch=main", "-c", "commit.gpgsign=false"]
                          + list(args), cwd=cwd, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=60, check=True,
                          env=git_env()).stdout.strip()


# LOCAL EDIT (card#13778): where this repo's workflow reads the lint; the framework's is `bin/`.
VENDORED_LINT_REL = (".github", "pr-body-lint", "pr-body-lint.py")


def _pr_checkout(td, name, base_lint, head_lint, depth, merge=True, head_is_merge=False):
    """A clone shaped as `actions/checkout` leaves a `pull_request` run: the PR's MERGE commit
    (first parent the base, second the PR head) fetched at `depth`, and the PR head's sha — what
    the event's `pull_request.head.sha` names. `base_lint` / `head_lint` are the bytes of
    `VENDORED_LINT_REL` on each side (LOCAL EDIT), `None` for no file. `merge=False` checks out the PR head
    itself instead — the checkout of an adopter who set `ref:` to the head sha. `head_is_merge`
    makes the PR head a merge of the base INTO the PR branch ("Update branch"), so that head has
    a second parent of its own and its first parent carries the PR's lint."""
    origin = os.path.join(td, name + "-origin")
    os.makedirs(origin)
    git(origin, "init", "-q")

    def commit(content, msg):
        path = os.path.join(origin, *VENDORED_LINT_REL)  # LOCAL EDIT (card#13778)
        if content is None:
            if os.path.exists(path):
                git(origin, "rm", "-q", path)
        else:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(content)
            git(origin, "add", path)
        git(origin, "commit", "-q", "--allow-empty", "-m", msg)
        return git(origin, "rev-parse", "HEAD")

    root = commit(None, "root")
    base = commit(base_lint, "base")
    git(origin, "checkout", "-q", "-b", "pr", root)
    commit(head_lint, "pr head")
    if head_is_merge:
        git(origin, "merge", "-q", "--no-ff", "-X", "ours", "-m", "update branch", base)
    head = git(origin, "rev-parse", "pr")
    git(origin, "checkout", "-q", "--detach", base)
    git(origin, "merge", "-q", "--no-ff", "-X", "theirs", "-m", "merge", "pr")
    ref = git(origin, "rev-parse", "HEAD" if merge else "pr")
    git(origin, "update-ref", "refs/pull/1/merge", ref)
    work = os.path.join(td, name + "-work")
    os.makedirs(work)
    git(work, "init", "-q")
    git(work, "fetch", "-q", "--depth=%d" % depth, "file://" + origin,
         "+refs/pull/1/merge:refs/remotes/pull/1/merge")
    git(work, "checkout", "-q", "--detach", "refs/remotes/pull/1/merge")
    return work, head


def workflow_judges_with_base_copy(td, wf, wf_text):
    with open(TOOL, encoding="utf-8") as fh:
        real_lint = fh.read()
    try:
        script = _workflow_step_script(wf_text)
    except (StopIteration, ValueError):
        check("I the lint step's `run:` script could be read out of the workflow", False, wf)
        return
    m = re.search(r"^\s+fetch-depth:\s*(\d+)\s*$", wf_text, re.M)
    depth = int(m.group(1)) if m else 1   # `actions/checkout`'s default when the key is absent
    runner_temp = os.path.join(td, "runner-temp")
    os.makedirs(runner_temp, exist_ok=True)

    def run_step(checkout):
        work, head = checkout
        env = git_env(COORD_PR_BODY=WF_RED_BODY, COORD_PR_AUTHOR_TYPE="User",
                      COORD_PR_TITLE="fix: retry window", COORD_PR_HEAD_SHA=head,
                      RUNNER_TEMP=runner_temp)
        return subprocess.run(["bash", "-c", script], cwd=work, capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=120, env=env)

    # The merge-commit check compares HEAD^2 with the PR head the EVENT names; the rows below set
    # that variable themselves, so the workflow must be shown to pass it from the event.
    check("I the workflow passes the PR head sha from the event as COORD_PR_HEAD_SHA",
          "COORD_PR_HEAD_SHA: ${{ github.event.pull_request.head.sha }}" in wf_text, wf)

    # The PR edits the lint to pass everything; the base's copy must still be the judge.
    proc = run_step(_pr_checkout(td, "wf-edits-lint", real_lint, WF_LENIENT_LINT, depth))
    check("I the workflow judges a PR that EDITS the lint with the BASE's copy — the PR's lenient "
          "copy does not wave its own red body through",
          proc.returncode == 1 and "banned-opener" in proc.stdout
          and "lenient copy" not in proc.stdout,
          (proc.returncode, proc.stdout[-500:], proc.stderr[-300:]))

    # The adoption PR: the base has no lint yet, so the copy the PR adds is the only judge — and the
    # run says that is what happened.
    proc = run_step(_pr_checkout(td, "wf-adopts", None, real_lint, depth))
    check("I on the ADOPTION PR (no lint at the base) the workflow runs the copy the PR adds, and "
          "says so", proc.returncode == 1 and "banned-opener" in proc.stdout
          and "adopts the lint" in proc.stdout,
          (proc.returncode, proc.stdout[-500:], proc.stderr[-300:]))

    # A checkout that is not this PR's merge commit — too shallow, or the PR head checked out
    # instead of it — must fail, never judge with the PR's own copy. `wf-head-ref-merge` is the
    # case a bare "has a second parent" check passes: the PR head is itself a merge of the base
    # ("Update branch"), so it HAS a second parent, and its first parent carries the PR's lint.
    for name, d, merge, head_is_merge in (("wf-shallow", 1, True, False),
                                          ("wf-head-ref", depth, False, False),
                                          ("wf-head-ref-merge", depth, False, True)):
        proc = run_step(_pr_checkout(td, name, real_lint, WF_LENIENT_LINT, d, merge,
                                     head_is_merge))
        check("I a checkout that is not this PR's merge commit (%s) is a fault (exit 2) that "
              "names the cause, never the PR's own copy" % name,
              proc.returncode == 2 and "lenient copy" not in proc.stdout
              and "merge commit" in proc.stdout + proc.stderr,
              (proc.returncode, proc.stdout[-300:], proc.stderr[-300:]))

    # THE CONTROL: with the merge-commit check cut out of the script, the shallow checkout reads as
    # the adoption PR and the PR's lenient copy judges it — the check is what refused it above.
    guard = re.search(r"^if [^\n]*COORD_PR_HEAD_SHA.*?HEAD\^2.*?^fi\n", script, re.M | re.S)
    if guard is None:
        check("I CONTROL: the lint step's merge-commit check could be found to cut out", False,
              script[:400])
        return
    script = script.replace(guard.group(0), "")
    proc = run_step(_pr_checkout(td, "wf-shallow-unguarded", real_lint, WF_LENIENT_LINT, 1))
    if check("I CONTROL: without the merge-commit check, a shallow checkout falls back to the PR's "
             "own lenient copy and passes", proc.returncode == 0 and "lenient copy" in proc.stdout,
             (proc.returncode, proc.stdout[-300:])):
        seen_red("I the base-copy judge, driven red by a workflow script without its merge-commit "
                 "check, whose shallow checkout is judged by the PR's own copy")


# ══════════════════════════════════════════════════════════════════════════════════════════════
# E — THE CLI, WHICH IS WHAT CI AND THE REVIEW PATH ACTUALLY RUN
# ══════════════════════════════════════════════════════════════════════════════════════════════
# ══════════════════════════════════════════════════════════════════════════════════════════════
# J — `ai-attribution`: NO LINE NAMES THE AI MODEL OR CARRIES A SESSION LINK (card#10673)
# ══════════════════════════════════════════════════════════════════════════════════════════════
# The literal footer line the harness wrote on fw#891 — the known positive's own last line. The
# negative is that body with THIS line removed by its literal text, never by the matcher under
# test: a negative built with the rule's own matcher would pass by construction.
FW891_FOOTER = "🤖 Generated with [Claude Code](https://claude.com/claude-code)"

# One row per shape, each a line the harness actually writes (or the stamp `coord-post` wrote before
# card#10673 retired it),
# and one row per shape that must NOT red: a placeholder or a mid-line mention of the same words.
AI_REDS = (
    ("co-author-trailer", "Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"),
    ("co-author-trailer", "co-authored-by: Claude <noreply@anthropic.com>"),
    ("co-author-trailer", "Co-Authored-By: Some Model <noreply@anthropic.com>"),
    ("session-trailer", "Claude-Session: https://claude.ai/code/session_01ABCdef"),
    ("session-link", "https://claude.ai/code/session_01M3jAPrz9zCGzdm9HJMQeFV"),
    ("generated-footer", "🤖 Generated with [Claude Code](https://claude.com/claude-code)"),
    ("generated-footer", "Generated with Claude Code"),
    ("generated-footer", "> 🤖 Generated with [Claude Code](https://claude.com/claude-code)"),
    ("ctx-stamp", "<!-- CTX: 47% | 94200tok | base 31000+20000 | KEEP -->"),
    ("ctx-stamp", "status update <!-- CTX: 70% -->"),
)
AI_PASSES = (
    "Co-authored-by: Fix Human <human@example.invalid>",
    # A HUMAN co-author whose name opens `Claude` (fw#1095 r1): only the harness's own address
    # marks the harness trailer, so this person's credit is not judged.
    "Co-authored-by: Claude Monet <claude.monet@example.com>",
    # Prose that QUOTES the footer's words in backticks is not the footer (fw#1095 r1).
    "- `Generated with [Claude Code]` footer is now dropped",
    "The harness adds a `Co-Authored-By: Claude` trailer by default.",
    # BOTH TRAILERS QUOTED MID-LINE, IN FULL (fw#1095 r2). The trailer shapes are anchored at the
    # line start, and these two lines are what holds that anchor: the co-author line carries the
    # harness's own address, so only the anchor keeps it from red; the session line is the
    # session-trailer's one near miss.
    "The harness ends each commit on `Co-Authored-By: Claude Opus 4.6 (1M context) "
    "<noreply@anthropic.com>` unless the composer drops it.",
    "The composer also drops the Claude-Session: trailer the harness writes after it.",
    "A session link has the form `claude.ai/code/session_<id>`.",
    "The stamp is written `<!-- CTX: <pct>% -->`.",
    "This was generated with care.",
)


def arm_j_ai_attribution(mod, td):
    positive = read_fixture("attr_negative")
    check("J fixture: the known positive still ends on the harness footer this arm is about",
          FW891_FOOTER in positive.split("\n"), "footer line not found in fw#891's body")
    hits = [f for f in mod.findings(positive) if f.rule == "ai-attribution"]
    check("J the KNOWN POSITIVE — fw#891's live body, harness footer and all — reds on "
          "`ai-attribution`, on that line, quoting it",
          len(hits) == 1 and hits[0].text == FW891_FOOTER, [(f.line, f.text) for f in hits])
    negative = "\n".join(l for l in positive.split("\n") if l != FW891_FOOTER)
    check("J the NEGATIVE — the same body without that one line — passes EVERY rule",
          rules_on(mod, negative) == [], rules_on(mod, negative))

    for shape, line in AI_REDS:
        body = COMPLIANT_BODY + "\n" + line + "\n"
        got = [mod.ai_attribution_shape(line)]
        check("J `%s` reds on %r" % (shape, line),
              got == [shape] and "ai-attribution" in rules_on(mod, body),
              (got, rules_on(mod, body)))
    for line in AI_PASSES:
        body = COMPLIANT_BODY + "\n" + line + "\n"
        check("J `ai-attribution` does not fire on %r" % line,
              "ai-attribution" not in rules_on(mod, body), rules_on(mod, body))

    fenced = COMPLIANT_BODY + "\n```\n%s\n```\n" % AI_REDS[0][1]
    check("J a trailer that exists only INSIDE A FENCE is payload in a PR body, not a finding",
          "ai-attribution" not in rules_on(mod, fenced), rules_on(mod, fenced))
    feature = rules_on(mod, "fix: a thing.\n\nBuilt: x\nCoordinated in: acme/c#1\n\n%s\n"
                       % FW891_FOOTER, title="fix(x): a feature PR")
    check("J it runs on EVERY PR — a FEATURE title does not scope it out", feature == ["ai-attribution"],
          feature)

    # ⛔ THE CONTROL. Unwire the rule from the one entry point: the known positive must stop reding
    # on `ai-attribution` — and with nothing else left to red on, pass outright — or the green above
    # is not evidence the rule is what reds it.
    unwired = mutant(td, "ai-attribution-unwired",
                     ("+ rule_attribution_line(rows) + rule_ai_attribution(rows)",
                      "+ rule_attribution_line(rows)"))
    got_u = rules_on(unwired, positive)
    if check("J CONTROL: with `rule_ai_attribution` UNWIRED, fw#891's footer passes — so the rule "
             "is what reds it", got_u == [], got_u):
        seen_red("J the ai-attribution rule, driven red by an unwired copy that lets fw#891's own "
                 "harness footer through")


# ══════════════════════════════════════════════════════════════════════════════════════════════
# O — `merge-instruction`: THE MERGE-METHOD NOTE, ON A RELEASE PR (card#13034)
# ══════════════════════════════════════════════════════════════════════════════════════════════
# The KNOWN POSITIVE is AIMLA-org/platform#467's line, verbatim as card#13034 quotes it: that body
# passed `pr-body-lint.py --title 'release: aimla-v0.1.1'` clean, and its live body no longer
# carries the line. It is a constant here, not a committed body: the rule judges one line, and the
# rest of that body is another repo's release text.
P467_LINE = ('**Merge with "Create a merge commit", never squash.** Tag `aimla-v0.1.1` is applied '
             'by hand after the merge.')

# PupFuzz/kanban-board#592's struck line, RECONSTRUCTED. That body's edit history was not readable
# when this arm was written (the repo 404s to every token this seat holds, and the edit history is
# GraphQL-only), so the struck text itself is not here. These are the merge-method and merge-gate
# lines of the release-body template `skills/release-pr/SKILL.md` Step 10 carried when #592 was
# drafted (`git show 6ba6ccaa^:plugins/coord/skills/release-pr/SKILL.md`, the commit card#6344
# struck them in), which is what a body drafted from that template carried.
KB592_RECONSTRUCTED = (
    ("merge-method", "- [x] Merge-button intent: **Create a merge commit**"),
    ("merger-named", "- User is the merger (release PRs to the release branch are the production "
                     "gate; no carve-out)"),
    ("merge-gate-wait", "- Pre-merge: wait for `mergeStateStatus: CLEAN` (all required CI checks "
                        "pass)"),
    ("merge-method", "- Merge button: **Create a merge commit** (per `pr-review-flow.md`)"),
)

# One example per shape alternative, each pinning ONE shape, so each per-shape mutant can be read.
# The rows marked `fw#<n>` are this repo's own release bodies, verbatim (`gh api
# repos/PupFuzz/agent-board-framework/pulls/<n> --jq .body`): earlier instances that passed.
MERGE_ROWS = KB592_RECONSTRUCTED + (
    # fw#815, lines 4 and 5.
    ("merge-method", '**Merge with "Create a Merge Commit"** (`skills/release-pr/SKILL.md § '
                     'Merge-button intent`) — do'),
    ("merge-method", "NOT squash. Do not merge on my account: this is the operator's gate."),
    # fw#707, line 6.
    ("merge-method", "**Merge button: `Create a Merge Commit`** (release PR — squashing corrupts "
                     "the release topology"),
    ("merge-method", "- Merge with **Create a merge commit**."),
    ("merge-method", "Do not squash this PR."),
    ("merge-method", '- Use "Create a merge commit".'),
    ("merger-named", "- The operator merges this once CI is CLEAN."),
    ("tag-after-merge", "- Tag `v1.4.0` is pushed after the merge."),
    ("tag-after-merge", "- Tag `v1.4.0` manually."),
)

# Lines that NAME a merge method as their SUBJECT — changelog-style highlights, and the generated
# `## Bundled` list's PR titles — must pass.
MERGE_SUBJECT_LINES = (
    "- `coord-self-merge` refuses a squash of a back-merge sync PR, so sync PRs are never squashed.",
    "- `branch-lines.sh` refuses to create a merge commit on a squash-only line.",
    "- `coord-sync` will never squash a back-merge sync PR.",
    "- `git rebase` is no longer run by `coord-build fix`; it merges the base instead.",
    "- `auto-tag-version.yml` creates the release tag after the merge to `main`.",
)
MERGE_BUNDLED_LINE = "- **#1475** fix(self-merge): refuse a squash of a back-merge sync PR (card#6942)"

# The header's NAMED residues, pinned so the list there is a measured claim.
MERGE_NOT_JUDGED = (
    ("a merge instruction whose opening token follows a word",
     "- Please merge with a merge commit."),
    ("a merge instruction in words no shape matches", "- Use the merge-commit button, please."),
)


def _in_highlights(line):
    """COMPLIANT_BODY with `line` as the first line of `## Highlights` — appended at the END it
    would sit under `## Bundled`, which this rule does not judge."""
    anchor = "## Highlights\n\n"
    if COMPLIANT_BODY.count(anchor) != 1:
        FAILURES.append("O the `## Highlights` anchor is not in COMPLIANT_BODY exactly once")
    return COMPLIANT_BODY.replace(anchor, anchor + line + "\n", 1)


def _merge_hits(mod, line, title=None):
    """The shapes `mod` names on `line` placed in a release body's highlights — `[]` for none."""
    kw = {} if title is None else {"title": title}
    hits = [f for f in mod.findings(declared(_in_highlights(line)), None, **kw)
            if f.rule == "merge-instruction"]
    return [s for s, _ in mod.MERGE_INSTRUCTIONS if hits and "`%s`" % s in hits[0].message]


def arm_o_merge_instruction(mod, td):
    body = _in_highlights(P467_LINE)
    got = rules_on(mod, body, title=RELEASE_TITLE)
    hits = [f for f in mod.findings(declared(body), None, title=RELEASE_TITLE)
            if f.rule == "merge-instruction"]
    check("O platform#467's line in a release body reds on `merge-instruction` and nothing else",
          got == ["merge-instruction"], got)
    check("O ...on that line, quoting it, naming `merge-method` and `tag-after-merge`, and citing "
          "§ PR body", len(hits) == 1 and hits[0].text == P467_LINE
          and _merge_hits(mod, P467_LINE) == ["merge-method", "tag-after-merge"]
          and "`skills/release-pr/SKILL.md § PR body`" in hits[0].message,
          [(f.text, f.message[:120]) for f in hits])

    for shape, line in MERGE_ROWS:
        check("O `%s` reds on %r, naming that shape alone" % (shape, line),
              _merge_hits(mod, line) == [shape], _merge_hits(mod, line))
    for line in MERGE_SUBJECT_LINES:
        got = rules_on(mod, _in_highlights(line), title=RELEASE_TITLE)
        check("O a line naming a merge method as its SUBJECT passes: %r" % line, got == [], got)
    bundled = COMPLIANT_BODY.replace("- #311 — read the env file\n",
                                     "- #311 — read the env file\n" + MERGE_BUNDLED_LINE + "\n", 1)
    check("O the bundled-line anchor applied", bundled != COMPLIANT_BODY)
    got = rules_on(mod, bundled, title=RELEASE_TITLE)
    check("O a changelog line about squash in the generated `## Bundled` section passes", got == [],
          got)
    for why, line in MERGE_NOT_JUDGED:
        got = rules_on(mod, _in_highlights(line), title=RELEASE_TITLE)
        check("O NOT judged — %s: %r" % (why, line), got == [], got)
    in_bundled = COMPLIANT_BODY.replace("- #311 — read the env file\n",
                                        "- #311 — read the env file\n" + P467_LINE + "\n", 1)
    got = rules_on(mod, in_bundled, title=RELEASE_TITLE)
    check("O NOT judged — a merge instruction hand-added under `## Bundled` (the header's "
          "residue)", got == [], got)
    after = in_bundled.replace("<!-- release-manifest:shipped-refs=310,311 -->\n",
                               "<!-- release-manifest:shipped-refs=310,311 -->\n\n"
                               "## Release artifacts\n\n" + P467_LINE + "\n", 1)
    got = rules_on(mod, after, title=RELEASE_TITLE)
    check("O ...and the section after `## Bundled` is judged again", got == ["merge-instruction"],
          got)
    fenced = _in_highlights("```\n%s\n```" % P467_LINE)
    commented = _in_highlights("<!-- %s -->" % P467_LINE)
    check("O a merge instruction inside a FENCE or an HTML comment is not judged",
          rules_on(mod, fenced, title=RELEASE_TITLE) == []
          and rules_on(mod, commented, title=RELEASE_TITLE) == [],
          (rules_on(mod, fenced, title=RELEASE_TITLE), rules_on(mod, commented, title=RELEASE_TITLE)))

    # RELEASE PRs ONLY: the same line on a feature PR is not this rule's, and with NO title it is
    # judged as a release, the strict side.
    feature = FEATURE_BODY + "\n" + P467_LINE + "\n"
    got = rules_on(mod, feature, title=FEATURE_TITLE)
    check("O the same line on a NON-release PR does not fire `merge-instruction`",
          "merge-instruction" not in got, got)
    check("O ...and with no title it does (a missing title is judged as a release)",
          _merge_hits(mod, P467_LINE, title=None) == ["merge-method", "tag-after-merge"],
          _merge_hits(mod, P467_LINE, title=None))

    # ⛔ THE CONTROLS. Unwired, every positive above passes — the state before card#13034, in which
    # platform#467's body passed clean.
    unwired = mutant(td, "merge-instruction-unwired",
                     ("        out += rule_merge_instruction(rendered)\n", ""))
    still = [line for _, line in MERGE_ROWS + (("", P467_LINE),)
             if rules_on(unwired, _in_highlights(line), title=RELEASE_TITLE)]
    if check("O CONTROL: with `rule_merge_instruction` UNWIRED, platform#467's line and every "
             "reconstructed kanban-board#592 line pass", not still, still):
        seen_red("O the merge-instruction rule, driven red by an unwired copy that lets "
                 "platform#467's merge-method line through")
    every = mutant(td, "merge-instruction-every-pr",
                   ("           + rule_declarations(body or \"\", author_type))\n",
                    "           + rule_declarations(body or \"\", author_type)"
                    " + rule_merge_instruction(rendered))\n"))
    got = rules_on(every, feature, title=FEATURE_TITLE)
    if check("O CONTROL: with the rule run on EVERY PR, the feature PR's line reds — the release "
             "predicate is what keeps it off a feature PR", "merge-instruction" in got, got):
        seen_red("O the release scope of `merge-instruction`, driven red by a copy that runs it on "
                 "a feature PR")
    nobundle = mutant(td, "merge-instruction-judges-bundled",
                      ("        if generated:\n            continue\n", ""))
    got = rules_on(nobundle, in_bundled, title=RELEASE_TITLE)
    if check("O CONTROL: with the `## Bundled` skip removed, a line under that heading reds — the "
             "skip is what keeps the generated list unjudged", got == ["merge-instruction"], got):
        seen_red("O the `## Bundled` skip, driven red by a copy that judges the generated list")
    for shape, _ in mod.MERGE_INSTRUCTIONS:
        off = mutant(td, "merge-shape-%s-disabled" % shape,
                     ('("%s",\n     r"(?:' % shape, '("%s",\n     r"(?!)(?:' % shape))
        own = [line for s, line in MERGE_ROWS if s == shape]
        others = [line for s, line in MERGE_ROWS if s != shape]
        if check("O CONTROL: with shape `%s` DISABLED, its own rows stop reding while every other "
                 "shape's rows still red" % shape,
                 own and all(_merge_hits(off, l) == [] for l in own)
                 and all(_merge_hits(off, l) for l in others),
                 ([_merge_hits(off, l) for l in own], [_merge_hits(off, l) for l in others])):
            seen_red("O shape `%s`, driven red by a copy whose pattern can never match" % shape)
    opener = mutant(td, "merge-opener-dropped", (r"(?<!\w )", ""), count=-1)
    withheld = (MERGE_SUBJECT_LINES[1], MERGE_SUBJECT_LINES[2], MERGE_NOT_JUDGED[0][1])
    reds = [line for line in withheld
            if "merge-instruction" in rules_on(opener, _in_highlights(line), title=RELEASE_TITLE)]
    if check("O CONTROL: with the clause-opening narrowing dropped, the subject lines `to create "
             "a merge commit` / `will never squash` and the `please merge with` residue red — the "
             "narrowing is what withholds them", len(reds) == len(withheld), reds):
        seen_red("O the clause-opening narrowing, driven red by a copy without `(?<!\\w )`")


# ══════════════════════════════════════════════════════════════════════════════════════════════
# M — THE PROVENANCE ROWS (card#11037): `Origin:`, `Design-approved:` and `Tier:`
# ══════════════════════════════════════════════════════════════════════════════════════════════
def arm_m_provenance(mod, td):
    def body(*lines):
        return "Fix the retry loop.\n\nBuilt: inline (trivial)\n**Coordinated in:** acme/coordination#1\n" + (
            "\n".join(lines) + "\n" if lines else "")

    feat = "fix: retry loop"
    check("M a body declaring `Origin: bug-fix card#<n>` passes every rule",
          rules_on(mod, body("Origin: bug-fix card#7"), title=feat, raw=True) == [],
          rules_on(mod, body("Origin: bug-fix card#7"), title=feat, raw=True))
    for lines in (("**Origin:** operator-directive card#283",),
                  ("Origin: operator-directive opq-1792846742-05a9",),
                  ("Origin: bundle",),
                  ("Origin: agent-originated card#7", "Design-approved: `opq-1792846742-05a9`"),
                  ("Origin: bug-fix card#7", "Tier: **RESERVED** money: payouts"),
                  ("Origin: bug-fix card#7", "Tier: routine"),
                  # card#12757: a change to tests alone names the card it was dispatched under.
                  ("Origin: test-only card#7",),
                  # card#12618: a `/coord:update` reconcile PR carries no card and no opq.
                  ("Origin: reconcile",),
                  ("Origin: reconcile area 4 orientation re-sync",)):
        got = rules_on(mod, body(*lines), title=feat, raw=True)
        check("M well-formed provenance passes: %r" % (lines,), got == [], got)
    cases = (
        ("origin-missing", body()),
        ("origin-malformed", body("Origin: guess card#7")),
        ("origin-malformed", body("Origin: bug-fix 7")),
        ("origin-malformed", body("Origin: operator-directive")),
        # card#11037 r1: a directive the merge gate cannot check is malformed, not merely unproven.
        ("origin-malformed", body("Origin: operator-directive thread#7 c-1")),
        # the bot origin is derived from the PR's author by the gate; no body may claim it.
        ("origin-malformed", body("Origin: dependency-bump")),
        ("origin-malformed", body("Origin: bug-fix card#7", "Origin: bundle")),
        # card#12757: `test-only` names its card the way `bug-fix` does.
        ("origin-malformed", body("Origin: test-only 7")),
        ("origin-malformed", body("Origin: test-only")),
        ("design-approved-missing", body("Origin: agent-originated card#7")),
        ("design-approved-malformed", body("Origin: agent-originated card#7",
                                           "Design-approved: card#12")),
        ("tier-malformed", body("Origin: bug-fix card#7", "Tier: hard")),
    )
    for rule, text in cases:
        got = rules_on(mod, text, title=feat, raw=True)
        check("M `%s` reds on the body that violates exactly it, and nothing else" % rule,
              got == [rule], got)
    # card#12618's control: a `/coord:update` area-4 reconcile PR body (the `Built:` value
    # `docs/built-line.md` defines for it) reds without an origin and passes with `reconcile`.
    area4 = ("Re-sync the impl orientation file to the installed plugin.\n\n"
             "Built: in-session (docs/coordination)\n**Coordinated in:** acme/coordination#1\n")
    check("M card#12618: an area-4 reconcile body with NO `Origin:` reds `origin-missing`",
          rules_on(mod, area4, title="chore: coord:update reconcile", raw=True) == ["origin-missing"],
          rules_on(mod, area4, title="chore: coord:update reconcile", raw=True))
    check("M card#12618: the same body carrying `Origin: reconcile` passes",
          rules_on(mod, area4 + "Origin: reconcile\n", title="chore: coord:update reconcile",
                   raw=True) == [],
          rules_on(mod, area4 + "Origin: reconcile\n", title="chore: coord:update reconcile",
                   raw=True))
    # The `origin-missing` message spells the forms an author may write; every kind the one parser
    # accepts is among them, so the message cannot fall behind `ORIGIN_KINDS`.
    missing_msg = " ".join(f.message for f in mod.findings(body(), None, title=feat)
                           if f.rule == "origin-missing")
    unnamed = [k for k in mod.ORIGIN_KINDS if "`Origin: %s" % k not in missing_msg]
    check("M the `origin-missing` message names every kind in `ORIGIN_KINDS`", not unnamed,
          (unnamed, missing_msg))
    # The bot exemption reaches `origin-missing` and `design-approved-missing` only.
    for rule, text in (("origin-missing", body()),
                       ("design-approved-missing", body("Origin: agent-originated card#7"))):
        check("M a BOT-authored body is exempt from `%s`" % rule,
              rule not in rules_on(mod, text, "Bot", title=feat, raw=True),
              rules_on(mod, text, "Bot", title=feat, raw=True))
    check("M ...and NOT from a malformed line",
          "origin-malformed" in rules_on(mod, body("Origin: guess card#7"), "Bot", title=feat,
                                         raw=True), None)
    # A release body opening on the provenance line still has its scope line BELOW it.
    rel = "Origin: bundle\n\n" + COMPLIANT_BODY.replace("Origin: bundle\n", "")
    check("M a release body that OPENS on `Origin:` is not read as scope-line-less — the line is a "
          "machine row the scope rule skips", "scope-line" not in rules_on(mod, rel, raw=True),
          rules_on(mod, rel, raw=True))
    # The id pattern is a declared restatement of `coord-ask-operator`'s, held equal here.
    filer = os.path.join(HERE, "coord-ask-operator")
    if os.path.exists(filer):
        spec = importlib.util.spec_from_loader("pbl_cao", importlib.machinery.SourceFileLoader(
            "pbl_cao", filer))
        cao = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cao)
        check("M `DESIGN_APPROVED_ID_RE` is `coord-ask-operator`'s `ITEM_ID_RE`, character for "
              "character — the id the registry mints is the id this lint accepts",
              mod.DESIGN_APPROVED_ID_RE.pattern == cao.ITEM_ID_RE.pattern,
              (mod.DESIGN_APPROVED_ID_RE.pattern, cao.ITEM_ID_RE.pattern))
    else:
        # LOCAL EDIT (card#13778): this repo ships no `coord-ask-operator`, so the guard is skipped
        # out loud here rather than failed.
        print("pr-body-lint.selftest: NOTICE: arm m's DESIGN_APPROVED_ID_RE guard skipped — no "
              "`coord-ask-operator` beside this suite (%s)" % filer)
    unwired = mutant(td, "declarations-unwired",
                     ('           + rule_declarations(body or "", author_type))',
                      '           + [])'))
    if check("M CONTROL: with `rule_declarations` unwired, a body with no `Origin:` passes — the "
             "rule is what reds it",
             "origin-missing" not in rules_on(unwired, body(), title=feat, raw=True),
             rules_on(unwired, body(), title=feat, raw=True)):
        seen_red("M a missing `Origin:` line, passed by a copy whose provenance rule is unwired")
    proc = run_cli(["--env", "COORD_PR_BODY", "--title", feat], env={"COORD_PR_BODY": body()},
                   raw=True)
    check("M CLI: a body with no `Origin:` exits 1 naming `origin-missing`",
          proc.returncode == 1 and "origin-missing" in proc.stdout, proc.stdout[-300:])


# ══════════════════════════════════════════════════════════════════════════════════════════════
# N — THE REPO-DECLARED RELEASE HEADINGS (card#12387 item 4)
# ══════════════════════════════════════════════════════════════════════════════════════════════
# An adopting repo can REQUIRE a section on every PR — sola-device's shape guard requires
# `## SaMD boundary check` at level 2 — and the closed release set reds it, so no release body could
# pass both. The repo declares its extra release H2s in one file the lint reads from the directory
# it runs in; the vendored lint stays byte-identical. Driven through the CLI, because the file is
# read there and nowhere else.
HEADINGS_AS_DIRECTORY = object()   # sentinel: the declared-headings PATH exists as a directory


def _release_headings_run(td, name, declared_lines, body, title=RELEASE_TITLE):
    """The CLI on `body` under `title`, run in a fresh repo-shaped directory that carries the
    declared-headings file with `declared_lines` — or no file at all when `declared_lines` is None,
    the file's exact bytes when it is `bytes`, and a directory at that path when it is
    `HEADINGS_AS_DIRECTORY`."""
    repo = os.path.join(td, "release-headings-" + name)
    os.makedirs(os.path.join(repo, ".github"))
    if declared_lines is HEADINGS_AS_DIRECTORY:
        os.makedirs(os.path.join(repo, RELEASE_HEADINGS_REL))
    elif isinstance(declared_lines, bytes):
        with open(os.path.join(repo, RELEASE_HEADINGS_REL), "wb") as fh:
            fh.write(declared_lines)
    elif declared_lines is not None:
        with open(os.path.join(repo, RELEASE_HEADINGS_REL), "w", encoding="utf-8",
                  newline="") as fh:
            fh.write("".join(line + "\n" for line in declared_lines))
    path = os.path.join(repo, "body.md")
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(body)
    return run_cli(["--body-file", path, "--title", title, "--json"], cwd=repo)


def _rules_of(proc):
    try:
        return sorted(f["rule"] for f in json.loads(proc.stdout)["findings"])
    except ValueError:
        return None


def arm_n_repo_release_headings(td):
    samd = COMPLIANT_BODY + "\n## SaMD boundary check\n\nNo change to the SaMD boundary.\n"
    declared_file = ["SaMD boundary check", "CI action-pin resync check"]

    # (1) THE DEFECT, CLOSED — with the heading declared, a release body carrying it passes.
    proc = _release_headings_run(td, "declared", declared_file, samd)
    check("N with `%s` declaring `SaMD boundary check`, a RELEASE body carrying "
          "`## SaMD boundary check` passes" % RELEASE_HEADINGS_REL,
          proc.returncode == 0 and _rules_of(proc) == [], (proc.returncode, proc.stdout[-500:]))

    # (2) THE CONTROL — the same body with no file reds on that heading: today's behaviour.
    proc = _release_headings_run(td, "absent", None, samd)
    if check("N with NO declared-headings file the same release body reds `heading-not-allowed` — "
             "a missing file is no extras", proc.returncode == 1
             and _rules_of(proc) == ["heading-not-allowed"], (proc.returncode, proc.stdout[-500:])):
        seen_red("N the SaMD-heading release body with no declared-headings file")

    # (3) THE SET STAYS CLOSED — an undeclared heading still reds with the file present.
    proc = _release_headings_run(td, "undeclared", declared_file, samd + "\n## Summary\n")
    check("N with the file present an UNDECLARED heading (`## Summary`) still reds "
          "`heading-not-allowed`, and only it",
          proc.returncode == 1 and _rules_of(proc) == ["heading-not-allowed"]
          and "## Summary" in proc.stdout and "## SaMD boundary check\"" not in proc.stdout
          and RELEASE_HEADINGS_REL in proc.stdout,
          (proc.returncode, proc.stdout[-500:]))

    # (4) EXACT, NOT PREFIX — a declared heading admits that heading's full text only.
    for near in ("SaMD boundary check (none)", "SaMD boundary", "samd boundary check"):
        proc = _release_headings_run(td, "near-" + re.sub(r"\W", "_", near), declared_file,
                                     COMPLIANT_BODY + "\n## %s\n" % near)
        check("N a declared heading matches EXACTLY: `## %s` still reds" % near,
              proc.returncode == 1 and _rules_of(proc) == ["heading-not-allowed"],
              (proc.returncode, proc.stdout[-400:]))

    # (5) A LINE WRITTEN AS A HEADING (`## …`) IS A FAULT, NEVER A SILENT NON-MATCH.
    proc = _release_headings_run(td, "marker", ["## SaMD boundary check"], samd)
    check("N a declared line carrying the `#` marker is a usage fault (exit 2) naming the file",
          proc.returncode == 2 and RELEASE_HEADINGS_REL in proc.stderr,
          (proc.returncode, proc.stderr[:300]))

    # (6) NON-RELEASE PRs ARE UNTOUCHED — the file changes nothing under a feature title, either way.
    with_file = _rules_of(_release_headings_run(td, "feat-file", declared_file, FEATURE_BODY,
                                                FEATURE_TITLE))
    without = _rules_of(_release_headings_run(td, "feat-none", None, FEATURE_BODY, FEATURE_TITLE))
    malformed = _release_headings_run(td, "feat-marker", ["## SaMD boundary check"], FEATURE_BODY,
                                      FEATURE_TITLE)
    check("N a FEATURE PR's verdict is the same with the file, without it, and with a malformed one "
          "— the file is read for a release PR only",
          with_file is not None and with_file == without == _rules_of(malformed)
          and malformed.returncode == 0, (with_file, without, malformed.returncode))

    # (7) A LEADING UTF-8 BYTE-ORDER MARK IS NOT PART OF THE FIRST HEADING (fw#1405 r1). Left in
    # place it is glued to line 1: that declaration silently admits nothing, and a `## …` line 1
    # slips past the `#` fault in (5).
    bom = b"\xef\xbb\xbf"
    proc = _release_headings_run(td, "bom", bom + b"SaMD boundary check\n", samd)
    check("N a declared-headings file opening with a UTF-8 BOM still admits its FIRST heading",
          proc.returncode == 0 and _rules_of(proc) == [], (proc.returncode, proc.stdout[-500:]))
    proc = _release_headings_run(td, "bom-marker", bom + b"## SaMD boundary check\n", samd)
    check("N ...and a BOM before a `## ` first line is still the `#` usage fault (exit 2) naming "
          "the file", proc.returncode == 2 and RELEASE_HEADINGS_REL in proc.stderr
          and "opens with `#`" in proc.stderr, (proc.returncode, proc.stderr[:300]))

    # (8) A PATH THAT EXISTS AND CANNOT BE READ IS A FAULT, NEVER "NO EXTRAS" (fw#1405 r1).
    proc = _release_headings_run(td, "directory", HEADINGS_AS_DIRECTORY, samd)
    check("N a DIRECTORY at the declared-headings path is a usage fault (exit 2) naming the path",
          proc.returncode == 2 and RELEASE_HEADINGS_REL in proc.stderr
          and "could not be read" in proc.stderr, (proc.returncode, proc.stderr[:300]))


def run_cli(args, env=None, cwd=None, raw=False, tool=TOOL):
    """The lint — or the copy at `tool` — as a child. Unless `raw`, the body it is handed is
    `declared` first — a `--body-file` through a temporary copy, an `--env` body in place (see
    `DECLARED_ORIGIN`)."""
    if not raw:
        args, env = list(args), dict(env or {})
        if "--env" in args and args[args.index("--env") + 1] in env:
            var = args[args.index("--env") + 1]
            env[var] = declared(env[var])
        if "--body-file" in args and args[args.index("--body-file") + 1] != "-":
            i = args.index("--body-file") + 1
            with open(args[i], "rb") as fh:
                text = fh.read().decode("utf-8", "replace")
            if declared(text) != text:
                with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8",
                                                 newline="") as fh:
                    fh.write(declared(text))
                args[i] = fh.name
                try:
                    return run_cli(args, env, cwd, raw=True, tool=tool)
                finally:
                    os.unlink(fh.name)
    full = dict(os.environ)
    full.pop("COORD_PR_BODY", None)
    # ⛔ AND THE AUTHOR-TYPE VARIABLE TOO. A row here asserting that an UNSET variable is not a bot
    # would be measuring the machine it ran on if the seat happened to export this name.
    full.pop("COORD_PR_AUTHOR_TYPE", None)
    # …and the title variable, for the same reason: an unset title is judged as a release body.
    full.pop("COORD_PR_TITLE", None)
    full.update(env or {})
    return subprocess.run([sys.executable, tool] + args, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=60, env=full,
                          cwd=EMPTY_CWD if cwd is None else cwd)


def arm_e_cli(td):
    pos_path = os.path.join(FIXTURE_DIR, FIXTURES["positive"][0])
    neg_path = os.path.join(FIXTURE_DIR, FIXTURES["negative"][0])

    proc = run_cli(["--body-file", pos_path])
    check("E the CLI exits 1 on the known positive", proc.returncode == 1, proc.stdout[-400:])
    check("E ...and its output quotes the offending lines and carries no finding TALLY",
          "Correlation gaps" in proc.stdout and "Why MINOR" in proc.stdout
          and not re.search(r"\b\d+ finding", proc.stdout), proc.stdout[-400:])

    proc = run_cli(["--body-file", neg_path])
    check("E the CLI exits 0 on the known negative", proc.returncode == 0, proc.stdout[-400:])

    body_path = os.path.join(td, "body.md")
    with open(body_path, "w", encoding="utf-8", newline="") as fh:
        fh.write(COMPLIANT_BODY)
    proc = run_cli(["--body-file", body_path, "--json"])
    check("E `--json` exits 0 and carries the two audit VALUES the review path transports",
          proc.returncode == 0 and '"clean": true' in proc.stdout
          and "acme/coordination#412" in proc.stdout, proc.stdout[:400])

    # ⛔ THE CI ENTRY POINT IS `--env`, AND AN UNSET VARIABLE IS NOT AN EMPTY BODY. A workflow that
    # mis-spells the variable would otherwise get a clean-looking red on a body nobody read.
    proc = run_cli(["--env", "COORD_PR_BODY"], env={"COORD_PR_BODY": COMPLIANT_BODY})
    check("E `--env` reads the body from the environment (the injection-safe CI route)",
          proc.returncode == 0, proc.stdout[-300:])
    proc = run_cli(["--env", "COORD_PR_BODY"])
    check("E ...and an UNSET variable is a FAULT (exit 2), never an empty body (exit 1)",
          proc.returncode == 2 and "not set" in proc.stderr, (proc.returncode, proc.stderr[:200]))

    # ⛔ ONE VERDICT WHICHEVER ROUTE CARRIED THE BODY (card#10815 r1 review, m1). `review-prep.py`
    # calls `findings()` on the API body directly, never through `read_body`; CI runs `--env`. A
    # newline fold done only in the body read gave a lone-CR body two answers — clean under
    # `--env`, `built-missing` from the direct call — so the fold belongs to the parse.
    lone_cr = ("**Coordinated in:** card#1\rBuilt: inline (trivial)\rOrigin: bug-fix card#1\r"
               "\rSummary here.\r")
    proc = run_cli(["--env", "COORD_PR_BODY", "--title", "fix: x", "--json"],
                   env={"COORD_PR_BODY": lone_cr})
    try:
        via_env = sorted(f["rule"] for f in json.loads(proc.stdout)["findings"])
    except ValueError:
        via_env = None
    direct = sorted(f.rule for f in mod_main.findings(lone_cr, None, "fix: x"))
    check("E CONTROL: a lone-CR body gets the SAME verdict through `--env` and through a direct "
          "`findings()` call (the review digest's route)",
          via_env is not None and via_env == direct,
          "--env rc %d %r; direct %r" % (proc.returncode, via_env, direct))

    proc = run_cli([])
    check("E no source is a usage fault, not a pass", proc.returncode != 0, proc.returncode)

    # ⛔ A CRASH IS A FAULT (exit 2), NEVER A FINDING (exit 1) — card#12387 item 1. A CI step that
    # tells "the body is wrong" from "the lint could not judge it" reads the exit status, and a
    # traceback that exits 1 reads as a body the author must fix. The crash is planted in a copy,
    # past the input reads, so the exception is one no handler in `main` anticipates.
    crashing = mutant_path(td, "planted-crash",
                           ("    found = findings(body, author_type, title, release_headings)\n",
                            "    found = None.planted_crash\n"))
    for extra in ([], ["--json"]):
        proc = run_cli(["--body-file", body_path] + extra, tool=crashing)
        check("E an unhandled exception exits 2 — a fault, not a finding — and the traceback names "
              "it on stderr, with no verdict on stdout (%s)" % (" ".join(extra) or "text output"),
              proc.returncode == 2 and "planted_crash" in proc.stderr
              and "Traceback" in proc.stderr and "meet" not in proc.stdout,
              (proc.returncode, proc.stdout[-300:], proc.stderr[-400:]))


def _finding_ids(path, source):
    """(rule ids, unreadable sites) from `source`'s `Finding(...)` calls — the SAME rule as
    `_reconciled.lint_rule_population`, which this file cannot import once vendored: a `Finding`
    with no argument, or whose id is not a string literal, is a site the derivation cannot read,
    never one it may skip (fw#955 r2/r3 MAJOR 2 — skipping it here kept this arm green while the
    mechanism could not derive the population at all)."""
    ids, unreadable = set(), []
    for node in ast.walk(ast.parse(source, filename=path)):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                and node.func.id == "Finding"):
            continue
        first = node.args[0] if node.args else None
        if isinstance(first, ast.Constant) and isinstance(first.value, str):
            ids.add(first.value)
        else:
            unreadable.append("%s:%d" % (path, node.lineno))
    return ids, unreadable


def arm_l_version_classification(mod, td):
    """⛔ EVERY RULE THIS FILE CAN EMIT CARRIES A VERSION CLASSIFICATION, OR THE SUITE REDS
    (card#9748).

    WHY IT IS A SUITE LEG AND NOT A COMMENT. A reviewer runs this program out of ITS OWN plugin
    root against a PR in a repo that may have reconciled at a DIFFERENT coord version.
    `hooks/bin/_reconciled.py` withholds a finding that would be false across that boundary — and
    it can only do that for a rule whose `VERSION_CLASSIFICATION` row says what the change did.
    A rule with no row, or a `Finding` whose id the derivation cannot read, makes every skewed
    review's reconciled version NOT ESTABLISHED (exit 3) and arbitrates nothing. That has to red
    HERE, in the author's own suite, not there.

    THE POPULATION IS DERIVED FROM THIS FILE'S OWN `Finding("<id>", …)` SITES by `_finding_ids`,
    under the run-time derivation's rule. A rule id written down in a list here would be a third copy.
    """
    with open(TOOL, encoding="utf-8") as fh:
        emitted, unreadable = _finding_ids(TOOL, fh.read())
    check("every `Finding(...)` site names its rule as a string literal the derivation can read",
          not unreadable, "unreadable: %s" % ", ".join(unreadable))
    check("the rule population derives non-empty from this file's own `Finding` sites",
          bool(emitted), "an empty population would report every rule as classified")
    declared = set(mod.VERSION_CLASSIFICATION)
    check("every rule this file can emit has a VERSION_CLASSIFICATION row",
          emitted <= declared, "unclassified: %s" % ", ".join(sorted(emitted - declared)))
    check("VERSION_CLASSIFICATION names no rule this file cannot emit",
          declared <= emitted, "stale row(s): %s" % ", ".join(sorted(declared - emitted)))
    for rule, entry in sorted(mod.VERSION_CLASSIFICATION.items()):
        check("`%s` declares a direction this mechanism understands" % rule,
              entry.get("direction") in ("one-directional", "hard-flip"),
              "direction=%r" % entry.get("direction"))
        check("`%s` declares case 1 or case 2" % rule, entry.get("case") in (1, 2),
              "case=%r" % entry.get("case"))
        if entry.get("direction") == "hard-flip":
            check("`%s` is a HARD FLIP and names the version it landed in" % rule,
                  bool(entry.get("since")),
                  "without `since` nothing can say which side of the flip a repo sits on")

    # ⭐ THE CONTROLS. Neither failing input is constructible from the shipped file, so each is
    # constructed: a COPY with one extra rule and no row, and a COPY whose extra rule's id is a
    # name rather than a literal. Each must red its check above.
    with open(TOOL, encoding="utf-8") as fh:
        source = fh.read()
    for label, planted_call in (
            ("a planted rule with no VERSION_CLASSIFICATION row", '"planted-unclassified-rule"'),
            ("a planted rule whose id is not a string literal", "PLANTED_RULE_ID")):
        planted_ids, planted_bad = _finding_ids("planted", source.replace(
            "def findings(body",
            'def _rule_planted(rows):\n'
            '    return [Finding(%s, 1, "", "planted")]\n\n\n'
            "def findings(body" % planted_call, 1))
        caught = (planted_ids - declared) if planted_call.startswith('"') else planted_bad
        if check("CONTROL: %s is SEEN" % label, bool(caught),
                 "the derivation did not see the planted `Finding` site, so the check above "
                 "cannot red on the state it exists to catch"):
            seen_red("%s -> %s" % (label, ", ".join(sorted(caught))))


# ══════════════════════════════════════════════════════════════════════════════════════════════
# K — A VENDORED COPY OF THIS SUITE RUNS, AND NAMES A WORKFLOW IT CANNOT FIND (card#10719)
# ══════════════════════════════════════════════════════════════════════════════════════════════
# The defect this arm holds shut was in the LAYOUT, not in a rule: a repo that copies the lint and
# this file into its own `bin/` has no `../workflows/` beside it, and step (9) of arm i used to
# raise there — so arms j and e never ran and that repo's CI redded on every PR. Only a copy in
# that layout can show it, so this arm builds one (lint, this file, its fixtures, and a workflow
# under `.github/workflows/` with a name of its own) and runs it twice, reading what the copy
# PRINTS, not only its exit code.
def _vendored_run(vend, args, env_over):
    env = dict(os.environ)
    env.pop(WORKFLOW_ENV, None)
    env[NESTED_ENV] = "1"
    env.update(env_over)
    return subprocess.run([sys.executable, os.path.join(vend, "bin", os.path.basename(__file__))]
                          + args, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", timeout=300, env=env, cwd=vend)


def arm_k_vendored(td):
    arm_k_resolution()
    vend = os.path.join(td, "vendored")
    os.makedirs(os.path.join(vend, "bin"))
    os.makedirs(os.path.join(vend, ".github", "workflows"))
    shutil.copy(TOOL, os.path.join(vend, "bin"))
    shutil.copy(os.path.abspath(__file__), os.path.join(vend, "bin"))
    shutil.copytree(FIXTURE_DIR, os.path.join(vend, "bin", os.path.basename(FIXTURE_DIR)))
    missing = os.path.join(vend, "bin", "..", "workflows", "pr-body-lint.yml")

    # (1) No input: the plugin-layout default names a file this layout does not have.
    proc = _vendored_run(vend, [], {})
    out = proc.stdout + proc.stderr
    check("K a vendored copy given no workflow does not crash — no traceback", "Traceback" not in out,
          out[-600:])
    check("K ...every arm after i still runs and reports (j and e included)",
          re.search(r"^pr-body-lint\.selftest: arms run: a b c d f g h i j l m n o e$", proc.stdout, re.M)
          is not None, proc.stdout[-600:])
    check("K ...and the result is a FAILURE of arm i that names the path it tried and both ways to "
          "point it elsewhere — never a pass, never a skip",
          proc.returncode == 1 and "pr-body-lint.selftest: FAIL" in proc.stdout
          and "I the workflow that runs the lint could be read" in proc.stdout
          and repr(missing) in proc.stdout and "--workflow PATH" in proc.stdout
          and WORKFLOW_ENV + "=PATH" in proc.stdout,
          (proc.returncode, proc.stdout[-800:]))
    check("K ...and it is the ONLY failure — the rest of the vendored suite is green",
          len(re.findall(r"^  - ", proc.stdout, re.M)) == 1, proc.stdout[-800:])

    # (2) `--workflow` names the vendored workflow, and wins over a variable naming a file that is
    # not there: the same copy passes. The workflow copied in is the one THIS run was pointed at —
    # an adopter's own vendored run has no plugin layout to copy from.
    real_wf = os.path.join(vend, ".github", "workflows", "pr-floor.yml")
    try:
        shutil.copy(WORKFLOW, real_wf)
    except OSError as exc:
        check("K a vendored copy pointed at a real workflow passes", False,
              "no workflow to copy in: %r (from %s): %s — arm i names the same path"
              % (WORKFLOW, WORKFLOW_SOURCE, exc.strerror or exc))
        return
    proc = _vendored_run(vend, ["--workflow", real_wf],
                         {WORKFLOW_ENV: os.path.join(vend, "no-such.yml")})
    check("K `--workflow` pointing at the vendored workflow passes the whole copy, and wins over "
          "the variable", proc.returncode == 0 and "pr-body-lint.selftest: ok" in proc.stdout,
          (proc.returncode, proc.stdout[-800:]))


def arm_k_resolution():
    # The precedence, in-process — `arm_k` drives the argument and the failure end to end; the
    # variable alone is decided here.
    check("K the variable alone names the workflow",
          resolve_workflow(None, {WORKFLOW_ENV: "/x.yml"}) == ("/x.yml", WORKFLOW_ENV))
    check("K `--workflow` wins over the variable",
          resolve_workflow("/a.yml", {WORKFLOW_ENV: "/x.yml"}) == ("/a.yml", "--workflow"))
    check("K neither is the plugin's own layout",
          resolve_workflow(None, {})[0] == DEFAULT_WORKFLOW)


def main(argv=None):
    global mod_main, WORKFLOW, WORKFLOW_SOURCE, EMPTY_CWD
    ap = argparse.ArgumentParser(description="The PR-body lint's own controls.", allow_abbrev=False)
    ap.add_argument("--workflow", metavar="PATH",
                    help="the workflow that runs the lint (default: this plugin's "
                         "templates/workflows/pr-body-lint.yml; env %s)" % WORKFLOW_ENV)
    a = ap.parse_args(argv)
    WORKFLOW, WORKFLOW_SOURCE = resolve_workflow(a.workflow, os.environ)
    nested = os.environ.get(NESTED_ENV) == "1"
    before = sha256_file(TOOL)
    mod_main = load_tool()
    ran = []
    with tempfile.TemporaryDirectory() as td:
        EMPTY_CWD = os.path.join(td, "empty-cwd")
        os.makedirs(EMPTY_CWD)
        for letter, run in (("a", lambda: arm_a_the_controls(mod_main)),
                            ("b", lambda: arm_b_each_rule(mod_main)),
                            ("c", lambda: arm_c_fences(mod_main, td)),
                            ("d", lambda: arm_d_mutants(td)),
                            ("f", lambda: arm_f_attribution(mod_main, td)),
                            ("g", lambda: arm_g_live_state(mod_main, td)),
                            ("h", lambda: arm_h_bot_author(mod_main, td)),
                            ("i", lambda: arm_i_release_scope(mod_main, td)),
                            ("j", lambda: arm_j_ai_attribution(mod_main, td)),
                            ("l", lambda: arm_l_version_classification(mod_main, td)),
                            ("m", lambda: arm_m_provenance(mod_main, td)),
                            ("n", lambda: arm_n_repo_release_headings(td)),
                            ("o", lambda: arm_o_merge_instruction(mod_main, td)),
                            ("e", lambda: arm_e_cli(td)),
                            # A copy `arm_k` runs does not run arm k again; the list printed below
                            # is what says so.
                            ("k", None if nested else lambda: arm_k_vendored(td))):
            if run is not None:
                run()
                ran.append(letter)
    print("pr-body-lint.selftest: arms run: %s" % " ".join(ran))
    after = sha256_file(TOOL)
    check("the shipped file was not touched by this suite (sha256 before == after)",
          before == after, "%s -> %s" % (before, after))

    for line in SEEN_RED:
        print("    seen red: %s" % line)
    if FAILURES:
        print("pr-body-lint.selftest: FAIL")
        for f in FAILURES:
            print("  - %s" % f)
        return 1
    print("pr-body-lint.selftest: ok (%d checks; %d controls SEEN RED before their green was "
          "believed)" % (CHECKS, len(SEEN_RED)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
