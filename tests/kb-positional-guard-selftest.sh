#!/usr/bin/env bash
# kb-positional-guard-selftest.sh — deterministic, network-free unit checks for the positional
# argument guard, in BOTH of its copies:
#   1. kb_require_positional    (bin/_kb-board-lib.sh)     — used by adopt-to-dl, board-card-start, kbcard
#   2. _ibh_require_positional  (bin/install-board-hooks)  — the standalone vendored mirror
#
# WHY THIS FILE EXISTS. One rule — refuse an empty positional BY NAME, refuse a second one —
# was hand-rolled in three bins, and the three copies had already drifted textually while
# agreeing behaviourally (card#5343). The hoist unifies them; nothing but this file keeps the
# lib copy and the standalone mirror from drifting apart again, and a comment pairing them is
# what failed the last time (kb-host-guard-selftest.sh:15 records the same lesson).
#
# The mirror hardcodes its `install-board-hooks: ` prefix while the lib copy renders
# `$(_kb_prog)`, so KB_PROG is set to that name below: with the prefixes equalized the two
# copies are compared on the DIAGNOSTIC, not merely on the exit status — unifying the refusal
# text is half of what the consolidation was for.
#
# WEAKEST PROPERTY of the both-copies matrix: it proves the two implementations agree on the
# inputs it feeds, and nothing about an input class absent from it. It is also blind to a call
# site left hand-rolled — a bin that never calls either copy passes it. That is why the second
# section RUNS every bin that owns a positional.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
LIB="$HERE/../bin/_kb-board-lib.sh"
IBH="$HERE/../bin/install-board-hooks"
ATD="$HERE/../bin/adopt-to-dl"
BCS="$HERE/../bin/board-card-start"
_need -r "$LIB"
_need -x "$IBH"
_need -x "$ATD"
_need -x "$BCS"

# shellcheck source=/dev/null
source "$LIB"

# install-board-hooks runs its main at top level under a sourced-guard and must stay
# standalone, so lift just the mirror out of it and rename — the extract-and-exercise pattern
# kb-host-guard-selftest.sh uses on the promote-released-cards mirror. This keeps the vendored
# copy honest rather than trusting the "keep the two in sync" comment. The extraction requires
# the mirror to be defined at COLUMN 0 (it would be indented inside _ibh_main).
ibh_src="$(sed -n '/^_ibh_require_positional() {/,/^}/p' "$IBH")"
[[ -n "$ibh_src" ]] || { echo "selftest: could not extract _ibh_require_positional from $IBH — was it renamed, or moved inside another function?" >&2; exit 1; }
eval "${ibh_src/_ibh_require_positional() \{/_ibh_mir() \{}"

# The equalization pair: the mirror hardcodes this prefix, the lib copy reads it from KB_PROG.
KB_PROG="install-board-hooks"

# check <want-rc> <want-diagnostic> <slot> <arg> <name> [suffix]
check() {
    local want_rc="$1" want_msg="$2"; shift 2
    local label="$3 slot='$1' arg='$2'${4+ suffix='$4'}"
    local lrc=0 mrc=0 lmsg mmsg
    lmsg="$(kb_require_positional "$@" 2>&1 >/dev/null)" || lrc=$?
    mmsg="$(_ibh_mir             "$@" 2>&1 >/dev/null)" || mrc=$?
    if [[ "$lrc" != "$want_rc" ]]; then
        bad "$label — kb_require_positional rc=$lrc, want rc=$want_rc"
    elif [[ "$lmsg" != "$want_msg" ]]; then
        bad "$label — kb_require_positional said '$lmsg', want '$want_msg'"
    elif [[ "$mrc" != "$lrc" || "$mmsg" != "$lmsg" ]]; then
        bad "$label — the two copies DISAGREE: lib=(rc=$lrc '$lmsg') mirror=(rc=$mrc '$mmsg')"
    else
        ok "$label (rc=$want_rc, both copies)"
    fi
}

echo "== a first, non-empty positional is ACCEPTED (no over-refusal) =="
check 0 "" ""  "./repo"     "<repo-dir>"
check 0 "" ""  "0"          "<card-id>"            # a falsy-looking but real value
check 0 "" ""  " "          "<repo-dir>"           # whitespace-only is NOT empty, at every site
check 0 "" ""  "--not-a-flag" "<repo-dir>"         # the arm dispatches; the guard never re-parses

echo "== an EMPTY positional is refused BY NAME =="
check 1 "install-board-hooks: <repo-dir> is empty (an unexpanded variable?)"   "" "" "<repo-dir>"
check 1 "install-board-hooks: <card-id> is empty (an unexpanded variable?)"    "" "" "<card-id>"

echo "== a SECOND positional is refused, quoting the offending argument =="
check 1 "install-board-hooks: unexpected extra argument: second" "first" "second" "<repo-dir>"
check 1 "install-board-hooks: unexpected extra argument: -x"     "first" "-x"     "<repo-dir>"

echo "== the [suffix] rides every diagnostic (board-card-start's standing qualifier) =="
check 1 "install-board-hooks: <branch-name> is empty (an unexpanded variable?) — no card moved" \
    "" "" "<branch-name>" " — no card moved"
check 1 "install-board-hooks: unexpected extra argument: b — no card moved" \
    "a" "b" "<branch-name>" " — no card moved"

echo "== slot FULL and arg EMPTY: the empty message wins (pre-hoist behaviour at all 3 sites) =="
check 1 "install-board-hooks: <repo-dir> is empty (an unexpanded variable?)" "first" "" "<repo-dir>"

echo "== the refusal is on stderr, and stdout stays clean =="
out="$(kb_require_positional "" "" "<card-id>" 2>/dev/null || true)"
eq "kb_require_positional prints nothing on stdout" "" "$out"
out="$(_ibh_mir "" "" "<card-id>" 2>/dev/null || true)"
eq "the mirror prints nothing on stdout" "" "$out"

# ---------------------------------------------------------------------------------------
# CALL-SITE PINS. The matrix above cannot see a bin left hand-rolled, so run all four. The
# first three refuse inside their argument loop, before any config read, API call or git
# invocation; kbcard refuses after its config load and carries its own fixture (see below).
# All are network-free; the scratch HOME keeps a real ~/.kanban-* file out of the result.
_mktmp_scratch --home

# pin <label> <want-rc> <want-first-stderr-line> <bin> <args...>
pin() {
    local label="$1" want_rc="$2" want_msg="$3"; shift 3
    local rc=0 err first
    err="$("$@" 2>&1 >/dev/null)" || rc=$?
    first="${err%%$'\n'*}"
    if [[ "$rc" != "$want_rc" ]]; then
        bad "$label — rc=$rc, want rc=$want_rc   [stderr: $first]"
    elif [[ "$first" != "$want_msg" ]]; then
        bad "$label — said '$first', want '$want_msg'"
    else
        ok "$label (rc=$rc)"
    fi
}

echo "== install-board-hooks — an ordinary CLI: refuses at rc 2 =="
pin "install-board-hooks ''"  2 "install-board-hooks: <repo-dir> is empty (an unexpanded variable?)" "$IBH" ""
pin "install-board-hooks a b" 2 "install-board-hooks: unexpected extra argument: b"                  "$IBH" a b

echo "== adopt-to-dl — an ordinary CLI: refuses at rc 2 =="
pin "adopt-to-dl ''"  2 "adopt-to-dl: <card-id> is empty (an unexpanded variable?)" "$ATD" ""
pin "adopt-to-dl 1 2" 2 "adopt-to-dl: unexpected extra argument: 2"                 "$ATD" 1 2

echo "== board-card-start — fail-soft by contract: refuses LOUD at rc 0, never blocking a checkout =="
pin "board-card-start ''"  0 "board-card-start: <branch-name> is empty (an unexpanded variable?) — no card moved" "$BCS" ""
pin "board-card-start a b" 0 "board-card-start: unexpected extra argument: b — no card moved"                     "$BCS" a b

# kbcard is the fourth call site (card#5276) and the one exception to "refuses before any config
# read": its verb dispatch sits after kb_load_config, so a scratch HOME alone would make every
# arm below report the board-env error instead of the thing under test. The fixture is therefore
# a MINIMAL WORKING config — nothing is faked about the guard itself, and the unknown-command arm
# is the witness that config really resolved (a broken fixture says "board env file not readable"
# there and reds). Still network-free: every arm exits inside main's dispatch, before any request.
unset KBCARD_BOARD_ENV KBCARD_API KBCARD_TOKEN_FILE
KBC="$HERE/../bin/kbcard"
_need -x "$KBC"
: > "$TMP/board.token"
{ echo "export KBCARD_API=\"https://kbcard-guard.invalid/api/v3\""
  echo "export KBCARD_TOKEN_FILE=\"$TMP/board.token\""; } > "$HOME/.kanban-host.env"
echo 'KB_BOARD_ID=42' > "$HOME/.kanban-dev-board.env"

echo "== kbcard — an ordinary CLI: refuses at rc 2 =="
pin "kbcard ''"                 2 "kbcard: <command> is empty (an unexpanded variable?)" "$KBC" ""
pin "kbcard --board dev ''"     2 "kbcard: <command> is empty (an unexpanded variable?)" "$KBC" --board dev ""
# The GLOBAL --board's own empty-value guard, driven here because this is the only file that
# runs kbcard as a PROCESS with a resolvable config — and it was the one guarded flag in the
# toolkit that nothing drove (card#6645, found by deriving kbcard's guarded set instead of
# reading the list of flags the tests happened to name). The bin's own header calls it the
# highest-stakes instance of the class: an empty --board falls through to the DEFAULT board, so
# `--board "$KEY"` with KEY unset is a wrong-board WRITE, not a no-op.
pin "kbcard --board '' list"    2 "kbcard: --board requires a non-empty value" "$KBC" --board "" list
# The discrimination the guard exists to make: NO arguments is a help request and stays rc 0 on
# stdout, while an EMPTY first argument is a failed expansion and is refused. Asserting only the
# refusal would pass just as well for a kbcard that refused its own help.
pin "kbcard <no args> is still help, not a refusal" 0 "" "$KBC"
eq "kbcard <no args> prints the usage block on STDOUT" "true" "$(has 'Usage:' "$("$KBC" 2>/dev/null)")"
pin "kbcard nope — witness that the fixture config resolved" 2 "kbcard: unknown command 'nope'" "$KBC" nope

_summary "kb-positional-guard-selftest"
