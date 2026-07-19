#!/usr/bin/env bash
# board-card-start-selftest.sh — deterministic, network-free unit checks for the pure decision
# logic of `bin/board-card-start` and `bin/install-board-hooks`. Sources each bin (each must not
# run its main when sourced) and asserts on its pure functions. Matches the toolkit's selftest-CI
# convention (no bats/shunit2; a runnable script CI invokes).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BCS="$HERE/../bin/board-card-start"
IBH="$HERE/../bin/install-board-hooks"
_need -r "$BCS"
_need -r "$IBH"
# shellcheck source=/dev/null
source "$BCS"   # returns early (sourced-guard) after defining the pure helpers
# shellcheck source=/dev/null
source "$IBH"   # main-guarded — defines _ibh_hooks_dir without running install

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

echo "== _bcs_explicit_card_id — named-card grammar incl. the glued card<N> spelling (card-4621) =="
expect_out "glued cardN (the fix)"              "4524" _bcs_explicit_card_id "fix/card4524-reorder-primitive"
expect_out "card-N (separator)"                 "4524" _bcs_explicit_card_id "fix/card-4524-x"
expect_out "card/N"                             "4524" _bcs_explicit_card_id "chore/card/4524"
expect_out "card#N (bridge grammar)"            "4524" _bcs_explicit_card_id "fix/card#4524-x"
expect_out "bare #N"                            "2950" _bcs_explicit_card_id "hotfix/#2950-thing"
expect_out "leading-zero strip"                 "42"   _bcs_explicit_card_id "chore/card0042"
expect_out "embedded 'card' (discard) → none"   ""     _bcs_explicit_card_id "feature/discard42-cleanup"
expect_out "embedded 'card' (wildcard) → none"  ""     _bcs_explicit_card_id "feat/wildcard-99-x"
expect_out "single-digit glued → none ({2,})"   ""     _bcs_explicit_card_id "fix/card3-redesign"
expect_out "a DL token is not a card id"        ""     _bcs_explicit_card_id "feature/dl212-event-gated"
expect_out "underscore sep is NOT explicit"     ""     _bcs_explicit_card_id "fix/card_4524-x"

echo "== _bcs_typed_card_id — typed-branch leading id (unchanged tier) =="
expect_out "typed leading id"                   "4524" _bcs_typed_card_id "fix/4524-slug"
expect_out "typed with #"                       "4524" _bcs_typed_card_id "feat/#4524"
expect_out "2-digit is not a typed id ({3,})"   ""     _bcs_typed_card_id "feat/12-bump"
expect_out "glued cardN is NOT a typed id"      ""     _bcs_typed_card_id "fix/card4524-x"

echo "== _bcs_branch_lint_warning — narrow, high-precision advisory (card-4621) =="
# Warns ONLY on a card-ish token the grammar just misses (a non-[-/#] separator).
lint_has() { # <label> <branch>  — asserts a non-empty warning naming the id
    local got; got="$(_bcs_branch_lint_warning "$2" 2>/dev/null || true)"
    [[ -n "$got" ]] && ok "$1" || bad "$1 expected a warning, got none"
}
lint_silent() { # <label> <branch> — asserts NO warning
    expect_out "$1" "" _bcs_branch_lint_warning "$2"
}
lint_has    "underscore sep (card_N) warns"        "fix/card_4524-x"
lint_has    "dot sep (card.N) warns"               "fix/card.4524"
lint_silent "glued cardN correlates → silent"      "fix/card4524-x"
lint_silent "card-N correlates → silent"           "fix/card-4524-x"
lint_silent "typed leading id correlates → silent" "fix/4524-slug"
lint_silent "a DL branch → silent"                 "feature/dl212-event-gated"
lint_silent "no card-ish signal → silent"          "docs/adoption-guide"
lint_silent "embedded 'card' (discard_42) → silent" "feature/discard_42-x"
lint_silent "single-digit (card_3) → silent ({2,})" "fix/card_3-x"

echo "== board-card-start --lint — the wiring the pre-push hook invokes (subprocess, network-free) =="
# --lint short-circuits before any board/network work; exercises the real arg path + exit code.
_lrc=0; _lout="$(bash "$BCS" --lint "fix/card_4524-x" 2>&1)" || _lrc=$?
[[ "$_lrc" -eq 0 ]] && ok "--lint exits 0 (fail-soft)" || bad "--lint expected rc=0 got $_lrc"
printf '%s' "$_lout" | grep -q "board-branch-lint:.*card 4524" && ok "--lint warns on the residual spelling" || bad "--lint did not warn: $_lout"
_lout="$(bash "$BCS" --lint "fix/card-4524-x" 2>&1 || true)"
[[ -z "$_lout" ]] && ok "--lint silent on the compliant spelling" || bad "--lint wrongly warned: $_lout"

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

echo "== install-board-hooks — end-to-end refuse/install (exercises _ibh_main, not just the pure fn) =="
if command -v git >/dev/null 2>&1; then
    _t="$(mktemp -d)"
    # in-tree core.hooksPath → must REFUSE LOUDLY (exit non-zero + guidance), never a bare exit
    # with no output (the set -e assignment dead-code bug the unit test can't see).
    git init -q "$_t/refuse"; git -C "$_t/refuse" config core.hooksPath .githooks
    _rc=0; _out="$(bash "$IBH" "$_t/refuse" 2>&1)" || _rc=$?
    [[ "$_rc" -ne 0 ]] && ok "in-tree hooksPath refused (rc=$_rc)" || bad "in-tree hooksPath must refuse (got rc=$_rc)"
    printf '%s' "$_out" | grep -q "resolves inside the tracked work tree" \
        && ok "refuse prints operator guidance" || bad "refuse guidance missing (set -e dead-code): $_out"
    # default repo (no hooksPath) → installs a symlink for EACH hook into .git/hooks
    git init -q "$_t/ok"
    if bash "$IBH" "$_t/ok" >/dev/null 2>&1 && [[ -L "$_t/ok/.git/hooks/post-checkout" ]]; then
        ok "default install symlinks .git/hooks/post-checkout"
    else
        bad "default install did not create the .git/hooks/post-checkout symlink"
    fi
    [[ -L "$_t/ok/.git/hooks/pre-push" ]] \
        && ok "default install symlinks .git/hooks/pre-push (card-4621)" \
        || bad "default install did not create the .git/hooks/pre-push symlink"
    rm -rf "$_t"
else
    echo "  skip (git not on PATH)"
fi

echo "== _bcs_patch — 2xx echoes success (no log); non-2xx durably logs the captured status; always fail-soft (#4510) =="
# Stub the shared writer so the decision logic is exercised network-free. Redefining kb_api here
# shadows the lib's (sourced via $BCS); this is the last block, so the stub can't leak into others.
_tmpd="$(mktemp -d)"
kb_api() { KB_HTTP=200; return 0; }   # success path
_out="$(KB_BCS_LOG="$_tmpd/ok.log" _bcs_patch 42 '{}' 'OKMSG-emitted' 'FAILMSG-reason' 2>&1 || true)"
printf '%s' "$_out" | grep -q 'OKMSG-emitted' && ok "2xx emits the success message" || bad "2xx did not emit success: $_out"
[[ ! -s "$_tmpd/ok.log" ]] && ok "2xx writes NO durable failure line" || bad "2xx wrote an unexpected failure line: $(cat "$_tmpd/ok.log")"
kb_api() { KB_HTTP=422; return 1; }   # non-2xx: KB_HTTP carries the code kb_api captured
_out="$(KB_BCS_LOG="$_tmpd/fail.log" _bcs_patch 42 '{}' 'OKMSG-emitted' 'FAILMSG-reason' 2>&1 || true)"
if grep -q 'FAILMSG-reason' "$_tmpd/fail.log" 2>/dev/null && grep -q 'HTTP 422' "$_tmpd/fail.log" 2>/dev/null; then
    ok "non-2xx durably logs the fail-reason + captured status"
else
    bad "non-2xx did not log fail-reason+status: $(cat "$_tmpd/fail.log" 2>/dev/null)"
fi
printf '%s' "$_out" | grep -q 'OKMSG-emitted' && bad "non-2xx wrongly emitted the success message" || ok "non-2xx does NOT emit the success message"
kb_api() { KB_HTTP=500; return 1; }
_rc=0; KB_BCS_LOG="$_tmpd/rc.log" _bcs_patch 42 '{}' 'x' 'y' >/dev/null 2>&1 || _rc=$?
[[ "$_rc" -eq 0 ]] && ok "returns 0 even on a failed write (fail-soft: never blocks a checkout)" || bad "returned rc=$_rc on failure (must be 0)"
rm -rf "$_tmpd"

_summary "board-card-start-selftest"
