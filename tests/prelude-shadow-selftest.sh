#!/usr/bin/env bash
# prelude-shadow-selftest.sh — the prelude's helpers are not silently re-minted. TWO legs, over
# two different channels, and the difference between them is the whole of what this file covers:
#
#   LEG 1 — BY NAME. No `tests/*-selftest.sh` re-declares a helper `_selftest-prelude.sh` already
#           defines, except the variants sanctioned below by name.
#   LEG 2 — BY IDIOM. No file in the suite hand-spells the function-extraction the prelude's
#           `_fn_src`/`_adopt_fn` own, except the sites dispositioned below with their reason.
#
# ⛔ THIS FILE IS THE ONE OWNER OF WHAT THAT COVERAGE IS. `docs/CHANGELOG.md` and
# `docs/CONSOLIDATION-PLAN.md` point HERE rather than restating it, because three surfaces once
# said this guard "reds on the seventh copy" of `_adopt_fn` when leg 1 — all there was — reds
# only on a copy NAMED `_adopt_fn`, and a seventh hand-spelling under any other name left it at
# rc 0. Measured on `dev` at `52125a6`: two further copies had ALREADY been minted, in
# `promote-source-qualify-selftest.sh`, spelled in `awk` instead of `sed`, with this file green —
# the exact drift the docs promised was covered (card#8548). Leg 2 exists because of that
# measurement; the docs no longer describe either leg in their own words.
#
# WHY THIS FILE EXISTS. `has()` — a literal-substring assertion helper — was hand-copied into
# ten selftests, and one copy took its arguments in the opposite order. That divergence cannot
# go red: reversing the arguments of a substring test is neither a syntax nor a type error, so
# `has <haystack> <needle>` under a needle-first definition compares two unrelated strings,
# answers `false`, and EVERY assertion expecting `false` keeps passing while testing nothing.
# Per-file review could not see it either — the inverted file was internally consistent across
# its own eight call sites, so only comparing two definitions could reveal it (card#5740).
#
# THE COPIES WERE DELETED; THE RULE THAT KEEPS THEM DELETED WAS NOT WRITTEN. Card#5740 left
# `has()` with exactly one definition and a prelude comment saying it "lives here and nowhere
# else" — enforced by nothing. A comment is not a gate (the lesson `ci-matrix-parity-selftest`
# was built on), and the eleventh copy would be re-minted in silence with the whole suite
# green. Fixing N copies without the guard that forbids the N+1th leaves the defect's cause in
# place, so this is the closure of that class rather than a new one.
#
# WHAT IS FORBIDDEN IS SILENT DISAGREEMENT, NOT LOCAL DEFINITION. A selftest that needs a
# genuine variant may define one — the prelude's own docblock says so. What must not happen is
# a second definition of the SAME behaviour drifting from the shared one unobserved. The
# sanctioned variants are therefore allow-listed BY NAME here, one line each with its reason:
# adding a shadow costs an explicit edit to this file, which is exactly the review moment the
# ten silent copies never got.
#
# THE HELPER SET IS DERIVED FROM THE PRELUDE, NEVER RESTATED. A hardcoded list here would be a
# second copy of the prelude's own function list — this repo's recurring defect, and the one
# `ci-matrix-parity-selftest` and `help-output-selftest` each closed on their own registry. Add
# a helper to the prelude and it is guarded on the next run with no edit here.
#
# BOUND OF LEG 1, STATED SO IT IS NOT OVER-CITED: it compares NAMES, not behaviour. It catches a
# re-declared helper; it cannot catch a selftest that hand-rolls the same logic inline under a
# different name, and it says nothing about whether the prelude's own argument order is right.
# It closes the copy channel that actually minted the `has()` bug, not every conceivable one.
#
# ─────────────────────────── LEG 2: THE PREDICATE, STATED ───────────────────────────
#
# POPULATION — BOTH halves of `.github/workflows/ci.yml`'s shellcheck expression, unioned:
# `_shipped_shell_files` and `_selftest_shell_files` out of `tests/_shipped-shell-lib.sh`, which
# is this repo's ONE OWNER of that derivation (card#6911) and is sourced rather than re-spelled
# here. Re-derived on every invocation; no file list is stored, and no `find` is restated.
# `_ci_shellcheck_drift`, asserted below, is what reds if `ci.yml` stops running it.
#
# MEMBER — a FILE, `<relpath>`, carrying a COUNT. Not a line number: a line number rots on the
# next edit above it. The count is what makes the file-level key safe — a NEW occurrence inside
# an already-dispositioned file moves the count and reds, which is the N+1th case a bare per-file
# allow-list swallows.
#
# AN OCCURRENCE is a PATTERN LITERAL ANCHORING A SHELL FUNCTION'S DEFINITION LINE AT COLUMN ZERO,
# derived in TWO parts rather than as one regex, because the two axes have different populations:
#
#   1. THE ANCHOR — any character that is not alphanumeric, `_` or a space, immediately followed by
#      `^`. That character is the literal's OPENING DELIMITER, and the delimiter set is OPEN: `sed`
#      takes `\%…%`, `perl` takes `m{…}`, and there is no last one to enumerate.
#   2. THE NAME, searched ONLY INSIDE THAT SAME LITERAL — from the `^` up to the next occurrence of
#      the delimiter the anchor opened with (end of line if it does not close on that character).
#      An identifier (`$2` and `${x}` included, since the prelude's own anchor is parameterised),
#      optionally closing a group (`'^(uint_ok)\(\)'`), then `()`, with the backslashes `awk` and
#      `grep -E` need and a `*` quantifier optional. Two names inside one line count as two.
#
# WHATEVER SITS BETWEEN THE `^` AND THE NAME IS SKIPPED WHOLESALE — a group, a character class, an
# alternation. That vocabulary is regex syntax and is as open as the delimiter set; enumerating it
# is what an inclusion list looks like. Comment lines are excluded — a header narrating the idiom
# (this one does it repeatedly) is prose.
#   ⛔ THE ANCHOR IS THE PREDICATE, NOT THE TOOL, and that is the correction card#8548 exists
#     for. A list of known tool spellings is an inclusion list: it fails open on the next one,
#     which is precisely how two `awk` copies of `sed`'s job walked past leg 1. Whatever consumes
#     it — `sed -n …,/^}/p`, an `awk` range, a `grep -E`, a `sed` `i` planter — must first WRITE
#     that anchor, so the anchor is what is counted and a tool this file has never heard of is
#     still derived.
#   ⛔ AND THE DELIMITER IS NOT ENUMERATED EITHER — that was the same defect one level down. The
#     first cut of this leg took `/`; the second took `/ ' "` and shipped; BOTH were inclusion
#     lists one keystroke wide. Measured on this tree: the three-delimiter predicate was blind to
#     two live copies it should have censused — `locale-range-guard-selftest.sh` (a character
#     class between the `^` and the name) and `next-dl-selftest.sh` (an alternation group) — both
#     dispositioned below now that it can see them. Bounding the NAME search by the delimiter the
#     ANCHOR itself opened with is what lets the delimiter set stay open without reporting the
#     whole tree: an unrelated `foo()` further along the line is outside the literal and is not
#     counted (`hand-enumerated-population-census.sh:179` is exactly that line, and stays out).
#
# ⛔ WHAT IS NOT SCRIPTABLE, AND IS THEREFORE THE DISPOSITION LIST'S JOB. The scanner derives
# where the anchor IS; whether an occurrence should have been `_fn_src` is a judgement no regex
# makes — a single-line function `_fn_src`'s `^}` terminator cannot express, a definition-line
# LOCATE that wants one line rather than a body, and a mutation planter that inserts BEFORE the
# definition all wear the same anchor as the extraction this owns. So the scanner owns the
# population and the list owns the verdict, one line per file with its reason — and a file NOT in
# the list is RED, which is the only property that makes the pair worth anything.
#
# ⛔ WHAT LEG 2 STRUCTURALLY CANNOT SEE — stated so it is not over-cited:
#   * An extraction that does not anchor at column zero, or that locates the function some other
#     way entirely (by line number, by a `declare -f` in a subshell, by a Python reader).
#   * An anchor COMPOSED AT RUNTIME rather than written as a literal — `$0 ~ "^" fn "\\(\\)"`,
#     which is live in `token-duplication-selftest.sh`'s own call-site counter. Named rather than
#     chased: catching it means matching a bare `"^"`, which every unrelated anchored regex in
#     the tree also carries, and a predicate that reports the whole tree disposition-lists the
#     whole tree. A negative control below pins that this is the bound and not an accident.
#   * A NON-SHELL definition: `promote-source-qualify-selftest.sh` extracts a `jq` `def` with
#     `/def canon_source:/`, which is the same duplication shape and is NOT derived here.
#   * AN ANCHOR WHOSE NAME POSITION IS A CLASS RATHER THAN A NAME — `/^[A-Za-z_][A-Za-z0-9_]*\(\) \{/`
#     addresses ANY definition line, not one function's. Live in `_selftest-prelude.sh` itself
#     (`_fn_src`'s own swallow check) and in `_defs_in` below. It is not a hand-spelled copy of an
#     extraction — it is the shape `_fn_src` exists to be — so it is out of the population by
#     intent, and named here rather than left to look like an accident.
#   * WHAT MAY SIT BETWEEN THE NAME AND ITS `()` — the ONE axis still enumerated, and the only
#     inclusion list left in this predicate: a group-closing paren, spaces, `*`, and the
#     backslashes `awk`/`grep -E` need. `^name\s*\(\)` spelled with a `\s`, or with any other
#     regex shorthand in that position, is NOT derived. Stated by name because it IS a list, and
#     a list that is not written down is the defect this leg was minted for.
#   * A LITERAL WHOSE CLOSING DELIMITER IS A DIFFERENT CHARACTER FROM ITS OPENER — perl's `m{…}`,
#     `m(…)`, `m[…]`. The name window then ends at the next copy of the OPENING character rather
#     than at the true close, which can only TRUNCATE the search (a false negative), never widen
#     it. `m{^host_ok\(\) \{}` is still derived because the name precedes the `\{`; a name pushed
#     past a nested `{` would not be.
#   * A FILE OUTSIDE THAT POPULATION — a program file the suite feeds to a tool (`tests/x.awk`,
#     a `.py`, a `.pl`), and anything nested below the one level `ci.yml` checks
#     (`tests/lib/x.sh`, `bin/sub/y`). The population is CI's, and is deliberately not widened
#     past what CI analyses; a bound, not an oversight.
#   * WHETHER a dispositioned reason is TRUE. It is a recorded judgement re-read by whoever next
#     edits that file — not a proof.
#
# ⛔ `command grep`, never bare `grep`: in an interactive Claude Code shell `grep` is a function
# exec'ing `ugrep --ignore-files`, which honours `.gitignore` and still exits 0 — a truncated
# sweep that reads as a clean one. Every read below goes through `awk`.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_shipped-shell-lib.sh"

ROOT="$(cd "$HERE/.." && pwd)"
PRELUDE="$HERE/_selftest-prelude.sh"
_need -r "$PRELUDE"

# Sanctioned shadows: "<selftest basename>:<helper>" — one line per variant, with its reason.
# kb-board-lib-selftest's pair route their failures through the shared `eq` so the prelude's
# PASS/FAIL counter still sees them; they differ in reporting, not in what they assert.
SANCTIONED=(
    "kb-board-lib-selftest:expect_rc"
    "kb-board-lib-selftest:expect_out"
)

# _defs_in <file> — every top-level function that file defines, C-collated. ONE extractor,
# used for the prelude and for each selftest alike: a second copy specialised to the prelude is
# the duplication this very test forbids, and it would drift the moment one side learned a
# spelling the other did not.
#
# All three bash spellings are matched, and that is not padding. The guard is worth only the
# spellings it recognises: `has ()` (a space before the parens) and `function has {` (no parens
# at all) are valid bash and define exactly the same shadow as `has()`. A name-only regex would
# have let the next copy evade the guard by a keystroke while reading as covered.
#
# Anchored at column zero on purpose: a nested definition is indented, and only a top-level one
# shadows the sourced prelude for the rest of the script.
_defs_in() {
    sed -nE \
        -e 's/^(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\).*/\2/p' \
        -e 's/^function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\{.*/\1/p' \
        "$1" | LC_ALL=C sort -u
}

_is_sanctioned() {
    local pair="$1" s
    for s in "${SANCTIONED[@]}"; do
        [[ "$s" == "$pair" ]] && return 0
    done
    return 1
}

mapfile -t HELPERS < <(_defs_in "$PRELUDE")
[[ "${#HELPERS[@]}" -gt 0 ]] || bad "prelude defines no helpers — the derivation is broken, not the tree"

# THE PRELUDE'S CONTENTS, PRINTED RATHER THAN WRITTEN DOWN ANYWHERE. `_selftest-prelude.sh`'s own
# docblock used to enumerate them and went stale on every addition for three rounds running
# (card#8548); it now points here instead. This is that pointer's target: derived from the file
# on every run, so it cannot disagree with it, and a helper added tomorrow appears that day with
# no edit to this file or to the prelude's header.
echo "== denominator [prelude-helpers/v1] =="
printf '  helpers `_selftest-prelude.sh` defines : %s\n' "${#HELPERS[@]}"
printf '%s\n' "${HELPERS[@]}" | awk 'NF { printf "    %s\n", $0 }'

echo "== no selftest re-declares a prelude helper =="

shadows=""
for f in "$HERE"/*-selftest.sh; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f" .sh)"
    while read -r fn; do
        [[ -n "$fn" ]] || continue
        for h in "${HELPERS[@]}"; do
            if [[ "$fn" == "$h" ]]; then
                pair="${base}:${fn}"
                _is_sanctioned "$pair" || shadows+="${pair}"$'\n'
            fi
        done
    done < <(_defs_in "$f")
done

eq "no unsanctioned prelude-helper shadows" "" "${shadows%$'\n'}"

# The allow-list must not outlive what it excuses: a sanctioned entry naming a shadow that no
# longer exists is a stale exception that would silently re-permit a future copy of that name.
echo "== every sanctioned shadow still exists =="
for s in "${SANCTIONED[@]}"; do
    base="${s%%:*}" fn="${s##*:}"
    if [[ -e "$HERE/${base}.sh" && "$(has_line "$fn" "$(_defs_in "$HERE/${base}.sh")")" == true ]]; then
        ok "sanctioned $s is live"
    else
        bad "sanctioned $s no longer exists — remove the allow-list entry"
    fi
done

# The helper set is derived, so a prelude that stopped defining `has` would silently stop
# guarding the exact helper this class was minted on. Pin that one by name.
echo "== the helper this class was minted on is still derived =="
[[ "$(has_line has "$(printf '%s\n' "${HELPERS[@]}")")" == true ]] \
    && ok "has is in the derived helper set" \
    || bad "has is not in the derived helper set — the prelude no longer defines it"

# ═══════════════════════ LEG 2 — the hand-spelled-extraction census ═══════════════════════
#
# "<relpath>|<expected occurrences>|<reason they are permitted>". Three ways to red: a file the
# scanner derives that is not listed, a listed file the scanner no longer derives, and a listed
# file whose COUNT moved. The third is the N+1th-copy case.
EXTRACTORS=(
  "tests/_selftest-prelude.sh|1|THE OWNER. \`_fn_src\`'s \`sed\` range is the one sanctioned spelling in the suite; \`_adopt_fn\` is that plus an \`eval\`. Every other entry below is a residual measured against it."
  "tests/locale-range-guard-selftest.sh|1|RESIDUAL, OUT OF \`_fn_src\`'S REACH ENTIRELY: A NON-SHELL FILE, AND NOT AT COLUMN ZERO. It locates \`version_ok()\` inside \`.github/workflows/auto-tag-version.yml\`'s \`run:\` block — indented, with no \`^}\` line to stop at — then strips the indent and evals the one line. \`_fn_src\` anchors at column zero in a shell file and can express neither half. DERIVED ONLY SINCE THE DELIMITER SET STOPPED BEING A LIST: the \`[[:space:]]*\` between the \`^\` and the name made it invisible to the predicate this leg shipped with."
  "tests/next-dl-selftest.sh|1|RESIDUAL, MISSING PRIMITIVE: A ONE-LINE RANGE. \`grep -E '^(max_int|max_dl)\\(\\) \\{'\` lifts BOTH of next-dl's one-line primitives in one read and asserts it got exactly two lines. \`_fn_src\` now REFUSES a one-liner by name rather than handing back the next function's body with it, so this cannot migrate until the primitive has a one-line mode — and it wants two names at once, which it also does not have. DERIVED ONLY SINCE THE ANCHOR STOPPED BEING AN INCLUSION LIST: the alternation group hid it. \`reader-ref-canon-selftest.sh\` below is the same site's sibling, on \`max_int\` alone."
  "tests/promote-source-qualify-selftest.sh|2|RESIDUAL, MISSING PRIMITIVE: A ONE-LINE RANGE. Both anchors address \`_ata_canon_source\`, whose whole body is on its definition line. \`_fn_src\` REFUSES it, naming what the range would have swallowed (\`_ata_adopt_decision\`), so the blocker is the missing one-line MODE and not a silent wrong answer. One occurrence counts the fold; the other takes the single line as source text."
  "tests/promote-pagination-selftest.sh|1|RESIDUAL, MISSING PRIMITIVE: A ONE-LINE RANGE. \`grep -E '^uint_ok\\(\\)'\` over another one-line function — and one \`_fn_src\` cannot even ADDRESS: \`uint_ok()\` is followed by five spaces before its \`{\`, outside the single-space spelling the primitive recognises, so it exits 1 on the name rather than on the one-line shape. Both bounds are stated in its docblock. PR #323 named this site as a seventh extraction under a different mechanism and left it out of scope; it is why this leg's anchor stopped taking only \`/\`."
  "tests/reader-ref-canon-selftest.sh|1|RESIDUAL, MISSING PRIMITIVE: A ONE-LINE RANGE. \`grep -E '^max_int\\(\\) \\{'\` over next-dl's one-line \`max_int\`. Same shape and same blocker as the two entries above."
  "tests/promote-ref-canon-selftest.sh|1|A LOCATE, NOT AN EXTRACTION. It collects the DEFINITION LINES so its leg can assert there is EXACTLY ONE — an extraction that silently concatenated two definitions is the failure it exists to catch, so it must not stop at the first."
  "tests/url-userinfo-render-selftest.sh|1|A MUTATION PLANTER. \`sed\` \`i\` INSERTS a new line BEFORE the definition; the anchor addresses the site, nothing is read out of it. Migrating it to \`_fn_src\` is not expressible and would not mean anything."
  "tests/readback-before-success-census.sh|1|RESIDUAL, OUT OF \`_fn_src\`'S REACH BY SHAPE: IT ASKS THE INVERSE QUESTION. \`_fn_src\` extracts a function GIVEN ITS NAME; this file has a LINE NUMBER in another repo file and needs the name and bounds of whatever function ENCLOSES it — there is no name to pass. The anchors locate every definition line in a \`bin/\` file so the last one at or above the call site can be selected, and it is not a selftest (it does not source the prelude at all, by the same design decision that keeps it out of the \`*-selftest.sh\` glob). A \`_fn_at_line\` primitive would absorb it; nothing else in the suite has wanted one."
  "tests/token-duplication-selftest.sh|1|A MUTATION PLANTER. An \`awk\` rule that copies the lib and injects an unmirrored \`_kb_expand_home\` call after \`kb_resolve_env\`'s definition line — the NEGATIVE control for card#8548's call-graph pin. Nothing is extracted; the anchor names where to insert."
)

# _extract_anchors <file> — "<line>\t<count>" per non-comment line carrying the anchor. ONE
# predicate, in the two parts the header states: `_EX_ANCHOR` finds the delimiter-plus-`^`, and
# `_EX_NAME` finds the function name inside the literal that anchor opened. The census total, the
# per-file counts and the fixture controls all read THIS FUNCTION, so a spelling one of them
# learned and another did not cannot exist.
#
# ⛔ THE DELIMITER IS TAKEN FROM THE LINE, NOT FROM A SET. `_EX_ANCHOR` accepts any non-word,
# non-space character before the `^`, and the character it matched is then used as the CLOSING
# delimiter for the name search. That is what makes the delimiter axis a derivation rather than
# the `/ ' "` list this leg shipped with — and what keeps it from reporting the whole tree: a
# `foo()` after the literal has closed is a call, not an anchor, and is not counted.
#
# The regexes are built as awk STRINGS rather than literals so this file is not a member of its
# own population — a literal `/^…()` here would make the scanner's own definition the thing it
# reds on, and the only ways out of that are excusing the gate in its own list (whose count then
# rots on every edit) or excluding this path (a hole exactly where the next author reaches for
# the idiom). Same reasoning, same fix, as `piped-match-gate-selftest.sh`'s `@GQ@` placeholder.
#
# ⛔ THEY TRAVEL THROUGH THE ENVIRONMENT, NOT THROUGH `-v`. awk applies escape processing to a
# `-v` assignment, so `\^`, `\(` and `\)` arrive as plain `^`, `(` and `)` — the regex still
# compiles, matches nothing here, and every absence assertion below passes over an empty scan.
# Measured: it did exactly that, loudly (`awk: warning: escape sequence …`) but at rc 0 per file.
# `ENVIRON[]` is handed over verbatim.
_EX_ANCHOR='[^A-Za-z0-9_ ]\^'
_EX_NAME='[A-Za-z_$][A-Za-z0-9_${}]*\\?\)?[ *]*\\?\(\\?\)'
_extract_anchors() {
    _EX_ANCHOR="$_EX_ANCHOR" _EX_NAME="$_EX_NAME" awk '
        $0 ~ /^[[:space:]]*#/ { next }          # a header narrating the idiom is prose
        {
            line = $0; c = 0
            while (match(line, ENVIRON["_EX_ANCHOR"])) {
                d = substr(line, RSTART, 1)                 # the delimiter this literal opened with
                line = substr(line, RSTART + RLENGTH)       # everything after the ^
                p = index(line, d)                          # …up to where that literal closes
                if (p > 0) { seg = substr(line, 1, p - 1); line = substr(line, p + 1) }
                else       { seg = line;                  line = "" }
                while (match(seg, ENVIRON["_EX_NAME"])) { c++; seg = substr(seg, RSTART + RLENGTH) }
            }
            if (c > 0) printf "%s\t%s\n", NR, c
        }' "$1"
}

# _ex_files <root> — the population: CI's shellcheck expression, BOTH halves, unioned. It is not
# spelled out here. `tests/_shipped-shell-lib.sh` is this repo's declared ONE OWNER of that
# derivation (card#6911, minted because the same `find` had been hand-copied into three gates),
# and a fourth hand-copy here — in the gate whose whole job is to red on hand-copies — would be
# this class re-minted by the file that forbids it. Adopting it also buys the drift row: a copy is
# guarded by nothing, so a narrowed `ci.yml` would leave this leg scanning the old set and
# printing a denominator for a population CI no longer has.
_ex_files() {
    { _shipped_shell_files "$1"; _selftest_shell_files "$1"; } | LC_ALL=C sort
}

# _ex_counts <root> — "<relpath> <total>", one line per file carrying any.
_ex_counts() {
    local root="$1" rel n
    while IFS= read -r rel; do
        [[ -n "$rel" && -f "$root/$rel" ]] || continue
        n="$(_extract_anchors "$root/$rel" | awk -F'\t' '{ t += $2 } END { print t+0 }')"
        # `if`, not `[[ … ]] && printf`: an AND-list whose test fails is the loop body's last
        # command, and reasoning about whether errexit spares it is not worth a truncated scan.
        if [[ "$n" -gt 0 ]]; then printf '%s %s\n' "$rel" "$n"; fi
    done < <(_ex_files "$root") | LC_ALL=C sort
}

# ── controls: the scanner must find something, and must not find everything ──────────────────
#
# Leg 2's shipped assertions are ABSENCE assertions, and a scanner matching NOTHING satisfies
# every one of them while measuring nothing. A planted positive is asserted FIRST, and the
# negatives beside it are each pinned to a spelling that is NOT this idiom and that a sloppier
# predicate would sweep up — N2 and N3 are both live in this repo right now.
_mktmp_scratch
FIX="$TMP/fixture"; mkdir -p "$FIX/bin" "$FIX/tests" "$FIX/hooks"
# `@A@` writes `/^`; `@C@` writes the bare `^` for fixtures that carry their own quote
# delimiter. Both expand at write time — see `_EX_RE`'s comment for why the positives are data
# rather than literals. The negatives need no placeholder: not matching is the whole of what they
# assert, so their literal text is the evidence.
_plant() { sed -e 's/@A@/\/\^/g' -e 's/@C@/\^/g' > "$1"; }

# POSITIVE 1 — the `sed` body extraction, in the spelling the migrated sites wore.
_plant "$FIX/tests/planted-sed-selftest.sh" <<'EOF'
#!/usr/bin/env bash
src="$(sed -n '@A@fetch_whole_board() {/,/^}/p' "$PRC")"
EOF
# POSITIVE 2 — the `awk` range that walked past leg 1, a PARAMETERISED anchor (the prelude's own
# is `$2`), and TWO anchors on ONE line. Four occurrences over three lines. The range's CLOSING
# `/^\}/` is deliberately not one of them: it addresses a brace, not a function, and counting it
# would double every `sed`-range site's disposition.
_plant "$FIX/bin/planted-awk" <<'EOF'
#!/usr/bin/env bash
awk '@A@src_canon\(\) \{/ {f=1} f {print} f && @A@\}/ {exit}' "$BIN"
sed -n "@A@$2() {/,/^}/p" "$1"
a="$(sed -n '@A@foo() {/,/^}/p' "$X")"; b="$(sed -n '@A@bar() {/,/^}/p' "$X")"
EOF
# POSITIVE 3 — a tool this file has never heard of, IN THE SPELLING ITS AUTHORS ACTUALLY WRITE.
# ⛔ This control shipped once already with `@A@` here, i.e. `m{/^host_ok\(\) \{}` — a perl regex
# requiring a literal `/` before the anchor, which no perl author would type. Driven against a
# real function it extracted ZERO lines, while the real spelling below was MISSED by the
# predicate it was shipped to pin. A control written in a spelling its own author invented proves
# the sample matched, never that the pattern covers.
_plant "$FIX/hooks/planted-unknown-tool" <<'EOF'
#!/usr/bin/env bash
perl -ne 'print if m{@C@host_ok\(\) \{} .. m{^\}}' "$BIN"
EOF
# POSITIVE 5 — the DIALECTS the shipped `/ ' "` list could not see, one line each, every one of
# them a legal seventh copy: a `sed` CUSTOM delimiter, a character class between the `^` and the
# name, an alternation group, a `perl` group capture, and a `*` quantifier before the parens. Two
# of them are not hypothetical: the character class and the alternation group are the shapes
# `locale-range-guard-selftest.sh` and `next-dl-selftest.sh` wear, both live in this repo and both
# invisible to the three-delimiter predicate this leg shipped with.
_plant "$FIX/tests/planted-dialects-selftest.sh" <<'EOF'
#!/usr/bin/env bash
src="$(sed -n '\%@C@fetch_whole_board() {%,/^}/p' "$PRC")"
d="$(grep -E '@C@[[:space:]]*version_ok\(\)' "$WF" | head -1)"
n="$(grep -E '@C@(max_int|max_dl)\(\) \{' "$NDL")"
p="$(perl -0777 -ne 'print $1 if /@C@(board_report\(\) \{.*?^\})/ms' "$BIN")"
q="$(sed -n '/@C@src_canon *() {/,/^}/p' "$BIN")"
EOF
# POSITIVE 4 — the QUOTE delimiters, both of them. `grep -E '^uint_ok\(\)'` is live in this repo
# (`promote-pagination-selftest.sh`) and PR #323 named it as a seventh extraction it was leaving
# out of scope; the `"` line beside it is the same idiom with a parameterised name. The first cut
# of `_EX_RE` took `/` only and derived neither.
_plant "$FIX/tests/planted-quoted-selftest.sh" <<'EOF'
#!/usr/bin/env bash
u="$(grep -E '@C@uint_ok\(\)' "$PRC" || true)"
v="$(grep -E "@C@${fn}\(\)" "$PRC" || true)"
EOF
# NEGATIVE 1 — the idiom inside a COMMENT. Every header in this class narrates it.
_plant "$FIX/tests/planted-comment-selftest.sh" <<'EOF'
#!/usr/bin/env bash
# Never hand-spell `sed -n '@A@name() {/,/^}/p'` — use the prelude's _fn_src.
    #   src="$(sed -n '@A@x() {/,/^}/p' "$f")"
_fn_src "$BIN" name
EOF
# NEGATIVE 2 — the bash parameter-expansion RENAME. Live in kb-host-guard-selftest.sh beside its
# real anchor; a `()`-anywhere predicate counts that file TWICE per extraction and its
# disposition count then describes nothing.
cat > "$FIX/bin/planted-rename" <<'EOF'
#!/usr/bin/env bash
eval "${src/host_ok() \{/host_ok_prc() \{}"
EOF
# NEGATIVE 3 — a plain function DEFINITION at column zero. Every shell file in the population
# carries these; a predicate keyed on the `name() {` text alone reports the whole repo.
cat > "$FIX/tests/planted-definition-selftest.sh" <<'EOF'
#!/usr/bin/env bash
fetch_whole_board() {
    printf 'x\n'
}
_bs_body() { _fn_src "$BIN" board_report; }
EOF
# NEGATIVE 4a — an anchor COMPOSED at runtime out of a variable. Live in
# `token-duplication-selftest.sh`'s call-site counter; outside the bound the header states, and
# pinned here so that bound is legible rather than accidental.
cat > "$FIX/tests/planted-composed-selftest.sh" <<'EOF'
#!/usr/bin/env bash
awk -v fn="$1" '$0 ~ "^" fn "\\(\\)" { next }' "$2"
EOF
# NEGATIVE 4 — a `jq` def extraction. The same duplication shape, explicitly OUTSIDE the bound
# (see the header), and this pins that the bound is what the header says it is.
cat > "$FIX/hooks/planted-jq-def" <<'EOF'
#!/usr/bin/env bash
awk '/def canon_source:/ {f=1} f {print} f && /end;[[:space:]]*$/ {exit}' "$BIN"
EOF

# NEGATIVE 5 — an anchored regex and, LATER ON THE SAME LINE, an ordinary function CALL. This is
# the price of an open delimiter set, and the reason the name search stops where the literal
# closes: a predicate that just looked for `^` … `name()` anywhere on the line derives this, and
# `hand-enumerated-population-census.sh:179` is exactly this shape, live in the tree today.
cat > "$FIX/tests/planted-call-after-selftest.sh" <<'EOF'
#!/usr/bin/env bash
awk 'L ~ /^echo "== / { flush_block(); reset_block(i, b); next }' "$1"
EOF

echo "== leg 2: the scanner finds the planted idiom (positive controls) =="
eq "the fixture population is the two derived sets, not a stored list" "11" \
   "$(_ex_files "$FIX" | wc -l | tr -d ' ')"
eq "sed, awk, grep, perl and an unheard-of tool are all derived; the delimiter is taken from the line and not from a set; a class, a group or a quantifier between the anchor and the name is skipped; a parameterised anchor counts and two on one line count as two" \
   "$(printf 'bin/planted-awk 4\nhooks/planted-unknown-tool 1\ntests/planted-dialects-selftest.sh 5\ntests/planted-quoted-selftest.sh 2\ntests/planted-sed-selftest.sh 1\n')" \
   "$(_ex_counts "$FIX")"

echo "== leg 2: the scanner discriminates (negative controls) =="
PLANTED="$(_ex_counts "$FIX")"
eq "the idiom inside a COMMENT is prose, not a call site" "false" "$(has 'planted-comment'    "$PLANTED")"
eq "a \${var/host_ok() \\{/…} rename is not an anchor"     "false" "$(has 'planted-rename'     "$PLANTED")"
eq "a plain function DEFINITION is not an anchor"          "false" "$(has 'planted-definition' "$PLANTED")"
eq "a jq \`def\` extraction is outside the stated bound"    "false" "$(has 'planted-jq-def'     "$PLANTED")"
eq "an anchor composed at runtime is outside the stated bound" "false" "$(has 'planted-composed'  "$PLANTED")"
eq "a function CALL after the literal closed is not an anchor" "false" "$(has 'planted-call-after' "$PLANTED")"

# ── the denominator ─────────────────────────────────────────────────────────────────────────
#
# Printed on EVERY run, clean or not. A clean result over an unnamed population reports where the
# searcher stopped, not the state of the tree.
mapfile -t EX_FILES  < <(_ex_files "$ROOT")
mapfile -t EX_COUNTS < <(_ex_counts "$ROOT")

EX_DERIVED="$(printf '%s\n' "${EX_COUNTS[@]}" | awk 'NF { print $1 }')"
EX_LISTED="$(printf '%s\n' "${EXTRACTORS[@]}" | awk -F'|' 'NF { print $1 }' | LC_ALL=C sort -u)"
EX_NEW="$(LC_ALL=C comm -23 <(printf '%s\n' "$EX_DERIVED") <(printf '%s\n' "$EX_LISTED"))"
EX_STALE="$(LC_ALL=C comm -13 <(printf '%s\n' "$EX_DERIVED") <(printf '%s\n' "$EX_LISTED"))"

EX_MOVED=""
for d in "${EXTRACTORS[@]}"; do
    _f="${d%%|*}"; _rest="${d#*|}"; _want="${_rest%%|*}"
    _got="$(printf '%s\n' "${EX_COUNTS[@]}" | awk -v f="$_f" 'NF && $1 == f { print $2 }')"
    [[ -n "$_got" ]] || continue          # absent entirely — EX_STALE reports it, not this
    [[ "$_got" == "$_want" ]] || EX_MOVED+="$_f: dispositioned for $_want, tree carries $_got"$'\n'
done

_ex_count() { printf '%s\n' "$1" | awk 'NF' | wc -l | tr -d ' '; }
EX_TOTAL="$(printf '%s\n' "${EX_COUNTS[@]}" | awk 'NF { t += $2 } END { print t+0 }')"

echo "== denominator [prelude-extract-gate/v1] =="
printf '  shell files scanned (bin/ + hooks/ + tests/)                : %s\n' "${#EX_FILES[@]}"
printf '  OCCURRENCES of a hand-spelled function anchor               : %s\n' "$EX_TOTAL"
printf '  files carrying it                                           : %s\n' "$(_ex_count "$EX_DERIVED")"
printf '  dispositioned in EXTRACTORS                                 : %s\n' "$(_ex_count "$EX_LISTED")"
printf '  NEW / undispositioned files                                 : %s\n' "$(_ex_count "$EX_NEW")"
printf '  stale dispositions (listed, no longer derived)              : %s\n' "$(_ex_count "$EX_STALE")"
printf '  dispositioned files whose count MOVED                       : %s\n' "$(_ex_count "$EX_MOVED")"
printf '  per file:\n'
printf '%s\n' "${EX_COUNTS[@]}" | awk 'NF { printf "    %-52s %s\n", $1, $2 }'

echo "== leg 2: the derivation carries real data (control on the REAL tree) =="
# The fixture controls prove the predicate discriminates; this one proves it is pointed at the
# tree. Both absence assertions below are satisfied by a scan that read nothing.
eq "the scan of $ROOT reached files" "true" \
   "$([[ "${#EX_FILES[@]}" -gt 20 ]] && echo true || echo false)"
eq "…and derived at least one occurrence" "true" \
   "$([[ "$EX_TOTAL" -gt 0 ]] && echo true || echo false)"
# …and pointed at the population CI actually shellchecks. `_ex_files` derives it from
# `_shipped-shell-lib.sh`, which restates `ci.yml`'s two `find` expressions because a workflow
# `run:` string cannot source a bash lib — a restatement that can only be GUARDED, never deleted
# (canon #16). Without this row a narrowed `ci.yml` leaves the denominator above describing a
# set nobody checks, at rc 0.
eq "the population matches what ci.yml shellchecks" "" "$(_ci_shellcheck_drift "$ROOT")"

echo "== leg 2: every hand-spelled function extraction is dispositioned =="
eq "undispositioned function-extraction anchor (use the prelude's _fn_src/_adopt_fn, or add a line to EXTRACTORS with its reason)" \
   "" "$EX_NEW"

echo "== leg 2: no disposition outlives the copies it excuses =="
eq "listed file the scanner no longer derives (drop the line)" "" "$EX_STALE"

echo "== leg 2: a NEW copy in an already-dispositioned file still reds =="
eq "dispositioned file whose occurrence count moved (the N+1th copy — re-read the reason, then use _fn_src or update the count)" \
   "" "${EX_MOVED%$'\n'}"

echo "== leg 2: every disposition carries a reason, once =="
ex_noreason=""
for d in "${EXTRACTORS[@]}"; do
    _r="${d#*|}"; _r="${_r#*|}"
    [[ -n "$_r" ]] || ex_noreason+="${d}"$'\n'
done
eq "disposition with no reason" "" "${ex_noreason%$'\n'}"
eq "duplicate disposition key" "" \
   "$(printf '%s\n' "${EXTRACTORS[@]}" | awk -F'|' 'NF { print $1 }' | LC_ALL=C sort | uniq -d)"

_summary "prelude-shadow-selftest"
