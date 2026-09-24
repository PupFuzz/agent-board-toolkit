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

# ── the runbook half: `tests/` files that are SHIPPED BEHAVIOUR, not harness ─────────────────
#
# WHY A THIRD POPULATION EXISTS (card#10311). `tests/` holds two unlike things. Most of it is
# the harness, which discards a read's status ON PURPOSE. A few files are OPERATOR-RUN CHECKS
# that happen to live there — `framework-mirror-check.sh` is one: `VERSIONING.md` release step
# 12 tells the operator to run it and to relay a re-sync request to ANOTHER REPO'S OWNER on a
# non-zero rc. That is shipped behaviour wearing a test's clothes, and the class gates whose
# population is "the shipped shell" were structurally blind to it: PR #387 shipped a
# read-outcome collapse in that very file and `read-outcome-collapse-selftest.sh` ran green
# over it, because `bin/`+`hooks/` cannot see `tests/`.
#
# ⛔ THE ANSWER IS NOT `_selftest_shell_files`. Unioning the whole harness in was MEASURED and
# rejected: it hands a class gate a pile of dispositions that mostly read "this is a test",
# and a reader who stamps a screenful of exemptions unread is not reading the next one either. The gate
# that adopts this composes `_shipped_shell_files` with THIS function, and says so.
#
# ⛔ AND IT IS NOT A HAND LIST. A named set checked into a gate is a restatement surface
# (canon #16) that cannot red when a runbook grows a step — the same defect one layer up as
# card#6645's. So membership is DERIVED FROM THE RUNBOOK: a check the operator is told to run
# is a check spelled as a COMMAND in a doc, and that is decidable.

# _md_fenced_lines <root> — every line INSIDE a fenced code block of a tracked `*.md`, as
# "relpath<TAB>lineno<TAB>text". The fence half is what discriminates: this tree's prose names
# its own tools constantly (README rows, changelog entries, `[link](tests/x.sh)`),
# and all of that is commentary rather than something an operator pastes.
#
# ⛔ THE `git ls-files` STATUS IS KEPT. An unreadable index and a tree with no tracked markdown
# would otherwise both arrive as "no lines", which is this repo's read-outcome-collapse class —
# in the derivation feeding the gate that exists to catch it. rc 3 says UNMEASURED; callers die
# on it rather than reporting an empty population.
#
# ⚠ What it cannot see: a fence opened with more than three backticks or with `~~~` (neither is
# used in this tree), and an indented (four-space) code block. `path-link-recipe-selftest.sh`
# states the same bound over the same primitive.
_md_fenced_lines() {
    local root="$1" files f
    files="$(cd "$root" && git ls-files '*.md')" || return 3
    [ -n "$files" ] || return 0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        awk -v F="$f" '
            /^[[:space:]]*```/ { fence = !fence; next }
            fence              { printf "%s\t%d\t%s\n", F, NR, $0 }
        ' "$root/$f"
    done <<< "$files"
}

# _runbook_invoked_checks <root> — the `tests/*.sh` files a tracked runbook INVOKES BY NAME, as
# repo-relative paths, C-collated and deduped. One line per file, however many times it is run.
#
# THE PREDICATE. A fenced line (above) whose COMMAND WORD is a `tests/…sh` path — after
# stripping leading whitespace, a `$ ` prompt, an explicit `bash `/`sh ` interpreter, and a
# leading `./`. The command-word anchor is the discriminating clause and is asserted against a
# fixture by the gate that adopts this, not assumed: `cat tests/x.sh` and `see tests/x.sh` are
# a file being READ and a file being NAMED, neither of which is an operator running a check.
#
# ⚠ WHAT IT STRUCTURALLY CANNOT SEE, stated so a small population is not over-read:
#   * A check invoked from a workflow rather than a runbook. That is deliberate, not a gap —
#     CI running `bash tests/X-selftest.sh` is the harness, which is the thing being excluded.
#   * A check named only in PROSE ("now run framework-mirror-check.sh"). The fence is the
#     evidence that a reader is meant to paste it; a prose mention is indistinguishable from
#     the commentary mentions this tree already carries in bulk.
#   * A check reached indirectly — through a `$VAR`, a wrapper script, or a `for` loop over a
#     glob. There is no literal path to key on.
#   * A runbook in another repo. This scans THIS tree's tracked markdown.
# A consumer of this population owes a NON-EMPTY control on the real tree: a predicate that has
# silently stopped matching is indistinguishable from a repo whose runbooks invoke nothing.
_runbook_invoked_checks() {
    local lines
    lines="$(_md_fenced_lines "$1")" || return $?
    printf '%s\n' "$lines" | awk '
        {
            L = $0
            if (!sub(/^[^\t]*\t[^\t]*\t/, "", L)) next
            sub(/^[[:space:]]+/, "", L)
            sub(/^\$[[:space:]]+/, "", L)
            sub(/^(bash|sh)[[:space:]]+/, "", L)
            sub(/^\.\//, "", L)
            if (match(L, /^tests\/[A-Za-z0-9_.-]+\.sh([[:space:]]|$)/)) {
                t = substr(L, RSTART, RLENGTH)
                sub(/[[:space:]]+$/, "", t)
                print t
            }
        }' | LC_ALL=C sort -u
}
