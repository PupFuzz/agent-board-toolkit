#!/usr/bin/env bash
# board-card-start-selftest.sh — deterministic, network-free unit checks for the pure decision
# logic of `bin/board-card-start` and `bin/install-board-hooks`. Sources each bin (each must not
# run its main when sourced) and asserts on its pure functions. Matches the toolkit's selftest-CI
# convention (no bats/shunit2; a runnable script CI invokes).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
BCS="$HERE/../bin/board-card-start"
IBH="$HERE/../bin/install-board-hooks"
[[ -r "$BCS" ]] || { echo "selftest: $BCS not found" >&2; exit 1; }
[[ -r "$IBH" ]] || { echo "selftest: $IBH not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$BCS"   # returns early (sourced-guard) after defining the pure helpers
# shellcheck source=/dev/null
source "$IBH"   # main-guarded — defines _ibh_hooks_dir without running install

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }

# assert a function returns the expected exit status
expect_rc() { # <label> <expected-rc> <fn> <args...>
    local label="$1" exp="$2"; shift 2
    local rc=0; "$@" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq "$exp" ]] && ok "$label (rc=$rc)" || bad "$label expected rc=$exp got rc=$rc"
}
# assert a function prints the expected stdout
expect_out() { # <label> <expected> <fn> <args...>
    local label="$1" exp="$2"; shift 2
    local got; got="$("$@" 2>/dev/null || true)"
    [[ "$got" == "$exp" ]] && ok "$label" || bad "$label expected '$exp' got '$got'"
}

echo "== _bcs_is_placeholder_host — reserved placeholders match (rc 0) =="
expect_rc "example.com"                0 _bcs_is_placeholder_host "https://example.com/api/v3"
expect_rc "sub.example.net"            0 _bcs_is_placeholder_host "https://kanban.example.net"
expect_rc "example.org with port"      0 _bcs_is_placeholder_host "https://example.org:8443/x"
expect_rc "kanban.invalid"             0 _bcs_is_placeholder_host "https://kanban.invalid/api/v3"
expect_rc "bare .test"                 0 _bcs_is_placeholder_host "https://board.test"
expect_rc "localhost"                  0 _bcs_is_placeholder_host "https://localhost:8000"
expect_rc "bare .example TLD"          0 _bcs_is_placeholder_host "https://kanban.example"
expect_rc "empty is a placeholder"     0 _bcs_is_placeholder_host ""

echo "== _bcs_is_placeholder_host — REAL hosts do NOT match (rc 1) — the F1 anchoring guard =="
expect_rc "latest-corp (…test… substr)" 1 _bcs_is_placeholder_host "https://kanban.latest-corp.com"
expect_rc "mytest.company.io"           1 _bcs_is_placeholder_host "https://mytest.company.io"
expect_rc "example-corp.net"            1 _bcs_is_placeholder_host "https://example-corp.net"
expect_rc "testflight.company.com"      1 _bcs_is_placeholder_host "https://kanban.testflight.company.com"
expect_rc "localhost.mycorp.net"        1 _bcs_is_placeholder_host "https://boards.localhost.mycorp.net"
expect_rc "a real prod host"            1 _bcs_is_placeholder_host "https://kanban.bwtekmed.com/api/v3"

echo "== _ibh_hooks_dir — install-target resolution + refuse discriminator (F7) =="
expect_rc  "unset → default .git/hooks (safe)"  0 _ibh_hooks_dir "/repo" ""
expect_out "unset → default path"   "/repo/.git/hooks"     _ibh_hooks_dir "/repo" ""
expect_rc  "relative .githooks (tracked) → REFUSE" 3 _ibh_hooks_dir "/repo" ".githooks"
expect_rc  "relative .git/hooks (under .git) → safe" 0 _ibh_hooks_dir "/repo" ".git/hooks"
expect_rc  "absolute out-of-tree → safe"        0 _ibh_hooks_dir "/repo" "/etc/git/hooks"
expect_rc  "absolute inside tree → REFUSE"      3 _ibh_hooks_dir "/repo" "/repo/.githooks"
expect_out "relative .githooks resolves vs root" "/repo/.githooks" _ibh_hooks_dir "/repo" ".githooks"

echo "== kb_bcs_log — writes the durable log (F5) + is set -u-safe with branch unset =="
_tmpd="$(mktemp -d)"
KB_BCS_LOG="$_tmpd/bcs.log" kb_bcs_log "unit probe reason" >/dev/null 2>&1 || true
if grep -q "unit probe reason" "$_tmpd/bcs.log" 2>/dev/null; then ok "log line written"; else bad "log line not written to KB_BCS_LOG"; fi
rm -rf "$_tmpd"

echo
if [[ "$fails" -eq 0 ]]; then echo "board-card-start-selftest: ALL PASS"; else echo "board-card-start-selftest: $fails FAIL(s)" >&2; exit 1; fi
