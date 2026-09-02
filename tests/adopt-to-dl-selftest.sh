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

# THE `--repo` PREDICATE IS NOT TESTED HERE ANY MORE, and that is a move rather than a drop
# (card#8421). `_ata_validate_repo` was a hand-rolled third copy of one accept-set; it is now
# `kb_is_repo_slug` in `bin/_kb-board-lib.sh`, called directly at this tool's readiness gate and
# by `bin/run-coverage-check`. Its arms — and the reasoning for every one of them — moved WITH
# it, to `tests/kb-board-lib-selftest.sh`, so the predicate is exercised in the file that owns
# it rather than in one of its two callers. What stays HERE is the end-to-end arm below that
# this tool actually refuses a bad `--repo` before anything is stamped.

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

# THE WIRING, not the predicate: `kb_is_repo_slug` is unit-tested in tests/kb-board-lib-selftest.sh,
# and NOTHING there can tell whether THIS tool still calls it. That is the gap the hoist opened —
# a bin that dropped the call would leave every lib arm green — so the readiness gate is driven
# for real here, on the spelling an operator most often pastes from a git remote. It must refuse
# BEFORE the board is named, which is what proves nothing was stamped: `--board` is supplied and
# the refusal must still be about the repo.
echo "== the --repo readiness gate calls the lib predicate, and refuses before the board =="
_rc=0; out="$(bash "$BIN" 4242 --repo "git@github.com:acme/widget" --board dev 2>&1)" || _rc=$?
if [[ "$_rc" -eq 2 ]]; then ok "an scp-style --repo is refused (rc 2)"
else bad "expected rc=2 for an scp-style --repo, got $_rc"; fi
case "$out" in *"--repo must be a bare <owner>/<name>"*) ok "…and the refusal names the flag and its shape" ;;
               *) bad "expected the --repo diagnostic, got: $out" ;; esac
case "$out" in *"board"*) bad "the run got as far as the board — the repo gate did not refuse first" ;;
               *) ok "…and it refused before the board was resolved (nothing stamped)" ;; esac
_rc=0; out="$(bash "$BIN" 4242 --repo "acme/widget.git" --board dev 2>&1)" || _rc=$?
case "$out" in *"--repo must be a bare <owner>/<name>"*) ok "a .git suffix is refused by the same gate" ;;
               *) bad "expected the --repo diagnostic for a .git suffix, got: $out" ;; esac
# CONTROL — a WELL-FORMED --repo gets PAST this gate. Without it every arm above is satisfied by
# a gate that refuses everything, which would be a tool that can adopt nothing at all.
_rc=0; out="$(bash "$BIN" 4242 --repo "acme/widget" 2>&1)" || _rc=$?
case "$out" in *"--repo must be a bare <owner>/<name>"*) bad "a well-formed --repo was refused by the repo gate" ;;
               *"--board <name> is required"*) ok "control: a well-formed --repo reaches the NEXT gate (--board)" ;;
               *) bad "expected the --board diagnostic after a good --repo, got: $out" ;; esac

# Every value-taking flag must be gated on the flag being SEEN with a value. `--dl ""` (an
# unexpanded variable) used to read as "no --dl" and take the MINT path — so a crash-retry that
# meant "re-stamp DL-N" would mint a SECOND DL, orphaning DL-N and stranding any branch or PR
# named for it. kbcard already rejected the identical input; this bin did not.
echo "== value-taking flags reject an empty value (kb_require_value) =="
# The population is DERIVED from the bin, not typed here (card#6645). A hand list cannot go red
# when the bin grows a flag, so a totality claim made over one narrows silently with every
# release — measured on this repo: `promote-stage-guard-selftest` named five of
# `promote-released-cards`' six guarded flags for two minor versions under the same claim.
# `expect_value_flags` compares the list below against the bin's own guard call sites and reds
# in both directions, so this block's claim cannot outlive the population it is about.
VALUE_FLAGS=(--dl --issue --repo --board)
expect_value_flags "$BIN" "${VALUE_FLAGS[@]}"
for f in "${VALUE_FLAGS[@]}"; do
    _rc=0; out="$(bash "$BIN" 4242 "$f" "" 2>&1)" || _rc=$?
    if [[ "$_rc" -eq 2 ]]; then ok "$f '' is rejected (rc 2), not read as absent"
    else bad "$f '' expected rc=2, got $_rc"; fi
    case "$out" in *"$f requires a non-empty value"*) ok "…and the diagnostic names $f" ;;
                   *) bad "$f '' diagnostic missing, got: $out" ;; esac
done
# A trailing flag with no argument at all was a bare `shift` failure: rc 1, zero output.
_rc=0; out="$(bash "$BIN" 4242 --dl 2>&1)" || _rc=$?
if [[ "$_rc" -eq 2 ]]; then ok "a trailing --dl with no argument exits 2, not a silent rc 1"
else bad "trailing --dl expected rc=2, got $_rc"; fi
if [[ -n "$out" ]]; then ok "…and says why (it used to print nothing at all)"
else bad "trailing --dl produced no output"; fi

# ---------------------------------------------------------------------------
echo "== the card fetch: a 2xx whose body is not JSON at all (card#6426) =="
# kb_api decides success on the HTTP STATUS CLASS alone, so a 2xx carrying a proxy's HTML error
# page or a truncated read arrives at the board-confirm read as a success. An unguarded jq there
# exits 5 under `set -e` with jq's parse error as this tool's whole diagnostic — and the very
# next line is the guard that keeps an adoption ON THE RIGHT BOARD, so its input must never be
# a value nobody could read. Driven as a PROCESS (tests/_kb-api-stub.sh) so the real kb_api,
# kb_load_config and exit status are what the assertions see.
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"
_mktmp_scratch --home
kb_stub_scrub_env
kb_stub_board_config dev 42
kb_stub_install
kb_stub_route() {
    case "$1 $2" in
        "GET "*/tasks/*.json) printf '%s\n%s' "${KB_STUB_CARD_HTTP:-200}" \
                                     "${KB_STUB_CARD_BODY:-$CARD_OK_BODY}" ;;
    esac
}
CARD_OK_BODY='{"data":{"id":4242,"board_id":42,"payload":{}}}'
export CARD_OK_BODY
export -f kb_stub_route

_rc=0
_err="$(KB_STUB_CARD_BODY='<html><body>502 Bad Gateway</body></html>' \
        bash "$BIN" 4242 --repo owner/name --board dev 2>&1 >/dev/null)" || _rc=$?
if [[ "$_rc" -eq 1 ]]; then ok "an unreadable card body → rc 1, not jq's rc 5"
else bad "unreadable card body expected rc=1, got $_rc"; fi
case "$_err" in *"no board id could be read out of its body"*)
        ok "…refuses in adopt-to-dl's words, naming what was not read" ;;
    *)  bad "expected the unreadable-body refusal, got: $_err" ;; esac
case "$_err" in *"is on board ,"*)
        bad "the board-mismatch arm reported a card as being on board '' — a claim about a card this read never got an answer about" ;;
    *)  ok "…and does NOT report the card as being on an empty board" ;; esac
case "$_err" in *"parse error"*) bad "leaked jq's raw parse error: $_err" ;;
                              *) ok "…and leaks no raw jq parse error" ;; esac
if [[ "$(kb_stub_total)" -eq 1 ]]; then ok "…having issued exactly the one read, and no write"
else bad "expected exactly 1 request, got $(kb_stub_total)"; fi
# The control that makes all of the above a measurement: the SAME invocation against a
# well-formed body gets past the board guard (and fails later, at the mint, for want of a real
# next-dl) — so the refusal above is the unreadable body and not this bin being broken outright.
kb_stub_reset
_err="$(bash "$BIN" 4242 --repo owner/name --board dev 2>&1 >/dev/null)" || true
case "$_err" in *"no board id could be read out of its body"*|*"refusing to adopt on the wrong board"*)
        bad "a well-formed body still failed the board guard: $_err" ;;
    *)  ok "control: a well-formed body passes the board guard" ;; esac
unset -f kb_stub_route
unset CARD_OK_BODY

_summary "adopt-to-dl-selftest"
