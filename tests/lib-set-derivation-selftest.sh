#!/usr/bin/env bash
# lib-set-derivation-selftest.sh — the set of bins that `source bin/_kb-board-lib.sh` is DERIVED,
# never listed, and this is what holds that true in the docs a consumer actually follows.
#
# WHY THIS FILE EXISTS. The set was enumerated in prose in four places (the lib header,
# `ADOPTION.md`, `docs/INSTALL.md` §6b, `docs/UPGRADE.md` §3) while `agent-board-toolkit-drift-check`
# derived the real one from the files. A vendor-by-copy consumer who follows a stale list copies a
# bin without the lib and gets an rc-1 "shared lib not found" refusal on EVERY invocation of it,
# `--help` included. That is not hypothetical and it is not a single miss:
#   * one copy omitted `adopt-to-dl` and `board-stats` — and `adopt-to-dl` calls `kb_parse_resp`,
#     so the omission was load-bearing;
#   * `gh-code-search` joined the set and reached exactly ONE of the four;
#   * the pass that deleted three of the four declared the class CLOSED — against a denominator
#     read out of its own plan document rather than re-derived from the tree — and `UPGRADE.md`
#     §3, the standing re-vendor recipe `INSTALL.md` §6b points consumers at, survived it naming
#     SIX bins where the derivation answered NINE.
# A list that must be re-synced by hand at every added bin is the defect. Three hand audits missed
# a copy of it; this file is the fourth attempt not being a hand audit.
#
# WHAT IT IS NOT. It does not test `agent-board-toolkit-drift-check` (that is
# `drift-check-fixture-selftest.sh`, which owns the premise that the anchored pattern still
# discriminates a real sourcer from a real standalone) and it does not test any bin's behaviour.
# It tests the DOCS against the tree, which is the axis neither of those can see: both of them
# keep the *pattern* honest, and neither can notice a prose list that has stopped agreeing with it.
#
# THE THREE LEGS:
#   1. Every published spelling of the derivation — anywhere in the repo — is the SAME spelling,
#      and running it answers the same set as the tree. A published command that answers NOTHING is
#      the worst case and the one that shipped: `'…"$KB_LIB"'` with the `$` unescaped is an ERE
#      anchor mid-pattern, so it can never match, and a reader who pastes it concludes that no bin
#      needs the lib — an empty result reading as an answer.
#   2. Each consumer-facing surface actually publishes it. Deleting a stale list is only half the
#      fix; a surface that names neither the set nor the way to derive it leaves the consumer
#      guessing, which is how a list grows back.
#   3. No consumer-facing surface enumerates the set in prose again.
#
# VERSION-SPECIFIC HISTORY IS DELIBERATELY OUT OF THE POPULATION for leg 3 — `docs/UPGRADE.md` §6
# and `docs/CHANGELOG.md` are append-only records of what was true AT a version, and a frozen
# at-that-version list cannot rot. (The v0.8.2 entry names six bins and says in its own words that
# the six is a fact about v0.8.2, pointing at §3 for the current set.) Leg 1 still covers them:
# history may not publish a derivation that does not work.
#
# ⛔ LEG 3'S UNIT IS THE LINE, AND THAT IS A STATED BOUND, not an oversight. In markdown a
# paragraph IS a line, so every consumer instruction in the surfaces below is scanned whole. In a
# shell comment block the prose is hard-wrapped, so an enumeration spread across two comment lines
# is invisible to it — `bin/_kb-board-lib.sh`'s own header narrates the past misses that way and
# passes. Widening the unit to the comment block was considered and rejected: it would report that
# narrative, which is a description of a defect rather than an instruction to copy anything, and a
# check that reds on its own explanation gets suppressed rather than obeyed. What is covered is
# what a vendoring consumer READS AND FOLLOWS; what is not is a wrapped historical aside.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

ROOT="$(cd "$HERE/.." && pwd)"
_need -r "$ROOT/bin/_kb-board-lib.sh"
_mktmp_scratch

# The reference derivation. It is the one spelling every surface must publish, and leg 1 is what
# keeps this copy from becoming a fifth thing that can disagree: a wrong pattern here answers the
# empty set and reds the non-empty premise below.
REF_PAT='^[[:space:]]*source "\$KB_LIB"'

# _derive <pattern> — the basenames the pattern selects out of bin/, C-collated, one per line.
# `-d skip` because `bin/` can hold a directory that is not a tool: a local `__pycache__` makes
# plain `grep … bin/*` exit 2 under `pipefail` on the developer's host and 0 in CI, which would
# make this file's verdict a property of whether someone had run the python helpers.
# The `|| true` is not decoration: a pattern that matches NOTHING is the state this file exists to
# catch, and under `set -e` + `pipefail` grep's rc 1 would kill the run at `got="$(_derive …)"`
# before the comparison it was about to fail. Found by mutating every published spelling at once.
_derive() {
    { grep -d skip -lE "$1" "$ROOT"/bin/* 2>/dev/null || true; } \
        | while read -r f; do basename "$f"; done | LC_ALL=C sort
}

REF_SET="$(_derive "$REF_PAT")"
REF_N="$(printf '%s' "$REF_SET" | grep -c . || true)"

# ---------------------------------------------------------------------------
echo "== premises — the derivation answers something, and it discriminates =="
# AN EMPTY REFERENCE SET WOULD MAKE EVERY COMPARISON BELOW PASS VACUOUSLY, which is the exact
# failure mode this file exists to catch, so it is asserted before anything is compared against it.
eq "the reference derivation selects at least one bin" "true" \
   "$([ "$REF_N" -ge 1 ] && echo true || echo false)"
# One positive and one negative, so a pattern that matched everything (or nothing) cannot pass.
# The general property — that this anchored pattern tracks a real `source` line — is owned by
# tests/drift-check-fixture-selftest.sh, against the same tool that uses it.
eq "…including a known sourcer"     "true"  "$(has 'kbcard' "$REF_SET")"
eq "…and excluding a known standalone" "false" "$(has 'promote-released-cards' "$REF_SET")"
echo "     (derived set, $REF_N bin(s): $(printf '%s' "$REF_SET" | tr '\n' ' '))"

# ---------------------------------------------------------------------------
echo "== leg 1 — every published spelling of the derivation runs, and answers the same set =="
# The population is every readable non-binary file in the repo, `.git` excluded: a derivation is
# dangerous wherever it is published, and scoping this to a doc list would reproduce the
# hand-kept-list defect one layer up.
_spellings() {
    grep -rIohE "grep -[lq]E '[^']*KB_LIB[^']*'" "$1" --exclude-dir=.git 2>/dev/null \
        | sed -E "s/^grep -[lq]E '//; s/'\$//" | LC_ALL=C sort -u
}
SPELLINGS="$(_spellings "$ROOT")"
N_SPELL="$(printf '%s' "$SPELLINGS" | grep -c . || true)"
eq "the derivation is published somewhere" "true" "$([ "$N_SPELL" -ge 1 ] && echo true || echo false)"
# ONE spelling, not N that happen to agree today: two spellings of one rule are two things that
# can drift apart, and the drift is invisible until a bin joins the set.
eq "…in exactly ONE spelling, repo-wide" "1" "$N_SPELL"
while IFS= read -r pat; do
    [[ -n "$pat" ]] || continue
    got="$(_derive "$pat")"
    eq "published spelling answers the derived set: ${pat:0:34}…" "$REF_SET" "$got"
done <<<"$SPELLINGS"

# THE CONTROL, pinned to the failure it guards (not a generic "can this loop fail"): the spelling
# that actually shipped. It parses, it runs, it exits 0 — and it selects NOTHING, so a reader who
# pastes it concludes no bin needs the lib.
mkdir -p "$TMP/broken"
printf 'see `grep -lE %s bin/*`\n' "'^[[:space:]]*source \"\$KB_LIB\"'" > "$TMP/broken/note.md"
BROKEN_PAT="$(_spellings "$TMP/broken")"
eq "control: the fixture publishes one spelling"        "1" "$(printf '%s' "$BROKEN_PAT" | grep -c . || true)"
eq "control: …it is the unescaped one"                  "true"  "$(has '"$KB_LIB"' "$BROKEN_PAT")"
eq "control: …it selects NOTHING, so leg 1 would red"   ""      "$(_derive "$BROKEN_PAT")"
eq "control: …which is not the reference set"           "false" "$([ "$(_derive "$BROKEN_PAT")" == "$REF_SET" ] && echo true || echo false)"

# ---------------------------------------------------------------------------
echo "== leg 2 + leg 3 — the consumer-facing surfaces =="
# THE SURFACES, and why exactly these: each one instructs someone about what to copy when they
# vendor. README's bin/ table is a different inventory of a different set and has its own gate
# (readme-bin-coverage-selftest.sh); the version-specific histories are out for the reason in the
# header. `docs/UPGRADE.md` is split at its own `## 6.` heading — derived, not a line number —
# because §1-§5 are live instructions and §6 is the frozen per-version record.
UPGRADE="$ROOT/docs/UPGRADE.md"
_upgrade_live() {
    local cut
    cut="$(grep -nE '^## 6\.' "$UPGRADE" | head -n 1 | cut -d: -f1)"
    [[ -n "$cut" ]] || { printf 'lib-set-derivation-selftest: docs/UPGRADE.md has no "## 6." heading\n' >&2; exit 1; }
    sed -n "1,$((cut - 1))p" "$UPGRADE"
}
_upgrade_live > "$TMP/upgrade-live.md"
eq "premise: the UPGRADE.md live region is non-empty" "true" \
   "$([ -s "$TMP/upgrade-live.md" ] && echo true || echo false)"
eq "…and stops before the version-specific record"    "false" \
   "$(has 'Version-specific upgrade actions' "$(cat "$TMP/upgrade-live.md")")"

SURFACES=("$ROOT/bin/_kb-board-lib.sh" "$ROOT/ADOPTION.md" "$ROOT/docs/INSTALL.md" "$TMP/upgrade-live.md")
SURFACE_NAMES=("bin/_kb-board-lib.sh" "ADOPTION.md" "docs/INSTALL.md" "docs/UPGRADE.md §1-§5")

# _publishes <file> — true when the file carries a spelling that answers the reference set.
_publishes() {
    local pat found=false
    while IFS= read -r pat; do
        [[ -n "$pat" ]] || continue
        [[ "$(_derive "$pat")" == "$REF_SET" ]] && found=true
    done < <(_spellings "$1")
    echo "$found"
}

# _enumerates <file> — the lines that both name the shared lib AND list two or more members of the
# derived set. TWO predicates, because either alone is noise: these bins are named in prose all
# over the repo for unrelated reasons, and the lib is discussed without listing anything. Two or
# more, not three, because a partial list is the defect in its most dangerous form — the one that
# looks like it was maintained. ONE member is fine and is deliberately allowed: every surface names
# `board-card-start` as the exits-0 variant, which is a statement about that bin, not a set.
_enumerates() {
    local f="$1" line n b
    while IFS= read -r line; do
        n=0
        while IFS= read -r b; do
            [[ -n "$b" ]] || continue
            case "$line" in *"$b"*) n=$((n + 1)) ;; esac
        done <<<"$REF_SET"
        [[ "$n" -ge 2 ]] && printf '%s\n' "$line"
    done < <(grep -e '_kb-board-lib' -e 'lib-sourcing' -e 'shared lib' "$f" 2>/dev/null) || true
}

for i in "${!SURFACES[@]}"; do
    name="${SURFACE_NAMES[$i]}"
    _need -r "${SURFACES[$i]}" "$name"
    eq "$name publishes a runnable derivation"  "true" "$(_publishes "${SURFACES[$i]}")"
    eq "$name enumerates the set nowhere"       ""     "$(_enumerates "${SURFACES[$i]}")"
done

# THE CONTROL FOR LEG 3, so an empty result above is a measurement and not an absence of scanning:
# the same predicate over a fixture carrying the line that actually shipped in `UPGRADE.md` §3.
cat > "$TMP/regrown.md" <<'FIXTURE'
cp ~/agent-board-toolkit/bin/_kb-board-lib.sh bin/   # + the shared lib IF you vendored a lib-sourcing bin (kbcard/next-dl/board-snapshot/board-card-start/dl-a0/dl-a1)
FIXTURE
eq "control: the regrown-list fixture IS reported" "true" \
   "$([ -n "$(_enumerates "$TMP/regrown.md")" ] && echo true || echo false)"
# And the other half of the pair — a line that names the lib and ONE member is not an enumeration,
# so the leg cannot be passing by reporting everything.
printf 'Without the shared lib, board-card-start reports the skip and still exits 0.\n' > "$TMP/one-name.md"
eq "control: …and a single-name line is NOT"       ""    "$(_enumerates "$TMP/one-name.md")"

_summary lib-set-derivation-selftest
