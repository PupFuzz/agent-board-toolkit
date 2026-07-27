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
        [[ -s "$_log" ]] || printf '%s' "$_out" | grep -q "fix/card-4242-x"
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
    printf '%s' "$_out" | grep -q "is empty" \
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
    printf '%s' "$_out" | grep -q "board-branch-lint:.*card 4524" \
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
    printf '%s' "$_out" | grep -q "unknown option" \
        && ok "unknown option: refuses loudly" || bad "unknown option: not refused: $_out"
    _bcs_attempted_move \
        && bad "unknown option: attempted a move: $_out" || ok "unknown option: NO board work attempted"
    _bcs_run "fix/card-4242-x" "fix/card-9999-y"
    [[ "$_rc" -eq 0 ]] && ok "extra positional: exits 0" || bad "extra positional: expected rc=0 got $_rc"
    printf '%s' "$_out" | grep -q "unexpected extra argument" \
        && ok "extra positional: refuses loudly" || bad "extra positional: not refused: $_out"
    _bcs_attempted_move \
        && bad "extra positional: attempted a move: $_out" || ok "extra positional: NO board work attempted"

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
    printf '%s' "$_out" | grep -q "unknown option" \
        && bad "--lint -- <dash-name>: refused as an option — the terminator is decorative: $_out" \
        || ok "--lint -- <dash-name>: NOT refused as an unknown option"
    printf '%s' "$_out" | grep -q "board-branch-lint:.*card 4242" \
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
    printf '%s' "$_out" | grep -q "is empty" \
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
        printf '%s' "$_out" | grep -q "board-branch-lint:.*card 4242" \
            && ok "pre-push '-card_4242-x': still LINTS through the terminator" \
            || bad "pre-push '-card_4242-x': the advisory did not fire: $_out"
    else
        bad "hooks/pre-push not readable — the call site could not be exercised"
    fi
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

echo "== install-board-hooks — a git common dir that is not <root>/.git is REFUSED, per topology (card#5226) =="
# Three separated topologies, three DIFFERENT right answers. They are built for real rather than
# faked, because the discriminator is what git actually reports for each: `--git-common-dir` !=
# `--git-dir` is true ONLY for the linked worktree (measured on git 2.43 — the other two report
# them EQUAL), so a check built on that comparison would pass here while missing two of three.
if command -v git >/dev/null 2>&1; then
    _t="$(mktemp -d)"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    git init -q "$_t/main"; ( cd "$_t/main" && echo a > a && git add a && git commit -qm a )
    git -C "$_t/main" worktree add -q "$_t/wt" -b wtb
    git init -q --separate-git-dir="$_t/sepgit" "$_t/sep"
    git init -q "$_t/super"
    ( cd "$_t/super" && echo s > s && git add s && git commit -qm s \
      && git -c protocol.file.allow=always submodule add -q "$_t/main" sub && git commit -qm sub ) >/dev/null 2>&1

    # Each topology: non-zero, AND its own words — a generic message would satisfy a bare rc test.
    _topo() {   # <label> <path> <must-contain> <must-NOT-contain>
        local _rc=0 _o
        _o="$(bash "$IBH" --check "$2" 2>&1)" || _rc=$?
        [[ "$_rc" -ne 0 ]] && ok "$1: refused (rc=$_rc)" || bad "$1: must refuse (got rc=$_rc, out=$_o)"
        printf '%s' "$_o" | grep -q "$3" \
            && ok "$1: message names its own topology ($3)" || bad "$1: wrong message: $_o"
        printf '%s' "$_o" | grep -q "$4" \
            && bad "$1: message carries another topology's wording ($4): $_o" \
            || ok "$1: does NOT emit another topology's wording"
    }
    _topo "linked worktree"  "$_t/wt"       "LINKED WORKTREE"      "SEPARATE git directory"
    _topo "--separate-git-dir" "$_t/sep"    "SEPARATE git directory" "LINKED WORKTREE"
    _topo "submodule"        "$_t/super/sub" "is a SUBMODULE of"    "LINKED WORKTREE"

    # Only the worktree has another checkout to redirect to; the message must name it, since a
    # classification without the command to run is what this refusal replaced.
    # Captured, never piped: `set -o pipefail` is live here, so `<refusal> | grep -q` reports the
    # REFUSAL's rc 1 and a matching pattern reads as a failure.
    _out="$(bash "$IBH" --check "$_t/wt" 2>&1 || true)"
    printf '%s' "$_out" | grep -q "install-board-hooks $_t/main\$" \
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
