#!/usr/bin/env bash
# pipeline-free-match-selftest.sh — the prelude's `has_line` answers whole-line membership
# correctly on a payload where the `| grep -qx` pipeline it replaces answers WRONG (card#7175).
#
# THE DEFECT, stated as a mechanism. Under `set -o pipefail`:
#
#     <producer> | grep -qx "$needle" && echo true || echo false
#
# `grep -q` exits the instant it matches. Its upstream is usually still writing, so the writer
# gets SIGPIPE, `pipefail` promotes that rc 141 to the PIPELINE's status, and the `&& echo true`
# tail reports a MATCH as `false`. The verdict is inverted — not an error, a wrong answer, at a
# call site whose reader has no way to tell. It cost a CI red this cycle:
# `lib-set-derivation-selftest.sh` leg 3 was green on five consecutive local runs and red in CI
# on the same commit, once a second multi-KB `[Unreleased]` entry pushed the payload over the
# pipe buffer.
#
# ⚑ WHAT THE DISCRIMINATOR ACTUALLY IS — and what it is NOT. The card that filed this class, and
# a comment in `fetch-board-cards-caller-claims-selftest.sh`, both said the hazard needs an
# EXTERNAL upstream writer, because "a bash printf/echo BUILTIN does not die on SIGPIPE (rc 0
# over a 5MB body)". That is false, and this file is where it is pinned false: bash forks a
# subshell for a builtin in a pipeline, and that subshell takes SIGPIPE like any other process.
#
# The real conditions are TWO, and both must hold:
#   (a) `grep -q` LEAVES EARLY — the match is near the start of the stream, so the reader is gone
#       while the writer still has bytes to push. A match at the END means grep read everything
#       and exited after the writer did: no closed pipe, no signal, rc 0.
#   (b) the writer still has MORE THAN THE PIPE BUFFER (64 KiB) left to write when that happens.
#       Under the buffer the whole payload is absorbed and the writer exits 0 regardless.
#
# ⛔ AND THAT IS EXACTLY HOW THE FALSE CLAIM SURVIVED — the original "rc 0 over a 5MB body"
# measurement is reproducible, with the needle at the END of the body. It is a real measurement
# of a case where condition (a) does not hold, reported as a fact about the shape. A control
# whose fixture cannot trigger the condition it tests reports clean and teaches the wrong rule;
# it then propagated from that comment into the class card and into the brief for this fix before
# anyone re-measured it. So every case below pins the AXIS it moves, one at a time — position at
# fixed size, size at fixed position — and asserts PIPESTATUS rather than the pipeline's rc
# alone, so the reader can see WHICH stage died instead of inferring it.
#
# THE FIX, and why it is not "use a herestring". `has_line` runs no pipeline AND no subprocess —
# it is a `case` glob over the text with the newline sentinels made explicit — so there is no
# writer to signal and no rc to promote. A herestring would also close the window, but it still
# forks a `grep`; the point of one owner is that the next author cannot re-open the window by
# reaching for the idiom that reads most naturally.
#
# WHAT THIS FILE DOES NOT CLAIM. It is a control battery for one primitive, not a census: it
# does not enumerate the suite's remaining `| grep -q` sites and it is not a gate on new ones.
# The per-site migration and the remaining population are recorded on card#7175.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
_mktmp_scratch

# ---------------------------------------------------------------------------
# The fixture. NEEDLE ON LINE 1 is load-bearing: the reader has to be able to leave early, or
# there is no closed pipe to meet and the whole battery measures nothing. SIZE is the other
# half — see the pipe-buffer assertions below.
# ---------------------------------------------------------------------------
NEEDLE='MATCH-ME'
# _filler <lines> — bulk that carries no needle.
_filler() { local i; for i in $(seq 1 "$1"); do printf 'filler-line-%s-padding-padding-padding\n' "$i"; done; }

# FOUR fixtures, one per cell of (match position) × (payload size). The pair that differs on ONE
# axis is what makes each verdict attributable; a single big-early fixture would red and prove
# only that SOMETHING about it is hazardous.
BIG_EARLY="$TMP/big-early.txt";  { printf '%s\n' "$NEEDLE"; _filler 20000; } > "$BIG_EARLY"
BIG_LATE="$TMP/big-late.txt";    { _filler 20000; printf '%s\n' "$NEEDLE"; } > "$BIG_LATE"
SMALL_EARLY="$TMP/small-early.txt"; { printf '%s\n' "$NEEDLE"; _filler 10; } > "$SMALL_EARLY"
SMALL_LATE="$TMP/small-late.txt";   { _filler 10; printf '%s\n' "$NEEDLE"; } > "$SMALL_LATE"
BIG_EARLY_TEXT="$(cat "$BIG_EARLY")"
BIG_LATE_TEXT="$(cat "$BIG_LATE")"
SMALL_EARLY_TEXT="$(cat "$SMALL_EARLY")"

_bytes() { wc -c < "$1" | tr -d ' '; }

# The 64 KiB pipe buffer is half the mechanism, so the fixtures' sizes are asserted rather than
# assumed. A "large" fixture that quietly shrank under the buffer would turn the whole battery
# into a vacuous pass — which is the precise failure this file exists to have caught.
echo "== the fixtures straddle the 64 KiB pipe buffer, and each carries the needle where it claims =="
for _f in "$BIG_EARLY" "$BIG_LATE"; do
    eq "$(basename "$_f") is past the pipe buffer" "true" \
       "$([[ "$(_bytes "$_f")" -gt 65536 ]] && echo true || echo false)"
done
for _f in "$SMALL_EARLY" "$SMALL_LATE"; do
    eq "$(basename "$_f") is inside the pipe buffer" "true" \
       "$([[ "$(_bytes "$_f")" -lt 65536 ]] && echo true || echo false)"
done
eq "the EARLY fixtures really do carry the needle on line 1" "true" \
   "$([[ "$(head -1 "$BIG_EARLY")" == "$NEEDLE" && "$(head -1 "$SMALL_EARLY")" == "$NEEDLE" ]] && echo true || echo false)"
eq "the LATE fixtures really do carry it on the LAST line"   "true" \
   "$([[ "$(tail -1 "$BIG_LATE")" == "$NEEDLE" && "$(tail -1 "$SMALL_LATE")" == "$NEEDLE" ]] && echo true || echo false)"

# _piped <file> — the construct being retired, EXTERNAL writer, spelled as the call sites did.
_piped() { ( set -o pipefail; cat "$1" | grep -qx "$NEEDLE" && echo true || echo false ); }
# _piped_builtin <text> — the same construct with a bash BUILTIN as the writer.
_piped_builtin() { ( set -o pipefail; printf '%s\n' "$1" | grep -qx "$NEEDLE" && echo true || echo false ); }
# _stat <file> / _stat_builtin <text> — PIPESTATUS, so a case names WHICH stage died. `grep -q`
# is stage 2 and answers 0 (it matched) in every cell below; stage 1 is the whole story.
_stat()         { ( set -o pipefail; cat "$1" | grep -qx "$NEEDLE"; echo "${PIPESTATUS[*]}" ) 2>/dev/null; }
_stat_builtin() { ( set -o pipefail; printf '%s\n' "$1" | grep -qx "$NEEDLE"; echo "${PIPESTATUS[*]}" ) 2>/dev/null; }

# ---------------------------------------------------------------------------
echo "== CONTROL 1 (positive) — the retired construct reports a MATCH as a NON-MATCH =="
# This is the assertion that makes every other one meaningful: it watches the defect happen on
# this host, on this bash, right now. If it ever flips to 'true', the battery below has stopped
# being able to fail and this file says so here rather than passing quietly.
eq "early match in a large body: the pipeline says NO to a text that DOES contain the line" \
   "false" "$(_piped "$BIG_EARLY")"
eq "…and PIPESTATUS names the WRITER as the one that died — grep matched fine" "141 0" \
   "$(_stat "$BIG_EARLY")"
eq "has_line answers the SAME question correctly on the SAME text" "true" \
   "$(has_line "$NEEDLE" "$BIG_EARLY_TEXT")"

# ---------------------------------------------------------------------------
echo "== CONTROL 2 (negative) — a genuine non-match still reports a non-match =="
# A helper that answered 'true' unconditionally would satisfy Control 1 and be strictly worse
# than the defect. These are the assertions that forbid it, at both fixture sizes and against
# the three ways a near-miss can look.
eq "a line that is absent: false (large text)"  "false" "$(has_line 'NOT-IN-THERE' "$BIG_EARLY_TEXT")"
eq "a line that is absent: false (small text)"  "false" "$(has_line 'NOT-IN-THERE' "$SMALL_EARLY_TEXT")"
eq "a needle that is only a SUBSTRING of a line is NOT a whole-line match" "false" \
   "$(has_line 'filler-line-7' "$BIG_EARLY_TEXT")"
eq "a needle that is a strict PREFIX of the matching line is not a match" "false" \
   "$(has_line 'MATCH' "$BIG_EARLY_TEXT")"
eq "a needle that EXTENDS the matching line is not a match" "false" \
   "$(has_line 'MATCH-ME-TOO' "$BIG_EARLY_TEXT")"
eq "the empty text contains no line"            "false" "$(has_line "$NEEDLE" "")"
# The negative side has to be able to fail too: the same needle against a text that DOES carry
# it must come back true, or 'false' above would be what a broken helper returns for everything.
eq "witness: the needles above are only absent because the TEXT lacks them" "true" \
   "$(has_line 'filler-line-7-padding-padding-padding' "$BIG_EARLY_TEXT")"

# ---------------------------------------------------------------------------
echo "== CONTROL 3 (discrimination) — early-match-in-a-large-body reds; late match or small body does not =="
# The half the class item got wrong. Each pair moves ONE axis, so the verdict is attributable to
# that axis and not to "something about the big fixture".
#
# AXIS 1 — MATCH POSITION, size held at large. This pair is the whole reason the original 5MB
# rc-0 measurement was not evidence: it was taken in the LATE cell and reported as a fact about
# the writer.
eq "external writer, LARGE body, LATE match: the pipeline is correct — grep never left early" \
   "true"  "$(_piped "$BIG_LATE")"
eq "…and nothing died: PIPESTATUS is clean, so there was no SIGPIPE to promote" "0 0" \
   "$(_stat "$BIG_LATE")"
eq "external writer, LARGE body, EARLY match: the same pipeline, one axis moved, is WRONG" \
   "false" "$(_piped "$BIG_EARLY")"

# AXIS 2 — PAYLOAD SIZE, position held at early.
eq "external writer, SMALL body, EARLY match: correct — the whole payload fits the pipe buffer" \
   "true"  "$(_piped "$SMALL_EARLY")"
eq "…and PIPESTATUS is clean there too"                                          "0 0" \
   "$(_stat "$SMALL_EARLY")"

# AXIS 3 — WRITER CLASS, position and size held at (early, large). This is the pair that pins
# the relayed rule FALSE: a bash builtin is forked into a subshell and takes SIGPIPE identically.
eq "BUILTIN writer, SMALL body, EARLY match: correct (this is why the shape survives review)" \
   "true"  "$(_piped_builtin "$SMALL_EARLY_TEXT")"
eq "BUILTIN writer, LARGE body, EARLY match: WRONG — a printf upstream is not safe, only untested" \
   "false" "$(_piped_builtin "$BIG_EARLY_TEXT")"
eq "…and PIPESTATUS shows the BUILTIN's own subshell took the signal, exactly as cat did" "141 0" \
   "$(_stat_builtin "$BIG_EARLY_TEXT")"
eq "BUILTIN writer, LARGE body, LATE match: correct — position, not writer class, decided it" \
   "true"  "$(_piped_builtin "$BIG_LATE_TEXT")"

# And the fix is indifferent to every axis the defect turns on, because there is no writer.
eq "has_line: correct on small+early" "true" "$(has_line "$NEEDLE" "$SMALL_EARLY_TEXT")"
eq "has_line: correct on large+early" "true" "$(has_line "$NEEDLE" "$BIG_EARLY_TEXT")"
eq "has_line: correct on large+late"  "true" "$(has_line "$NEEDLE" "$BIG_LATE_TEXT")"

# ---------------------------------------------------------------------------
echo "== the needle is matched LITERALLY (glob metacharacters are not patterns) =="
# `has_line` is a `case` glob, so an unquoted needle would silently become a pattern — the one
# way this helper could answer 'true' for a line it does not actually contain.
GLOBS="$(printf 'a*b\n[abc]\nliteral?\nx\n')"
eq "a needle containing * matches its literal line"     "true"  "$(has_line 'a*b' "$GLOBS")"
eq "…and does NOT match some other line by globbing"    "false" "$(has_line 'a*b' "$(printf 'aXXXb\n')")"
eq "a needle containing a bracket set matches literally" "true"  "$(has_line '[abc]' "$GLOBS")"
eq "…and the bracket set does not match one of its members" "false" \
   "$(has_line '[abc]' "$(printf 'a\n')")"
eq "a needle containing ? does not match a one-char difference" "false" \
   "$(has_line 'literal?' "$(printf 'literalX\n')")"

# ---------------------------------------------------------------------------
echo "== first, last and only lines are all members (no sentinel is eaten) =="
# The implementation wraps the text in explicit newlines; these pin that the wrapping does not
# lose the boundaries, which is the one way a whole-line test silently under-matches.
THREE="$(printf 'first\nmiddle\nlast\n')"
eq "the first line is a member"  "true" "$(has_line 'first'  "$THREE")"
eq "a middle line is a member"   "true" "$(has_line 'middle' "$THREE")"
eq "the last line is a member"   "true" "$(has_line 'last'   "$THREE")"
eq "a single-line text's only line is a member" "true" "$(has_line 'only' "$(printf 'only\n')")"
eq "an EMPTY line inside the text is found"     "true" "$(has_line '' "$(printf 'a\n\nb\n')")"

_summary "pipeline-free-match-selftest"
