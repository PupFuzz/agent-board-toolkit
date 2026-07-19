# shellcheck shell=bash
# _selftest-prelude.sh — shared harness for the tests/*-selftest.sh scripts.
#
# Sourced by each selftest AFTER it computes its own HERE:
#     HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
#     source "$HERE/_selftest-prelude.sh"
#
# It carries only the harness the selftests all shared verbatim — the assertion
# helpers (ok/bad/fails, eq, expect_rc/expect_out), the required-bin guard, the
# temp-dir+trap[+scratch-HOME] setup, and the PASS/FAIL summary. It defines no test
# cases and asserts nothing; the fixtures and cases stay in each selftest.
#
# It deliberately does NOT run `set` — each selftest keeps its own shell options
# (board-snapshot omits -e on purpose). A selftest that needs a variant helper simply
# defines its own after sourcing (kb-board-lib's expect_rc/expect_out delegate to eq).

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }

# eq <label> <expected> <got> — string-equality assertion.
eq() { [[ "$2" == "$3" ]] && ok "$1" || bad "$1 — expected '$2' got '$3'"; }

# expect_rc <label> <expected-rc> <fn> <args...> — assert a call's exit status.
expect_rc() {
    local label="$1" exp="$2"; shift 2
    local rc=0; "$@" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq "$exp" ]] && ok "$label (rc=$rc)" || bad "$label expected rc=$exp got rc=$rc"
}
# expect_out <label> <expected> <fn> <args...> — assert a call's stdout.
expect_out() {
    local label="$1" exp="$2"; shift 2
    local got; got="$("$@" 2>/dev/null || true)"
    [[ "$got" == "$exp" ]] && ok "$label" || bad "$label expected '$exp' got '$got'"
}

# _need <-r|-x> <path> [label] — guard a bin the test needs; exit 1 if it can't run.
# label defaults to the path, reproducing the "selftest: <path> not found" message.
_need() {
    local flag="$1" path="$2" label="${3:-$2}" have=1
    case "$flag" in
        -r) [[ -r "$path" ]] && have=0 ;;
        -x) [[ -x "$path" ]] && have=0 ;;
    esac
    [[ "$have" -eq 0 ]] || { printf 'selftest: %s not found\n' "$label" >&2; exit 1; }
}

# _mktmp_scratch [--home] — set TMP to a fresh temp dir + an EXIT trap that removes it.
# With --home, also export a scratch HOME=$TMP so no real ~/.kanban-* file taints a result.
_mktmp_scratch() {
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    if [[ "${1:-}" == "--home" ]]; then
        export HOME="$TMP"
        mkdir -p "$HOME"
    fi
}

# _summary <name> — the trailing PASS/FAIL block: fail loud on stderr + exit 1, else pass.
_summary() {
    if [[ "$fails" -gt 0 ]]; then
        echo "$1: $fails check(s) FAILED" >&2
        exit 1
    fi
    echo "$1: all checks passed"
}
