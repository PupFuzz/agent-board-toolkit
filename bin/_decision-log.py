#!/usr/bin/env python3
"""_decision-log.py — the ONE grammar of a `## DL-NNN` decision-log entry, and the collision
predicate CI runs over it.

Hoisted from agent-webhook-bridge's `bin/decision-log.py` (card#12338), where it was written for
card#7157 / card#9936 and measured on that repo's log, so that every repo whose CI refuses a
colliding DL number reads ONE definition of what an entry is. A second spelling of the grammar is
how a gate and an allocator come to disagree about what an entry is.

USAGE
    _decision-log.py check --head FILE [--base FILE --target FILE]
    _decision-log.py floor FILE
    _decision-log.py --tool-version

`bin/dl-collision-gate` is the CI entry point and the one most callers want: it derives the three
files from a `pull_request` checkout and maps each exit status below to a verdict. This file is the
predicate over three files already on disk, and the importable grammar. `floor` reads the same
heading grammar for an allocator, deliberately counting more than `check` does: `bin/next-dl`'s
offline max+1 scan runs it over each local log (`cmd_floor` owns what it counts, and why).

THE IMPORT CONTRACT — a cross-repo seam, declared here. `tests/decision-log-selftest.sh`
(§ import contract) path-loads this file and asserts both return shapes on one fixture; it checks
nothing about any consumer's use of them. A consumer that must agree with this grammar
(the bridge's `decision-log.py next`, whose post-claim veto reads local logs) path-loads THIS FILE
with `importlib.util.spec_from_file_location` — the filename carries a hyphen, so it is not
importable by name — and calls only these two names:
    header_scan(text)    -> (entries, skipped, unnumbered, unclosed_fence)
    header_numbers(text) -> entries
where `entries` is a list of `(number, lineno)` with leading zeros stripped, `skipped` the count of
`## DL-` heading lines inside code fences, `unnumbered` a list of `(stripped line, lineno)` for every
DL heading `_HEADER` rejects, and `unclosed_fence` the 1-based line a fence left OPEN at end of file
opened on (None when every fence closed) — a consumer reading `header_numbers` alone does not see
that a fence hid the rest of the log, and must read `header_scan` to. Every other name here is
private and may change.

EXIT CODES (check) — the contract a caller maps:
  0  clean
  2  usage, or an input that could not be read
  5  the log at head uses one number twice
  6  a number this change adds is already in use on the target branch
  7  this change adds a DL heading that carries no well-formed number
  8  a log read ends inside an UNCLOSED code fence, so its population cannot be measured

EXIT CODES (floor): 0 with the number on stdout (an empty line: the log holds none), 2 the log could
not be read, 8 it ends inside an unclosed code fence.
"""

import argparse
import re
import sys
from collections import Counter
from pathlib import Path

# A path-load caches bytecode beside its TARGET, i.e. into bin/, which consumers glob onto PATH
# (card#6871). The flag only governs loads made after it, so the entry point sets it.
sys.dont_write_bytecode = True

ABTK_TOOL_VERSION='0.51.0'

EXIT_USAGE = 2
EXIT_DUPLICATE_AT_HEAD = 5
EXIT_ALREADY_ON_TARGET = 6
EXIT_UNNUMBERED_AT_HEAD = 7
EXIT_UNCLOSED_FENCE = 8

# THE GRAMMAR, one rule per line class. Each was a hole in the bridge original (card#12338).
#
# A DL HEADING is a top-level ATX H2 whose text starts `DL-`: `_DL_H2`. Up to THREE spaces of
# indentation are allowed because CommonMark renders `   ## DL-342` as an H2 — an indent-blind
# grammar let that heading duplicate a number unseen. Four spaces or a tab make an indented code
# block, not a heading, and are not matched. NOT READ, and not pinned by any test: a setext H2
# (`DL-342` underlined with `---`) and an ATX H2 inside a blockquote (`> ## DL-342`) or a list item
# (`- ## DL-342`) — each renders as an H2, but a duplicate written that way passes at rc 0.
#
# A DL ENTRY is a DL heading whose `DL-` is followed by digits and then a word boundary: `_HEADER`.
# Deliberately not a search for `DL-\d+` anywhere: decision logs embed cross-repo references
# ("Mirrors kanban-board DL-196"), and a bare grep counts those as entries — measured on the
# bridge's log returning 197 when the real max was 188. Leading zeros are stripped by `int()`, so a
# log's two spellings (`## DL-288`, `## DL-0288`) name the same number and COLLIDE. A non-word
# character after the digits (`## DL-0344.1`, `## DL-0344-b`, `## DL-0344—`) still ends the number
# there, so those are DL-344.
#
# EVERY OTHER DL HEADING carries no well-formed number and is REFUSED when added (rc 7), never left
# uncounted: the placeholder `## DL-TBD`, a bare `## DL-`, and a suffixed `## DL-0344a` /
# `## DL-0344_x`, which the bridge original matched with neither its entry nor its placeholder
# pattern and so counted nowhere at rc 0. Classifying by "a DL heading `_HEADER` rejects", rather
# than by a second pattern for what a placeholder looks like, is what makes the two classes cover
# every DL heading, as defined above, between them.
_DL_H2 = re.compile(r"^ {0,3}##[ \t]+DL-")
_HEADER = re.compile(r"^ {0,3}##[ \t]+DL-0*(\d+)\b")
# `_HEADER` without its word boundary: the digits ANY DL heading starts with (`## DL-0344a` → 344).
# Read by `cmd_floor` alone, which counts every DL heading's digits (its docstring says why).
_LEADING_DIGITS = re.compile(r"^ {0,3}##[ \t]+DL-0*(\d+)")
# A fence opens on ``` or ~~~ and closes on a line starting with the same characters.
_FENCE = re.compile(r"^\s*(```|~~~)")


def header_scan(text: str):
    """(entries outside a fence, DL headings a fence hid, the unnumbered ones, unclosed-fence line).

    Lines inside a fenced code block are skipped: a decision entry that SHOWS what a header looks
    like is documentation, not a second entry. The fourth element keeps that skip from truncating
    the log silently: ONE unbalanced fence swallows every later heading, and the bridge original
    then exited 0 over the remainder with only a stderr warning. A fence still OPEN at
    end of file is returned as the line it opened on, and `check` refuses it (rc 8) instead of
    counting what is left. Bound: a STRAY fence that is later "closed" by another stray one
    balances, and the headings between them are skipped as quoted — every skip is still counted
    and stated, so that case is visible in the population line, not refused.
    """
    found = []
    unnumbered = []
    skipped = 0
    fence = None
    fence_line = None
    for lineno, line in enumerate(text.splitlines(), start=1):
        m = _FENCE.match(line)
        if m:
            if fence is None:
                fence, fence_line = m.group(1), lineno
            elif line.strip().startswith(fence):
                fence, fence_line = None, None
            continue
        if not _DL_H2.match(line):
            continue
        if fence is not None:
            skipped += 1
            continue
        m = _HEADER.match(line)
        if m is None:
            unnumbered.append((line.strip(), lineno))
        else:
            found.append((int(m.group(1)), lineno))
    return found, skipped, unnumbered, fence_line


def header_numbers(text: str):
    """`header_scan`'s entries alone, for callers that do not report a population."""
    return header_scan(text)[0]


def _read(path: str, label: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        print(f"decision-log: cannot read the {label} decision log {path}: {exc}", file=sys.stderr)
        raise SystemExit(EXIT_USAGE) from exc


def _scan(path: str, label: str):
    """`header_scan` over a file, stating on stderr what the fences hid from it."""
    entries, skipped, unnumbered, unclosed = header_scan(_read(path, label))
    if skipped:
        print(
            f"decision-log: WARNING: {skipped} `## DL-` line(s) in the {label} log {path} sit "
            "inside a code fence and were NOT counted. That is correct for an entry quoted as an "
            "example inside a fence that closes.",
            file=sys.stderr,
        )
    return entries, skipped, unnumbered, unclosed


def _population(entries, skipped, unnumbered) -> str:
    """The head log's denominator, printed beside every OK so it is never implicit."""
    total = len(entries) + skipped + len(unnumbered)
    return (
        f"population: {len(entries)} of {total} `## DL-` header lines counted, "
        f"{skipped} skipped inside code fences, {len(unnumbered)} carrying no well-formed number"
    )


def _refuse_unnumbered(path: str, unnumbered) -> bool:
    """Name every DL heading with no well-formed number handed in, and say whether there were any."""
    for text, lineno in unnumbered:
        print(
            f"decision-log: {path} line {lineno} opens a DL entry with NO WELL-FORMED NUMBER: {text}",
            file=sys.stderr,
        )
    if unnumbered:
        print(
            "decision-log: a placeholder or malformed header is not an identifier. Two changes can "
            "each write one, and neither the duplicate assertion nor the target-branch assertion "
            "can see it — both read `## DL-NNN`. Allocate a number with your repo's allocator "
            "(`next-dl <project>`) and renumber the entry, its CHANGELOG line, its commit messages "
            "and the PR title together.",
            file=sys.stderr,
        )
    return bool(unnumbered)


# The base and target logs are the TARGET BRANCH's, not the change's, so a change cannot clear
# them: one that closes the fence is refused on the same unclosed base/target as every other.
_TARGET_BRANCH_FENCE_REMEDY = (
    "Close the fence ON THE TARGET BRANCH, by a path this check does not block (a direct push, or "
    "a merge that bypasses it); a change that closes it is refused like any other, because this "
    "log is read from the target branch. Then update this change so it is checked against the new "
    "tip."
)


def _refuse_unclosed(path: str, label: str, unclosed) -> bool:
    if unclosed is None:
        return False
    remedy = _TARGET_BRANCH_FENCE_REMEDY if label in ("base", "target") else "Close the fence."
    print(
        f"decision-log: the {label} log {path} opens a code fence at line {unclosed} that is never "
        "closed. Every `## DL-` heading after that line renders as code and was NOT scanned, so no "
        f"verdict over this log would describe its real population. {remedy}",
        file=sys.stderr,
    )
    return True


def cmd_check(args) -> int:
    """Refuse a decision log that uses one DL number twice.

    TWO assertions, and the SECOND is why `--target` exists:

      1. The log AT HEAD must not repeat a number. Because the log is append-only, a change that
         mints a number its own base already carries shows up here — the entry it collides with
         is still in the file.

      2. A number this change ADDS (present at head, absent at `--base`) must not already be in
         use at `--target`, the LIVE tip of the branch being merged into. Assertion 1 is blind to
         this: if the target branch gained the colliding entry after the `--base` snapshot was
         taken, the file at head does not contain it either.

    WHAT `--base` MUST BE — a PAIRING with `--head`, not the fork point. "Present at head, absent
    at base" means "this change minted it" only while head is a snapshot containing base plus this
    change and nothing else. `bin/dl-collision-gate` satisfies that by passing the FIRST PARENT of
    the merge commit it runs on (`HEAD^1`, read by `bin/pr-base-snapshot`) while `--head` is the
    working tree at that same merge: ONE snapshot of the base branch by construction. Hand this
    command a base its head does not contain — the merge base, say — and `added` silently gains
    the base branch's OWN post-fork entries, which then read as this change's mints (rc 6 on an
    innocent change). NOT `github.event.pull_request.base.sha` either: GitHub does not refresh it
    on every `synchronize`, so it can LAG the base the merge was built on (measured on the
    bridge's PR #640, run 33598959720: `base.sha` 549c894 against a merge whose first parent was
    7a11085 — this command returned 6 on an innocent PR).

    STATED BOUND — the whole of what the guard claims, deliberately narrower than "no duplicate
    DL can be minted":

      * It does NOT catch two OPEN changes that each mint the same NEW number. Neither number is
        on the target branch yet and neither file contains the other's entry, so both pass. The
        second reds only when it is re-checked AFTER the first merges — a re-run, not an
        automatic consequence of the merge.
      * It reads three files. It knows nothing about a number claimed from a board counter but not
        yet written into any log, nor about a number the counter never issued.
      * The UNNUMBERED assertion refuses a placeholder this change ADDS, not every placeholder in
        the file — ON THE PAIRED `--base`/`--target` INVOCATION: one whose header line is
        IDENTICAL (after `strip()`) to one on the base snapshot is reported and allowed through,
        because refusing it would red every innocent PR cut after it landed. A change that EDITS
        an inherited placeholder's wording is adding one, and is refused. A HEAD-ONLY run refuses
        EVERY placeholder, because with no base it cannot tell added from inherited.
    """
    head_headers, head_skipped, head_unnumbered, head_unclosed = _scan(args.head, "head")
    if _refuse_unclosed(args.head, "head", head_unclosed):
        return EXIT_UNCLOSED_FENCE

    seen = {}
    for number, lineno in head_headers:
        if number in seen:
            print(
                f"decision-log: DL-{number} is used TWICE in {args.head} "
                f"(line {seen[number]} and line {lineno}).",
                file=sys.stderr,
            )
            return EXIT_DUPLICATE_AT_HEAD
        seen[number] = lineno

    if (args.base is None) != (args.target is None):
        # Half the inputs would run half the assertion and still print OK — a clean result over
        # an unnamed population. Neither, or both.
        print(
            "decision-log: --base and --target are given together or not at all "
            "(one alone would report OK having skipped assertion 2).",
            file=sys.stderr,
        )
        return EXIT_USAGE

    if args.base is None:
        if _refuse_unnumbered(args.head, head_unnumbered):
            return EXIT_UNNUMBERED_AT_HEAD
        print(f"OK: {args.head} carries {len(head_headers)} DL entries, no number twice.")
        print(f"({_population(head_headers, head_skipped, head_unnumbered)})")
        print("(no --base/--target given — the target-branch assertion did not run)")
        return 0

    base_entries, _, base_unnumbered, base_unclosed = _scan(args.base, "base")
    target_entries, _, _, target_unclosed = _scan(args.target, "target")
    # A truncated base INVENTS mints (every hidden number reads as added); a truncated target
    # HIDES the collision assertion 2 exists to see. Either way the verdict is not a measurement.
    if _refuse_unclosed(args.base, "base", base_unclosed) | _refuse_unclosed(args.target, "target", target_unclosed):
        return EXIT_UNCLOSED_FENCE
    base_numbers = {n for n, _ in base_entries}
    target_numbers = {n for n, _ in target_entries}

    # COUNTED, not set-membership: a change that adds a SECOND copy of a placeholder heading
    # already on base is adding one, and a set would read both copies as inherited.
    budget = Counter(text for text, _ in base_unnumbered)
    added_unnumbered = []
    for text, lineno in head_unnumbered:
        if budget[text]:
            budget[text] -= 1
            continue
        added_unnumbered.append((text, lineno))
    if _refuse_unnumbered(args.head, added_unnumbered):
        return EXIT_UNNUMBERED_AT_HEAD

    added = [(n, lineno) for n, lineno in head_headers if n not in base_numbers]
    collisions = [(n, lineno) for n, lineno in added if n in target_numbers]
    if collisions:
        for number, lineno in collisions:
            print(
                f"decision-log: DL-{number} (added at {args.head} line {lineno}) is "
                f"ALREADY IN USE on the target branch.",
                file=sys.stderr,
            )
        return EXIT_ALREADY_ON_TARGET

    added_desc = ", ".join(f"DL-{n}" for n, _ in added) if added else "none"
    print(
        f"OK: this change adds {len(added)} DL entries ({added_desc}); "
        "no number it adds is already in use on the target branch, and the log "
        "at head uses no number twice."
    )
    print(f"({_population(head_headers, head_skipped, head_unnumbered)})")
    return 0


def cmd_floor(args) -> int:
    """Print the highest DL number a max+1 allocator must stay above, read from one local log.

    The digits of EVERY DL heading (`_DL_H2`'s indentation rule), fenced or not, well-formed or
    not. An allocator that over-counts costs a gap in the sequence; one that under-counts re-mints
    a number already in use. So `floor` is deliberately WIDER than `check`'s entries: it does not
    apply the fence skip, because `_FENCE` also matches lines that open no fence (a paragraph
    starting with an inline code span, a backtick run indented as code), and two such lines would
    hide every real heading between them. It counts the digits of a heading carrying no
    well-formed number (`## DL-0344a` adds 344), which may be the entry a number was meant for. A
    placeholder with no digits (`## DL-TBD`) adds nothing and is not refused, since it is what an
    author writes before allocating. A log ending inside an unclosed fence is refused (rc 8): the
    gate refuses the same log, so a number minted over it could not land as written.
    """
    text = _read(args.log, "local")
    _, _, unnumbered, unclosed = header_scan(text)
    if unclosed is not None:
        print(
            f"decision-log: the local log {args.log} opens a code fence at line {unclosed} that is "
            "never closed. dl-collision-gate refuses a log in that state, so a number minted over it "
            "could not land as written. Close the fence.",
            file=sys.stderr,
        )
        return EXIT_UNCLOSED_FENCE
    for heading, lineno in unnumbered:
        m = _LEADING_DIGITS.match(heading)
        if m:
            print(
                f"decision-log: {args.log} line {lineno} carries no well-formed DL number ({heading}); "
                f"its DL-{int(m.group(1))} is counted toward the floor anyway.",
                file=sys.stderr,
            )
    numbers = [int(m.group(1)) for m in map(_LEADING_DIGITS.match, text.splitlines()) if m]
    print(max(numbers) if numbers else "")
    return 0


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    # Answered before anything else is parsed or read, so a vendored copy can say what it is.
    if argv == ["--tool-version"]:
        print(ABTK_TOOL_VERSION)
        return 0
    parser = argparse.ArgumentParser(
        prog="_decision-log.py",
        description="Refuse a decision log that reuses a DL number (see the module docstring).",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    p_check = sub.add_parser("check", help="refuse a decision log that uses one number twice")
    p_check.add_argument("--head", required=True, help="the decision log as this change leaves it")
    p_check.add_argument(
        "--base",
        help="the decision log at the snapshot --head is the merge of: in CI the FIRST PARENT of "
        "that merge commit (bin/pr-base-snapshot), NOT the merge base and NOT the pull_request "
        "event's base.sha",
    )
    p_check.add_argument("--target", help="the decision log at the live tip of the target branch")
    p_check.set_defaults(func=cmd_check)
    p_floor = sub.add_parser("floor", help="print the highest DL number one local log holds")
    p_floor.add_argument("log", help="the decision log to read")
    p_floor.set_defaults(func=cmd_floor)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
