# shellcheck shell=bash
# _selftest-prelude.sh — shared harness for the tests/*-selftest.sh scripts.
#
# Sourced by each selftest AFTER it computes its own HERE:
#     HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
#     source "$HERE/_selftest-prelude.sh"
#
# It carries only the harness the selftests all shared verbatim — the assertion
# helpers (ok/bad/fails, eq, expect_rc/expect_out, has), the required-bin guard, the
# temp-dir+trap[+scratch-HOME] setup, and the PASS/FAIL summary. It defines no test
# cases and asserts nothing; the fixtures and cases stay in each selftest.
#
# It deliberately does NOT run `set` — each selftest keeps its own shell options
# (board-snapshot omits -e on purpose). A selftest that needs a variant helper simply
# defines its own after sourcing (kb-board-lib's expect_rc/expect_out delegate to eq).

# The suite runs OUT OF the checkout whose `bin/` is symlinked onto a maintainer's PATH, and
# several selftests path-load `bin/*.py` with `importlib.util.spec_from_file_location` — a load
# that caches the compiled bytecode beside its target, i.e. inside `bin/`. The shipped helpers
# suppress that for themselves (card#6871); this covers the TEST side once, for every python3 any
# selftest spawns, rather than at each heredoc. `bin-artifact-hygiene-selftest.sh` deliberately
# clears it again per probe — its mutants have to be able to write, or they measure nothing.
export PYTHONDONTWRITEBYTECODE=1

# $GITHUB_REPOSITORY IS REMOVED FOR THE WHOLE SUITE, and this is a floor rather than a tidy-up.
# Actions sets it to the repository the workflow is running in, and since card#8538
# `bin/promote-released-cards` REFUSES a resolved `.promote.source` that is not it. Several
# files drive that bin with a fixture source (`acme/widget`) while asking about something else
# entirely — the charset guard, the unsourced-card report, the coverage section — and every one
# of them would then refuse for the WRONG reason IN CI while passing on a laptop. No count is
# written here, because one in a comment rots: reproduce it by deleting this line, exporting
# GITHUB_REPOSITORY to this repo's own slug, and running promote-source-qualify-selftest,
# release-pr-body-selftest and locale-range-guard-selftest — all three red, all three green
# locally, which is the whole hazard.
#
# The floor is HERE and not at each call site on purpose: a per-site scrub is a hand-kept list,
# and the site it misses is a CI-ONLY red — the most expensive kind to diagnose. A file for
# which the variable IS the subject sets it EXPLICITLY per arm instead
# (`promote-source-qualify-selftest.sh` § 7 is the one that does, and asserts this floor holds).
unset GITHUB_REPOSITORY

fails=0
# `checks` counts every assertion that ran, passed or failed. `fails` alone cannot tell a suite
# that ran its whole battery from one that lost half of it: delete an `eq` line and the file
# still prints `all checks passed`. A selftest that wants that leg closed asserts on this
# counter itself (`composite-action-wiring-selftest.sh` does); nothing here reads it, so no
# other file's behaviour changes.
checks=0
ok()  { checks=$((checks + 1)); printf '  ok   %s\n' "$1"; }
bad() { checks=$((checks + 1)); printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }

# eq <label> <expected> <got> — string-equality assertion.
eq() { [[ "$2" == "$3" ]] && ok "$1" || bad "$1 — expected '$2' got '$3'"; }

# has <needle> <haystack> → true/false on a LITERAL substring match (robust against
# the JSON quotes/braces and glob metacharacters in captured output).
#
# NEEDLE FIRST — a real contract, not a preference. Reversing the arguments is not a type
# error and not a syntax error: it silently becomes a substring test between two different
# strings, so it reads as a plain `false` and an assertion expecting `false` still passes.
# Ten selftests once defined this locally and one of them had exactly that inversion, which is
# why this lives here and nowhere else (card#5740). `prelude-shadow-selftest.sh` is what keeps
# that true — re-declaring any helper defined here reds it.
has() { case "$2" in *"$1"*) echo true ;; *) echo false ;; esac; }

# ⚑ WHEN A SELFTEST MAY STILL REACH FOR `grep -q` — stated here because this function is what
# would otherwise be the unexplained second idiom (card#7175). `has` and `has_line` are the
# owners for LITERAL substring / whole-line membership, and they answer with a STRING, which is
# what `eq <label> true|false "$(has …)"` consumes. Two questions they do not answer:
#   * a REGEX or an ANCHOR — `"board-branch-lint:.*card 4524"`, `"^usage: board-card-start"`, or
#     a needle supplied by the caller of a local helper, which may be either.
#   * an rc, where the site's shape is `<test> && ok … || bad "…: $out"` — `eq` prints
#     `expected 'true' got 'false'` and CANNOT carry the captured output into the failure
#     message, which at those sites is the whole diagnostic.
# In both cases the sanctioned spelling is `grep -q <needle> <<< "$var"` — a HERESTRING, whose
# producer is the shell itself writing an already-complete string, so the early-exit window this
# helper exists to close does not exist there either.
#
# ⚑ COUNTED, NOT ASSERTED, so the claim above is checkable: of the nineteen herestring sites in
# `board-card-start-selftest.sh`, six carry a REGEX or an anchor and four take a needle from
# their caller (either shape) — ten `has` cannot answer at all. Of the remaining NINE literal
# ones, seven interpolate the captured `$_out` into their `bad` text and one is rc-shaped inside
# a helper's `||` chain. **That leaves exactly one — the `'OKMSG-emitted'` negative — for which
# no counter-argument holds**, and it is left as a herestring on purpose: its mirror-image twin
# two lines above DOES interpolate `$_out`, and splitting an adjacent assertion pair across two
# idioms costs more to read than the single conversion buys. Recorded rather than done, so the
# next author meets the decision instead of re-deriving it.
# ⛔ WHAT IS FORBIDDEN IS THE PIPELINE — `<producer> | grep -q`, in any file under `bin/`,
# `hooks/` or `tests/`. `tests/piped-match-gate-selftest.sh` derives that population every run
# and reds on any occurrence it does not already disposition, so this is a gate, not advice.

# has_line <line> <text> → true/false on WHOLE-LINE membership: is <line> one of <text>'s
# lines? The line-anchored twin of `has`, and the replacement for every
# `<producer> | grep -qx <line>` in this suite (card#7175).
#
# ⛔ WHY IT EXISTS — a pipeline answers this question WRONG, and only sometimes. `grep -q`
# exits the moment it matches, closing the pipe while its writer is still writing. The writer
# then fails on that closed pipe, `set -o pipefail` promotes ITS non-zero status to the whole
# pipeline's, and the `&& echo true || echo false` tail reports a MATCH as `false`. (The status
# is 141 where SIGPIPE is at its default and 1 — an EPIPE write error — where an ancestor has
# ignored it, as the GitHub Actions runner does. Both are non-zero and both are promoted.) It
# cost a CI red on
# `lib-set-derivation-selftest.sh`, which was green on five consecutive local runs and red in CI
# on the same commit once a second multi-KB `[Unreleased]` entry pushed the payload past the pipe
# buffer.
#
# ⚑ THE DISCRIMINATOR IS NOT builtin-vs-external. Two conditions decide it, and both must hold:
# (a) `grep -q` leaves EARLY — the match is near the START of the stream, so the reader is gone
# while the writer still has bytes to push (a match at the END means grep read everything and
# exited after the writer did: no closed pipe, no signal); and (b) the writer has more than the
# 64 KiB PIPE BUFFER left to write at that moment. Measured on this host (bash 5.2.21),
# `printf '%s\n' "$big" | grep -qx MATCH-ME` — a BUILTIN writer:
#     needle first, 60009 bytes → rc 0    PIPESTATUS 0 0    (payload fits the buffer)
#     needle first, 65009 bytes → rc 141  PIPESTATUS 141 0  (the builtin's subshell DIED)
#     needle last,  5 MB        → rc 0    PIPESTATUS 0 0    (grep never left early)
# — taken with SIGPIPE at its DEFAULT. Under an inherited SIG_IGN the middle row reads rc 1 /
# PIPESTATUS `1 0` instead: the writer is not killed, it takes EPIPE and exits 1. Same defect.
# So a `printf`/`echo` upstream is not a safe form, only an untested one — which is the same
# "green until it is not" this helper exists to remove. `tests/pipeline-free-match-selftest.sh`
# pins every cell of that matrix, on both writer classes, asserting PIPESTATUS.
#
# NEEDLE FIRST, matching `has` — same contract, same reason (card#5740).
# No pipeline, no subprocess, not even a `grep`: a `case` glob over the text with the newline
# sentinels made explicit, so the SIGPIPE window structurally cannot exist. `"$1"` is quoted
# inside the pattern, so a needle carrying glob metacharacters is matched literally.
#
# ⛔ ONE divergence from `grep -qx`, and it is command substitution's, not this helper's: `$(…)`
# strips trailing newlines, so a producer that emitted one empty line and one that emitted
# nothing both arrive here as "". Both answer `true` for an EMPTY needle where `grep -qx ''`
# distinguishes them. No caller passes an empty needle; if one ever needs to, it must not
# capture through `$(…)` first.
has_line() {
    local nl=$'\n'
    case "$nl$2$nl" in *"$nl$1$nl"*) echo true ;; *) echo false ;; esac
}

# expect_rc <label> <expected-rc> <fn> <args...> — assert a call's exit status.
expect_rc() {
    local label="$1" exp="$2"; shift 2
    local rc=0; "$@" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq "$exp" ]] && ok "$label (rc=$rc)" || bad "$label expected rc=$exp got rc=$rc"
}
# expect_out <label> <expected> <fn> <args...> — assert a call's stdout.
expect_out() {
    local label="$1" exp="$2"; shift 2
    local got; got="$("$@" 2>/dev/null || true)"
    [[ "$got" == "$exp" ]] && ok "$label" || bad "$label expected '$exp' got '$got'"
}

# _need <-r|-x> <path> [label] — guard a bin the test needs; exit 1 if it can't run.
# label defaults to the path, reproducing the "selftest: <path> not found" message.
_need() {
    local flag="$1" path="$2" label="${3:-$2}" have=1
    case "$flag" in
        -r) [[ -r "$path" ]] && have=0 ;;
        -x) [[ -x "$path" ]] && have=0 ;;
    esac
    [[ "$have" -eq 0 ]] || { printf 'selftest: %s not found\n' "$label" >&2; exit 1; }
}

# _adopt_fn <src> <name> — eval one shell function out of <src>, by name, into THIS shell, and
# exit 1 naming it if <src> does not define it. The one spelling of "borrow a function from the
# tool under test", for the tests that drive a bin's internal function directly rather than the
# bin's CLI (`token-duplication-selftest.sh` adopts five out of
# `bin/agent-board-toolkit-runtime-check`: the digest that defines its needle, and the four
# `_kb-board-lib.sh` mirrors its parity block drives row-by-row).
#
# ⛔ THE `exit 1` IS THE POINT, not defensive padding. An extraction that silently answered ""
# would `eval` nothing, leave the caller's later invocations to fail as "command not found" in a
# subshell, and — where the caller compares two outputs — retire the comparison rather than red
# it. A rename in the bin must red the build, which is the same rule the population-glob and
# `require_value` derivations in this file are built on.
#
# ⚑ BOUND: this recognises the `^name() {` … `^}` spelling, which is what every bin here uses. A
# function defined as `name ()` or `function name {` is NOT extracted — it exits 1 naming the
# function, so the bound is loud rather than silent.
#
# ⚑ FIVE OTHER SITES, IN FOUR SELFTESTS, STILL HAND-SPELL THIS `sed` RANGE, and only ONE of them
# could adopt this as it stands — counted, not estimated, so the residual is not read as smaller
# than it is. `promote-pagination-selftest.sh:29` evals verbatim (adoptable today).
# `kb-host-guard-selftest.sh:35`/`:269` and `kb-positional-guard-selftest.sh:44` eval the source
# through a RENAME (`${src/host_ok() \{/host_ok_prc() \{}`) because the mirror and the lib copy
# must coexist in one shell — they need an alias parameter this does not have.
# `board-snapshot-selftest.sh:310` never evals at all; it greps the extracted TEXT, which needs a
# text-returning sibling. Not migrated here, and named rather than implied:
# `docs/CONSOLIDATION-PLAN.md` § Post-program dispositions carries that residual.
_adopt_fn() {
    local src
    src="$(sed -n "/^$2() {/,/^}/p" "$1")"
    [[ -n "$src" ]] || { printf 'selftest: could not extract %s from %s — did it get renamed?\n' "$2" "$1" >&2; exit 1; }
    eval "$src"
}

# _mktmp_scratch [--home] — set TMP to a fresh temp dir + an EXIT trap that removes it.
# With --home, also export a scratch HOME=$TMP so no real ~/.kanban-* file taints a result.
_mktmp_scratch() {
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    if [[ "${1:-}" == "--home" ]]; then
        export HOME="$TMP"
        mkdir -p "$HOME"
    fi
}

# ── a window measured from a stamp the FIXTURE wrote (card#8533) ─────────────────────────────
#
# WHY A SHARED PAIR RATHER THAN TWO LOCAL COPIES. A selftest that bounds elapsed time around a
# tool must not start its clock in the TEST: the tool's own startup then sits inside the window
# and a loaded box reds the cell for a defect the tool does not have. The fix is that the
# fixture stamps the instant its subject began — `release-tag-check-selftest`'s `ext::` remote
# helper stamps the read it is about to hang, `board-session-close-selftest`'s hanging delegate
# stamps its own launch — and the test measures from there. The WRITERS are properly different
# (a git remote helper vs a `/bin/sh` delegate); the READER is one behaviour, and it arrived in
# two near-verbatim copies in a single commit. Extracted at that second caller.
#
# ⛔ THE TWO ARE A PAIR, AND USING `_since_stamp` WITHOUT `_stamp_taken` IS THE TRAP. A stamp
# that was never written reads as epoch 0, so `_since_stamp` answers the seconds since 1970 —
# a number no bound passes, which LOOKS like the bound firing. The failure text then blames the
# subject for an interval that never happened. Assert `_stamp_taken` first, as its own cell, so
# a fixture that was never reached is reported as a fixture that was never reached.

# _since_stamp <stamp-file> — whole seconds from the epoch second in <stamp-file> until now.
# A stamp that yields NO epoch second counts from 0 (see the pairing rule above), and that is
# THREE states, not two: absent, unreadable, and — the one the writers actually produce —
# PRESENT BUT EMPTY. `date +%s > stamp` opens the redirect before it execs `date`, so a fixture
# killed in that window leaves a real zero-byte file, which `cat` then reads SUCCESSFULLY as
# nothing. `${s:-0}` is what covers that third state; without it the arithmetic is
# `$(( now -  ))` — a syntax error, so the reader fails instead of the subject, and in a
# `set -e` selftest the whole file aborts at this call, ahead of the `_stamp_taken` cell that
# exists to name exactly this. The `|| echo 0` is kept as well as `${s:-0}`, not replaced by
# it: it is what makes the absent/unreadable states independent of `inherit_errexit`, which no
# file here sets today and nothing stops a consumer setting tomorrow.
_since_stamp() { local s; s="$(cat "$1" 2>/dev/null || echo 0)"; echo $(( $(date +%s) - ${s:-0} )); }

# _stamp_taken <stamp-file> — true/false: did the fixture actually write the stamp? The
# precondition cell for every `_since_stamp` window; answers a STRING for `eq <label> true …`,
# the same contract as `has`/`has_line`.
# `-s`, not `-e`, and that is the half that pairs with the third state above: the zero-byte
# stamp is a file that EXISTS, so `-e` would answer `true` for a fixture that never wrote and
# hand the window a start it never had — the wrong diagnosis this pair exists to prevent.
_stamp_taken() { [[ -s "$1" ]] && echo true || echo false; }

# _summary <name> — the trailing PASS/FAIL block: fail loud on stderr + exit 1, else pass.
_summary() {
    if [[ "$fails" -gt 0 ]]; then
        echo "$1: $fails check(s) FAILED" >&2
        exit 1
    fi
    echo "$1: all checks passed"
}

# ── value-taking-flag parity (card#6645) ────────────────────────────────────────────────────
#
# WHY THIS LIVES HERE. Six selftest blocks asserted "every value-taking flag rejects an empty
# value" over a HAND-TYPED list of flags, and four more carried the same hand list without
# making the claim out loud. A hand list cannot go red when the bin grows a flag, so a claim
# made over one narrows silently and nothing fails: measured on this tree,
# promote-stage-guard-selftest listed FIVE of promote-released-cards' SIX guarded flags —
# `--cards` (v0.26.0) was never driven and the block still said "the whole class, not one
# instance", and kbcard-selftest drove TWO of bin/kbcard's 27. The fix is not ten repaired
# lists, which re-mint the defect at the eleventh; it is ONE derivation of the population FROM
# THE BIN, two-way-compared against what each block names — the same shape
# `help-output-selftest.sh` uses to hold its `--help` registry level with `bin/`.
#
# THE PREDICATE, STATED. A "value-taking flag" here means exactly one thing: a flag whose parse
# arm calls `require_value` or `kb_require_value`. BOTH spellings, deliberately — the three
# release movers are vendored standalone and MUST NOT source the lib, so each carries its own
# copy of the guard, while everything else uses `_kb-board-lib.sh`'s. A derivation covering one
# spelling would answer the empty set for half the toolkit.
#
# Each call site is resolved back to a flag by, in this order:
#   1. a literal flag as the call's own first argument (`require_value "--dl" …`);
#   2. the `case` pattern opening the SAME line (`--dls) require_value "$1" …`), with alias arms
#      (`-b|--board)`) split on `|` so both spellings are members;
#   3. the nearest preceding NON-COMMENT line that is either such a `case` pattern or an
#      `if [[ "${1:-}" == "--flag" ]]` test. That third rule is not padding: it is the only way
#      board-stats' and next-dl's multi-line arms are seen at all, and kbcard's global `--board`
#      — the highest-stakes flag in the toolkit — sits in an `if`, not in the `case`.
# A call site that none of the three resolves is NOT dropped. It is emitted as
# `UNRESOLVED:<line>`, a member no hand list can contain, so an arm shape this predicate does
# not recognise reds the gate instead of silently shrinking the population it reports.
#
# ⛔ WHAT IT STRUCTURALLY CANNOT SEE — stated so the gate is not over-cited:
#   * A value-taking flag with NO guard at all, or one guarded some other way. The predicate
#     keys on the GUARD, so it answers "is every GUARDED flag accounted for", never "is every
#     value-taking flag guarded". `agent-board-toolkit-runtime-check`'s `--reference` is the live
#     instance — it guards with `"${2:?…}"` and is invisible here. That one is a DELIBERATE
#     exclusion with its own reasoning (`docs/CONSOLIDATION-PLAN.md` § Stage C: that bin validates
#     `_kb-board-lib.sh`, so it must not source it, and its rc 1 is fixed in place by that), not a
#     gap this gate is failing to report. What is invisible is the SHAPE, whatever its reason.
#   * Whether a listed flag is actually DRIVEN by the block. The list is the block's own claim
#     about what it covers; this only holds that claim level with the bin.
#   * Anything about behaviour. It compares NAMES.
#
# awk rather than grep: resolving rule 3 needs a backward walk over the file, which a
# line-oriented match cannot do, and that walk has to skip comment lines — a header narrating
# `--dls) require_value "$1"` is prose, not an arm.

# _value_flags <bin-path> — the flags <bin> guards, derived from the file, C-collated, deduped.
_value_flags() {
    awk '
    function add_pattern(pat,   k, i, t, tok) {
        k = split(pat, tok, /\|/)
        for (i = 1; i <= k; i++) {
            t = tok[i]
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
            if (t ~ /^--?[A-Za-z0-9][A-Za-z0-9-]*$/) { out[t] = 1; got = 1 }
        }
    }
    # arm_pattern <line> — the case-arm pattern this line opens, or "" if it opens none.
    function arm_pattern(L,   p) {
        if (L !~ /\)/) return ""
        p = L; sub(/\).*$/, "", p)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", p)
        return (p ~ /^--?[A-Za-z0-9][A-Za-z0-9|_-]*$/) ? p : ""
    }
    { lines[NR] = $0 }
    END {
        for (i = 1; i <= NR; i++) {
            L = lines[i]
            if (L ~ /^[[:space:]]*#/) continue
            if (L !~ /(^|[^A-Za-z0-9_])(kb_)?require_value[[:space:]]/) continue
            got = 0
            if (match(L, /(kb_)?require_value[[:space:]]+"--[A-Za-z0-9][A-Za-z0-9-]*"/)) {
                # `^[^"]*"`, never `^.*"`: a greedy prefix eats through BOTH quotes and
                # leaves the empty string, which reads as "this call site resolved to nothing".
                s = substr(L, RSTART, RLENGTH); sub(/^[^"]*"/, "", s); sub(/"$/, "", s)
                out[s] = 1; continue
            }
            p = arm_pattern(L)
            if (p != "") { add_pattern(p); if (got) continue }
            for (j = i - 1; j >= 1 && j >= i - 40; j--) {
                P = lines[j]
                if (P ~ /^[[:space:]]*#/) continue
                p = arm_pattern(P)
                if (p != "") { add_pattern(p); break }
                if (match(P, /==[[:space:]]*"?--[A-Za-z0-9][A-Za-z0-9-]*"?/)) {
                    s = substr(P, RSTART, RLENGTH); sub(/^[^-]*--/, "--", s); gsub(/["[:space:]]/, "", s)
                    out[s] = 1; got = 1; break
                }
                # the arm above ended, or the construct did: this call site is in neither, so
                # stop walking rather than attribute it to an unrelated flag further up.
                if (P ~ /;;[[:space:]]*$/ || P ~ /^[[:space:]]*(esac|fi|done)[[:space:]]*$/) break
            }
            if (!got) out["UNRESOLVED:" i] = 1
        }
        for (k in out) print k
    }' "$1" | LC_ALL=C sort -u
}

# expect_value_flags <bin-path> <flag>... — two-way parity between the flags <bin> GUARDS and
# the flags the calling block names. Reds in BOTH directions, which is the whole point: a flag
# the bin grew and this test never heard of, and a flag this test still names after the bin
# dropped it. `comm` validates its inputs' order in the AMBIENT locale, so both sides are
# pinned to C alongside their producers — en_US.UTF-8 ignores punctuation in its primary pass
# and orders `-`-bearing tokens differently from codepoint order.
expect_value_flags() {
    local bin="$1"; shift
    local name derived listed
    _need -r "$bin"
    name="$(basename "$bin")"
    derived="$(_value_flags "$bin")"
    listed="$(printf '%s\n' "$@" | awk 'NF' | LC_ALL=C sort -u)"
    # Positive control FIRST: the two legs below are assertions of ABSENCE, and an empty
    # derivation — a moved bin, a renamed guard, an awk that matched nothing — satisfies both
    # while measuring nothing at all.
    eq "$name: the require_value derivation carries real data (positive control)" "false" \
       "$([[ -z "$derived" ]] && echo true || echo false)"
    eq "$name: guarded flag the bin has and this block does not name (add + drive it here)" "" \
       "$(LC_ALL=C comm -23 <(printf '%s\n' "$derived" | awk 'NF') <(printf '%s\n' "$listed" | awk 'NF'))"
    eq "$name: flag named here that the bin no longer guards (drop it)" "" \
       "$(LC_ALL=C comm -13 <(printf '%s\n' "$derived" | awk 'NF') <(printf '%s\n' "$listed" | awk 'NF'))"
}
