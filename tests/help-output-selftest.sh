#!/usr/bin/env bash
# help-output-selftest.sh — deterministic, network-free checks that every CLI's `--help`
# prints its WHOLE header comment and nothing below it, and that no bin/ carrying `--help`
# escapes this file's scope unnoticed.
#
# WHY THIS FILE EXISTS. Both release movers printed their header with a FIXED line range
# (`sed -n '2,20p'`). A fixed range is silently wrong in both directions: it truncates once
# the header outgrows it, and it leaks code once the header shrinks. promote-released-cards'
# header reached 43 lines while the range still said 20, so `--help` stopped at line 20 and
# never reached `Usage:` at line 35 — the single block a `--help` user most needs. Nothing
# caught it because nothing asserted the output at all (card#5145, roundtable #161 item 2).
#
# The assertion is deliberately an EQUALITY on the line count, not a range or a
# contains-check. A "prints at least N lines" or "contains Usage:" assertion passes while
# truncating everything after the match — that is exactly the class of assertion that let
# this survive. Comparing against the file's own contiguous-leading-comment count means the
# check re-derives the expected length from the file on every run, so it cannot go stale as
# the header grows.
#
# The LEAK direction is not hypothetical: agent-board-toolkit-runtime-check, missed by that
# card's sibling audit, carried `sed -n '2,30p'` over a 28-line header and printed
# `set -euo pipefail` as its last --help line (card#5334).
#
# WHY THE REGISTRY ITSELF IS GATED (card#5339). The repair for that missed bin was to append
# its name to the CLIS array below — a HAND-MAINTAINED registry, i.e. the very mechanism that
# missed it, so the N+1th bin to grow a `--help` would be missed identically. CLIS is now one
# half of a COMPLETENESS assertion: every entry of bin/ whose source carries `--help` must
# appear in CLIS or in EXCLUDED, and each exclusion is verified rather than trusted.
#
# DERIVING CLIS FROM THE HEADER IDIOM WOULD BE WORSE THAN THE STATUS QUO, which is why it is
# not done: a CLI regressing from the `awk` form back to a `sed -n` range would drop OUT of a
# grep-derived required set, and the suite would go green on the exact defect it exists to
# catch. The completeness form has no such hole — the REQUIRED set is the hand-written
# registry, and the derived scan can only ever add names that must be answered for. The same
# idiom grep appears below, but only to CHALLENGE an exclusion, a direction in which it can
# add a member and never silently drop one.
#
# WHY THE CHANNEL IS ASSERTED (card#5337). Which STREAM help lands on is a property of every
# bin here, not only of the ones printing a header, so it is asserted over the whole registry —
# CLIS and EXCLUDED alike. adopt-to-dl baked `>&2` into usage() itself, so `adopt-to-dl --help
# > f` produced an EMPTY f at rc 0: a false success reading as "this tool has no help" to any
# caller redirecting stdout. The channel is the CALLER's to choose because the two uses differ —
# a requested `--help` is the requested OUTPUT (pipeable, pageable), while usage-after-a-bad-
# argument is diagnostic. Moving the redirect out to the four error arms is what makes both
# true at once, and that is exactly why the ERROR direction is asserted too: the redirect now
# lives at each call site, so a later tidy dropping one `>&2` would put diagnostics on stdout
# with nothing to notice. That leg is adopt-to-dl-only — a population of one, deliberately,
# because it guards the regression THIS change creates rather than a property of the registry.
#
# WHAT A GREEN RUN HERE ACTUALLY PROVES — the weakest property the assertions support:
#   * for each CLIS member, that its `--help` reproduces that file's own contiguous header
#     exactly. Nothing about whether the header's PROSE is accurate, current, or complete.
#   * that every bin/ file MENTIONING `--help` is named in one of the two lists — NOT that
#     every bin offering help is. A bin dispatching help under some other spelling entirely
#     (`-?`, a `help` subcommand, `--usage`) mentions no `--help` and stays invisible here.
#   * for each EXCLUDED member, only that it does not use the contiguous-header idiom. It says
#     nothing about whether that bin's help is correct or complete.
#   * for every REGISTRY member, that `--help` exits 0 with output on stdout and stderr silent.
#     Nothing about that output's CONTENT — for the three EXCLUDED bins the channel is the only
#     thing asserted about their help at all — and nothing about any spelling other than
#     `--help`, nor about the other five bins' ERROR channel.
#   * for adopt-to-dl alone, that ONE rejected shape — an unknown flag — exits 2 with the
#     diagnostic on stderr and stdout empty. Its other three error arms are not exercised.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

BINDIR="$HERE/../bin"
_mktmp_scratch

# The CLIs whose --help prints a leading comment header.
CLIS=(promote-released-cards release-pr-body agent-board-toolkit-runtime-check)

# Bins that carry `--help` and are deliberately NOT asserted above. Each entry states WHY, and
# the reason is machine-checked below — an exclusion here is a claim, not a licence. A one-line
# usage string can never satisfy a line-count equality against an 18–43 line header, so the
# assertion simply does not apply to these three.
EXCLUDED=(
    adopt-to-dl             # usage() one-liner
    dl-a0-backfill-triaged  # $USAGE one-liner
    dl-a1-register-field    # $USAGE one-liner
)

# _registry — the two hand-written lists as one C-collated set: what this file answers for.
_registry() { printf '%s\n' "${CLIS[@]}" "${EXCLUDED[@]}" | LC_ALL=C sort; }

# _help_bins <dir> — the basename of every regular file under <dir> whose source mentions
# `--help` AT ALL, C-collated. Deliberately the broadest matcher available, in both respects:
#   * NO comment filter. A bin whose header merely discusses `--help` reads as unaccounted and
#     goes red until someone names it — noisy in the safe direction. A filter that guessed
#     wrong would drop a real help arm silently, which is the failure this file exists to stop.
#   * NOT the `-h|--help)` case-arm shape. A bin dispatching help as `--help)` alone, from an
#     `if`, or behind an extra alias would be invisible to that pattern and slip through green.
# Directories are skipped because a directory has no source to scan — the OPPOSITE of
# readme-bin-coverage-selftest.sh's _public_bins, which must NOT skip them (a non-`_` directory
# there is a real entry with no README row). Same directory, two checks, two correct answers;
# do not "harmonize" them.
_help_bins() {
    local d="$1" f
    for f in "$d"/*; do
        [[ -f "$f" ]] || continue
        if grep -qF -- '--help' "$f"; then basename "$f"; fi
    done | LC_ALL=C sort
}

# header_lines <file>: the count of contiguous comment lines after the shebang — the
# authoritative expected length, re-derived from the file itself.
header_lines() { awk 'NR>1 { if (substr($0,1,1) == "#") c++; else exit } END { print c+0 }' "$1"; }

# _channel <cmd> <args...> — run a command and reduce it to `rc/stdout/stderr` occupancy. Both
# streams are reported in ONE record so every assertion using it carries its own presence
# witness: "stderr=empty" is only meaningful next to a "stdout=data" measured on the same run,
# which is what distinguishes a silent stream from a command that produced nothing at all (or
# never executed). Occupancy is `[ -s ]`, a byte-count test, not a command substitution — the
# latter strips trailing newlines, so a stream holding only "\n" would read as empty.
_channel() {
    local rc=0
    "$@" >"$TMP/ch.out" 2>"$TMP/ch.err" || rc=$?
    printf 'rc=%s stdout=%s stderr=%s' "$rc" \
        "$([ -s "$TMP/ch.out" ] && echo data || echo empty)" \
        "$([ -s "$TMP/ch.err" ] && echo data || echo empty)"
}

# The contiguous-header idiom, used ONLY to challenge an exclusion (see the header rationale).
HEADER_IDIOM="awk 'NR>1"

# ---------------------------------------------------------------------------
# Positive control FIRST. The completeness legs below are assertions of ABSENCE ("nothing
# unaccounted"), and an empty answer is indistinguishable from a scan that returned nothing at
# all — a moved bin/, a bad glob, or a grep that matched no file would make every one pass.
# ---------------------------------------------------------------------------
echo "== positive control — the bin/ --help scan carries real data =="
found="$(_help_bins "$BINDIR")"
eq "the bin/ --help scan is non-empty" "false" "$([ -z "$found" ] && echo true || echo false)"
# A named member, not a count: a count pins the check to a past value and goes stale as the
# toolkit grows, whereas a member that must be present re-derives nothing and cannot rot.
eq "…and contains a known member" "true" \
   "$(printf '%s\n' "$found" | grep -qx 'promote-released-cards' && echo true || echo false)"

echo "== every bin/ carrying --help is accounted for: CLIS ∪ EXCLUDED =="
# `comm` validates its inputs' order in the AMBIENT locale, so it is pinned to C alongside both
# producers, not merely for tidiness: en_US.UTF-8 ignores punctuation in its primary collation
# pass and orders `-`-bearing names differently from codepoint order.
eq "unaccounted bins with --help (add to CLIS, or to EXCLUDED with a reason)" "" \
   "$(LC_ALL=C comm -23 <(printf '%s\n' "$found") <(_registry))"
eq "registry names a bin that no longer carries --help (drop the entry)" "" \
   "$(LC_ALL=C comm -13 <(printf '%s\n' "$found") <(_registry))"

echo "== EXCLUDED is verified, not merely asserted =="
# The witnesses run first and on the same live tree: without them, "does not carry the idiom"
# would also pass for a grep that can never match anything.
for cli in "${CLIS[@]}"; do
    eq "witness: $cli DOES carry the contiguous-header idiom" "true" \
       "$(grep -qF -- "$HEADER_IDIOM" "$BINDIR/$cli" && echo true || echo false)"
done
for cli in "${EXCLUDED[@]}"; do
    _need -r "$BINDIR/$cli"
    eq "$cli is excluded on FORM: it does not carry the header idiom" "false" \
       "$(grep -qF -- "$HEADER_IDIOM" "$BINDIR/$cli" && echo true || echo false)"
done

echo "== --help goes to the CALLER's channel, over the WHOLE registry =="
# Over _registry(), not over CLIS + EXCLUDED written out again: the registry has one owner, so a
# name added to either list is channel-asserted without a second edit.
while read -r cli; do
    _need -x "$BINDIR/$cli"
    eq "$cli: --help ⇒ rc 0, help on stdout, stderr silent" \
       "rc=0 stdout=data stderr=empty" "$(_channel "$BINDIR/$cli" --help)"
done < <(_registry)

echo "== adopt-to-dl's ERROR channel is the other one (card#5337) =="
# Population of one on purpose — this guards the regression the fix introduces, not a registry
# property. The redirect moved out of usage() into the four error arms, so it is now droppable
# one call site at a time. Only the unknown-flag arm is exercised.
eq "adopt-to-dl: an unknown flag ⇒ rc 2, diagnostic on stderr, stdout silent" \
   "rc=2 stdout=empty stderr=data" "$(_channel "$BINDIR/adopt-to-dl" --nope)"

echo "== the header assertions, over CLIS =="
for cli in "${CLIS[@]}"; do
    bin="$BINDIR/$cli"
    _need -x "$bin"

    echo "== $cli --help =="
    out="$("$bin" --help)"
    got="$(printf '%s\n' "$out" | wc -l)"
    want="$(header_lines "$bin")"

    eq "$cli: --help prints the ENTIRE header (line-count equality)" "$want" "$got"
    eq "$cli: --help reaches the Usage: block"      "true"  "$(case "$out" in *"Usage:"*) echo true ;; *) echo false ;; esac)"
    # Everything below the header is implementation, not user-facing help. `set -euo
    # pipefail` is the first line after every header, so it is the canary for over-printing.
    eq "$cli: --help does not leak code past the header" "false" \
       "$(case "$out" in *"set -euo pipefail"*) echo true ;; *) echo false ;; esac)"
    # -h is the documented alias; assert it is the same output, not merely non-empty.
    eq "$cli: -h is identical to --help"            "true"  "$([ "$("$bin" -h)" = "$out" ] && echo true || echo false)"
done

# ---------------------------------------------------------------------------
# PROVE IT CAN FAIL. Each leg is pointed at a fixture carrying the exact defect it claims to
# catch. Without this, a check that answers "" for structural reasons reads identically to one
# that answered "" because the registry is complete.
# ---------------------------------------------------------------------------
echo "== prove-it-can-fail: an unaccounted bin carrying --help is REPORTED =="
mkdir -p "$TMP/bin-help/adir"
printf '%s\n' '    -h|--help) usage; exit 0 ;;' > "$TMP/bin-help/ghost-cli"
# An ACCOUNTED sibling, and a bin with no help at all: the first is the presence witness (it
# must NOT be reported, which is what shows the comparison ran against the real registry), the
# second proves the scan discriminates rather than listing the directory.
printf '%s\n' '    -h|--help) usage; exit 0 ;;' > "$TMP/bin-help/adopt-to-dl"
printf '%s\n' 'echo no flags here' > "$TMP/bin-help/quiet-cli"
eq "the scan sees exactly the --help-carrying files (a help-free file and a DIRECTORY are not)" \
   "$(printf 'adopt-to-dl\nghost-cli')" "$(_help_bins "$TMP/bin-help")"
eq "an unaccounted bin is named" "ghost-cli" \
   "$(LC_ALL=C comm -23 <(_help_bins "$TMP/bin-help") <(_registry))"
eq "the ACCOUNTED sibling is not named (witness: the comparison saw the registry)" "" \
   "$(LC_ALL=C comm -23 <(_help_bins "$TMP/bin-help") <(_registry) | grep -x 'adopt-to-dl' || true)"

echo "== prove-it-can-fail: a registry entry with no --help left is REPORTED =="
# The other direction, on a fixture holding only ONE of the registry's names: every other entry
# must come back as dropped, so the leg is proven able to be non-empty.
mkdir -p "$TMP/bin-gone"
printf '%s\n' '    -h|--help) usage; exit 0 ;;' > "$TMP/bin-gone/adopt-to-dl"
eq "a registry name absent from the scan is reported" "true" \
   "$(LC_ALL=C comm -13 <(_help_bins "$TMP/bin-gone") <(_registry) | grep -qx 'release-pr-body' && echo true || echo false)"
eq "the surviving entry is NOT reported (witness: the scan was read, not ignored)" "" \
   "$(LC_ALL=C comm -13 <(_help_bins "$TMP/bin-gone") <(_registry) | grep -x 'adopt-to-dl' || true)"

echo "== prove-it-can-fail: the exclusion challenge FIRES on a bin that adopts the idiom =="
# An EXCLUDED bin converting to the contiguous-header form must stop being excludable. Without
# this fixture the challenge above is a grep no live file makes true.
mkdir -p "$TMP/idiom"
printf '%s\n' "        -h|--help) awk 'NR>1 { print }' \"\$0\"; exit 0 ;;" > "$TMP/idiom/converted"
eq "a converted bin trips the header-idiom discriminator" "true" \
   "$(grep -qF -- "$HEADER_IDIOM" "$TMP/idiom/converted" && echo true || echo false)"

echo "== prove-it-can-fail: both channel predicates REPORT the shapes they exist to catch =="
# Two fixtures, each carrying exactly one of the two defects, and each therefore the OTHER's
# presence witness: every run below asserts BOTH predicates, so the passing one is observed
# present on the same fixture that fails the other. A fixture failing both would prove nothing —
# it would be indistinguishable from a file that does not execute.
#
# These are synthetic rather than `git show <rev>:bin/adopt-to-dl`: the real pre-fix binary IS a
# faithful negative control and was run as one by hand, but naming a revision pins the check to
# a history position that a squash-merge invalidates, and the extracted file needs
# _kb-board-lib.sh copied alongside it or it exits 1 before reaching any argument.
mkdir -p "$TMP/channel"
cat > "$TMP/channel/help-on-stderr" <<'FIXTURE'
#!/usr/bin/env bash
usage() { echo "usage: help-on-stderr <x>" >&2; }
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    *) echo "help-on-stderr: unknown flag '${1:-}'" >&2; usage; exit 2 ;;
esac
FIXTURE
cat > "$TMP/channel/usage-on-stdout" <<'FIXTURE'
#!/usr/bin/env bash
usage() { echo "usage: usage-on-stdout <x>"; }
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    *) echo "usage-on-stdout: unknown flag '${1:-}'" >&2; usage; exit 2 ;;
esac
FIXTURE
chmod +x "$TMP/channel/help-on-stderr" "$TMP/channel/usage-on-stdout"

# Fixture 1 — usage() bakes in `>&2`, i.e. adopt-to-dl before this fix. The help predicate must
# go red; the error predicate is unaffected, which is why the fix could not be verified by the
# error path alone.
eq "the pre-fix shape FAILS the --help channel predicate" \
   "rc=0 stdout=empty stderr=data" "$(_channel "$TMP/channel/help-on-stderr" --help)"
eq "…while still SATISFYING the error predicate (witness: the fixture runs)" \
   "rc=2 stdout=empty stderr=data" "$(_channel "$TMP/channel/help-on-stderr" --nope)"

# Fixture 2 — the regression this change makes possible: usage() prints on stdout (correct) and
# an error arm calls it without the redirect, putting the diagnostic's own usage on stdout.
eq "a dropped error-arm redirect FAILS the error-channel predicate" \
   "rc=2 stdout=data stderr=data" "$(_channel "$TMP/channel/usage-on-stdout" --nope)"
eq "…while still SATISFYING the --help predicate (witness: the fixture runs)" \
   "rc=0 stdout=data stderr=empty" "$(_channel "$TMP/channel/usage-on-stdout" --help)"

_summary "help-output-selftest"
