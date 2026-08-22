#!/usr/bin/env bash
# piped-match-gate-selftest.sh — `<producer> | grep -q <needle>` is the shape that reports a
# MATCH as a NON-MATCH under `pipefail`. card#7175 removed 46 of 47 copies. This file is the
# guard that forbids the 48th: it derives the live population from the tree on every run and
# REDS on any occurrence its disposition list does not already carry.
#
# WHY A GATE AND NOT ANOTHER SWEEP. The repo has ruled on this exact question twice, and both
# rulings are in `docs/CONSOLIDATION-PLAN.md`. Stage B's card#5740 section:
#
#     "Deleting the copies did not close the class, and the first cut of this section said it
#      had. … fixing N copies without the guard that forbids the N+1th leaves the cause in
#      place."
#
# and § Corrections carried forward, generalising it:
#
#     "a copy that survives an audit of its own class is the argument FOR the gate that audit
#      declined."
#
# TWO copies survived card#7175's audit — the `_piped*` / `_stat*` fixtures in
# `pipeline-free-match-selftest.sh`, which are the class ITSELF held still so it can be measured
# — and the first cut of that file said outright that it "is not a gate on new ones". That
# sentence is what this file answers. It was also measured a third time on a neighbouring class
# in this same repo: PR #274 re-minted the read-outcome collapse ONE COMMIT after its own parent
# closed it at `install-board-hooks`, which is why `tests/read-outcome-collapse-selftest.sh`
# exists and why this file is built to its shape.
#
# ─────────────────────────── THE DEFECT, STATED ───────────────────────────
#
#     <producer> | grep -q "$needle" && echo true || echo false
#
# `grep -q` exits the instant it matches, closing the pipe while its producer is still writing.
# The producer then fails on the closed pipe, `set -o pipefail` promotes ITS non-zero status to
# the pipeline's, and the `&&` tail reports the match as `false`. Not an error — a WRONG ANSWER
# at rc 0, with nothing for the reader to notice. It needs the match near the START of the stream
# (so the reader leaves early) and more than the 64 KiB pipe buffer still to write, which is why
# it is invisible until a payload grows: `lib-set-derivation-selftest.sh` was green on five
# consecutive local runs and red in CI on the same commit once a second multi-KB `[Unreleased]`
# entry crossed the buffer.
#
# ⛔ THE PRODUCER'S CLASS IS NOT THE DISCRIMINATOR, and neither is its status NUMBER. A bash
# `printf` builtin is forked into a subshell and takes SIGPIPE like anything else; and the status
# is **141 at SIGPIPE's default, 1 on the EPIPE path an inherited `SIG_IGN` produces** (the
# GitHub Actions runner installs the latter), with `pipefail` promoting either. Both of those
# were relayed wrong before this card and both cost a red.
# `tests/pipeline-free-match-selftest.sh` is the control battery that measures every cell; THIS
# file makes no measurement at all — it is a census with a verdict list.
#
# ─────────────────────────── THE PREDICATE, STATED ───────────────────────────
#
# POPULATION — `find bin hooks -maxdepth 1 -type f ! -name '*.py'` (the `bin`/`hooks` half of
# `.github/workflows/ci.yml`'s shellcheck expression) PLUS `tests/*.sh`, re-derived on every
# invocation. No file list is stored here, so a bin or a selftest added tomorrow is scanned that
# day.
#   ⚑ `tests/` IS IN THE POPULATION HERE, and that is a deliberate DIVERGENCE from
#     `read-outcome-collapse-selftest.sh`, which excludes it. The reason is not symmetry, it is
#     where the defect lives: this class minted its CI red INSIDE the harness, and 44 of the 47
#     copies card#7175 found were in `tests/`. A gate over `bin/` alone would have said nothing
#     about any of them. (The other gate excludes `tests/` because a selftest discards a read's
#     status on purpose — that reasoning is specific to that class and does not transfer.)
#
# MEMBER — a FILE, `<relpath>`, carrying a COUNT of occurrences. Not a line number: a line number
# rots on the next edit above it and turns every disposition into a re-typing chore. The count is
# what makes the file-level key safe — a NEW copy inside an already-dispositioned file moves the
# count and reds, which is precisely the N+1th case a bare per-file allow-list would swallow.
#
# AN OCCURRENCE is `|` (a pipe, not a `||`) followed by optional whitespace and a `grep` whose
# FIRST operand asks it to be quiet: a `q` in a short-option cluster (`grep -q`, `-qx`, `-qF`,
# `-qiE`, `-qsq`…) or the long forms `--quiet` / `--silent`. Two on one line count as two. Line
# continuations are joined before the test, because a call site may put the `&& ok … || bad …`
# tail on the next physical line. Comment lines are excluded — a header NARRATING the retired
# shape (this one does it a dozen times) is prose, not a call site.
#   ⛔ THE FLAG MUST COME FIRST. `producer | grep "$pat" -q` — the option AFTER the operand,
#     which GNU grep accepts — is NOT derived, and widening to find it would mean matching a `-q`
#     anywhere on the line, which sweeps up `grep -e '-q'` and every unrelated `-q` in the
#     statement. Stated as a bound rather than chased: no site in this repo spells it that way,
#     and every migrated one wore the flag first.
#
# ⛔ WHAT IS NOT SCRIPTABLE, AND IS THEREFORE THE DISPOSITION LIST'S JOB. The scanner derives
# where the shape IS; whether an occurrence is a DEFECT is a judgement no regex can make. The
# fixtures in `pipeline-free-match-selftest.sh` are the class held still on purpose and must
# never be "fixed"; a new one three files over is the bug. Both match identically. So the scanner
# owns the population and the list below owns the verdict, one line per file with its reason —
# and a file NOT in the list is RED, which is the only property that makes the pair worth
# anything.
#
# ⛔ WHAT IT STRUCTURALLY CANNOT SEE — stated so it is not over-cited:
#   * THE WIDER EARLY-EXIT-READER CLASS. `grep -q` is not the only reader that leaves early:
#     `| head -N`, `| head -c N` and a `while read` that breaks do the same thing to their
#     producer. This gate covers `grep -q` ONLY — the shape card#7175 retired — and the
#     denominator prints the wider count as an ADVISORY figure it does not assert on, so the
#     remainder is a number that moves rather than a prose "N at time of writing" that rots.
#     `bin/release-artifacts-check`'s `… | head -1` is a live member of that wider class, held
#     safe by an explicit `|| true` documented at the site. Recorded in
#     `docs/CONSOLIDATION-PLAN.md § Post-program dispositions`; NOT closed here.
#   * A pipeline BUILT AS A STRING and run through `eval`, or one assembled in a variable.
#   * `bin/*.py`, and the bash embedded in this repo's composite actions — every `action.yml`
#     in the tree, not a list written here (one stood here naming two of what are now three).
#   * A `grep -q` reached across a FUNCTION boundary — `_match() { grep -q "$1"; }` called as
#     `producer | _match x`. There is no `grep` on the pipeline's own line to find.
#   * Whether a DISPOSITIONED reason is TRUE. It is a recorded judgement re-read by whoever next
#     edits that file — not a proof.
#
# ⛔ `command grep`, never bare `grep`: in an interactive Claude Code shell `grep` is a function
# exec'ing `ugrep --ignore-files`, which honours `.gitignore` and still exits 0 — a truncated
# sweep that reads as a clean one. Every read here goes through awk.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$(cd "$HERE/.." && pwd)"

# ── the disposition list ────────────────────────────────────────────────────────────────────
#
# "<relpath>|<expected occurrences>|<reason they are permitted>". Three ways to red:
# a file the scanner derives that is not listed, a listed file the scanner no longer derives,
# and a listed file whose COUNT moved. The third is the N+1th-copy case.
DISPOSITIONED=(
  "tests/pipeline-free-match-selftest.sh|6|THE CLASS ITSELF, HELD STILL. \`_piped\`/\`_piped_builtin\`/\`_piped_ignored\` and \`_stat\`/\`_stat_builtin\`/\`_stat_ignored\` ARE the retired construct — that file's CONTROL 1 asserts the defect happens on this host right now, and would stop being able to fail if these were rewritten. Every one runs inside its own \`( … )\` subshell with the producer reading a fixture the file sizes and asserts. Fixing them would delete the only place in this repo where the bug is observable."
)

# ── the derivation ──────────────────────────────────────────────────────────────────────────
#
# awk, not grep: joining line continuations is a stateful scan a line-oriented match cannot do,
# and an occurrence COUNT needs a repeated match within one logical line.
_pmg_awk='
{
    if (cont != "") { L = cont " " $0 } else { L = $0; start = NR }
    if (L ~ /\\[[:space:]]*$/) { sub(/\\[[:space:]]*$/, "", L); cont = L; next }
    cont = ""
    if (L ~ /^[[:space:]]*#/) next
    # A leading `|` on a continued line would be lost by the [^|] guard below, so pad.
    line = " " L
    c = 0
    while (match(line, /[^|][[:space:]]*\|[[:space:]]*grep[[:space:]]+(-[a-zA-Z]*q[a-zA-Z]*|--quiet|--silent)([[:space:]]|$)/)) {
        c++
        line = " " substr(line, RSTART + RLENGTH)
    }
    if (c > 0) printf "%s\t%s\t%s\n", REL, start, c
}'

# _pmg_files <root> — the population, re-derived from the tree with CI's own expression.
_pmg_files() {
    ( cd "$1" && { find bin hooks -maxdepth 1 -type f ! -name '*.py' 2>/dev/null
                   find tests -maxdepth 1 -type f -name '*.sh' 2>/dev/null; } | LC_ALL=C sort )
}

# _pmg_records <root> — one TAB record per logical line carrying the shape: relpath, line, count.
_pmg_records() {
    local root="$1" rel
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        [[ -f "$root/$rel" ]] || continue
        awk -v REL="$rel" "$_pmg_awk" "$root/$rel"
    done < <(_pmg_files "$root")
}

# _pmg_counts <root> — "<relpath> <total occurrences>", one line per file that carries any.
_pmg_counts() {
    _pmg_records "$1" | awk -F'\t' '{ n[$1] += $3 } END { for (f in n) printf "%s %s\n", f, n[f] }' \
        | LC_ALL=C sort
}

# _pmg_early_readers <root> — the ADVISORY wider-class count (see the header). Not asserted on.
_pmg_early_readers() {
    local root="$1" rel t=0 n
    while IFS= read -r rel; do
        [[ -f "$root/$rel" ]] || continue
        n="$(awk '
            { if (cont != "") { L = cont " " $0 } else { L = $0 }
              if (L ~ /\\[[:space:]]*$/) { sub(/\\[[:space:]]*$/, "", L); cont = L; next }
              cont = ""
              if (L ~ /^[[:space:]]*#/) next
              line = " " L
              while (match(line, /[^|][[:space:]]*\|[[:space:]]*(head|tail)[[:space:]]+-/)) {
                  c++; line = " " substr(line, RSTART + RLENGTH) } }
            END { print c+0 }' "$root/$rel")"
        t=$((t + n))
    done < <(_pmg_files "$root")
    printf '%s\n' "$t"
}

# ── controls: the scanner must find something, and must not find everything ──────────────────
#
# The assertions this gate ships are ABSENCE assertions, and a scanner matching NOTHING satisfies
# every one of them while measuring nothing at all. A planted positive is therefore asserted
# FIRST, and four planted negatives beside it — each pinned to a spelling that is NOT this defect
# and that a sloppier predicate would sweep up.
_mktmp_scratch
FIX="$TMP/fixture"; mkdir -p "$FIX/bin" "$FIX/tests" "$FIX/hooks"

# ⛔ THE POSITIVE FIXTURES ARE WRITTEN THROUGH A `@GQ@` PLACEHOLDER, EXPANDED AT WRITE TIME, AND
# THAT IS NOT A STYLE CHOICE. `tests/*.sh` is in this gate's own population, so a fixture spelling
# the construct literally would make THIS FILE a member — and the only ways out of that are to
# disposition the scanner in its own list (which is a gate excusing itself, and whose count then
# rots on every fixture edit) or to exclude this path from the scan (a hole exactly where the next
# author is most likely to reach for the idiom). Writing the shape as data leaves the gate with no
# exception at all. The NEGATIVE fixtures need no placeholder: not matching the predicate is the
# whole of what they assert, and their literal text is the evidence.
_plant() { sed -e 's/@GQ@/grep -q/g' -e 's/@GLONG@/grep --quiet/g' -e 's/@GLONG2@/grep --silent/g' > "$1"; }

# POSITIVE — the construct, in the exact spelling the migrated call sites wore.
_plant "$FIX/bin/planted-piped" <<'EOF'
#!/usr/bin/env bash
set -o pipefail
printf '%s\n' "$body" | @GQ@x "$needle" && echo true || echo false
EOF
# POSITIVE 2 — two on ONE line, and a continuation carrying the tail. Counted as two.
_plant "$FIX/tests/planted-two-selftest.sh" <<'EOF'
#!/usr/bin/env bash
a=$(printf x | @GQ@F y && echo t); b=$(printf x | @GQ@F z && echo t)
printf '%s\n' "$rows" | @GQ@iE '^kbcard$' \
    && ok "found" || bad "missing"
EOF
# NEGATIVE 1 — a herestring. Same question, no pipeline, no producer to signal.
cat > "$FIX/bin/planted-herestring" <<'EOF'
#!/usr/bin/env bash
grep -q "$needle" <<< "$body" && echo true || echo false
EOF
# NEGATIVE 2 — `||` immediately before the grep is a logical OR, not a pipe. This exact shape
# is live in tests/board-card-start-selftest.sh and a `\|` predicate reports it as a member.
cat > "$FIX/bin/planted-logical-or" <<'EOF'
#!/usr/bin/env bash
[[ -s "$log" ]] || grep -q "fix/card-4242-x" <<< "$out"
EOF
# POSITIVE 3 — the LONG forms. `--quiet` and `--silent` exit early exactly as `-q` does, and a
# short-cluster-only predicate reports neither.
_plant "$FIX/hooks/planted-long-flag" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$body" | @GLONG@ "$needle" && echo true || echo false
printf '%s\n' "$body" | @GLONG2@ "$needle" && echo true || echo false
EOF
# NEGATIVE 3 — a grep with no `q`: it does not exit early, so there is no window.
cat > "$FIX/hooks/planted-no-q" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$body" | grep -cF "$needle"
printf '%s\n' "$body" | grep -oE '[0-9]+'
EOF
# NEGATIVE 4 — the construct inside a COMMENT. Every header in this class narrates it.
_plant "$FIX/tests/planted-comment-selftest.sh" <<'EOF'
#!/usr/bin/env bash
# Never `printf … | @GQ@ "$x"`: under pipefail a MATCH reads as a non-match.
    #   printf '%s\n' "$b" | @GQ@x "$n" && echo true || echo false
has_line "$n" "$b"
EOF

echo "== the scanner finds the planted construct (positive controls) =="
eq "the population is the two derived sets, not a stored list" "7" \
   "$(_pmg_files "$FIX" | wc -l | tr -d ' ')"
eq "the canonical spelling is derived, a two-on-one-line file counts BOTH, and --quiet/--silent are not a way out" \
   "$(printf 'bin/planted-piped 1\nhooks/planted-long-flag 2\ntests/planted-two-selftest.sh 3\n')" \
   "$(_pmg_counts "$FIX")"

echo "== the scanner discriminates (negative controls) =="
PLANTED="$(_pmg_counts "$FIX")"
eq "a herestring is not a member"                     "false" "$(has 'planted-herestring' "$PLANTED")"
eq "a '||' before the grep is not a pipe"             "false" "$(has 'planted-logical-or'  "$PLANTED")"
eq "a grep with no -q does not exit early, not a member" "false" "$(has 'planted-no-q'     "$PLANTED")"
eq "the construct inside a COMMENT is prose, not a call site" "false" \
   "$(has 'planted-comment' "$PLANTED")"

# ── the denominator ─────────────────────────────────────────────────────────────────────────
#
# Printed on EVERY run, clean or not. A clean result over an unnamed population reports where the
# searcher stopped, not the state of the tree.
mapfile -t FILES     < <(_pmg_files "$ROOT")
mapfile -t RECORDS   < <(_pmg_records "$ROOT")
mapfile -t COUNTS    < <(_pmg_counts "$ROOT")

DERIVED="$(printf '%s\n' "${COUNTS[@]}" | awk 'NF { print $1 }')"
LISTED="$(printf '%s\n' "${DISPOSITIONED[@]}" | awk -F'|' 'NF { print $1 }' | LC_ALL=C sort -u)"
NEW="$(LC_ALL=C comm -23 <(printf '%s\n' "$DERIVED") <(printf '%s\n' "$LISTED"))"
STALE="$(LC_ALL=C comm -13 <(printf '%s\n' "$DERIVED") <(printf '%s\n' "$LISTED"))"

# COUNT drift on a file that IS dispositioned — the N+1th-copy case.
MOVED=""
for d in "${DISPOSITIONED[@]}"; do
    _f="${d%%|*}"; _rest="${d#*|}"; _want="${_rest%%|*}"
    _got="$(printf '%s\n' "${COUNTS[@]}" | awk -v f="$_f" 'NF && $1 == f { print $2 }')"
    [[ -n "$_got" ]] || continue          # absent entirely — STALE reports it, not this
    [[ "$_got" == "$_want" ]] || MOVED+="$_f: dispositioned for $_want, tree carries $_got"$'\n'
done

_count() { printf '%s\n' "$1" | awk 'NF' | wc -l | tr -d ' '; }
TOTAL="$(printf '%s\n' "${COUNTS[@]}" | awk 'NF { t += $2 } END { print t+0 }')"

echo "== denominator [piped-match-gate/v1] =="
printf '  shell files scanned (bin/ + hooks/ + tests/)                : %s\n' "${#FILES[@]}"
printf '  logical lines carrying `| grep -q…`                         : %s\n' "${#RECORDS[@]}"
printf '  OCCURRENCES of the construct                                : %s\n' "$TOTAL"
printf '  files carrying it                                           : %s\n' "$(_count "$DERIVED")"
printf '  dispositioned below                                         : %s\n' "$(_count "$LISTED")"
printf '  NEW / undispositioned files                                 : %s\n' "$(_count "$NEW")"
printf '  stale dispositions (listed, no longer derived)              : %s\n' "$(_count "$STALE")"
printf '  dispositioned files whose count MOVED                       : %s\n' "$(_count "$MOVED")"
printf '  ── ADVISORY, NOT GATED: the wider early-exit-reader class ──\n'
printf '  `| head`/`| tail -N` occurrences (see the header)            : %s\n' "$(_pmg_early_readers "$ROOT")"
printf '  per file:\n'
printf '%s\n' "${COUNTS[@]}" | awk 'NF { printf "    %-52s %s\n", $1, $2 }'

echo "== the derivation carries real data (control on the REAL tree) =="
# The fixture controls prove the predicate discriminates; this one proves it is pointed at the
# tree. Both absence assertions below are satisfied by a scan that read nothing.
eq "the scan of $ROOT reached files" "true" \
   "$([[ "${#FILES[@]}" -gt 20 ]] && echo true || echo false)"
eq "…and derived at least one occurrence" "true" \
   "$([[ "$TOTAL" -gt 0 ]] && echo true || echo false)"

echo "== every file carrying the construct is dispositioned =="
eq "undispositioned \`<producer> | grep -q\` (use the prelude's has_line/has, or add a line to DISPOSITIONED with its reason)" \
   "" "$NEW"

echo "== no disposition outlives the copies it excuses =="
eq "listed file the scanner no longer derives (drop the line)" "" "$STALE"

echo "== a NEW copy in an already-dispositioned file still reds =="
eq "dispositioned file whose occurrence count moved (the N+1th copy — re-read the reason, then update the count or remove the copy)" \
   "" "${MOVED%$'\n'}"

echo "== every disposition carries a reason, once =="
noreason=""
for d in "${DISPOSITIONED[@]}"; do
    _r="${d#*|}"; _r="${_r#*|}"
    [[ -n "$_r" ]] || noreason+="${d}"$'\n'
done
eq "disposition with no reason" "" "${noreason%$'\n'}"
dupes="$(printf '%s\n' "${DISPOSITIONED[@]}" | awk -F'|' 'NF { print $1 }' | LC_ALL=C sort | uniq -d)"
eq "duplicate disposition key" "" "$dupes"

_summary "piped-match-gate-selftest"
