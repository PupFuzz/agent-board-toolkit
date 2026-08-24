#!/usr/bin/env bash
# hand-enumerated-population-census.sh — a CENSUS INSTRUMENT, not a gate. It enumerates the
# candidate instances of one defect class across `tests/` and prints the population plus the
# count. It asserts nothing and is deliberately NOT named `*-selftest.sh`, so
# `ci-matrix-parity-selftest.sh`'s orphan gate (whose population IS `tests/*-selftest.sh`) does
# not claim it and it is not wired into any workflow.
#
# THE DEFECT CLASS. A selftest block whose population is a HAND-MAINTAINED LIST cannot red when
# a new member appears. The block names its members literally while the real population is
# derivable from the tree, so the guard silently stops covering things and nothing fails. The
# known-good shape is the opposite: re-derive the members from the tree on every run
# (`fetch-board-cards-caller-claims-selftest.sh` does this and says so).
#
# ⛔ WHY EVERY SWEEP HERE USES `command grep`. In an interactive Claude Code shell `grep` is a
# shell FUNCTION that execs `ugrep --ignore-files`, which silently honours `.gitignore` and
# still exits 0 — a truncated sweep that looks exactly like a clean result. Measured on this
# box: a 4-file fixture returned ground-truth 4, `command grep -rl` 4, bare `grep -rl` 2 at
# rc 0. A census that under-reports its own population would reproduce the very defect it is
# hired to measure, so every read below goes through `command grep` or `/usr/bin/grep`.
#
# ─────────────────────────── THE PREDICATE, STATED ───────────────────────────
#
# UNIT — the BLOCK. Every file in `tests/*.sh` (the glob is re-expanded on every run; no file
# list is stored) is split at its own section banners, `^echo "== … =="`. Block 0 of each file
# is the header region above the first banner. Sub-banners (`^echo "-- … --"`) do NOT split;
# they are read as part of the enclosing block's claim text. The banner convention is the
# repo's own — it is used by 40 of 44 files in `tests/`; the 4 without banners are stubs/libs
# and are covered as a single block-0 each.
#
# A block is a CANDIDATE iff  TOTALITY ∧ LITERAL.
#
#   TOTALITY — the block CLAIMS to cover a whole population. Read from the block's claim text
#   only (its banner, its `^#` comment lines, and its `-- … --` sub-banners) — never from
#   executable code, where the same words are data. Lexicon in TOTALITY_RE below; it was tuned
#   against measured output, not guessed, and every widening/narrowing is recorded there.
#
#   LITERAL — the block enumerates its members as literal strings in the source. Four
#   structural signatures, any one of which suffices (S1–S4, tallied per block so the evidence
#   is legible):
#     S1  `for VAR in <2+ bare literal words>` — no `$`, no command substitution, no glob.
#     S2  a literal array assignment `IDENT=( … )` with >= 2 elements and no expansion inside.
#     S3  >= 2 calls to a FILE-LOCAL helper function with >= 2 DISTINCT quoted literal first
#         arguments. "File-local" is DERIVED per file (functions defined in the file) MINUS the
#         framework primitives DERIVED from `_selftest-prelude.sh` — so `eq`/`has`/`ok`, which
#         every block calls many times, are excluded by derivation and not by a hand list.
#     S4  a keyword set spelled as >= 2 `-e '…'` alternatives on one grep/sed invocation.
#
#   DERIVED — an ATTRIBUTE, not part of the candidate predicate: does the block contain a
#   run-time derivation over the tree or over production source (`command grep -r…`, `find`,
#   `git ls-files`, `mapfile`, `< <(…)`, a `_derive*`/`_disk_*` helper, a directory glob)?
#   It is reported rather than subtracted BECAUSE a block can derive one axis and hard-code
#   another — that is exactly known instance 2, whose FILE population is derived while its
#   member SPELLINGS are three literals. Subtracting DERIVED blocks would hide that shape.
#
# ⚠ WHAT THIS PREDICATE STRUCTURALLY CANNOT SEE — stated because a census that reads as total
# and is not is worse than a narrow one:
#   R1  A totality claim carried by a block's PROSE MEANING rather than its lexicon ("the
#       matrix below", "one leg per verb" is caught, but "the three shapes" is a bare numeral).
#   R2  A hand-maintained population expressed as `case` patterns or as an if/elif ladder. Both
#       are excluded from S1–S4: stub routers use them for routing, not enumeration, and
#       including them buried the signal (measured — see the tuning note at CASE_NOTE).
#   R3  A helper DEFINED in one block and CALLED in another: S3 tallies calls inside a block,
#       so a helper whose literal member list lives at its definition site is attributed to the
#       definition's block, not the block that claims totality.
#   R4  A hand-maintained list that lives OUTSIDE `tests/` (in `bin/`, `.github/workflows/`, or
#       a doc) and is merely consumed by a test. The population here is `tests/` by choice.
#   R5  Whether a literal list is actually STALE — that needs the production population driven
#       and compared, which is per-candidate work. This instrument finds candidates; it does
#       not decide membership.
#
# WHERE THE DISPOSITIONS LIVE — card#6645, NOT this file. A per-candidate IS/IS-NOT table
# checked in beside the instrument would be a hand-maintained list of the members of a
# hand-maintained-list census: the defect, rebuilt one layer up, which is exactly how leg 3 of
# `lib-set-derivation-selftest.sh` went wrong. This file re-computes the CANDIDATES on every
# run and prints them; the ruling on each is recorded on the card.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
GREP=/usr/bin/grep
[[ -x "$GREP" ]] || GREP="$(command -v grep)"

# TOTALITY_RE — tuned against measured output. `all ` alone matched assertion prose ("all 4
# segments") in blocks with no population claim, so it is anchored to a population noun. Bare
# numerals ("the three shapes") are deliberately OUT: they matched mostly value assertions and
# would have doubled the candidate set with noise. That exclusion is R1 above.
#
# TUNING ROUND 2, on a MEASURED miss rather than on taste. The first lexicon ran at 39
# candidates and was ground-truthed against one cluster it could be checked on: the six
# `value-taking flag` blocks in `tests/` (found independently, by name, not by this
# predicate). It caught 4 of the 6 and missed `adopt-to-dl-selftest.sh:73` and
# `release-artifacts-selftest.sh:1386`, BOTH of which carry the population claim as a BARE
# PLURAL — "value-taking flags reject an EMPTY value" — with no lexicon token in it. The
# `[a-z]+s (reject|refuse|are all|must|still|each)` alternative was added for exactly that
# shape. Report BOTH counts, never only the later one: a lexicon is a bound on the census,
# and a single number hides that the bound moved.
TOTALITY_RE='(every|each of|all [a-z]* ?(of|the|its|bin|call|site|surface|member|leg|case|arm|flag|verb|field|state|row|shape|instance|consumer|file|test)|the rest of|one leg per|one per |whole class|whole population|the population|the full set|the complete|exhaustive|accounted for|no [a-z_-]+ anywhere|the whole set|totality|the set of|nothing (else|more) |[a-z]+s (reject|refuse|are all|must|still|each) )'

# DERIVED_RE — evidence of a run-time re-derivation over the tree / production source.
DERIVED_RE='(command grep -[a-zA-Z]*r|grep -[a-zA-Z]*r[a-zA-Z]* |git ls-files|mapfile|readarray|< <\(|\$\((command )?grep|\$\(find|find "\$|find \$|_derive|_disk_|_publishes|/\*\.sh|/\*-selftest|\$\(ls |compgen -A function)'

# CASE_NOTE: `case … in` with >= 2 literal patterns was trialled as a fifth signature (S5) and
# REJECTED on measurement, not on taste: it fired on 100+ blocks, almost all of them stub
# routers (`case "$method $url" in`) and rc dispatchers, where the literals are the thing under
# test rather than a claimed population. It is recorded as residual R2 rather than dropped
# silently, because a genuine hand-maintained list CAN be spelled that way.

# ── derive the framework primitives (so S3's exclusion is derived, not listed) ───────────────
PRELUDE="$HERE/_selftest-prelude.sh"
[[ -r "$PRELUDE" ]] || { printf 'census: cannot read %s\n' "$PRELUDE" >&2; exit 1; }
PRELUDE_FNS="$("$GREP" -oE '^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)' "$PRELUDE" \
    | sed -E 's/[[:space:]]*\(\)$//; s/^[[:space:]]*(function[[:space:]]+)?//' | sort -u)"

# ── the population, re-expanded on every run ─────────────────────────────────────────────────
shopt -s nullglob
FILES=("$HERE"/*.sh)
shopt -u nullglob
# This instrument is itself in tests/*.sh; exclude it by IDENTITY (its own resolved path), not
# by name, so a rename cannot silently put it back into its own denominator.
SELF="$(readlink -f "${BASH_SOURCE[0]}")"

VERBOSE="${CENSUS_VERBOSE:-0}"
n_files=0; n_blocks=0; n_totality=0; n_literal=0; n_cand=0

for f in "${FILES[@]}"; do
    [[ "$(readlink -f "$f")" == "$SELF" ]] && continue
    n_files=$((n_files + 1))
    # Passed through the ENVIRONMENT, never `awk -v`: -v runs escape-sequence processing on the
    # value, which ate the backslashes out of both regexes and produced an "invalid regexp"
    # fatal on the first file. ENVIRON[] hands the bytes over untouched.
    out="$(CENSUS_PRELUDE="$PRELUDE_FNS" CENSUS_TOT_RE="$TOTALITY_RE" CENSUS_DER_RE="$DERIVED_RE" \
           CENSUS_FNAME="$f" awk '
    function lc(s) { return tolower(s) }
    function flush_block(   i, sig, tot, lit, der, key, ndistinct, cmd) {
        if (bstart == 0) return
        tot = (match(lc(claim), tot_re) > 0)
        # ---- S1: for VAR in <2+ bare literals> ------------------------------------------
        lit = 0; sig = ""
        if (s1) { lit = 1; sig = sig "S1," }
        if (s2) { lit = 1; sig = sig "S2," }
        # ---- S3: >=2 calls to a file-local helper with >=2 distinct literal first args ---
        for (key in callargs) {
            split(key, p, SUBSEP)
            if (p[1] in localfn) { cnt[p[1]]++ }
        }
        for (cmd in cnt) { if (cnt[cmd] >= 2) { lit = 1; sig = sig "S3(" cmd ")," } }
        delete cnt
        if (s4) { lit = 1; sig = sig "S4," }
        der = (match(body, der_re) > 0)
        printf "%s\t%d\t%s\t%d\t%d\t%d\t%s\n", fname, bstart, banner, tot, lit, der, sig
    }
    function reset_block(ln, ban) {
        bstart = ln; banner = ban; claim = ban; body = ""
        s1 = 0; s2 = 0; s4 = 0
        delete callargs
    }
    BEGIN {
        prelude = ENVIRON["CENSUS_PRELUDE"]; tot_re = ENVIRON["CENSUS_TOT_RE"]
        der_re  = ENVIRON["CENSUS_DER_RE"];  fname   = ENVIRON["CENSUS_FNAME"]
        n = split(prelude, pl, "\n"); for (i = 1; i <= n; i++) if (pl[i] != "") prelude_fn[pl[i]] = 1
        bstart = 0
    }
    # pass 1 is folded in: collect file-local function defs first via a pre-read
    {
        lines[NR] = $0
    }
    END {
        # --- derive this FILE'\''s locally-defined helpers, minus the framework primitives ---
        for (i = 1; i <= NR; i++) {
            if (match(lines[i], /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/)) {
                nm = lines[i]
                sub(/^[[:space:]]*(function[[:space:]]+)?/, "", nm)
                sub(/[[:space:]]*\(\).*$/, "", nm)
                if (!(nm in prelude_fn)) localfn[nm] = 1
            }
        }
        reset_block(1, "(file header)")
        for (i = 1; i <= NR; i++) {
            L = lines[i]
            if (L ~ /^echo "== /) { flush_block(); b = L; sub(/^echo "== /, "", b); sub(/ ==".*$/, "", b); reset_block(i, b); continue }
            body = body "\n" L
            # claim text: comments and sub-banners only
            if (L ~ /^[[:space:]]*#/ || L ~ /^echo "-- /) claim = claim "\n" L
            # ---- S1 ----
            if (match(L, /^[[:space:]]*for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]+/)) {
                rest = substr(L, RSTART + RLENGTH)
                sub(/;.*$/, "", rest); sub(/[[:space:]]*do.*$/, "", rest)
                if (rest !~ /[$`*?]/ && rest !~ /\(/) {
                    k = split(rest, w, /[[:space:]]+/); c = 0
                    for (j = 1; j <= k; j++) if (w[j] != "") c++
                    if (c >= 2) s1 = 1
                }
            }
            # ---- S2: literal array assignment on one line ----
            if (match(L, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\(/)) {
                inner = L; sub(/^[^(]*\(/, "", inner); sub(/\).*$/, "", inner)
                if (inner !~ /[$`]/ && inner ~ /[^[:space:]]/) {
                    k = split(inner, w, /[[:space:]]+/); c = 0
                    for (j = 1; j <= k; j++) if (w[j] != "") c++
                    if (c >= 2) s2 = 1
                }
            }
            # ---- S3: record <cmd, literal-first-arg> pairs ----
            if (match(L, /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]+["'\''][^"'\'']+["'\'']/)) {
                tokline = L; sub(/^[[:space:]]*/, "", tokline)
                cmdnm = tokline; sub(/[[:space:]].*$/, "", cmdnm)
                argpart = tokline; sub(/^[A-Za-z_][A-Za-z0-9_]*[[:space:]]+/, "", argpart)
                q = substr(argpart, 1, 1)
                arg = substr(argpart, 2); idx = index(arg, q)
                if (idx > 1) { arg = substr(arg, 1, idx - 1); if (arg !~ /\$/) callargs[cmdnm, arg] = 1 }
            }
            # ---- S4: >=2 `-e '"'"'lit'"'"'` alternatives on one line ----
            ec = gsub(/-e[[:space:]]+['\''"][^'\''"]+['\''"]/, "&", L)
            if (ec >= 2) s4 = 1
        }
        flush_block()
    }' "$f")"

    while IFS=$'\t' read -r file line banner tot lit der sig; do
        [[ -n "$file" ]] || continue
        n_blocks=$((n_blocks + 1))
        [[ "$tot" == 1 ]] && n_totality=$((n_totality + 1))
        [[ "$lit" == 1 ]] && n_literal=$((n_literal + 1))
        if [[ "$tot" == 1 && "$lit" == 1 ]]; then
            n_cand=$((n_cand + 1))
            printf 'CANDIDATE  %s:%s  [derived=%s] [%s]\n    %s\n' \
                "${file#"$HERE"/}" "$line" "$der" "${sig%,}" "$banner"
        elif [[ "$VERBOSE" == 1 ]]; then
            printf 'skip       %s:%s  tot=%s lit=%s\n' "${file#"$HERE"/}" "$line" "$tot" "$lit"
        fi
    done <<<"$out"
done

printf '\n── population, re-derived this run ──\n'
printf 'files in tests/*.sh (excl. this instrument) : %d\n' "$n_files"
printf 'blocks (banner-delimited, + one header each): %d\n' "$n_blocks"
printf 'blocks asserting TOTALITY                   : %d\n' "$n_totality"
printf 'blocks enumerating LITERAL members          : %d\n' "$n_literal"
printf 'CANDIDATES (TOTALITY and LITERAL)           : %d\n' "$n_cand"
