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
#   2. Each of a NAMED FOUR surfaces actually publishes it. Deleting a stale list is only half the
#      fix; a surface that names neither the set nor the way to derive it leaves the consumer
#      guessing, which is how a list grows back. The four are hand-kept and that is legitimate:
#      "this surface OWES the reader a derivation" is an editorial obligation, not a property of
#      any file, so the tree cannot derive it. It is a FLOOR — a surface missing from it is one
#      nobody promised anything about, and leg 3 does not read it.
#   3. NO file in the repo enumerates the set in prose again — the population is derived on every
#      run (the same one leg 1 uses), minus two carve-outs, each named and reasoned at the leg.
#
# ⛔ LEG 3 ONCE RAN OVER LEG 2'S FOUR PATHS WHILE CLAIMING THE REPO, which is the same defect this
# file exists to close, rebuilt one layer up: a gate against hand-kept lists, carrying one. A fifth
# consumer-facing surface joined SILENTLY — measured, by appending a re-vendor sentence naming four
# bins to `README.md`: this file stayed rc 0, and so did `readme-bin-coverage-selftest`, whose own
# gate compares names only. Leg 3's population is now the tree, so an unnamed file is IN and reports;
# only a carve-out with a reason is out. The FIRST closure of this class was against an inherited
# denominator; the SECOND shipped a gate whose own denominator was fixed at four. Both are recorded
# in `docs/CONSOLIDATION-PLAN.md` rather than smoothed over.
#
# VERSION-SPECIFIC HISTORY IS DELIBERATELY OUT OF THE POPULATION for leg 3 — `docs/UPGRADE.md` §6,
# `docs/CHANGELOG.md` and `CLAUDE.md`'s release-snapshot table are append-only records of what was
# true AT a version, and a frozen at-that-version list cannot rot. (The v0.8.2 entry names six bins
# and says in its own words that the six is a fact about v0.8.2, pointing at §3 for the current
# set.) Leg 1 still covers them: history may not publish a derivation that does not work.
#
# ⛔ LEG 3'S UNIT IS THE LINE, AND THAT IS A STATED BOUND, not an oversight. In markdown a
# paragraph IS a line, so every consumer instruction in a doc is scanned whole. In a
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
# The FILE population is every readable non-binary file in the repo, `.git` excluded: a derivation
# is dangerous wherever it is published, and scoping this to a doc list would reproduce the
# hand-kept-list defect one layer up.
#
# ⛔ THE SPELLING POPULATION IS NARROWER THAN THE FILE POPULATION, and the difference is a
# convention this repo keeps rather than a property the grep can check. Only the single-quoted
# `grep -[lq]E '…'` form is recognised, so a derivation published as `grep -rlE "…"`, with the
# pattern in double quotes, or with the flags in another order is INVISIBLE here — it would sit in
# a consumer-facing doc, answer whatever it answers, and never be run against the tree. Safe today
# and measured, not assumed: each of leg 2's four surfaces publishes the single-quoted form, and
# leg 2 reds if one stops (a surface whose only spelling moved out of this predicate publishes
# nothing as far as `_publishes` can tell). The quoting convention is therefore load-bearing —
# keep it when adding a surface, or widen this pattern in the same change.
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
echo "== leg 2 — the surfaces that MUST publish the derivation =="
# THE SURFACES, and why exactly these: each one instructs someone about what to copy when they
# vendor. README's bin/ table is a different inventory of a different set and has its own gate
# (readme-bin-coverage-selftest.sh); the version-specific histories are out for the reason in the
# header. `docs/UPGRADE.md` is split at its own `## 6.` heading — derived, not a line number —
# because §1-§5 are live instructions and §6 is the frozen per-version record.
#
# THIS LIST IS A FLOOR AND ONLY LEG 2 READS IT, which is what makes hand-keeping it legitimate
# here: "this surface owes the reader a derivation" is an editorial obligation, not a property of
# any file, so nothing in the tree can derive it. A surface missing from it is a surface nobody
# promised anything about — it is NOT a hole in leg 3, which no longer reads this array at all.
# It used to: leg 3 ran over exactly these four paths while claiming "NO consumer-facing surface
# enumerates the set", so a fifth surface joined SILENTLY — the same mechanism that let
# `UPGRADE.md` §3 survive the first three-copy audit, rebuilt inside the gate that closed it.
# Measured: appending to `README.md` a sentence telling a vendoring reader to copy the shared lib
# beside kbcard, next-dl, board-snapshot and board-card-start left this file at rc 0, and
# `readme-bin-coverage-selftest` at rc 0 beside it.
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
done

# ---------------------------------------------------------------------------
echo "== leg 3 — no surface anywhere in the repo enumerates the set in prose =="
# THE POPULATION IS THE WHOLE REPO, the same one leg 1 uses, and it is derived on every run rather
# than listed: this leg is a PROHIBITION, and a prohibition scoped to a list of paths answers about
# the list, not about the repo. It is fail-CLOSED by construction — a file that nobody thought
# about is IN, and reports; only a named, reasoned carve-out is out. That direction is the whole
# fix. The previous spelling ran over leg 2's four paths and read as if it ran over the repo.
#
# TWO CARVE-OUTS, and they are different shapes on purpose:
#
#   (a) VERSION-SPECIFIC FROZEN HISTORY, carved out WHOLE-FILE. `docs/CHANGELOG.md`,
#       `docs/UPGRADE.md` §6 and `CLAUDE.md`'s release-snapshot table are append-only records of
#       what was true AT a version; a frozen at-that-version list cannot rot, and a per-line
#       disposition here would need a new entry at every release, i.e. exactly the hand-kept list
#       this file exists to abolish. `CLAUDE.md` is carved out whole for a second, independent
#       reason: it is this repo's own agent orientation and reaches no vendoring consumer at all.
#       Leg 1 still covers all three — history may not publish a derivation that does not work.
#
#   (b) DISPOSED LINES, carved out LINE-BY-LINE. The two predicates below cannot tell a vendoring
#       instruction from prose that happens to name the same nouns, so a handful of real lines
#       report and are not defects. Each is disposed by <path>::<substring> and each disposition
#       is ASSERTED to still match something — a disposition that suppresses nothing is dead
#       weight and reds, which forces it to be re-derived rather than inherited. Line scope, not
#       file scope, is load-bearing: `README.md` carries one disposed paragraph and is otherwise
#       the most consumer-facing file in the repo, so carving out the FILE would hide a real
#       regrown list in the one place it would do the most damage.
LEG3_HISTORY=("docs/CHANGELOG.md" "CLAUDE.md")
LEG3_DISPOSED=(
    # The tolerant-parse paragraph. It enumerates the paginator's CONSUMERS — a different set,
    # with its own gate (tests/fetch-board-cards-caller-claims-selftest.sh) — and instructs
    # nobody to copy anything.
    "README.md::A \`2xx\` nothing can be read out of is refused by the tool"
    # A code comment about which siblings this one bin resolves at runtime. Not an instruction to
    # a vendoring reader, and drift in it reds that bin, not a consumer's install.
    "bin/adopt-to-dl::resolve the shared lib AND the sibling bins"
    # A test header naming the callers of one helper — again a different set, and the file it is
    # in is the gate for that helper.
    "tests/kb-positional-guard-selftest.sh::kb_require_positional"
    # This file's own regrown-list control fixture, below. It MUST be reportable; that is its job.
    "tests/lib-set-derivation-selftest.sh::IF you vendored a lib-sourcing bin"
)

# _leg3_scan <root> — every reported line in the tree under <root>, as `<relpath>: <line>`.
# `docs/UPGRADE.md` is scanned through its live region only, reusing the `## 6.` split above — and
# ONLY under the real `$ROOT`, so a fixture tree that happened to carry that path would be read as
# itself rather than silently answered from the repo's own live region.
_leg3_scan() {
    local root="$1" f rel src hit
    while IFS= read -r f; do
        rel="${f#"$root"/}"
        case " ${LEG3_HISTORY[*]} " in *" $rel "*) continue ;; esac
        src="$f"
        [[ "$root" == "$ROOT" && "$rel" == "docs/UPGRADE.md" ]] && src="$TMP/upgrade-live.md"
        while IFS= read -r hit; do
            [[ -n "$hit" ]] && printf '%s: %s\n' "$rel" "$hit"
        done < <(_enumerates "$src")
    done < <(grep -rIl '' "$root" --exclude-dir=.git 2>/dev/null | LC_ALL=C sort)
}

# _leg3_undisposed <raw> — the reported lines with every disposition applied.
_leg3_undisposed() {
    local raw="$1" d dpath dsub line keep
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        keep=true
        for d in "${LEG3_DISPOSED[@]}"; do
            dpath="${d%%::*}"; dsub="${d#*::}"
            case "$line" in "$dpath: "*) case "$line" in *"$dsub"*) keep=false ;; esac ;; esac
        done
        $keep && printf '%s\n' "$line"
    done <<<"$raw"
}

LEG3_RAW="$(_leg3_scan "$ROOT")"
eq "premise: the scan reached files and reported something" "true" \
   "$([ -n "$LEG3_RAW" ] && echo true || echo false)"
# EVERY DISPOSITION IS STILL LIVE — the guard on the carve-out itself. A disposition that has
# stopped matching is not harmless: it is an inherited ruling about a line nobody can point to,
# and this is the leg that refuses to carry one.
for d in "${LEG3_DISPOSED[@]}"; do
    dpath="${d%%::*}"; dsub="${d#*::}"
    eq "disposition suppresses a live line: $dpath — $dsub" "true" \
       "$(printf '%s\n' "$LEG3_RAW" | grep -F "$dpath: " | grep -qF "$dsub" && echo true || echo false)"
done
eq "no undisposed enumeration anywhere in the repo" "" "$(_leg3_undisposed "$LEG3_RAW")"

# THE CONTROLS, so an empty result above is a measurement and not an absence of scanning. The
# fixture is a miniature tree, because the property under test is now about the POPULATION and a
# single-file probe cannot see it: a file nobody named must report, and a disposition must
# suppress its own line and nothing else in the same file.
#
# THE FIXTURE LINES ARE COMPOSED, NOT TYPED — `$KW` carries the keyword half of the predicate, so
# no line of THIS file holds both halves and the fixtures are not themselves reported by the leg
# they exercise. The alternative is a disposition per fixture line, i.e. this file disposing of
# itself four times over, which buys nothing and grows the very list the carve-out is trying to
# keep short. The one deliberate exception is the `regrown.md` quote at the bottom: it is a
# VERBATIM copy of the line that shipped in `UPGRADE.md` §3, its documentary value is in being
# verbatim, and its disposition is what demonstrates the mechanism on a real line.
KW='shared lib'
mkdir -p "$TMP/leg3fix/docs"
{
  printf -- '- **A `2xx` nothing can be read out of is refused by the tool** — the %s parse reaches kbcard, next-dl and board-snapshot.\n' "$KW"
  printf -- 'When you vendor, copy the %s beside kbcard, next-dl, board-snapshot and board-card-start.\n' "$KW"
} > "$TMP/leg3fix/README.md"
printf -- 'Copy the %s next to kbcard, next-dl and board-stats when you vendor them.\n' "$KW" \
    > "$TMP/leg3fix/docs/A-SURFACE-NOBODY-NAMED.md"
FIX_RAW="$(_leg3_scan "$TMP/leg3fix")"
FIX_LEFT="$(_leg3_undisposed "$FIX_RAW")"
eq "control: a surface NOBODY NAMED is reported"          "true" \
   "$(has 'docs/A-SURFACE-NOBODY-NAMED.md' "$FIX_LEFT")"
eq "control: …and so is a regrown list in a disposed file" "true" \
   "$(has 'When you vendor, copy the shared lib beside' "$FIX_LEFT")"
eq "control: …while the disposed line itself is NOT"       "false" \
   "$(has 'is refused by the tool' "$FIX_LEFT")"
# The line-unit half of the pair: a line that names the lib and ONE member is not an enumeration,
# so the leg cannot be passing by reporting everything.
printf 'Without the shared lib, board-card-start reports the skip and still exits 0.\n' > "$TMP/one-name.md"
eq "control: a single-name line is NOT an enumeration"     ""    "$(_enumerates "$TMP/one-name.md")"
# And the line that actually shipped in `UPGRADE.md` §3, which is what this whole file is about.
cat > "$TMP/regrown.md" <<'FIXTURE'
cp ~/agent-board-toolkit/bin/_kb-board-lib.sh bin/   # + the shared lib IF you vendored a lib-sourcing bin (kbcard/next-dl/board-snapshot/board-card-start/dl-a0/dl-a1)
FIXTURE
eq "control: the regrown-list fixture IS reported" "true" \
   "$([ -n "$(_enumerates "$TMP/regrown.md")" ] && echo true || echo false)"

_summary lib-set-derivation-selftest
