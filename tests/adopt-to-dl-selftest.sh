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
# THE SHAPE-ONLY ROWS ABOVE ARE NOT THE WHOLE ACCEPT SET, and the gap is not cosmetic
# (card#8421). This predicate gates a value that is then spent TWICE, on both sides of ONE
# comparison: it is interpolated into the placeholder `pr_url` the card is STAMPED with, and
# into the `source=` of the step-5 by-ref VERIFY. A spelling that survives here therefore
# derives the SAME garbage on both sides, so the verify passes VACUOUSLY and "adopted =>
# correlatable" is certified by a check that could not have failed (canon #9) — while the
# bridge writeback and the reconcile, which derive the source through the server's own
# repoFromGitHubUrl, correlate the card to nothing.
#   * `git@github.com:acme/widget` — one slash, two non-empty parts, no whitespace, so the
#     shape ALONE accepts it (measured). It stamps `github.com/git@github.com:acme/widget/pull/0`,
#     whose capture is `git@github.com:acme/widget`; the verify then queries that same string.
#   * `acme/*` — same story, and the stored source is a literal `*` that names no repo.
#   * `acme/widget.git` — the one spelling that does NOT pass vacuously, and it is worse than a
#     refusal rather than better: repoFromGitHubUrl TRIMS the `.git`, so the card's derived
#     source is `acme/widget` while the verify queries `acme/widget.git` — it fails LOUD, AFTER
#     the card has already been stamped. Refusing before the write leaves nothing half-applied.
# The charset+shape pair asserted here is the one `bin/promote-released-cards` applies to
# `.promote.source` (`src_charset_ok` plus the shape `case`) — the same value at the other end
# of the same correlation. Keep the two in sync.
expect_rc "scp-style remote rejected" 2 _ata_validate_repo "git@github.com:acme/widget"
expect_rc "a .git suffix rejected"    2 _ata_validate_repo "acme/widget.git"
expect_rc "a glob is not a repo"      2 _ata_validate_repo "acme/*"
expect_rc "a URL scheme rejected"     2 _ata_validate_repo "ssh://git@github.com/acme/widget"
expect_rc "a colon is not in the set" 2 _ata_validate_repo "acme:x/widget"
# CONTROLS — without these a validator that refused EVERYTHING would pass every row above.
# Each is a spelling a real adoption uses and must keep accepting.
expect_rc "control: a plain repo passes"    0 _ata_validate_repo "acme/widget"
expect_rc "control: a dot inside a name"    0 _ata_validate_repo "acme/widget.js"
expect_rc "control: underscore + hyphen"    0 _ata_validate_repo "acme_org/my-repo"
expect_rc "control: digits either side"     0 _ata_validate_repo "acme2/widget3"

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
