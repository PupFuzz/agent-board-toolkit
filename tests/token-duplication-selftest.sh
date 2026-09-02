#!/usr/bin/env bash
# token-duplication-selftest.sh — the duplicate-kanban-token leg of
# bin/agent-board-toolkit-runtime-check (card#8376, roundtable 336).
#
# WHAT IT IS FOR. The coord-store rung (card#7316) let a seat stop keeping a second plaintext
# copy of its kanban token; it does not DELETE the copy an operator already minted, and until
# this leg existed nothing on the box could see one. A detector that cannot tell the two states
# apart — the same credential in two files, versus two different live credentials — is
# decoration, so both are driven here, each against a control that fires the other way.
#
# ⛔ THE LEAK CONTROL IS THE POINT OF THIS FILE, not a nicety. A duplicate detector is by
# construction the one instrument that resolves two credentials at once, so the firing run is
# driven with a KNOWN planted token value and the tool's whole stdout+stderr is searched for it —
# and for its sha256, which is the value the leg actually compares. Both searches are preceded by
# a positive control proving the search finds that string when it IS present, because an
# absence-only assertion certifies whatever replaces it.
#
# THE MIRROR PARITY BLOCK at the end is the other half. runtime-check must not source
# `_kb-board-lib.sh` (it judges it), so the store rung and its two helpers are duplicated inside
# it — guarded duplication, per docs/CONSOLIDATION-PLAN.md § Stage D. This file EXTRACTS those
# functions and drives them row-by-row against the lib's originals, and EXITS 1 if it cannot
# extract one, so a rename reds the build instead of silently retiring the comparison. A drifted
# mirror resolves a different file than the tools do, and then the leg above reports a duplicate
# that is not there, or misses the one that is.
#
# Network-free. Every case runs under a scratch HOME with a PATH carrying no toolkit tool, so the
# PATH-topology legs of the check contribute their own warn and rc 0 — every rc 1 below is this
# leg's verdict and nothing else's.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
CHECK="$HERE/../bin/agent-board-toolkit-runtime-check"
LIB="$HERE/../bin/_kb-board-lib.sh"
_need -x "$CHECK"
_need -r "$LIB"

_mktmp_scratch
SEAT="$TMP/home"

# reset_seat — an empty scratch HOME. Every case builds the seat it means to measure; a fixture
# left over from the case above is how a green run stops being about the case it names.
reset_seat() {
    rm -rf "$SEAT"
    mkdir -p "$SEAT/.config/coord"
}

# run_check [args...] -> RC, OUT (stdout AND stderr, which is what an operator reads)
run_check() {
    RC=0
    OUT="$(HOME="$SEAT" PATH="${STUB_PATH:-}/usr/bin:/bin" env -u KBCARD_TOKEN_FILE -u COORD_CREDENTIALS \
           -u KANBAN_HOST_ENV "$CHECK" "$@" 2>&1)" || RC=$?
}

FAKE='FAKETOKEN-c8376-planted-do-not-leak-8f3a2b1c'
HOSTNAME_FIXTURE='board.invalid'   # kb_require_known_api_host needs a declared host to match
FAKE_DIGEST="$(printf '%s\n' "$FAKE" | sha256sum)"; FAKE_DIGEST="${FAKE_DIGEST%% *}"
OTHER='OTHERTOKEN-c8376-planted-second-credential-4d5e6f'

mk_board() { # <name> [token file path]
    printf 'export KB_BOARD_ID=%s\n' "$((RANDOM % 900 + 100))" > "$SEAT/.kanban-$1-board.env"
    [ "$#" -lt 2 ] || printf 'export KBCARD_TOKEN_FILE="%s"\n' "$2" >> "$SEAT/.kanban-$1-board.env"
}
mk_store() { # <token file path>
    printf '[kanban]\napi_token_file = %s\n' "$1" > "$SEAT/.config/coord/credentials.ini"
}

echo "== control: ONE token file, one board → green and silent =="
reset_seat
printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"
mk_board dev "$SEAT/.kanban-dev-token"
run_check
eq "single source → rc 0"                    "0"     "$RC"
eq "  …and says so"                          "true"  "$(has 'one kanban token file resolves' "$OUT")"
eq "  …with no duplicate finding"            "false" "$(has 'DUPLICATE kanban token' "$OUT")"
eq "  …and no second-credential finding"     "false" "$(has 'SECOND kanban credential' "$OUT")"

echo "== control: two declarations naming the SAME file are ONE credential =="
# The host env and the board env both name it, and a symlink alias names it a third time. A
# check keyed on declarations rather than on the resolved file reports a duplicate here.
reset_seat
printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"
ln -s "$SEAT/.kanban-dev-token" "$SEAT/.kanban-alias-token"
printf 'export KBCARD_TOKEN_FILE="%s"\n' "$SEAT/.kanban-alias-token" > "$SEAT/.kanban-host.env"
mk_board dev "$SEAT/.kanban-dev-token"
run_check
eq "same file under two names → rc 0"        "0"     "$RC"
eq "  …no duplicate invented"                "false" "$(has 'DUPLICATE kanban token' "$OUT")"

echo "== control: two declarations naming one file through a HARD LINK are ONE credential =="
# The symlink case above is settled by `readlink -f`; a hard link is not. Each name of a
# hard-linked file HAS its own canonical path, so an identity keyed on the path text reads one
# inode as two files with equal digests and issues a keep-one-DELETE-the-other verdict over a
# single credential — deleting either name changes nothing about how many this seat carries.
reset_seat
printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"
if ln "$SEAT/.kanban-dev-token" "$SEAT/.kanban-hard-token" 2>/dev/null; then
    printf 'export KBCARD_TOKEN_FILE="%s"\n' "$SEAT/.kanban-hard-token" > "$SEAT/.kanban-host.env"
    mk_board dev "$SEAT/.kanban-dev-token"
    run_check
    eq "one inode under two names → rc 0"    "0"     "$RC"
    eq "  …no duplicate invented"            "false" "$(has 'DUPLICATE kanban token' "$OUT")"
    eq "  …and both declarations are credited" "true" "$(has "$SEAT/.kanban-host.env" "$OUT")"
    # Control: two SEPARATE files holding the same bytes, declared the same two ways, DO red — so
    # the arm above is about file identity and not about a leg that had stopped firing.
    rm -f "$SEAT/.kanban-hard-token"
    printf '%s\n' "$FAKE" > "$SEAT/.kanban-hard-token"
    run_check
    eq "control: two real files, same bytes → rc 1" "1" "$RC"
else
    ok "skipped: this filesystem refused a hard link"
fi

echo "== control: per-board isolation — two boards, two DIFFERENT tokens, both in use =="
# The topology card#7245 exists to produce. Failing it would tell every correct multi-board
# install to break itself, so it is asserted as green rather than left to chance.
reset_seat
printf '%s\n' "$FAKE"  > "$SEAT/.kanban-a-token"
printf '%s\n' "$OTHER" > "$SEAT/.kanban-b-token"
mk_board a "$SEAT/.kanban-a-token"
mk_board b "$SEAT/.kanban-b-token"
run_check
eq "per-board isolation → rc 0"              "0"     "$RC"
eq "  …no duplicate finding"                 "false" "$(has 'DUPLICATE kanban token' "$OUT")"
eq "  …no second-credential finding"         "false" "$(has 'SECOND kanban credential' "$OUT")"
eq "  …and it says both are in use"          "true"  "$(has 'per-board isolation' "$OUT")"

echo "== ⭐ the card's state: the store points at the SAME credential a board env also holds =="
reset_seat
printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"
printf '%s\n' "$FAKE" > "$SEAT/.config/coord/kanban-token"
mk_store "$SEAT/.config/coord/kanban-token"
mk_board dev "$SEAT/.kanban-dev-token"
run_check
eq "duplicate credential → rc 1"             "1"     "$RC"
eq "  …named as a duplicate"                 "true"  "$(has 'DUPLICATE kanban token' "$OUT")"
eq "  …names the file to DELETE"             "true"  "$(has "DELETE $SEAT/.kanban-dev-token" "$OUT")"
eq "  …keeps the store-managed file"         "true"  "$(has "keep $SEAT/.config/coord/kanban-token" "$OUT")"
eq "  …names the source that declares it"    "true"  "$(has "$SEAT/.kanban-dev-board.env" "$OUT")"
eq "  …and points at the doc section"        "true"  "$(has 'docs/INSTALL.md §3b' "$OUT")"

echo "== ⛔ NO VALUE LEAKS — the firing run's whole output, searched for the planted token =="
eq "witness: the planted files really hold it" "true" \
   "$(has "$FAKE" "$(cat "$SEAT/.kanban-dev-token" "$SEAT/.config/coord/kanban-token")")"
eq "witness: the run produced a report to search" "true" \
   "$([ "${#OUT}" -gt 100 ] && echo true || echo false)"
eq "control: the search FINDS that string when it is present" "true" "$(has "$FAKE" "$OUT$FAKE")"
eq "  the token VALUE is absent from stdout+stderr"           "false" "$(has "$FAKE" "$OUT")"
eq "control: the search finds the DIGEST when present"        "true" "$(has "$FAKE_DIGEST" "$OUT$FAKE_DIGEST")"
eq "  the digest is absent too (compared, never printed)"     "false" "$(has "$FAKE_DIGEST" "$OUT")"

echo "== …and the verdict survives --quiet, which is how SessionStart runs it =="
run_check --quiet
eq "--quiet still reds on a duplicate"       "1"     "$RC"
eq "  …and still explains why"               "true"  "$(has 'DUPLICATE kanban token' "$OUT")"
eq "  …and still leaks nothing"              "false" "$(has "$FAKE" "$OUT")"

echo "== ⭐ the copy an install FORGETS: declared by NOTHING, seen only through the glob =="
# docs/INSTALL.md §3b: migrating onto the store's pointer means DROPPING step (c)'s
# KBCARD_TOKEN_FILE line — after which the old ~/.kanban-<name>-token is named by NO source at
# all. A population built from declarations alone answers `ok — one kanban token file resolves`
# over exactly that seat, which is the state §3b tells the operator this check reports. The
# population is therefore the declared sources PLUS the literal glob `~/.kanban-*-token`.
reset_seat
printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"            # the forgotten copy: nothing names it
printf '%s\n' "$FAKE" > "$SEAT/.config/coord/kanban-token"
mk_store "$SEAT/.config/coord/kanban-token"
mk_board dev                                                  # step (c) dropped — declares no token
run_check
eq "an UNDECLARED same-digest copy → rc 1"   "1"     "$RC"
eq "  …named as a duplicate"                 "true"  "$(has 'DUPLICATE kanban token' "$OUT")"
eq "  …names the forgotten file to DELETE"   "true"  "$(has "DELETE $SEAT/.kanban-dev-token" "$OUT")"
eq "  …says NO source declares it"           "true"  "$(has 'NO source declares it' "$OUT")"
eq "  …states the population it walked"      "true"  "$(has '`~/.kanban-*-token` scan' "$OUT")"
eq "  …and the remedy is rm, not a config edit" "true" \
   "$(has 'UNDECLARED copy is named by no config line' "$OUT")"
eq "  …no DROP-the-declaration sentence, since there is none" "false" \
   "$(has 'Then either DROP the KBCARD_TOKEN_FILE line' "$OUT")"
eq "  …keeping the store-managed file"       "true"  "$(has "keep $SEAT/.config/coord/kanban-token" "$OUT")"
eq "control: the search FINDS the value when present" "true" "$(has "$FAKE" "$OUT$FAKE")"
eq "  …and the token VALUE is absent"        "false" "$(has "$FAKE" "$OUT")"
eq "control: the search finds the DIGEST when present" "true" "$(has "$FAKE_DIGEST" "$OUT$FAKE_DIGEST")"
eq "  …and the digest is absent too"         "false" "$(has "$FAKE_DIGEST" "$OUT")"

echo "-- control: the SAME bytes in a file OUTSIDE the glob are not reported --"
# `~/.kanban-dev-token.bak` does not match `~/.kanban-*-token`. That edge is what the glob being
# STATED verbatim on every surface buys the operator: the check does not sweep $HOME, and a
# reader can tell which file it would have missed without running it.
mv "$SEAT/.kanban-dev-token" "$SEAT/.kanban-dev-token.bak"
run_check
eq "a copy outside the glob → rc 0"          "0"     "$RC"
eq "  …no duplicate reported"                "false" "$(has 'DUPLICATE kanban token' "$OUT")"
eq "  …and that file is never named"         "false" "$(has '.kanban-dev-token.bak' "$OUT")"
eq "  …the seat reads as one resolving file" "true"  "$(has 'one kanban token file resolves' "$OUT")"

echo "-- an UNDECLARED file holding a DIFFERENT token is the ⚠ arm, not the ✗ one --"
rm -f "$SEAT/.kanban-dev-token.bak"
printf '%s\n' "$OTHER" > "$SEAT/.kanban-dev-token"
run_check
eq "undeclared, different value → rc 0"      "0"     "$RC"
eq "  …named as a SECOND credential"         "true"  "$(has 'SECOND kanban credential' "$OUT")"
eq "  …distinguished from a stale copy"      "false" "$(has 'DUPLICATE kanban token' "$OUT")"
eq "  …with the rm-or-adopt remedy"          "true"  "$(has "rm $SEAT/.kanban-dev-token" "$OUT")"
eq "  …and no declaration to delete is implied" "false" \
   "$(has 'delete it and the declaration naming it' "$OUT")"
eq "  …and it leaks nothing"                 "false" "$(has "$OTHER" "$OUT")"
# ⚠ arms ride stderr, which --quiet does NOT silence — only the `ok` lines are suppressed. Driven
# here because a `warn()` that honoured QUIET would leave every rc-0 finding invisible at
# SessionStart, which is the one place this leg is actually read.
run_check --quiet
eq "  …and the ⚠ still prints under --quiet" "true"  "$(has 'SECOND kanban credential' "$OUT")"
eq "  …at rc 0"                              "0"     "$RC"

echo "== two DIFFERENT live credentials → reported, distinguished, and NOT gated =="
# The host env declares one, every board overrides it: nothing on this seat resolves the host's
# file, so it is a second live credential that only its own operator remembers to rotate.
reset_seat
printf '%s\n'  "$FAKE" > "$SEAT/.kanban-dev-token"
printf '%s\n' "$OTHER" > "$SEAT/.kanban-legacy-token"
printf 'export KBCARD_TOKEN_FILE="%s"\n' "$SEAT/.kanban-legacy-token" > "$SEAT/.kanban-host.env"
mk_board dev "$SEAT/.kanban-dev-token"
run_check
eq "different values → rc 0 (reported, not gated)" "0"    "$RC"
eq "  …named as a SECOND credential"         "true"  "$(has 'SECOND kanban credential' "$OUT")"
eq "  …distinguished from a stale copy"      "false" "$(has 'DUPLICATE kanban token' "$OUT")"
eq "  …names the orphaned file"              "true"  "$(has "$SEAT/.kanban-legacy-token" "$OUT")"
eq "  …and the source that declares it"      "true"  "$(has "$SEAT/.kanban-host.env" "$OUT")"
eq "  …and leaks neither value"              "false" "$(has "$OTHER" "$OUT")"
# M2: the two original remedies BOTH change a topology INSTALL §3b sanctions, and the first one
# deletes a declaration and a token file belonging to the coord framework's own tooling, which
# this toolkit does not own. The third arm is what makes the ⚠ readable as "possibly nothing".
eq "  …offers the supported shadowed-pointer arm" "true" \
   "$(has 'this is the supported shadowed-pointer install' "$OUT")"
# M3: the predicate is the board-env GLOB, so the claim has to carry that bound — a board env
# reached only through $KBCARD_BOARD_ENV is documented back-compat and is not in the population.
eq "  …bounds the boards it consulted"       "true" \
   "$(has 'any board declared under `~/.kanban-*-board.env` resolves' "$OUT")"
eq "  …and names what it cannot see"         "true" \
   "$(has 'reached only through $KBCARD_BOARD_ENV' "$OUT")"
run_check --quiet
eq "  …the ⚠ survives --quiet"               "true"  "$(has 'SECOND kanban credential' "$OUT")"
eq "  …still at rc 0"                        "0"     "$RC"

echo "== the AMBIENT KBCARD_TOKEN_FILE is a source too =="
# The tier an operator shell creates by sourcing a board env, or a hook by exporting one. It is
# the one source that is not a file on the box, so it is the one a file-walking implementation
# would silently omit — and omitting it is a MISSED duplicate, the failure direction that reads
# as healthy.
reset_seat
printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"
# OUTSIDE the `~/.kanban-*-token` glob, deliberately: inside it the file is a member of the
# undeclared population and the control below would red on the SCAN's finding rather than on the
# ambient tier's, measuring a different claim than it names.
STRAY="$SEAT/.config/coord/ambient.token"
printf '%s\n' "$FAKE" > "$STRAY"
mk_board dev "$SEAT/.kanban-dev-token"
RC=0
OUT="$(HOME="$SEAT" PATH=/usr/bin:/bin env -u COORD_CREDENTIALS -u KANBAN_HOST_ENV \
       KBCARD_TOKEN_FILE="$STRAY" "$CHECK" 2>&1)" || RC=$?
eq "an ambient duplicate is seen → rc 1"     "1"     "$RC"
eq "  …and the environment is named as the source" "true" \
   "$(has 'exported into this process' "$OUT")"
eq "  …naming the stray file to delete"      "true"  "$(has "$STRAY" "$OUT")"
eq "  …and leaking nothing"                  "false" "$(has "$FAKE" "$OUT")"
# Control: the same seat WITHOUT the ambient export is clean, so the assertion above is about
# that tier and not about the two files merely existing.
run_check
eq "control: the same two files with no ambient export → rc 0" "0" "$RC"

echo "== the mirror's REFUSALS are the lib's: an inline store token resolves NOTHING =="
# Same two files as the card's state above — but the store declares an INLINE token and no
# pointer, so the tools resolve nothing from it and neither may this leg. A mirror that read the
# inline form would invent a source and report a duplicate the operator cannot act on.
reset_seat
printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"
printf '%s\n' "$FAKE" > "$SEAT/.config/coord/kanban-token"
printf '[kanban]\napi_token = %s\n' "$FAKE" > "$SEAT/.config/coord/credentials.ini"
mk_board dev "$SEAT/.kanban-dev-token"
run_check
eq "inline store token → rc 0"               "0"     "$RC"
eq "  …no duplicate reported"                "false" "$(has 'DUPLICATE kanban token' "$OUT")"
eq "  …and the inline value is not echoed"   "false" "$(has "$FAKE" "$OUT")"
# Control: the SAME two files, with the store spelling a POINTER, do red — so the assertion
# above is about the inline refusal and not about a leg that had stopped firing.
mk_store "$SEAT/.config/coord/kanban-token"
run_check
eq "control: the same files under a POINTER → rc 1" "1" "$RC"

echo "== no board env ⇒ no resolution context ⇒ silent =="
reset_seat
printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"
printf '%s\n' "$FAKE" > "$SEAT/.config/coord/kanban-token"
mk_store "$SEAT/.config/coord/kanban-token"
run_check
eq "two files, no board env → rc 0"          "0"     "$RC"
eq "  …and nothing is claimed about them"    "false" "$(has 'kanban token' "$OUT")"

echo "== cannot digest ⇒ honest UNKNOWN, not ok, and not a verdict =="
# sha256sum shadowed by a stub that fails. The seat is the card's duplicate state, so the leg
# has something real to be unable to judge.
reset_seat
printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"
printf '%s\n' "$FAKE" > "$SEAT/.config/coord/kanban-token"
mk_store "$SEAT/.config/coord/kanban-token"
mk_board dev "$SEAT/.kanban-dev-token"
mkdir -p "$TMP/stub"; printf '#!/bin/sh\nexit 1\n' > "$TMP/stub/sha256sum"; chmod +x "$TMP/stub/sha256sum"
STUB_PATH="$TMP/stub:" run_check
eq "no digest tool → rc 0"                   "0"     "$RC"
eq "  …says CANNOT BE VERIFIED"              "true"  "$(has 'CANNOT BE VERIFIED' "$OUT")"
eq "  …and does not guess a verdict"         "false" "$(has 'DUPLICATE kanban token' "$OUT")"
STUB_PATH="$TMP/stub:" run_check --quiet
eq "  …and the ⚠ survives --quiet"           "true"  "$(has 'CANNOT BE VERIFIED' "$OUT")"
run_check
eq "control: with the real sha256sum the same seat reds" "1" "$RC"

echo "== a store that exists but cannot be read is UNKNOWN, not absent =="
if [ "$(id -u)" -ne 0 ]; then
    reset_seat
    printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"
    mk_board dev "$SEAT/.kanban-dev-token"
    mk_store "$SEAT/.config/coord/kanban-token"
    chmod 000 "$SEAT/.config/coord/credentials.ini"
    run_check
    eq "unreadable store → rc 0"             "0"    "$RC"
    eq "  …and says so, as UNKNOWN"          "true" "$(has 'is not readable' "$OUT")"
    run_check --quiet
    eq "  …and that ⚠ survives --quiet"      "true" "$(has 'is not readable' "$OUT")"
    chmod 600 "$SEAT/.config/coord/credentials.ini"
    run_check
    eq "control: readable again → silent about readability" "false" "$(has 'is not readable' "$OUT")"
else
    ok "skipped: running as root, where a 000 mode is not a refusal"
fi

echo "== a credential-SHAPED value in a _file slot is refused and never rendered =="
# Both halves of that refusal, because they are two different pieces of code. In the STORE the
# mirror refuses exactly as the lib does and says nothing — the lib is loud about it at every
# tool's use site, and a second voice at SessionStart is noise. In a BOARD ENV nothing else
# looks, so this leg refuses it itself and says the source is UNJUDGED rather than passing a
# token-shaped value into a message as if it were a path.
reset_seat
PASTED='ghp_NOTAREALTOKEN000000000000000000000000'
printf '%s\n' "$FAKE" > "$SEAT/.kanban-dev-token"
mk_board dev "$SEAT/.kanban-dev-token"
mk_store "$PASTED"
run_check
eq "pasted secret in the store → rc 0"       "0"     "$RC"
eq "  …its text is NOT rendered"             "false" "$(has "$PASTED" "$OUT")"
eq "  …and no source is invented from it"    "false" "$(has 'DUPLICATE kanban token' "$OUT")"

reset_seat
mk_board dev "$PASTED"
run_check
eq "pasted secret in a board env → rc 0"     "0"     "$RC"
eq "  …its text is NOT rendered"             "false" "$(has "$PASTED" "$OUT")"
eq "  …and that source is named UNJUDGED"    "true"  "$(has 'UNJUDGED' "$OUT")"
eq "  …naming the file that declares it"     "true"  "$(has "$SEAT/.kanban-dev-board.env" "$OUT")"
run_check --quiet
eq "  …and that ⚠ survives --quiet"          "true"  "$(has 'UNJUDGED' "$OUT")"

# ── mirror parity: the three functions runtime-check duplicates from the lib ──────────────────
echo "== mirror parity vs bin/_kb-board-lib.sh =="
for fn in _rc_expand_home _rc_looks_like_pasted_secret _rc_store_pointer _rc_declared_token_file; do
    src="$(sed -n "/^$fn() {/,/^}/p" "$CHECK")"
    [[ -n "$src" ]] || { echo "selftest: could not extract $fn from $CHECK — did it get renamed?" >&2; exit 1; }
    eval "$src"
done
# shellcheck source=/dev/null
source "$LIB"
KB_PROG="token-duplication-selftest"
export HOME="$SEAT"
reset_seat

# The table's SIZE is counted as the rows run and printed below, never typed: a number written
# into a doc or a PR body is a quoted authority that survives the edit that falsifies it — the
# `16 store shapes` this file was once described by was 15 on the day it was written.
n_home=0; n_secret=0; n_store=0; n_boardenv=0

echo "-- _rc_expand_home vs _kb_expand_home --"
for v in '~' '~/tok' '$HOME' '$HOME/tok' '${HOME}' '${HOME}/tok' '/abs/tok' '~user/tok' 'rel/tok' ''; do
    n_home=$((n_home + 1))
    eq "expand_home agrees on [$v]" "$(_kb_expand_home "$v")" "$(_rc_expand_home "$v")"
done

echo "-- _rc_looks_like_pasted_secret vs _kb_looks_like_pasted_secret --"
for v in 'ghp_NOTAREALTOKEN000000000000000000000000' 'GHP_UPPERCASE0000000000000000000000' \
         'glpat-000000000000000000000' 'xoxb-0000000000000000000000000' '~/tok' '/x/tok' \
         'tok.txt' 'REPLACE_ME' 'C:\creds\tok' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'short' ''; do
    n_secret=$((n_secret + 1))
    l=refuse; _kb_looks_like_pasted_secret "$v" && l=accept
    r=refuse; _rc_looks_like_pasted_secret "$v" && r=accept
    eq "pasted-secret shape agrees on [$v]" "$l" "$r"
done

echo "-- _rc_store_pointer vs kb_coord_store_token_file --"
printf 'store-token\n' > "$TMP/store.token"
STORE="$SEAT/.config/coord/credentials.ini"
export COORD_CREDENTIALS="$STORE"
store_case() { # <label> <ini body...>
    local label="$1"; shift
    n_store=$((n_store + 1))
    if [ "$#" -eq 0 ]; then rm -f "$STORE"; else printf '%s\n' "$@" > "$STORE"; fi
    local lo="" lrc=0 ro="" rrc=0
    lo="$(kb_coord_store_token_file 2>/dev/null)" || lrc=$?
    ro="$(_rc_store_pointer 2>/dev/null)" || rrc=$?
    eq "store rung agrees on $label (rc)"     "$lrc" "$rrc"
    eq "store rung agrees on $label (stdout)" "$lo"  "$ro"
    LAST_LIB_OUT="$lo"; LAST_LIB_RC="$lrc"
}
store_case "no store file at all"
store_case "a pointer"                 '[kanban]' "api_token_file = $TMP/store.token"
eq "  control: that pointer really resolves" "$TMP/store.token" "$LAST_LIB_OUT"
store_case "a ~ pointer"               '[kanban]' 'api_token_file = ~/tok'
store_case 'a $HOME pointer'           '[kanban]' 'api_token_file = $HOME/tok'
store_case "a colon delimiter"         '[kanban]' "api_token_file: $TMP/store.token"
store_case "a case-folded key"         '[kanban]' "API_TOKEN_FILE = $TMP/store.token"
store_case "a duplicated key"          '[kanban]' "api_token_file = $TMP/store.token" "api_token_file = $TMP/other.token"
store_case "an inline token"           '[kanban]' 'api_token = ghp_NOTAREALTOKEN0000000000000000'
store_case "inline AND a pointer"      '[kanban]' 'api_token = ghp_NOTAREALTOKEN0000000000000000' "api_token_file = $TMP/store.token"
store_case "a %%-bearing pointer"      '[kanban]' 'api_token_file = /tmp/%%weird/tok'
store_case "a pasted secret"           '[kanban]' 'api_token_file = ghp_NOTAREALTOKEN000000000000000000000000'
store_case "another section only"      '[github]' "api_token_file = $TMP/store.token"
store_case "a commented-out pointer"   '[kanban]' "# api_token_file = $TMP/store.token"
store_case "an empty store"            ''
store_case "no [kanban] section"       "api_token_file = $TMP/store.token"

echo "-- _rc_declared_token_file vs kb_board_env_get --"
printf 'export KB_BOARD_ID=7\nexport KBCARD_TOKEN_FILE="%s"\n' "$TMP/store.token" > "$SEAT/.kanban-p-board.env"
printf 'export KB_BOARD_ID=8\n' > "$SEAT/.kanban-q-board.env"
export KBCARD_TOKEN_FILE="$TMP/ambient.token"   # the inherited value both must refuse to report
for envf in "$SEAT/.kanban-p-board.env" "$SEAT/.kanban-q-board.env" "$SEAT/.kanban-absent-board.env"; do
    n_boardenv=$((n_boardenv + 1))
    lib_v="$(kb_board_env_get "$envf" KBCARD_TOKEN_FILE)"; lib_v="${lib_v%%$'\n'*}"
    mir_v="$(_rc_declared_token_file "$envf" || true)"
    eq "declared-token read agrees on $(basename "$envf")" "$lib_v" "$mir_v"
done
eq "control: the declaring env really declares one" "$TMP/store.token" \
   "$(_rc_declared_token_file "$SEAT/.kanban-p-board.env" || true)"

echo "-- the mirror composes HOST then BOARD, as kb_resolve_env does --"
# A board env may spell its token path against a variable the HOST env sets. `kb_resolve_env`
# sources the host env and THEN the board env into ONE shell, so `$KB_TOKENS/x.token` resolves
# there to a real path; a mirror that sources the board env alone expands it against an EMPTY
# variable and answers a different file — silently, because the bogus path is unreadable, so the
# source is dropped and a seat carrying two copies of one credential reports `ok`.
# Pinned against the RESOLVER, not `kb_board_env_get`: the single-file read cannot express this
# shape at all, which is exactly why the parity block above could not see the divergence.
reset_seat
n_boardenv=$((n_boardenv + 1))
mkdir -p "$SEAT/toks"; printf 'host-composed\n' > "$SEAT/toks/x.token"
printf 'export KB_TOKENS="%s/toks"\nexport KBCARD_API="https://%s/api"\nexport KANBAN_EXPECTED_HOST="%s"\n' \
    "$SEAT" "$HOSTNAME_FIXTURE" "$HOSTNAME_FIXTURE" > "$SEAT/.kanban-host.env"
printf 'export KB_BOARD_ID=9\nexport KBCARD_TOKEN_FILE="$KB_TOKENS/x.token"\n' > "$SEAT/.kanban-h-board.env"
lib_v="$( unset KBCARD_TOKEN_FILE KBCARD_API KANBAN_EXPECTED_HOST KANBAN_HOST_ENV
          kb_resolve_env "$SEAT/.kanban-h-board.env" >/dev/null 2>&1 && printf '%s' "$KB_TOKEN_FILE" )"
mir_v="$(_rc_declared_token_file "$SEAT/.kanban-h-board.env" "$SEAT/.kanban-host.env" || true)"
eq "control: the resolver really composes it" "$SEAT/toks/x.token" "$lib_v"
eq "host-composed token path agrees with the resolver" "$lib_v" "$mir_v"

echo "== the parity table this run actually drove =="
echo "   $n_store store shapes · $n_home home expansions · $n_secret credential shapes · $n_boardenv board-env reads"
# Positive control: every counter above is incremented INSIDE the loop it describes, so a table
# that stopped running would report zeros rather than a stale total.
eq "every parity table carries rows (positive control)" "true" \
   "$([ "$n_store" -gt 0 ] && [ "$n_home" -gt 0 ] && [ "$n_secret" -gt 0 ] && [ "$n_boardenv" -gt 0 ] \
      && echo true || echo false)"

_summary "token-duplication-selftest"
