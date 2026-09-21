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
# card#9845: before that change, "rename it" was the WHOLE fix — every wired repo fired the
# hook, so a compliant rename always correlated AND moved. Since the hook is opt-in, a rename
# in an unarmed repo still moves nothing, so the advisory must not imply otherwise. This leg
# reds against the PRE-FIX wording of this same line (the string this file's own git history
# carries before this commit) — NOT against origin/dev's hook, since the defect is in this
# advisory's TEXT, introduced by card#9845's change, not in the old hook's behavior:
#   git show <pre-fix HEAD>:bin/board-card-start | grep -c 'ARMED for checkout auto-move'  # 0
_lint_arm_warn="$(_bcs_branch_lint_warning "fix/card_4524-x")"
grep -q "ARMED for checkout auto-move" <<< "$_lint_arm_warn" \
    && ok "malformed-spelling advisory also names arming as a separate precondition" \
    || bad "malformed-spelling advisory does not mention arming: $_lint_arm_warn"
grep -q "kanban.automove-on-checkout" <<< "$_lint_arm_warn" \
    && ok "…and gives the exact config key to check" \
    || bad "malformed-spelling advisory omits the config key: $_lint_arm_warn"

echo "== board-card-start --lint — the wiring the pre-push hook invokes (subprocess, network-free) =="
# --lint moves nothing and issues no request; exercises the real arg path + exit code. The
# malformed spelling carries no ACCEPTED card id, so the board-verdict leg has nothing to judge
# and this run is independent of the host's config and of any recorded verdict. A compliant id is
# judged by that leg, whose lines are asserted in the fixtures below.
_lrc=0; _lout="$(bash "$BCS" --lint "fix/card_4524-x" 2>&1)" || _lrc=$?
[[ "$_lrc" -eq 0 ]] && ok "--lint exits 0 (fail-soft)" || bad "--lint expected rc=0 got $_lrc"
grep -q "board-branch-lint:.*card 4524" <<< "$_lout" && ok "--lint warns on the residual spelling" || bad "--lint did not warn: $_lout"

echo "== _bcs_card_id — the id the mover, the verdict record and the lint judge (explicit first, else typed) =="
expect_out "explicit card-N"                        "4524" _bcs_card_id "fix/card-4524-x"
expect_out "typed leading id"                       "712"  _bcs_card_id "fix/712-foo"
expect_out "explicit beats a typed leading id"      "4524" _bcs_card_id "fix/712/card-4524"
expect_out "a DL-only branch carries no card id"    ""     _bcs_card_id "feature/dl212-event-gated"
expect_out "a malformed spelling carries no card id" ""    _bcs_card_id "fix/card_4524-x"

echo "== _bcs_uint_lt — a digit-string compare that cannot wrap (the verdict leg's staleness compare) =="
expect_rc "712 < 1000"                                  0 _bcs_uint_lt 712 1000
expect_rc "1234 < 1235 (boundary, same length)"         0 _bcs_uint_lt 1234 1235
expect_rc "999 < 1000 (fewer digits)"                   0 _bcs_uint_lt 999 1000
expect_rc "1000 is NOT < 1000 (equal)"                 1 _bcs_uint_lt 1000 1000
expect_rc "4524 is NOT < 1000"                          1 _bcs_uint_lt 4524 1000
expect_rc "10000 is NOT < 9999 (length decides first)"  1 _bcs_uint_lt 10000 9999
# 2^64 + 1: `[ … -lt … ]` errors on it (rc 2) and `(( … ))` wraps it to 1 — an arithmetic compare
# answers neither case.
expect_rc "a 20-digit value is NOT below a 4-digit one"  1 _bcs_uint_lt 18446744073709551617 1000
expect_rc "a 4-digit value IS below a 20-digit one"      0 _bcs_uint_lt 1000 18446744073709551617

echo "== the board verdict record — writer, reader, staleness (DL-225) =="
# _ctl <string>: "true" when <string> holds a control character — C0 or DEL (`[[:cntrl:]]` under the C
# locale) or the UTF-8 spelling of a C1 control (bytes C2 80..C2 9F).
_ctl() {
    local LC_ALL=C
    [[ "${1-}" == *[[:cntrl:]]* || "${1-}" == *$'\xc2'[$'\x80'-$'\x9f']* ]] && echo true || echo false
}
# The pure halves, sourced: the record the mover writes (_bcs_verdict_write) and the lint leg that
# reads it (_bcs_board_verdict_warning). Every loud case is paired with a silent or undecided
# witness that differs from it in ONE input, so no line here can pass by never firing.
if command -v git >/dev/null 2>&1; then
    _vt="$(mktemp -d)"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    git init -q "$_vt/repo"
    ( cd "$_vt/repo" && echo a > a && git add a && git commit -qm a )
    git -C "$_vt/repo" worktree add -q -b side "$_vt/wt"
    _vrec() { ( cd "$_vt/repo" && _bcs_verdict_write "$@" ); }   # <branch> <verdict> <dl> <board> <subject> <reason>
    _vwarn() {  # <branch> <board-now> [<created-at>] — sets _vrc/_vout
        _vrc=0
        _vout="$(cd "$_vt/repo" && _bcs_board_verdict_warning "$1" "$(_bcs_verdict_file "$1")" "$2" "${3:-}")" || _vrc=$?
    }
    _vfile() { (cd "$_vt/repo" && _bcs_verdict_file "$1"); }
    _vfield() { sed -n "s/^$2=//p" "$(_vfile "$1")"; }            # <branch> <key>

    # WRITER — the location, and that it is shared by a linked worktree.
    _vrec fix/card-712-x absent "" 42 "" "card #712: HTTP 404"; _wrc=$?
    eq "write: rc 0" "0" "$_wrc"
    _vf="$(_vfile fix/card-712-x)"
    eq "write: the record sits under the COMMON git dir, keyed by the branch name's blob hash" \
       "$(cd "$_vt/repo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/agent-board-toolkit/board-verdict/$(printf '%s' fix/card-712-x | git hash-object --stdin)" "$_vf"
    eq "write: the record exists" "true" "$([[ -s "$_vf" ]] && echo true || echo false)"
    eq "write: a linked worktree resolves the SAME file" \
       "$(readlink -f "$_vf")" "$(readlink -f "$(cd "$_vt/wt" && _bcs_verdict_file fix/card-712-x)")"
    eq "write: git status sees nothing — the record can never be committed" "" "$(git -C "$_vt/repo" status --porcelain --ignored)"
    eq "write: header, branch, the card id the name yields, board, verdict" \
       "abtk-board-verdict 1|fix/card-712-x|712|42|absent" \
       "$(head -1 "$_vf")|$(_vfield fix/card-712-x branch)|$(_vfield fix/card-712-x card)|$(_vfield fix/card-712-x board)|$(_vfield fix/card-712-x verdict)"
    eq "write: no temp file is left beside it" "" "$(find "${_vf%/*}" -name '.tmp.*')"
    _vrec fix/card-713-x not_checked "" 42 "" $'line one\nline two'
    eq "write: a line break in the reason is flattened — one key per line survives" "line one line two" "$(_vfield fix/card-713-x reason)"
    # EVERY value handed to the writer is scrubbed, not only the reason: a board id read straight out of
    # an API body carried ESC/BEL into the record, and from there to the terminal.
    _cb=$'fix/card-716-x\e[31m'
    _vrec "$_cb" not_checked $'8\a9' $'4\e[31m2' $'71\x7f6' $'r\e[31mRED\a\xc2\x9bX\ty'
    eq "write: no control character in any field (C0, DEL, UTF-8 C1)" "false" "$(_ctl "$(tr -d '\n' < "$(_vfile "$_cb")")")"
    eq "write: what is left of each field survives" "fix/card-716-x[31m|89|4[31m2|716|r[31mREDXy" \
       "$(_vfield "$_cb" branch)|$(_vfield "$_cb" dl)|$(_vfield "$_cb" board)|$(_vfield "$_cb" subject)|$(_vfield "$_cb" reason)"
    _cb=$'fix/card-717-n\nverdict=resolved'
    _vrec "$_cb" absent "" 42 "" r
    eq "write: a line break in the BRANCH cannot forge a second verdict line" "1|absent" \
       "$(grep -c '^verdict=' "$(_vfile "$_cb")")|$(_vfield "$_cb" verdict)"
    # A write that cannot land returns non-zero and leaves nothing: the record dir's parent is a FILE.
    git init -q "$_vt/blocked"; : > "$_vt/blocked/.git/agent-board-toolkit"
    _brc=0; ( cd "$_vt/blocked" && _bcs_verdict_write fix/card-712-x absent "" 42 "" r ) || _brc=$?
    eq "write failure: rc 1" "1" "$_brc"
    eq "write failure: nothing written" "false" "$([[ -e "$_vt/blocked/.git/agent-board-toolkit/board-verdict" ]] && echo true || echo false)"
    # A REWRITE that fails at the rename: the older checkout's record must not stand in for this one.
    _vrec fix/card-715-x resolved "" 42 715 "card #715 (#715)"
    eq "failed rewrite: the witness record exists first" "resolved" "$(_vfield fix/card-715-x verdict)"
    _brc=0; ( cd "$_vt/repo" && mv() { return 1; } && _bcs_verdict_write fix/card-715-x absent "" 42 "" "card #715: HTTP 404" ) || _brc=$?
    eq "failed rewrite: rc 1, the previous record is gone, no temp file left" "1|false|" \
       "$_brc|$([[ -e "$(_vfile fix/card-715-x)" ]] && echo true || echo false)|$(find "${_vf%/*}" -name '.tmp.*')"

    # READER — a recorded ABSENCE is repeated loudly and DECIDES the branch.
    _vwarn fix/card-712-x 42
    eq "absent: rc 0 (decided)" "0" "$_vrc"
    eq "absent: names the card and the board"    "true" "$(has "branch 'fix/card-712-x' names card 712, which is NOT a card on board 42" "$_vout")"
    eq "absent: carries what the board said"     "true" "$(has "card #712: HTTP 404" "$_vout")"
    eq "absent: names BOTH id spaces"            "true" "$(has "card ids and GitHub issue/PR numbers are separate id spaces" "$_vout")"
    eq "absent: teaches the branch-cut rule"     "true" "$(has "cut the branch from the CARD id" "$_vout")"
    # …and a RESOLVED record — same branch, same board, one field different — is silent.
    _vrec fix/card-712-x resolved "" 42 712 "card #712 (#712)"
    _vwarn fix/card-712-x 42
    eq "resolved: rc 0 (decided)" "0" "$_vrc"
    eq "resolved: silent — and the rewrite replaced the absent verdict (latest checkout wins)" "" "$_vout"
    # NO record: speaks, by name, and leaves the branch undecided.
    _vwarn fix/card-714-x 42
    eq "no record: rc 1 (undecided)" "1" "$_vrc"
    eq "no record: names the branch and card" "true" "$(has "board verdict NOT RECORDED for branch 'fix/card-714-x' (card 714)" "$_vout")"
    eq "no record: says how to record one"    "true" "$(has "check the branch out again" "$_vout")"
    # NOT CHECKED: speaks with the recorded reason, undecided.
    _vwarn fix/card-713-x 42
    eq "not checked: rc 1 (undecided)" "1" "$_vrc"
    eq "not checked: names the reason it was not checked" "true" "$(has "board verdict NOT CHECKED for branch 'fix/card-713-x' (card 713)" "$_vout")"
    eq "not checked: …carrying the recorded reason"      "true" "$(has "line one line two" "$_vout")"
    eq "not checked, no remedy recorded: names the re-checkout (witness)" "true" \
       "$(has "; once that is fixed, check the branch out again ('git checkout fix/card-713-x')" "$_vout")"
    # A verdict a re-checkout would only re-record carries its own remedy, printed in place of that advice.
    _vrec fix/card-731-x not_checked 89 42 "" "the reason" "rename the branch, the remedy"
    _vwarn fix/card-731-x 42
    eq "not checked with a recorded remedy: rc 1, the remedy replaces the re-checkout advice" "1|true|false" \
       "$_vrc|$(has "— the reason; rename the branch, the remedy." "$_vout")|$(has "check the branch out again" "$_vout")"
    # A branch with no card id is silent and decided, record or none.
    _vwarn docs/adoption-guide ""
    eq "no card id: rc 0, silent, no record needed" "0|" "$_vrc|$_vout"
    _vwarn feature/dl212-event-gated 42
    eq "DL-only branch: rc 0, silent" "0|" "$_vrc|$_vout"
    # A record written by an older writer, or by hand, is scrubbed again when the lint PRINTS it.
    _vrec fix/card-718-x absent "" 42 "" "card #718: HTTP 404"
    printf '%s\n' "$_BCS_VERDICT_HEADER" branch=fix/card-718-x card=718 dl= board=42 verdict=absent subject= \
        $'reason=card #718\e[31m RED\a\xc2\x9b' recorded_at=1 $'recorded_utc=2026\e[2J' > "$(_vfile fix/card-718-x)"
    _vwarn fix/card-718-x 42
    eq "hand-edited absent record: still repeated (rc 0), with no control character printed" "0|true|false" \
       "$_vrc|$(has "which is NOT a card on board 42" "$_vout")|$(_ctl "$_vout")"
    sed -i 's/^verdict=absent$/verdict=not_checked/' "$(_vfile fix/card-718-x)"
    _vwarn fix/card-718-x 42
    eq "hand-edited not_checked record: NOT CHECKED, with no control character printed" "1|true|false" \
       "$_vrc|$(has "board verdict NOT CHECKED for branch 'fix/card-718-x'" "$_vout")|$(_ctl "$_vout")"
    sed -i $'s/^board=42$/board=4\x1b[2J2/' "$(_vfile fix/card-718-x)"
    _vwarn fix/card-718-x 42
    eq "hand-edited board: STALE, with no control character printed" "1|true|false" \
       "$_vrc|$(has "is STALE" "$_vout")|$(_ctl "$_vout")"

    # STALENESS — each against the resolved fix/card-712-x record, which the witness above showed silent.
    _vwarn fix/card-712-x 43
    eq "re-mapped board: rc 1" "1" "$_vrc"
    eq "re-mapped board: STALE, naming both boards" "true" \
       "$(has "is STALE — it was recorded against board 42, but this repo now maps to board 43" "$_vout")"
    _vwarn fix/card-712-x ""
    eq "now unmapped: STALE, naming 'no board'" "true" "$(has "but this repo now maps to no board" "$_vout")"
    # A record naming NO board (its checkout stopped before resolving one: curl or jq not on PATH) is not
    # stale against the board the repo maps to: its own reason is the finding.
    _vrec fix/card-732-x not_checked "" "" "" "curl and jq are both required but not both on PATH"
    _vwarn fix/card-732-x 42
    eq "record naming no board, repo mapped: NOT CHECKED with its own reason, not STALE" "1|true|true|false" \
       "$_vrc|$(has "board verdict NOT CHECKED for branch 'fix/card-732-x' (card 732)" "$_vout")|$(has "curl and jq are both required" "$_vout")|$(has "STALE" "$_vout")"
    _at="$(_vfield fix/card-712-x recorded_at)"
    _vwarn fix/card-712-x 42 "$((_at + 1))"
    eq "branch created AFTER the record (deleted and re-created without a checkout): rc 1" "1" "$_vrc"
    eq "…STALE, saying so" "true" "$(has "before a branch of this name was created" "$_vout")"
    _vwarn fix/card-712-x 42 "$_at"
    eq "branch created in the SAME second as the record (a switch -c): current, silent" "0|" "$_vrc|$_vout"
    _vwarn fix/card-712-x 42 "not-a-time"
    eq "an unreadable creation time is not compared: current, silent" "0|" "$_vrc|$_vout"
    # What the reflog rule CANNOT see (docs/HOOKS.md § How staleness shows): a re-creation whose last
    # reflog entry is not `branch: Created from` yields no creation time, so a record older than it
    # is read as current. `git branch` is the control that does yield one.
    _cat() { (cd "$_vt/repo" && _bcs_branch_created_at fix/card-719-a); }
    git -C "$_vt/repo" branch fix/card-719-a
    eq "created by git branch: a creation time, so STALE can fire (control)" "true" "$(kb_is_uint "$(_cat)" && echo true || echo false)"
    git -C "$_vt/repo" branch -q -D fix/card-719-a; git -C "$_vt/repo" update-ref refs/heads/fix/card-719-a HEAD
    eq "re-created by git update-ref: no creation time — NOT detected" "" "$(_cat)"
    git -C "$_vt/repo" branch -q -D fix/card-719-a; git -C "$_vt/repo" fetch -q . HEAD:refs/heads/fix/card-719-a
    eq "re-created by git fetch: no creation time — NOT detected" "" "$(_cat)"
    git -C "$_vt/repo" branch -q -D fix/card-719-a; git -C "$_vt/repo" -c core.logAllRefUpdates=false branch fix/card-719-a
    eq "re-created with reflogs off: no creation time — NOT detected" "" "$(_cat)"
    unset -f _cat
    sed -i 's/^card=712$/card=999/' "$(_vfile fix/card-712-x)"
    _vwarn fix/card-712-x 42
    eq "a record for another card id (a different grammar wrote it): STALE" "1|true" \
       "$_vrc|$(has "it was recorded for card 999, but this branch name yields card 712" "$_vout")"

    # UNREADABLE — a torn or foreign file never reads as a verdict.
    printf 'garbage\n' > "$(_vfile fix/card-712-x)"
    _vwarn fix/card-712-x 42
    eq "garbage record: rc 1, UNREADABLE" "1|true" "$_vrc|$(has "is UNREADABLE" "$_vout")"
    cp "$(_vfile fix/card-713-x)" "$(_vfile fix/card-712-x)"
    _vwarn fix/card-712-x 42
    eq "another branch's record at this path: UNREADABLE, never borrowed" "1|true" "$_vrc|$(has "is UNREADABLE" "$_vout")"

    unset -f _vrec _vwarn _vfile _vfield
    rm -rf "$_vt"
else
    echo "  skip (git not on PATH)"
fi

echo "== board-card-start --lint — the board verdict leg, end to end (subprocess, fixture HOME + repo) =="
# The real argument path and the real config resolution (git config, else .release-pr.json → the
# board the verdict record is judged against), in a scratch HOME so no operator board env is read.
# Network-free by construction: no host env and emptied ambient KBCARD_*, so nothing here could name
# a host. The board env carries KB_CARD_ID_FLOOR, the key of the card-id floor leg DL-225 superseded
# (card#9570): whatever it holds, no line mentions a floor — and each absence below is paired with
# the verdict line that must still print on the same run.
if command -v git >/dev/null 2>&1; then
    _ft="$(mktemp -d)"
    _frepo="$_ft/repo"; _fhome="$_ft/home"; mkdir -p "$_fhome"
    git init -q "$_frepo"
    _flint() {  # <branch> — lint it from inside the fixture repo; sets _frc/_fout
        _frc=0
        _fout="$(cd "$_frepo" && HOME="$_fhome" KBCARD_API='' KBCARD_TOKEN_FILE='' KB_BCS_LOG="$_ft/bcs.log" \
                 bash "$BCS" --lint -- "$1" 2>&1)" || _frc=$?
    }
    _flines() { printf '%s\n' "$_fout" | wc -l | tr -d ' '; }
    _fnr="board-branch-lint: board verdict NOT RECORDED for branch 'fix/card-712-foo' (card 712)"
    # 1. No board mapping at all, never checked out: NOT RECORDED, and nothing else.
    _flint "fix/card-712-foo"
    eq "unmapped repo: rc 0, ONE line, NOT RECORDED, no floor text" "0|1|true|false" \
       "$_frc|$(_flines)|$(has "$_fnr" "$_fout")|$(has "floor" "$_fout")"
    # 2. Mapped, a board env without the key, then one still seeding a floor the id is BELOW.
    git -C "$_frepo" config kanban.board-id 42
    printf 'export KB_BOARD_ID=42\n' > "$_fhome/.kanban-t-board.env"
    _flint "fix/card-712-foo"; _funseeded="$_fout"
    eq "board env without KB_CARD_ID_FLOOR: ONE NOT RECORDED line, no floor text" "1|true|false" \
       "$(_flines)|$(has "$_fnr" "$_fout")|$(has "floor" "$_fout")"
    printf 'export KB_BOARD_ID=42\nexport KB_CARD_ID_FLOOR=1000\n' > "$_fhome/.kanban-t-board.env"
    _flint "fix/card-712-foo"
    eq "KB_CARD_ID_FLOOR=1000 left in the board env, card 712 below it: rc 0, ONE line, NOT RECORDED, no floor text" "0|1|true|false" \
       "$_frc|$(_flines)|$(has "$_fnr" "$_fout")|$(has "floor" "$_fout")"
    eq "…and that line is byte-identical to the one without the key: the key changes nothing" "$_funseeded" "$_fout"
    [[ -s "$_ft/bcs.log" ]] \
        && bad "lint: --lint wrote the mover's durable log: $(cat "$_ft/bcs.log")" \
        || ok "lint: no move attempted (durable log untouched)"
    # 3. PRESENCE witness on the same branch and env: an `absent` record is repeated with the id-space rule.
    ( cd "$_frepo" && _bcs_verdict_write fix/card-712-foo absent "" 42 "" "card #712: HTTP 404" ) \
        || bad "fixture: could not write the absent record"
    _flint "fix/card-712-foo"
    eq "absent record, KB_CARD_ID_FLOOR still in the env: rc 0, ONE line, the board's answer + the id-space rule, no floor text" "0|1|true|true|false" \
       "$_frc|$(_flines)|$(has "board-branch-lint: branch 'fix/card-712-foo' names card 712, which is NOT a card on board 42" "$_fout")|$(has "card ids and GitHub issue/PR numbers are separate id spaces" "$_fout")|$(has "floor" "$_fout")"
    # 4. The committed board id is the board the record is judged against when no git config names one.
    git -C "$_frepo" config --unset kanban.board-id
    printf '{"promote":{"board_id":42}}\n' > "$_frepo/.release-pr.json"
    _flint "fix/card-712-foo"
    if command -v jq >/dev/null 2>&1; then
        eq "committed .promote.board_id 42: the board-42 record is current, not STALE" "true|false" \
           "$(has "which is NOT a card on board 42" "$_fout")|$(has "STALE" "$_fout")"
        # A committed value that is not a plain integer maps to no board, so the board-42 record is stale.
        for _bj in '"42abc"' '-42' '42.0' '["42"]'; do
            printf '{"promote":{"board_id":%s}}\n' "$_bj" > "$_frepo/.release-pr.json"
            _flint "fix/card-712-foo"
            eq "committed board_id $_bj: maps to no board, so the record is STALE, one line" "1|true" \
               "$(_flines)|$(has "is STALE — it was recorded against board 42, but this repo now maps to no board" "$_fout")"
        done
    fi
    # 5. The lint sources NO board env, for any branch — the floor leg was its only reader. The control
    # sources that same env through the lib's own resolver, so the marker is proven able to fire.
    rm -f "$_frepo/.release-pr.json"
    git -C "$_frepo" config kanban.board-id 42
    printf 'touch %q\nexport KB_BOARD_ID=42\nexport KB_CARD_ID_FLOOR=1000\n' "$_ft/sourced" > "$_fhome/.kanban-t-board.env"
    for _nb in "docs/adoption-guide" "feature/dl212-event-gated" "fix/card-712-foo" "fix/card-4244-x"; do
        rm -f "$_ft/sourced"; _flint "$_nb"
        [[ ! -e "$_ft/sourced" ]] && ok "lint ($_nb): no board env sourced" \
            || bad "lint ($_nb): --lint sourced a board env"
    done
    _flint "docs/adoption-guide"
    [[ -z "$_fout" ]] && ok "no card id (docs/adoption-guide): silent" || bad "no card id: spoke: $_fout"
    rm -f "$_ft/sourced"; ( export HOME="$_fhome"; kb_board_env_for 42 >/dev/null )
    [[ -e "$_ft/sourced" ]] && ok "control: kb_board_env_for 42 DOES source that env, so the marker can fire" \
        || bad "control: the board env was never sourced — the marker probe cannot fire"
    unset -f _flint _flines
    rm -rf "$_ft"
fi

echo "== board-card-start argument surface — flag position, empty positional, HEAD default (card#5333) =="
# Exercises the REAL argument path in a subprocess, network-free: a fixture repo whose branch
# CORRELATES (card-4242), a scratch HOME (so no ~/.kanban-* token/host file is readable) and no
# board id anywhere, so a run that reaches board work fail-softs at the FIRST board gate — loudly,
# naming the branch it resolved, and appending the same line to the durable log. That pair is the
# observable for "a move was attempted"; its ABSENCE is the observable for "the refusal held".
# Every case asserts rc 0 as well: a refusal here is a no-move, NEVER a non-zero exit (this runs
# from post-checkout, which must never block a checkout — docs/HOOKS.md).
if command -v git >/dev/null 2>&1; then
    _t="$(mktemp -d)"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    _repo="$_t/repo"; _home="$_t/home"; _log="$_t/bcs.log"; mkdir -p "$_home"
    git init -q "$_repo"
    ( cd "$_repo" && echo a > a && git add a && git commit -qm a && git checkout -q -b fix/card-4242-x )
    _bcs_run() {  # <args…> — run the bin in the fixture; sets _rc/_out, with a fresh durable log
        # The scratch HOME + emptied ambient KBCARD_* are what keep this network-free no matter
        # whose shell runs it: the bin reads an ambient KBCARD_API/KBCARD_TOKEN_FILE ahead of the
        # host env, so leaving a real one in scope is the one way a fixture run could go live.
        #
        # `"$@"` is expanded with ZERO arguments for the zero-args case below, and that is
        # deliberate rather than overlooked: it is the shape the shipped bins already run on their
        # own production path — `bin/kbcard` and `bin/adopt-to-dl` both end in `main "$@"` under
        # the STRICTER `set -euo pipefail`, and both are routinely invoked bare. (This bin's parser
        # reads `$#`/`$1` because it consumes arguments one at a time, not to avoid `"$@"`.)
        # Measured on the reference host, bash 5.2.21: a zero-arg `"$@"` under `set -euo pipefail`
        # expands to zero words and does not trip `set -u`. That measurement is scoped to that
        # shell — but the exposure is not this test's alone, so a shell where the shape did fail
        # would take those two tools' bare invocation down before it reached here.
        rm -f "$_log"; _rc=0
        _out="$(cd "$_repo" && HOME="$_home" KBCARD_API='' KBCARD_TOKEN_FILE='' KB_BCS_LOG="$_log" \
                bash "$BCS" "$@" 2>&1)" || _rc=$?
    }
    _bcs_attempted_move() {   # did the run get past argument handling into board work?
        # The mover's own sentence, not the branch name: --lint's board-verdict leg names the
        # branch too, and its line is a lint finding, not a move attempt.
        [[ -s "$_log" ]] || grep -q "carries a DL/card token but the move did not happen" <<< "$_out"
    }

    # ZERO ARGS → the current branch. hooks/post-checkout passes NO arguments at all, so this is
    # the production path and the empty-positional refusal must not touch it. It is also the
    # POSITIVE CONTROL for _bcs_attempted_move: without it, a probe that can never fire would
    # make every "no move" assertion below pass vacuously.
    _bcs_run
    [[ "$_rc" -eq 0 ]] && ok "no args: exits 0" || bad "no args: expected rc=0 got $_rc"
    _bcs_attempted_move \
        && ok "no args: defaults to the CURRENT branch, and board work IS detectable (control)" \
        || bad "no args: did not resolve HEAD's branch: $_out"

    # AN EXPLICITLY-EMPTY BRANCH → refuse. It must NOT silently become the HEAD default — that
    # moves a card the caller never named (an unexpanded "$BRANCH" is the way in).
    _bcs_run ""
    [[ "$_rc" -eq 0 ]] && ok "empty branch: exits 0 (fail-soft)" || bad "empty branch: expected rc=0 got $_rc"
    grep -q "is empty" <<< "$_out" \
        && ok "empty branch: refuses loudly" || bad "empty branch: no refusal on stderr: $_out"
    _bcs_attempted_move \
        && bad "empty branch: fell through to HEAD and attempted a move: $_out" \
        || ok "empty branch: NO board work attempted"

    # TRAILING --lint → lint only. The fixture branch correlates, so a dropped flag shows up as
    # real board work; an rc-0-only assertion would pass with the flag silently ignored.
    _bcs_run "fix/card-4242-x" --lint
    [[ "$_rc" -eq 0 ]] && ok "<branch> --lint: exits 0" || bad "<branch> --lint: expected rc=0 got $_rc"
    _bcs_attempted_move \
        && bad "<branch> --lint: flag dropped — a REAL move was attempted: $_out" \
        || ok "<branch> --lint: no move attempted"
    # …and it is lint MODE, not merely an early exit: a warn-worthy branch must still warn.
    _bcs_run "fix/card_4524-x" --lint
    grep -q "board-branch-lint:.*card 4524" <<< "$_out" \
        && ok "<branch> --lint: actually lints (the warning is emitted)" || bad "<branch> --lint: no lint warning: $_out"

    # LEADING --lint — hooks/pre-push's call form — keeps working: lint only, no move.
    _bcs_run --lint "fix/card-4242-x"
    [[ "$_rc" -eq 0 ]] && ok "--lint <branch>: exits 0" || bad "--lint <branch>: expected rc=0 got $_rc"
    _bcs_attempted_move \
        && bad "--lint <branch>: attempted a move: $_out" || ok "--lint <branch>: no move attempted"

    # An unrecognised flag or a second positional is refused by name, never silently
    # reinterpreted — a flag read as a branch name is a move nobody asked for. The fixture flag
    # deliberately CARRIES a card token (`--card-4242`), so "no board work" is a live assertion
    # here: with a token-free `--bogus` it would pass even when the flag is stored as the branch.
    _bcs_run --card-4242
    [[ "$_rc" -eq 0 ]] && ok "unknown option: exits 0" || bad "unknown option: expected rc=0 got $_rc"
    grep -q "unknown option" <<< "$_out" \
        && ok "unknown option: refuses loudly" || bad "unknown option: not refused: $_out"
    _bcs_attempted_move \
        && bad "unknown option: attempted a move: $_out" || ok "unknown option: NO board work attempted"
    _bcs_run "fix/card-4242-x" "fix/card-9999-y"
    [[ "$_rc" -eq 0 ]] && ok "extra positional: exits 0" || bad "extra positional: expected rc=0 got $_rc"
    grep -q "unexpected extra argument" <<< "$_out" \
        && ok "extra positional: refuses loudly" || bad "extra positional: not refused: $_out"
    _bcs_attempted_move \
        && bad "extra positional: attempted a move: $_out" || ok "extra positional: NO board work attempted"

    # `-h`/`--help` (card#5354). Asserted on STDOUT ALONE, not the merged stream `_bcs_run`
    # captures: a requested help is the requested OUTPUT, and every refusal arm here also prints
    # the same usage line — to stderr. Merged, "prints the usage line" cannot tell the help arm
    # from the `-*` refusal it was added to stop reaching, so the assertion would pass either way.
    _bcs_help_stdout() {  # <args…> — stdout only; sets _hout
        _hout="$(cd "$_repo" && HOME="$_home" KBCARD_API='' KBCARD_TOKEN_FILE='' KB_BCS_LOG="$_log" \
                 bash "$BCS" "$@" 2>/dev/null)" || true
    }
    for _hflag in --help -h; do
        rm -f "$_log"; _bcs_help_stdout "$_hflag"
        grep -q "^usage: board-card-start" <<< "$_hout" \
            && ok "$_hflag: prints the usage line on STDOUT" \
            || bad "$_hflag: no usage line on stdout: $_hout"
        [[ -s "$_log" ]] \
            && bad "$_hflag: attempted board work" || ok "$_hflag: NO board work attempted"
    done

    # THE REGRESSION THIS PAIRING EXISTS TO CATCH: the help arm lives INSIDE the end-of-options
    # guard, so `-- --help` is still a BRANCH NAME (git accepts the ref). Move the arm above the
    # guard — the natural "simplification" — and this goes red while every assertion above stays
    # green, because help would then be printed for an argument the terminator already claimed.
    rm -f "$_log"; _bcs_help_stdout -- --help
    [[ -z "$_hout" ]] \
        && ok "-- --help: help NOT printed — the terminator still claims the argument" \
        || bad "-- --help: printed help for a terminated argument — the arm escaped the guard: $_hout"

    # `--` IS AN END-OF-OPTIONS TERMINATOR, and the population it serves is live, not theoretical:
    # git ACCEPTS a branch whose name starts with '-' — `git check-ref-format refs/heads/-foo` is
    # rc 0 and `git update-ref` creates it (only the `git branch` PORCELAIN refuses the name) — and
    # hooks/pre-push is fed whatever is being pushed. So the refs below are created the way git
    # actually allows, rather than passed as bare strings: the shape under test is a REAL ref.
    # Without the terminator the `-*` arm refuses these names, which is a FALSE refusal (the mover
    # moves their cards regardless — post-checkout passes no arguments and resolves HEAD).
    # The premise is ASSERTED, not assumed: if a future git rejected these names the terminator
    # would be serving a population that no longer exists, and every assertion below would keep
    # passing while the premise had silently gone false.
    _mkref_ok=1
    for _r in "-card-4242-x" "-card_4242-x" "-foo"; do
        git -C "$_repo" update-ref "refs/heads/$_r" HEAD 2>/dev/null || _mkref_ok=0
    done
    [[ "$_mkref_ok" -eq 1 ]] \
        && ok "git CREATES branches whose names start with '-' (the premise the terminator serves)" \
        || bad "git refused a '-'-leading branch name — the premise for the -- terminator no longer holds"

    # …on the LINT path: accepted, and it still lints (a terminator that merely stopped the refusal
    # while dropping the argument would pass an rc-0-and-no-refusal test).
    _bcs_run --lint -- "-card_4242-x"
    [[ "$_rc" -eq 0 ]] && ok "--lint -- <dash-name>: exits 0" || bad "--lint -- <dash-name>: expected rc=0 got $_rc"
    grep -q "unknown option" <<< "$_out" \
        && bad "--lint -- <dash-name>: refused as an option — the terminator is decorative: $_out" \
        || ok "--lint -- <dash-name>: NOT refused as an unknown option"
    grep -q "board-branch-lint:.*card 4242" <<< "$_out" \
        && ok "--lint -- <dash-name>: the name reached the lint (it warns)" \
        || bad "--lint -- <dash-name>: no lint warning — the argument was dropped: $_out"
    # "no move attempted" is asserted on the CORRELATING dash-name, never on the warn-worthy one:
    # the lint warns only where the grammar does NOT recognize the branch, so a warn-worthy name
    # can never reach board work and a no-move assertion on it could not fail under any mutation.
    _bcs_run --lint -- "-card-4242-x"
    _bcs_attempted_move \
        && bad "--lint -- <dash-name>: flag dropped — a REAL move was attempted: $_out" \
        || ok "--lint -- <dash-name>: no move attempted"

    # …and on the MOVER path: after `--` a dash-leading name is the BRANCH, so a correlating one
    # reaches board work. This is what makes it a terminator rather than an early `exit 0`.
    _bcs_run -- "-card-4242-x"
    [[ "$_rc" -eq 0 ]] && ok "-- <dash-name>: exits 0" || bad "-- <dash-name>: expected rc=0 got $_rc"
    _bcs_attempted_move \
        && ok "-- <dash-name>: became the branch (board work reached)" \
        || bad "-- <dash-name>: never reached board work — dropped or refused: $_out"

    # The terminator does NOT reopen the empty-positional hole: one positional owner serves both
    # sides of `--`, so an empty argument after it is refused exactly as before it. A second copy
    # of that arm is how the two sides would drift apart, so this is the assertion that pins it.
    _bcs_run -- ""
    [[ "$_rc" -eq 0 ]] && ok "-- \"\": exits 0" || bad "-- \"\": expected rc=0 got $_rc"
    grep -q "is empty" <<< "$_out" \
        && ok "-- \"\": still refuses an empty positional" || bad "-- \"\": empty not refused: $_out"
    _bcs_attempted_move \
        && bad "-- \"\": fell through to HEAD and attempted a move: $_out" \
        || ok "-- \"\": NO board work attempted"

    # THE CALL SITE. The false refusal was reachable only through hooks/pre-push, which is where
    # the branch name arrives unsanitised, so the hook itself is exercised — real stdin in git's
    # "<local-ref> <local-sha> <remote-ref> <remote-sha>" shape, real `board-card-start` on PATH.
    # Asserting the parser alone would leave the hook free to drop the `--` and go back to
    # printing "no card moved" on every push of such a branch.
    _pp="$HERE/../hooks/pre-push"
    if [[ -r "$_pp" ]]; then
        _ppbin="$_t/ppbin"; mkdir -p "$_ppbin"
        # A wrapper, not a symlink: `ln -s` yields copies on the Windows/MSYS topology this
        # toolkit supports, and a copied board-card-start cannot find _kb-board-lib.sh beside it.
        printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$BCS" > "$_ppbin/board-card-start"
        chmod +x "$_ppbin/board-card-start"
        _pp_run() {  # <bare-branch-name> — feed the hook one pushed ref, as git does
            rm -f "$_log"; _rc=0
            _out="$(cd "$_repo" && PATH="$_ppbin:$PATH" HOME="$_home" KBCARD_API='' KBCARD_TOKEN_FILE='' \
                    KB_BCS_LOG="$_log" bash "$_pp" origin "$_repo" \
                    <<<"refs/heads/$1 1111111111111111111111111111111111111111 refs/heads/$1 0000000000000000000000000000000000000000" 2>&1)" || _rc=$?
        }
        _pp_run "-foo"
        # WHAT THIS rc ASSERTION ACTUALLY PINS: the hook's `|| true` and its trailing `exit 0` each
        # independently force rc 0, so no change to what board-card-start returns can red it — it
        # is a SMOKE test that the hook parses and runs at all, and it reds on the failure that
        # would (a syntax error: rc 2, verified). Recorded because reading it as "a non-zero
        # board-card-start would be caught here" would be wrong.
        [[ "$_rc" -eq 0 ]] && ok "pre-push '-foo': exits 0 (runs, and never blocks a push)" \
            || bad "pre-push '-foo': expected rc=0 got $_rc"
        [[ -z "$_out" ]] && ok "pre-push '-foo': SILENT — no 'no card moved' refusal on a valid branch" \
            || bad "pre-push '-foo': the hook printed a refusal for a branch git accepts: $_out"
        _pp_run "-card_4242-x"
        grep -q "board-branch-lint:.*card 4242" <<< "$_out" \
            && ok "pre-push '-card_4242-x': still LINTS through the terminator" \
            || bad "pre-push '-card_4242-x': the advisory did not fire: $_out"
    else
        bad "hooks/pre-push not readable — the call site could not be exercised"
    fi

    # ── the token DECLARATION gate (card#7245) ───────────────────────────────────────────
    # Every case above stops at the board-id gate, so the token ladder is never reached there.
    # This block gets past it — a host-local board id plus a matching board env — so the arm
    # under test is the one that used to fall through to ~/.kanban-dev-token: a hook on a box
    # with no per-board token would send the SHARED credential, and did so silently.
    git -C "$_repo" config kanban.board-id 42
    printf 'export KB_BOARD_ID=42\n' > "$_home/.kanban-t-board.env"
    _bcs_run
    [[ "$_rc" -eq 0 ]] && ok "no declared token: exits 0 (never blocks a checkout)" \
        || bad "no declared token: expected rc=0 got $_rc"
    grep -q "no token file is declared" <<< "$_out" \
        && ok "no declared token: refuses loudly, naming the missing declaration" \
        || bad "no declared token: did not name it: $_out"
    grep -q "kanban-dev-token" <<< "$_out" \
        && bad "no declared token: still names the removed shared default: $_out" \
        || ok "no declared token: does NOT reach for the removed shared default"
    # WITNESS for the absence assertion above: the SAME repo and board env, with one declaration
    # added, gets PAST this gate — it stops at the NEXT one instead (no api_base: this fixture
    # runs with KBCARD_API='' and a scratch HOME, so there is no host env to resolve one from).
    # Without this, a board-card-start that had started refusing everything would satisfy all
    # three assertions above.
    : > "$_home/board.token"
    printf 'export KB_BOARD_ID=42\nexport KBCARD_TOKEN_FILE=%s\n' "$_home/board.token" \
        > "$_home/.kanban-t-board.env"
    _bcs_run
    grep -q "no token file is declared" <<< "$_out" \
        && bad "declared token: still refused at the token gate: $_out" \
        || ok "declared token: gets PAST the token gate (witness)"
    grep -q "no usable kanban api_base" <<< "$_out" \
        && ok "declared token: stops at the NEXT gate, naming it" \
        || bad "declared token: did not reach the api_base gate: $_out"

    # ── a userinfo-bearing api_base never reaches the DURABLE log (card#7500) ────────────
    # `https://user:password@host/api/v3` is a SUPPORTED api_base — kb_require_https_host
    # ACCEPTS it, by design, because it judges the HOST (kb-host-guard-selftest pins the row).
    # This hook's diagnostics are written to $KB_BCS_LOG, a FILE: stderr in a CI run is at least
    # bounded by log retention, a password under ~/.cache/ is not. Both of this bin's sites that
    # render the base are driven here, and both are past the token gate the block above just
    # cleared, so the fixture is already in the right state.
    #
    # ⛔ ASSERTED ON THE CREDENTIAL VALUE, never on the presence of a mask — a run printing
    # `***` AND the password would satisfy a mask check and leak anyway. Paired with a HOST leg
    # each time: these messages exist to tell an operator which host was involved, and an edit
    # that redacted the whole base would pass the absence half while destroying that.
    #
    # THE HOST IS 127.0.0.1 AND NOT AN RFC-2606 NAME, deliberately: `_bcs_is_placeholder_host`
    # treats every reserved documentation host (.test / .invalid / example.*) as host-scrubbed
    # and substitutes $KB_API for it, so a fixture using one would never reach these lines with
    # the base it declared. A loopback literal is the RFC-2606-equivalent that survives the scrub
    # check. Nothing is ever sent: the guard refuses in the first case, and the second runs
    # against a `curl` stub that answers a transport failure without opening a socket.
    _UI_PW='not-a-real-password-card7500'
    _UI_USER='fakeuser'
    printf '{"promote":{"board_id":"42","released_stage_id":"85","api_base":"https://%s:%s@127.0.0.1/api/v3"}}\n' \
        "$_UI_USER" "$_UI_PW" > "$_repo/.release-pr.json"
    # The stage ids the board env above deliberately lacked — the block that wrote it was
    # asserting the token gate and stops before them. The SECOND site below is past that gate,
    # so this fixture needs them; declared here rather than earlier so nothing above moves.
    printf 'export KB_BOARD_ID=42\nexport KBCARD_TOKEN_FILE=%s\nexport KB_STAGE_IN_PROGRESS=84\nexport KB_STAGE_BACKLOG=81\nexport KB_STAGE_PRIORITIZED=82\nexport KB_STAGE_HELD=83\n' \
        "$_home/board.token" > "$_home/.kanban-t-board.env"
    mkdir -p "$_t/stubbin"
    # A `curl` that can never reach anything: rc 7 is what real curl returns when it cannot
    # connect, which is what makes kb_api_status yield HTTP 000 and reach the second site.
    printf '#!/usr/bin/env bash\ncat >/dev/null 2>&1 || true\nexit 7\n' > "$_t/stubbin/curl"
    chmod +x "$_t/stubbin/curl"

    _ui_run() {  # <expected-host> [--stub-curl] — run the bin, leave the durable log in $_log
        local _eh="$1" _p="$PATH"
        [[ "${2:-}" == "--stub-curl" ]] && _p="$_t/stubbin:$PATH"
        rm -f "$_log"; _rc=0
        _out="$(cd "$_repo" && HOME="$_home" PATH="$_p" KBCARD_API='' KBCARD_TOKEN_FILE='' \
                KANBAN_EXPECTED_HOST="$_eh" KB_BCS_LOG="$_log" bash "$BCS" 2>&1)" || _rc=$?
        _ui_log="$(cat "$_log" 2>/dev/null || true)"
    }
    _ui_assert() {  # <label>
        local _l="$1"
        # POSITIVE CONTROL FIRST: every leg below is an ABSENCE, and an empty durable log — a
        # run that never got here, a renamed knob — satisfies all of them while measuring nothing.
        eq "$_l — the durable log was written (positive control)" "true" \
           "$(has 'board-card-start:' "$_ui_log")"
        eq "$_l — the password is NOT in the durable log" "false" "$(has "$_UI_PW"   "$_ui_log")"
        eq "$_l — the username is NOT in the durable log" "false" "$(has "$_UI_USER" "$_ui_log")"
        eq "$_l — the HOST is still named"                "true"  "$(has '127.0.0.1' "$_ui_log")"
        eq "$_l — nor is the password on the merged stream" "false" "$(has "$_UI_PW" "$_out")"
        eq "$_l — the hook still exits 0 (never blocks a checkout)" "0" "$_rc"
    }

    # SITE 1 — the https-host trust guard refuses (the expected host is not this base's host).
    _ui_run "board.invalid"
    eq "userinfo base, guard refuses — it IS the guard line" "true" \
       "$(has 'failed the https-host trust guard' "$_ui_log")"
    _ui_assert "userinfo base, guard refuses"

    # SITE 2 — the guard PASSES (the base is on the expected host) and the card read cannot
    # complete, which is the HTTP 000 arm. This is the one that only fires once a credential
    # has been accepted as legitimate, i.e. on a real operator's real base.
    _ui_run "127.0.0.1" --stub-curl
    eq "userinfo base, unreachable API — it IS the 000 arm" "true" \
       "$(has 'is unreachable' "$_ui_log")"
    _ui_assert "userinfo base, unreachable API"

    # CONTROL — a userinfo-FREE base is still rendered verbatim, so the mask is not a rewrite of
    # every message. Without this, redacting the base wholesale would pass everything above.
    printf '{"promote":{"board_id":"42","released_stage_id":"85","api_base":"https://127.0.0.1/api/v3"}}\n' \
        > "$_repo/.release-pr.json"
    _ui_run "board.invalid"
    eq "CONTROL: a userinfo-free base is quoted verbatim" "true" \
       "$(has "api_base 'https://127.0.0.1/api/v3' failed" "$_ui_log")"
    eq "CONTROL: …and no mask is inserted into it"        "false" "$(has '***' "$_ui_log")"
    unset -f _ui_run _ui_assert
    unset _UI_PW _UI_USER _ui_log

    rm -rf "$_t"
else
    echo "  skip (git not on PATH)"
fi

echo "== _ibh_hooks_dir — install-target resolution + refuse discriminator (F7) =="
expect_rc  "unset → default .git/hooks (safe)"  0 _ibh_hooks_dir "/repo" ""
expect_out "unset → default path"   "/repo/.git/hooks"     _ibh_hooks_dir "/repo" ""
expect_rc  "relative .githooks (tracked) → REFUSE" 3 _ibh_hooks_dir "/repo" ".githooks"
expect_rc  "relative .git/hooks (under .git) → safe" 0 _ibh_hooks_dir "/repo" ".git/hooks"
expect_rc  "absolute out-of-tree → safe"        0 _ibh_hooks_dir "/repo" "/etc/git/hooks"
expect_rc  "absolute inside tree → REFUSE"      3 _ibh_hooks_dir "/repo" "/repo/.githooks"
expect_out "relative .githooks resolves vs root" "/repo/.githooks" _ibh_hooks_dir "/repo" ".githooks"
# A '..'-relative hooksPath resolves OUTSIDE the work tree, but the RAW string still starts with
# the repo root — an un-normalized prefix test called it in-tree and printed the wrong fix.
expect_rc  "'../shared-hooks' escapes the tree → safe, not the in-tree refuse" 0 _ibh_hooks_dir "/repo/proj" "../shared-hooks"
expect_rc  "'sub/../.githooks' still lands in-tree → REFUSE"  3 _ibh_hooks_dir "/repo/proj" "sub/../.githooks"
expect_out "the echoed path is NOT lexically rewritten (the OS resolves it as git does)" \
           "/repo/proj/../shared-hooks" _ibh_hooks_dir "/repo/proj" "../shared-hooks"

echo "== _ibh_hooks_dir — SET-but-EMPTY core.hooksPath is 'hooks disabled', not 'unset' =="
# git does not fall back on an empty value: it dispatches NO hooks. Presence therefore has to
# arrive as an explicit argument, because the value alone cannot carry it.
expect_rc  "empty value + presence flag → rc 4 (disabled)"     4 _ibh_hooks_dir "/repo" "" "/repo/.git" "1"
expect_rc  "empty value WITHOUT the flag → the unset default"  0 _ibh_hooks_dir "/repo" "" "/repo/.git" ""
expect_out "…and that default is <git-dir>/hooks"  "/repo/.git/hooks" _ibh_hooks_dir "/repo" "" "/repo/.git" ""
expect_out "an explicit common dir wins (linked worktree)" "/main/.git/hooks" _ibh_hooks_dir "/wt" "" "/main/.git"

echo "== _ibh_norm — pure lexical normalization (no filesystem access) =="
expect_out "collapses x/.."        "/a/c"    _ibh_norm "/a/b/../c"
expect_out "collapses . and //"    "/a/b"    _ibh_norm "/a/./b//"
expect_out "keeps a relative path relative" "a/b" _ibh_norm "a/./b"
expect_out "root stays root"       "/"       _ibh_norm "/a/.."

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
    grep -q "resolves inside the tracked work tree" <<< "$_out" \
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

echo "== install-board-hooks — separated git topologies: worktree REFUSED, the other two INSTALL (card#5226, card#5311) =="
# Three separated topologies, three DIFFERENT right answers, split by BLAST RADIUS: only the
# linked worktree shares its hooks dir with checkouts the operator did not name, so only it is
# refused. They are built for real rather than faked, because the discriminator is what git
# actually reports for each: `--git-common-dir` != `--git-dir` is true ONLY for the linked
# worktree (measured on git 2.43 — the other two report them EQUAL), so a check built on that
# comparison would pass here while missing two of three.
if command -v git >/dev/null 2>&1; then
    _t="$(mktemp -d)"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    git init -q "$_t/main"; ( cd "$_t/main" && echo a > a && git add a && git commit -qm a )
    git -C "$_t/main" worktree add -q "$_t/wt" -b wtb
    git init -q --separate-git-dir="$_t/sepgit" "$_t/sep"
    # The COMMIT is load-bearing, not fixture decoration: `git checkout -b` on an UNBORN head does
    # not dispatch post-checkout, so the dispatch proof below would be a check that cannot pass
    # (measured — it failed exactly this way before the commit was added). The submodule fixture
    # is committed already, by virtue of being a clone.
    ( cd "$_t/sep" && echo x > x && git add x && git commit -qm x )
    git init -q "$_t/super"
    ( cd "$_t/super" && echo s > s && git add s && git commit -qm s \
      && git -c protocol.file.allow=always submodule add -q "$_t/main" sub && git commit -qm sub ) >/dev/null 2>&1

    _sepgit="$_t/sepgit"
    _subgit="$_t/super/.git/modules/sub"

    # THE REFUSED ONE: non-zero, AND its own words — a generic message would satisfy a bare rc test.
    _topo() {   # <label> <path> <must-contain> <must-NOT-contain>
        local _rc=0 _o
        _o="$(bash "$IBH" --check "$2" 2>&1)" || _rc=$?
        [[ "$_rc" -ne 0 ]] && ok "$1: refused (rc=$_rc)" || bad "$1: must refuse (got rc=$_rc, out=$_o)"
        grep -q "$3" <<< "$_o" \
            && ok "$1: message names its own topology ($3)" || bad "$1: wrong message: $_o"
        grep -q "$4" <<< "$_o" \
            && bad "$1: message carries another topology's wording ($4): $_o" \
            || ok "$1: does NOT emit another topology's wording"
    }
    _topo "linked worktree"  "$_t/wt"       "LINKED WORKTREE"      "SEPARATE git directory"

    # ── THE TWO THAT NOW INSTALL (card#5311) ────────────────────────────────────────────────
    # Asserted on the MESSAGE and on the hook landing where git READS, never on rc: all of these
    # paths exited 1 before this card, so an rc-only test could not have failed on the old code.
    _installs() {   # <label> <repo> <expected-common-dir> <must-contain> <must-NOT-contain>
        local _label="$1" _repo="$2" _cdir="$3" _want="$4" _not="$5" _rc=0 _o _err
        # (a) DISPATCH PROOF, before installing anything: git itself must run a hook placed in
        # <cdir>/hooks. Every other assertion in this block rests on that dir being the one git
        # reads, and an `-L` presence check alone would never establish it.
        printf '#!/bin/sh\necho fired > %s/DISPATCHED\n' "$_cdir" > "$_cdir/hooks/post-checkout"
        chmod +x "$_cdir/hooks/post-checkout"
        git -C "$_repo" checkout -qb "probe-$$" 2>/dev/null
        [[ -f "$_cdir/DISPATCHED" ]] \
            && ok "$_label: git DISPATCHES hooks from $_cdir/hooks (proven by running one)" \
            || bad "$_label: git did not dispatch from $_cdir/hooks — the whole disposition rests on this"
        rm -f "$_cdir/DISPATCHED" "$_cdir/hooks/post-checkout"

        # (b) --check: rc 0, and stdout EXACTLY the dispatch dir. Captured WITHOUT stderr — the
        # topology note is deliberately on stderr in both modes because --check's only stdout is
        # the target dir (a contract board-session-close consumes), and folding 2>&1 in here would
        # both pollute the equality and hide a regression that moved the note onto stdout.
        _rc=0; _o="$(bash "$IBH" --check "$_repo" 2>/dev/null)" || _rc=$?
        [[ "$_rc" -eq 0 && "$_o" == "$_cdir/hooks" ]] \
            && ok "$_label: --check rc 0, stdout is exactly the dispatch dir" \
            || bad "$_label: --check must print only $_cdir/hooks (rc=$_rc out=$_o)"

        # (c) the note is on STDERR, names this topology, and not another's.
        _err="$(bash "$IBH" --check "$_repo" 2>&1 >/dev/null)"
        grep -q "$_want" <<< "$_err" \
            && ok "$_label: stderr note names its own topology ($_want)" \
            || bad "$_label: wrong/absent stderr note: $_err"
        grep -q "$_not" <<< "$_err" \
            && bad "$_label: note carries another topology's wording ($_not): $_err" \
            || ok "$_label: does NOT emit another topology's wording"

        # (d) a SUB-DIRECTORY argument prints the SAME canonical dir. git answers the common dir
        # ABSOLUTE for both these topologies even from a sub-directory (measured, git 2.43.0),
        # which is why no normalization is needed here — and this pins that measurement.
        mkdir -p "$_repo/subdir"
        _o="$(bash "$IBH" --check "$_repo/subdir" 2>/dev/null)"
        [[ "$_o" == "$_cdir/hooks" ]] \
            && ok "$_label: sub-directory argument prints the same canonical dir" \
            || bad "$_label: sub-directory argument printed $_o, wanted $_cdir/hooks"

        # (e) the REAL install lands where git dispatches — both hooks — and writes nothing into
        # the work tree's own .git (the path the installer used to be hardcoded to).
        bash "$IBH" "$_repo" >/dev/null 2>&1 \
            && ok "$_label: install succeeds" || bad "$_label: install failed"
        local _h
        for _h in post-checkout pre-push; do
            [[ -L "$_cdir/hooks/$_h" ]] \
                && ok "$_label: $_h symlinked into the dispatch dir" \
                || bad "$_label: $_h is NOT at $_cdir/hooks/$_h"
        done
        [[ ! -e "$_repo/.git/hooks/post-checkout" ]] \
            && ok "$_label: nothing written into the work tree's own .git/hooks" \
            || bad "$_label: also wrote into $_repo/.git/hooks — the old hardcoded target"
    }
    _installs "--separate-git-dir" "$_t/sep"        "$_sepgit" "SEPARATE git directory" "LINKED WORKTREE"
    _installs "submodule"          "$_t/super/sub"  "$_subgit" "is a SUBMODULE of"      "LINKED WORKTREE"

    # PROVE-IT-CAN-FAIL: with the disposition mutated back to the pre-card behaviour (always
    # <root>/.git), the assertions above must RED. Without this the block could be passing on a
    # target that happens to be right for another reason.
    # The mutant must live in a REAL toolkit LAYOUT: the installer resolves its hook sources at
    # <dirname $0>/../hooks and exits 1 before reading a single argument if they are absent. A
    # bare copy in a scratch dir therefore dies at "hook source missing" and never reaches the
    # code under mutation — a control that silently never ran. (It did, on the first pass here.)
    _mut="$_t/mutant"; mkdir -p "$_mut/bin"
    ln -s "$(cd "$(dirname "$IBH")/.." && pwd)/hooks" "$_mut/hooks"
    sed 's|^    if \[ "\$cdir" -ef "\$root/\.git" \]; then printf .*$|    printf "%s" "$root/.git"; return 0|' \
        "$IBH" > "$_mut/bin/install-board-hooks"
    if cmp -s "$IBH" "$_mut/bin/install-board-hooks"; then
        bad "prove-it-can-fail: the mutation did not apply — the control never ran"
    else
        # TWO facts, both required. A bare "stdout != the right dir" is satisfied by the mutant
        # dying for an unrelated reason, which is exactly how an earlier version of this control
        # passed while never reaching the mutated code at all.
        #   (a) WITNESS — the mutated value reached the downstream code. <sep>/.git is a FILE, so
        #       the mutant cannot create a hooks dir under it and says so, naming the mutated
        #       target. That diagnostic is producible ONLY by the mutated disposition.
        #   (b) the --check assertion above genuinely reds on this mutant.
        _rc=0; _o="$(bash "$_mut/bin/install-board-hooks" --check "$_t/sep" 2>"$_t/mut.err")" || _rc=$?
        if grep -q "$_t/sep/\.git/hooks" "$_t/mut.err" && [[ "$_o" != "$_sepgit/hooks" ]]; then
            ok "prove-it-can-fail: the mutant targeted $_t/sep/.git/hooks (witnessed in its own diagnostic) and the assertion reds"
        else
            bad "prove-it-can-fail: control did not run — mutant stdout='$_o' rc=$_rc stderr='$(cat "$_t/mut.err")'"
        fi
    fi

    # Only the worktree has another checkout to redirect to; the message must name it, since a
    # classification without the command to run is what this refusal replaced.
    # Captured, never piped: `set -o pipefail` is live here, so `<refusal> | grep -q` reports the
    # REFUSAL's rc 1 and a matching pattern reads as a failure.
    _out="$(bash "$IBH" --check "$_t/wt" 2>&1 || true)"
    grep -q "install-board-hooks $_t/main\$" <<< "$_out" \
        && ok "worktree refusal names the MAIN checkout as the command to run" \
        || bad "worktree refusal did not name the main checkout: $_out"

    # …and it must be TRUE: the command the refusal prints has to actually succeed.
    bash "$IBH" "$_t/main" >/dev/null 2>&1 && [[ -L "$_t/main/.git/hooks/post-checkout" ]] \
        && ok "the redirected command works (main checkout installs)" \
        || bad "the refusal named a command that does not work"
    # Installing at the main checkout wires the worktree too — the claim the message makes.
    [[ -L "$(git -C "$_t/wt" rev-parse --git-common-dir)/hooks/post-checkout" ]] \
        && ok "…and that wires the worktree's dispatch dir, as the message claims" \
        || bad "main-checkout install did not reach the worktree's dispatch dir"

    # THE REFUSAL IS TOPOLOGY-CONDITIONAL, NOT TOPOLOGY-ABSOLUTE: a set core.hooksPath wins on
    # every topology, so a worktree that configures one is installable and refusing it would be
    # a FALSE refusal. This is the positive control for the guard — without it, a guard keyed on
    # topology alone passes every assertion above.
    mkdir -p "$_t/outhooks"; git -C "$_t/wt" config core.hooksPath "$_t/outhooks"
    _rc=0; _out="$(bash "$IBH" --check "$_t/wt" 2>&1)" || _rc=$?
    [[ "$_rc" -eq 0 && "$_out" == "$_t/outhooks" ]] \
        && ok "worktree + out-of-tree core.hooksPath: NOT refused, targets the hooksPath" \
        || bad "worktree with core.hooksPath must install (rc=$_rc out=$_out)"
    git -C "$_t/wt" config --unset core.hooksPath

    # An ordinary checkout is unaffected, and a SUB-DIRECTORY argument still prints the canonical
    # <root>/.git/hooks — `--git-common-dir` is answered relative to the typed path, so passing it
    # through would print `<root>/subdir/../.git/hooks` into a stdout other tools consume.
    mkdir -p "$_t/main/subdir"
    _out="$(bash "$IBH" --check "$_t/main/subdir" 2>&1)"
    [[ "$_out" == "$_t/main/.git/hooks" ]] \
        && ok "sub-directory argument still prints the canonical <root>/.git/hooks" \
        || bad "sub-directory argument printed a non-canonical target: $_out"
    rm -rf "$_t"
else
    echo "  skip (git not on PATH)"
fi

echo "== the owner tag follows the In Progress move as its own write (process, faked kanban API) =="
# The whole hook, run as the post-checkout path runs it (no arguments, the fixture repo's branch),
# against a `curl` stand-in. Every leg asserts the WHOLE PATCH sequence: the move must be exactly
# `{workflow_stage_id}` (a stage-only PATCH is a MOVE to the server; any other key needs the update
# permission), and the owner tag, when written, is a SEPARATE `{tags}` PATCH after it. Every
# refusal must also reach the DURABLE log — the installed wrapper discards this hook's stderr.
if command -v git >/dev/null 2>&1; then
    _mktmp_scratch --home
    # shellcheck source=/dev/null
    source "$HERE/_kb-api-stub.sh"
    kb_stub_scrub_env
    kb_stub_board_config t 42 \
        'export KB_STAGE_IN_PROGRESS=84' 'export KB_STAGE_BACKLOG=81' 'export KB_STAGE_PRIORITIZED=82'
    kb_stub_install
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    _orepo="$TMP/repo"
    git init -q "$_orepo"
    ( cd "$_orepo" && echo a > a && git add a && git commit -qm a && git checkout -q -b fix/card-4242-x )
    git -C "$_orepo" config kanban.board-id 42
    printf '{"project":"acme","roster":[{"name":"builder"}]}\n' > "$TMP/coordination.config.json"
    _olog="$TMP/bcs-owner.log"

    # KB_STUB_TAGS is the card's `tags` value, spliced raw so a leg can hand it a non-list.
    # KB_STUB_TAGS_PATCH answers a PATCH carrying `tags` with that status; KB_STUB_MOVE refuses the
    # stage-only move.
    kb_stub_route() {
        local method="$1" url="$2" body="$3"
        case "$method $url" in
            "GET "*/tasks/4242.json*)
                printf '200\n{"data":{"id":4242,"board_id":42,"workflow_stage_id":81,"tags":%s}}' "${KB_STUB_TAGS:-[]}" ;;
            "GET "*/tasks/4244.json*)
                printf '200\n{"data":{"id":4244,"board_id":42,"workflow_stage_id":84,"tags":[]}}' ;;
            "PATCH "*/tasks/4242.json)
                if [[ -n "${KB_STUB_TAGS_PATCH:-}" ]] && jq -e 'has("tags")' <<<"$body" >/dev/null; then
                    printf '%s\n{"message":"tag write refused by the stub"}' "$KB_STUB_TAGS_PATCH"
                elif [[ -n "${KB_STUB_MOVE:-}" ]]; then
                    printf '%s\n{"message":"refused"}' "$KB_STUB_MOVE"
                else
                    printf '200\n{"data":{"id":4242}}'
                fi ;;
            *) printf '404\n{"message":"unrouted"}' ;;
        esac
    }
    export -f kb_stub_route

    _own_run() {  # <COORD_AGENT or -unset> — run the hook; sets _rc/_out/_ologtxt/_obody
        kb_stub_reset; rm -f "$_olog"; _rc=0
        local envs=(COORD_CONFIG="$TMP/coordination.config.json")
        [[ "$1" == -unset ]] || envs+=(COORD_AGENT="$1")
        _out="$(cd "$_orepo" && env "${envs[@]}" KB_BCS_LOG="$_olog" bash "$BCS" 2>&1)" || _rc=$?
        _ologtxt="$(cat "$_olog" 2>/dev/null || true)"
        _obody="$(kb_stub_bodies PATCH /tasks/4242.json | jq -cS .)"
    }
    _move='{"workflow_stage_id":84}'

    KB_STUB_TAGS='["fr"]' _own_run builder
    eq "stamp: rc 0"                                     "0" "$_rc"
    eq "stamp: the stage-only move, THEN a separate PATCH with the card's tags plus the owner tag" \
       "$_move"$'\n''{"tags":["fr","owner:acme/builder"]}' "$_obody"
    eq "stamp: …the owner write re-reads the card after the move" "2" "$(kb_stub_count GET /tasks/4242.json)"
    eq "stamp: …and says so"                             "true" "$(has 'owner tag owner:acme/builder stamped on card #4242' "$_out")"

    for _tp in 403 422; do
        KB_STUB_TAGS_PATCH=$_tp KB_STUB_TAGS='["fr"]' _own_run builder
        eq "tag write $_tp: rc 0"                        "0" "$_rc"
        eq "tag write $_tp: the move is exactly {workflow_stage_id} and still happened" \
           "$_move"$'\n''{"tags":["fr","owner:acme/builder"]}' "$_obody"
        eq "tag write $_tp: the move is reported"        "true" "$(has 'card #4242 (#4242) → In Progress' "$_out")"
        eq "tag write $_tp: the durable log says NOT stamped, with the status and reason" "true" \
           "$(has "NOT stamped on card #4242 (#4242) — HTTP $_tp, server said: tag write refused by the stub" "$_ologtxt")"
        eq "tag write $_tp: …not worded as a failed move" "false" "$(has 'the move did not happen' "$_ologtxt")"
    done

    KB_STUB_MOVE=403 KB_STUB_TAGS='["fr"]' _own_run builder
    eq "a refused move: no owner tag is written for it"  "$_move" "$_obody"
    eq "a refused move: …and the card is not re-read for one" "1" "$(kb_stub_count GET /tasks/4242.json)"

    KB_STUB_TAGS='["owner:acme/builder","fr"]' _own_run builder
    eq "same owner: the move alone (no tags write)"      "$_move" "$_obody"
    eq "same owner: nothing logged"                      "" "$_ologtxt"

    KB_STUB_TAGS='["fr","owner:other/reviewer"]' _own_run builder
    eq "conflict: rc 0"                                  "0" "$_rc"
    eq "conflict: the move STILL happens, the holder's tag untouched, no second owner" "$_move" "$_obody"
    eq "conflict: the durable log names the holder"      "true" "$(has 'already held by owner:other/reviewer' "$_ologtxt")"

    KB_STUB_TAGS='["fr"]' _own_run ghost
    eq "seat outside the roster: the move alone"         "$_move" "$_obody"
    eq "seat outside the roster: the durable log says why" "true" "$(has "COORD_AGENT 'ghost' is not a roster[].name" "$_ologtxt")"
    KB_STUB_TAGS='["fr"]' _own_run -unset
    eq "COORD_AGENT unset: the move alone"               "$_move" "$_obody"
    eq "COORD_AGENT unset: the durable log says why"     "true" "$(has 'COORD_AGENT is unset' "$_ologtxt")"
    eq "…and it is not worded as a failed move"          "false" "$(has 'the move did not happen' "$_ologtxt")"

    KB_STUB_TAGS='{"0":"keep-me"}' _own_run builder
    eq "unreadable tags: the move alone, no tag write"   "$_move" "$_obody"
    eq "unreadable tags: the durable log says so"        "true" "$(has 'current tags could not be read' "$_ologtxt")"

    # A card id the board answers 404 for: LOUD only when the branch NAMED the card explicitly
    # (`card-712`), SILENT for a typed leading id (`fix/712-…`, often a foreign ticket number). Both
    # legs assert the GET happened, so the silent one is a measured miss, not a run that never read.
    git -C "$_orepo" checkout -q -b fix/card-712-x
    _own_run builder
    eq "explicit id 404: rc 0"                            "0" "$_rc"
    eq "explicit id 404: the card WAS read"               "1" "$(kb_stub_count GET /tasks/712.json)"
    eq "explicit id 404: the durable log says it does not exist" "true" "$(has 'card #712 named in the branch does not exist' "$_ologtxt")"
    eq "explicit id 404: nothing written"                 "" "$(kb_stub_bodies PATCH /tasks/712.json)"
    git -C "$_orepo" checkout -q -b fix/712-x
    _own_run builder
    eq "typed id 404: rc 0"                               "0" "$_rc"
    eq "typed id 404: the card WAS read"                  "1" "$(kb_stub_count GET /tasks/712.json)"
    eq "typed id 404: SILENT — nothing in the durable log" "" "$_ologtxt"
    eq "typed id 404: SILENT — nothing on stderr"         "" "$_out"
    # ⭐ NO STAGE REGRESSION: a card already In Progress is LEFT ALONE — nothing written, nothing
    # stamped, and silently, because that is a genuine no-op rather than a failure. This is the
    # invariant `kbcard move --card-start` now shares with this mover through the lib (card#9556);
    # the leg lives here because this is the caller that has always carried it and had no leg.
    git -C "$_orepo" checkout -q -b fix/card-4244-x
    _own_run builder
    eq "a card past the move stages: rc 0"                 "0" "$_rc"
    eq "⭐ a card past the move stages: NOTHING is written" "" "$(kb_stub_bodies PATCH /tasks/4244.json)"
    eq "…and it is a genuine no-op, not a failure"         "" "$_ologtxt"
    git -C "$_orepo" checkout -q fix/card-4242-x

    unset -f _own_run kb_stub_route
    unset KB_STUB_TAGS KB_STUB_TAGS_PATCH KB_STUB_MOVE _orepo _olog _ologtxt _obody _move _tp
else
    echo "  skip (git not on PATH)"
fi

echo "== the mover records its board verdict on every arm; pre-push repeats it (process, faked kanban API, DL-225) =="
# Every arm is driven as post-checkout drives it (no arguments, the fixture repo's current branch),
# against the `curl` stand-in installed above, and each asserts the RECORD — not the log, which
# several arms keep silent on purpose. The arm list is derived from the mover: every
# `_bcs_verdict` / `bcs_skip` call and the exits between the token gate and the resolved card.
# Then the real hooks, on real checkouts: post-checkout writes, pre-push reads, from a linked
# worktree too.
if command -v git >/dev/null 2>&1 && [[ -n "${TMP:-}" && "${HOME:-}" == "${TMP:-}" ]]; then
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    _rrepo="$TMP/vrepo"; _rlog="$TMP/bcs-verdict.log"
    git init -q "$_rrepo"
    ( cd "$_rrepo" && echo a > a && git add a && git commit -qm a )
    git -C "$_rrepo" config kanban.board-id 42

    kb_stub_route() {
        local method="$1" url="$2"
        case "$method $url" in
            "GET "*/tasks/4242.json*) printf '200\n{"data":{"id":4242,"board_id":42,"workflow_stage_id":81,"tags":[]}}' ;;
            "GET "*/tasks/4243.json*) printf '200\n{"data":{"id":4243,"board_id":42,"workflow_stage_id":81,"block_reason":"waiting on ops","tags":[]}}' ;;
            "GET "*/tasks/5555.json*) printf '200\n{"data":{"id":5555,"board_id":99,"workflow_stage_id":81}}' ;;
            "GET "*/tasks/5556.json*) printf '200\n{"data":{"id":5556,"board_id":"99\\u001b[31mRED\\u0007","workflow_stage_id":81}}' ;;
            "GET "*/tasks/6000.json*) printf '%s\n{"message":"stub read answer"}' "${KB_STUB_READ:-403}" ;;
            "GET "*/tasks/6100.json*) printf '200\n{"data":{"id":6100}}' ;;
            "GET "*/tasks/search.json*) printf '%s\n{"data":%s,"meta":{"last_page":1,"total":%s}}' "${KB_STUB_SEARCH:-200}" "${KB_STUB_SEARCH_DATA:-[]}" "${KB_STUB_SEARCH_TOTAL:-0}" ;;
            "PATCH "*) printf '200\n{"data":{}}' ;;
            *) printf '404\n{"message":"unrouted"}' ;;
        esac
    }
    export -f kb_stub_route

    _vrun() {  # <branch> — create/switch the fixture to it (no hook installed yet), run the mover; sets _rc/_out/_ologtxt
        git -C "$_rrepo" checkout -q -B "$1"
        kb_stub_reset; rm -f "$_rlog"; _rc=0
        _out="$(cd "$_rrepo" && KB_BCS_LOG="$_rlog" bash "${BCS_RUN:-$BCS}" 2>&1)" || _rc=$?
        _ologtxt="$(cat "$_rlog" 2>/dev/null || true)"
    }
    _vget() {  # <branch> <key> — one field of the branch's record (empty when there is none)
        local f; f="$(cd "$_rrepo" && _bcs_verdict_file "$1")"
        sed -n "s/^$2=//p" "$f" 2>/dev/null || true
    }
    _varm() {  # <label> <branch> <verdict> <reason-substring>
        eq "$1: rc 0 (never blocks a checkout)" "0" "$_rc"
        eq "$1: recorded verdict" "$3" "$(_vget "$2" verdict)"
        eq "$1: recorded reason names the arm" "true" "$(has "$4" "$(_vget "$2" reason)")"
    }

    _vrun fix/card-4242-x
    _varm "resolved (card on this board)"   fix/card-4242-x resolved "card #4242 (#4242)"
    eq "resolved: the record names the board and the card" "42|4242" "$(_vget fix/card-4242-x board)|$(_vget fix/card-4242-x subject)"
    _vrun fix/card-4243-x
    _varm "resolved, then refused as pinned" fix/card-4243-x resolved "card #4243"
    eq "pinned: the refusal still reaches the durable log" "true" "$(has "is pinned" "$_ologtxt")"
    _vrun fix/card-712-x
    _varm "explicit id, HTTP 404"           fix/card-712-x absent "card #712: HTTP 404"
    _vrun fix/712-x
    _varm "typed id, HTTP 404"              fix/712-x absent "card #712: HTTP 404"
    eq "typed id 404: the mover itself stays SILENT (record only)" "|" "$_out|$_ologtxt"
    _vrun fix/card-5555-x
    _varm "card on ANOTHER board"           fix/card-5555-x absent "card #5555 is a card on board 99"
    eq "another board: the mover itself stays SILENT (record only)" "|" "$_out|$_ologtxt"
    # A board id that is not a plain integer (here with ESC/BEL in it) is no evidence of another board.
    _vrun fix/card-5556-x
    _varm "board id not a plain integer"    fix/card-5556-x not_checked "no plain-integer board id could be read"
    eq "board id not a plain integer: the record holds no control character" "false" \
       "$(_ctl "$(tr -d '\n' < "$(cd "$_rrepo" && _bcs_verdict_file fix/card-5556-x)")")"
    _vrun fix/card-6100-x
    _varm "HTTP 200 with no stage (unreadable, not an absence)" fix/card-6100-x not_checked "NOT confirmed missing"
    KB_STUB_READ=403 _vrun fix/card-6000-x
    _varm "card read refused (403)"         fix/card-6000-x not_checked "HTTP 403"
    KB_STUB_READ='!curl 7' _vrun fix/card-6000-x
    _varm "board unreachable (transport)"   fix/card-6000-x not_checked "unreachable"
    _vrun feature/dl-77-x
    _varm "DL matching no card, no card id" feature/dl-77-x absent "DL-77 matches no card on board 42"
    KB_STUB_SEARCH=500 _vrun feature/dl-77-x
    _varm "DL board read failed"            feature/dl-77-x not_checked "did not return a complete card list"
    KB_STUB_SEARCH_DATA='[{"id":4242,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"DL-89"}}]' KB_STUB_SEARCH_TOTAL=1 \
        _vrun feature/dl-89-x
    _varm "DL matched a card on this board" feature/dl-89-x resolved "card #4242 (DL-89)"
    # A DL that resolves wins the MOVE, but the branch's own EXPLICIT card token was never read — and at
    # merge the bridge makes such a token authoritative over the DL (docs/HOOKS.md). Not resolved.
    _d89='[{"id":4242,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"DL-89"}}]'
    KB_STUB_SEARCH_DATA="$_d89" KB_STUB_SEARCH_TOTAL=1 _vrun feature/dl-89-card-712-x
    _varm "DL resolved a card other than the explicit token" feature/dl-89-card-712-x not_checked \
        "DL-89 resolved card #4242; the branch's own card #712 was not judged"
    eq "DL vs explicit token: the mover is unchanged — DL wins, 4242 is moved, 712 is never read" "true|true|0" \
       "$(has "DL wins; #712 ignored" "$_out")|$(grep -q $'^PATCH\t.*/tasks/4242\\.json' "$KB_STUB_LOG" && echo true || echo false)|$(grep -c '/tasks/712\.json' "$KB_STUB_LOG")"
    KB_STUB_SEARCH_DATA="$_d89" KB_STUB_SEARCH_TOTAL=1 _vrun feature/dl-89-card-4242-x
    _varm "DL resolved the SAME card as the explicit token" feature/dl-89-card-4242-x resolved "card #4242 (DL-89)"
    eq "same card: no conflict line" "false" "$(has "DL wins" "$_out")"
    KB_STUB_SEARCH_DATA="$_d89" KB_STUB_SEARCH_TOTAL=1 _vrun fix/712-dl-89
    _varm "DL resolved, typed leading id differs (not in the bridge grammar)" fix/712-dl-89 resolved "card #4242 (DL-89)"
    eq "typed id + DL: the subject is the DL's card" "4242|712" "$(_vget fix/712-dl-89 subject)|$(_vget fix/712-dl-89 card)"
    # A DL the search DID match whose card then reads 404: the branch's own id (712) was never asked
    # about, so the record must not call it absent — the lint would accuse a number nobody judged.
    KB_STUB_SEARCH_DATA='[{"id":6200,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"DL-88"}}]' KB_STUB_SEARCH_TOTAL=1 \
        _vrun feature/dl-88-card-712-x
    # Its explicit 712 is not the DL's card, so the DL-vs-token verdict is set first and stands.
    _varm "DL matched a card whose read then 404s" feature/dl-88-card-712-x not_checked "DL-88 resolved card #6200; the branch's own card #712 was not judged"
    eq "DL-matched card 404: the record still keys the branch's own card id" "712" "$(_vget feature/dl-88-card-712-x card)"
    # A typed 712 is not that conflict, so the 404 of the DL's card is what the record says.
    KB_STUB_SEARCH_DATA='[{"id":6200,"board_id":42,"workflow_stage_id":81,"payload":{"dl_number":"DL-88"}}]' KB_STUB_SEARCH_TOTAL=1 \
        _vrun fix/712-dl-88
    _varm "DL matched a card whose read then 404s (typed id)" fix/712-dl-88 not_checked "the branch's own card id was not judged"
    # ⭐ AN rc OUTSIDE THE LIB'S DECLARED SET IS NO ANSWER (card#9756). Beside a _kb-board-lib.sh that
    # predates the card-start invariants each call returns 127; read as "not pinned" that stamped
    # dl_number onto a PINNED card before the stage verdict was ever asked. The DL matches no card, so
    # the branch's own card id is used and the dl_number stamp is due — the control proves this
    # fixture reaches that write, so the refusals below are measured and not a run that stopped early.
    _vrun fix/card-4242-dl-77-x
    eq "control, current lib: the dl_number stamp and the move are both written" \
       '{"payload":{"dl_number":"DL-0077"}}'$'\n''{"workflow_stage_id":84}' \
       "$(kb_stub_bodies PATCH /tasks/4242.json | jq -cS . | head -2)"
    BCS_RUN="$(_bin_beside_stale_lib "$TMP/bcs-stale-both" "$BCS" kb_card_pinned kb_card_start_stage_verdict)"
    for _sc in 4242 4243; do
        _vrun "fix/card-$_sc-dl-77-x"
        eq "⭐ lib without either invariant, card #$_sc: rc 0 (never blocks a checkout)" "0" "$_rc"
        eq "⭐ …NOTHING written — no dl_number stamp, no move, no owner tag" "" "$(kb_stub_bodies PATCH "/tasks/$_sc.json")"
        eq "⭐ …the durable log names the function and the rc" "true" \
           "$(has "kb_card_pinned returned rc 127, which is not one of its answers" "$_ologtxt")"
        eq "…and never reads the card as pinned" "false" "$(has 'is pinned' "$_ologtxt")"
    done
    BCS_RUN="$(_bin_beside_stale_lib "$TMP/bcs-stale-verdict" "$BCS" kb_card_start_stage_verdict)"
    _vrun fix/card-4242-dl-77-x
    eq "⭐ lib without the stage verdict only: NOTHING written — the stamp waits on the verdict too" "" \
       "$(kb_stub_bodies PATCH /tasks/4242.json)"
    eq "⭐ …the durable log names that function and the rc" "true" \
       "$(has "kb_card_start_stage_verdict returned rc 127, which is not one of its answers" "$_ologtxt")"
    unset BCS_RUN _sc

    _vrun docs/adoption-guide
    _varm "no DL or card-id token"          docs/adoption-guide not_checked "no DL or card-id token"
    git -C "$_rrepo" config kanban.board-id 43
    _vrun fix/card-4242-x
    _varm "board with no board env (no stage ids)" fix/card-4242-x not_checked "KB_BOARD_ID=43"
    git -C "$_rrepo" config --unset kanban.board-id
    _vrun fix/card-4242-x
    _varm "unmapped repo (no board id)"     fix/card-4242-x not_checked "no board_id"
    eq "unmapped: the record's board is empty" "" "$(_vget fix/card-4242-x board)"
    git -C "$_rrepo" config kanban.board-id 42
    # curl and jq both required: a PATH of the tools the mover reaches before that gate, minus jq.
    # A tool missing from this list makes the run stop at a different arm, which reds the reason check.
    _nojq="$TMP/nojq-bin"; mkdir -p "$_nojq"
    for _pn in bash git curl grep sed head tail cat date dirname readlink mkdir mktemp mv rm tr cut wc awk env; do
        _pt="$(command -v "$_pn")" && ln -s "$_pt" "$_nojq/$_pn"
    done
    git -C "$_rrepo" checkout -q -B fix/card-4242-x; rm -f "$_rlog"; _rc=0
    _out="$(cd "$_rrepo" && PATH="$_nojq" KB_BCS_LOG="$_rlog" bash "$BCS" 2>&1)" || _rc=$?
    _varm "jq not on PATH"                  fix/card-4242-x not_checked "curl and jq are both required"

    # A write that cannot land never fails the checkout, is logged, and the lint then says NOT RECORDED.
    _vrdir="$(cd "$_rrepo" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/agent-board-toolkit"
    rm -rf "$_vrdir"; : > "$_vrdir"
    _vrun fix/card-712-x
    eq "unwritable record: rc 0" "0" "$_rc"
    eq "unwritable record: the durable log says it could not be recorded" "true" \
       "$(has "the board verdict for branch 'fix/card-712-x' (absent) could not be recorded" "$_ologtxt")"
    _lrc=0; _lout="$(cd "$_rrepo" && bash "$BCS" --lint -- fix/card-712-x 2>&1)" || _lrc=$?
    eq "unwritable record: --lint says NOT RECORDED for the branch the board DID answer" "0|true" \
       "$_lrc|$(has "board verdict NOT RECORDED for branch 'fix/card-712-x'" "$_lout")"
    rm -f "$_vrdir"

    # ── the hooks themselves, on real checkouts ──────────────────────────────────────────────
    _hbin="$TMP/hookbin"; mkdir -p "$_hbin"
    printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$BCS" > "$_hbin/board-card-start"; chmod +x "$_hbin/board-card-start"
    cp "$HERE/../hooks/post-checkout" "$_rrepo/.git/hooks/post-checkout"; chmod +x "$_rrepo/.git/hooks/post-checkout"
    printf 'export KB_BOARD_ID=42\nexport KB_STAGE_IN_PROGRESS=84\nexport KB_STAGE_BACKLOG=81\nexport KB_STAGE_PRIORITIZED=82\nexport KB_CARD_ID_FLOOR=5000\n' \
        > "$HOME/.kanban-t-board.env"   # a key nothing reads since card#9570; no push line below may mention a floor
    _git() { ( cd "$1" && shift && PATH="$_hbin:$PATH" KB_BCS_LOG="$_rlog" git "$@" ); }
    _push() {  # <dir> <branch> — feed hooks/pre-push one pushed ref; sets _rc/_out
        _rc=0
        _out="$(cd "$1" && PATH="$_hbin:$PATH" bash "$HERE/../hooks/pre-push" origin x \
                <<<"refs/heads/$2 1111111111111111111111111111111111111111 refs/heads/$2 0000000000000000000000000000000000000000" 2>&1)" || _rc=$?
    }
    _git "$_rrepo" checkout -q main 2>/dev/null || _git "$_rrepo" checkout -q master
    _git "$_rrepo" branch -q -D fix/card-712-x fix/card-4242-x

    # ── the auto-move OPT-IN gate, on real checkouts (card#9845) ─────────────────────────────
    # `hooks/post-checkout` called the mover on EVERY branch checkout, so reading a colleague's
    # branch, bisecting or hopping back to `main` silently moved that branch's card to In
    # Progress. `git config kanban.automove-on-checkout` now arms it, per repo, and UNSET IS OFF.
    #
    # ⛔ ASSERTED ON WHAT REACHED THE BOARD — the stub's request log — never on an exit code: the
    # hook is fail-soft, so "moved the card" and "did nothing at all" are both rc 0, and an
    # exit-code assertion would pass whatever this hook does. Card 4242 sits in BACKLOG (stage 81)
    # in the stub, which is what makes BOTH answers reachable here: on a card already In Progress
    # the mover writes nothing regardless, so that fixture could not fail and would prove nothing.
    # Every arm is driven through a REAL `git switch -c` firing the REAL hook file, not by calling
    # the hook by hand — the guard being tested is one git itself has to reach.
    _hookcut() {  # <branch> — re-cut <branch> from scratch so post-checkout fires on a branch checkout
        _git "$_rrepo" checkout -q main 2>/dev/null || _git "$_rrepo" checkout -q master
        _git "$_rrepo" branch -q -D "$1" >/dev/null 2>&1 || true
        rm -f "$(cd "$_rrepo" && _bcs_verdict_file "$1")"
        kb_stub_reset; rm -f "$_rlog"; _rc=0
        _out="$(_git "$_rrepo" switch -q -c "$1" 2>&1)" || _rc=$?
    }
    _hmoved() { kb_stub_bodies PATCH /tasks/4242.json | jq -cS . 2>/dev/null | head -1; }
    _hcard=fix/card-4242-x

    _hookcut "$_hcard"
    eq "⭐ opt-in UNSET: the card is NOT moved on a real branch checkout" "" "$(_hmoved)"
    eq "⭐ opt-in UNSET: the card is not even READ — no request is issued at all" "0" \
       "$(kb_stub_count_any /tasks/)"
    eq "opt-in UNSET: the checkout itself succeeded and HEAD is the new branch" "0|$_hcard" \
       "$_rc|$(git -C "$_rrepo" symbolic-ref --short HEAD)"
    eq "opt-in UNSET: the hook prints nothing" "" "$_out"
    # The cost of not calling the mover, pinned so it is a decision and not a surprise: the
    # board-verdict record (DL-225) is the mover's write too, so a disarmed repo records none and
    # `pre-push` then reports NOT RECORDED for such a branch.
    eq "opt-in UNSET: no board verdict is recorded either" "" "$(_vget "$_hcard" verdict)"
    _push "$_rrepo" "$_hcard"
    eq "opt-in UNSET: pre-push says NOT RECORDED and still never blocks a push" "0|true" \
       "$_rc|$(has "board verdict NOT RECORDED for branch '$_hcard'" "$_out")"
    # …and that line names the arming as a cause, because its own remedy — check the branch out
    # again — does not work here: an unarmed repo records nothing on any number of re-checkouts,
    # and a remedy that cannot work is worse than a cause too many. (It is not the ONLY such
    # cause — an unwritable record survives a re-checkout too — so the message says "which",
    # never "the one": a uniqueness claim there would be false.)
    eq "opt-in UNSET: the NOT RECORDED line names the arming, as a cause a re-checkout will not fix" "true|true" \
       "$(has "git config kanban.automove-on-checkout true" "$_out")|$(has "which a re-checkout does NOT fix" "$_out")"

    # THE CONTROL: the same fixture, the same checkout, armed — the card DOES move. Without this
    # arm every assertion above would also pass against a fixture that can never move a card.
    git -C "$_rrepo" config kanban.automove-on-checkout true
    _hookcut "$_hcard"
    eq "⭐ opt-in TRUE: the card moves to In Progress (stage-only PATCH)" '{"workflow_stage_id":84}' "$(_hmoved)"
    eq "opt-in TRUE: the board verdict is recorded again" "resolved" "$(_vget "$_hcard" verdict)"

    # git owns the SPELLING (`--bool`), not the hook: the arming values are git's, and everything
    # else — including a value git refuses to read as a boolean — is OFF, silently and fail-soft.
    for _hv in yes on 1; do
        git -C "$_rrepo" config kanban.automove-on-checkout "$_hv"
        _hookcut "$_hcard"
        eq "opt-in '$_hv' (a git boolean TRUE): the card moves" '{"workflow_stage_id":84}' "$(_hmoved)"
    done
    for _hv in false off 0 "" not-a-boolean; do
        git -C "$_rrepo" config kanban.automove-on-checkout "$_hv"
        _hookcut "$_hcard"
        eq "opt-in '$_hv' → OFF: nothing is read or written, the checkout succeeds, nothing is printed" "0|0||" \
           "$_rc|$(kb_stub_count_any /tasks/)|$(_hmoved)|$_out"
    done
    unset _hv

    # The branch-checkout guard is unchanged and still decides first: git passes $3=0 for a FILE
    # checkout, and an ARMED repo must not move a card on one either. Driven by argv — that is the
    # interface git uses, and it is the one way to reach flag 0 deterministically.
    git -C "$_rrepo" config kanban.automove-on-checkout true
    kb_stub_reset; _rc=0
    _out="$( cd "$_rrepo" && PATH="$_hbin:$PATH" bash "$_rrepo/.git/hooks/post-checkout" \
             1111111111111111111111111111111111111111 1111111111111111111111111111111111111111 0 2>&1 )" || _rc=$?
    eq "armed, but \$3=0 (a file checkout): no request, rc 0, nothing printed" "0|0|" \
       "$_rc|$(kb_stub_count_any /tasks/)|$_out"

    # The rest of this block drives the hook's ARMED path (it is testing what post-checkout does
    # once it decides to run), so the fixture stays opted in from here on, and is returned to the
    # state the legs below expect: no `fix/card-4242-x`, no record for it, HEAD on the base branch.
    _git "$_rrepo" checkout -q main 2>/dev/null || _git "$_rrepo" checkout -q master
    _git "$_rrepo" branch -q -D "$_hcard"
    rm -f "$(cd "$_rrepo" && _bcs_verdict_file "$_hcard")"
    kb_stub_reset
    unset -f _hookcut _hmoved
    unset _hcard

    # A branch cut from a wrong-space number: the board says no, and pre-push repeats it.
    _git "$_rrepo" switch -q -c fix/card-712-x
    _push "$_rrepo" fix/card-712-x
    eq "hook: post-checkout recorded the 404 on a real switch -c" "absent" "$(_vget fix/card-712-x verdict)"
    eq "pre-push: rc 0 (never blocks a push)" "0" "$_rc"
    eq "pre-push: the board verdict is repeated" "true" "$(has "board-branch-lint: branch 'fix/card-712-x' names card 712, which is NOT a card on board 42" "$_out")"
    eq "pre-push: ONE line, and no floor text though the board env still sets KB_CARD_ID_FLOOR=5000" "1|false" \
       "$(printf '%s\n' "$_out" | wc -l | tr -d ' ')|$(has "floor" "$_out")"
    # One local branch pushed to two remote refs feeds pre-push two lines naming the same local ref.
    _rc=0
    _out="$(cd "$_rrepo" && PATH="$_hbin:$PATH" bash "$HERE/../hooks/pre-push" origin x 2>&1 <<EOF
refs/heads/fix/card-712-x 1111111111111111111111111111111111111111 refs/heads/a 0000000000000000000000000000000000000000
refs/heads/fix/card-712-x 1111111111111111111111111111111111111111 refs/heads/b 0000000000000000000000000000000000000000
EOF
)" || _rc=$?
    eq "pre-push, one branch to two remote refs: linted ONCE" "0|1|true" \
       "$_rc|$(printf '%s\n' "$_out" | wc -l | tr -d ' ')|$(has "names card 712, which is NOT a card on board 42" "$_out")"
    # The DL-vs-token record speaks at push, on one line. Each
    # branch is checked out through the real post-checkout first (the records above were removed).
    KB_STUB_SEARCH_DATA="$_d89" KB_STUB_SEARCH_TOTAL=1 _git "$_rrepo" checkout -q feature/dl-89-card-712-x
    _push "$_rrepo" feature/dl-89-card-712-x
    eq "pre-push, DL resolved another card: NOT CHECKED, one line, no floor text" "0|1|true|false" \
       "$_rc|$(printf '%s\n' "$_out" | wc -l | tr -d ' ')|$(has "board verdict NOT CHECKED for branch 'feature/dl-89-card-712-x' (card 712)" "$_out")|$(has "floor" "$_out")"
    eq "pre-push, DL resolved another card: names the rename remedy, not a re-checkout" "true|false" \
       "$(has "rename the branch so its DL and its card token name the same card, or accept that the bridge acts on card #712 at merge" "$_out")|$(has "check the branch out again" "$_out")"
    KB_STUB_SEARCH_DATA="$_d89" KB_STUB_SEARCH_TOTAL=1 _git "$_rrepo" checkout -q feature/dl-89-card-4242-x
    _push "$_rrepo" feature/dl-89-card-4242-x
    eq "pre-push, DL resolved the same card: silent" "0|" "$_rc|$_out"
    KB_STUB_SEARCH_DATA="$_d89" KB_STUB_SEARCH_TOTAL=1 _git "$_rrepo" checkout -q fix/712-dl-89
    _push "$_rrepo" fix/712-dl-89
    eq "pre-push, DL resolved + typed id: silent" "0|" "$_rc|$_out"
    _git "$_rrepo" checkout -q fix/card-5556-x
    _push "$_rrepo" fix/card-5556-x
    eq "pre-push, board id not a plain integer: NOT CHECKED, no control character printed" "true|false" \
       "$(has "board verdict NOT CHECKED for branch 'fix/card-5556-x'" "$_out")|$(_ctl "$_out")"
    # curl or jq missing at checkout, in a repo mapped by git config: the record names no board, and the
    # push line repeats that reason rather than a STALE that every later checkout would write again.
    PATH="$_nojq" _git "$_rrepo" checkout -q -b fix/card-4247-x
    eq "hook, jq not on PATH: post-checkout recorded not_checked, naming curl and jq, against no board" "not_checked|true|" \
       "$(_vget fix/card-4247-x verdict)|$(has "curl and jq are both required" "$(_vget fix/card-4247-x reason)")|$(_vget fix/card-4247-x board)"
    _push "$_rrepo" fix/card-4247-x
    eq "pre-push, jq was not on PATH at checkout (repo mapped by git config): NOT CHECKED with that reason, not STALE, one line" "0|1|true|true|false" \
       "$_rc|$(printf '%s\n' "$_out" | wc -l | tr -d ' ')|$(has "board verdict NOT CHECKED for branch 'fix/card-4247-x' (card 4247)" "$_out")|$(has "curl and jq are both required" "$_out")|$(has "STALE" "$_out")"
    rm -rf "$_nojq"
    # A real card, cut from a linked worktree, read back from the main one.
    git -C "$_rrepo" worktree add -q --detach "$TMP/vwt"
    _git "$TMP/vwt" switch -q -c fix/card-4242-x
    _push "$_rrepo" fix/card-4242-x
    eq "worktree: the record written in the linked worktree is read from the main one" "resolved" "$(_vget fix/card-4242-x verdict)"
    eq "pre-push: a RESOLVED verdict is silent" "0|" "$_rc|$_out"
    # A branch that was never checked out speaks, by name, on one line.
    _git "$_rrepo" branch fix/card-4244-x
    _push "$_rrepo" fix/card-4244-x
    eq "never checked out: NOT RECORDED, by name" "true" "$(has "board verdict NOT RECORDED for branch 'fix/card-4244-x' (card 4244)" "$_out")"
    eq "never checked out: ONE line, and no floor text" "1|false" \
       "$(printf '%s\n' "$_out" | wc -l | tr -d ' ')|$(has "floor" "$_out")"
    # Deleted and re-created WITHOUT a checkout: the old record is STALE, not borrowed…
    _git "$_rrepo" checkout -q fix/card-4244-x
    _git "$_rrepo" branch -q -D fix/card-712-x
    sleep 1
    _git "$_rrepo" branch fix/card-712-x
    _push "$_rrepo" fix/card-712-x
    eq "re-created without a checkout: STALE, not the old verdict" "true|false" \
       "$(has "board verdict for branch 'fix/card-712-x' (card 712) is STALE" "$_out")|$(has "which is NOT a card on board 42" "$_out")"
    # …and the next checkout records a current verdict again.
    _git "$_rrepo" checkout -q fix/card-712-x
    _push "$_rrepo" fix/card-712-x
    eq "re-created, then checked out: the current verdict is repeated, not STALE" "true|false" \
       "$(has "which is NOT a card on board 42" "$_out")|$(has "STALE" "$_out")"
    _push "$_rrepo" docs/adoption-guide
    eq "pre-push: a branch with no card id stays silent" "" "$_out"

    unset -f kb_stub_route _vrun _vget _varm _git _push
else
    echo "  skip (git not on PATH, or no scratch HOME)"
fi

echo "== _bcs_patch — 2xx echoes success (no log); non-2xx durably logs the captured status; always fail-soft (#4510) =="
# Stub the shared writer so the decision logic is exercised network-free. Redefining kb_api here
# shadows the lib's (sourced via $BCS); this is the last block, so the stub can't leak into others.
_tmpd="$(mktemp -d)"
kb_api() { KB_HTTP=200; return 0; }   # success path
_out="$(KB_BCS_LOG="$_tmpd/ok.log" _bcs_patch 42 '{}' 'OKMSG-emitted' 'FAILMSG-reason' 2>&1 || true)"
grep -q 'OKMSG-emitted' <<< "$_out" && ok "2xx emits the success message" || bad "2xx did not emit success: $_out"
[[ ! -s "$_tmpd/ok.log" ]] && ok "2xx writes NO durable failure line" || bad "2xx wrote an unexpected failure line: $(cat "$_tmpd/ok.log")"
kb_api() { KB_HTTP=422; return 1; }   # non-2xx: KB_HTTP carries the code kb_api captured
_out="$(KB_BCS_LOG="$_tmpd/fail.log" _bcs_patch 42 '{}' 'OKMSG-emitted' 'FAILMSG-reason' 2>&1 || true)"
if grep -q 'FAILMSG-reason' "$_tmpd/fail.log" 2>/dev/null && grep -q 'HTTP 422' "$_tmpd/fail.log" 2>/dev/null; then
    ok "non-2xx durably logs the fail-reason + captured status"
else
    bad "non-2xx did not log fail-reason+status: $(cat "$_tmpd/fail.log" 2>/dev/null)"
fi
grep -q 'OKMSG-emitted' <<< "$_out" && bad "non-2xx wrongly emitted the success message" || ok "non-2xx does NOT emit the success message"
kb_api() { KB_HTTP=500; return 1; }
_rc=0; KB_BCS_LOG="$_tmpd/rc.log" _bcs_patch 42 '{}' 'x' 'y' >/dev/null 2>&1 || _rc=$?
[[ "$_rc" -eq 0 ]] && ok "returns 0 even on a failed write (fail-soft: never blocks a checkout)" || bad "returned rc=$_rc on failure (must be 0)"
rm -rf "$_tmpd"

_summary "board-card-start-selftest"
