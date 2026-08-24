#!/usr/bin/env bash
# verdict-through-truncating-reader-selftest.sh — a tool's EXIT CODE is its verdict, and a
# reader that stops consuming stdout can destroy it before the verdict-carrying `exit` ever
# runs. This gate MEASURES every shipped bin against that reader and reds on any outcome this
# file does not already disposition.
#
# WHY THIS FILE EXISTS (card#6911). A bin writes its report to stdout and only afterwards
# reaches a verdict-carrying exit. A consumer that stops reading — `| head -1`, `| head -n 0`,
# a pager the operator quit, `$(…)` in a caller that already died — kills the writer at the
# write, and the caller receives a signal death instead of the verdict and its explanation:
#
#     gh-code-search …            rc 3, 671 B of stderr naming the refusal
#     gh-code-search … | head -1  rc 141, 0 B of stderr        (card#6884, since FIXED)
#
# This is worse than having no guard, because the invocation looks like it worked.
#
# ─────────────────── THREE THINGS THIS REPO GOT WRONG ABOUT THE MECHANISM ───────────────────
# Each was believed, written down, and then measured false. They are recorded here so the next
# reader does not re-mint them, and every one of them is a FIXTURE in the control matrix below
# rather than a claim in this prose.
#
#  1. ⛔ IT IS NOT builtin-vs-external. An in-tree note once claimed bash's `printf` BUILTIN
#     "does not die (rc 0 over 5 MB)". It does — measured rc 141. That fixture put its match at
#     the END of the stream, where the reader never exits early: THE FIXTURE COULD NOT REACH
#     THE CONDITION IT TESTED. Which is why every measurement here carries a presence witness
#     (below) proving the driver actually wrote bytes before the verdict.
#
#  2. ⛔ IT IS NOT `set -e` EITHER, and this file is where that was measured. The card's own
#     text explained `board-stats` surviving by "has no `set -e`". A bare builtin write with NO
#     errexit at all still dies:
#
#         #!/usr/bin/env bash          (no set -e)
#         printf '%s\n' $(seq 1 200000); echo VERDICT >&2; exit 7
#         → direct rc 7 · through `| head -n 0`  rc 141, and the stderr line is gone too
#
#     errexit is one of TWO routes, not the mechanism. The measured table, reproduced as
#     fixtures below:
#
#         write is a BUILTIN in the main shell      → SIGPIPE kills the shell    ✗ regardless
#         write is a CHILD  + errexit               → child dies, errexit takes it ✗
#         write is a CHILD  + no errexit            → child dies, parent survives ✓
#         builtin + `trap '' PIPE`, no tolerance    → EPIPE → errexit at rc 1    ✗ WRONG VERDICT
#         builtin + `trap '' PIPE` + tolerated      → survives                   ✓
#
#     `board-stats` is clean because it is BOTH — no errexit AND it renders through children.
#     Naming only the errexit half would have excused the first line of that table.
#
#  3. ⛔ `rc 141` IS NOT THE MECHANISM, AND MUST NEVER BE ASSERTED ON. A GitHub Actions runner
#     starts bash from Node, which sets SIGPIPE to `SIG_IGN`, and that disposition SURVIVES
#     `execve`. In CI the writer therefore gets EPIPE instead of the signal, prints
#     `write error: Broken pipe`, and exits 1; `pipefail` promotes it identically. A test
#     asserting `rc == 141` PASSES LOCALLY AND REDS IN CI. Every assertion in this file is on
#     rc PRESERVATION — `truncated_rc == direct_rc` — which is the same sentence under both
#     dispositions and names no signal number at all.
#
# ────────────────────────────── THE PREDICATE, STATED ──────────────────────────────
#
# POPULATION — the SHIPPED shell: `_shipped_shell_files` from `tests/_shipped-shell-lib.sh`,
# which is the `bin`/`hooks` half of `.github/workflows/ci.yml`'s shellcheck expression,
# re-derived on every invocation. No file list is stored here, so a new bin arrives as an
# unaccounted member the day it lands. `tests/` is excluded for the same reason CI's expression
# splits them: a selftest is not a shipped tool and has no caller to lose a verdict to — the
# lib exports that half separately (`_selftest_shell_files`) precisely so the two gates that
# DO want it can union it without this one inheriting it.
#
# ⚑ THE DERIVATION IS SOURCED, NOT SPELLED, and that is a card#6911 correction. The expression
# had been hand-copied into three class gates plus their prose; this file was the third, which
# is one past canon #5's threshold. `tests/_shipped-shell-lib.sh` now owns it, `ci.yml` remains
# the authority, and `_ci_shellcheck_drift` (asserted below, with planted controls) is what
# keeps the lib's copy honest — a workflow `run:` string cannot source a bash lib, so the
# restatement can only be guarded, not deleted. The other two gates are unchanged and can adopt
# the lib in their own PRs: its output is byte-identical to what each already computes.
#
# MEMBERSHIP IS MEASURED, NOT READ. A grep over the shape is NOT an audit of this class, and
# the first sibling-audit instrument tried on it failed its own control (it reported the
# already-known-defective `gh-code-search` as clean) and was discarded. So each member is
# DRIVEN and the outcome recorded:
#
#     direct_rc     = rc of `<bin> <driver-argv>`
#     direct_bytes  = bytes it wrote to STDOUT on that run          ← the presence witness
#     dfl_rc        = rc of the same command on `| head -n 0`, with SIGPIPE at SIG_DFL
#     ign_rc        = …the same, with SIGPIPE at SIG_IGN
#
#   SURVIVES   bytes > 0  ∧  dfl_rc == direct_rc  ∧  ign_rc == direct_rc
#   LOSES      bytes > 0  ∧  either truncated rc differs from the direct one
#   (no state) bytes == 0                              the driver never reached a write
#
# ⛔ BOTH DISPOSITIONS ARE MEASURED, AND THAT IS NOT BELT-AND-BRACES — THE ANSWER DIFFERS.
# Measured on this tree: under SIG_DFL 12 of 15 driven members lose their verdict; under
# SIG_IGN only 9 do. (⚠ THOSE ARE THE READING, NOT THE POPULATION — the run's own denominator
# block re-derives both on every invocation and is the figure to quote. This pair moved from
# 11-of-14 / 8 the day `release-tag-check` landed, and quoting a written count is exactly how
# it went stale.) A bin with NO errexit (`board-card-start`, `board-snapshot`,
# `board-session-close`) is killed outright by the signal but merely gets a non-zero `printf`
# it never inspects when the signal is ignored — so it LOSES on a developer box and SURVIVES on
# a GitHub Actions runner. Measuring one disposition and recording the result would therefore
# produce a gate that reds in the other environment, which is defect 3 one level deeper: not a
# hardcoded `141`, but a hardcoded per-member OUTCOME that only holds where it was taken.
#
# Both legs are PINNED — with `env --default-signal` / `env --ignore-signal`, NOT with `trap`
# (see `_measure`: a signal ignored on entry to a non-interactive shell cannot be reset from
# inside it, so `trap - PIPE` is a silent no-op on a CI runner). SAFE means safe under both,
# which is exactly the property the two-mechanism fix was built to have (`trap '' PIPE`
# neutralises the signal, the tolerated write neutralises the EPIPE rc; either alone covers only
# one disposition).
#
# ⛔ "THE SAME ANSWER WHATEVER STARTED IT" IS TRUE ON THE SIGNAL AXIS ONLY, AND SAYING IT
# UNQUALIFIED WAS THIS FILE'S OWN DEFECT. The claim was verified by running the gate under a
# parent that sets SIG_IGN and getting a byte-identical table — which measures the DISPOSITION
# axis and nothing else. The second axis is HOST CONFIG, and it was live: `bin/kbcard`'s driver
# read `$HOME`, so the gate answered LOSES on a developer box and UNREACHED (a hard red) on a
# GitHub Actions runner, on the same commit — found by CI, not by this file. Closed for that
# member with the planted config at `DRIVER_ENV` below, and a control drives BOTH sides of it.
# ⚠ ONE KNOWN RESIDUAL ON THIS AXIS, named rather than swept: `board-session-close`'s direct rc
# and byte count also differ between a configured box and a bare runner (rc 0 / ~20 KB vs
# rc 1 / ~1.4 KB). Its CLASSIFICATION agrees in both, so no assertion here is host-dependent
# today — but the measurement behind it is, and a future change to that bin could split them.
#
# THE bytes == 0 ROW IS A HARD RED, NEVER A PASS. A driver that produced no stdout measured nothing
# — it is defect (1) above, exactly. It cannot be dispositioned as SURVIVES; the driver must be
# fixed or the member moved to UNDRIVEN.
#
# THE DRIVER IS `--help`-SHAPED, AND THAT BOUNDS WHAT A GREEN RUN PROVES. It must be
# network-free, side-effect-free and deterministic, which the verdict paths of most of these
# bins are not (they read boards, remotes and the GitHub API). So:
#   * LOSES is SOUND. If a bin cannot keep rc 0 through a truncating reader on its help path,
#     its stdout writes are fatal to the main shell, and every verdict behind them is at risk.
#     The card measured exactly this equivalence on `agent-board-toolkit-runtime-check`:
#     driven to a real STALE-COPIES verdict it gave rc 141/0 B, and on a passing tree the same
#     rc 141 in place of rc 0.
#   * SURVIVES IS NOT A PROOF OF SAFETY. It certifies ONE path. A bin whose help renders
#     through a child while its report path uses a builtin would read SURVIVES here and still
#     lose its verdict. Where a member's verdict path has been measured directly, its
#     disposition says so; where it has not, the disposition says that too.
#
# ⛔ WHAT THIS GATE STRUCTURALLY CANNOT SEE — stated so it is not over-cited:
#   * Any code path the driver does not execute (above). This is the big one.
#   * The UNDRIVEN members: three git hooks and a sourced lib have no argv surface at all, one
#     hook writes to a live board, and `_shellcheck-pinned` writes nothing to its own stdout on
#     any path. They are UNMEASURED, not clean, and each is listed with its reason.
#   * `bin/*.py`, and the bash embedded in this repo's composite actions — the population
#     `tests/composite-action-wiring-selftest.sh` derives every run, not a list written here.
#   * STDERR. The class as filed is about stdout; a bin can equally lose its verdict to a
#     truncated stderr, and only the merged-stream case is sampled here.
#   * Whether a dispositioned reason is TRUE. It is a recorded judgement, re-read by whoever
#     next edits that site — not a proof.
#   * A BIN THAT LANDS IN A CONCURRENT PR. The population is this tree, so a bin merging on
#     another branch is invisible here and unaccounted the moment it arrives — which is the
#     gate WORKING (card#6579's `release-tag-check` and card#6619's `_shellcheck-pinned` were
#     each found exactly this way, by a merge-up), but it means neither PR's CI can see the
#     pair. Whichever merges SECOND reds `dev` until it merges up and adds the entry. That is
#     deliberate and must not be softened: an entry may only be added once the file is IN THE
#     TREE, because the symmetric leg below — a listed member the population no longer carries
#     — is what stops the roll accumulating fiction, and forward-declaring a file that is not
#     there yet would cost that leg its only teeth.
#
# ⛔ `command grep`, never bare `grep`: in an interactive Claude Code shell `grep` is a function
# execing `ugrep --ignore-files`, which honours `.gitignore` and still exits 0 — a truncated
# sweep that reads as a clean one.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_shipped-shell-lib.sh"
ROOT="$(cd "$HERE/.." && pwd)"

# ── the drivers ─────────────────────────────────────────────────────────────────────────────
#
# "<relpath>|<argv…>" — the network-free, side-effect-free invocation that reaches a stdout
# write. A population member with no entry here must appear in UNDRIVEN below.
DRIVERS=(
  "bin/adopt-to-dl|--help"
  "bin/agent-board-toolkit-runtime-check|--help"
  "bin/board-card-start|--help"
  "bin/board-session-close|--help"
  "bin/board-snapshot|--help"
  "bin/board-stats|--help"
  "bin/dependabot-deploy-reconcile|--help"
  "bin/dl-a0-backfill-triaged|--help"
  "bin/dl-a1-register-field|--help"
  "bin/gh-code-search|--help"
  "bin/gitignore-secret-family-check|--help"
  "bin/kbcard|"
  "bin/promote-released-cards|--help"
  "bin/release-artifacts-check|--help"
  "bin/release-pr-body|--help"
  "bin/release-tag-check|--help"
)

# ── the dispositions ────────────────────────────────────────────────────────────────────────
#
# "<relpath>|<SURVIVES|LOSES>|<reason>" — the MEASURED outcome for every driven member, one
# line each. Both directions red: a LOSES member that starts surviving reds too, so the roll
# can only ever shrink and a fix cannot land without deleting its line. That RATCHET is the
# point — an open class item blocks its own symptoms (canon #18), and a bin fixed silently
# would take its entry's warning with it.
DISPOSITIONED=(
  "bin/gh-code-search|SURVIVES|FIXED (card#6884) — \`trap '' PIPE\` as the first statement after \`set\`, plus one tolerated write per stream of an already-built string. Its VERDICT path is measured too, in tests/gh-code-search-selftest.sh: rc 3 with 671 B of stderr through both \`head -1\` and \`head -n 0\`."
  "bin/agent-board-toolkit-runtime-check|SURVIVES|FIXED (card#6911) — the same two mechanisms. Its VERDICT path is measured: driven to a real STALE-COPIES verdict it answers rc 1 with 259 B of stderr through \`head -n 0\`, where it answered rc 141 with 0 B before."
  "bin/gitignore-secret-family-check|SURVIVES|BUILT THIS WAY (card#7036) — the same two mechanisms as the two fixed members above: \`trap '' PIPE\` as the first statement after \`set\`, and one tolerated write per stream of an already-built string. It ships correct rather than joining the roll below, deliberately: this is a SECURITY gate whose entire product is the rc plus a FINDINGS block on STDOUT, so a lost verdict is the gate reporting nothing while the invocation looks like it worked. Its VERDICT path is measured, not just \`--help\`: driven to a real UNCOVERED verdict it answers rc 1 through \`head -n 0\` AND \`head -1\`, under the default SIGPIPE disposition and under an inherited SIG_IGN, and its rc-2 refusal keeps its stderr through a truncating reader."
  "bin/board-stats|SURVIVES|NOT AT RISK — no errexit AND the report renders through child processes, so a killed child neither kills the shell nor is promoted into one. BOTH halves are load-bearing (see defect 2 in the header); adding \`set -e\` alone would move this to LOSES. Its verdict path was measured directly under card#6911: rc 1 and 150 B of stderr survive \`head -n 0\`, \`head -c 1\` and \`head -n 1\`."

  # ── KNOWN DEFECTS. Each is a live instance of card#6911 awaiting the two-mechanism fix. They
  # are listed rather than fixed here because each is a per-bin refactor (every write in the
  # file must be routed through one tolerated emitter), not an edit this card can land as a
  # batch — and a shared primitive is NOT available: `trap '' PIPE` must precede the lib source
  # to cover the lib-missing refusal, so it cannot live in `_kb-board-lib.sh`, and the two
  # standalone bins must not source the lib at all. Instance fixes append to card#6911.
  "bin/adopt-to-dl|LOSES|card#6911 instance — help path measured. Verdict path NOT separately driven."
  "bin/board-card-start|LOSES|card#6911 instance — help path measured. Verdict path NOT separately driven; this is a git-hook callee and fail-soft, so the rc it loses is mostly consumed by the hook."
  "bin/board-session-close|LOSES|card#6911 instance — help path measured. Verdict path NOT separately driven; its report is ~20 KB, well past the pipe buffer, so a pager or \`head\` on the real report is the LIKELIEST truncating reader in the toolkit."
  "bin/board-snapshot|LOSES|card#6911 instance — help path measured. Verdict path NOT separately driven; its terminal exit is 0, so what is lost is the success rc, not a refusal."
  "bin/dependabot-deploy-reconcile|LOSES|card#6911 instance — help path measured. Verdict path NOT separately driven; a known residual at rc 120 on the python side is recorded in the v0.27.0 CHANGELOG entry."
  "bin/dl-a0-backfill-triaged|LOSES|card#6911 instance — help path measured. Verdict path NOT separately driven; this is a board WRITER, so a lost rc is a write whose outcome the caller cannot read."
  "bin/dl-a1-register-field|LOSES|card#6911 instance — help path measured. Verdict path NOT separately driven; also a board writer."
  "bin/kbcard|LOSES|card#6911 instance — driven by the no-argument usage path (25 KB to stdout at rc 0). Verdict path NOT separately driven; this is the toolkit's most-piped tool and every board WRITE goes through it, so it is the highest-consequence member of the roll."
  "bin/promote-released-cards|LOSES|card#6911 instance — help path measured. Verdict path NOT separately driven; it prints a summary and then \`die\`s, which is the filed shape exactly, and it MOVES CARDS."
  "bin/release-artifacts-check|LOSES|card#6911 instance — help path measured. Verdict path NOT separately driven; it writes \`::error::\` annotations to STDOUT and then \`exit 1\`, so a truncating reader costs both the annotations and the gate's verdict."
  "bin/release-pr-body|LOSES|card#6911 instance — help path measured. Verdict path NOT separately driven."
  "bin/release-tag-check|LOSES|card#6911 instance — help path measured (rc 0, 6783 B; 141 under BOTH dispositions, because \`awk\` renders the help as a CHILD under errexit — row 2 of the mechanism table). Verdict path NOT separately driven: it polls a remote. Its \`::error::\` refusals are on STDERR, but its STDOUT carries the not-a-release rc-0 line and the 'must exist at <sha>' banner it prints BEFORE the first poll — so a truncating reader kills it at that banner, before it ever looks for the tag, and \`release-promote-cards\` gets a signal death in place of both answers."
)

# ── the undriven remainder ──────────────────────────────────────────────────────────────────
#
# "<relpath>|<why no network-free driver exists>". UNMEASURED, NOT CLEAN. Kept in the
# population and named, because a silent remainder means the loop stopped rather than finished.
UNDRIVEN=(
  "bin/_kb-board-lib.sh|A sourced library, not a tool: it has no argv surface (executing it is rc 126) and every byte it writes is written on behalf of a caller that is itself in this population."
  "bin/_shellcheck-pinned|It writes NOTHING to its own stdout on any path it controls — measured, not read: its five \`printf\`/\`echo\` sites are a \`die\` to stderr, a capture into a variable, a fetch notice to stderr, a pipe into \`sha256sum\`, and the banner to stderr. Every stdout byte a caller sees belongs to the analyser it \`exec\`s, so a measurement here would be of shellcheck, not of this file. And there is no network-free driver for even that: reaching the \`exec\` needs the PINNED analyser already present, otherwise it DOWNLOADS (\$SHELLCHECK_PIN_FILE=/nonexistent → rc 9, 0 B stdout; /dev/null → rc 9, 0 B) — which this gate scores UNREACHED and reds, correctly. A driver that only reaches its condition on a box with a warm cache is defect 1 in the header."
  "bin/agent-board-toolkit-drift-check|Refuses at rc 2 with its usage on STDERR before writing any stdout; it carries no --help, so no argv reaches a stdout write without giving it two real checkouts to diff."
  "bin/install-board-hooks|Same shape: rc 2 with usage on stderr, no --help. Its stdout paths all INSTALL into a repo, which a selftest must not do to an arbitrary tree."
  "bin/next-dl|Same shape: rc 2 with usage on stderr, no --help. Its stdout paths CONSUME a DL number from a live board counter."
  "hooks/agent-dispatch-card-start|A Claude Code hook: input is JSON on stdin, not argv, and a well-formed input calls \`kbcard move\` against a LIVE BOARD. Deliberately not executed here."
  "hooks/post-checkout|A git hook: input is git's three positional args, and the only non-trivial path shells out to board-card-start against a live board. It writes nothing to stdout on any path."
  "hooks/pre-push|A git hook: input is ref lines on stdin, so an unfed run blocks. It writes its advisory to stderr, never stdout."
)

# ── the measurement ─────────────────────────────────────────────────────────────────────────
#
# _measure <dir> <relpath> <argv…> → "<direct_rc> <direct_bytes> <dfl_rc> <ign_rc>"
#
# `head -n 0` exits before its first read, so the reader is provably gone by the time the
# writer's first byte is offered — which is what makes this deterministic rather than a race
# against the 64 KB pipe buffer (verified 60/60 on the four smallest-output members).
# `${PIPESTATUS[0]}` is the writer's own status; the pipeline's status is `head`'s and would
# report 0 for every member. Nothing here names a signal number.
#
# ⛔ THE `set +e` IS LOAD-BEARING, AND THIS FILE IS ITS OWN SUBJECT. Under `pipefail` the
# measurement pipeline's status IS the dying writer's — the very thing being measured — so
# errexit would kill this harness on exactly the members it exists to find. It happens not to
# fire while `_measure` is called from a command substitution, which is a context rule subtle
# enough that a later caller moving the call to statement position would take the suite out
# with no warning (measured: the identical pipeline at top level exits the shell at once).
# Suppressed explicitly rather than left to that accident. `|| true` would NOT do — `true` is
# itself a pipeline and resets `PIPESTATUS` before it can be read.
_measure() {
    local dir="$1" rel="$2"; shift 2
    local drc=0 bytes trc_dfl trc_ign
    # ⛔ THE ENV PREFIX IS A HOST-INDEPENDENCE FIX, NOT A CONVENIENCE (see DRIVER_ENV below).
    # `${DRIVER_ENV[$rel]}` is a deliberate word-split of a fixture's env assignments; empty for
    # every member that needs none, so `pre` stays empty and the invocation is unchanged.
    local -a pre=()
    # shellcheck disable=SC2206  # deliberate word-split of a space-separated env spec
    [[ -n "${DRIVER_ENV[$rel]:-}" ]] && pre=(env ${DRIVER_ENV[$rel]})
    "${pre[@]}" "$dir/$rel" "$@" >"$TMP/m.out" 2>/dev/null || drc=$?
    bytes="$(wc -c <"$TMP/m.out" | tr -d ' ')"
    # ⛔ `env`, NOT `trap`, AND THAT IS A MEASURED CORRECTION. The first cut of this pinned the
    # two legs with `trap - PIPE` / `trap '' PIPE` in a subshell. `trap '' PIPE` works; **`trap -
    # PIPE` DOES NOT** — POSIX and bash both specify that a signal IGNORED on entry to a
    # non-interactive shell cannot be trapped or reset, so from a CI runner (where Node has
    # already set SIG_IGN) the reset is a silent no-op and BOTH legs run under SIG_IGN. That is
    # defect 1 in this file's own header — a fixture that cannot reach the condition it tests —
    # and it was caught by the disagreement control below rather than by reading, which is
    # exactly what that control is for. `env --default-signal` sets the disposition in the
    # CHILD, after fork and before exec, where the shell's inherited-ignore rule does not apply.
    set +e
    # shellcheck disable=SC2086  # same deliberate word-split; one `env` carries both concerns
    trc_dfl="$( env --default-signal=PIPE ${DRIVER_ENV[$rel]:-} "$dir/$rel" "$@" 2>/dev/null | head -n 0 >/dev/null 2>&1; printf '%s' "${PIPESTATUS[0]}" )"
    # shellcheck disable=SC2086
    trc_ign="$( env --ignore-signal=PIPE  ${DRIVER_ENV[$rel]:-} "$dir/$rel" "$@" 2>/dev/null | head -n 0 >/dev/null 2>&1; printf '%s' "${PIPESTATUS[0]}" )"
    set -e
    printf '%s %s %s %s' "$drc" "$bytes" "$trc_dfl" "$trc_ign"
}

# _classify "<direct_rc> <bytes> <dfl_rc> <ign_rc>" → SURVIVES | LOSES | UNREACHED
# SAFE means safe under BOTH dispositions; one leg differing is enough to lose the verdict in
# the environment that leg names.
_classify() {
    local drc bytes dfl ign
    read -r drc bytes dfl ign <<<"$1"
    if [[ "$bytes" -eq 0 ]]; then printf 'UNREACHED'
    elif [[ "$dfl" == "$drc" && "$ign" == "$drc" ]]; then printf 'SURVIVES'
    else printf 'LOSES'; fi
}

_mktmp_scratch

# ── DRIVER_ENV: the host-independence fixture ───────────────────────────────────────────────
#
# ⛔ A DRIVER THAT READS THE INVOKING USER'S `$HOME` MEASURES THE BOX, NOT THE TOOL — and this
# gate shipped one. `bin/kbcard` was driven with no arguments, which on a developer box prints
# 25 394 B of usage at rc 0 and on a GitHub Actions runner exits **2 with 0 B of stdout**,
# because `kb_load_config` resolves `$HOME/.kanban-dev-board.env` BEFORE the no-argument help
# arm and refuses when it is absent. The gate therefore read LOSES locally and UNREACHED — a
# hard red, correctly — in CI, on the same commit. That is defect 1 in this file's header
# (a fixture that cannot reach the condition it tests) wearing a second skin: not the wrong
# payload, the wrong BOX. `kbcard --help` is no escape; every argv goes through the same
# resolver, measured.
#
# The fix is a PLANTED config, not a weaker assertion: three files no network is ever asked
# about, and the ambient overrides cleared so a box that HAS a real config gets the planted one
# too (an empty `KBCARD_BOARD_ENV`/`KANBAN_HOST_ENV` falls through to `$HOME`, which is the
# point). The token is a literal non-secret string; nothing here can reach a board, and the
# usage path this drives never consults any of it — it just has to get PAST the resolver.
KBHOME="$TMP/fakehome"; mkdir -p "$KBHOME"
printf 'KB_BOARD_ID=1\n'                                                  >"$KBHOME/.kanban-dev-board.env"
# KANBAN_EXPECTED_HOST is part of the planted config since card#7245: the resolver now refuses
# an api host nobody declared, so without it the driver would again fail BEFORE the usage write
# and this gate would read UNREACHED — the same wrong-box failure in a new coat. It names the
# loopback address this fixture already points at, and the `http://` there is the live witness
# that the preflight's predicate is the HOST alone and carries no scheme rule.
printf 'KBCARD_API=http://127.0.0.1:1/api\nKANBAN_EXPECTED_HOST=127.0.0.1\nKBCARD_TOKEN_FILE=%s\n' \
       "$KBHOME/.kanban-dev-token"                                        >"$KBHOME/.kanban-host.env"
printf 'not-a-real-token\n'                                               >"$KBHOME/.kanban-dev-token"
declare -A DRIVER_ENV=(
  ["bin/kbcard"]="HOME=$KBHOME KBCARD_BOARD_ENV= KANBAN_HOST_ENV= KBCARD_API= KBCARD_TOKEN_FILE= KANBAN_EXPECTED_HOST="
)

# ── the one hard prerequisite ───────────────────────────────────────────────────────────────
#
# FAIL CLOSED, LOUDLY. Without `env --default-signal` this file cannot pin the two dispositions
# and would measure the ambient one TWICE while reporting a two-disposition result — a clean
# answer over a population half of which was never measured, which is the failure this whole
# gate exists to make impossible. Refusing is the only honest option; skipping would ship the
# lie. GNU coreutils >= 8.31 (2019); ubuntu-latest, which CI runs, carries 9.x.
if ! env --default-signal=PIPE true 2>/dev/null || ! env --ignore-signal=PIPE true 2>/dev/null; then
    printf '%s\n' "verdict-through-truncating-reader-selftest: needs GNU coreutils env with --default-signal/--ignore-signal (>= 8.31); without it the two SIGPIPE dispositions cannot be pinned and every measurement below would silently be of the ambient one." >&2
    exit 1
fi

# ── controls: the mechanism table, planted and measured ─────────────────────────────────────
#
# The two assertions this gate ships over the real tree are equality assertions against a
# hand-written list, and a measurement harness that cannot distinguish the outcomes satisfies
# them while measuring nothing. So the five rows of the header's mechanism table are planted as
# fixtures FIRST and classified by the same code path that judges the tree. Each is a negative
# control for the others: if the classifier answered LOSES for everything, rows 3 and 5 red; if
# it answered SURVIVES for everything, rows 1, 2 and 4 red; if the presence witness were
# dropped, row 6 would read SURVIVES instead of UNREACHED. Rows 7/7b are not part of that
# matrix — they measure the fix's COST (the buffer's EXIT-trap obligation) rather than its
# benefit, and are asserted on stdout content rather than through `_classify`.
FIX="$TMP/fixture"; mkdir -p "$FIX/bin"
_plant() { printf '%s' "$2" >"$FIX/bin/$1"; chmod +x "$FIX/bin/$1"; }

# 1 — a BUILTIN write, no errexit anywhere. The row that killed the builtin-vs-external theory.
_plant planted-builtin-noerrexit '#!/usr/bin/env bash
printf "%s\n" $(seq 1 200000)
echo "VERDICT" >&2
exit 7
'
# 2 — a CHILD write under errexit: the child dies and errexit takes the shell with it.
_plant planted-child-errexit '#!/usr/bin/env bash
set -euo pipefail
seq 1 200000
echo "VERDICT" >&2
exit 7
'
# 3 — a CHILD write with NO errexit: board-stats. The parent outlives the killed child.
_plant planted-child-noerrexit '#!/usr/bin/env bash
seq 1 200000
echo "VERDICT" >&2
exit 7
'
# 4 — `trap '"'"'' PIPE` WITHOUT the tolerated write. The trap alone is NOT the fix: it converts
#     the kill into an errexit death at the write's own rc, which is a WRONG VERDICT rather
#     than a crash. This is why both mechanisms are asserted separately.
_plant planted-trap-only '#!/usr/bin/env bash
set -euo pipefail
trap "" PIPE
printf "%s\n" $(seq 1 200000)
echo "VERDICT" >&2
exit 7
'
# 5 — both mechanisms: the ratified fix shape.
_plant planted-trap-and-tolerated '#!/usr/bin/env bash
set -euo pipefail
trap "" PIPE
OUT="$(seq 1 200000)"
printf "%s\n" "$OUT" 2>/dev/null || true
printf "%s\n" "VERDICT" >&2 2>/dev/null || true
exit 7
'
# 6 — writes nothing to stdout. The presence witness must call this UNREACHED, never SURVIVES.
_plant planted-silent '#!/usr/bin/env bash
set -euo pipefail
echo "VERDICT" >&2
exit 7
'
# 7 / 7b — THE COST OF THE FIX, PLANTED. Rows 1–6 measure the fix's benefit; this pair measures
# what it takes away. The ratified shape emits ONE write per stream of an already-built string,
# which means the report is BUFFERED, which means an unexpected `set -e` death anywhere before
# the verdict prints NOTHING AT ALL and loses the diagnosis — a strictly worse failure than the
# progressive output it replaced. `agent-board-toolkit-runtime-check` answers that with
# `trap _flush EXIT`, and until now this file only ASSERTED that in prose: deleting the trap
# left both this gate and the class gate green, because neither drives a mid-run death. The
# pair below is the same claim as a measurement — 7 keeps the trap, 7b is 7 with the trap line
# removed and nothing else. Their stdout must DIFFER.
_plant planted-buffered-exit-trap '#!/usr/bin/env bash
set -euo pipefail
trap "" PIPE
BUF=""
_put()   { [ -z "$1" ] || printf "%s" "$1" 2>/dev/null || true; }
_flush() { _put "$BUF"; BUF=""; }
trap _flush EXIT
BUF="DIAGNOSIS-SO-FAR"
false
_flush
exit 7
'
_plant planted-buffered-no-trap '#!/usr/bin/env bash
set -euo pipefail
trap "" PIPE
BUF=""
_put()   { [ -z "$1" ] || printf "%s" "$1" 2>/dev/null || true; }
_flush() { _put "$BUF"; BUF=""; }
BUF="DIAGNOSIS-SO-FAR"
false
_flush
exit 7
'

echo "== controls: the planted mechanism table classifies as measured =="
eq "a BUILTIN write with no errexit loses the verdict"        "LOSES"     "$(_classify "$(_measure "$FIX" bin/planted-builtin-noerrexit)")"
eq "a CHILD write under errexit loses the verdict"            "LOSES"     "$(_classify "$(_measure "$FIX" bin/planted-child-errexit)")"
eq "a CHILD write with no errexit KEEPS it (board-stats)"     "SURVIVES"  "$(_classify "$(_measure "$FIX" bin/planted-child-noerrexit)")"
eq "\`trap '' PIPE\` ALONE still loses it (wrong verdict)"     "LOSES"     "$(_classify "$(_measure "$FIX" bin/planted-trap-only)")"
eq "trap PLUS a tolerated write keeps it (the fix shape)"     "SURVIVES"  "$(_classify "$(_measure "$FIX" bin/planted-trap-and-tolerated)")"
eq "a driver that wrote no stdout is UNREACHED, not SURVIVES" "UNREACHED" "$(_classify "$(_measure "$FIX" bin/planted-silent)")"

echo "== control: buffering owes an EXIT trap, and the trap is what pays it =="
# The ONE assertion in this file about a mid-run death rather than a truncating reader. It is
# here because the fix shape CREATED this obligation: rows 4 and 5 above are why the report is
# buffered at all. Asserted as a DIFFERENCE between two fixtures identical but for the trap
# line — an absence assertion alone ("the trap is present") would certify whatever replaced it.
_bt_out="$("$FIX/bin/planted-buffered-exit-trap" 2>/dev/null || true)"
_nt_out="$("$FIX/bin/planted-buffered-no-trap"   2>/dev/null || true)"
eq "with \`trap _flush EXIT\`, a mid-run death still delivers the buffer" "DIAGNOSIS-SO-FAR" "$_bt_out"
eq "…and WITHOUT it the same death delivers nothing at all"              ""                 "$_nt_out"
_btrc=0; "$FIX/bin/planted-buffered-exit-trap" >/dev/null 2>&1 || _btrc=$?
eq "…and the EXIT trap does not disturb the rc it exits with"            "1"                "$_btrc"

echo "== control: the kbcard driver measures the TOOL, not the box =="
# The pair that would have caught the shipped defect. The plant above is only worth having if
# its ABSENCE is visibly different, so both sides are driven here — with the ambient config
# denied, and with the planted one.
# ⚠ AND THIS CONTROL IS A CI-SIDE GUARD ONLY — measured, not assumed. Deleting `DRIVER_ENV`
# reds the SECOND leg on a bare box (3 checks fail, the CI failure reproduced) and reds
# NOTHING on a configured developer box, because the ambient config silently substitutes for
# the plant. The first leg passes either way; it forces its own empty `HOME`. That asymmetry —
# the box that runs the gate most often is the box that cannot see this regression — is
# precisely how the original defect survived a full review cycle, and it is why the claim
# above it is scoped to the signal axis rather than stated flat.
mkdir -p "$TMP/emptyhome"
# `:-` so that DELETING the plant reds this control as an ASSERTION rather than killing the run
# on `set -u` — a crash reports "something broke", an assertion reports which claim stopped
# holding, and this control's whole job is to name that claim.
_kb_planted="${DRIVER_ENV["bin/kbcard"]:-}"
DRIVER_ENV["bin/kbcard"]="HOME=$TMP/emptyhome KBCARD_BOARD_ENV= KANBAN_HOST_ENV= KBCARD_API= KBCARD_TOKEN_FILE="
eq "with NO board config the driver reaches no stdout write (the CI failure, reproduced)" \
   "UNREACHED" "$(_classify "$(_measure "$ROOT" bin/kbcard)")"
DRIVER_ENV["bin/kbcard"]="$_kb_planted"
eq "…and with the PLANTED one it reaches its usage write and is classifiable" \
   "LOSES"     "$(_classify "$(_measure "$ROOT" bin/kbcard)")"

echo "== control: the fix shape preserves a NON-ZERO verdict, not merely 'some rc' =="
# rc PRESERVATION is the assertion everywhere in this file; this pins that the preserved value
# is the tool's own verdict (7) and not a coincidence of two equal failures. Asserted on the
# measured triple rather than a signal number, so it reads identically under SIG_DFL and
# SIG_IGN — the CI disposition that makes an `rc == 141` assertion red (defect 3 in the header).
read -r _cdrc _cbytes _cdfl _cign <<<"$(_measure "$FIX" bin/planted-trap-and-tolerated)"
eq "the fixture's direct rc is its verdict"           "7"    "$_cdrc"
eq "…and the SIG_DFL truncated rc is the SAME verdict" "7"   "$_cdfl"
eq "…and the SIG_IGN one too (the CI disposition)"     "7"   "$_cign"
eq "…measured over a real payload, not an empty one"  "true" "$([[ "$_cbytes" -gt 100000 ]] && echo true || echo false)"

echo "== control: the two dispositions are really being pinned, and they DISAGREE =="
# If both legs silently ran under one disposition, every assertion above would still pass while
# half the measurement did not exist. The builtin/no-errexit fixture is the discriminator: the
# signal kills it, an ignored signal does not — so the two legs MUST differ on it. This is also
# the negative control for the pinning itself: it holds whichever disposition started this file.
read -r _bdrc _bbytes _bdfl _bign <<<"$(_measure "$FIX" bin/planted-builtin-noerrexit)"
eq "SIG_DFL kills the builtin writer (verdict lost)"      "false" "$([[ "$_bdfl" == "$_bdrc" ]] && echo true || echo false)"
eq "SIG_IGN does NOT (same bin, same driver, other rc)"   "true"  "$([[ "$_bign" == "$_bdrc" ]] && echo true || echo false)"
eq "…so the member is LOSES on the union of the two"      "LOSES" "$(_classify "$_bdrc $_bbytes $_bdfl $_bign")"

echo "== control: no assertion in this file expects a signal number =="
# Defect 3, guarded rather than promised: a later edit asserting the signal's rc would pass on
# a developer box and red in CI, where Node's inherited SIG_IGN turns the kill into EPIPE at
# rc 1 instead. The PREDICATE is deliberately narrower than "mentions the number" — it is the
# number AS A QUOTED LITERAL, which is the shape an `eq <label> <expected> <got>` expected value
# takes and the shape prose never does. A wider match would flag this file's own header, and a
# guard whose stated scope exceeds its actual predicate is the defect it is trying to prevent.
# The needle is BUILT AT RUNTIME so that this file does not contain it and cannot match itself.
SIGLIT="$(printf '"%d"' 141)"
_sigscan() { awk -v n="$SIGLIT" '!/^[[:space:]]*#/ && index($0, n) { print FNR ": " $0 }' "$1"; }

# Presence witness FIRST: the leg below is an ABSENCE assertion, and a scanner that matches
# nothing satisfies it perfectly. A planted positive proves it can fire.
printf '%s\n' '#!/usr/bin/env bash' "eq \"truncated rc\" $SIGLIT \"\$RC\"" >"$TMP/sigpositive"
eq "witness: the scan DOES find a planted signal-number assertion" "1" \
   "$(_sigscan "$TMP/sigpositive" | wc -l | tr -d ' ')"
printf '%s\n' '#!/usr/bin/env bash' '# a comment mentioning 141 is prose, not an assertion' \
                'eq "the rc is preserved" "$DIRECT" "$TRUNC"' >"$TMP/signegative"
eq "…and does NOT fire on prose or on an rc-preservation assertion" "0" \
   "$(_sigscan "$TMP/signegative" | wc -l | tr -d ' ')"

eq "assertion expecting a signal number (assert rc PRESERVATION instead)" "" \
   "$(_sigscan "$HERE/$(basename "${BASH_SOURCE[0]}")")"

# ── the denominator ─────────────────────────────────────────────────────────────────────────
#
# Printed on EVERY run, clean or not. A clean result over an unnamed population reports where
# the searcher stopped, not the state of the tree.
mapfile -t POP < <(_shipped_shell_files "$ROOT")

_keys() { printf '%s\n' "$@" | awk -F'|' 'NF { print $1 }' | LC_ALL=C sort -u; }
DRIVEN_KEYS="$(_keys "${DRIVERS[@]}")"
UNDRIVEN_KEYS="$(_keys "${UNDRIVEN[@]}")"
DISP_KEYS="$(_keys "${DISPOSITIONED[@]}")"
ACCOUNTED="$(printf '%s\n%s\n' "$DRIVEN_KEYS" "$UNDRIVEN_KEYS" | awk 'NF' | LC_ALL=C sort -u)"
POP_KEYS="$(printf '%s\n' "${POP[@]}" | awk 'NF')"

_count() { printf '%s\n' "$1" | awk 'NF' | wc -l | tr -d ' '; }

# Measure every driven member ONCE, here, so the denominator and the assertions below read the
# same numbers off the same runs.
declare -A MEASURED=() STATE=()
for d in "${DRIVERS[@]}"; do
    rel="${d%%|*}"; argv="${d#*|}"
    [[ -x "$ROOT/$rel" ]] || continue
    # shellcheck disable=SC2086  # argv is a deliberate word-split driver spec, empty = no args
    MEASURED["$rel"]="$(_measure "$ROOT" "$rel" $argv)"
    STATE["$rel"]="$(_classify "${MEASURED[$rel]}")"
done

echo "== denominator [verdict-through-truncating-reader/v1] =="
printf '  shipped shell files in the population (bin/ + hooks/)      : %s\n' "$(_count "$POP_KEYS")"
printf '  DRIVEN and measured this run                               : %s\n' "$(_count "$DRIVEN_KEYS")"
printf '  UNDRIVEN — unmeasured, not clean                           : %s\n' "$(_count "$UNDRIVEN_KEYS")"
printf '  unaccounted (in neither list)                              : %s\n' \
       "$(_count "$(LC_ALL=C comm -23 <(printf '%s\n' "$POP_KEYS") <(printf '%s\n' "$ACCOUNTED"))")"
printf '  measured SURVIVES / LOSES / UNREACHED                      : %s / %s / %s\n' \
       "$(printf '%s\n' "${STATE[@]}" | command grep -cx SURVIVES  || true)" \
       "$(printf '%s\n' "${STATE[@]}" | command grep -cx LOSES     || true)" \
       "$(printf '%s\n' "${STATE[@]}" | command grep -cx UNREACHED || true)"
printf '  per-member  direct_rc / stdout_bytes / trunc_rc@SIG_DFL / @SIG_IGN → state:\n'
for rel in $(printf '%s\n' "${!STATE[@]}" | LC_ALL=C sort); do
    read -r drc bytes dfl ign <<<"${MEASURED[$rel]}"
    printf '    %-40s %3s /%7s /%5s /%5s  → %s\n' "$rel" "$drc" "$bytes" "$dfl" "$ign" "${STATE[$rel]}"
done

# ── the assertions ──────────────────────────────────────────────────────────────────────────

echo "== the shared derivation still answers CI's own question =="
# `tests/_shipped-shell-lib.sh` restates `ci.yml`'s two find expressions, because a workflow
# `run:` string cannot source a bash lib — a restatement that can only be GUARDED, never
# deleted (canon #16). Without this leg, narrowing CI's expression would leave this gate (and
# any other adopter) measuring a population CI no longer analyses, silently.
#
# Controls FIRST — this is an ABSENCE assertion over a file, and a drift check that can never
# fire satisfies it perfectly. A tree with the expressions and one without are both planted.
_wfpos="$TMP/wf-ok"; mkdir -p "$_wfpos/.github/workflows"
printf '%s\n' "        run: shellcheck -S error \$($_SSL_FIND_SHIPPED; $_SSL_FIND_SELFTESTS)" \
  >"$_wfpos/.github/workflows/ci.yml"
_wfneg="$TMP/wf-drifted"; mkdir -p "$_wfneg/.github/workflows"
printf '%s\n' "        run: shellcheck -S error \$(find bin -maxdepth 1 -type f)" \
  >"$_wfneg/.github/workflows/ci.yml"
eq "witness: the drift check PASSES a workflow carrying both expressions" "" "$(_ci_shellcheck_drift "$_wfpos")"
eq "…and FIRES on a workflow that narrowed them"                          "2" \
   "$(_ci_shellcheck_drift "$_wfneg" | wc -l | tr -d ' ')"
eq "…and on a tree with no ci.yml at all (never silently clean)"          "1" \
   "$(_ci_shellcheck_drift "$TMP" | wc -l | tr -d ' ')"

eq "ci.yml no longer runs the expression this gate's population is derived from" "" \
   "$(_ci_shellcheck_drift "$ROOT")"

echo "== the population carries real data (control on the REAL tree) =="
eq "the bin/+hooks/ scan is non-empty" "false" "$([[ "${#POP[@]}" -eq 0 ]] && echo true || echo false)"
eq "…and every driver actually ran"    "true"  "$([[ "${#STATE[@]}" -eq "$(_count "$DRIVEN_KEYS")" ]] && echo true || echo false)"

echo "== every population member is DRIVEN or explicitly UNDRIVEN =="
eq "unaccounted shipped shell (add a DRIVERS entry, or an UNDRIVEN one with its reason)" "" \
   "$(LC_ALL=C comm -23 <(printf '%s\n' "$POP_KEYS") <(printf '%s\n' "$ACCOUNTED"))"
eq "listed member that is no longer in the population (drop the entry)" "" \
   "$(LC_ALL=C comm -13 <(printf '%s\n' "$POP_KEYS") <(printf '%s\n' "$ACCOUNTED"))"

echo "== every DRIVEN member has a disposition, and vice versa =="
eq "driven member with no disposition" "" \
   "$(LC_ALL=C comm -23 <(printf '%s\n' "$DRIVEN_KEYS") <(printf '%s\n' "$DISP_KEYS"))"
eq "disposition for a member that is not driven (drop the line)" "" \
   "$(LC_ALL=C comm -13 <(printf '%s\n' "$DRIVEN_KEYS") <(printf '%s\n' "$DISP_KEYS"))"

echo "== no driver measured nothing (the presence witness) =="
# UNREACHED here means the driver never reached a stdout write, so its SURVIVES/LOSES answer
# would be about a code path that did not run — the fixture defect this class was misdiagnosed
# by twice. It is never dispositionable.
unreached=""
for rel in "${!STATE[@]}"; do
    [[ "${STATE[$rel]}" == UNREACHED ]] && unreached+="$rel (wrote 0 bytes to stdout)"$'\n'
done
eq "driver reached no stdout write — fix the driver or move the member to UNDRIVEN" "" "${unreached%$'\n'}"

echo "== every measured outcome matches its disposition =="
# BOTH directions red. A LOSES member that starts surviving must have its line deleted, which
# is the ratchet: the known-defect roll can only shrink, and a fix cannot land silently.
mismatch=""
for d in "${DISPOSITIONED[@]}"; do
    rel="${d%%|*}"; rest="${d#*|}"; want="${rest%%|*}"
    got="${STATE[$rel]:-<not measured>}"
    [[ "$got" == "$want" ]] || mismatch+="$rel: dispositioned $want, measured $got"$'\n'
done
eq "measured outcome disagrees with its disposition" "" "${mismatch%$'\n'}"

echo "== every disposition and every UNDRIVEN entry carries a reason =="
noreason=""
for d in "${DISPOSITIONED[@]}"; do
    rest="${d#*|}"; [[ "${rest#*|}" != "$rest" && -n "${rest#*|}" ]] || noreason+="$d"$'\n'
done
for u in "${UNDRIVEN[@]}"; do
    [[ "$u" == *"|"* && -n "${u#*|}" ]] || noreason+="$u"$'\n'
done
eq "entry with no reason" "" "${noreason%$'\n'}"

echo "== no member is listed twice =="
dupes="$(printf '%s\n%s\n' "$(printf '%s\n' "${DRIVERS[@]}" "${UNDRIVEN[@]}" | awk -F'|' 'NF { print $1 }')" \
                            "" | awk 'NF' | LC_ALL=C sort | uniq -d)"
eq "duplicate population key" "" "$dupes"
dupd="$(printf '%s\n' "${DISPOSITIONED[@]}" | awk -F'|' 'NF { print $1 }' | LC_ALL=C sort | uniq -d)"
eq "duplicate disposition key" "" "$dupd"

_summary "verdict-through-truncating-reader-selftest"
