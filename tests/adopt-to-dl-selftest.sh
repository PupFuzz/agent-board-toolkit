#!/usr/bin/env bash
# adopt-to-dl-selftest.sh — deterministic, network-free unit checks for the pure
# decision logic of `bin/adopt-to-dl`. Sources the bin (which must not run its
# main when sourced) and asserts on its pure functions. Matches the toolkit's
# selftest-CI convention (no bats/shunit2 dep; a runnable script CI invokes).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
BIN="$HERE/../bin/adopt-to-dl"
[[ -r "$BIN" ]] || { echo "selftest: $BIN not found" >&2; exit 1; }
# shellcheck source=/dev/null
source "$BIN"

fails=0
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }

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

echo "== _ata_dl_int (server canonicalize('dl') — strip non-digits, collapse zeros) =="
expect_out "bare int"                  "42"    _ata_dl_int "42"
expect_out "DL-088 3-pad -> 88"        "88"    _ata_dl_int "DL-088"
expect_out "DL-0192 4-pad -> 192"      "192"   _ata_dl_int "DL-0192"
expect_out "lowercase dl- prefix"      "42"    _ata_dl_int "dl-042"
expect_out "empty -> empty"            ""      _ata_dl_int ""
expect_out "no digits -> empty"        ""      _ata_dl_int "DL-"
expect_out "all-zeros -> 0"            "0"     _ata_dl_int "DL-0000"
expect_out "multi-run strips all"      "20042" _ata_dl_int "v2-DL-0042"

echo "== _ata_by_ref_hit =="
expect_rc "card present -> hit"       0 _ata_by_ref_hit '{"data":[{"id":4020}]}'            4020
expect_rc "card present among many"   0 _ata_by_ref_hit '{"data":[{"id":4020},{"id":5}]}'   4020
expect_rc "different card -> miss"     1 _ata_by_ref_hit '{"data":[{"id":99}]}'              4020
expect_rc "empty data -> miss"        1 _ata_by_ref_hit '{"data":[]}'                        4020

echo
if [[ "$fails" -eq 0 ]]; then
    echo "adopt-to-dl-selftest: PASS"
else
    echo "adopt-to-dl-selftest: $fails FAILURE(S)" >&2
    exit 1
fi
