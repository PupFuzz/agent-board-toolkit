# shellcheck shell=bash
# _shipped-shell-lib.sh — the ONE derivation of the shell-file populations that
# `.github/workflows/ci.yml` shellchecks, for the gates whose population IS one of them —
# plus `_runbook_invoked_checks`, a DERIVED NARROWING of the `tests/` half (card#10311).
# Sourced after `_selftest-prelude.sh`, alongside it.
#
# WHY THIS EXISTS (card#6911). CI's shellcheck step names the population once:
#
#     run: shellcheck -S error $(find bin hooks -maxdepth 1 -type f ! -name '*.py'; find tests -maxdepth 1 -type f -name '*.sh')
#          ^ the `run:` prefix is ci.yml's own and is also load-bearing HERE: a comment line
#            whose first word is `shellcheck` is parsed as a shellcheck DIRECTIVE (SC1072/SC1073,
#            watched red on this very line), so quoting the command needs it kept.
#
# and by the time this file was written that expression had been hand-copied into THREE class
# gates — `read-outcome-collapse-selftest.sh` (card#7210), `piped-match-gate-selftest.sh`
# (card#7175) and `verdict-through-truncating-reader-selftest.sh` (card#6911) — plus their
# headers' prose. Canon #5 says extract at the SECOND real caller; the third is where it got
# noticed. Nothing was drifting yet at that moment, which is the only comfortable time to do it.
#
# ⛔ THE POPULATIONS ARE NOT THE SAME SET, AND FLATTENING THEM WOULD BE A REGRESSION.
# `verdict-through-truncating-reader-selftest.sh` takes `bin/`+`hooks/` only;
# `piped-match-gate-selftest.sh` deliberately ADDS all of `tests/*.sh`, because 44 of the 47
# copies its class found were inside the harness; `read-outcome-collapse-selftest.sh` takes
# `bin/`+`hooks/` plus a DERIVED NARROWING of `tests/` (`_runbook_invoked_checks`, below —
# card#10311), because one operator-run check lives there and the rest is harness. Each
# divergence is reasoned at its own call site and is not a defect to fix. So this file exports
# CI's halves SEPARATELY, plus the narrowing, and every caller composes the population it
# wants — the population is a PARAMETER, not a constant baked in here.
#
# ADOPTION IS BEHAVIOUR-PRESERVING BY CONSTRUCTION. `_shipped_shell_files` is byte-identical in
# output to the expression each gate already ran (same `find`, same `LC_ALL=C sort`, same
# relative paths, same `2>/dev/null`), and `_selftest_shell_files` likewise. A gate adopting it
# changes which line computes its population and nothing about what that population is;
# `piped-match-gate-selftest.sh` is the one gate still spelling the expression itself and can
# adopt in its own PR without touching this file.
#
# WHAT THIS DOES NOT FIX, STATED SO IT IS NOT OVER-CITED. It dedupes the DERIVATION, not the
# per-gate ROLL. Each gate still carries its own hand-maintained dispositions, and a new bin
# still costs one edit per gate — which is by design (a disposition is a per-class judgement
# and cannot be shared), and is what makes each gate red loudly on the day the bin lands. The
# card#6911 blocker that prompted this extraction was a STALE ROLL, not a drifted `find`; this
# file would not have caught it. Do not cite it as if it would.

# `.github/workflows/ci.yml` is the AUTHORITY for both halves, and it cannot source a bash lib
# from inside a `run:` string — so the restatement here cannot be deleted, only GUARDED
# (canon #16). These two constants are the guard's needles; `_ci_shellcheck_drift` below is the
# guard, and `verdict-through-truncating-reader-selftest.sh` runs it with planted controls.
_SSL_FIND_SHIPPED="find bin hooks -maxdepth 1 -type f ! -name '*.py'"
_SSL_FIND_SELFTESTS="find tests -maxdepth 1 -type f -name '*.sh'"

# _shipped_shell_files <root> — the SHIPPED shell: `bin/` + `hooks/`, one level, minus the
# python shims (shellcheck cannot parse them — SC1071 — which is why CI's own expression
# excludes them by name rather than by extension-guessing). Relative paths, C-collated. A
# directory is excluded by `-type f`; `bin/__pycache__` is the one that appears. CI's own
# syntax gate was minting it until card#7207 (it ran `py_compile bin/*.py`); a hand-run of the
# same command still can, which is why the exclusion is by TYPE and not by that name.
_shipped_shell_files() {
    ( cd "$1" && find bin hooks -maxdepth 1 -type f ! -name '*.py' 2>/dev/null | LC_ALL=C sort )
}

# _selftest_shell_files <root> — the other half of CI's expression: `tests/*.sh`, one level.
# A caller wanting the harness in its population unions this with the above; a caller whose
# class is about SHIPPED tools does not, and says so at its own call site.
_selftest_shell_files() {
    ( cd "$1" && find tests -maxdepth 1 -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort )
}

# _ci_shellcheck_drift <root> — empty when `ci.yml` still runs BOTH expressions above verbatim;
# otherwise one line per half that ci.yml no longer contains. This is the whole point of keeping
# the two literals: a workflow edit that narrows or widens CI's population without updating this
# file leaves every gate sourcing it measuring a set CI does not, and nothing else would notice.
# Substring containment, not line equality — the two halves share one `run:` line today and a
# later split across lines must not read as drift.
_ci_shellcheck_drift() {
    local wf="$1/.github/workflows/ci.yml" body
    if [ ! -r "$wf" ]; then printf '%s\n' "no readable .github/workflows/ci.yml at $wf"; return 0; fi
    body="$(cat "$wf")"
    case "$body" in *"$_SSL_FIND_SHIPPED"*) ;; *) printf '%s\n' "ci.yml no longer runs: $_SSL_FIND_SHIPPED" ;; esac
    case "$body" in *"$_SSL_FIND_SELFTESTS"*) ;; *) printf '%s\n' "ci.yml no longer runs: $_SSL_FIND_SELFTESTS" ;; esac
}

# ── the OPERATOR-RUN CHECKS under `tests/`, and the guards that keep that set complete ───────
#
# WHY A THIRD POPULATION EXISTS (card#10311). `tests/` holds two unlike things. Most of it is
# the harness, which discards a read's status ON PURPOSE. A few files are OPERATOR-RUN CHECKS
# that happen to live there: `framework-mirror-check.sh`, which `VERSIONING.md` release step 12
# tells the operator to run before relaying a re-sync request to ANOTHER REPO'S OWNER, and
# `install-board-hooks-capability-windows-check.sh`, which `docs/HOOKS.md` tells a Windows seat
# to run and send the whole output of. That is shipped behaviour wearing a test's clothes, and
# the class gates whose population is "the shipped shell" were structurally blind to it: PR #387
# shipped a read-outcome collapse in the first of those and `read-outcome-collapse-selftest.sh`
# ran green over it, because `bin/`+`hooks/` cannot see `tests/`.
#
# ⛔ THE ANSWER IS NOT `_selftest_shell_files`. Unioning the whole harness in was MEASURED and
# rejected: it hands a class gate a pile of dispositions that mostly read "this is a test", and
# a reader who stamps a screenful of exemptions unread is not reading the next one either.
#
# ⛔ AND IT IS NOT A HAND LIST. A named set checked into a gate is a restatement surface
# (canon #16) that cannot red when the tree grows a member — card#6645's class, one layer up.
#
# ⛔ AND IT IS NOT "WHAT A RUNBOOK INVOKES", WHICH IS WHAT THIS FILE TRIED FIRST AND GOT WRONG.
# That predicate has to parse markdown, and its miss is SILENT — a check whose invocation is an
# inline-code span, or is spelled `<toolkit>/tests/…`, or sits in a blockquoted fence, simply
# does not appear, and the gate stays green over a blind spot. `docs/HOOKS.md` invokes the
# Windows check in exactly that shape, so the first cut of this population reached ONE of the
# two operator-run checks in this tree while asserting there was only one. A predicate whose
# failure mode is a silent under-count has no business being the POPULATION of a gate whose
# whole subject is silent under-counting.
#
# ⇒ THE POPULATION IS A NAME. This repo already carries the kind of a `tests/` file in its
# FILENAME, and does so deliberately — `hand-enumerated-population-census.sh`'s own header
# records being named `*-census.sh` so `ci-matrix-parity-selftest.sh`'s orphan gate, whose
# population is `tests/*-selftest.sh`, does not claim it. Four kinds, and they PARTITION
# `tests/*.sh` exhaustively: `_*` libs and stubs, `*-selftest.sh` harness, `*-census.sh`
# instruments, `*-check.sh` operator-run checks. So `_operator_run_checks` is one glob over the
# tree — nothing to parse, nothing to spell, and no way for a doc's formatting to shrink it.
#
# TWO GUARDS KEEP THAT GLOB HONEST, because a naming convention with no check is a convention:
#   * `_tests_shell_unclassified` — a `tests/*.sh` matching NONE of the four kinds. That set
#     must stay empty. It is what makes the glob a COMPLETE population rather than a lucky one:
#     a new `tests/whatever.sh` reds, and its author has to say which kind it is.
#   * `_runbook_invoked_checks` — kept, DEMOTED from population to guard. A `tests/` file a
#     runbook invokes must be one of the four kinds; the shape it catches is an operator-run
#     check landing under an unrecognised name AND being wired into a doc. Its markdown reach is
#     bounded (below) and that is now tolerable: a miss weakens a secondary check instead of
#     silently shrinking the population.

# _operator_run_checks <root> — THE POPULATION half: `tests/*-check.sh`, one level. Relative
# paths, C-collated. Re-derived on every call; no list anywhere.
_operator_run_checks() {
    ( cd "$1" && find tests -maxdepth 1 -type f -name '*-check.sh' 2>/dev/null | LC_ALL=C sort )
}

# _tests_shell_unclassified <root> — every `tests/*.sh` whose NAME does not say which of the
# four kinds it is. Empty on a healthy tree; a consumer asserts that and reds otherwise.
_tests_shell_unclassified() {
    _selftest_shell_files "$1" | awk '
        { n = $0; sub(/^tests\//, "", n) }
        n ~ /^_/            { next }
        n ~ /-selftest\.sh$/ { next }
        n ~ /-census\.sh$/   { next }
        n ~ /-check\.sh$/    { next }
        { print }'
}

# _md_fenced_lines <root> — every line INSIDE a fenced code block of a tracked `*.md`, as
# "relpath<TAB>lineno<TAB>text". The fence half is what discriminates: this tree's prose names
# its own tools constantly (README rows, changelog entries, `[link](tests/x.sh)`), and all of
# that is commentary rather than something an operator pastes.
#
# ⛔ A BLOCKQUOTED FENCE COUNTS. ``` > ```bash ``` opens a real code block that a reader pastes
# from, and this tree uses that shape in `docs/INSTALL.md` and `docs/UPGRADE.md` — two of them
# operator recipes. The toggle therefore accepts leading `>` markers, and the emitted TEXT has
# them stripped, so a consumer that EXECUTES a recipe line (`path-link-recipe-selftest.sh`)
# gets the command rather than `> command`. Before card#10311 round 2 both consumers were blind
# to it: a third copy of the `PATH` symlink loop planted in a blockquoted fence in the very file
# that owns that recipe left `path-link-recipe-selftest.sh` at `all checks passed`.
#
# ⛔ THE `git ls-files` STATUS IS KEPT. An unreadable index and a tree with no tracked markdown
# would otherwise both arrive as "no lines", which is this repo's read-outcome-collapse class.
# rc 3 says UNMEASURED. ⚠ KEEPING a status is not READING one — each consumer owes its own
# `|| die`, and both of this repo's do it at their call site; grep `_md_fenced_lines` to see.
#
# ⚠ What it still cannot see, enumerated because a fresh reader will trust this list: a fence
# opened with more than three backticks or with `~~~` (neither is used in this tree); an
# indented (four-space) code block; and a file that MIXES blockquoted and plain fences, since
# one toggle serves both (no tracked `*.md` does today — `_md_fence_parity` is not a thing, and
# if one appears the symptom is a swallowed or truncated block, not a quiet subset).
_md_fenced_lines() {
    local root="$1" files f
    files="$(cd "$root" && git ls-files '*.md')" || return 3
    [ -n "$files" ] || return 0
    while IFS= read -r f; do
        # belt-and-braces: `git ls-files` emits no blank line, so this cannot fire today. Its
        # twin in `read-outcome-collapse-selftest.sh`'s `_roc_records_over` IS load-bearing —
        # `"${h[@]:-}"` hands that loop one empty argument when the array is empty. Do not
        # delete them as a pair.
        [ -n "$f" ] || continue
        awk -v F="$f" '
            /^[[:space:]]*(>[[:space:]]*)*```/ { fence = !fence; next }
            fence {
                L = $0
                if (L ~ /^[[:space:]]*>/) sub(/^[[:space:]]*(>[[:space:]]?)+/, "", L)
                printf "%s\t%d\t%s\n", F, NR, L
            }
        ' "$root/$f"
    done <<< "$files"
}

# Two filters for `_md_fenced_lines` output, on stdin. Both exist so that NO caller re-spells
# the record decoder — two copies of a decoder in the change that hoists the record producer is
# the same defect one line down (canon #5, at the second caller).
#
# _md_fenced_text — prints the TEXT of every record, dropping the `relpath<TAB>lineno<TAB>`
# prefix. For a caller that parses the command.
_md_fenced_text() {
    awk '{ L = $0; if (sub(/^[^\t]*\t[^\t]*\t/, "", L)) print L }'
}

# _md_fenced_grep <ere> — prints WHOLE records whose TEXT matches <ere>, prefix intact. For a
# caller that selects on the command but needs the file and line to report with. The match is
# against the text alone, never the record: a path or a line number must not be able to satisfy
# a predicate about what a code block says.
_md_fenced_grep() {
    awk -v RE="$1" '{ T = $0; if (sub(/^[^\t]*\t[^\t]*\t/, "", T) && T ~ RE) print }'
}

# _runbook_invoked_checks <root> — the `tests/*.sh` files a tracked runbook INVOKES BY NAME, as
# repo-relative paths, C-collated and deduped. A GUARD INPUT, not the population (see above).
#
# THE PREDICATE. A fenced line whose COMMAND WORD is a `tests/…sh` path, after stripping, in
# order: leading whitespace; a `$ ` prompt; any number of `env VAR=value` prefixes; an
# interpreter (`bash`/`sh`) with any flags; a directory or placeholder prefix ending in `/`
# (`<toolkit>/`, `~/agent-board-toolkit/`, `"$TK"/`). A command-word position reached after a
# `&&`, `||`, `;` or `|` separator counts — `cd "$TK" && tests/x.sh` is an invocation. The
# path may be followed by whitespace, end-of-line, or a `|`/`>`/`;`/`&` operator.
#
# The command-word anchor is the discriminating clause and is asserted against a fixture by the
# gate that uses this, not assumed: `cat tests/x.sh` and a `[link](tests/x.sh)` are a file being
# READ and a file being NAMED, neither of which is an operator running a check.
#
# ⚠ WHAT IT STILL CANNOT SEE — and this list is the reason the population is a glob, not this:
#   * An invocation in an INLINE-CODE SPAN rather than a fence. This is not hypothetical: it is
#     how `docs/HOOKS.md` invokes the Windows check. Admitting inline spans wholesale was
#     measured and refused — this tree carries scores of spans that merely NAME a `tests/*.sh`
#     as a noun, and they would drown the signal.
#   * A check invoked from a workflow rather than a runbook — deliberate: CI running
#     `bash tests/X-selftest.sh` is the harness.
#   * A check named only in flowing prose, reached through a `$VAR`, a wrapper or a glob, or
#     invoked by a runbook in another repo.
_runbook_invoked_checks() {
    local lines
    lines="$(_md_fenced_lines "$1")" || return $?
    printf '%s\n' "$lines" | _md_fenced_text | awk '
        # drop leading `VAR=value ` assignment prefixes
        function unassign(C) {
            while (C ~ /^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]/)
                sub(/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/, "", C)
            return C
        }
        # drop a leading `-x ` / `--long ` flag run
        function unflag(C) {
            while (C ~ /^-[^[:space:]]*[[:space:]]/) sub(/^-[^[:space:]]*[[:space:]]+/, "", C)
            return C
        }
        # drop a directory or placeholder prefix — `<toolkit>/`, `~/agent-board-toolkit/`,
        # `"$TK"/`. No lookahead (POSIX awk has none): match the whole head, then keep the
        # strip only when what precedes `tests/` really is a path prefix.
        function undir(C,   head, pre) {
            if (!match(C, /^[^[:space:]]*tests\//)) return C
            head = substr(C, RSTART, RLENGTH)
            pre  = substr(head, 1, length(head) - length("tests/"))
            if (pre == "" || pre ~ /\/$/) return substr(C, length(pre) + 1)
            return C
        }
        {
            L = $0
            sub(/^[[:space:]]+/, "", L)
            sub(/^\$[[:space:]]+/, "", L)
            # a command word can also begin just after a separator
            n = split(L, seg, /&&|\|\||[;|]/)
            for (i = 1; i <= n; i++) {
                C = seg[i]
                sub(/^[[:space:]]+/, "", C)
                C = unassign(C)
                if (C ~ /^env[[:space:]]/) { sub(/^env[[:space:]]+/, "", C); C = unassign(C) }
                if (C ~ /^(bash|sh)[[:space:]]/) {
                    sub(/^(bash|sh)[[:space:]]+/, "", C); C = unflag(C)
                }
                C = undir(C)
                if (match(C, /^tests\/[A-Za-z0-9_.-]+\.sh([[:space:]]|[|>;&]|$)/)) {
                    t = substr(C, RSTART, RLENGTH)
                    sub(/[[:space:]|>;&]+$/, "", t)
                    print t
                }
            }
        }' | LC_ALL=C sort -u
}
