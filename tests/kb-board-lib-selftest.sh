#!/usr/bin/env bash
# kb-board-lib-selftest.sh — deterministic, network-free unit checks for the config-resolution
# helpers in `bin/_kb-board-lib.sh` (kb_resolve_env / kb_load_host_env / kb_board_env_for /
# kb_board_env_get / kb_read_token). The lib is freely sourceable (no main), so these drive
# the real functions against synthetic env files under a scratch HOME. Matches the toolkit's
# selftest-CI convention (no bats/shunit2; a runnable script CI invokes).
#
# The token LADDER is the thing under test: a board env's KBCARD_TOKEN_FILE > the host env's >
# an ambient one > the coord credential store's `[kanban] api_token_file` pointer. It regressed
# silently once (#4325) because the first three are a property of source ORDER that nothing
# exercised. There is no DEFAULT rung: card#7245 removed the baked ~/.kanban-dev-token, so
# "nobody declared one and no store points at one" is a REFUSAL, and that refusal is asserted
# beside a witness that a declared path still resolves — an rc-only assertion here would be
# satisfied by a resolver that had stopped resolving anything at all. The fourth rung
# (card#7316) is a DISCOVERY rather than a declaration, so its section asserts both halves that
# a discovery has to satisfy: a seat that has a store pointer resolves through it, and a seat
# that has none behaves exactly as it did before the rung existed.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
LIB="$HERE/../bin/_kb-board-lib.sh"
_need -r "$LIB"
# shellcheck source=/dev/null
source "$LIB"
KB_PROG="kb-board-lib-selftest"

# Scratch HOME so no real ~/.kanban-* file can influence (or be influenced by) a result.
_mktmp_scratch --home
export KANBAN_HOST_ENV="$TMP/.kanban-host.env"

printf 'board-token\n'   > "$TMP/board.token"
printf 'host-token\n'    > "$TMP/host.token"
printf 'ambient-token\n' > "$TMP/ambient.token"
printf 'default-token\n' > "$TMP/.kanban-dev-token"
printf 'spaced-token\n'  > "$TMP/tok with space.token"

# expect_out drives a function and compares stdout; expect_rc compares exit status.
# These deliberately shadow the prelude's like-named helpers: this variant routes
# through eq() (different pass/fail wording), so it defines its own after sourcing.
expect_out() { # <label> <expected> <fn> <args...>
    local label="$1" exp="$2"; shift 2
    local got; got="$("$@" 2>/dev/null || true)"
    eq "$label" "$exp" "$got"
}
expect_rc() { # <label> <expected-rc> <fn> <args...>
    local label="$1" exp="$2"; shift 2
    local rc=0; "$@" >/dev/null 2>&1 || rc=$?
    eq "$label (rc)" "$exp" "$rc"
}

# reset_env: drop every var the resolvers read or publish, so each case starts from a known
# state — these functions communicate through globals and a leaked one would fake a pass.
reset_env() {
    unset KBCARD_API KBCARD_TOKEN_FILE KB_API KB_BOARD_ID KB_TOKEN KB_TOKEN_FILE \
          KB_BOARD_ENV KB_HOST_TOKEN_FILE KANBAN_EXPECTED_HOST COORD_CREDENTIALS
    : > "$KANBAN_HOST_ENV"
    # COORD_CREDENTIALS and the scratch store go with them (card#7316). The token ladder now
    # ends in a DISCOVERY — the coord credential store's `[kanban] api_token_file` — so an
    # operator shell exporting COORD_CREDENTIALS would point these cases at a REAL store, and a
    # store fixture written by one case would still be standing under the next. The scratch
    # HOME already makes the DEFAULT store path absent; this makes the override absent too.
    rm -rf "$TMP/.config/coord"
    # Every case below resolves an api base on kanban.test, and the api-host preflight
    # (card#7245) refuses a host nobody declared — so the baseline fixture declares it. The
    # preflight's OWN section re-points and unsets it deliberately; nothing else here should
    # be measuring that guard by accident.
    export KANBAN_EXPECTED_HOST="kanban.test"
}

# ---------------------------------------------------------------------------
echo "== kb_resolve_env — the token ladder (board > host > ambient; no default) =="

# 1. board env's KBCARD_TOKEN_FILE wins over the host's — the case v0.8.2 regressed.
reset_env
{ echo 'export KBCARD_API="https://kanban.test/api/v3"'; echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""; } > "$KANBAN_HOST_ENV"
{ echo 'KB_BOARD_ID=42'; echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\""; } > "$TMP/.kanban-x-board.env"
kb_resolve_env "$TMP/.kanban-x-board.env"; rc=$?
eq "board KBCARD_TOKEN_FILE wins over host (rc)" "0" "$rc"
eq "board KBCARD_TOKEN_FILE wins over host"      "$TMP/board.token" "${KB_TOKEN_FILE:-}"
eq "  and publishes KB_BOARD_ID"                 "42" "${KB_BOARD_ID:-}"
eq "  and publishes KB_BOARD_ENV"                "$TMP/.kanban-x-board.env" "${KB_BOARD_ENV:-}"

# 2. host's wins when the board env sets none.
reset_env
{ echo 'export KBCARD_API="https://kanban.test/api/v3"'; echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""; } > "$KANBAN_HOST_ENV"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
kb_resolve_env "$TMP/.kanban-x-board.env"
eq "host KBCARD_TOKEN_FILE used when board sets none" "$TMP/host.token" "${KB_TOKEN_FILE:-}"

# 3. an ambient one is used when neither config sets one (the tier below host).
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
export KBCARD_TOKEN_FILE="$TMP/ambient.token"
kb_resolve_env "$TMP/.kanban-x-board.env"
eq "ambient KBCARD_TOKEN_FILE used when no config sets one" "$TMP/ambient.token" "${KB_TOKEN_FILE:-}"

# 4. host BEATS ambient (source order) — not the reverse.
reset_env
{ echo 'export KBCARD_API="https://kanban.test/api/v3"'; echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""; } > "$KANBAN_HOST_ENV"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
export KBCARD_TOKEN_FILE="$TMP/ambient.token"
kb_resolve_env "$TMP/.kanban-x-board.env"
eq "host KBCARD_TOKEN_FILE beats an ambient one" "$TMP/host.token" "${KB_TOKEN_FILE:-}"

# 5. NOTHING declares one ⇒ rc 7, and no token file is published. There is no ~/.kanban-dev-token
# rung any more (card#7245) — and this box HAS that file (it is written at the top of this
# script), so the assertion is about the resolver's behaviour, not about the file's absence.
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
# ⛔ THE SENTINEL IS WHAT MAKES THE NEXT ASSERTION A MEASUREMENT. reset_env above UNSETS
# KB_TOKEN_FILE, so "it is empty afterwards" was true before kb_resolve_env was even called —
# the line passed against a resolver that had never touched the variable, and mutation 11
# redded the same claim at :160 and :234 while leaving this one green. Seeding a value that
# only the function under test can remove turns it into the check it was written to be: the
# "CLEARED FIRST" arm of kb_resolve_env is what has to run for this to pass.
KB_TOKEN_FILE="$TMP/STALE-FROM-A-PREVIOUS-RESOLVE.token"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "no declared token file is rc 7, not a default"   "7" "$rc"
eq "  and KB_TOKEN_FILE is not published"            ""  "${KB_TOKEN_FILE:-}"
eq "  even though ~/.kanban-dev-token EXISTS (control)" "true" \
   "$([[ -r "$TMP/.kanban-dev-token" ]] && echo true || echo false)"
msg="$(kb_resolve_env "$TMP/.kanban-x-board.env" 2>&1 >/dev/null || true)"
eq "  the refusal names the file to edit"            "true" "$(has "$TMP/.kanban-x-board.env" "$msg")"
eq "  the refusal names the line to add"             "true" "$(has 'export KBCARD_TOKEN_FILE=' "$msg")"
# WITNESS for the two absence assertions above: the very same fixture, with one declaration
# added, resolves. Without this, a kb_resolve_env that had stopped working entirely would
# satisfy every line in this block.
echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\"" >> "$TMP/.kanban-x-board.env"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" || rc=$?
eq "  …and the SAME fixture resolves once one is declared (witness)" "0" "$rc"
eq "  …to the declared path"                         "$TMP/board.token" "${KB_TOKEN_FILE:-}"

# ---------------------------------------------------------------------------
echo "== kb_declared_token_file — the coord-store rung (card#7316: DISCOVERED, pointer-only) =="

# WHAT THIS SECTION IS FOR. The rung is a fourth tier under the three above, and it is a
# DISCOVERY rather than a declaration — so two properties have to hold at once and neither
# implies the other: a seat that HAS a store pointer must resolve through it, and a seat that
# has NONE must behave exactly as it did before the tier existed. The precedence assertions
# are written so that MOVING the rung up the ladder reds them: each one puts a live, resolvable
# store fixture underneath a declaration and asserts the DECLARATION is what came out, and each
# is paired with a control that removes only the declaration and watches the same fixture
# resolve — without that control, "the declaration won" would also pass against a rung that
# never worked at all.
#
# ⛔ NO STORE VALUE IS EVER ASSERTED BY VALUE. The fixtures below include a token-shaped string
# in the two slots an operator really mis-pastes into; the assertions are that the refusal does
# NOT carry it and DOES carry the coordinate plus a `sha256:` fingerprint. A secret-shaped
# string in a test file is not a secret, but the assertion has to be written the way the
# production rule reads or it certifies nothing about that rule.

mk_store() {   # <path> <line>… — write a credential-store fixture, creating its directory
    local f="$1"; shift
    mkdir -p "$(dirname "$f")"
    printf '%s\n' "$@" > "$f"
}
# The board env every case in this section resolves; the host env declares only the api base,
# so nothing but the store can supply a token unless a case adds one.
mk_bare_board() {
    echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
    echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
}
printf 'coord-store-token\n' > "$TMP/store.token"
STORE_TOKEN_LEN=17          # length of the fixture's CONTENT — the witness is a length, never a value
DEFAULT_STORE="$TMP/.config/coord/credentials.ini"
PASTED='ghp_NOTAREALTOKEN000000000000000000000000'

# 1. THE DEFAULT STORE PATH is discovered — no COORD_CREDENTIALS needed.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $TMP/store.token"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "store pointer at the default path resolves (rc)" "0" "$rc"
eq "  …to the file the pointer names"                "$TMP/store.token" "${KB_TOKEN_FILE:-}"
# ⛔ THE LENGTH IS TAKEN ONLY ON A SUCCESSFUL READ. `${#KB_TOKEN}` on the failing path is an
# UNBOUND VARIABLE under this file's `set -u`, which aborts the whole script — so a regression
# in the rung would have killed the suite HERE and left every later case, including the
# no-store regression check, unrun and reported as nothing rather than as red. Measured: it
# did exactly that on the first mutation pass.
tok_len=0; kb_read_token "${KB_TOKEN_FILE:-}" 2>/dev/null && tok_len="${#KB_TOKEN}"
eq "  …and that file is the one holding the token (length witness, never the value)" \
   "$STORE_TOKEN_LEN" "$tok_len"

# 2. $COORD_CREDENTIALS overrides the default path — same rule the framework's resolver holds.
reset_env
mk_bare_board
mk_store "$TMP/elsewhere.ini" '[kanban]' "api_token_file = $TMP/store.token"
export COORD_CREDENTIALS="$TMP/elsewhere.ini"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "COORD_CREDENTIALS names the store (rc)"          "0" "$rc"
eq "  …and its pointer is what resolved"             "$TMP/store.token" "${KB_TOKEN_FILE:-}"

# 3. ⭐ THE REGRESSION THAT MATTERS: no store at all ⇒ byte-for-byte today's behaviour.
# Every existing seat is this case, so it asserts the rc, the unpublished path AND the two
# sentences of the refusal — a rung that had started answering on a box with no store would
# change one of them.
reset_env
mk_bare_board
KB_TOKEN_FILE="$TMP/STALE-FROM-A-PREVIOUS-RESOLVE.token"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "no store, nothing declared → still rc 7"         "7" "$rc"
eq "  and KB_TOKEN_FILE is still not published"      ""  "${KB_TOKEN_FILE:-}"
eq "  (control: the store file really is absent)"    "false" \
   "$([[ -e "$DEFAULT_STORE" ]] && echo true || echo false)"
msg="$(kb_resolve_env "$TMP/.kanban-x-board.env" 2>&1 >/dev/null || true)"
eq "  the refusal still names the file to edit"      "true" "$(has "$TMP/.kanban-x-board.env" "$msg")"
eq "  the refusal still names the line to add"       "true" "$(has 'export KBCARD_TOKEN_FILE=' "$msg")"
eq "  and it says NOTHING about a credential store"  "false" "$(has 'coord' "$msg")"

# 4. PRECEDENCE — a DECLARATION beats the discovery, at every one of the three declared tiers.
# Each case has a live store fixture in place; the control under it removes only the
# declaration and watches that same fixture resolve.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $TMP/store.token"
echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\"" >> "$TMP/.kanban-x-board.env"
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "a BOARD env's declaration beats the store"       "$TMP/board.token" "${KB_TOKEN_FILE:-}"

reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $TMP/store.token"
echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\"" >> "$KANBAN_HOST_ENV"
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "the HOST env's declaration beats the store"      "$TMP/host.token" "${KB_TOKEN_FILE:-}"

reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $TMP/store.token"
export KBCARD_TOKEN_FILE="$TMP/ambient.token"
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "an AMBIENT declaration beats the store"          "$TMP/ambient.token" "${KB_TOKEN_FILE:-}"

# CONTROL for all three: the fixture they were declared over is genuinely resolvable, so the
# three assertions above measured precedence and not a dead rung.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $TMP/store.token"
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "  (control: with the declarations removed, that same store resolves)" \
   "$TMP/store.token" "${KB_TOKEN_FILE:-}"

# 5. POINTER-ONLY — an INLINE [kanban] api_token is refused, and the refusal is the migration
# prompt. The value must not appear in it; the coordinate and the pointer spelling must.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token = $PASTED"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "an inline api_token does NOT resolve (rc 7)"     "7" "$rc"
eq "  and publishes no token file"                   ""  "${KB_TOKEN_FILE:-}"
msg="$(kb_resolve_env "$TMP/.kanban-x-board.env" 2>&1 >/dev/null || true)"
eq "  the refusal names the pointer form"            "true" "$(has 'api_token_file = <path>' "$msg")"
eq "  the refusal does NOT echo the inline value"    "false" "$(has "$PASTED" "$msg")"
# …AND THE INLINE BRANCH IS WHAT REFUSED IT, not the credential-shape guard one layer down.
# The value above is token-shaped, so BOTH guards would refuse it and the rc alone cannot say
# which fired (measured: a mutant that let the inline value through as a pointer still ended in
# rc 7, caught only by the message). A value no guard but this one recognises pins it.
mk_store "$DEFAULT_STORE" '[kanban]' 'api_token = short1'
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "  an inline value NOTHING else would flag is still refused" "7" "$rc"

# WITNESS: the same store, same box, with the inline value replaced by a pointer — so the two
# absence assertions above are about the inline FORM and not about a store that never parsed.
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $TMP/store.token"
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "  …while the pointer form in the SAME slot resolves (witness)" \
   "$TMP/store.token" "${KB_TOKEN_FILE:-}"

# 6. INLINE **and** POINTER — refused, because the framework's own resolver prefers the inline
# value, so honouring the pointer here would send a different credential than the framework does.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token = $PASTED" "api_token_file = $TMP/store.token"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "inline + pointer → refused, not resolved"        "7" "$rc"
msg="$(kb_resolve_env "$TMP/.kanban-x-board.env" 2>&1 >/dev/null || true)"
eq "  and says why the pointer was not taken"        "true" "$(has 'prefers the INLINE value' "$msg")"
eq "  still without echoing the inline value"        "false" "$(has "$PASTED" "$msg")"

# 7. A TOKEN PASTED INTO THE POINTER SLOT is refused HERE — the leak this rung would otherwise
# open, because a resolved KB_TOKEN_FILE is named verbatim by callers' own failure messages.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $PASTED"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "a credential-shaped pointer is refused (rc 7)"   "7" "$rc"
eq "  and is never published as a token file path"   ""  "${KB_TOKEN_FILE:-}"
msg="$(kb_resolve_env "$TMP/.kanban-x-board.env" 2>&1 >/dev/null || true)"
eq "  the refusal does NOT echo it"                  "false" "$(has "$PASTED" "$msg")"
eq "  the refusal fingerprints it instead"           "true" "$(has 'sha256:' "$msg")"
eq "  and names the store coordinate"                "true" "$(has '[kanban] api_token_file' "$msg")"
# CONTROL: an ordinary path through the very same code path is NOT flagged — the guard
# discriminates rather than refusing everything.
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $TMP/store.token"
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "  (control: an ordinary path is not mistaken for one)" "$TMP/store.token" "${KB_TOKEN_FILE:-}"

# 8. `~` and `$HOME` in the pointer are expanded — and NOT by eval.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' 'api_token_file = ~/store.token'
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "a leading ~ is expanded"                         "$TMP/store.token" "${KB_TOKEN_FILE:-}"
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' 'api_token_file = $HOME/store.token'
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "a leading \$HOME is expanded"                    "$TMP/store.token" "${KB_TOKEN_FILE:-}"

# 9. A pointer at a MISSING file is rc 5 (unreadable), NOT rc 7 (undeclared). A source that is
# SET but broken must be reported as broken, never degraded into "nobody declared one".
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $TMP/absent.token"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "a pointer at a missing file is rc 5, not rc 7"   "5" "$rc"
eq "  and the path it names is the pointer's"        "$TMP/absent.token" "${KB_TOKEN_FILE:-}"

# 10. Shapes that declare NOTHING for this rung — each must fall through to the refusal, and
# each is a shape a real store carries. `[kanban]` shipped as a COMMENTED TEMPLATE is the
# common one; a pointer in another section must not be read as kanban's.
for shape in commented other_section empty_value; do
    reset_env
    mk_bare_board
    case "$shape" in
        commented)    mk_store "$DEFAULT_STORE" '[kanban]' "# api_token_file = $TMP/store.token" ;;
        other_section) mk_store "$DEFAULT_STORE" '[github]' "api_token_file = $TMP/store.token" ;;
        empty_value)  mk_store "$DEFAULT_STORE" '[kanban]' 'api_token_file =' ;;
    esac
    rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
    eq "store shape '$shape' declares nothing → rc 7" "7" "$rc"
done

# 10b. A COMMENT NEITHER OPENS, CLOSES NOR FILLS A SLOT — asserted as a PROPERTY, with its
# limit stated, because mutation showed the obvious version of this check was a decoration.
#
# ⛔ NO FIXTURE HERE KILLS THE PARSER'S `#`/`;` SKIP, and that is a measurement rather than an
# oversight: a mutant that DELETED the skip left this whole section green. The reason is that
# the marker stays glued to the first token — a commented line's key trims to
# `# api_token_file`, which matches no key, and its first character is not `[`, so it can open
# no section either. The skip is therefore the INTENTIONAL handling of an input class this
# store is mostly made of, not the only thing standing between a comment and a match.
#
# What these two cases DO pin is the property itself, in both directions, against a future
# parse change that strips the marker: a bracketed comment (this store's comments
# cross-reference sections by name) must not close the section a pointer is in, and must not
# open one — the second direction being the wrong-token outcome, where another section's key is
# handed over as kanban's.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' '# resolution rides [git-credential-map] below' \
    "api_token_file = $TMP/store.token"
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "a bracketed COMMENT does not close the section" "$TMP/store.token" "${KB_TOKEN_FILE:-}"

reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[github]' '# the [kanban] section below holds the board token' \
    "api_token_file = $TMP/board.token"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "a bracketed COMMENT does not OPEN one either (rc 7)" "7" "$rc"
eq "  so another section's key is never taken as kanban's" "" "${KB_TOKEN_FILE:-}"

# 11. Two shapes where GUESSING would hand out a token, so the rung refuses instead: the key
# declared twice (a store the framework's own parser rejects outright), and a pointer holding
# one of the two escapes whose meaning changed when the framework stopped %-interpolating.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $TMP/store.token" "api_token_file = $TMP/board.token"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "a duplicated api_token_file is refused, not picked" "7" "$rc"
msg="$(kb_resolve_env "$TMP/.kanban-x-board.env" 2>&1 >/dev/null || true)"
eq "  and says it will not guess"                    "true" "$(has 'declared more than once' "$msg")"

reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' 'api_token_file = /tmp/a%%b/store.token'
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "an ambiguous %%-escape in the pointer is refused" "7" "$rc"

# 12. Key case: an exact match wins, and a case-folded key still resolves — the framework's
# resolver folds, so a store spelling that works there must not silently fail here.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "API_TOKEN_FILE = $TMP/store.token"
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "a case-folded key resolves"                      "$TMP/store.token" "${KB_TOKEN_FILE:-}"
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "API_TOKEN_FILE = $TMP/board.token" "api_token_file = $TMP/store.token"
kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || true
eq "an EXACT key beats a case-folded one"            "$TMP/store.token" "${KB_TOKEN_FILE:-}"

# 13. A store that EXISTS but cannot be READ is a fault, not an absence: the refusal still
# fires, and the operator is told the store was not consulted rather than left believing the
# credential they configured was ignored for no reason.
reset_env
mk_bare_board
mk_store "$DEFAULT_STORE" '[kanban]' "api_token_file = $TMP/store.token"
chmod 000 "$DEFAULT_STORE"
if [[ -r "$DEFAULT_STORE" ]]; then
    # Running as root (or on a filesystem that ignores the mode): the state this asserts cannot
    # be produced here, so say so rather than print a pass nothing measured.
    printf '  --   SKIPPED unreadable-store arm — chmod 000 is still readable by this user\n'
else
    rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
    eq "an unreadable store does not resolve (rc 7)"  "7" "$rc"
    msg="$(kb_resolve_env "$TMP/.kanban-x-board.env" 2>&1 >/dev/null || true)"
    eq "  and says the store was not consulted"       "true" "$(has 'is not readable' "$msg")"
fi
chmod 600 "$DEFAULT_STORE"
reset_env

# ---------------------------------------------------------------------------
echo "== kb_resolve_env — the api-host preflight (card#7245) =="

# The board and host envs are FINE in every case below; the only thing that moves is which
# host has been declared. rc 6 is reached before the token file is even located.
mk_ok_env() {
    reset_env
    { echo "export KBCARD_API=\"$1\""
      echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""; } > "$KANBAN_HOST_ENV"
    echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
}

mk_ok_env "https://kanban.test/api/v3"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" || rc=$?
eq "the declared host resolves (positive control)"   "0" "$rc"

mk_ok_env "https://board.kanban.test/api/v3"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" || rc=$?
eq "a subdomain of the declared host resolves"       "0" "$rc"

mk_ok_env "http://kanban.test/api/v3"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" || rc=$?
eq "http on the declared host resolves — the predicate is the HOST, not the scheme" "0" "$rc"

# The rc-6 arm returns BEFORE the token file is located, so this is the arm where a stale
# global is possible at all: a resolve that succeeded earlier in this shell has left one.
# Populated first, on purpose — without that the "no token file was even located" assertion
# below is satisfied by a variable that was already empty and measures nothing.
mk_ok_env "https://kanban.test/api/v3"
kb_resolve_env "$TMP/.kanban-x-board.env"
eq "  (a prior resolve populated the global — control)" "$TMP/host.token" "${KB_TOKEN_FILE:-}"
export KANBAN_EXPECTED_HOST="kanban.test"
# The successful resolve above RESTORED its api base into this shell, and an ambient
# KBCARD_API beats the host env's — so it has to go, or the next resolve re-reads the host
# this case is trying to move away from.
unset KBCARD_API
{ echo 'export KBCARD_API="https://kanban.example.invalid/api/v3"'
  echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""; } > "$KANBAN_HOST_ENV"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "an undeclared host is rc 6"                      "6" "$rc"
eq "  and no token file was even located"            ""  "${KB_TOKEN_FILE:-}"
msg="$(kb_resolve_env "$TMP/.kanban-x-board.env" 2>&1 >/dev/null || true)"
eq "  the refusal names the host it refused"         "true" "$(has 'kanban.example.invalid' "$msg")"
eq "  and names the file that points there"          "true" "$(has 'KBCARD_API' "$msg")"

# THE ARM THAT WOULD HAVE CAUGHT THE INCIDENT: the 00:42 write replaced ~/.kanban-host.env
# wholesale, which deleted KANBAN_EXPECTED_HOST along with everything else. A guard that only
# fired on "declared AND mismatched" would have been silent through exactly that write.
mk_ok_env "https://kanban.test/api/v3"
unset KANBAN_EXPECTED_HOST
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "NOTHING declared is rc 6 too — no host is recognised" "6" "$rc"
export KANBAN_EXPECTED_HOST=""
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "an EMPTY declaration is rc 6 as well"            "6" "$rc"

# ---------------------------------------------------------------------------
echo "== kb_resolve_env — KBCARD_API is host-only =="

# A board env that sets KBCARD_API is REFUSED (rc 4), not silently honored.
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
{ echo 'KB_BOARD_ID=42'; echo 'export KBCARD_API="https://board-set.test/api/v3"'; } > "$TMP/.kanban-api-board.env"
rc=0; kb_resolve_env "$TMP/.kanban-api-board.env" 2>/dev/null || rc=$?
eq "board-env KBCARD_API is refused" "4" "$rc"

# The refusal must be LOUD — a silent rc is what an operator never sees.
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
{ echo 'KB_BOARD_ID=42'; echo 'export KBCARD_API="https://board-set.test/api/v3"'; } > "$TMP/.kanban-api-board.env"
msg="$(kb_resolve_env "$TMP/.kanban-api-board.env" 2>&1 >/dev/null || true)"
case "$msg" in
    *"board-independent"*"$TMP/.kanban-api-board.env"*) ok "refusal names the offending file on stderr" ;;
    *) bad "refusal message missing/unhelpful: '$msg'" ;;
esac

# An ambient KBCARD_API still beats the host's (and does NOT trip the board-env refusal).
# The declared host is the AMBIENT one here, because that is the base this resolve ends up
# using — the api-host preflight judges what was resolved, not what the host env said.
reset_env
{ echo 'export KBCARD_API="https://host.test/api/v3"'
  echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""; } > "$KANBAN_HOST_ENV"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
export KBCARD_API="https://ambient.test/api/v3"
export KANBAN_EXPECTED_HOST="ambient.test"
kb_resolve_env "$TMP/.kanban-x-board.env"
eq "ambient KBCARD_API beats the host's" "https://ambient.test/api/v3" "${KB_API:-}"

# KBCARD_API must be restored in the caller's env — the probe unsets it internally, and a
# caller (or a child process) left with it missing would be a silent side effect.
eq "KBCARD_API restored in the caller's env after resolve" "https://ambient.test/api/v3" "${KBCARD_API:-}"

# ---------------------------------------------------------------------------
echo "== kb_resolve_env — no cross-call leak (sourcing mutates the caller's shell) =="
# Resolving board A then board B in ONE shell: B declares no token, so it must NOT come away
# with A's. kb_resolve_env sources into the caller, so without an explicit restore A's value
# would still be sitting there as B's "ambient" tier. Since card#7245 the outcome is a
# refusal rather than a fall to a default — same property, one fewer place to land.
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
{ echo 'KB_BOARD_ID=1'; echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\""; } > "$TMP/.kanban-one-board.env"
echo 'KB_BOARD_ID=2' > "$TMP/.kanban-two-board.env"   # sets NO token
kb_resolve_env "$TMP/.kanban-one-board.env"
eq "board A resolves to its own token"          "$TMP/board.token"       "${KB_TOKEN_FILE:-}"
rc=0; kb_resolve_env "$TMP/.kanban-two-board.env" 2>/dev/null || rc=$?
eq "board B (declares none) refuses"                "7" "$rc"
eq "  and does NOT come away with A's token"        "" "${KB_TOKEN_FILE:-}"
# The stronger form of the same property, and the one a stale GLOBAL would break: A's value
# is in KB_TOKEN_FILE when B's resolve starts, so "empty" above is only meaningful because
# a failed resolve CLEARS what it did not resolve. Asserted against A's actual path.
kb_resolve_env "$TMP/.kanban-one-board.env"
eq "  (A resolved again, so the global is populated — control)" "$TMP/board.token" "${KB_TOKEN_FILE:-}"
rc=0; kb_resolve_env "$TMP/.kanban-two-board.env" 2>/dev/null || rc=$?
eq "  a REFUSED resolve leaves no stale credential path behind" "" "${KB_TOKEN_FILE:-}"
eq "  …and no stale board env either"                          "" "${KB_BOARD_ENV:-}"

# ...and the ambient tier still works after a resolve has run.
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
export KBCARD_TOKEN_FILE="$TMP/ambient.token"
kb_resolve_env "$TMP/.kanban-one-board.env"   # board A: sets its own
kb_resolve_env "$TMP/.kanban-two-board.env"   # board B: none -> must fall to AMBIENT, not A's
eq "board B falls through to the ambient token, not A's" "$TMP/ambient.token" "${KB_TOKEN_FILE:-}"
eq "ambient KBCARD_TOKEN_FILE restored in the caller's env" "$TMP/ambient.token" "${KBCARD_TOKEN_FILE:-}"

# ---------------------------------------------------------------------------
echo "== kb_resolve_env — failure return codes =="
reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
rc=0; kb_resolve_env "$TMP/nope-board.env" 2>/dev/null || rc=$?
eq "unreadable board env → rc 2" "2" "$rc"

reset_env   # empty host env ⇒ no KBCARD_API anywhere
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-x-board.env"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "no KBCARD_API → rc 3" "3" "$rc"

reset_env
echo 'export KBCARD_API="https://kanban.test/api/v3"' > "$KANBAN_HOST_ENV"
{ echo 'KB_BOARD_ID=42'; echo "export KBCARD_TOKEN_FILE=\"$TMP/absent.token\""; } > "$TMP/.kanban-x-board.env"
rc=0; kb_resolve_env "$TMP/.kanban-x-board.env" 2>/dev/null || rc=$?
eq "unreadable token file → rc 5" "5" "$rc"

# ---------------------------------------------------------------------------
echo "== kb_load_config — the board-env-missing error names its fix (roundtable #89) =="

# A box with real board envs under non-dev names but NO ~/.kanban-dev-board.env and no
# KBCARD_BOARD_ENV: a bare (default) load must exit 2 AND tell the operator how to recover —
# name --board / KBCARD_BOARD_ENV and list the boards that DO exist. The rc-3/rc-4 sibling arms
# already name their fix; this one didn't, so a fresh non-`dev` box read the tool as "broken".
reset_env
rm -f "$TMP"/.kanban-*-board.env "$TMP/.kanban-dev-board.env"
unset KBCARD_BOARD_ENV
echo 'KB_BOARD_ID=7' > "$TMP/.kanban-sola-board.env"
echo 'KB_BOARD_ID=9' > "$TMP/.kanban-sandbox-board.env"
rc=0; msg="$(kb_load_config "" 2>&1 >/dev/null)" || rc=$?
eq "bare load, no default board → rc 2" "2" "$rc"
case "$msg" in *"board env file not readable"*) ok "  names the unreadable default env" ;;
    *) bad "  missing the base 'not readable' line: '$msg'" ;; esac
case "$msg" in *KBCARD_BOARD_ENV*) ok "  names KBCARD_BOARD_ENV as a fix" ;;
    *) bad "  error omits KBCARD_BOARD_ENV: '$msg'" ;; esac
case "$msg" in *"--board"*) ok "  names --board as a fix" ;;
    *) bad "  error omits --board: '$msg'" ;; esac
case "$msg" in *sola*sandbox*|*sandbox*sola*) ok "  lists the discovered boards (sola, sandbox)" ;;
    *) bad "  error does not list discovered boards: '$msg'" ;; esac

# A --board NAME whose env file is absent points at THAT file (not the default) and still names --board.
reset_env
rm -f "$TMP"/.kanban-*-board.env "$TMP/.kanban-dev-board.env"
unset KBCARD_BOARD_ENV
rc=0; msg="$(kb_load_config nope 2>&1 >/dev/null)" || rc=$?
eq "--board nope, no such env → rc 2" "2" "$rc"
case "$msg" in *".kanban-nope-board.env"*) ok "  names the named board's own env file" ;;
    *) bad "  --board error names wrong file: '$msg'" ;; esac
case "$msg" in *"--board"*) ok "  still points at --board" ;;
    *) bad "  --board error unhelpful: '$msg'" ;; esac

# No board envs on the box at all: still names the fix, says none were found (no empty list dangling).
reset_env
rm -f "$TMP"/.kanban-*-board.env "$TMP/.kanban-dev-board.env"
unset KBCARD_BOARD_ENV
rc=0; msg="$(kb_load_config "" 2>&1 >/dev/null)" || rc=$?
eq "no board envs → still rc 2" "2" "$rc"
case "$msg" in *"no ~/.kanban-*-board.env files found"*) ok "  says no board envs were found" ;;
    *) bad "  empty-discovery message unclear: '$msg'" ;; esac

# ---------------------------------------------------------------------------
echo "== kb_load_host_env =="
reset_env
{ echo 'export KBCARD_API="https://host.test/api/v3"'
  echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""
  echo 'export KANBAN_EXPECTED_HOST="host.test"'; } > "$KANBAN_HOST_ENV"
kb_load_host_env
eq "publishes KB_API from the host env"          "https://host.test/api/v3" "${KB_API:-}"
eq "publishes KB_HOST_TOKEN_FILE"                "$TMP/host.token" "${KB_HOST_TOKEN_FILE:-}"

# The regression the gated mode caused: a stray ambient KBCARD_API must NOT stop the host env
# from loading, or KANBAN_EXPECTED_HOST vanishes and every https-host guard fail-closes.
reset_env
{ echo 'export KBCARD_API="https://host.test/api/v3"'
  echo "export KBCARD_TOKEN_FILE=\"$TMP/host.token\""
  echo 'export KANBAN_EXPECTED_HOST="host.test"'; } > "$KANBAN_HOST_ENV"
export KBCARD_API="https://ambient.test/api/v3"
kb_load_host_env
eq "ambient KBCARD_API still wins"                        "https://ambient.test/api/v3" "${KB_API:-}"
eq "  but the host env STILL loaded (KANBAN_EXPECTED_HOST)" "host.test" "${KANBAN_EXPECTED_HOST:-}"
eq "  and the host token default STILL loaded"             "$TMP/host.token" "${KB_HOST_TOKEN_FILE:-}"

# No host env at all must not fail (it reads no token, so it has nothing to fail on).
reset_env
rm -f "$KANBAN_HOST_ENV"
# Sentinel, same reason as the rc-7 block above: reset_env UNSETS KB_API, so "empty
# afterwards" was already true before kb_load_host_env ran and the line passed against a
# function that never assigned. A stale KB_API from a previous host env is the thing worth
# catching, so seed one and require this call to have overwritten it.
KB_API="$TMP/STALE-API-FROM-A-PREVIOUS-LOAD"
rc=0; kb_load_host_env || rc=$?
eq "no host env → still rc 0" "0" "$rc"
eq "  KB_API empty"           ""  "${KB_API:-}"
: > "$KANBAN_HOST_ENV"

# ---------------------------------------------------------------------------
echo "== kb_board_env_for =="
reset_env
rm -f "$TMP"/.kanban-*-board.env
{ echo 'KB_BOARD_ID=42'; echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\""; } > "$TMP/.kanban-a-board.env"
echo 'KB_BOARD_ID=99' > "$TMP/.kanban-b-board.env"
eq "finds the env whose KB_BOARD_ID matches" "$TMP/.kanban-a-board.env" "$(kb_board_env_for 42 2>/dev/null)"
eq "finds the other one"                     "$TMP/.kanban-b-board.env" "$(kb_board_env_for 99 2>/dev/null)"
rc=0; kb_board_env_for 7 >/dev/null 2>&1 || rc=$?
eq "no match → rc 1" "1" "$rc"

# An env that sets NO KB_BOARD_ID must never match — with KB_BOARD_ID leaked from the caller
# it would otherwise match every lookup.
reset_env
rm -f "$TMP"/.kanban-*-board.env
echo 'KB_STAGE_BACKLOG=1' > "$TMP/.kanban-noid-board.env"   # sets no KB_BOARD_ID
KB_BOARD_ID=42   # a leaked global from an earlier resolve
rc=0; kb_board_env_for 42 >/dev/null 2>&1 || rc=$?
eq "env with no KB_BOARD_ID does not false-match a leaked KB_BOARD_ID" "1" "$rc"
unset KB_BOARD_ID

# A duplicate KB_BOARD_ID is arbitrary either way — the defect is being silent about it.
reset_env
rm -f "$TMP"/.kanban-*-board.env
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-dup1-board.env"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-dup2-board.env"
warn="$(kb_board_env_for 42 2>&1 >/dev/null || true)"
case "$warn" in
    *"2 board envs set KB_BOARD_ID=42"*) ok "duplicate KB_BOARD_ID warns loudly" ;;
    *) bad "duplicate KB_BOARD_ID did not warn: '$warn'" ;;
esac
[[ -n "$(kb_board_env_for 42 2>/dev/null)" ]] && ok "duplicate still returns a usable path" \
    || bad "duplicate returned no path"

# A board env that is unparsable must not abort the scan or match.
reset_env
rm -f "$TMP"/.kanban-*-board.env
echo 'this is ( not valid shell' > "$TMP/.kanban-broken-board.env"
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-good-board.env"
eq "a broken board env is skipped, not fatal" "$TMP/.kanban-good-board.env" "$(kb_board_env_for 42 2>/dev/null)"

# ---------------------------------------------------------------------------
echo "== kb_board_env_get =="
# get1: read one var the way a caller does (first line; the '.' sentinel is never read).
get1() { local v; IFS= read -r v <<<"$(kb_board_env_get "$1" "$2")"; printf '%s' "$v"; }

reset_env
rm -f "$TMP"/.kanban-*-board.env
{ echo 'KB_BOARD_ID=42'; echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\""; } > "$TMP/.kanban-a-board.env"
eq "reports the board env's own KBCARD_TOKEN_FILE" "$TMP/board.token" \
   "$(get1 "$TMP/.kanban-a-board.env" KBCARD_TOKEN_FILE)"

# Empty (not the inherited host value) when the board env sets none — otherwise the caller
# would read the host's override back as a per-board one and never fall through its ladder.
reset_env
echo 'KB_BOARD_ID=42' > "$TMP/.kanban-b-board.env"
export KBCARD_TOKEN_FILE="$TMP/host.token"   # as kb_load_host_env would have left it
eq "empty when the board env sets none (host value not echoed back)" "" \
   "$(get1 "$TMP/.kanban-b-board.env" KBCARD_TOKEN_FILE)"

# A token path containing a space must survive intact (no word-splitting).
reset_env
{ echo 'KB_BOARD_ID=42'; echo "export KBCARD_TOKEN_FILE=\"$TMP/tok with space.token\""; } > "$TMP/.kanban-sp-board.env"
eq "a token path with a space survives" "$TMP/tok with space.token" \
   "$(get1 "$TMP/.kanban-sp-board.env" KBCARD_TOKEN_FILE)"

# Multi-var read: the exact call board-card-start makes for its stage ids. An unset OPTIONAL
# key must come back EMPTY and must not shift a later value into its place.
reset_env
{ echo 'KB_BOARD_ID=42'; echo 'export KB_STAGE_IN_PROGRESS=84'; echo 'export KB_STAGE_BACKLOG=83'
  echo 'export KB_STAGE_PRIORITIZED=86'; } > "$TMP/.kanban-noheld-board.env"   # NO KB_STAGE_HELD
{ IFS= read -r ip; IFS= read -r bl; IFS= read -r pr; IFS= read -r hl; } \
    <<<"$(kb_board_env_get "$TMP/.kanban-noheld-board.env" KB_STAGE_IN_PROGRESS KB_STAGE_BACKLOG KB_STAGE_PRIORITIZED KB_STAGE_HELD)"
eq "multi-var: in_progress" "84" "$ip"
eq "multi-var: backlog"     "83" "$bl"
eq "multi-var: prioritized" "86" "$pr"
eq "multi-var: an unset optional KB_STAGE_HELD reads EMPTY (no shift)" "" "$hl"

# THE LEAK: board envs `export` their keys, so another board's value is live in an operator
# shell. A board env that omits an optional key must NOT inherit it.
reset_env
export KB_STAGE_HELD=88   # leaked from a previously-sourced board env
{ IFS= read -r ip; IFS= read -r bl; IFS= read -r pr; IFS= read -r hl; } \
    <<<"$(kb_board_env_get "$TMP/.kanban-noheld-board.env" KB_STAGE_IN_PROGRESS KB_STAGE_BACKLOG KB_STAGE_PRIORITIZED KB_STAGE_HELD)"
eq "a leaked KB_STAGE_HELD is NOT reported as this board's" "" "$hl"
unset KB_STAGE_HELD

reset_env
export KBCARD_TOKEN_FILE="$TMP/host.token"
eq "a leaked KBCARD_TOKEN_FILE is NOT reported as this board's" "" \
   "$(get1 "$TMP/.kanban-noheld-board.env" KBCARD_TOKEN_FILE)"

# kb_board_env_get must not leak the board env into the caller.
# ⛔ CALLED DIRECTLY, NOT THROUGH get1 — and that is the whole assertion. get1 runs
# kb_board_env_get inside a `$( )` command substitution, which is itself a subshell, so a
# leak could never have reached this shell no matter what the function did: routed through
# get1 this line was incapable of failing, and stayed green under a mutation that replaced
# the function's own `( )` isolation with a plain `{ }` group. Driving the function in THIS
# shell is what puts its isolation, rather than get1's, under test. The sentinel is the
# second half: the board env sets KB_BOARD_ID=42, so a leak OVERWRITES a value the caller
# owns — asserting an empty string could not tell "did not leak" from "never ran".
reset_env
KB_BOARD_ID="SENTINEL-OWNED-BY-THE-CALLER"
kb_board_env_get "$TMP/.kanban-a-board.env" KBCARD_TOKEN_FILE >/dev/null
eq "does not leak the board env's KB_BOARD_ID into the caller" \
   "SENTINEL-OWNED-BY-THE-CALLER" "${KB_BOARD_ID:-}"

# ---------------------------------------------------------------------------
echo "== kb_board_roster — the roster file, then DISCOVERY as the fallback =="
# The parser half is board-snapshot's inline block hoisted for its second caller; the fallback
# half is new, and it is the one that can fail SILENTLY — a box with no roster file must
# report on the boards it has, not on an empty set that renders as a healthy quiet report.
reset_env
rm -f "$TMP"/.kanban-*-board.env
export KANBAN_SNAPSHOT_BOARDS="$TMP/.kanban-snapshot-boards"
{ echo '# a comment line'
  echo ''
  echo '   dev:Board 5 (kanban-board)'
  echo 'toolkit'
  echo '  spaced name  :Label: with a colon'
  echo ':nameless'
} > "$KANBAN_SNAPSHOT_BOARDS"
roster="$(kb_board_roster)"
eq "one line per usable entry (comment, blank and nameless dropped)" "3" \
   "$(printf '%s\n' "$roster" | grep -c .)"
eq "a name:label line splits at the FIRST colon" "dev	Board 5 (kanban-board)" \
   "$(printf '%s\n' "$roster" | sed -n 1p)"
eq "a line with no colon takes its name as its label" "toolkit	toolkit" \
   "$(printf '%s\n' "$roster" | sed -n 2p)"
eq "whitespace is stripped from the NAME and the label kept verbatim" "spacedname	Label: with a colon" \
   "$(printf '%s\n' "$roster" | sed -n 3p)"

# The fallback: no roster file at all ⇒ every board env on the box, label = name.
rm -f "$KANBAN_SNAPSHOT_BOARDS"
echo 'KB_BOARD_ID=7' > "$TMP/.kanban-sola-board.env"
echo 'KB_BOARD_ID=9' > "$TMP/.kanban-sandbox-board.env"
eq "with no roster it discovers every board env" "sandbox	sandbox
sola	sola" "$(kb_board_roster | LC_ALL=C sort)"
# A roster file present but holding nothing usable is the same case as none — the count, not
# the file's existence, is what decides.
printf '# only a comment\n\n' > "$KANBAN_SNAPSHOT_BOARDS"
eq "an unusable roster file falls back the same way" "2" "$(kb_board_roster | grep -c .)"
# The control: with the roster usable again, discovery must NOT also fire (or the two would
# concatenate and every board on the box would be reported twice).
printf 'dev:D\n' > "$KANBAN_SNAPSHOT_BOARDS"
eq "control: a usable roster suppresses discovery" "dev	D" "$(kb_board_roster)"
# And a box with neither returns nothing at all, quietly — the caller decides what that means.
rm -f "$KANBAN_SNAPSHOT_BOARDS" "$TMP"/.kanban-*-board.env
eq "no roster and no board env ⇒ empty output" "" "$(kb_board_roster)"
expect_rc "…at rc 0 (emptiness is not an error here)" 0 kb_board_roster
unset KANBAN_SNAPSHOT_BOARDS

# ---------------------------------------------------------------------------
echo "== kb_read_token =="
reset_env
kb_read_token "$TMP/board.token"
eq "reads the token content"        "board-token"      "${KB_TOKEN:-}"
eq "publishes the token file path"  "$TMP/board.token" "${KB_TOKEN_FILE:-}"
kb_read_token "$TMP/tok with space.token"
eq "reads a token path with a space" "spaced-token" "${KB_TOKEN:-}"
rc=0; kb_read_token "$TMP/absent.token" || rc=$?
eq "unreadable token → rc 1 (returns, never exits)" "1" "$rc"

# ---------------------------------------------------------------------------
echo "== fetch_board_cards: HTTP failure carries status + body (card #4337) =="
# curl is stubbed as a shell function (shadows the binary for the sourced lib) so the
# checks are network-free. The stub consumes the herestring auth on fd 0 and emits the
# lib's -w marker exactly as real curl would.
reset_env
FETCH_LOG="$TMP/fetch-failures.log"

# The stub EMULATES real curl's -f semantics (body discarded, rc 22 on non-2xx) so
# reintroducing -f into curl_opts reds the body checks below (mutation-sensitive).
_stub_curl_respond() { # <body> <status>
    cat >/dev/null
    local a
    for a in "${_STUB_ARGS[@]}"; do
        if [[ "$a" == -f* && "$2" != 2* ]]; then return 22; fi
    done
    printf '%s\n__HTTP__%s' "$1" "$2"
    return 0
}
curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"error":"forbidden: token lacks board scope"}' 403; }
rc=0; out="$(KB_FETCH_LOUD=1 KB_LOG_FILE="$FETCH_LOG" fetch_board_cards "https://api.example" tok 8 2>"$TMP/fetch.err")" || rc=$?
eq "HTTP 403 on page 1 → rc 1"                    "1" "$rc"
eq "HTTP 403 → no data on stdout"                 ""  "$out"
grep -q "HTTP-403" "$FETCH_LOG" && ok "failure log carries the HTTP status" || bad "failure log missing HTTP-403"
grep -q "forbidden: token lacks board scope" "$FETCH_LOG" && ok "failure log carries the error body (403 vs 422 distinguishable)" || bad "failure log lost the error body"
grep -q "HTTP 403" "$TMP/fetch.err" && ok "loud mode surfaces the status on stderr" || bad "stderr missing HTTP 403"

curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"error":{"stage_id":["invalid"]}}' 422; }
: > "$FETCH_LOG"
rc=0; KB_FETCH_LOUD=1 KB_LOG_FILE="$FETCH_LOG" fetch_board_cards "https://api.example" tok 8 >/dev/null 2>&1 || rc=$?
grep -q "HTTP-422" "$FETCH_LOG" && ok "a 422 logs as HTTP-422, not a generic curl rc" || bad "422 indistinguishable in log"

curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"data":[{"id":7}],"meta":{"last_page":1,"total":1}}' 200; }
rc=0; out="$(fetch_board_cards "https://api.example" tok 8)" || rc=$?
eq "200 single page → rc 0"          "0" "$rc"
eq "200 single page → data returned" '[{"id":7}]' "$out"

curl() { cat >/dev/null; return 7; }
: > "$FETCH_LOG"
rc=0; KB_FETCH_LOUD=1 KB_LOG_FILE="$FETCH_LOG" fetch_board_cards "https://api.example" tok 8 >/dev/null 2>&1 || rc=$?
eq "transport failure on page 1 → rc 1" "1" "$rc"
grep -q "FAILED-FETCH curl-rc=7" "$FETCH_LOG" && ok "transport failure keeps the curl-rc log line" || bad "transport log line regressed"
unset -f curl

# ---------------------------------------------------------------------------
echo "== fetch_board_cards: short-read rc 4 vs dedup artifact (card #4338) =="
# Page-aware stub: selects the per-page payload by inspecting the page= query param, then
# emits it through the shared _stub_curl_respond core (the single owner of the stdin-drain
# + __HTTP__<status> convention) at a fixed 200.
_stub_page_curl() { # uses _PAGES assoc: _PAGES[<n>]=<json>
    local a page=1
    for a in "${_STUB_ARGS[@]}"; do
        [[ "$a" == *"page="* ]] && page="${a##*page=}"
    done
    _stub_curl_respond "${_PAGES[$page]}" 200
}
declare -A _PAGES

# GENUINE short read: server claims total=3, delivers 2 rows on the only page.
curl() { _STUB_ARGS=("$@"); _stub_page_curl; }
_PAGES=( [1]='{"data":[{"id":1},{"id":2}],"meta":{"last_page":1,"total":3}}' )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/short.err")" || rc=$?
eq "genuine short read → rc 4"                 "4" "$rc"
eq "genuine short read still emits the partial data" '[{"id":1},{"id":2}]' "$out"
grep -q "INCOMPLETE" "$TMP/short.err" && ok "genuine short read warns INCOMPLETE" || bad "missing INCOMPLETE warn"

# DEDUP ARTIFACT: two pages, one card straddles the boundary; pre-dedup sum (201)
# covers total (201) but distinct read_n (200) < total → complete, rc 0, soft warn.
# total=202 while only 201 DISTINCT ids exist: the straddling duplicate (199)
# makes the pre-dedup sum (202) cover the total, so the read is complete and
# the 201<202 gap is the collapsed duplicate, not a missing row.
page1="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":2,"total":202}}')"
page2='{"data":[{"id":199},{"id":200}],"meta":{"last_page":2,"total":202}}'
_PAGES=( [1]="$page1" [2]="$page2" )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/dedup.err")" || rc=$?
eq "dedup artifact → rc 0 (read complete)"     "0" "$rc"
eq "dedup artifact → all distinct cards"       "201" "$(printf '%s' "$out" | jq 'length')"   # 202 delivered, 1 collapsed
grep -q "duplicates across pages collapsed" "$TMP/dedup.err" && ok "dedup artifact warns honestly (not INCOMPLETE)" || bad "dedup warn wording regressed"
grep -q "INCOMPLETE" "$TMP/dedup.err" && bad "dedup artifact must not claim INCOMPLETE" || ok "dedup artifact does not claim INCOMPLETE"

# Positive control: clean two-page read, totals agree → rc 0, silent.
page1c="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":2,"total":201}}')"
page2b='{"data":[{"id":200}],"meta":{"last_page":2,"total":201}}'
_PAGES=( [1]="$page1c" [2]="$page2b" )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/clean.err")" || rc=$?
eq "clean two-page read → rc 0"                "0" "$rc"
eq "clean two-page read → 201 cards"           "201" "$(printf '%s' "$out" | jq 'length')"
[[ -s "$TMP/clean.err" ]] && bad "clean read must be silent on stderr" || ok "clean read silent"

# ---------------------------------------------------------------------------
echo "== fetch_board_cards: last_page must not truncate a full page 1 (card #4623) =="
# Parity with the standalone's fetch_whole_board (promote-pagination-selftest): meta.last_page
# is a SECONDARY signal; the n<200 short-page break is primary. An ABSENT or out-of-range
# last_page defaults to UNKNOWN and must fall through to the short-page break, never stop the
# scan at a full 200-row page 1. The old `// 1` default broke here and silently returned only
# page 1 (the #4513 miss). Reverting the guard reds these two cases.

# Full 200-row page 1 with NO meta at all: must keep paging to the short page, not truncate.
full1="$(jq -nc '{"data":[range(200)|{id:.}]}')"     # 200 rows, no meta whatsoever
tail2='{"data":[{"id":200},{"id":201}]}'             # short page → n<200 terminates
_PAGES=( [1]="$full1" [2]="$tail2" )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/nometa.err")" || rc=$?
eq "full page + no meta → rc 0"                "0"   "$rc"
eq "full page + no meta → paged to 202"        "202" "$(printf '%s' "$out" | jq 'length')"
[[ -s "$TMP/nometa.err" ]] && bad "no-meta full read must be silent on stderr" || ok "no-meta full read silent"

# last_page=0 on a full page: a non-positive value is not a meaningful declaration ⇒ unknown ⇒
# must keep paging, not break at page 1 (the same truncation class as an absent last_page).
lp0="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":0}}')"
_PAGES=( [1]="$lp0" [2]='{"data":[{"id":200}]}' )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/lp0.err")" || rc=$?
eq "last_page=0 → rc 0"                        "0"   "$rc"
eq "last_page=0 → paged to 201"                "201" "$(printf '%s' "$out" | jq 'length')"

# ---------------------------------------------------------------------------
echo "== fetch_board_cards: an unreadable 2xx is not an empty board (card#6594) =="
# The defect: `.data // []` answered a 200 carrying an HTML 502 with `[]` at rc 0 — byte-identical
# to a genuinely EMPTY board — so next-dl dropped the board's DL floor and minted from the local
# scan alone. The predicate is the ENVELOPE, not the row count: `.data` present AND an array.
# The refusal legs below are bracketed by TWO controls on the same route — a genuinely empty
# board and a one-card board — because the whole point is that a refusal and a legitimate read
# are now distinguishable; a block that passed by refusing everything would have broken a
# legitimate board read, not fixed anything.
UNREAD_LOG="$TMP/unreadable.log"
_fbc_case() { # <label> <body> <expect-rc> <expect-stdout>
    local label="$1" body="$2" exprc="$3" expout="$4" rc=0 out
    curl() { _STUB_ARGS=("$@"); _stub_curl_respond "$body" 200; }
    : > "$UNREAD_LOG"
    out="$(KB_FETCH_LOUD=1 KB_LOG_FILE="$UNREAD_LOG" fetch_board_cards "https://api.example" tok 8 2>"$TMP/unread.err")" || rc=$?
    eq "$label (rc)"     "$exprc"  "$rc"
    eq "$label (stdout)" "$expout" "$out"
}

# The measured defect input: HTTP 200 whose body is a proxy's HTML error page.
_fbc_case "200 + <html>502</html> → rc 1" '<html><head><title>502 Bad Gateway</title></head><body>502</body></html>' 1 ""
eq "…and the refusal is in the lib's own voice, naming the status" "true" \
   "$(has 'fetch_board_cards: page 1 for board 8 returned HTTP 200 with no readable card array' "$(cat "$TMP/unread.err")")"
eq "…and says what it refused to do, so the diagnostic is not just 'failed'" "true" \
   "$(has 'refusing rather than report it as an empty board' "$(cat "$TMP/unread.err")")"
eq "…and the failure log distinguishes this cause from a non-2xx" "true" \
   "$(has 'UNREADABLE-BODY' "$(cat "$UNREAD_LOG")")"
eq "…and the log carries the body, so the cause is diagnosable after the fact" "true" \
   "$(has '502 Bad Gateway' "$(cat "$UNREAD_LOG")")"

# THE CONTROL, and the one that matters most: a genuinely empty board is a legitimate state and
# must still SUCCEED. This is the real API's empty-result envelope, probed live before the fix was
# written. A predicate that cannot separate this from the case above is the wrong predicate.
_fbc_case "CONTROL: a genuinely EMPTY board still succeeds → rc 0" \
    '{"data":[],"links":{"first":"x","last":"x","prev":null,"next":null},"meta":{"current_page":1,"from":null,"last_page":1,"per_page":200,"to":null,"total":0}}' 0 "[]"
[[ -s "$TMP/unread.err" ]] && bad "an empty board must be silent on stderr" || ok "an empty board is silent on stderr"
[[ -s "$UNREAD_LOG" ]] && bad "an empty board must not write a failure-log line" || ok "an empty board writes no failure-log line"

# The other shapes that carried no readable card array. What each USED to produce differs, and
# the difference is the point — rounding them all to `[]` is what made the class look smaller
# than it was (measured at dev 0b2ea6b, HTTP 200 in every case):
#   no .data / .data null → `[]` at rc 0        — the plausible empty board
#   .data a STRING        → rc 0, EMPTY stdout  — the dedup's `reduce .[]` cannot iterate a
#                                                 string, so jq faulted into its own 2>/dev/null
#   .data an OBJECT       → rc 0, `[9]`         — a FABRICATED array: that same `reduce .[]`
#                                                 iterates an object's VALUES. This one, not the
#                                                 string, is the "garbage value" half of README's
#                                                 "never … emit a garbage value".
_fbc_case "200 + valid JSON with no .data at all → rc 1"      '{"error":"upstream connect error"}' 1 ""
_fbc_case "200 + .data null → rc 1"                           '{"data":null,"meta":{"total":0}}'   1 ""
_fbc_case "200 + .data a string → rc 1"                       '{"data":"not-an-array"}'            1 ""
_fbc_case "200 + .data an object (was a fabricated [9]) → rc 1" '{"data":{"id":9}}'                1 ""
# …and the second control, after the last of them, so the block cannot pass by refusing
# everything: a one-card board is a complete read at rc 0.
_fbc_case "CONTROL: one real card → rc 0 with the card"       '{"data":[{"id":7}],"meta":{"last_page":1,"total":1}}' 0 '[{"id":7}]'

# The refusal must not break board-snapshot's SessionStart contract: WITHOUT KB_FETCH_LOUD the
# paginator is return-code-only, and that is what keeps a fail-soft display quiet. Asserted
# separately from _fbc_case, which always sets the knob.
curl() { _STUB_ARGS=("$@"); _stub_curl_respond '<html>502</html>' 200; }
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/quiet.err")" || rc=$?
eq "quiet mode (no KB_FETCH_LOUD) still refuses → rc 1" "1" "$rc"
eq "quiet mode emits nothing on stdout"                 ""  "$out"
[[ -s "$TMP/quiet.err" ]] && bad "quiet mode must stay silent on stderr (board-snapshot's contract)" || ok "quiet mode stays silent on stderr"

# THE SAME PREDICATE ON A LATER PAGE (card#6630) — the half card#6594 left open. An unreadable
# body on page > 1 fell back to `[]`, and `[]` is a SHORT page, which ENDS the scan: the caller
# got rc 0 and a board it had only partly read. It is now the paginator's existing rc 2, the rc
# its contract already assigns to "a page > 1 failed mid-pagination" — the same rc the curl and
# non-2xx arms return for the same page, because the difference between them is which layer
# noticed, not what the caller can trust.
#
# The two servers are asserted separately because they used to give DIFFERENT wrong answers, and
# only one of them was ever loud:
#   DECLARES meta.total  → the census caught it at rc 4 WITH the partial data (loud, consumable)
#   OMITS   meta.total   → rc 0, the partial data, and an EMPTY stderr (the silent truncation)
# A leg written only against the first would have passed on this install and asserted nothing
# about the case the card exists for.
curl() { _STUB_ARGS=("$@"); _stub_page_curl; }
UNREAD_LOG="$TMP/p2-unreadable.log"

_fbc_p2() { # <label> <page-1 body> <page-2 body> <expect-rc>
    local label="$1" exprc="$4" rc=0 out
    _PAGES=( [1]="$2" [2]="$3" )
    : > "$UNREAD_LOG"
    out="$(KB_FETCH_LOUD=1 KB_LOG_FILE="$UNREAD_LOG" fetch_board_cards "https://api.example" tok 8 2>"$TMP/p2.err")" || rc=$?
    eq "$label (rc)" "$exprc" "$rc"
    _P2_OUT="$out"
}

fullp="$(jq -nc '{"data":[range(200)|{id:.}],"meta":{"last_page":2,"total":201}}')"
fullnm="$(jq -nc '{"data":[range(200)|{id:.}]}')"      # no meta at all — the silent-truncation server

_fbc_p2 "a server DECLARING meta.total: unreadable page 2 → rc 2 (was rc 4 + partial)" \
        "$fullp" '<html>502</html>' 2
eq "…and nothing is emitted, so no caller can act on the 200 rows page 1 did deliver" "" "$_P2_OUT"
eq "…and the refusal names the PAGE, not just the board"  "true" \
   "$(has 'fetch_board_cards: page 2 for board 8 returned HTTP 200 with no readable card array' "$(cat "$TMP/p2.err")")"
eq "…and says what it refused to do, which is NOT what page 1 refuses (an empty board)" "true" \
   "$(has 'report a TRUNCATED board as a complete read' "$(cat "$TMP/p2.err")")"
eq "…and the failure log carries the cause + the body" "true" \
   "$(has 'UNREADABLE-BODY' "$(cat "$UNREAD_LOG")")"

_fbc_p2 "a server OMITTING meta.total: unreadable page 2 → rc 2 (was rc 0, SILENT, truncated)" \
        "$fullnm" '{"error":"upstream connect error"}' 2
eq "…and nothing is emitted"                              "" "$_P2_OUT"
eq "…and the census is not what caught it (there is no total to census against)" "false" \
   "$(has 'board has ' "$(cat "$TMP/p2.err")")"

# THE CONTROL for this arm, and the one that decides whether the predicate is the right one: a
# legitimate SHORT final page is how a real multi-page read ENDS. If the page-2 refusal cannot
# tell a legitimate `{"data":[…]}` — or a legitimately EMPTY one — from an unreadable body, it
# refuses every board bigger than one page, and a block asserting only refusals would pass.
_fbc_p2 "CONTROL: a legitimate short page 2 completes the read → rc 0" "$fullnm" '{"data":[{"id":200}]}' 0
eq "…and every row from BOTH pages is emitted"            "201" "$(printf '%s' "$_P2_OUT" | jq 'length')"
[[ -s "$TMP/p2.err" ]] && bad "a legitimate two-page read must be silent on stderr" || ok "a legitimate two-page read is silent"
_fbc_p2 "CONTROL: an EMPTY page 2 is a complete read, not an unreadable one → rc 0" "$fullnm" '{"data":[],"meta":{"total":200}}' 0
eq "…and page 1's 200 rows are the answer"                "200" "$(printf '%s' "$_P2_OUT" | jq 'length')"

# Quiet mode on the LATER page too — board-snapshot reads the paginator without the knob, so a
# page-2 refusal that started printing would break the same SessionStart contract page 1's does.
_PAGES=( [1]="$fullnm" [2]='{"error":"upstream connect error"}' )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/p2quiet.err")" || rc=$?
eq "quiet mode: unreadable page 2 still refuses → rc 2" "2" "$rc"
eq "quiet mode: nothing on stdout"                      ""  "$out"
[[ -s "$TMP/p2quiet.err" ]] && bad "quiet mode must stay silent on a page-2 refusal too" || ok "quiet mode stays silent on a page-2 refusal"

unset -f _fbc_case _fbc_p2
unset UNREAD_LOG _P2_OUT

# ---------------------------------------------------------------------------
echo "== fetch_board_cards: a userinfo-bearing api_base never reaches the DURABLE log (card#7500) =="
# `https://user:password@host/api/v3` is a SUPPORTED api_base — kb_require_known_api_host and
# kb_require_https_host both ACCEPT it (kb-host-guard-selftest pins the row), because they judge
# the HOST. Every failure line in this loop is written to $KB_LOG_FILE, which is a FILE on disk:
# stderr in CI is at least bounded by log retention, a password in a log file is not.
#
# ⛔ ASSERTED ON THE CREDENTIAL VALUE, NEVER ON THE PRESENCE OF A MASK. A tool that printed
# `***` AND the password would satisfy a `has '***'` check and leak anyway. Paired with a HOST
# leg every time: without it a later "simplification" that redacted the whole url would pass the
# absence half while destroying the only fact these lines exist to carry.
_UI_PW='not-a-real-password-card7500'
_UI_USER='fakeuser'
_UI_BASE="https://$_UI_USER:$_UI_PW@kanban.test/api/v3"
_UI_LOG="$TMP/userinfo-fetch.log"

_ui_case() { # <label> <expect-rc>; the caller has already installed the curl stub
    local label="$1" exprc="$2" rc=0 logtext errtext
    : > "$_UI_LOG"
    KB_FETCH_LOUD=1 KB_LOG_FILE="$_UI_LOG" fetch_board_cards "$_UI_BASE" tok 8 \
        >/dev/null 2>"$TMP/userinfo-fetch.err" || rc=$?
    logtext="$(cat "$_UI_LOG")"; errtext="$(cat "$TMP/userinfo-fetch.err")"
    eq "$label (rc)" "$exprc" "$rc"
    # POSITIVE CONTROL FIRST: the legs below are assertions of ABSENCE, and an EMPTY log — a
    # renamed knob, a route that never fired — satisfies every one of them while measuring
    # nothing at all.
    eq "$label — the durable log was actually written (positive control)" "true" \
       "$(has 'GET https://' "$logtext")"
    eq "$label — the password is NOT in the durable log" "false" "$(has "$_UI_PW"   "$logtext")"
    eq "$label — the username is NOT in the durable log" "false" "$(has "$_UI_USER" "$logtext")"
    eq "$label — the HOST still is"                      "true"  "$(has 'kanban.test' "$logtext")"
    eq "$label — nor is the password on stderr"          "false" "$(has "$_UI_PW"   "$errtext")"
}

# One case per line in the loop that renders a url: the transport arm, the answered-non-2xx arm,
# and the unreadable-2xx arm. All three are error paths, which is exactly when an operator is
# most likely to paste the output somewhere.
curl() { cat >/dev/null; return 7; }
_ui_case "FAILED-FETCH (curl transport)" 1
curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"error":"forbidden"}' 403; }
_ui_case "HTTP-403 (the server answered)" 1
curl() { _STUB_ARGS=("$@"); _stub_curl_respond '<html>502</html>' 200; }
_ui_case "UNREADABLE-BODY (a 2xx with no card array)" 1

# …and the CONTROL that keeps the mask from being a wholesale rewrite: a base with NO userinfo
# is logged byte-identically to how it always was.
: > "$_UI_LOG"
curl() { cat >/dev/null; return 7; }
KB_FETCH_LOUD=1 KB_LOG_FILE="$_UI_LOG" fetch_board_cards "https://kanban.test/api/v3" tok 8 >/dev/null 2>&1 || true
eq "CONTROL: a userinfo-free base is logged verbatim, mask and all absent" "true" \
   "$(has 'GET https://kanban.test/api/v3/tasks/search.json?q=board_id=8' "$(cat "$_UI_LOG")")"
eq "CONTROL: …and no mask was inserted into it"                           "false" \
   "$(has '***' "$(cat "$_UI_LOG")")"
unset -f _ui_case
unset _UI_PW _UI_USER _UI_BASE _UI_LOG
unset -f curl

# ---------------------------------------------------------------------------
echo "== fetch_board_cards: the optional [query] — one encoded term inside the same q= (card#6771) =="
# The paginator gained a fifth argument so a caller can read the board's MATCHING cards through
# the same paging/dedup/rc machinery, rather than a second copy of it growing beside this one.
# What must hold: the term reaches the wire ENCODED as one value, the no-query URL does not move
# at all (eight of the nine calls in bin/ send no query), and the two messages that claim a POPULATION
# say something true when the read was of a match set instead.
# argv goes to a FILE, for the reason the KB_CURL_MAX_TIME block below states in full: curl runs
# inside a "$(…)", so a stub-assigned array dies with that subshell and would assert nothing.
_QC_ARGV="$TMP/qc-curl-argv.txt"
_QC_CALLS="$TMP/qc-curl.calls"
_QC_URL() { /usr/bin/grep -m1 '^http' "$_QC_ARGV"; }
: > "$_QC_CALLS"
curl() { printf '%s\n' "$@" > "$_QC_ARGV"; printf 'x' >> "$_QC_CALLS"; _stub_curl_respond '{"data":[{"id":7}],"meta":{"last_page":1,"total":1}}' 200; }

# THE CONTROL FIRST — the historic URL, byte for byte. Every existing consumer passes no query,
# so this is the assertion that says they are untouched; the legs below only mean anything
# beside it.
fetch_board_cards "https://api.example" tok 8 >/dev/null
eq "no query → the URL is the historic whole-board spelling, unchanged" \
   "https://api.example/tasks/search.json?q=board_id=8&limit=200&page=1" "$(_QC_URL)"

fetch_board_cards "https://api.example" tok 8 50 'deploy hook' >/dev/null
eq "a query rides INSIDE the same q value, after board_id, space-encoded" \
   "https://api.example/tasks/search.json?q=board_id=8%20deploy%20hook&limit=200&page=1" "$(_QC_URL)"

# The encode is the whole defence against a search term rewriting the request: `&` would
# otherwise start a new parameter, `#` would truncate the URL at a fragment.
fetch_board_cards "https://api.example" tok 8 50 'a&b #c' >/dev/null
eq "an & or # in the term is encoded, never a new parameter or a fragment" \
   "https://api.example/tasks/search.json?q=board_id=8%20a%26b%20%23c&limit=200&page=1" "$(_QC_URL)"

# WHY jq's @uri AND NOT A HAND-ROLLED ENCODER: bash's `${s:i:1}` yields a CHARACTER, and
# `printf %02X` on it yields the CODE POINT, so the obvious 8-line encoder emits `%E9` for `é`
# where the wire needs its UTF-8 bytes `%C3%A9`. Card bodies carry non-ASCII routinely (every
# `·` and `—` in this repo's own card bodies), so that is a live case, not a curiosity.
fetch_board_cards "https://api.example" tok 8 50 'café' >/dev/null
eq "a non-ASCII term is encoded as UTF-8 BYTES, not as a code point" \
   "https://api.example/tasks/search.json?q=board_id=8%20caf%C3%A9&limit=200&page=1" "$(_QC_URL)"

# rc 5 — the encode refusal. Fail-CLOSED is the point: a dropped term would send the bare
# board_id read, i.e. the WHOLE BOARD answered as though it were the match set. Unreachable from
# any input (a non-empty string always has a non-empty @uri), so the seam is a jq that fails
# exactly that call.
jq() {
    local a
    for a in "$@"; do
        if [[ "$a" == *"@uri"* ]]; then echo "jq stub: refusing the @uri encode" >&2; return 5; fi
    done
    command jq "$@"
}
: > "$_QC_CALLS"
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 50 'deploy hook' 2>"$TMP/qc.err")" || rc=$?
eq "an unencodable term → rc 5"                        "5" "$rc"
eq "…nothing on stdout"                                ""  "$out"
eq "…and NO request was issued at all"                 ""  "$(cat "$_QC_CALLS")"
eq "…the refusal says the term could not be encoded"   "true" "$(has 'could not be encoded' "$(cat "$TMP/qc.err")")"
# It must not depend on KB_FETCH_LOUD: there is no request for a quiet caller to have logged,
# so this is the only place the cause can appear.
rc=0; fetch_board_cards "https://api.example" tok 8 50 'deploy hook' >/dev/null 2>"$TMP/qc-quiet.err" || rc=$?
eq "…and says so even without KB_FETCH_LOUD"           "true" "$(has 'could not be encoded' "$(cat "$TMP/qc-quiet.err")")"
unset -f jq
# CONTROL: with the real jq back, the same call succeeds — so the four assertions above measured
# the stub's effect on the arm, not a call that was broken anyway.
: > "$_QC_CALLS"
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 50 'deploy hook')" || rc=$?
eq "CONTROL: the same call with the real jq → rc 0"    "0" "$rc"
eq "CONTROL: …and it did issue its request"            "x" "$(cat "$_QC_CALLS")"

echo "== fetch_board_cards: what the refusals CLAIM when the read was a search =="
# meta.total and "an empty board" are claims about a POPULATION. Under a query the population is
# the match set, so the same sentences would be false about the board — the two messages that
# name one are scoped, and the no-query wording (asserted verbatim earlier in this file) is what
# they must not disturb.
curl() { _STUB_ARGS=("$@"); _stub_curl_respond '<html>502</html>' 200; }
rc=0; KB_FETCH_LOUD=1 fetch_board_cards "https://api.example" tok 8 50 'deploy hook' >/dev/null 2>"$TMP/qs1.err" || rc=$?
eq "an unreadable page 1 under a query → still rc 1"   "1" "$rc"
eq "…and it refuses to report A SEARCH THAT MATCHED NOTHING, not an empty board" "true" \
   "$(has 'refusing rather than report it as a search that matched nothing' "$(cat "$TMP/qs1.err")")"
eq "…so it makes no claim about the board being empty" "false" \
   "$(has 'report it as an empty board' "$(cat "$TMP/qs1.err")")"

curl() { _STUB_ARGS=("$@"); _stub_page_curl; }
_PAGES=( [1]="$(jq -nc '{"data":[range(200)|{id:.}]}')" [2]='<html>502</html>' )
rc=0; KB_FETCH_LOUD=1 fetch_board_cards "https://api.example" tok 8 50 'deploy hook' >/dev/null 2>"$TMP/qs2.err" || rc=$?
eq "an unreadable page 2 under a query → still rc 2"   "2" "$rc"
eq "…and what it refuses is a TRUNCATED RESULT SET"    "true" \
   "$(has 'report a TRUNCATED result set as a complete read' "$(cat "$TMP/qs2.err")")"

_PAGES=( [1]='{"data":[{"id":1},{"id":2}],"meta":{"last_page":1,"total":3}}' )
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 50 'deploy hook' 2>"$TMP/qs4.err")" || rc=$?
eq "a short read under a query → still rc 4"           "4" "$rc"
eq "…and the census counts MATCHES, not the board's cards" "true" \
   "$(has 'the search over board 8 matched 3 cards but pages delivered only 2' "$(cat "$TMP/qs4.err")")"
eq "…so it never says the board holds 3 cards"         "false" \
   "$(has 'board has 3 cards' "$(cat "$TMP/qs4.err")")"
# CONTROL, on the same fixture with no query: the ORIGINAL wording, which the scoping must not
# have moved for the whole-board calls, which never pass one.
rc=0; out="$(fetch_board_cards "https://api.example" tok 8 2>"$TMP/qs4c.err")" || rc=$?
eq "CONTROL: the same short read with no query → rc 4" "4" "$rc"
eq "CONTROL: …and the board wording is untouched"      "true" \
   "$(has 'board has 3 cards but pages delivered only 2' "$(cat "$TMP/qs4c.err")")"
unset -f curl _QC_URL
unset _QC_CALLS _QC_ARGV


# ---------------------------------------------------------------------------
echo "== fetch_board_cards: a caller's regular-file stderr survives the fetch (card#6661) =="
# The redirect target for curl's stderr must be a DESCRIPTOR. It was the PATH /dev/stderr,
# which RE-OPENS the file behind the caller's stderr — and a regular-file stderr
# (`kbcard list 2>run.log`, how an agent logs) is re-opened O_TRUNC, so everything written
# before the FIRST page fetch was destroyed. Clean on a pipe and on a tty, where O_TRUNC is a
# no-op — but that is NOT why no other case here sees it. Every one of them redirects to a
# REGULAR file and was truncated on every call under the old code; they lost nothing only
# because none of them WRITES to its stderr file before the first fetch. A new case that does
# will need this same shape.
#
# Asserted on CONTENT and on the NUL COUNT, never on rc — the run stays rc 0 either way.
# The failure is NUL-fill, not absence: the caller's next write lands at its OWN unchanged
# offset in the now-truncated file, so the gap between what curl re-wrote and that offset
# reads back as NUL bytes — a log of plausible length whose head is gone. A command
# substitution silently drops NULs, so a string compare cannot see them and the count is
# asserted separately.
#
# THE FIXTURE'S PROPORTIONS ARE LOAD-BEARING, and the NUL leg is a decoration without them:
# the caller must write MORE before the fetch (28 bytes) than curl writes into the truncated
# file (18), or the caller's post-fetch write lands inside what curl re-wrote and overwrites
# it in place, leaving no hole and a NUL count of 0 in the presence of the bug. Measured both
# ways against the reverted fix: 28-over-18 gives 10 NULs; a longer curl note gave 0.
_bytes()  { wc -c < "$1" | tr -d ' '; }
_nuls()   { tr -dc '\000' < "$1" | wc -c | tr -d ' '; }
# A stub that also WRITES to stderr, so the same block asserts the other half of the knob's
# contract: under KB_FETCH_LOUD curl's own diagnostic must actually reach the caller.
_stub_loud_curl() { printf 'curl: (7) refused\n' >&2; _stub_curl_respond "$1" 200; }
ERRLOG="$TMP/caller-stderr.log"

# LOUD: the caller opens run.log ONCE (as a shell does for `2>run.log`) and writes before
# and after the fetch — the shape a logging agent actually runs.
curl() { _STUB_ARGS=("$@"); _stub_loud_curl '{"data":[{"id":7}],"meta":{"last_page":1,"total":1}}'; }
{
    echo "LINE-BEFORE-1" >&2
    echo "LINE-BEFORE-2" >&2
    KB_FETCH_LOUD=1 fetch_board_cards "https://api.example" tok 8 >/dev/null
    echo "LINE-AFTER" >&2
} 2>"$ERRLOG"
loud_exp=$'LINE-BEFORE-1\nLINE-BEFORE-2\ncurl: (7) refused\nLINE-AFTER\n'
eq "loud: the lines written BEFORE the fetch are still there" "true" \
   "$(has $'LINE-BEFORE-1\nLINE-BEFORE-2' "$(cat "$ERRLOG")")"
eq "loud: curl's own stderr reached the caller (the knob's contract)" "true" \
   "$(has 'curl: (7) refused' "$(cat "$ERRLOG")")"
eq "loud: the log is exactly those four lines, in order" "${loud_exp}." "$(cat "$ERRLOG"; printf '.')"
eq "loud: byte count matches that content"  "$(printf '%s' "$loud_exp" | wc -c | tr -d ' ')" "$(_bytes "$ERRLOG")"
eq "loud: no NUL fill (a truncated-then-re-extended log)" "0" "$(_nuls "$ERRLOG")"

# QUIET (the default, board-snapshot's contract): the caller's lines are equally intact AND
# curl's stderr is still swallowed. This is the control — a "fix" that simply passed curl's
# stderr through unconditionally would satisfy the loud legs above and red here.
: > "$ERRLOG"
{
    echo "LINE-BEFORE-1" >&2
    echo "LINE-BEFORE-2" >&2
    fetch_board_cards "https://api.example" tok 8 >/dev/null
    echo "LINE-AFTER" >&2
} 2>"$ERRLOG"
quiet_exp=$'LINE-BEFORE-1\nLINE-BEFORE-2\nLINE-AFTER\n'
eq "quiet: the log is exactly the caller's own three lines" "${quiet_exp}." "$(cat "$ERRLOG"; printf '.')"
eq "quiet: byte count matches that content" "$(printf '%s' "$quiet_exp" | wc -c | tr -d ' ')" "$(_bytes "$ERRLOG")"
eq "quiet: no NUL fill"                     "0" "$(_nuls "$ERRLOG")"

unset -f _stub_loud_curl _bytes _nuls
unset ERRLOG loud_exp quiet_exp

unset -f curl _stub_page_curl

# --- KB_CURL_MAX_TIME parity: kb_api and fetch_board_cards honor the SAME knob ---
# board-snapshot sets this knob ONCE at the top of the script so a slow/down API can
# never stall SessionStart, then reaches the board through BOTH lib fetchers. kb_api
# ignored it while fetch_board_cards honored it, so a single read was unbounded under
# a cap that read as global — reintroducing, via the sibling, the exact hang the cap
# exists to prevent. A caller cannot tell which fetcher it landed on, so the knob must
# mean the same thing in both. Keep these three assertions together: the parity IS the
# contract, and the unset case pins that existing callers are unaffected.
#
# argv is captured to a FILE, not a variable: kb_api runs curl inside "$(…)", so a
# stub-assigned array dies with that subshell and would assert nothing.
_argv_file="$TMP/curl-argv.txt"
curl() { printf '%s\n' "$@" > "$_argv_file"; _stub_curl_respond '{"data":[{"id":7}],"meta":{"last_page":1,"total":1}}' 200; }
_maxtime_arg() { grep -A1 -x -F -- '--max-time' "$_argv_file" 2>/dev/null | tail -1; }

KB_API="https://api.example"
KB_TOKEN=tok

: > "$_argv_file"
KB_CURL_MAX_TIME=5
kb_api GET /boards/8/preload.json >/dev/null 2>&1
eq "kb_api honors KB_CURL_MAX_TIME → curl gets --max-time 5"        "5" "$(_maxtime_arg)"

: > "$_argv_file"
KB_CURL_MAX_TIME=5
fetch_board_cards "https://api.example" tok 8 >/dev/null 2>&1
eq "fetch_board_cards honors the SAME knob (parity)"                "5" "$(_maxtime_arg)"

# kb_api_status is the THIRD fetcher. It was the sibling missed when kb_api was
# fixed — a parity claim covering two of three is just a wrong claim, and the
# caller cannot tell which of the three it reached. Assert all three or none.
: > "$_argv_file"
KB_CURL_MAX_TIME=5
kb_api_status GET /boards/8/preload.json >/dev/null 2>&1
eq "kb_api_status honors the SAME knob (third fetcher)"             "5" "$(_maxtime_arg)"

: > "$_argv_file"
unset KB_CURL_MAX_TIME
kb_api GET /boards/8/preload.json >/dev/null 2>&1
eq "kb_api without the knob → no --max-time (callers unchanged)"    ""  "$(_maxtime_arg)"

unset -f curl _maxtime_arg
unset KB_API KB_TOKEN _argv_file

# ---------------------------------------------------------------------------
echo "== kb_api: the request DID NOT COMPLETE vs the server ANSWERED non-2xx (card#6680) =="
# THE DEFECT THESE PIN. kb_api returned 1 for BOTH a transport failure (curl exited
# non-zero — the request may never have arrived, and a write it DID deliver may already be
# committed) and any completed non-2xx (403/404/422/500 — the server answered, so the
# outcome is KNOWN). One rc, two opposite epistemic states, and every caller buckets on
# `|| …`. Measured consequence: kbcard's restamp pass printed `HTTP 500 on PATCH …` and
# then, two lines later, `the request did not complete`.
#
# ⛔ ASSERT ON THE DISTINCTION, NOT ON "non-zero". Non-zero is what the two states already
# SHARED, so an `expect_rc … 1`-shaped check here could not have failed on the defect. Each
# case below compares its rc against the transport rc captured in the same run — which is
# what reds when the two collapse back into one value.
KB_API="https://api.example"
KB_TOKEN=tok
_api_err="$TMP/kb-api.err"

# --- 1. TRANSPORT FAILURE: curl exits non-zero, so nothing was read ---
# rc 7 is CURL's here, and is deliberately not what kb_api hands back: the contract says
# curl's rc is logged, never returned. If the two ever coincide it is a coincidence, and
# the assertion is on $KB_API_RC_TRANSPORT, never on a literal.
curl() { cat >/dev/null; return 7; }
rc_t=0; out_t="$(kb_api PATCH /tasks/9.json '{"a":1}' 2>"$_api_err")" || rc_t=$?
eq "transport failure → rc \$KB_API_RC_TRANSPORT"  "$KB_API_RC_TRANSPORT" "$rc_t"
eq "…and no body on stdout"                        ""    "$out_t"
eq "…and the diagnostic says curl failed"          "true" "$(case "$(cat "$_api_err")" in *'curl failed on PATCH /tasks/9.json'*) echo true ;; *) echo false ;; esac)"
# KB_HTTP is read from a call that is NOT inside a command substitution — see the
# subshell case at the end of this block for why that distinction is the whole reason
# the rc carries the signal at all.
KB_HTTP=stale
kb_api PATCH /tasks/9.json '{"a":1}' >/dev/null 2>&1 || true
eq "…and KB_HTTP is the 000 sentinel"              "000" "$KB_HTTP"

# --- 2. THE SERVER ANSWERED 500 ---
curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"error":"server exploded"}' 500; }
rc_500=0; out_500="$(kb_api PATCH /tasks/9.json '{"a":1}' 2>"$_api_err")" || rc_500=$?
eq "a completed 500 → rc 1 (unchanged for every existing caller)" "1" "$rc_500"
eq "…and no body on stdout"                        ""     "$out_500"
eq "…and the diagnostic names the status"          "true" "$(case "$(cat "$_api_err")" in *'HTTP 500 on PATCH /tasks/9.json'*) echo true ;; *) echo false ;; esac)"
eq "⭐ 500 is DISTINGUISHABLE from the transport failure" "differ" \
   "$(if [[ "$rc_500" == "$rc_t" ]]; then echo same; else echo differ; fi)"
KB_HTTP=stale
kb_api PATCH /tasks/9.json '{"a":1}' >/dev/null 2>&1 || true
eq "…and KB_HTTP carries 500, not 000"             "500" "$KB_HTTP"

# --- 3. THE SERVER ANSWERED 404 — the common case, and an ANSWER, not an absence of one ---
curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"error":"not found"}' 404; }
rc_404=0; kb_api GET /tasks/9.json >/dev/null 2>"$_api_err" || rc_404=$?
eq "a completed 404 → rc 1"                        "1" "$rc_404"
eq "⭐ 404 is DISTINGUISHABLE from the transport failure" "differ" \
   "$(if [[ "$rc_404" == "$rc_t" ]]; then echo same; else echo differ; fi)"
eq "…and the diagnostic names the status"          "true" "$(case "$(cat "$_api_err")" in *'HTTP 404 on GET /tasks/9.json'*) echo true ;; *) echo false ;; esac)"

# --- 4. A 2xx still succeeds, byte for byte ---
curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"data":{"id":9}}' 200; }
rc_200=0; out_200="$(kb_api GET /tasks/9.json 2>"$_api_err")" || rc_200=$?
eq "a 2xx → rc 0"                                  "0" "$rc_200"
eq "…with the response body on stdout"             '{"data":{"id":9}}' "$out_200"
eq "…and nothing on stderr"                        ""  "$(cat "$_api_err")"

# --- the rc is the channel BECAUSE the global cannot cross a command substitution ---
# `resp="$(kb_api …)" || …` is the caller shape this tree is built out of, and it runs
# kb_api in a SUBSHELL: KB_HTTP set in there is gone when the parent tests it. This is
# what makes "just read KB_HTTP" a non-answer for those callers, and the rc is asserted
# here so a future edit cannot quietly move the signal back onto the global.
#
# ⛔ THE OTHER HALF IS DELIBERATELY NOT ASSERTED. A companion
# `eq "KB_HTTP does NOT survive the caller's \$( … )" "pre-existing" "$KB_HTTP"` stood here
# and was a DECORATION: a command substitution is a subshell by the language's definition, so
# no edit to this repo's code can make an assignment inside one reach the parent — that check
# passes against kb_api, against a kb_api that never touches KB_HTTP, and against no kb_api at
# all. What this repo DOES own — that kb_api sets the global to the 000 sentinel on this path —
# can fail, and is already asserted at the top of this block off a call that is not wrapped in
# `$( … )`; restating it here would be a second copy of one assertion, not a second assertion.
curl() { cat >/dev/null; return 7; }
rc_sub=0; _ignored="$(kb_api GET /tasks/9.json 2>/dev/null)" || rc_sub=$?
eq "the rc crosses the caller's \$( … ) — the signal has to ride it" "$KB_API_RC_TRANSPORT" "$rc_sub"
# A property of the constant, not its value: 0 would read as success and 2 as a usage
# error in every CLI here, and 1 is the state it exists to be told apart from.
eq "the transport rc is none of 0, 1, 2"           "true" \
   "$(case "$KB_API_RC_TRANSPORT" in 0|1|2) echo false ;; *) echo true ;; esac)"

echo "-- kb_api_status: the SAME distinction, on the status line, at rc 0 --"
# The sibling. Its discriminator is the status line, so it needs no rc — and it must not
# grow one: dl-a1-register-field captures it with a BARE assignment under `set -e`, where
# any non-zero rc kills the script before the status is read. These two cases hold both
# halves: the states stay distinguishable AND the rc stays 0.
curl() { cat >/dev/null; return 7; }
KB_HTTP=stale
rc_st=0; st_out="$(kb_api_status GET /tasks/9.json)" || rc_st=$?
eq "transport failure → status line 000"           "000" "${st_out%%$'\n'*}"
eq "…at rc 0 (its callers' bare \$( … ) under set -e)" "0" "$rc_st"
kb_api_status GET /tasks/9.json >/dev/null 2>&1 || true
eq "…and KB_HTTP agrees with the status line"      "000" "$KB_HTTP"

curl() { _STUB_ARGS=("$@"); _stub_curl_respond '{"error":"server exploded"}' 500; }
rc_st5=0; st_out5="$(kb_api_status GET /tasks/9.json)" || rc_st5=$?
eq "a completed 500 → status line 500"             "500" "${st_out5%%$'\n'*}"
eq "⭐ …distinguishable from 000 without parsing a message" "differ" \
   "$(if [[ "${st_out5%%$'\n'*}" == "${st_out%%$'\n'*}" ]]; then echo same; else echo differ; fi)"
eq "…still at rc 0"                                "0" "$rc_st5"

unset -f curl
unset KB_API KB_TOKEN KB_HTTP _api_err out_t out_500 out_200 st_out st_out5 _ignored \
      rc_t rc_500 rc_404 rc_200 rc_sub rc_st rc_st5

# ---------------------------------------------------------------------------
echo "== kb_is_uint — the CANONICAL decimal spelling, leading zero refused (card#6912) =="
# WHY THE LEADING-ZERO CASES ARE THE POINT. Every adopter hands the value it accepts to bash
# arithmetic, and bash reads a leading-zero literal as BASE 8. Measured against the old
# `^[0-9]+$`: `kb_is_uint 010` said yes and `[[ 010 -eq 10 ]]` was then FALSE (010 is 8), and
# `kb_is_uint 08` said yes and the next `[[ 08 -gt 0 ]]` died with
# `[[: 08: value too great for base (error token is "08")` — a raw bash fault leaking out of a
# guard whose whole job was to prevent one. So these are not spelling nits: each is a value the
# predicate vouched for and the next line then got wrong or crashed on.
expect_rc "0 is a uint (posctl — the one spelling of zero)"  0 kb_is_uint "0"
expect_rc "1 is a uint (posctl)"                             0 kb_is_uint "1"
expect_rc "42 is a uint (posctl)"                            0 kb_is_uint "42"
expect_rc "100 is a uint (posctl — an interior zero is fine)" 0 kb_is_uint "100"
expect_rc "010 refused (bash reads it as 8, not 10)"         1 kb_is_uint "010"
expect_rc "08 refused (not even a legal octal literal)"      1 kb_is_uint "08"
expect_rc "007 refused"                                      1 kb_is_uint "007"
expect_rc "00 refused (a second spelling of zero)"           1 kb_is_uint "00"
expect_rc "0101 refused"                                     1 kb_is_uint "0101"
# The pre-existing contract, unchanged by the tightening — asserted HERE so a future widening
# of the pattern cannot quietly re-admit these while the leading-zero cases stay green.
expect_rc "empty refused"                                    1 kb_is_uint ""
expect_rc "no argument at all refused"                       1 kb_is_uint
expect_rc "non-numeric refused"                              1 kb_is_uint "abc"
expect_rc "a signed value is not a uint"                     1 kb_is_uint "+5"
expect_rc "a negative value is not a uint"                   1 kb_is_uint "-5"
expect_rc "a decimal is not a uint"                          1 kb_is_uint "1.0"
expect_rc "leading whitespace refused"                       1 kb_is_uint " 5"
expect_rc "trailing whitespace refused"                      1 kb_is_uint "5 "

echo "== kb_is_repo_slug — the bare <owner>/<name> predicate (card#8421) =="
# ⛔ A SHAPE TEST ALONE CANNOT DO THIS JOB, which is why the shape-only rows below are not the
# whole accept set. The value this predicate gates is spent TWICE, on both sides of ONE
# comparison: `bin/adopt-to-dl` interpolates it into the placeholder `pr_url` the card is
# STAMPED with, AND into the `source=` of the step-5 by-ref VERIFY. A spelling that survives
# here therefore derives the SAME garbage on both sides, so the verify passes VACUOUSLY and
# "adopted => correlatable" is certified by a check that could not have failed (canon #9) —
# while the bridge writeback and the reconcile, which derive the source through the server's
# own repoFromGitHubUrl, correlate the card to nothing.
#   * `git@github.com:acme/widget` — one slash, two non-empty parts, no whitespace, so a SHAPE
#     test alone accepts it (measured). It stamps `github.com/git@github.com:acme/widget/pull/0`,
#     whose capture is `git@github.com:acme/widget`; the verify then queries that same string.
#   * `acme/*` — same story, and the stored source is a literal `*` that names no repo.
#   * `acme/widget.git` — the one spelling that does NOT pass vacuously, and it is worse than a
#     refusal rather than better: repoFromGitHubUrl TRIMS the `.git`, so the card's derived
#     source is `acme/widget` while the verify queries `acme/widget.git` — it fails LOUD, AFTER
#     the card has already been stamped. Refusing before the write leaves nothing half-applied.
# The pair asserted here is the one `bin/promote-released-cards` applies to `.promote.source`
# (`src_charset_ok` plus its shape `case`) — the same value at the other end of the same
# correlation. That tool is a vendored standalone that must not source this lib, so the copy
# stands and the two must be kept in sync.
expect_rc "owner/name valid"          0 kb_is_repo_slug "owner/name"
expect_rc "mixed-case owner valid"    0 kb_is_repo_slug "AIMLA-org/platform"
expect_rc "no slash rejected"         1 kb_is_repo_slug "owner"
expect_rc "two slashes rejected"      1 kb_is_repo_slug "owner/name/extra"
expect_rc "full URL rejected"         1 kb_is_repo_slug "https://github.com/owner/name"
expect_rc "whitespace rejected"       1 kb_is_repo_slug "owner /name"
expect_rc "empty rejected"            1 kb_is_repo_slug ""
expect_rc "no argument at all rejected" 1 kb_is_repo_slug
expect_rc "empty owner rejected"      1 kb_is_repo_slug "/name"
expect_rc "empty name rejected"       1 kb_is_repo_slug "owner/"
expect_rc "scp-style remote rejected" 1 kb_is_repo_slug "git@github.com:acme/widget"
expect_rc "a .git suffix rejected"    1 kb_is_repo_slug "acme/widget.git"
# THE SUFFIX ARM IS CASE-INSENSITIVE, and the uppercase spellings are not a curiosity — they are
# the one input on which this predicate DISAGREED with its declared duplicate. `.git` is refused
# because the two derivations disagree about it (see the arm's own comment in the lib), and that
# disagreement is a property of the SUFFIX, not of its casing: GitHub's `<owner>/<name>` is
# case-insensitive, `repoFromGitHubUrl` is `/i` and trims `.GIT` too, so `acme/widget.GIT` stamps
# a card whose derived source is `acme/widget` and then verifies against `acme/widget.git` —
# LOUD, but only AFTER the counter is consumed and the card stamped, which is the exact
# half-applied write the arm exists to prevent. `bin/promote-released-cards`' copy lowercases
# before its own `case`, so it refused these all along; this predicate accepted them until
# card#8421's third review round, and § 3c of tests/promote-source-qualify-selftest.sh is what
# now holds the two accept sets to each other rather than leaving it to two files' comments to
# agree.
expect_rc "a .GIT suffix rejected"    1 kb_is_repo_slug "acme/widget.GIT"
expect_rc "a .Git suffix rejected"    1 kb_is_repo_slug "acme/widget.Git"
expect_rc "a glob is not a repo"      1 kb_is_repo_slug "acme/*"
expect_rc "a URL scheme rejected"     1 kb_is_repo_slug "ssh://git@github.com/acme/widget"
expect_rc "a colon is not in the set" 1 kb_is_repo_slug "acme:x/widget"
# CONTROLS — without these a predicate that refused EVERYTHING would pass every row above.
# Each is a spelling a real adoption or coverage read uses and must keep accepting.
expect_rc "control: a plain repo passes"    0 kb_is_repo_slug "acme/widget"
expect_rc "control: a dot inside a name"    0 kb_is_repo_slug "acme/widget.js"
expect_rc "control: underscore + hyphen"    0 kb_is_repo_slug "acme_org/my-repo"
expect_rc "control: digits either side"     0 kb_is_repo_slug "acme2/widget3"
# `.git` is refused by its own arm and NOT by the charset, so the two must stay distinguishable:
# a name that merely CONTAINS `.git` is legal and must still pass, or the suffix arm has quietly
# become a substring ban.
expect_rc "control: '.git' inside a name is not the suffix" 0 kb_is_repo_slug "acme/widget.gitignore"
expect_rc "control: '.GIT' inside a name is not the suffix" 0 kb_is_repo_slug "acme/widget.GITIGNORE"
expect_rc "control: an owner may end in .git-ish text"      0 kb_is_repo_slug "acme.github/widget"

echo "== kb_dl_num — strict (rejects non-DL loudly) =="
expect_out "bare int"                   "42"  kb_dl_num "42"
expect_out "DL-093 -> 93"               "93"  kb_dl_num "DL-093"
expect_out "lowercase dl- prefix"       "42"  kb_dl_num "dl-042"
expect_rc  "no digits rejected"         2     kb_dl_num "DL-"
expect_rc  "all-zeros rejected"         2     kb_dl_num "DL-0000"
expect_rc  "mixed junk rejected"        2     kb_dl_num "v2-DL-0042"
expect_rc  "over-6-digits rejected"     2     kb_dl_num "1234567"

echo "== kb_dl_canon — the ONE canonical stored form DL-NNNN =="
expect_out "pads to 4"                  "DL-0093"   kb_dl_canon "93"
expect_out "already-canonical token"    "DL-0093"   kb_dl_canon "DL-093"
expect_out "5-digit not truncated"      "DL-12345"  kb_dl_canon "12345"
expect_rc  "non-DL rejected"            2           kb_dl_canon "not-a-dl"

echo "== kb_dl_int_lenient — server canonicalize('dl') (strip non-digits, collapse zeros) =="
expect_out "bare int"                   "42"    kb_dl_int_lenient "42"
expect_out "DL-088 3-pad -> 88"         "88"    kb_dl_int_lenient "DL-088"
expect_out "DL-0192 4-pad -> 192"       "192"   kb_dl_int_lenient "DL-0192"
expect_out "lowercase dl- prefix"       "42"    kb_dl_int_lenient "dl-042"
expect_out "empty -> empty"             ""      kb_dl_int_lenient ""
expect_out "no digits -> empty"         ""      kb_dl_int_lenient "DL-"
expect_out "all-zeros -> 0"             "0"     kb_dl_int_lenient "DL-0000"
expect_out "multi-run strips all"       "20042" kb_dl_int_lenient "v2-DL-0042"

echo "== kb_by_ref_hit — object-or-array tolerant by-ref predicate =="
expect_rc "envelope: card present -> hit"        0 kb_by_ref_hit '{"data":[{"id":4020}]}'          4020
expect_rc "envelope: present among many"         0 kb_by_ref_hit '{"data":[{"id":4020},{"id":5}]}' 4020
expect_rc "envelope: different card -> miss"     1 kb_by_ref_hit '{"data":[{"id":99}]}'            4020
expect_rc "envelope: empty data -> miss"         1 kb_by_ref_hit '{"data":[]}'                     4020
expect_rc "bare array: present -> hit"           0 kb_by_ref_hit '[{"id":4020}]'                   4020
expect_rc "bare array: different -> miss"        1 kb_by_ref_hit '[{"id":99}]'                     4020
expect_rc "bare empty array -> miss"             1 kb_by_ref_hit '[]'                              4020
expect_rc "missing data key -> miss"             1 kb_by_ref_hit '{}'                              4020
# Malformed JSON: jq's own parse-error exit code passes through (not necessarily 1); the
# contract every caller relies on is "falsy = no hit", so assert the truthiness, not the code.
if kb_by_ref_hit 'not json' 4020; then bad "malformed json -> miss (fail-closed)"; else ok "malformed json -> miss (fail-closed)"; fi

# ---------------------------------------------------------------------------
echo "== kb_require_value — a value-taking flag's PRESENCE is the dispatch signal =="
# The primitive behind card#5146. Consumers pass `"$1" "${2:-}"` from their arg loop, so
# this must reject BOTH an explicitly-empty value and a missing argument entirely — the two
# inputs that a later `[[ -n "$var" ]]` cannot tell apart from the flag being absent.
rc=0; err="$(kb_require_value --dl "" 2>&1)" || rc=$?
eq "empty value → rc 1"                    "1" "$rc"
eq "empty value names the flag"            "true" "$(case "$err" in *'--dl requires a non-empty value'*) echo true ;; *) echo false ;; esac)"
eq "diagnostic is prefixed with the prog"  "true" "$(case "$err" in "$KB_PROG:"*) echo true ;; *) echo false ;; esac)"

rc=0; kb_require_value --dl >/dev/null 2>&1 || rc=$?
eq "missing argument entirely → rc 1"      "1" "$rc"

rc=0; err="$(kb_require_value --dl "DL-7" 2>&1)" || rc=$?
eq "non-empty value → rc 0"                "0" "$rc"
eq "non-empty value is silent"             ""  "$err"

# Whitespace is a VALUE, not emptiness — this guard's job is presence-vs-absence only, and a
# domain-meaningless value stays the caller's validation to make (promote-released-cards, for
# one, normalizes whitespace and then rejects it with its own message).
rc=0; kb_require_value --dl " " >/dev/null 2>&1 || rc=$?
eq "whitespace-only value → rc 0 (not this guard's call)" "0" "$rc"

# ---------------------------------------------------------------------------
_summary "kb-board-lib-selftest"
