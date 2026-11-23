#!/usr/bin/env python3
r"""pr-body-lint.py — the PR-body standard, ENFORCED instead of described (card#9073 leg B).

THE MEASURED DEFECT. `skills/release-pr/SKILL.md § PR body — write it for the software installer`
is the standard for what a PR body may contain — its release-only rules on a RELEASE PR only
(the ⛔ RELEASE-SCOPE block below names them and owns that split) — it is ratified twice by the
operator (the second time on 2026-09-09, naming the READER), and until this file NOTHING
CHECKED IT.
`review-prep.py` and the wrappers around it checked field PRESENCE — `Built:`,
`**Coordinated in:**` — never the ABSENCE of narration, so a body could carry every required
machine line and still be the essay the standard forbids. It did, repeatedly:

    "The PR for v0.50.0 doesn't meet my criteria. It is full of commentary again instead of
     what someone installing the package needs to know. For example, Why MINOR (0.49.0 →
     0.50.0) section and Correlation gaps"              — operator, 2026-09-08, card#9073

That body is this program's KNOWN POSITIVE: `PupFuzz/agent-board-framework` #847 as it stood at
2026-09-08T22:02:29Z (recoverable from the PR's `userContentEdits`; the live body at #847 has
since been rewritten to the standard and PASSES, which is the negative control). It reds on two
of the rules below and the operator's two named examples are exactly those two rows.

WHAT IT CHECKS, AND WHERE EACH RULE COMES FROM. The rules are the STANDARD'S, not this file's —
`§ PR body`'s IN/OUT tables own every one of them and this program deliberately does not restate
their reasoning (canon #16: point, do not copy). What lives here is the executable form:

    scope-line          the IN table's `Scope line` row — one line, FIRST, naming the range.
    heading-not-allowed the IN table, read as a closed set — `ALLOWED_H2` below is its
                        executable form and the section's own `pr-body-lint:allowed-h2` marker
                        block is what a drift check holds the two equal against, so neither this
                        paragraph nor any other prose restates the set. Any H2 outside it is a
                        section the standard gives a home OUTSIDE the body, so it reds here —
                        unless the adopting repo DECLARES it, by its exact text, in
                        `.github/pr-body-lint-release-headings.txt` (card#12387; the comment at
                        `RELEASE_HEADINGS_FILE` owns why and how).
    banned-opener       the OUT table, read as the phrases those homes actually begin with.
                        `BANNED_OPENERS` below is the set, held equal to the section's
                        `pr-body-lint:banned-openers` marker block by the same drift check — so
                        this paragraph names the rule and not its membership, for the reason the
                        row above gives: a prose list here is a copy nothing guards.
    built-missing       the IN table's machine-read row + the coord plugin's
                        `docs/built-line.md`. A BOT-AUTHORED PR is exempt from this row, the
                        next, `origin-missing` and `design-approved-missing`, and from nothing
                        else — the ⛔ block below owns that exemption and its discriminator.
    coordinated-missing the IN table's machine-read row.
    origin-missing, origin-malformed, design-approved-missing, design-approved-malformed,
    tier-malformed
                        the IN table's machine-read row, for the provenance lines (card#11037,
                        operator-directed): `Origin:` on every PR, `Design-approved:` beside an
                        `agent-originated` origin, and `Origin:` / `Design-approved:` / `Tier:`
                        well-formed where present. `declarations()` is the ONE reader of them; the
                        merge gate (`design_gate.py`) calls it too. A bot-authored PR is exempt
                        from `origin-missing` and `design-approved-missing` only.
    attribution-line    the OUT table's `FROM:` / `TO:` row — a PR body carries NO attribution
                        line, on ANY repo (see below).
    ai-attribution      the OUT table's AI-attribution row — no line names the AI model, carries
                        a Claude session link or co-author trailer, or carries the context stamp
                        (operator-directed, card#10673). `AI_ATTRIBUTION_SHAPES` is the closed
                        shape table, a vendored region shared with `squash-message.sh`, and its
                        names are held equal to the section's `pr-body-lint:ai-attribution`
                        marker block by the same drift check.
    live-state-reading  the OUT table's `Readings` row, for the part of it a program can decide:
                        a CLOSED table of claim shapes about LIVE CI / push / base state
                        (`LIVE_STATE_READINGS` below, held equal to the section's
                        `pr-body-lint:live-state-readings` marker block by the same drift check).
    merge-instruction   § PR body's merge-method note, on a RELEASE PR: a CLOSED table of line
                        shapes that tell the merger how to merge, who merges, or what to do by hand
                        after the merge (`MERGE_INSTRUCTIONS` below, held equal to the section's
                        `pr-body-lint:merge-instructions` marker block by the same drift check).
                        The generated `## Bundled` section is not judged (card#13034).

⛔ `attribution-line` IS OPERATOR-DIRECTED AND IT IS THE ONE RULE HERE THAT REFUSES A LINE THE
STANDARD USED TO REQUIRE. A PR body carries no `FROM:` / `TO:` attribution line, on any repo
(operator, 2026-09-11, card#9229 → card#9073 leg E). Those lines are the COORDINATION channel's —
an issue body and a comment still carry them, unchanged, and the coord plugin's
`docs/protocol-spec.md` § Addressing owns the rule for all three surfaces. A PR is attributed by
the ROSTER'S REPO BINDING instead (the coordination repo → pm; an impl repo → the seat whose roster
entry owns it), which is what `templates/bin/handoff-check.py`'s `attribute_pr` now reads and what
the coordination repo's protocol-integrity Action now enforces on `pull_request_target`. The pair
that discriminates this rule is one PR again: fw#891's body as it stood at `2026-09-10T14:08:53Z`
(it opened on `FROM: pm`) against the same body after the operator's ruling.

⛔ A BOT-AUTHORED PR IS EXEMPT FROM THE TWO AUDIT ROWS — AND FROM `origin-missing` AND
`design-approved-missing`, FOR THE SAME REASON (card#11037) — AND FROM NOTHING ELSE (card#9927). A
dependency bot opens a PR with no dispatch behind it and no coordination thread to anchor to, so
it can declare neither `Built:` nor `**Coordinated in:**` TRUTHFULLY — and on an adopter that
gates self-merge on this workflow, that red is what stops a SECURITY BUMP from landing until a
person hand-edits the bot's body. That is a MEASUREMENT, twice: an adopter seat reported it on its
own live Dependabot PR (card#9927), and it re-derives here on this repo's own — `gh api
repos/PupFuzz/agent-board-framework/pulls/426 --jq .body` into `--body-file` gives rc 1 on exactly
`built-missing` + `coordinated-missing` and nothing else (and, since card#11037, `origin-missing`),
and rc 0 with `--author-type-env` naming a variable set to `Bot`. No fixture is committed for it because, unlike the pairs above, the pair
that discriminates here is not two BODIES: it is one body under two author types, which is what
`pr-body-lint.selftest.py`'s `arm_h` drives. The exemption lives HERE, in the one
program, rather than as an `if:` on the workflow job — an adopter's vendored copy is
byte-identical and needs no local fork, and the review path (`review-prep.py`) reads the same
rule rather than a second one.

THE DISCRIMINATOR IS THE EVENT'S `user.type`, NEVER AN AUTHOR LOGIN — `author_is_bot` below is
the whole of it. GitHub sets that field from the ACCOUNT KIND and the PR's author cannot choose
it; a login is a string that enumerates one bot at a time, and is already known to arrive in more
than one spelling for a SINGLE bot (`dependabot[bot]` on the REST / webhook payload,
`app/dependabot` as `gh`'s projection renders it — `templates/kanban/examples/kanban-prs-sync.py`'s
`_is_bot` carries that measurement and the double-carding defect it caused). Type covers
Dependabot, Renovate and every other GitHub App at once, with nothing enumerated and nothing to
add when an adopter installs a bot this repo has never heard of. The coordination-repo skeleton's
`.github/scripts/protocol-integrity.js` decided the SAME question the same way
(`commentSkipReason`, "this predicate never reads the author LOGIN — type is the discriminator"),
and it states the fleet fact that makes the exemption safe here too: agents post through a SHARED
PAT and come back `user.type: "User"`, so no agent-authored PR is exempted by this.

AND IT FAILS CLOSED, WHICH IS THE ONLY DIRECTION AVAILABLE TO A PROVENANCE CHECK. Nothing but the
exact string `Bot` is a bot: no author at all (a `--body-file` run from a terminal, and every
caller that passes none — `review-prep.py` is one), a variable that is unset, an empty or
whitespace value, any other account type, any other casing. An exemption that fired when it could
not PROVE the author is a bot would let any body shed its audit rows by naming a variable the
lint cannot read. The residue is therefore deliberate and is not a degradation to hide: a
workflow that does not pass the field gets TODAY's behaviour — both rows required — which is a
red the author can see, never a silent pass.

⛔ THE RELEASE STANDARD JUDGES RELEASE PRs, AND ONLY THEM (card#10493). `ALLOWED_H2`'s members are
RELEASE nouns — `Bundled` and `Release artifacts` mean nothing on a feature PR — so while every
rule ran on every body, a feature PR failed this lint BY CONSTRUCTION. Measured: the
`BWtek-Medical/sola-device` feature PRs card#10493 lists each spent a review finding on
`heading-not-allowed` for `## Summary` / `## SaMD boundary check` / `## CI action-pin resync
check`, headings that repo's own PR template and shape guard REQUIRE. A non-release PR's section
shape is its repo's to define, so only the rules that model that SHAPE are scoped:
  * RELEASE ONLY — `scope-line` and `heading-not-allowed`. They are § PR body's IN table read as a
    CLOSED set of release sections opened by a release range line, and nothing else here models a
    section shape.
  * RELEASE ONLY TOO — `merge-instruction` (card#13034), for a different reason: it is § PR body's
    merge-method note, which names the release case, and every instance measured was a release
    body (AIMLA-org/platform#467, PupFuzz/kanban-board#592). A feature PR in this fleet is often
    ABOUT merge tooling, so its body names merge methods as its subject; the rule was scoped to the
    release PR on that ground.
  * EVERY PR — everything else. `banned-opener` and `live-state-reading` are § PR body's OUT table,
    and the OUT table's relocations (narration, the audit trail, findings and readings go to the
    review-request round) bind every PR body whatever its section shape — § PR body says so, and
    `live-state-reading` was minted on fw#873, a feature PR. `built-missing` and
    `coordinated-missing` (the coord plugin's `docs/built-line.md` requires `Built:` on every PR
    body, and plane 1 of its `docs/pr-review-flow.md` reads `**Coordinated in:**` off every PR),
    and `attribution-line` (its `docs/protocol-spec.md` § Addressing: no `FROM:` / `TO:` on a PR
    body, on any repo — operator-directed), `ai-attribution` (its `docs/engineering-canon.md`'s
    standing instruction — operator-directed) and the provenance rows (its `docs/USER-GATING.md`
    § 2g — operator-directed, card#11037) have fleet-wide owners of their own.
The ALLOW-SET IS NOT WIDENED to admit a feature PR's headings: that would keep a closed set of
release nouns and silence the findings about a different document (canon #3).

THE DISCRIMINATOR IS THE PR TITLE'S `release:` PREFIX — `judged_as_release` below is the whole of
it. It is the one mark the release flow ALREADY puts on every release PR (`release-pr` SKILL.md's
checklist, criterion 5: `release: vX.Y.Z`), and it needs NO CONFIGURATION to read: the
`pull_request` event carries it into CI, `review-prep` has it on the PR it already reads, and an
author about to run `gh pr create --title` has it in hand. The BASE BRANCH was the alternative and
was ruled out on exactly that: which bases are release branches is per-install config
(`branch_model.release`, plus every `branch_model.lines` entry's `release`, which only
`templates/bin/branch-lines.sh` resolves), and this file runs in an adopter's CI with no
coordination config beside it — so it would have to guess `main`, and would judge a declared
line's release PR as a feature PR.

AND A MISSING TITLE IS A RELEASE PR, WHICH IS THE STRICT SIDE. No title at all — a terminal
`--body-file` run, an old copy of the workflow that does not pass one, a caller that names an unset
variable — cannot prove the PR is not a release, so the body gets the full standard, which is
exactly what every body got before this split. The run SAYS so, so a feature author who forgot
`--title` sees why their `## Summary` reds. The RESIDUE, named rather than hidden: a release PR
whose title does not open `release:` is judged as a feature PR and escapes the section rules. The
title is itself a release checklist item, visible on the PR page, so the miss is a checklist
finding as well as a lint one.

⛔ IT IS ONE PROGRAM WITH SEVERAL CONSUMERS AND THAT IS WHY IT IS SHAPED THIS WAY. It runs (1) in
the CI of every repo that has adopted `templates/workflows/pr-body-lint.yml`, on `pull_request` opened / edited
/ synchronize, and as the same command in `coord-preflight`; (2) inside the review path, where
`hooks/bin/review-prep.py` loads it as a module and transports its answer into the digest
`coord-review prepare` builds — the same delegation, for the same reason, that `review-prep`
already applies to `ci-read`; and (3) in `coord-post`'s PR-body pre-flight, through
`coord_protocol.pr_body_findings`. A second implementation of one verdict is the divergence canon
#5 forbids, and it would be the divergence that matters here (two answers to "does this body meet
the standard", one of them green). ONE INPUT BESIDES THE BODY AND TITLE CAN MOVE THE VERDICT: the
repo's declared release headings (`RELEASE_HEADINGS_FILE`). Consumers (1) and (2) both read that
file and both parse it with `parse_release_headings`; `findings()`'s docstring names what each
caller passes for it.

⛔ SO IT IS A SINGLE SELF-CONTAINED FILE, IMPORTING NOTHING BUT THE STDLIB, AND THE FENCE TRACKER
IS A VENDORED REGION RATHER THAN AN IMPORT. `templates/bin/handoff-check.py` joined the same
`fence-mask` group for the identical reason and its registry entry states it: a file that deploys
as ONE file — to `~/.local/bin`, and into an adopting repo's `bin/` for CI — has no sibling to
import. `hooks/bin/_fence.py` is the review family's adapter over the SAME fragment and the two
cannot drift: `tools/gen-vendored.py --check` runs in CI and asserts this region byte-for-byte
against `plugins/coord/_vendor/fence-mask.py.txt`.

⛔ AND THE FENCE RULE IS NOT A NICETY HERE — IT IS WHAT KEEPS THIS PROGRAM FROM MANUFACTURING
FINDINGS. A PR body that DOCUMENTS the standard in a fenced example is ordinary in this repo,
whose PRs are largely about the lines this file reads; a heading or a banned opener QUOTED inside
a fence is payload, not the body's own claim. Reading them as the body's would produce a FAIL
against a body that is RIGHT, and a false accusation is worse than no check at all — that is
`_audit_field`'s own measured lesson (card#9047 r2), one layer up. Every rule below runs over the
fence-aware line scan and never over the raw text.

⛔ AN HTML COMMENT IS MASKED THE SAME WAY, FOR THE RULES ABOUT WHAT A READER SEES (card#12387). A
PR template's `<!-- … -->` guidance is not rendered, so its lines are not the body's: read as
content, a template comment reding on `banned-opener` was a false accusation the author could only
clear by deleting the template's guidance. `scan(body, html_comments=True)` has the fence tracker
itself (`fenced_flags`, the `fence-mask` region above) mark a comment block's lines in the scan's
fenced column, so `scope-line`, `heading-not-allowed`, `banned-opener` and `live-state-reading`
skip them as they skip a fenced line. `attribution-line` and `ai-attribution`
still read them: those rules judge what the body CARRIES, and a comment's text lands in the squash
message — the context stamp is itself a comment. The machine-read rows (`Built:`, `Origin:` and the
rest) are read by `field_values`, which only the fence masks, unchanged here: `declarations()` is
also the merge gate's reader, and the two must not disagree.

⛔ WHAT IT REFUSES TO JUDGE, STATED SO A GREEN RUN IS NOT OVER-READ.
  * **H3 and below are not checked.** The allowlist is the IN table's SECTION set, and the
    standard admits sub-structure inside `## Highlights` (the shipped generator emits it). A
    narrating `###` therefore passes here and is a HUMAN finding at review. Narrowed on purpose:
    a rule that cannot be stated from the IN table is one this file would be inventing.
  * **Everything after an UNCLOSED fence is invisible to every rule here.** CommonMark runs an
    unclosed ``` ``` ``` to end of document, so the fence tracker below marks the whole remainder
    as payload and a body that opens a fence and never closes it PASSES on whatever follows —
    measured, not reasoned: a compliant preamble, an unclosed fence, then `## Correlation gaps`
    and `### Why MINOR` → rc 0, zero findings. That is the renderer's own reading (the reader
    sees that text as a code block too), so it is not a bug in the tracker; it is an escape hatch,
    and a green over such a body is a statement about a document that ends inside a fence rather
    than about the body's sections. Named here because this block exists to stop exactly that
    over-read. (An unclosed fence ABOVE the audit rows reds on three rules instead — only the
    SUFFIX case is silent.) **An unclosed HTML comment does the same** to every rule the
    comment mask reaches — CommonMark runs it to end of document too, and the renderer hides it.
  * **An HTML comment that does not open its line is not masked.** `text <!-- … --> text` is
    judged as written: only a comment BLOCK (`<!--` first on the line) is masked, and a whole line
    at a time — so text after a block's `-->` on its closing line is masked with it, and goes
    unjudged although a reader sees it.
  * **It never judges whether a line is TRUE** — only whether the body is in the shape the
    standard describes. Whether a `Built:` count matches what happened is plane 1's, on the
    body's edit history (`pr-review-flow.md`). `live-state-reading` is no exception: it reds on a
    reading whether or not the reading holds at the head, because the standard homes every
    reading outside the body — the comment above `LIVE_STATE_READINGS` owns why it refuses the
    shape rather than comparing the claim with the head.
  * **`live-state-reading` judges its CLOSED shape table and nothing else.** A CI / push / base
    claim in words no shape matches PASSES here, so a green says only that no line matched one
    of those shapes. Named residues, each pinned by a driven row in the selftest: a base other
    than `dev` or `main` (`3 commits behind release`) is NOT judged — pm ruling on card#9073 leg
    B-2, and the table is not to be widened with a pattern; markdown emphasis BETWEEN a shape's
    words (`CI is **green** at <sha>`) is not judged, because no decoration is stripped inside a
    line; a reading split across table cells is not judged, because no shape crosses a `|`. And,
    from the narrowings fw#910 r1 forced so that pass conditions and descriptions of a tool stop
    reding: a reading whose opening token follows a word (`Note CI is green at <sha>`) is not
    judged, because every shape but `behind-base` must open its clause; a sha of decimal digits
    alone is not judged, because a sha must carry a hex letter; a ZERO count is not judged, because
    a pass condition and a reading share that shape (`a pass is 0 commits behind dev`, and fw#627's
    real reading `0 commits behind origin/dev (bcdc12bb)`), so the rule withholds both. Named
    FALSE REDS, each pinned RED by a driven row in the selftest's `LIVE_KNOWN_FALSE_REDS`:
    `behind-base` does not open its clause, so a description of a tool with a NON-ZERO count in
    `<n> commits behind|ahead of <base>` (`refuses when the branch is 5 commits behind dev`, `warns
    when the branch is 3 commits ahead of main`) reds — no shape separates it from a reading, which
    also puts a word before the count (`The branch is 2 commits behind`). Reworded without
    `<n> commits behind|ahead of <base>`, the description passes.
  * **`merge-instruction` judges its CLOSED shape table, on a release PR, outside `## Bundled`,
    and nothing else.** A merge instruction in words no shape matches PASSES, and so does one
    whose opening token follows a word (`please merge with a merge commit`), because every shape
    but `is the merger` opens its clause; a line hand-added under the generated `## Bundled`
    heading is not judged at all. Each is pinned by a driven row in the selftest's arm O.

⚠ WHAT IT ECHOES. A finding PRINTS THE OFFENDING LINE (clipped to `LINE_CLIP` characters), never
a tally — a count of findings is a figure that is false on the next edit and tells the author
nothing about which line to fix (canon #16). The line is the PR body's own text, which is already
displayed to everyone who can read the PR; the CI log this program writes to is readable at the
same access level, so echoing it moves no value across a boundary. It is not a secret-bearing
surface and this program does not read one: it reads a body, from a file or an environment
variable the caller names, and the repo's declared release headings
(`.github/pr-body-lint-release-headings.txt` under the directory it runs in, when that file
exists), and nothing else.

Exit codes: 0 = the body meets the standard | 1 = at least one finding | 2 = a fault: usage,
input, or a crash — no verdict was reached (the `__main__` block owns the crash floor).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import traceback

# VENDOR-BEGIN(stdio-encoding)
# GENERATED — do not edit; source: plugins/coord/_vendor/stdio-encoding.py.txt; regenerate (framework repo only): python3 tools/gen-vendored.py; fragment-sha256: 9107d70a8af83298
# jscpd:ignore-start
def pin_std_streams():
    """Pin this program's stdout and stderr so no character it writes can KILL the write.

    THE DEFECT THIS ENDS. Python's text streams encode with the `strict` error handler, and
    outside a UTF-8 locale their codec is the platform's — `cp1252` on the fleet's Windows
    seat, for a redirected stream as well as for an old console. The first character that
    codec cannot represent raises `UnicodeEncodeError` *inside* the write, so the process
    dies with a traceback and the stream it was writing to is left EMPTY. Measured on the
    tool whose whole subject is refusing empty answers: `git-object-id --help` under
    `PYTHONIOENCODING=cp1252` exits 1 with ZERO BYTES on stdout, because the contract it
    prints contains one `⛔`. A reader who asks a tool what it promises, and is handed
    nothing, reads that as "the tool has nothing to say" — the wrong-population zero,
    produced by the help path of the tool written to forbid it.

    THREE PROPERTIES, AND EACH IS LOAD-BEARING ON ITS OWN.
      * `encoding="utf-8"` — the tooling's text IS UTF-8 (arrows, em-dashes, box drawing,
        accented names come out of coordination data, not out of decoration), so the stream
        is pinned to the codec that can carry all of it rather than left on whatever the
        machine's locale happens to be. This is also what makes a redirected stream a FILE
        of known bytes instead of a file whose encoding depends on which seat produced it.
      * `errors="backslashreplace"` — the residue after that pin. UTF-8 still cannot encode
        a LONE SURROGATE, which is exactly what an undecodable byte in a filename becomes
        once it has been through the filesystem's `surrogateescape` decode, so a program
        that prints a path it did not choose can still meet a character its stream refuses.
        The handler makes that one character print as `\\udcXX` and lets the rest of the
        line through. THE DIRECTION IS THE POINT: an unprintable character must cost its own
        glyph, never the whole message.
      * `newline="\\n"` — Windows opens a text stream in TEXT MODE and translates every
        `\\n` written into `\\r\\n`. Any consumer that captures this program's stdout and
        compares, splits or evaluates a field then compares a value with a carriage return
        welded onto it, and the mismatch names nothing. Pinning at the PRODUCER is what lets
        a reader rely on it, rather than every reader stripping `\\r` for itself.

    WHY THE ERROR HANDLER IS NOT LEFT STRICT once the encoding is pinned: `strict` is the
    setting that turns an unrepresentable character into NO OUTPUT AT ALL. There is no
    caller anywhere for whom that is the better answer — a diagnostic that cannot be printed
    is not a diagnostic — and the two settings are independent, so pinning one and leaving
    the other is how the crash survives a fix aimed at it. Note that `reconfigure(encoding=)`
    RESETS the handler to `strict` when `errors=` is omitted (measured, CPython 3.14), which
    is why the two travel together in one call and never in two — and why NOTHING LATER IN A
    HOST MAY CALL `reconfigure(encoding=…)` AGAIN. A second such call, however well meant,
    silently undoes this one on both streams and leaves the program back at the setting that
    prints nothing; the framework repo's population guard reds on it two ways, statically and
    by reading the handler the program leaves installed at runtime.

    STDIN IS DELIBERATELY NOT TOUCHED. This is an ENCODE failure — a property of what the
    program writes — and stdin's decode is a different question with a different right
    answer per program: a reader that must not corrupt bytes reads `sys.stdin.buffer` and
    decodes explicitly, and pinning the text layer underneath it would say something about a
    stream that program never uses.

    A STREAM THAT CANNOT BE RECONFIGURED IS LEFT ALONE, and that is the whole of the failure
    handling. `reconfigure` exists on a real `TextIOWrapper`; a stream replaced by a test
    harness, or absent entirely, has neither the method nor the defect. There is no second
    attempt with fewer arguments, because no stream accepts one of these keywords and
    refuses another — a fallback rung there would be code for a state that cannot arise, and
    it would hide the one case worth knowing about by making it look handled.
    """
    for _stream in (sys.stdout, sys.stderr):
        try:
            _stream.reconfigure(encoding="utf-8", errors="backslashreplace", newline="\n")
        except Exception:
            pass


# THE CALL IS SCOPED TO THE PROGRAM, and the scope is load-bearing. A host in this group can also
# be a LIBRARY — `coord_credentials.py` is imported by the `coord-gh` / `xproj-gh` / `impl-ro-gh`
# wrappers, by `git-credential-coord`, by `coord-credential-migrate.py`, by `hooks/bin/_ghcred.py`
# and by `templates/hooks/coord-merge-guard.py` — and an unconditional call re-pins the IMPORTER's
# streams as a side effect of the import. Measured: `coord-merge-guard.py` ended at
# `backslashreplace` when `coord_credentials.py` happened to sit in `~/.local/bin` and at `strict`
# when it did not, so a program's own stdout was a function of another file's install layout. A
# module choosing an encoding for a program that never asked is this file's own defect one level
# up — the caller's stream is the CALLER's to declare — and a pin that arrives only sometimes is
# worse than none, because nothing downstream can rely on either state. Every host here is
# executed directly, so this still fires for every PROGRAM run; what it no longer does is fire for
# a reader that only wanted a function.
if __name__ == "__main__":
    pin_std_streams()
# jscpd:ignore-end
# VENDOR-END(stdio-encoding)


# VENDOR-BEGIN(fence-mask)
# GENERATED — do not edit; source: plugins/coord/_vendor/fence-mask.py.txt; regenerate (framework repo only): python3 tools/gen-vendored.py; fragment-sha256: 261bd08478c8a48f
# jscpd:ignore-start
_FENCE_RE = re.compile(r'^ {0,3}(?P<f>`{3,}|~{3,})(?P<info>.*)$')
_HTML_COMMENT_OPEN_RE = re.compile(r'^ {0,3}<!--')


def fenced_flags(text, html_comments=False):
    """Per-line booleans over ``text.split("\\n")``: True when that line lies inside a fenced
    code block, the opening and closing fence lines INCLUDED (they are part of the example,
    not content).

    MARKDOWN STRUCTURE ONLY COUNTS OUTSIDE A FENCED CODE BLOCK. Inside a fence, a line that
    looks like a marker / a heading / a divider is an EXAMPLE OF one, quoted for a human — it
    is the thing being written ABOUT, not an instance of it. Every structural scanner that
    shipped without that distinction mis-parsed the same way, which is why this is ONE tracker
    every one of them consults rather than N local patches.

    THE GRAMMAR, stated here because this fragment is spliced whole into hosts that have no
    other description of it: CommonMark's fenced-code rules, minus what nothing here emits. An
    opening fence is >=3 backticks or tildes indented <=3 spaces (a backtick fence's info
    string may not itself contain a backtick); it closes on the first line with >= as many of
    the SAME character and nothing but whitespace after; an unclosed fence runs to end of
    document. Indented (4-space) code blocks are NOT tracked, and the PRECONDITION that makes
    that safe belongs to the caller, not to this: a scanner anchored at column 0 excludes an
    indented example BY ITS OWN ANCHOR. This sentence used to assert that as a fact about "the
    scanners that care", and a scanner that deliberately tolerates leading whitespace falsified
    it (`dispatch-grant.MARKERISH_RE`, which must still see a HAND-MANGLED marker and therefore
    cannot anchor at column 0). A caller that tolerates indentation reads an indented example as
    real and owns that remainder itself — as that one does, in writing, beside the pattern.

    `html_comments=True` ALSO flags every line of an HTML comment BLOCK — a caller's opt-in, for
    a caller that judges what a reader SEES (a comment's own text is not rendered). A block opens
    on a line whose first text, indented <=3 spaces, is `<!--`, and closes on the first line
    holding `-->`, the opening line included; unclosed, it runs to end of document. That is
    CommonMark's HTML-block rule for a comment. It is tracked in THIS loop, not a second pass,
    because the two blocks hide each other: a `<!--` inside a fence opens no comment, and a fence
    line inside a comment opens no fence. The flag is per LINE, so text after `-->` on the
    closing line is flagged with it although a reader DOES see that text — a known false pass
    for a caller judging what is seen — and a `<!--` that does not open its line flags nothing."""
    flags, fence_char, fence_len = [], None, 0
    in_comment = False
    for ln in text.split("\n"):
        if in_comment:
            flags.append(True)
            in_comment = "-->" not in ln
            continue
        if fence_char is None and html_comments and _HTML_COMMENT_OPEN_RE.match(ln):
            flags.append(True)
            in_comment = "-->" not in ln
            continue
        m = _FENCE_RE.match(ln)
        if fence_char is None:
            opening = bool(m) and not (m.group("f")[0] == "`" and "`" in m.group("info"))
            if opening:
                fence_char, fence_len = m.group("f")[0], len(m.group("f"))
            flags.append(opening)
            continue
        flags.append(True)
        if (m and m.group("f")[0] == fence_char and len(m.group("f")) >= fence_len
                and not m.group("info").strip()):
            fence_char, fence_len = None, 0
    return flags


def mask_fenced(text):
    """`text` with every fenced-code line blanked to SPACES. SAME LENGTH, same newline
    positions, so an offset found in the mask indexes the ORIGINAL unchanged — which is what
    lets a caller splice on it.

    THE MASK DOCTRINE, BOTH CONJUNCTS — THIS DOCSTRING IS ITS SINGLE OWNER, and a caller
    arguing a pattern safe argues it HERE, against both. Blanking to spaces withholds a match
    ONLY for a pattern that (i) cannot span a line boundary AND (ii) cannot match a run of
    spaces or an all-space line. A pattern failing (ii) can GAIN matches on masked text: an
    all-space line is a line the mask MANUFACTURED, so ``^\\s*$`` and ``^ {3}$`` both match more
    often after masking, not less. Every wiring must be argued safe under BOTH clauses.

    THIS DOCSTRING USED TO STATE ONLY THE WITHHELD HALF — "the only thing the mask can do is
    withhold a match that a fenced example would otherwise have won". That was measurably
    false, not merely loose, and the gained direction was executed against this very function
    before the sentence was replaced. The withheld half is still true and still the point; it
    was never the whole statement."""
    return "\n".join(" " * len(ln) if f else ln
                     for ln, f in zip(text.split("\n"), fenced_flags(text)))
# jscpd:ignore-end
# VENDOR-END(fence-mask)


# VENDOR-BEGIN(bodylint-core)
# GENERATED — do not edit; source: plugins/coord/_vendor/bodylint-core.py.txt; regenerate (framework repo only): python3 tools/gen-vendored.py; fragment-sha256: a36db6b9fbcf91c6
# ── The body-lint kernel ──────────────────────────────────────────────────────────────────────
# WHAT THIS FRAGMENT IS, AND WHY IT IS A FRAGMENT RATHER THAN A SECOND COPY (card#9550 leg 1).
#
# A body lint is a program that reads ONE markdown body a human or an agent authored, decides
# whether it is in the SHAPE a standard describes, and refuses it with a message that teaches the
# standard. This repo now has two such programs, enforcing two UNRELATED standards:
# `templates/bin/pr-body-lint.py` (the PR-body standard) and `templates/bin/coord-ask-operator`
# (the operator-question shape). Their RULES share nothing — different closed heading sets, for
# different reasons, owned by different documents — but the machinery under the rules is the same
# five things, and NONE of those five is about either standard's content:
#
#   * `LINE_CLIP` / `Finding` — one rule, one line, that line's own text, clipped for an echo.
#     Never a tally.
#   * `scan` — a fence-aware per-line view of the body, with the zip-length assertion that keeps
#     a truncated answer from reading like a clean one. It and `field_values` read the body through
#     `fold_newlines`, the one newline fold, so a body parses the same whoever decoded it.
#   * `field_values` / `field_value` — the machine-read-line grammar: `Name:` or `**Name:**` at
#     the start of an unfenced line, with a non-blank value.
#   * `read_body` — the `--body-file` / `--env` dual source, with `--env` existing for the
#     shell-injection reason the workflow template states; `env_text` is its environment read,
#     for a host's other environment values too.
#
# ⛔ THE ARGUMENT FOR HOISTING IT IS THE HOST'S OWN HISTORY, NOT A PREFERENCE. `field_value`'s
# ancestor `_audit_field` was itself a consolidation: `Built:` and `Coordinated in:` had been
# matched by TWO hand-written regexes strict in OPPOSITE directions, so each rejected the spelling
# the other required and a compliant PR was reported ABSENT. `pr-body-lint.py`'s own docstring for
# that function calls two regexes for one family "the measured defect this consolidation fixed."
# Hand-copying the same five mechanisms into a second lint re-creates, one layer out, exactly the
# shape that consolidation ended (canon #5: a second divergent implementation of one behavior is a
# defect, not a style choice).
#
# ⛔ WHAT IT DOES NOT CARRY, AND THE LINE IS THE POINT. No rule, no heading set, no phrase table,
# no exit-code dispatch, no CLI parser. A standard's CONTENT is its own program's, and a rule that
# drifted in here would be this fragment inventing a standard for two hosts at once. Host-specific
# reasoning — why THIS host needed the kernel, what its fields mean, what it measured — stays
# OUTSIDE the markers, hand-authored, per host, the same rule the `fence-mask` group states.
#
# ⛔ IT ASSUMES `os`, `re` AND `sys` ARE IMPORTED IN THE HOST, and `mask_fenced` / `fenced_flags`
# — the `fence-mask` group. Every host here is a copy of that group too; a host that were not
# would fail on the first body it read rather than silently, because `field_value` calls
# `mask_fenced` unconditionally.

# The per-finding echo cap. An authored line is text of unbounded length and a finding becomes one
# line of a CI log, a review digest or a terminal refusal; an unclipped echo of a 70 KB line is a
# finding nobody can read. The number is this fragment's own and nothing is measured against it —
# it is not a threshold.
LINE_CLIP = 200


class Finding:
    """One rule, one line, the line's own text. NEVER a tally.

    A COUNT IS A FIGURE THAT IS FALSE ON THE NEXT EDIT (canon #16), and a lint that reports "3
    findings" has told the author nothing they can act on. Every finding names its rule, points at
    a line, quotes that line, and states the fix in prose."""

    def __init__(self, rule, line, text, message):
        # A quoted line carries no `\r`: every line a rule quotes comes from `scan`, which folds
        # the body's newlines before it splits (`fold_newlines`).
        self.rule, self.line, self.text, self.message = rule, line, text, message

    def clipped(self):
        text = self.text
        return text if len(text) <= LINE_CLIP else text[:LINE_CLIP] + "… [clipped]"

    def as_dict(self):
        return {"rule": self.rule, "line": self.line, "text": self.clipped(),
                "message": self.message}


def fold_newlines(text):
    r"""`text` with every `\r\n` and every lone `\r` turned into `\n` — THE ONE NEWLINE FOLD.

    ⛔ IT IS APPLIED WHERE THE KERNEL PARSES (`scan`, `field_values`), NOT ONLY WHERE A HOST READS
    (card#10815 r1 review, m1). `review-prep.py` hands the lint an API body straight to
    `findings()` / `audit_fields()`, never through `read_body`; when the fold lived in the read
    alone, a lone-CR body was clean under `--env` and `built-missing` from the direct call — the
    review digest and the CI red were two verdicts. `_body_text` calls this too, because what a
    host STORES (a filed item's `raw_body`) is the decoded text, not the parse."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def scan(body, html_comments=False):
    r"""`[(lineno, text, fenced)]`, one row per line of `fold_newlines(body)`, 1-based.
    `html_comments` is `fenced_flags`'s own opt-in: True also marks an HTML comment block's lines
    in the `fenced` column, so a rule that skips a fenced line skips a commented one.

    ⛔ THE LINE LISTS ARE NEVER ZIPPED ACROSS TWO PROVENANCES WITHOUT THE LENGTH ASSERTED —
    `zip` TRUNCATES SILENTLY to the shorter, and a per-line answer that ran out halfway would
    report the tail of a body as unfenced and read exactly like a clean scan. `hooks/bin/_fence.py`
    states the same rule over the same tracker; both are consumers of one fragment, not two
    opinions about it.
    """
    body = fold_newlines(body)
    lines = body.split("\n")
    flags = fenced_flags(body, html_comments)
    if len(flags) != len(lines):
        raise AssertionError(
            "bodylint-core.scan: the fence tracker returned %d flag(s) for %d line(s). Both are "
            "computed over `text.split(chr(10))` and must agree." % (len(flags), len(lines)))
    return [(i + 1, line, bool(f)) for i, (line, f) in enumerate(zip(lines, flags))]


def field_values(body, name):
    r"""EVERY value of the machine-read line `name` in `body`, in document order — `[]` for none.

    ⛔ ONE GRAMMAR FOR EVERY MACHINE-READ LINE IN EVERY HOST. Both accepted spellings are
    `**Name:**` and plain `Name:`, line-anchored, at the start of the line, with a non-blank value.
    Both are measured-live in this repo's own PR bodies (`pr-body-lint._audit_field`'s docstring
    owns that measurement and the sample it came from); the colon-OUTSIDE spelling `**Name**:`
    appears zero times in it and is deliberately NOT accepted, because tolerating an unmeasured
    form widens the guard for nobody (canon #3).

    ⛔ `[ \t]*`, NEVER `\s*`, BETWEEN THE FIELD NAME AND ITS VALUE. `\s` matches `\n`, so the
    shipped pattern once matched ACROSS a newline (driven: `"Built:\ndispatched (…)"` matched,
    taking the NEXT line as the value). Read over the fence mask that makes a quoted example
    payload, that spanning arm would take the first non-blank line AFTER a fenced block as the
    field's value — the fence rule manufacturing the machine line it exists to suppress.

    ⛔ AND IT IS READ OUTSIDE THE BODY'S FENCES. A body that DOCUMENTS this grammar in a fenced
    example — ordinary in a repo whose bodies are largely about the lines these tools read — would
    otherwise have its EXAMPLE read as its FIELD. The fail-safe direction is deliberate: a body
    whose only `Name:` line is inside a fence reads as ABSENT, which is a finding the author fixes
    by unfencing their own line, rather than a PASS computed from somebody else's text.
    """
    body = fold_newlines(body or "")
    pattern = r"^(?:\*\*%(n)s:\*\*|%(n)s:)[ \t]*(?P<v>\S.*)$" % {"n": re.escape(name)}
    return [m.group("v").strip()
            for m in re.finditer(pattern, mask_fenced(body), re.MULTILINE)]


def field_value(body, name):
    """The FIRST value of the machine-read line `name`, or `None` when the body carries none.

    One arity over `field_values`, never a second regex: a field a standard declares once and a
    field it allows to repeat are read by the SAME grammar, and the only difference is which
    program wants how many. Two patterns for one family is the defect this fragment's header
    names."""
    values = field_values(body, name)
    return values[0] if values else None


def read_body(args):
    """The body text, from the ONE source the caller named. Raises `ValueError` on a fault.

    TWO SOURCES AND NO DEFAULT. `--body-file` is what a caller with the text already on disk uses;
    `--env` exists because a body interpolated into a `run:` script or any other shell argument is
    an injection by construction — double quotes do not stop backticks or `$(...)` — and the same
    value passed through the environment is not. Every host offers both for that reason, and the
    choice of which is the CALLER's; a default here would make one of them the silent path.

    ⛔ EVERY SOURCE DECODES THE SAME BYTES TO THE SAME TEXT, because all three read BYTES and
    hand them to ONE decoder, `_body_text`: UTF-8, an undecodable byte becoming U+FFFD, and `\\r\\n`
    or a lone `\\r` becoming `\\n`. The environment hands POSIX Python an undecodable byte as a
    lone surrogate (`\\xff` arrives as `\\udcff`, PEP 383), and `sys.stdin`'s text layer decodes
    with the locale's codec and error handler; read that way, the same bytes that file cleanly
    from a file reached a host's UTF-8 write as a surrogate and died there with a traceback
    (card#10815 r3). The `surrogateescape` re-encode in `env_text` gives back the exact bytes on
    POSIX; `env_text` owns the Windows case. NEWLINES ARE PART OF THAT PROMISE (card#10815 r4,
    m2): before they were, only the text-mode file open translated them, and a CRLF body through
    the environment or stdin kept a `\\r` on every line — which `coord-ask-operator` read as
    `## Background\\r`, no section at all, and refused the item `section-missing` (exit 1,
    nothing filed)."""
    if args.body_file:
        if args.body_file == "-":
            return _body_text(sys.stdin.buffer.read())
        try:
            with open(args.body_file, "rb") as fh:
                return _body_text(fh.read())
        except OSError as exc:
            raise ValueError("--body-file %s could not be read: %s" % (args.body_file, exc))
    if args.env not in os.environ:
        raise ValueError("--env %s names a variable that is not set. An UNSET variable is not an "
                         "empty body: the caller did not pass one, and a lint that treated the "
                         "two alike would red on a body it never saw." % args.env)
    return env_text(args.env)


def env_text(name):
    """The environment variable `name` as `read_body` decodes a body, or `None` when unset.

    The ONE environment read for any value a host writes as text — a body through
    `--env`, and an identity such as `COORD_AGENT` stored in a record (card#10815 r4, m1: read
    raw, a non-UTF-8 byte in it reached the record's UTF-8 write as a lone surrogate and died
    there with a traceback).

    ⛔ IT NEVER RAISES ON THE VALUE (card#10815 r1 review, m2). A Windows environment is text
    already, and a lone surrogate in it outside `\\udc80`-`\\udcff` fails the `surrogateescape`
    re-encode. `surrogatepass` encodes it instead, to bytes that are not UTF-8, which `_body_text`
    then turns into U+FFFD like any other undecodable byte."""
    if name not in os.environ:
        return None
    value = os.environ[name]
    try:
        raw = value.encode("utf-8", "surrogateescape")
    except UnicodeEncodeError:
        raw = value.encode("utf-8", "surrogatepass")
    return _body_text(raw)


def _body_text(raw):
    """`raw` bytes as text: UTF-8, U+FFFD for an undecodable byte, universal newlines — exactly
    what a text-mode `open(..., encoding="utf-8", errors="replace")` of the same bytes returns."""
    return fold_newlines(raw.decode("utf-8", "replace"))
# VENDOR-END(bodylint-core)


# ── The standard, as data ─────────────────────────────────────────────────────────────────────
# ⛔ BOTH TABLES BELOW ARE THE EXECUTABLE FORM OF `skills/release-pr/SKILL.md § PR body`'s IN and
# OUT tables. They are DATA so that the rules read off one place; they are NOT a second statement
# of the standard, and a disagreement between them and that section is a defect in THIS file. A
# rule added here without a row there is this program inventing a standard, which is the one thing
# it must not do — the section is ratified by the operator and this is its enforcement, not its
# author.

# The IN table's section set, read as CLOSED. A heading outside it is a section the OUT table
# gives a home elsewhere (the review-request round, the CHANGELOG, a card), so it reds.
# Compared by PREFIX, case-insensitively: the shipped generator writes `## Bundled (generated —
# do not hand-edit)` and `## Bundled PRs`, which are that row's heading with its own qualifier,
# not a different section.
#
# ⛔ EVERY MEMBER CITES THE IN-TABLE ROW IT COMES FROM, AND THE CITATION IS CHECKED. § PR body
# carries a `<!-- pr-body-lint:allowed-h2 … -->` marker block beside that table mapping each
# heading to the row cell it is admitted by; a drift check in the framework repo's own CI reds
# when this tuple and that block disagree, or when a cited row cell is no longer a row of the
# table. That is what makes this an executable COPY of the standard rather than a second standard
# (canon #16 GUARD: a restatement a program must load inline gets a drift check, not a comment).
#
# ⛔ `Release artifacts` IS HERE BECAUSE THE GENERATOR EMITS IT AND THE IN TABLE ADMITS IT —
# operator ruling, 2026-09-11, on fw#898 r1. `## Card coverage` and `## Correlation gaps` are
# deliberately NOT here: they are process diagnostics about card promotion, the operator struck them
# from the v0.50.0 and v0.51.0 release bodies, and the fix was the GENERATOR's, not a widened guard
# here (canon #3). The toolkit's generator from v0.34.0 (DL-224) emits neither; a stale copy still
# can — § PR body names which, and what an author does with a red on one: not a finding against the
# author.
ALLOWED_H2 = ("Highlights", "Upgrade warnings", "Bundled", "Release artifacts")

# THE ONE WIDENING OF THAT SET, AND IT IS THE ADOPTING REPO'S, NOT THIS FILE'S (card#12387). A repo
# can REQUIRE a section on every PR — `BWtek-Medical/sola-device`'s shape guard requires
# `## SaMD boundary check` and `## CI action-pin resync check` at level 2 — and the closed set above
# reds that section on a release PR, so no release body could satisfy both checks. The repo declares
# its extra release H2s in this file, relative to the directory the lint runs in (the repo root in
# the shipped workflow, and in `coord-preflight`'s run of it), so this program stays byte-identical
# in every repo that vendors it. `read_release_headings` owns the format. A MISSING FILE IS NO
# EXTRAS, which is the closed set exactly. A declared heading is admitted by its FULL TEXT, exactly
# and case-sensitively — never by the prefix compare above: the prefix exists for the generator's
# own qualifiers on the IN table's rows, and a repo's required section has no qualifier to allow.
# It reaches only `heading-not-allowed`, which only a release PR runs; a non-release PR is
# untouched. The IN table is not widened by it — a repo's required section is that repo's.
# Written with `/`, which `open` takes on every platform, so the path every message names is the
# path the docs name.
RELEASE_HEADINGS_FILE = ".github/pr-body-lint-release-headings.txt"

# The OUT table, read as the phrases its rows actually BEGIN with in a body. Every phrase is homed
# by an OUT-table row, and THIS FILE DOES NOT SAY WHICH — neither the membership nor the mapping is
# restated here in prose, because a prose copy is one a program cannot guard and one a phrase
# added below would silently outdate. § PR body's `<!-- pr-body-lint:banned-openers … -->` marker
# block names the row that homes each phrase, verbatim, and the same drift check holds this tuple
# and that block equal. A phrase added here with no row there reds.
BANNED_OPENERS = ("Why", "Worth reading", "Not included", "Still to do", "Seen to fail",
                  "Verification", "Controls", "Review round")

# The IN table's `Machine-read / process-native lines` row: PARSED, not prose, so the installer
# POV does not reach them and they are not the body's scope line either. `Built:` and
# `**Coordinated in:**` are the audit rows, `Origin:`, `Design-approved:` and `Tier:` the provenance
# rows (card#11037), and `<!-- … -->` the generated markers (`<!-- release-manifest:… -->`).
# ⛔ `FROM` / `TO` USED TO BE IN THIS FAMILY AND ARE DELIBERATELY GONE (card#9073 leg E). While the
# standard admitted an attribution line, the scope-line rule had to SKIP it or a protocol-shaped
# body would have read as scope-line-less. The standard now REFUSES it (`rule_attribution_line`),
# so a body that carries one is judged on both rows at once: the line reds as an attribution line,
# and it is not silently accepted as the body's first content line either.
_MACHINE_LINE_RE = re.compile(r"^(?:\*\*(?:Built|Coordinated in|Origin|Design-approved|Tier)"
                              r"(?::\*\*|\*\*:)"
                              r"|(?:Built|Coordinated in|Origin|Design-approved|Tier):|<!--)")

# The attribution rows the coordination protocol puts on an ISSUE body and a COMMENT, and which a
# PR body must not carry. Indent-TOLERANT, `>`-INTOLERANT, and both halves are deliberate: the
# protocol's own parser (`templates/bin/coord_attribution.py` / the Action's `parseBody`) TRIMS
# each line before its `startswith`, so `  FROM: pm` is an attribution line to every consumer that
# matters and refusing it here is reading the same population they read; a `> FROM: pm` is a
# QUOTATION of somebody else's attribution (the approval-marker fragment owns that distinction and
# was measured on it), and a body quoting a coordination post is not making the claim itself.
# `[ \t]`, never `\s`, for the mask doctrine's reason — see `_DECORATION_RE` below.
_ATTRIBUTION_RE = re.compile(r"^[ \t]*(?P<name>FROM|TO):")

# A line's markdown DECORATION — the leading block quote, list bullet, ATX heading marker,
# ordered-list marker and emphasis runs — stripped before an opener is read, because `### Why
# MINOR` and `- **Why** we did it` open with the same word the OUT table sends elsewhere. Written
# with `[ \t]` and never `\s`: `\s` matches a newline, and a pattern in this family that can span
# a line boundary is the defect `_fence.py`'s mask doctrine names (three shipped patterns had it).
_DECORATION_RE = re.compile(r"^[ \t>]*(?:#{1,6}[ \t]+|[-*+][ \t]+|\d+[.)][ \t]+)?[ \t]*"
                            r"(?:\*\*|__|\*|_|`)*")

# ⛔ AN EXPLICIT CLASS RATHER THAN `\b`, AND IT IS THE DIFFERENCE BETWEEN A RULE AND A NUISANCE.
# `\b` after `Why` matches inside `Why-not`, and after `Controls` it matches in `Controls-Plane`;
# a hyphen is a word character to a reader and not to `re`. The negative lookahead refuses both.
#
# ⛔ AND THE CLASS IS SPELLED OUT INSTEAD OF `\w`, BECAUSE `_` IS A `\w` CHARACTER AND THAT MADE
# THE DECORATION STRIPPER UNREACHABLE FOR HALF THE MARKDOWN THAT SHIPS. `_DECORATION_RE` strips the
# LEADING emphasis run, so `__Why__ MINOR` arrives here as `Why__ MINOR` — and `(?![\w-])` then
# REFUSED it, because the very `_` that closes the bold is a word character. Measured on the
# shipped file before the fix: `**Why** we did it` red, `### Why MINOR` red, `` `Why` MINOR `` red,
# and `__Why__ MINOR` / `_Why_ we bumped` PASSED — the rule's coverage turned on which of two
# equivalent markdown bold spellings the author happened to type (fw#898 r1, M2). The lookahead's
# own reason above is the same reason: a character that closes an emphasis run is punctuation to a
# reader.
# THE RESIDUE, NAMED: the class is ASCII, so a banned phrase followed IMMEDIATELY by a non-ASCII
# letter or digit now reds where `\w` would have let it through. Every phrase in the tuple above is
# an English phrase and no such word exists; the direction is accepted rather than unnoticed.
_BANNED_RE = re.compile(r"(?:%s)(?![A-Za-z0-9-])" % "|".join(re.escape(p) for p in BANNED_OPENERS),
                        re.IGNORECASE)

# An H2, on ONE line. `[ \t]` for the same reason as above, and this pattern is applied per LINE
# (over the fence-aware scan) rather than with `re.MULTILINE` over the whole body — the mask
# doctrine does not arise, because no rule here ever sees a fenced line at all.
_H2_RE = re.compile(r"^##[ \t]+(?P<name>.+?)[ \t]*$")

# The OUT table's `Readings` row, read as a CLOSED table of claim shapes about LIVE CI / push /
# base state — card#9073 comment 4102's rule (leg B-2). Each entry is `(shape name, pattern)`; the
# NAMES are held equal, in order, to § PR body's `<!-- pr-body-lint:live-state-readings … -->`
# marker block by the same drift check that holds `ALLOWED_H2` / `BANNED_OPENERS` above, and every
# entry there cites the `Readings` row. A shape added here with no entry there reds.
#
# ⛔ IT REFUSES THE SHAPE; IT DOES NOT COMPARE THE CLAIM WITH THE HEAD — pm ruling on the leg B-2
# fork, and the reason is the consumer that gates. In CI this program runs on `pull_request`
# opened / edited / synchronize with a depth-1 checkout and no API read: it is ITSELF one of the
# runs on the head, so "every run terminal" is never true while it runs, and nothing re-runs it
# when CI concludes or the base moves. A green from a comparison would be a reading taken at lint
# time — the defect this rule exists to catch, one level up. The standard already answers the
# product question (a reading lives only in a sha-bound artefact; the body carries its
# derivation), so no head facts are read and there is no not-checked path.
#
# ⛔ A QUOTED CLAIM COUNTS — pm ruling, deliberately. fw#873's final body quotes its own first
# revision (`Revision 1 asserted "CI has not run on this head; the branch is not pushed"`), and a
# line like that reds here. `banned-opener` does not separate quoted from asserted text either, and
# a body quoting a stale reading is narration the OUT table moves out of the body anyway. A FENCED
# line is still payload, as it is for every rule here.
#
# THE SHAPE OF EACH PATTERN IS LOAD-BEARING. Every one is ONE outer group with no top-level `|`, so
# `(?!)` prefixed to it disables the whole shape — which is how the selftest's per-shape mutants
# show each one is what produced its red. Gaps are `[^.\n|]{…}` and literal spaces, never `\s`, for
# the mask doctrine's reason (see `_DECORATION_RE` above), and no shape crosses a `|`. A sha is 7–40
# hex characters with at least one digit AND at least one letter, so neither an all-letter word
# (`defaced`) nor a decimal number (`2026091`) is a sha. Bases are `dev` and `main` BY NAME and only
# by name (pm ruling; the header names the residue): `(?![\w/-]|\.\w)` ends the name, so a base that
# merely BEGINS with one (`dev-next`, `main-v2`, `origin/main-lts`, `dev/feature`) is another base,
# while a sentence's closing `.` still ends `main`.
#
# ⛔ A READING IS NOT ITS OWN PASS CONDITION — fw#910 r1 M1. The finding asks for a derivation and
# the conditions under which its output is a pass, and those conditions restate the reading (`a pass
# is 0 commits behind dev`, `a pass means CI is green at this head`); so does a description of what a
# tool does (`waits until all tags are pushed`). Closed narrowings separate them, each pinned by a
# mutant in the selftest's `LIVE_NARROWINGS`. A COUNT of zero is not judged (`[1-9]\d*`): a condition
# and a reading share that shape, so it withholds both, and the header names the zero-count reading
# as a residue. And every shape but
# `behind-base` OPENS ITS CLAUSE: `(?<!\w )` refuses the token a shape opens on when it follows a
# word and a space (a sha's optional backtick gets `(?<!\w `)` for the same reason). A condition or a
# description embeds the claim after a word (`means`, `until`, `when`); a reading opens on it, after
# a list marker, emphasis, a cell's `|`, a quote or clause punctuation. `behind-base` is exempt
# because its own reading puts a word before the count (`The branch is 2 commits behind`), and its
# conditions are written with zero counts. The residue — a reading introduced by a word — and
# `behind-base`'s false red — a description of a tool with a non-zero count — are the header's.
LIVE_STATE_READINGS = (
    ("ci-not-run",
     r"(?:(?<!\w )\bCI has not run (?:on|at) (?:this head"
     r"|`?\b(?=[0-9a-f]*[0-9])(?=[0-9]*[a-f])[0-9a-f]{7,40}\b`?))"),
    ("ci-state-at",
     r"(?:(?<!\w )\bCI (?:is |was )?(?:green|clean|terminal|passing|queued|pending|red)\b"
     r"[^.\n|]{0,12}\bat (?:this head|`?\b(?=[0-9a-f]*[0-9])(?=[0-9]*[a-f])[0-9a-f]{7,40}\b`?))"),
    ("branch-push",
     r"(?:(?<!\w )\b(?:the )?branch is not pushed\b"
     r"|(?<!\w )\ball \w+ (?:is |are )?(?:not )?pushed\b"
     r"|(?<!\w )(?<!\w `)`?\b(?=[0-9a-f]*[0-9])(?=[0-9]*[a-f])[0-9a-f]{7,40}\b`?"
     r" (?:is |are )?(?:not )?pushed\b)"),
    ("behind-base",
     r"(?:\b[1-9]\d* commits? (?:behind|ahead of) `?(?:origin/)?(?:dev|main)(?![\w/-]|\.\w))"),
    ("runs-success",
     r"(?:(?<!\w )\b[1-9]\d* runs?\b[^.\n|]{0,20}\ball\b[^.\n|]{0,24}\bsuccess\b)"),
)
_LIVE_STATE_RES = tuple((shape, re.compile(pattern, re.IGNORECASE))
                        for shape, pattern in LIVE_STATE_READINGS)

# The OUT table's `Process warnings` row, for the part of it § PR body names by name: "The
# merge-method note is OUT of the body — including on a release PR … no merge-button line in the
# body, no merge-gate narration (who merges, wait-for-`CLEAN`, why) around it". A CLOSED table of
# line shapes (card#13034), `(shape name, pattern)`, its NAMES held equal, in order, to § PR body's
# `<!-- pr-body-lint:merge-instructions … -->` marker block by the same drift check that holds the
# tuples above. It is judged on RELEASE PRs only (the header's ⛔ RELEASE-SCOPE block owns why).
#
# A SHAPE IS AN INSTRUCTION TO THE MERGER, NEVER A MENTION OF A MERGE METHOD. A release body's
# highlights and its generated `## Bundled` list name squash, rebase and merge commits as SUBJECTS
# (`fix(self-merge): refuse a squash of a back-merge`), and those lines are the installer's. So no
# shape is a bare method word, and every shape OPENS ITS CLAUSE the way `LIVE_STATE_READINGS`'
# shapes do: `(?<!\w )` refuses the opening token when it follows a word and a space, so `refuses
# to create a merge commit` and `will never squash a sync PR` are not judged, while `Merge with …`,
# `, never squash`, `- Merge button: …` and `- User is the merger` are. The same one-outer-group,
# no-top-level-`|` and `[^.\n|]` / literal-space conventions hold, for the same reasons; a gap may
# also cross one backticked span, because the tag a release names carries dots (`aimla-v0.1.1`).
MERGE_INSTRUCTIONS = (
    ("merge-method",
     r"(?:(?<!\w )\bmerge (?:with|using|via)\b"
     r"|(?<!\w )\b(?:never|do not|don't|not) (?:squash|rebase)\b"
     r"|(?<!\w )\bcreate a merge commit\b"
     r"|(?<!\w )\bmerge[ -](?:button|method)(?: intent)?:)"),
    ("merger-named",
     r"(?:\bis the merger\b"
     r"|(?<!\w )\b(?:the )?(?:user|operator|pm|maintainer|merger) (?:merges|will merge|must merge)"
     r" (?:this|it|the PR|the release PR)\b)"),
    ("merge-gate-wait",
     r"(?:(?<!\w )\bwait (?:for|until)\b[^.\n|]{0,30}\bmergeStateStatus\b)"),
    ("tag-after-merge",
     r"(?:(?<!\w )\btag\b(?:`[^`\n|]{1,40}`|[^.\n|`]){0,60}"
     r"\b(?:by hand|manually|after (?:the )?merg(?:e|ing))\b)"),
)
_MERGE_INSTRUCTION_RES = tuple((shape, re.compile(pattern, re.IGNORECASE))
                               for shape, pattern in MERGE_INSTRUCTIONS)

# The IN table's generated section, whose lines are the bundled PRs' own TITLES. `merge-instruction`
# does not judge it: a title about merge tooling is a subject, and the section is generated, so its
# author cannot reword a line the rule would red. Compared like `ALLOWED_H2`, by prefix.
GENERATED_H2 = "Bundled"

# The OUT table's AI-attribution row, as a CLOSED table of line shapes (card#10673). The table and
# its matcher are a VENDORED REGION, shared with `squash-message.sh`, which composes the landed
# commit message out of this same PR description — so the lint and the composer cannot disagree
# about what a matching line is. The shape NAMES are held equal, in order, to § PR body's
# `<!-- pr-body-lint:ai-attribution … -->` marker block by the same drift check that holds the
# tuples above.
# VENDOR-BEGIN(ai-attribution)
# GENERATED — do not edit; source: plugins/coord/_vendor/ai-attribution.py.txt; regenerate (framework repo only): python3 tools/gen-vendored.py; fragment-sha256: af82f73a303393df
# ── AI attribution — the lines no GitHub-bound text may carry (card#10673, operator-directed) ──
# The operator's ruling, verbatim: "On all github posts (PRs, Tasks, etc), I do not want bodies or
# comments to indicate the AI model used to generate the code or provide a session link." The
# ruling on the context stamp followed it: "Yes, remove any AI attributions". So no commit message,
# PR description, issue, comment or card is to carry the lines below. The rule's owner is the
# coord plugin's `docs/engineering-canon.md`'s standing instruction (for the context stamp,
# card#10673's operator ruling); this table is its executable form.
#
# `(shape name, pattern)`. Each pattern is applied with `search` to ONE line and never spans a
# line break (`[ \t]`, never `\s`). The table is CLOSED: a line that names a model in words no
# shape matches is NOT judged, so a clean result means only "no line matched one of these shapes".
#   co-author-trailer  the harness's commit trailer, `Co-Authored-By: <name> <noreply@anthropic.com>`.
#                      It is the line that makes GitHub list a second author on the commit.
#                      Anchored at the line start (after an optional `>` quote), so a trailer quoted
#                      mid-line in prose is not judged. It is keyed on the harness's own
#                      `noreply@anthropic.com` ADDRESS alone, whatever name precedes it — never on
#                      the name: a human co-author named `Claude …` is a person's credit, and
#                      dropping it would erase that person from the landed commit (fw#1095 r1).
#   session-trailer    the `Claude-Session:` commit trailer, anchored the same way.
#   session-link       a claude.ai session URL anywhere on the line. It requires a real session-id
#                      character after `session_`, so a placeholder written `session_…` or
#                      `session_<id>` is not a link and is not judged.
#   generated-footer   the harness's PR footer, `🤖 Generated with [Claude Code](…)`, with or without
#                      the link brackets. Before it only spaces, `>` quote marks and the harness's
#                      own robot emoji (U+1F916, optionally with its variation selector) may stand,
#                      so prose that quotes the words — a list item, a backtick — is not judged
#                      (fw#1095 r1).
#   ctx-stamp          the context-fill stamp, `<!-- CTX: <digits>% … -->`. It requires the digits,
#                      as the stamp's retired reader did, so the form written `<pct>%` is not judged.
#                      `coord-post` no longer writes the stamp (card#10673); the shape stays so a
#                      stamp copied forward from an old post still reds.
AI_ATTRIBUTION_SHAPES = (
    ("co-author-trailer",
     r"^[ \t>]*Co-Authored-By:[^\n]*noreply@anthropic\.com"),
    ("session-trailer", r"^[ \t>]*Claude-Session:"),
    ("session-link", r"claude\.ai/code/session_[A-Za-z0-9]"),
    ("generated-footer", r"^[ \t>]*(?:\U0001F916\uFE0F?[ \t]*)?Generated with \[?Claude Code\b"),
    ("ctx-stamp", r"<!--[ \t]*CTX:[ \t]*[0-9]+%"),
)
_AI_ATTRIBUTION_RES = tuple((shape, re.compile(pattern, re.IGNORECASE))
                            for shape, pattern in AI_ATTRIBUTION_SHAPES)


def ai_attribution_shape(line):
    """The NAME of the first shape `line` matches, or `None` when it matches none.

    One line in, one verdict out. WHICH lines are the population — every line of a commit message,
    or only the unfenced lines of a PR body — is the caller's decision, because the two surfaces
    differ on what a fenced block means."""
    for shape, rx in _AI_ATTRIBUTION_RES:
        if rx.search(line):
            return shape
    return None
# VENDOR-END(ai-attribution)


# ── The audit-row grammar — ONE OWNER FOR BOTH CONSUMERS ─────────────────────────────────────
def _audit_field(body, name):
    r"""The VALUE of the audit-trail line `name` in `body`, or `None` when the body carries none.

    ⛔ ONE GRAMMAR FOR THE WHOLE AUDIT-ROW FAMILY — THIS IS A PRIMITIVE BECAUSE TWO OF THEM WERE
    A DEFECT (canon #5). `Built:` and `**Coordinated in:**` are one family: same section, same
    contract, read by the same reviewer. They were matched by two hand-written regexes, strict in
    OPPOSITE directions — one demanded the `**` wrapper, the other refused it — so each rejected
    the spelling the other required, and a compliant PR was reported ABSENT. A verdict of ABSENT
    against a line that is RIGHT THERE is worse than no check: `agents/impl-reviewer.md § INPUT`
    tells the reviewer to CITE these lines rather than re-derive them, so the false accusation is
    what gets carried into the round. A third field added later must call this and not a third
    regex.

    THE ACCEPTED SPELLINGS ARE MEASURED, NOT ASSUMED. Over this repo's last 100 PR bodies
    (`gh api pulls?per_page=100`, counted 2026-09-07): `**Built:**` on 27 lines and plain `Built:`
    on 46; `**Coordinated in:**` on 55 and plain `Coordinated in:` on 9. BOTH spellings are live
    for BOTH fields, and both are documented in the coord plugin — its `docs/built-line.md` and
    `agents/impl-reviewer.md` write the bold form, `skills/release-pr/SKILL.md`'s Step-10
    checklist writes the plain one. The colon-OUTSIDE spelling `**Built**:` appears 0 times in
    that sample and is deliberately NOT accepted: tolerating an unmeasured form widens the guard
    for nobody (canon #3).

    What is NOT relaxed is the rest of the shape — line-anchored, at the start of the line, with a
    non-blank value. A `Built:` inside prose, or a bold header with nothing after it, is still
    not an audit-trail line, and for `Built:` the VALUE is then checked against the canonical set
    by the caller.

    ⛔ AND IT LIVES IN THIS FILE — THE card#9073 MOVE, AND IT IS A MOVE, NOT A COPY. It was
    `review-prep._audit_field` while review-prep was its only consumer. A repo's CI became the
    second consumer, on the far side of a deploy boundary review-prep cannot cross: this program
    runs standalone, in a tree where nothing of this plugin exists. THREE SHAPES WERE MEASURED
    against this checkout before this one was chosen. (1) A hand-synced second copy: the defect
    the paragraph above describes, one layer out, and the shape card#4953 built the vendoring
    engine to end. (2) A VENDORED REGION over both files — the engine's designed use, and it was
    STRUCTURALLY UNAVAILABLE when this was chosen: a group carried ONE `exec` bit for all its
    copies, `hooks/bin/review-prep.py` is 100755 because `install-linked-bin.sh` puts it on PATH
    BY SYMLINK (a link to a non-executable target cannot be run), and this file was then 100644.
    `--write` proved it by chmod'ing review-prep.py to 644 the moment the group was declared.
    ⚠ THAT MODE ARGUMENT NO LONGER HOLDS: since card#9211 this file is a PATH entry point listed
    in `templates/bin/.entrypoints`, which the engine holds to 100755, so an `exec: True` group
    over the pair would keep both executable. The choice of (3) has not been revisited since.
    (Read the pair's modes from git, never from this sentence: `git ls-tree <ref>
    --format='%(objectmode) %(path)' -- plugins/coord/hooks/bin/review-prep.py
    plugins/coord/templates/bin/pr-body-lint.py`. `templates/bin` as a whole is a MIX of both
    modes, which is why no directory-wide mode claim belongs here.)
    (3) ONE OWNER, TRANSPORTED — this. `review-prep.py`
    loads this file BY PATH through `hooks/bin/_modload.py` (the family's sanctioned loader) and
    reads `audit_fields()` and `findings()` off it, exactly as it delegates plane 1 to `ci-read`
    rather than re-deriving a CI verdict. One grammar, one file, no copy to keep in step.

    ⛔ AND IT IS READ OUTSIDE THE BODY'S FENCES, WHICH WAS THE DEFECT (card#9047
    r2). A PR body that DOCUMENTS this grammar in a fenced example — ordinary in this repo, whose
    PRs are largely about the lines this function reads — had its EXAMPLE read as its FIELD:
    driven, a body whose fence contained `Built: dispatched (coder x9 / mechanic x9)` and
    `Coordinated in: evil/repo#1` returned exactly those, while its REAL lines sat below the
    fence. That is a plane-1 verdict computed off text the author quoted rather than claimed, on
    the surface `agents/impl-reviewer.md § INPUT` tells the reviewer to CITE instead of
    re-deriving — and `coord-review` then routes `--thread` off the same example's ref. The rule
    is the record's own (`coord-review.py`'s machine-line note): a fenced line is QUOTED PAYLOAD,
    never the document's own answer, and it is one module so the two cannot drift.

    The fail-safe direction is deliberate: a body whose ONLY `Built:` line is inside a fence now
    reads as ABSENT, which is a finding the author fixes by unfencing their own line, rather than
    a PASS computed from somebody else's text.
    """
    return field_value(body, name)


def audit_fields(body):
    """`{field: value_or_None}` for the two audit rows the IN table's machine-read row names."""
    return {name: _audit_field(body, name) for name in ("Built", "Coordinated in")}


# ── The provenance declarations — ONE READER FOR THE LINT AND THE MERGE GATE (card#11037) ────────
# Where a PR's change came from (`Origin:`), the operator's design approval it rests on
# (`Design-approved:`), and the tier its author declares (`Tier:`). They are read HERE, once, by
# `declarations()`, and every consumer calls it: this lint (whether the lines are present and
# well-formed), and the approval gate `design_gate.py`, which `coord-approve` and `coord-self-merge`
# run (whether the declared origin is allowed to merge). Two parsers of one line is how a body the
# lint passes gets read differently by the gate (canon #5). `USER-GATING.md` § 2g owns what each
# origin means and which one needs a design approval; `skills/release-pr/SKILL.md § PR body`'s IN
# table owns the lines as part of the PR-body standard.
ORIGIN_KINDS = ("operator-directive", "bug-fix", "test-only", "agent-originated", "bundle",
                "reconcile")
# The kinds whose reference must be a card, written `card#<n>`.
_ORIGIN_CARD_KINDS = ("bug-fix", "test-only", "agent-originated")
_CARD_REF_RE = re.compile(r"card#[0-9]+")
# ⚠ A DECLARED RESTATEMENT, WITH A GUARD. The operator registry's item id is minted by
# `coord-ask-operator` (`ITEM_ID_RE`), and this file cannot import it: it deploys as ONE file into
# an adopting repo's CI, where no sibling exists. `pr-body-lint.selftest.py` reds unless this
# pattern equals that one.
DESIGN_APPROVED_ID_RE = re.compile(r"opq-[0-9]+-[0-9a-f]{4}")
TIER_VALUES = ("RESERVED", "ROUTINE")
# The origin the merge gate DERIVES for a PR GitHub reports as bot-authored — the ONE spelling;
# `design_gate.py` reads it from here (`bot_pr`): never a body's to declare.
BOT_ORIGIN = "dependency-bump"


def _declared(body, name):
    """`(value, None)`, `(None, None)` when absent, or `(None, why)` when the line is repeated.
    A value has one surrounding pair of backticks removed, the way an author quotes an id."""
    values = field_values(body, name)
    if len(values) > 1:
        return None, ("the body carries %d `%s:` lines; it declares one" % (len(values), name))
    if not values:
        return None, None
    v = values[0]
    if len(v) >= 2 and v.startswith("`") and v.endswith("`"):
        v = v[1:-1].strip()
    return v, None


def declarations(body):
    """The body's provenance declarations: `{"origin", "design_approved", "tier", "faults"}`.

    `origin` is `{"kind", "ref"}` or `None` when the body carries no `Origin:` line; `ref` is the
    rest of the line (`""` when there is none). `design_approved` is the registry item id or
    `None`; `tier` is `RESERVED`, `ROUTINE` or `None`. A line that is present but cannot be read
    leaves its value `None` and adds `(field, why)` to `faults` — a malformed line is never read as
    an absent one, and never as a guess at what it meant. Read outside the body's fences, by the
    same grammar as every other machine-read line (`field_values`)."""
    out = {"origin": None, "design_approved": None, "tier": None, "faults": []}
    value, why = _declared(body, "Origin")
    if why:
        out["faults"].append(("Origin", why))
    elif value is not None:
        kind, _, ref = value.partition(" ")
        ref = ref.strip()
        if kind == BOT_ORIGIN:
            out["faults"].append(("Origin", "`%s` is not declared: the merge gate derives it from a "
                                  "PR GitHub reports as bot-authored, and no body may claim it"
                                  % BOT_ORIGIN))
        elif kind not in ORIGIN_KINDS:
            out["faults"].append(("Origin", "`%s` is not an origin; the line is `Origin: <kind> "
                                  "<ref>` with <kind> one of %s"
                                  % (kind, ", ".join("`%s`" % k for k in ORIGIN_KINDS))))
        elif kind in _ORIGIN_CARD_KINDS and not _CARD_REF_RE.fullmatch(ref):
            out["faults"].append(("Origin", "`Origin: %s` names its card as `card#<n>`, and the "
                                  "rest of the line is %r" % (kind, ref)))
        elif kind == "operator-directive" and not (_CARD_REF_RE.fullmatch(ref)
                                                   or DESIGN_APPROVED_ID_RE.fullmatch(ref)):
            out["faults"].append(("Origin", "`Origin: operator-directive` names the directive as an "
                                  "operator register item (`opq-<digits>-<4 hex>`) or a card "
                                  "(`card#<n>`) — the two refs the merge gate can check — and the "
                                  "rest of the line is %r" % ref))
        else:
            out["origin"] = {"kind": kind, "ref": ref}
    value, why = _declared(body, "Design-approved")
    if why:
        out["faults"].append(("Design-approved", why))
    elif value is not None:
        if DESIGN_APPROVED_ID_RE.fullmatch(value):
            out["design_approved"] = value
        else:
            out["faults"].append(("Design-approved", "%r is not an operator registry item id "
                                  "(`opq-<digits>-<4 hex>`)" % value))
    value, why = _declared(body, "Tier")
    if why:
        out["faults"].append(("Tier", why))
    elif value is not None:
        word = value.split()[0].strip("*`_.,;:").upper() if value.split() else ""
        if word in TIER_VALUES:
            out["tier"] = word
        else:
            out["faults"].append(("Tier", "`Tier: %s` opens with neither %s" % (
                value, " nor ".join("`%s`" % t for t in TIER_VALUES))))
    return out


# ── The bot-author exemption — ONE PREDICATE, AND IT IS THE WHOLE OF IT ──────────────────────
# The account type GitHub reports for a BOT account, verbatim and case-sensitive. It is an
# enumerated value of the event payload's `user.type` (`User` | `Bot` | `Organization`), measured
# on this repo's own Dependabot PR — `PupFuzz/agent-board-framework#426`, whose `user.login` is
# `dependabot[bot]` and whose `user.type` is `Bot` — not recalled. It is a PROTOCOL CONSTANT, not
# prose, which is why it is written down once here and compared to rather than spelled at the
# comparison site.
BOT_AUTHOR_TYPE = "Bot"


def author_is_bot(author_type):
    """True only when `author_type` PROVES a bot account authored the PR. The header's ⛔ block
    owns why this reads a type and never a login, and why every other answer is `False`.

    ⛔ EXACT, AND THE STRICTNESS IS THE SAFETY PROPERTY. `.strip()` absorbs the transport (a value
    that arrived through a file or a shell with a trailing newline is the same value); the compare
    itself is exact, because this is the one input that switches a provenance rule OFF. A
    case-insensitive compare would accept a spelling GitHub does not emit, and the only caller
    that could supply one is a caller wiring this flag to something that is not `user.type` —
    exactly the case that must not win the exemption. The cost of being wrong in this direction is
    that a bot PR reds on the two rows, which is the behaviour that shipped before this existed;
    the cost of being wrong in the other direction is a body-provenance check any author can
    disarm.
    """
    return (author_type or "").strip() == BOT_AUTHOR_TYPE


# ── The release scope — ONE PREDICATE, AND THE TITLE IS ITS WHOLE INPUT (card#10493) ────────────
# The prefix the release flow gives every release PR's title — `release-pr` SKILL.md's checklist,
# criterion 5 (`release: vX.Y.Z`). Written once here and compared to, for the reason
# `BOT_AUTHOR_TYPE` is: it is the release flow's convention, not this file's prose.
RELEASE_TITLE_PREFIX = "release:"


def judged_as_release(title):
    """True when the body must meet the RELEASE standard. The header's ⛔ RELEASE-SCOPE block owns
    why the title is the discriminator and why a missing one is judged as a release.

    ⛔ A BLANK TITLE IS A MISSING ONE — `None`, `""` and whitespace alike — because each of them
    fails to prove the PR is NOT a release, and that proof is the only thing that switches the
    release rules OFF. The compare is case-insensitive and ignores leading whitespace, and both
    choices push toward the STRICT side: `Release: v1.4.0` is still a release PR's own declaration,
    and judging it as a feature PR would let a release body shed its section rules on a typo.
    """
    t = (title or "").strip()
    return not t or t.lower().startswith(RELEASE_TITLE_PREFIX)


# ── The rules ─────────────────────────────────────────────────────────────────────────────────
def _content_rows(rows):
    """The rows a rule may judge: unfenced, non-blank. Everything else is payload or spacing."""
    return [(n, text) for n, text, fenced in rows if not fenced and text.strip()]


def rule_scope_line(rows):
    """The IN table's `Scope line` row: one line, FIRST, naming the range this merges.

    WHAT IS CHECKED IS ITS POSITION, NEVER ITS WORDING. "Name the range" is a judgement a
    reviewer makes; "the body opens with a line of prose rather than a heading or nothing" is a
    property a program can decide, and it is the one that was actually violated — a body that
    opens on `## Highlights` has no scope line at all. The machine-read lines are SKIPPED rather
    than counted as the scope line: `Built:` and `**Coordinated in:**` are the IN table's audit
    rows and a generated `<!-- … -->` marker is payload, so a body that opens on one of them has
    its scope line on the first line BELOW them.

    ⛔ `FROM:` / `TO:` ARE NO LONGER IN THAT SKIP (card#9073 leg E). The skip existed because the
    standard used to ADMIT an attribution line above the scope line; it now refuses one
    (`rule_attribution_line`). While the skip carried the attribution rows, a body of an
    attribution line plus the two audit rows reported `scope-line` — every content row was
    skipped, so this rule fell through to its no-scope-line finding. Now the attribution line is
    ORDINARY CONTENT: such a body reds on `attribution-line` ALONE, and deleting the line is what
    re-exposes the scope-line question. This rule still checks POSITION and nothing else, so a
    body opening on `FROM: pm` satisfies it — `rule_attribution_line` is what reds that body, not
    this one. `pr-body-lint.selftest.py`'s `only_attr` row is where that is pinned.
    """
    for lineno, text in _content_rows(rows):
        if _MACHINE_LINE_RE.match(text.strip()):
            continue
        if text.lstrip().startswith("#"):
            return [Finding("scope-line", lineno, text,
                            "the body's first content line is a HEADING. The IN table's `Scope "
                            "line` row requires one line, FIRST, naming the commit / PR range "
                            "this merges against its base — read it in `skills/release-pr/"
                            "SKILL.md § PR body`.")]
        return []
    return [Finding("scope-line", 1, "",
                    "the body carries no content line outside its fences and its machine-read "
                    "rows, so it has no scope line. The IN table's `Scope line` row requires one "
                    "line, FIRST, naming the range this merges against its base.")]


def rule_headings(rows, release_headings=()):
    """The IN table's section set, read as closed: any other H2 is a section with a home outside
    the body, and the OUT table names that home. `release_headings` is the repo's declared extras
    (`RELEASE_HEADINGS_FILE`), each admitted by its exact full text."""
    out = []
    declared = ("; this repo declares %s in `%s`"
                % (", ".join("`%s`" % h for h in release_headings), RELEASE_HEADINGS_FILE)
                if release_headings else "")
    for lineno, text, fenced in rows:
        if fenced:
            continue
        match = _H2_RE.match(text)
        if not match:
            continue
        name = match.group("name").strip()
        if name in release_headings:
            continue
        if any(name.lower().startswith(allowed.lower()) for allowed in ALLOWED_H2):
            continue
        out.append(Finding("heading-not-allowed", lineno, text,
                           "`## %s` is not one of the sections the IN table admits (%s%s). The OUT "
                           "table names where this content lives — usually the review-request "
                           "round on the coordination thread, a card, or the CHANGELOG."
                           % (name, ", ".join("`%s`" % a for a in ALLOWED_H2), declared)))
    return out


def rule_banned_openers(rows):
    """The OUT table, read at the start of a line: the phrases the homes it names begin with."""
    out = []
    for lineno, text in _content_rows(rows):
        bare = text[_DECORATION_RE.match(text).end():]
        match = _BANNED_RE.match(bare)
        if not match:
            continue
        out.append(Finding("banned-opener", lineno, text,
                           "the line opens on `%s`, which the OUT table moves out of the body: "
                           "rationale, what is not included, still-to-do and self-review "
                           "narration belong to the review-request round, a card or the "
                           "CHANGELOG — the obligation is unchanged, only the home moves."
                           % match.group(0)))
    return out


def rule_attribution_line(rows):
    """A PR body carries NO `FROM:` / `TO:` attribution line — operator-directed, any repo.

    THE RULE IS the coord plugin's `docs/protocol-spec.md` § Addressing's, NOT THIS FILE'S, and it
    is the one row of the OUT table whose home is a different SURFACE rather than a different
    section: the coordination channel keeps these lines on issue bodies and comments, and a PR is
    attributed by the roster's repo binding instead. The finding quotes the line, like every other
    rule here.
    """
    out = []
    for lineno, text in _content_rows(rows):
        match = _ATTRIBUTION_RE.match(text)
        if not match:
            continue
        out.append(Finding("attribution-line", lineno, text,
                           "the body carries a `%s:` attribution line. A PR body carries none, on "
                           "ANY repo — the coordination channel's `FROM:` / `TO:` lines belong to "
                           "issue bodies and comments, and a PR is attributed by the roster's repo "
                           "binding (the coordination repo → pm; an impl repo → the seat that owns "
                           "it). Delete the line; the coord plugin's `docs/protocol-spec.md` "
                           "§ Addressing owns the rule and `skills/release-pr/SKILL.md § PR "
                           "body`'s OUT table carries the row." % match.group("name")))
    return out


def rule_ai_attribution(rows):
    """No line names the AI model, carries a Claude session link or co-author trailer, or carries
    the context stamp — operator-directed (card#10673), EVERY PR, any repo.

    THE RULE IS the coord plugin's `docs/engineering-canon.md`'s standing instruction, and the
    shapes are the vendored `ai-attribution` region above, shared with `squash-message.sh`. It runs
    over the unfenced rows like every rule here, so a body that quotes a trailer inside a fence to
    document it is not judged. One finding per line, naming the shape it matched."""
    out = []
    for lineno, text in _content_rows(rows):
        shape = ai_attribution_shape(text)
        if shape is None:
            continue
        out.append(Finding("ai-attribution", lineno, text,
                           "the line carries AI attribution (shape: `%s`). No GitHub-bound text "
                           "names the AI model, carries a Claude session link or co-author "
                           "trailer, or carries the context stamp — operator-directed, card#10673. "
                           "Delete the line. The harness adds these by default; `attribution` in "
                           "`~/.claude/settings.json` turns that off, and `hooks/bin/"
                           "ai-attribution-settings.py` reports whether it is off. "
                           "`skills/release-pr/SKILL.md § PR body`'s OUT table carries the row."
                           % shape))
    return out


def rule_live_state_reading(rows):
    """The OUT table's `Readings` row, for the CLOSED shape table `LIVE_STATE_READINGS` names.

    ONE FINDING PER LINE, naming every shape that line matched: a line can state more than one
    reading at once (fw#873's `CI has not run on this head. The branch is not pushed`), and one
    line is one thing for the author to fix."""
    out = []
    for lineno, text in _content_rows(rows):
        shapes = [shape for shape, pattern in _LIVE_STATE_RES if pattern.search(text)]
        if not shapes:
            continue
        out.append(Finding("live-state-reading", lineno, text,
                           "the line states a LIVE CI / push / base READING (shape: %s). A PR body "
                           "is not bound to a sha, so the next push, base move or CI conclusion "
                           "falsifies it in place while it goes on reading as current. Replace "
                           "this reading with its derivation — the command that re-derives it and "
                           "the conditions under which that command's output is a pass — and post "
                           "the reading itself in the review-request round. A QUOTED reading "
                           "counts too. `skills/release-pr/SKILL.md § PR body`'s `Readings` row "
                           "owns the rule." % ", ".join("`%s`" % s for s in shapes)))
    return out


def rule_merge_instruction(rows):
    """§ PR body's merge-method note, on a RELEASE PR: no line telling the merger how to merge, who
    merges, or what to do by hand once merged. One finding per line, naming every shape it matched.
    Lines under the generated `## Bundled` section are not judged (`GENERATED_H2`)."""
    out, generated = [], False
    for lineno, text in _content_rows(rows):
        heading = _H2_RE.match(text)
        if heading:
            generated = heading.group("name").strip().lower().startswith(GENERATED_H2.lower())
            continue
        if generated:
            continue
        shapes = [shape for shape, rx in _MERGE_INSTRUCTION_RES if rx.search(text)]
        if not shapes:
            continue
        out.append(Finding("merge-instruction", lineno, text,
                           "the line is a merge instruction or merge-gate narration (shape: %s). "
                           "A release PR body is written for the installer, and how to merge it, "
                           "who merges it and what is done by hand after the merge are the "
                           "merger's, not the installer's. Delete the line, and make sure your "
                           "repo's release / versioning doc owns the merge-method rule. "
                           "`skills/release-pr/SKILL.md § PR body` owns the rule and names where "
                           "the merge button reaches the merger instead."
                           % ", ".join("`%s`" % s for s in shapes)))
    return out


def rule_audit_rows(body, author_type=None):
    """The IN table's machine-read row, for the two fields it names by name.

    ⛔ THE BOT EXEMPTION IS APPLIED HERE, IN THE RULE THAT OWNS BOTH ROWS, AND NOWHERE ELSE — which
    is what makes "only these two rows are excused" a property of the code rather than a promise.
    A filter over `findings`' output would have to name the two rules by string and would silently
    widen the day a third finding of this family is added. `author_type=None` — every caller that
    does not pass one, `review-prep.py` included — is not a bot, so nothing changes for them.
    """
    if author_is_bot(author_type):
        return []
    out = []
    fields = audit_fields(body)
    if not fields["Coordinated in"]:
        out.append(Finding("coordinated-missing", 0, "",
                           "`**Coordinated in:**` is ABSENT from the body — in EITHER spelling, "
                           "and outside a fence. It is the PR ↔ coord-thread audit anchor; a "
                           "user-direct feature with no pre-existing thread is the one exemption "
                           "and the author states it."))
    if not fields["Built"]:
        out.append(Finding("built-missing", 0, "",
                           "`Built:` is ABSENT from the body — in EITHER spelling, and outside a "
                           "fence. The coord plugin's `docs/built-line.md` owns the value set; a "
                           "missing line is a finding. This program checks PRESENCE only — the "
                           "VALUE's shape is checked against that doc by `review-prep.py`, which "
                           "owns that read."))
    return out


def rule_declarations(body, author_type=None):
    """The provenance rows (card#11037): `Origin:` on every PR, `Design-approved:` beside an
    `agent-originated` one, and each of `Origin:`, `Design-approved:` and `Tier:` well-formed where
    present. `declarations()` reads them; this only reports.

    ⛔ THE BOT EXEMPTION REACHES `origin-missing` AND `design-approved-missing` AND NOTHING ELSE,
    for the audit rows' reason: a bot has no dispatch behind it, so it cannot declare an origin truthfully. A malformed
    line is still a finding — a bot does not write one. This exempts the LINT only: the merge gate
    (`design_gate.py`) refuses a body with no `Origin:` whoever authored it."""
    d = declarations(body)
    out = []
    for field, why in d["faults"]:
        message = "%s. %s" % (why, _DECLARATION_OWNER)
        if field == "Origin":
            out.append(Finding("origin-malformed", 0, "", message))
        elif field == "Design-approved":
            out.append(Finding("design-approved-malformed", 0, "", message))
        else:
            out.append(Finding("tier-malformed", 0, "", message))
    faulted = {field for field, _ in d["faults"]}
    if author_is_bot(author_type):
        return out
    if d["origin"] is None and "Origin" not in faulted:
        out.append(Finding("origin-missing", 0, "",
                           "`Origin:` is ABSENT from the body. Every PR declares where its change "
                           "came from — `Origin: operator-directive <opq-id | card#<n>>`, `Origin: "
                           "bug-fix card#<n>`, `Origin: test-only card#<n>` (a change to tests "
                           "alone), `Origin: agent-originated card#<n>`, `Origin: bundle` on a "
                           "release or back-merge sync PR, or `Origin: reconcile` on a "
                           "`/coord:update` reconcile PR — and `coord-approve` refuses a PR without "
                           "one. %s" % _DECLARATION_OWNER))
    elif ((d["origin"] or {}).get("kind") == "agent-originated" and d["design_approved"] is None
          and "Design-approved" not in faulted):
        out.append(Finding("design-approved-missing", 0, "",
                           "`Origin: agent-originated` needs `Design-approved: <opq-id>` — the "
                           "operator registry item whose answer approved this design. Without one "
                           "the deliverable is the design, filed with `coord-ask-operator` as a "
                           "`design` question, not this PR. %s" % _DECLARATION_OWNER))
    return out


_DECLARATION_OWNER = ("The coord plugin's `docs/USER-GATING.md` § 2g owns what each origin means; "
                      "`skills/release-pr/SKILL.md § PR body` owns the line.")


# ─────────────────────────────────────────────────────────────────────────────────────────────
# ⛔ THE VERSION CLASSIFICATION — ONE ROW PER RULE ABOVE, AUTHORED BY WHOEVER LANDS THE RULE
# ─────────────────────────────────────────────────────────────────────────────────────────────
# WHAT THIS IS FOR (card#9748). A reviewer runs THIS file out of ITS OWN plugin root and judges a
# PR in a repo that may have reconciled at a DIFFERENT coord version. Where a rule judges the same
# artifact differently at the two versions, the finding it emits is FALSE FOR THAT REPO — and it
# arrives as a verdict, which is what makes it expensive: confidence, not a question. The
# mechanism that catches that is `hooks/bin/_reconciled.py`, and it deliberately CANNOT infer
# these two properties at runtime: they are properties of the CHANGE, not of the two repos, and
# from inside the mechanism a policy fork and an upstream bugfix look identical.
#
# ⇒ SO THEY ARE DECLARED HERE, BESIDE THE RULES, BY THE HUMAN LANDING THE RULE. Two axes, and
# only their INTERSECTION sizes anything:
#
#   direction   `one-directional` — ONE artifact satisfies both versions (the mechanism never
#                                   engages: the finding is true at either).
#               `hard-flip`       — NO artifact satisfies both. `since` is then REQUIRED: it is
#                                   the coord version the flip LANDED in, and it is what decides
#                                   which side of the flip a repo's marker sits on.
#   case        `1` a POLICY divergence — both versions defensible ⇒ ARBITRATE to the reviewed
#                                   repo's version.
#               `2` a DEFECT fixed upstream — one version is simply wrong ⇒ judged at the NEWER
#                                   version, NEVER arbitrated (arbitration would deliberately
#                                   preserve the bug).
#
# ⛔ A RULE MISSING FROM THIS TABLE IS UNCLASSIFIED, AND IS NEVER ARBITRATED: across a skew it
# makes every review's reconciled version NOT ESTABLISHED (exit 3, the rule named). It does not
# default to safe. `pr-body-lint.selftest.py`'s arm l DERIVES the rule ids from this file's own
# `Finding("<id>", …)` sites and reds when the two disagree — or when an id is not a string
# literal it can read — so landing a rule without a row fails the suite rather than a review.
#
# ⚠ AND A LATER EDIT TO A RULE CAN CHANGE ITS ROW. These values describe the rule's history, not
# its current text: loosening a rule that was one-directional into one that refuses what it used
# to require makes it a `hard-flip` with a new `since`, and the row must move with the change.
VERSION_CLASSIFICATION = {
    # ⭐ THE ARBITRATED ROW: hard flip + case 1, the only combination in this table where NO
    # artifact satisfies both versions. (Which rows are in that set is DERIVED, never written
    # down — `hooks/bin/_reconciled.py`'s header owns the derivation and the reason a version
    # window spelled in a comment is a figure with a maintenance schedule.) Until v0.53.0 the
    # PR-body standard REQUIRED the
    # `FROM:` / `TO:` attribution line; the operator's 2026-09-11 ruling (card#9229 → card#9073
    # leg E) REFUSES it, and this rule is that refusal. A repo reconciled before the flip has
    # bodies whose attribution line is correct FOR IT, so a reviewer holding v0.53.0+ emits a
    # false accusation against every one of them. `since` is derived, not recalled: the rule
    # arrived with this whole file in `13d45704`, whose earliest containing tag is v0.53.0.
    "attribution-line": {
        "case": 1, "direction": "hard-flip", "since": "0.53.0",
        "note": "the standard REVERSED — required before v0.53.0, refused from v0.53.0",
    },
    # CASE 1 (the IN table's allowed-H2 set is a policy choice, and a future window could widen or
    # narrow it), but ONE-DIRECTIONAL across every window so far: the set has only ever been read
    # as closed, and a body whose headings are inside it is inside it at either version. ⚠ REMOVING
    # a heading from `ALLOWED_H2` would make this a hard flip and this row must move with it.
    "heading-not-allowed": {
        "case": 1, "direction": "one-directional",
        "note": "the allowed-H2 set is a policy choice; a body inside the set is inside it at "
                "both versions. A heading REMOVED from the set makes this a hard flip.",
    },
    # CASE 2 — `LIVE_STATE_READINGS` names claim shapes a PR body cannot honestly make; a body
    # that makes none of them is correct at every version, so the finding is true either way.
    "live-state-reading": {
        "case": 2, "direction": "one-directional",
        "note": "a body carrying no live-state claim satisfies both versions",
    },
    # The four below are the EXECUTABLE FORM of standard rows that predate this file (the header
    # says so: the rules are the STANDARD'S, not this file's). The change at `13d45704` was
    # ENFORCEMENT, not policy — nothing that passed the written standard began to fail — so a body
    # satisfying them satisfies both versions. CASE 2: "unenforced" is not a defensible
    # alternative policy, it is the defect the rule fixed.
    "scope-line": {
        "case": 2, "direction": "one-directional",
        "note": "the IN table's Scope line row predates the rule; enforcement, not a policy change",
    },
    "banned-opener": {
        "case": 2, "direction": "one-directional",
        "note": "the OUT table predates the rule; enforcement, not a policy change",
    },
    "coordinated-missing": {
        "case": 2, "direction": "one-directional",
        "note": "`review-prep` checked this field's PRESENCE before this file existed; the rule "
                "moved the read, not the standard",
    },
    "built-missing": {
        "case": 2, "direction": "one-directional",
        "note": "`review-prep` checked this field's PRESENCE before this file existed; the rule "
                "moved the read, not the standard",
    },
    # CASE 1 (an operator policy, card#10673 — not a defect fixed), ONE-DIRECTIONAL: no earlier
    # standard REQUIRED a model name, session link or co-author trailer in a PR body, so a body
    # carrying none of them satisfies both versions and the finding is true at either. Same shape
    # as `heading-not-allowed`. ⚠ It would become a hard flip only if an older standard had
    # REQUIRED such a line, which none did.
    "ai-attribution": {
        "case": 1, "direction": "one-directional",
        "note": "a body carrying no AI-model / session / co-author attribution satisfies both "
                "versions; no earlier standard required one",
    },
    # CASE 1 (operator-directed provenance, card#11037), ONE-DIRECTIONAL: no earlier standard
    # refused an `Origin:`, `Design-approved:` or `Tier:` line, so a body carrying well-formed ones
    # satisfies both versions and each finding is true at either.
    "origin-missing": {
        "case": 1, "direction": "one-directional",
        "note": "a body carrying an `Origin:` line satisfies both versions",
    },
    # Still ONE-DIRECTIONAL when a kind is ADDED (card#12757 `test-only`, card#12618
    # `reconcile`): a body declaring a kind in the OLDER set satisfies both versions. A new kind is
    # well-formed only from the release that carries it — the earliest tag containing the commit
    # that adds it to `ORIGIN_KINDS` (`git tag --contains`), never a recalled version — so a
    # reviewer behind that release reads it as malformed. REMOVING a kind would make this a hard
    # flip, and this row must move with it.
    "origin-malformed": {
        "case": 1, "direction": "one-directional",
        "note": "a body whose `Origin:` kind is in the OLDER version's set satisfies both; a kind "
                "added later (`test-only`, `reconcile`) is well-formed only from the release that "
                "carries it",
    },
    "design-approved-missing": {
        "case": 1, "direction": "one-directional",
        "note": "an agent-originated body carrying `Design-approved:` satisfies both versions",
    },
    "design-approved-malformed": {
        "case": 1, "direction": "one-directional",
        "note": "a body whose `Design-approved:` line is well-formed satisfies both versions",
    },
    "tier-malformed": {
        "case": 1, "direction": "one-directional",
        "note": "a body with no `Tier:` line, or one opening RESERVED or ROUTINE, satisfies both "
                "versions",
    },
    # CASE 2, ONE-DIRECTIONAL — the same shape as `banned-opener`: § PR body has put the
    # merge-method note OUT of the release body since card#6344, so this rule (card#13034) is
    # enforcement, not a policy change, and a body carrying no merge instruction satisfies both
    # versions.
    "merge-instruction": {
        "case": 2, "direction": "one-directional",
        "note": "§ PR body's merge-method note predates the rule; enforcement, not a policy change",
    },
}


def findings(body, author_type=None, title=None, release_headings=()):
    """Every finding in `body`, ordered by line. THE ONE ENTRY POINT — every consumer calls this.

    `author_type` is the PR author's ACCOUNT TYPE as the event payload reports it, or `None` when
    the caller has none to give — a terminal run over a file, and `review-prep.py`, which builds a
    reviewer's digest rather than a gate. `None` is not a bot.

    `title` is the PR's title, or `None` when the caller has none. It decides which rules run —
    `judged_as_release` is the predicate and the header's ⛔ RELEASE-SCOPE block owns the split.
    `None` is judged as a release, so a caller that passes no title gets every rule, as before
    card#10493.

    `release_headings` is the repo's declared extra release H2s (`parse_release_headings`), empty
    when the caller passes none — the closed set exactly. Only a release PR's section rule reads it.
    WHAT EACH CALLER PASSES: this file's CLI reads the working tree's `RELEASE_HEADINGS_FILE`;
    `review-prep.py` reads that file at the reviewed PR's head; `coord_protocol.pr_body_findings`
    passes none. The PRs that last caller judges are `coord-post`'s, and `coord-post` creates and
    edits PRs only on the coordination repo (or, for `--cross edit`, the channel repo), so an
    implementation repo's declaration never applies there. The RESIDUE, named: a coordination repo
    that itself declares release headings would have them ignored by that pre-flight.
    """
    rows = scan(body or "")
    # The rules about what a reader SEES judge the rendered rows, comments masked. The attribution
    # rules judge what the body CARRIES, so they keep the comments: the body becomes the squash
    # message with its comments in it, and the context stamp `ai-attribution` refuses IS a comment.
    rendered = scan(body or "", html_comments=True)
    out = (rule_banned_openers(rendered) + rule_live_state_reading(rendered)
           + rule_attribution_line(rows) + rule_ai_attribution(rows)
           + rule_audit_rows(body or "", author_type)
           + rule_declarations(body or "", author_type))
    if judged_as_release(title):
        out += rule_merge_instruction(rendered)
        out += rule_scope_line(rendered) + rule_headings(rendered, release_headings)
    return sorted(out, key=lambda f: (f.line, f.rule))


# ── CLI ───────────────────────────────────────────────────────────────────────────────────────
def read_author_type(args):
    """The PR author's account type, or `None` when the caller named no source for it.

    ⛔ AN UNSET VARIABLE IS `None` HERE, AND A FAULT IN `read_body` — THE ASYMMETRY IS THE POINT.
    For the BODY there is no correct answer when the variable is missing: the program would grade
    a body it never saw, and either verdict it printed would be about nothing, so it refuses with
    exit 2. For the AUTHOR there IS a correct answer, and it is the strict one — nothing proves a
    bot wrote this, so no exemption. Faulting here would turn a workflow that passes the body
    correctly and the author not at all into a hard CI error on every PR, in exchange for a
    question that already has a safe answer.
    """
    if not args.author_type_env:
        return None
    return os.environ.get(args.author_type_env)


def read_title(args):
    """The PR's title, or `None` when the caller named no source for it — or named a variable that
    is unset. `None` is judged as a release PR (`judged_as_release`), which is the strict side.

    ⛔ AN UNSET VARIABLE IS `None`, NOT A FAULT, for `read_author_type`'s reason: the question has a
    safe answer without it. An adopter who re-copies this file and keeps a workflow that passes no
    title gets the full standard on every PR, as before card#10493, and a line saying so — never a
    hard CI error on every PR.
    """
    if args.title is not None:
        return args.title
    if args.title_env:
        return os.environ.get(args.title_env)
    return None


def parse_release_headings(raw, source):
    """The declared extra release H2s in `raw` — the bytes of a `RELEASE_HEADINGS_FILE` — as a
    tuple of heading texts. `source` names where the bytes came from, for the fault message only.
    Raises `ValueError` on a fault.

    ⛔ THE ONE PARSER OF THIS FILE'S FORMAT, AND IT TAKES BYTES SO IT IS ALSO THE ONE DECODER. Two
    callers hold the file: `read_release_headings` below reads it from the working tree, and
    `hooks/bin/review-prep.py` reads it at the PR's head through the contents API. Both hand the
    bytes here, so a review digest and a CI run on the same version of this file parse a
    declaration the same way. (The two can run different versions: the digest uses the reviewer's
    plugin copy, CI the repo's vendored one.)

    THE FORMAT IS ONE HEADING'S TEXT PER LINE, AS IT APPEARS AFTER `## ` — `SaMD boundary check`,
    not `## SaMD boundary check`. Surrounding whitespace and blank lines are ignored; there is no
    comment syntax. ⛔ A LINE OPENING `#` IS A FAULT, NOT A HEADING: written as `## SaMD boundary
    check` it would never equal any heading's text, so the repo's declaration would silently admit
    nothing and the release PR would red on a heading its author believes declared. Refusing it
    names the source and the line instead.

    ⛔ A LEADING UTF-8 BYTE-ORDER MARK IS STRIPPED, because an editor that writes one is not
    declaring a heading that starts with U+FEFF. `str.strip` does not remove it, so left in place
    it is glued to the first line: that heading would silently never match, and a first line
    written `## …` would slip past the `#` fault above."""
    text = _body_text(raw)
    if text.startswith("\ufeff"):
        text = text[1:]
    names = []
    for lineno, line in enumerate(text.split("\n"), 1):
        name = line.strip()
        if not name:
            continue
        if name.startswith("#"):
            raise ValueError("%s line %d declares %r, which opens with `#`. The file lists each "
                             "extra release heading's TEXT, one per line, without the `## ` "
                             "marker — write %r." % (source, lineno, name, name.lstrip("#").strip()))
        names.append(name)
    return tuple(names)


def read_release_headings(path=RELEASE_HEADINGS_FILE):
    """The repo's declared extra release H2s from the working tree — `()` when `path` does not
    exist, else `parse_release_headings` of its bytes. Raises `ValueError` on a fault, which the
    CLI reports as exit 2.

    ⛔ ONLY A MISSING FILE IS "NO EXTRAS". A path that exists and cannot be read — a directory, or
    a file this process may not open — is a fault: reading it as empty would red a release body on
    headings the repo did declare, and the log would not say why."""
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except FileNotFoundError:
        return ()
    except OSError as exc:
        raise ValueError("%s could not be read: %s" % (path, exc))
    return parse_release_headings(raw, path)


def main(argv):
    ap = argparse.ArgumentParser(
        prog="pr-body-lint",
        description="Red on a PR body that does not meet `release-pr` SKILL.md § PR body — write "
                    "it for the software installer. The PR's title decides how much of it: one "
                    "opening `release:` gets the full standard, any other title everything but the "
                    "release-only section set, scope line and merge-instruction rule (the "
                    "header's RELEASE-SCOPE block owns the split), and no title at all the full "
                    "standard.",
        epilog="exit: 0 = meets the standard | 1 = at least one finding | 2 = a fault (usage, "
               "input, or a crash): no verdict", allow_abbrev=False)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--body-file", help="read the body from this path (`-` for stdin)")
    src.add_argument("--env", help="read the body from this ENVIRONMENT VARIABLE (CI: pass "
                                   "${{ github.event.pull_request.body }} through `env:`)")
    ap.add_argument("--author-type-env",
                    help="read the PR AUTHOR'S ACCOUNT TYPE from this ENVIRONMENT VARIABLE (CI: "
                         "pass ${{ github.event.pull_request.user.type }} through `env:`). The "
                         "exact value `Bot` exempts the body from `Built:`, "
                         "`**Coordinated in:**` and `Origin:` (with the `Design-approved:` an "
                         "agent-originated origin needs), and from NOTHING else. Every other value "
                         "— including an unset variable — is not a bot and those rows are required, "
                         "which is also what happens when this flag is absent")
    ttl = ap.add_mutually_exclusive_group()
    ttl.add_argument("--title",
                     help="the PR's TITLE, literally — what an author passes before `gh pr "
                          "create --title`. A title opening `release:` is a release PR")
    ttl.add_argument("--title-env",
                     help="read the PR's TITLE from this ENVIRONMENT VARIABLE (CI: pass "
                          "${{ github.event.pull_request.title }} through `env:`, for the "
                          "injection reason `--env` states). With neither flag, or with an unset "
                          "variable, the body is judged as a RELEASE PR body — the full standard")
    ap.add_argument("--label", default="PR body",
                    help="what to call the body in the output (default: %(default)s)")
    ap.add_argument("--json", action="store_true",
                    help="emit the result as JSON on stdout (the review path's transport)")
    args = ap.parse_args(argv)

    try:
        body = read_body(args)
    except ValueError as exc:
        sys.stderr.write("pr-body-lint: %s\n" % exc)
        return 2

    author_type = read_author_type(args)
    title = read_title(args)
    release = judged_as_release(title)
    # Read only for a release PR — the one run whose verdict it can change — so a non-release PR's
    # outcome does not depend on the file at all, a malformed one included.
    try:
        release_headings = read_release_headings() if release else ()
    except ValueError as exc:
        sys.stderr.write("pr-body-lint: %s\n" % exc)
        return 2
    found = findings(body, author_type, title, release_headings)
    if args.json:
        # `author_type` is emitted RAW — the value as read, `null` when none was given — and the
        # exemption itself is NOT emitted beside it. A consumer that wants to know whether the
        # audit rows were waived reads this field against the one rule (`author_is_bot`); a second
        # boolean here would be that rule restated in the output, free to disagree with it. The
        # TITLE is emitted RAW for the same reason, and the release scope is `judged_as_release`'s.
        json.dump({"tool": "pr-body-lint", "label": args.label, "clean": not found,
                   "author_type": author_type, "title": title,
                   "release_headings": list(release_headings),
                   "fields": audit_fields(body),
                   "findings": [f.as_dict() for f in found]},
                  sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
        return 1 if found else 0

    # ⛔ AN EXEMPTION THAT FIRES SILENTLY IS THE ONE A LATER READER MIS-READS AS A CLEAN BODY. When
    # the two audit rows were waived, the run SAYS SO — on the pass path and the fail path alike,
    # because a bot PR that reds on some other rule must not look like a bot PR that was never
    # exempted at all.
    if author_is_bot(author_type):
        sys.stdout.write("pr-body-lint: the PR's author type is `%s`, so `Built:`, "
                         "`**Coordinated in:**` and `Origin:` are NOT required of this body — a bot "
                         "can declare none of them truthfully. Every other rule of the standard "
                         "still applies. `coord-approve` still refuses a PR with no `Origin:`.\n"
                         % BOT_AUTHOR_TYPE)

    # ⛔ THE SCOPE IS STATED ON EVERY RUN THAT DID NOT GET THE PLAIN RELEASE CASE, for the reason
    # the bot line above is: a scope decided silently is the one a reader mis-reads. A feature PR
    # author who forgot `--title` must see WHY `## Summary` reds; a feature PR's green must not
    # read as "this body meets the release standard".
    if title is None or not title.strip():
        sys.stdout.write("pr-body-lint: no PR title was given (`--title` / `--title-env`), so this "
                         "body is judged as a RELEASE PR body — the full standard. A PR whose "
                         "title does not open `%s` is not held to the release-only section set, "
                         "scope line and merge-instruction rule; pass its title to get that.\n"
                         % RELEASE_TITLE_PREFIX)
    elif not release:
        sys.stdout.write("pr-body-lint: this is NOT a release PR (its title does not open `%s`), "
                         "so the release-only rules — the closed section set, the scope line and "
                         "the merge-instruction rule — are not applied: its section shape is "
                         "your repo's own PR template's. Every other rule is, on every PR.\n"
                         % RELEASE_TITLE_PREFIX)

    # The repo's declared extras are stated when they applied, for the same reason: a release body
    # that passes on a heading the IN table does not admit must show WHERE that admission came from.
    if release and release_headings:
        sys.stdout.write("pr-body-lint: this repo declares extra release sections in `%s`, each "
                         "admitted by its exact text: %s.\n"
                         % (RELEASE_HEADINGS_FILE, ", ".join("`## %s`" % h for h in release_headings)))

    if not found:
        if release:
            sys.stdout.write("pr-body-lint: %s meets `release-pr` SKILL.md § PR body.\n"
                             % args.label)
        else:
            sys.stdout.write("pr-body-lint: %s meets every rule a non-release PR body is held "
                             "to.\n" % args.label)
        return 0
    if release:
        sys.stdout.write("pr-body-lint: %s does NOT meet `release-pr` SKILL.md § PR body — write "
                         "it for the software installer.\n" % args.label)
    else:
        sys.stdout.write("pr-body-lint: %s does NOT meet the rules every PR body is held to.\n"
                         % args.label)
    for f in found:
        where = "line %d" % f.line if f.line else "the body"
        sys.stdout.write("\n  %s · %s\n    %s\n" % (where, f.rule, f.message))
        if f.text.strip():
            sys.stdout.write("    > %s\n" % f.clipped())
    if release:
        sys.stdout.write("\nThe standard, and the home it names for everything it keeps out, are "
                         "in `skills/release-pr/SKILL.md § PR body` in your coord install. Nothing "
                         "is dropped by fixing this — only the home moves.\n")
    else:
        sys.stdout.write("\nThe OUT table a `banned-opener` or `live-state-reading` finding cites "
                         "is `skills/release-pr/SKILL.md § PR body`'s, in your coord install; every "
                         "other finding names the document that owns its rule.\n")
    return 1


if __name__ == "__main__":
    # ⛔ THE CRASH FLOOR: an exception no handler above anticipated exits 2, the fault status, never
    # 1 (card#12387). Python's own exit for an uncaught exception is 1 — this program's FINDING
    # status — so a crash read as "the body is wrong" and sent its author to fix a body nobody had
    # judged. The traceback is still printed, so the cause stays visible. Only `Exception` is
    # caught: `SystemExit` (argparse's own exit 2 included) and `KeyboardInterrupt` pass through.
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception:
        traceback.print_exc()
        sys.stderr.write("pr-body-lint: the program CRASHED (traceback above), so no verdict was "
                         "reached — exit 2, a fault, not a finding about the body.\n")
        sys.exit(2)
