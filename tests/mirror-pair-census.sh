#!/usr/bin/env bash
# mirror-pair-census.sh — a CENSUS INSTRUMENT, not a gate. It re-derives the population of one
# defect class across `bin/` and prints it with a per-copy verdict. It asserts nothing about that
# population and is deliberately NOT named `*-selftest.sh`, so `ci-matrix-parity-selftest.sh`'s
# orphan gate (whose population IS `tests/*-selftest.sh`) does not claim it, `suite-home
# -containment`'s `*selftest*` glob does not run it, and it is wired into no workflow. It is the
# same shape, and for the same reason, as `readback-before-success-census.sh` and
# `hand-enumerated-population-census.sh` beside it.
#
# THE DEFECT CLASS (card#8529). `bin/` ships four tools vendored STANDALONE into consumer repos
# that must not source `bin/_kb-board-lib.sh` — `docs/CONSOLIDATION-PLAN.md` § Stage D DECIDED
# (2026-08-01) against consolidating them and chose GUARDED duplication instead. Each therefore
# carries inline copies of guards the lib also owns, marked `keep the two in sync`. A comment is
# not a guard: a fix landing in one copy and missing its twin ships a guard that is right in the
# tool and wrong in the lib, with a green suite, because nothing compares them. Measured twice —
# `host_ok` carried one defect in BOTH copies before `kb-host-guard-selftest`, and PR #322's MF-1
# was a case-sensitive `.git` arm fixed in one repo-slug copy while the published contract was
# case-insensitive.
#
# WHY IT EXISTS AT ALL, given the pins have landed. The population is not fixed: every new
# standalone guard is a new candidate, and a population re-derived only when somebody remembers
# to is a population nobody is measuring. This is the METHOD by which a later pass RE-COMPUTES it
# — cheap enough to actually run — rather than a number in a document that goes stale the day a
# bin grows a copy. The card that minted this file quoted "13 sites" and "5 of 13 pinned"; both
# figures were already wrong when it was picked up. Do not quote this file's output either — run it.
#
# ⛔ WHY EVERY SWEEP HERE USES `command grep`. In an interactive Claude Code shell `grep` is a
# shell FUNCTION that execs `ugrep --ignore-files`, which silently honours `.gitignore` and still
# exits 0 — a truncated sweep that looks exactly like a clean result. A census that under-reports
# its own population reproduces the defect it is hired to measure.
#
# ─────────────────────────── THE PREDICATE, STATED ───────────────────────────
#
# UNIT — a shell function DEFINITION at column zero in a shipped shell file (`bin/` + `hooks/`,
# minus the python shims — the population `tests/_shipped-shell-lib.sh` derives from CI's own
# analyser step, so this file does not hand-copy that `find`).
#
# A definition is a MIRROR CANDIDATE by EITHER of two independent legs, unioned. Neither leg is
# sufficient alone and that is the point — one is a prose search and one is not:
#
#   LEG D — DECLARED. The contiguous `#` block immediately above the definition matches
#     `MIRROR_RE`. This is what a `keep the two in sync` comment gets you, and it is the leg that
#     finds a mirror whose two copies have DIFFERENT NAMES (`host_ok` ↔ `kb_require_https_host`,
#     `_rc_expand_home` ↔ `_kb_expand_home`) — no structural search can pair those.
#   LEG S — STRUCTURAL, MARKER-FREE. The same function NAME is defined in two or more shipped
#     files. This is the leg that survives the card's own warning that "a clean grep is not a
#     clean audit": it needs no prose at all, so it still sees a copy whose author wrote no
#     comment, or wrote one this file's wording does not match.
#
# ⚠ LEG D IS DELIBERATELY LOOSE AND ITS NOISE IS NOT SUBTRACTED. `MIRROR_RE` admits prose ABOUT
# the pattern — a docblock explaining why a SECOND COPY was avoided reads the same to a regex as
# one declaring a copy exists (`_ibh_norm`, `_bsc_hooks_dir` and `_emit_withheld` are live
# examples). Every LEG-D row's matching fragment is printed in the second section BELOW the table
# so a reader can rule on it in one glance. There is NO exemption list, which is what lets the
# denominator equal the predicate exactly: an exemption list is where the next missed member hides.
# Tightening the wording was tried and dropped — it lost `src_canon` ("two byte-identical inline
# copies") and all five `_rc_*` mirrors ("mirror of the lib's …") at once.
#
# ⚠ LEG S ADMITS PER-TOOL BOILERPLATE, on purpose. `die`, `main`, `cfg`, `_put`, `_put_err` are
# defined in many bins and are NOT one rule in N copies — each names its own tool and exits on its
# own policy. They report as candidates forever. Two dozen rows of known noise are cheaper than an
# exemption list, for LEG D's reason.
#
# VERDICT, per copy — the question the card asks, which is only ever about the NON-LIB copy:
#   LIB          — defined in `bin/_kb-board-lib.sh`. A test reaches it by `source`, so there is
#                  no extraction to look for; the pin question belongs to its twin.
#   EXTRACTED    — some file under `tests/` lifts THIS copy out of its bin by name, which is what
#                  lets a test drive it beside its twin over one corpus. Detected three ways: a
#                  literal `_adopt_fn`/`_fn_src <src> <name>`; a `<name>` in a `for … in` word
#                  list within three lines above such a call (`token-duplication-selftest.sh`
#                  adopts its four mirrors that way, and a detector that missed it reported the
#                  best-pinned pairs in the repo as unpinned); and a hand-spelled `^<name>(`
#                  regex anchor, the residual spelling `prelude-shadow-selftest.sh` dispositions.
#   UNEXTRACTED  — nothing lifts it. NOT A FINDING BY ITSELF: most rows here are LEG-S boilerplate
#                  or LEG-D prose. It is the column to read a candidate out of, not a verdict.
#
# ⚠ WHAT THIS PREDICATE STRUCTURALLY CANNOT SEE — stated because a census that reads as total and
# is not is worse than a narrow one:
#   R1  A mirror that is not a shell FUNCTION. `bin/promote-released-cards`'s jq `canon_source`
#       and `norm` are copies of `src_canon` and `numlist` in another RUNTIME, and no scan of
#       `^name()` can see them. They are pinned (`promote-source-qualify-selftest.sh` § 3e,
#       `promote-ref-canon-selftest.sh`) — by files this instrument cannot credit.
#   R2  A mirror INSIDE a function: the `awk` `trim()` in `_kb-board-lib.sh`'s
#       `kb_coord_store_token_file` is byte-identical to the one in
#       `agent-board-toolkit-runtime-check`'s `_rc_store_pointer`. The enclosing pair IS in the
#       table, and its 16-row store matrix in `token-duplication-selftest.sh` drives the awk with
#       it — but that is the pair being covered, not this leg seeing the awk. Re-run the
#       enumeration rather than trusting this note, which is a measurement with a date on it:
#       `command grep -rnE '^[[:space:]]*function [a-z]' bin/` listed ELEVEN awk functions across
#       three files. Eight names appear once, in `bin/run-coverage-check`'s workflow parser. `trim`
#       appears three times and only TWO of them are the pair: the third is that same parser's own
#       helper and is a DIFFERENT function (no `\r` in its class), which is the shape to check for
#       before calling a shared name a shared rule.
#   R3  Whether an EXTRACTED copy is actually driven BESIDE its twin. Extraction is structural;
#       that the test compares the two over one corpus is per-pair work. `EXTRACTED` is where to
#       start reading, not a certificate.
#   R4  A definition not at column zero, or spelled `function name {`. `bin/next-dl`'s nested
#       `unusable()` is the one indented definition in `bin/` and is file-local to a subshell.
#   R5  Anything outside the shipped shell files. A mirror between two TEST files is out of scope
#       by choice; `prelude-shadow-selftest.sh` owns that population.
#
# The CONTROL below is what makes the classifier a measurement rather than a decoration. It runs
# on REAL `bin/` lines, never on a fixture this file wrote: a control that mints its own sample
# proves only the sample. Its five legs are stated with the leg each one owns — one real row of
# each VERDICT, and one row that ONLY ONE denominator leg can admit, per leg, so neither leg can
# be narrowed away silently. Each addresses its line by an ANCHOR grepped out of the file, never
# by a line number: a number here would rot on the next edit above it and red for the wrong
# reason. An anchor that no longer matches is itself a refusal — the control says which one and
# exits 2 rather than printing a population it can no longer justify.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/_shipped-shell-lib.sh"
cd "$ROOT" || exit 2

FN_RE='^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)'
MIRROR_RE='[Mm]irror|MIRROR|in sync|duplicat|[Cc]opies|[Cc]opy of|(second|third) copy|vendored standalone'
LIB_FILE='bin/_kb-board-lib.sh'

# _defs — "<name>\t<file>\t<line>" for every column-zero definition in the shipped shell files.
_defs() {
    local f
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        command grep -nE "$FN_RE" "$f" | while IFS=: read -r ln rest; do
            printf '%s\t%s\t%s\n' "${rest%%[[:space:](]*}" "$f" "$ln"
        done
    done < <(_shipped_shell_files "$ROOT")
}

# _declared <file> <line> — the matching fragment of the contiguous comment block above the
# definition, or nothing. Printed in the second section so LEG D's noise is legible, not hidden.
_declared() {
    local f="$1" ln="$2" blk
    # ONE awk pass, not a `sed -n "$((s-1))p"` per line walking upward: at 77 rows that spelling
    # spawned thousands of processes and the instrument took 49s, which is the difference between
    # a derivation somebody runs every pass and a number in a document.
    blk="$(awk -v L="$ln" '
        NR < L { a[NR] = $0; next }
        NR == L {
            s = L
            while (s > 1 && substr(a[s-1], 1, 1) == "#") s--
            for (i = s; i < L; i++) print a[i]
            exit
        }' "$f")"
    [[ -n "$blk" ]] || return 1
    printf '%s\n' "$blk" | command grep -oE ".{0,40}($MIRROR_RE).{0,46}" | head -1
}

# _extracted_names — every function name some file under tests/ lifts out of a bin, by the three
# spellings the header states. Computed ONCE: the table and the control both read this set, so a
# spelling one of them learned and the other did not cannot exist.
_extracted_names() {
    local t body
    for t in tests/*.sh; do
        [[ -f "$t" ]] || continue
        # ⛔ THIS FILE IS EXCLUDED FROM ITS OWN SCAN. The control's anchors below are literal
        # `^die\(\)` and `^_put_err\(\)` strings, and read as extractions they would report the
        # two rows the control pins as UNEXTRACTED as EXTRACTED — the control reds on itself, which
        # is not a signal about the tree. `prelude-shadow-selftest.sh` hit the same self-reference
        # and took the same way out; the alternative there and here is a placeholder spelling of
        # the regex, which buys nothing because this file extracts nothing.
        [[ "$t" == "tests/$(basename "${BASH_SOURCE[0]}")" ]] && continue
        # Comment lines are stripped: a header narrating the idiom (`_fn_src <src> <name>`) is
        # prose, and reading it as an extraction minted the names `name`, `runs` and `update`.
        body="$(sed 's/^[[:space:]]*#.*$//' "$t")"
        printf '%s\n' "$body" \
            | command grep -hoE '(_adopt_fn|_fn_src)[[:space:]]+[^[:space:]]+[[:space:]]+"?[A-Za-z_][A-Za-z0-9_]*' \
            | awk '{ n=$3; gsub(/"/,"",n); print n }'
        printf '%s\n' "$body" \
            | command grep -hoE '\^[A-Za-z_][A-Za-z0-9_]*\\?\(' \
            | sed -e 's/^\^//' -e 's/\\//' -e 's/(//'
        printf '%s\n' "$body" | awk '
            /^[[:space:]]*for [A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]/ {
                list = $0
                sub(/^[[:space:]]*for [A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]+/, "", list)
                sub(/;.*$/, "", list)
                sub(/[[:space:]]*do[[:space:]]*$/, "", list)
                pending = NR; plist = list; next
            }
            pending && NR <= pending + 3 && /(_adopt_fn|_fn_src)[[:space:]]/ {
                n = split(plist, w, /[[:space:]]+/)
                for (i = 1; i <= n; i++) { gsub(/"/, "", w[i]); if (w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*$/) print w[i] }
                pending = 0
            }'
    done
}

DEFS="$(_defs)"
DUPNAMES="$(printf '%s\n' "$DEFS" | cut -f1 | LC_ALL=C sort | uniq -d)"
EXNAMES="$(_extracted_names | LC_ALL=C sort -u)"

# _row <name> <file> <line> — "<leg>\t<verdict>" for one definition, or nothing when it is not a
# mirror candidate. THE DENOMINATOR PREDICATE: the control drives THIS function, so it exercises
# the rule that actually produces the population rather than a second copy of it.
_row() {
    local name="$1" file="$2" ln="$3" leg="" verdict
    _declared "$file" "$ln" >/dev/null && leg="D"
    printf '%s\n' "$DUPNAMES" | command grep -qx -- "$name" && leg="${leg}S"
    [[ -n "$leg" ]] || return 1
    if [[ "$file" == "$LIB_FILE" ]]; then verdict="LIB"
    elif printf '%s\n' "$EXNAMES" | command grep -qx -- "$name"; then verdict="EXTRACTED"
    else verdict="UNEXTRACTED"; fi
    printf '%s\t%s\n' "$leg" "$verdict"
}

# _ctl_line <file> <anchor-ere> — the line number of the ONE line matching <anchor-ere>. Returns 1
# (printing nothing) unless it matches EXACTLY once: a control that silently addressed the first
# of several matches would be pinning a line nobody chose.
_ctl_line() {
    local file="$1" anchor="$2" hits
    hits="$(command grep -cE "$anchor" "$file")" || return 1
    [[ "$hits" -eq 1 ]] || return 1
    command grep -nE "$anchor" "$file" | cut -d: -f1
}

# _ctl <leg-label> <file> <anchor> <name> <want-leg> <want-verdict>
_ctl() {
    local label="$1" f="$2" anchor="$3" name="$4" want="$5"$'\t'"$6" ln got
    ln="$(_ctl_line "$f" "$anchor")" || {
        echo "control: $label's anchor in $f no longer matches exactly one line — the control cannot address the row it exists to classify" >&2
        return 1
    }
    got="$(_row "$name" "$f" "$ln")" || got="<not in the sweep>"
    [[ "$got" == "$want" ]] || {
        printf 'control: %s (%s:%s, %s) classified %s, expected %s\n' \
            "$label" "$f" "$ln" "$name" "$(printf '%s' "$got" | tr '\t' '/')" "$(printf '%s' "$want" | tr '\t' '/')" >&2
        return 1
    }
    return 0
}

_control() {
    local rc=0

    # LEG 1 — a real EXTRACTED row. `host_ok` is the standalone host guard that
    # `kb-host-guard-selftest.sh` sed-extracts and drives against the lib's row by row; it is
    # declared (LEG D) and its name is unique in bin/ (so NOT LEG S). Break the extraction
    # detector and this reds.
    _ctl "LEG 1 (a pinned mirror)" bin/promote-released-cards '^host_ok\(\) \{' host_ok D EXTRACTED || rc=1

    # LEG 2 — a real UNEXTRACTED row, and the opposite verdict on the same classifier. Every bin
    # defines its own `die`; `bin/_shellcheck-pinned`'s exits 9 rather than 2, so it is per-tool
    # boilerplate that nothing will ever lift. Flip the classifier to EXTRACTED-by-default and
    # this reds.
    _ctl "LEG 2 (per-tool boilerplate)" bin/_shellcheck-pinned "^die\(\) \{ printf '_shellcheck-pinned" die S UNEXTRACTED || rc=1

    # LEG 3 — THE DENOMINATOR, LEG D ALONE. `_rc_expand_home` is a declared mirror of the lib's
    # `_kb_expand_home` whose NAME appears in exactly one bin, so only the prose leg can put it in
    # the sweep. Tighten MIRROR_RE past "mirror of the lib's …" and this reds with the file named.
    _ctl "LEG 3 (declared-only)" bin/agent-board-toolkit-runtime-check '^_rc_expand_home\(\) \{' _rc_expand_home D EXTRACTED || rc=1

    # LEG 4 — THE DENOMINATOR, LEG S ALONE. `_put_err` in `bin/gh-code-search` carries no mirror
    # prose at all: only the name-collision leg admits it. Drop LEG S — the marker-free half, the
    # one that survives an author who wrote no comment — and this reds.
    _ctl "LEG 4 (structural-only)" bin/gh-code-search '^_put_err\(\)' _put_err S UNEXTRACTED || rc=1

    # LEG 5 — THE HARD HALF OF THE VERDICT. `_rc_store_pointer` is lifted ONLY through
    # `token-duplication-selftest.sh`'s `for fn in … ; do _adopt_fn "$CHECK" "$fn"`, never as a
    # literal argument. A detector reading literal arguments alone reports the four best-pinned
    # mirrors in this repo as unpinned — it did, on this file's first draft. Remove the
    # loop-variable resolution and this reds.
    _ctl "LEG 5 (extraction through a loop variable)" bin/agent-board-toolkit-runtime-check '^_rc_store_pointer\(\) \{' _rc_store_pointer D EXTRACTED || rc=1

    return "$rc"
}

if ! _control; then
    echo "mirror-pair-census: the classifier no longer DISCRIMINATES — refusing to print a population it cannot justify." >&2
    exit 2
fi

printf '%-32s  %-42s  %-4s  %s\n' 'FUNCTION' 'SITE' 'LEG' 'VERDICT'
n_total=0; n_lib=0; n_ex=0; n_unex=0; declared=""
while IFS=$'\t' read -r name file ln; do
    [[ -n "$name" ]] || continue
    IFS=$'\t' read -r leg verdict < <(_row "$name" "$file" "$ln") || continue
    [[ -n "${leg:-}" ]] || continue
    n_total=$((n_total + 1))
    case "$verdict" in
        LIB)         n_lib=$((n_lib + 1)) ;;
        EXTRACTED)   n_ex=$((n_ex + 1)) ;;
        UNEXTRACTED) n_unex=$((n_unex + 1)) ;;
    esac
    printf '%-32s  %-42s  %-4s  %s\n' "$name" "$file:$ln" "$leg" "$verdict"
    case "$leg" in *D*) declared+="$(printf '%-32s %s' "$name" "$(_declared "$file" "$ln")")"$'\n' ;; esac
done <<< "$DEFS"

echo
echo "LEG-D declarations, verbatim — the fragment that admitted each row, so prose ABOUT the"
echo "pattern can be told from a declaration that a copy exists:"
printf '%s' "$declared"

echo
echo "denominator — mirror candidates in the shipped shell files: $n_total"
echo "  LIB          (reached by sourcing; the pin question is its twin's): $n_lib"
echo "  EXTRACTED    (some tests/ file lifts this copy by name):           $n_ex"
echo "  UNEXTRACTED  (nothing lifts it):                                   $n_unex"
echo
echo "An UNEXTRACTED row is not a finding: read R1-R5 and the LEG-D fragments above before ruling."
