# shellcheck shell=bash
# _shipped-shell-lib.sh — the ONE derivation of the shell-file populations that
# `.github/workflows/ci.yml` shellchecks, for the gates whose population IS one of them.
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
# ⛔ THE THREE COPIES ARE NOT THE SAME SET, AND FLATTENING THEM WOULD BE A REGRESSION. Two of
# them take `bin/`+`hooks/` only; `piped-match-gate-selftest.sh` deliberately ADDS `tests/*.sh`,
# because 44 of the 47 copies its class found were inside the harness. That divergence is
# reasoned at each call site and is not a defect to fix. So this file exports CI's two halves
# SEPARATELY and every caller composes the union it wants — the population is a PARAMETER, not
# a constant baked in here.
#
# ADOPTION IS BEHAVIOUR-PRESERVING BY CONSTRUCTION. `_shipped_shell_files` is byte-identical in
# output to the expression all three already run (same `find`, same `LC_ALL=C sort`, same
# relative paths, same `2>/dev/null`), and `_selftest_shell_files` likewise. A gate adopting it
# changes which line computes its population and nothing about what that population is; the
# other two can adopt it in their own PRs without touching this file.
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
# directory is excluded by `-type f`; `bin/__pycache__` is the one that appears, from CI's own
# `py_compile bin/*.py` step.
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
