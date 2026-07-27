#!/usr/bin/env bash
# adopt-to-dl-selftest.sh — deterministic, network-free unit checks for the pure
# decision logic of `bin/adopt-to-dl`. Sources the bin (which must not run its
# main when sourced) and asserts on its pure functions. Matches the toolkit's
# selftest-CI convention (no bats/shunit2 dep; a runnable script CI invokes).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/adopt-to-dl"
_need -r "$BIN"
# shellcheck source=/dev/null
source "$BIN"

echo "== _ata_validate_repo =="
expect_rc "owner/name valid"          0 _ata_validate_repo "owner/name"
expect_rc "mixed-case owner valid"    0 _ata_validate_repo "AIMLA-org/platform"
expect_rc "no slash rejected"         2 _ata_validate_repo "owner"
expect_rc "two slashes rejected"      2 _ata_validate_repo "owner/name/extra"
expect_rc "full URL rejected"         2 _ata_validate_repo "https://github.com/owner/name"
expect_rc "whitespace rejected"       2 _ata_validate_repo "owner /name"
expect_rc "empty rejected"            2 _ata_validate_repo ""
expect_rc "empty owner rejected"      2 _ata_validate_repo "/name"
expect_rc "empty name rejected"       2 _ata_validate_repo "owner/"

echo "== _ata_pr_url =="
expect_out "placeholder url"          "https://github.com/owner/name/pull/0"        _ata_pr_url "owner/name"
expect_out "mixed-case preserved"     "https://github.com/AIMLA-org/platform/pull/0" _ata_pr_url "AIMLA-org/platform"

echo "== _ata_issue_url (issue-correlation source URL — mirror of _ata_pr_url) =="
expect_out "issue url carries the real #N"  "https://github.com/owner/name/issues/42"        _ata_issue_url "owner/name" 42
expect_out "mixed-case owner preserved"     "https://github.com/AIMLA-org/platform/issues/7" _ata_issue_url "AIMLA-org/platform" 7

echo "== _ata_adopt_decision (MUST-FIX-3 already-adopted guard) =="
# args: <existing-dl-int-or-empty> <requested-dl-int-or-empty>
expect_out "no existing, no --dl -> mint"                "mint"            _ata_adopt_decision "" ""
expect_out "no existing, --dl given -> use-requested"    "use-requested"   _ata_adopt_decision "" "5"
expect_out "existing, no --dl -> refuse-adopted"         "refuse-adopted"  _ata_adopt_decision "5" ""
expect_out "existing == requested -> retry"              "retry"           _ata_adopt_decision "5" "5"
expect_out "existing != requested -> refuse-conflict"    "refuse-conflict" _ata_adopt_decision "5" "7"

echo "== _ata_canon_source (server canonicalizeSource — lowercase) =="
expect_out "lowercases owner"          "aimla-org/platform"  _ata_canon_source "AIMLA-org/platform"
expect_out "already-lower unchanged"   "owner/name"          _ata_canon_source "owner/name"
expect_out "mixed name too"            "owner/my-repo"       _ata_canon_source "Owner/My-Repo"

# NB: the DL-int (lenient) and by-ref-hit predicates moved to the shared lib
# (kb_dl_int_lenient / kb_by_ref_hit) — their coverage lives in tests/kb-board-lib-selftest.sh.

# An explicitly-empty positional must not be swallowed: `adopt-to-dl "" 4242` used to adopt
# card 4242 while the caller had written two positionals. Presence is tracked as SEEN, never as
# non-empty — the v0.23.1 empty-value class, reaching positionals this time.
echo "== positional presence is SEEN, not non-empty =="
_rc=0; out="$(bash "$BIN" "" 4242 2>&1)" || _rc=$?
if [[ "$_rc" -eq 2 ]]; then ok "an empty positional does not let the next one become <card-id> (rc 2)"
else bad "expected rc=2 for an empty positional, got $_rc"; fi
case "$out" in *"is empty"*) ok "…and it names the EMPTY argument as the problem" ;;
               *) bad "expected the empty-argument diagnostic, got: $out" ;; esac
_rc=0; out="$(bash "$BIN" 4242 4243 2>&1)" || _rc=$?
if [[ "$_rc" -eq 2 ]]; then ok "two non-empty positionals are still rejected (rc 2)"
else bad "expected rc=2 for two positionals, got $_rc"; fi
case "$out" in *"unexpected extra argument"*) ok "…and that guard names itself (extra, not empty)" ;;
               *) bad "expected the extra-argument diagnostic, got: $out" ;; esac
_rc=0; out="$(bash "$BIN" 2>&1)" || _rc=$?
case "$out" in *"<card-id> is required"*) ok "no positional at all still reports the missing id" ;;
               *) bad "expected the required-id diagnostic, got: $out" ;; esac

_summary "adopt-to-dl-selftest"
