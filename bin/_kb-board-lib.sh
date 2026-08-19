# shellcheck shell=bash
# _kb-board-lib.sh — shared helpers for the agent-board-toolkit's OWN scripts.
#
# CO-VENDORED, not toolkit-only. Every lib-sourcing bin `source`s this as a sibling,
# so a vendor-by-copy consumer MUST copy it too.
#
# ⛔ THE SET IS DERIVED, NEVER LISTED — here or anywhere else. Name it for the version in
# your hand with:
#     grep -lE '^[[:space:]]*source "\$KB_LIB"' bin/*
# That is the same anchored pattern agent-board-toolkit-drift-check's MISSING-LIB probe
# uses, and tests/drift-check-fixture-selftest.sh asserts the pattern still matches a
# real sourcer and still misses a real standalone — so the derivation cannot rot silently
# while the checks keep passing. The FOUR prose lists it replaced (here, ADOPTION.md,
# INSTALL.md section 6b and UPGRADE.md section 3) are gone for cause, three times
# demonstrated: this copy once omitted adopt-to-dl and board-stats — and adopt-to-dl is a
# kb_parse_resp caller, so the omission was load-bearing; the newest bin to join the set,
# gh-code-search, reached only one of them, leaving the rest telling a vendoring consumer
# to copy a set without it; and the pass that deleted three of the four declared the class
# closed against a denominator it had inherited rather than re-derived, so UPGRADE.md
# section 3 — the standing re-vendor recipe INSTALL.md section 6b points at — survived,
# naming six bins while the derivation answered nine.
#
# THAT THIRD DEMONSTRATION IS WHY THIS NOW CARRIES A GATE and not a fifth careful edit:
# tests/lib-set-derivation-selftest.sh runs every published spelling of the derivation
# above against the tree and reds when one answers a different set — or nothing, which is
# how the release note for that pass shipped it, unescaped, matching 0 files — and reds
# when an instruction line ANYWHERE IN THE TREE names members of the set instead of
# deriving them. A list that must be re-synced by hand at every added bin IS the defect;
# a fifth copy would have minted it again, and a hand audit had already proved it can
# miss one. That gate itself shipped scoped to four hand-listed paths in its first
# attempt — the same defect one layer up, since a fifth surface then joined in silence —
# and its population is now derived from the tree on every run, minus a named
# version-history carve-out and a per-line disposition set the check asserts is still
# live. The reversal is recorded in docs/CONSOLIDATION-PLAN.md.
#
# Cited by ANCHOR TEXT, never by line — these four were line numbers and three had
# rotted: INSTALL.md by 62 lines, the drift check by 17, the
# CHANGELOG quote by ~390 (the reason is at fetch_board_cards's parse site below).
# ADOPTION.md has no numbered sections and its "§8" means the Task-tracking
# standard's §8:
#   ADOPTION.md § "Where this fits" — a PM project may vendor these tools; the
#     lib-sourcing bins require _kb-board-lib.sh copied beside them.
#   docs/INSTALL.md § "6b. Non-Actions consumer — vendor + drift-check" — same
#     requirement, with the failure mode.
#   bin/agent-board-toolkit-drift-check, the "MISSING-LIB" probe — flags a
#     lib-sourcing bin vendored without the lib.
#   docs/CHANGELOG.md, the v0.15.0 entry — "Consumers who vendor: re-vendor
#     `promote-released-cards` (#110, diagnostic-only) and `_kb-board-lib.sh`
#     (#103/#106)." (No "[vendor]" tag on it: the only two in that file are
#     v0.14.0's, both for promote-released-cards. v0.11.2/#74 established the
#     co-vendoring requirement itself.)
# (promote-released-cards is the standalone exception: it is vendored and must
# never source this.) This header claimed the opposite until 2026-07-15 — treat any
# change here as having consumer blast radius, because it does.
#
# It is sourced, never executed. It collapses the config-resolution, kanban-API curl
# wrapper, tolerant response parse, whole-board pagination, and DL-canonicalization
# logic that was copy-pasted across the lib-sourcing bins into one definition.
#
# Source it from a sibling toolkit script with:
#   source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/_kb-board-lib.sh"
#
# Conventions honored:
#   - API base ($KBCARD_API) is board-INDEPENDENT: host-level only
#     (~/.kanban-host.env, override $KANBAN_HOST_ENV). A board env that sets it is
#     refused, not honored — see kb_resolve_env.
#   - Board env is ~/.kanban-<name>-board.env; kanban|dev (and "no --board") map
#     to the kanban-dev board.
#   - Token file is $KBCARD_TOKEN_FILE (resolvable from inside a config file) or
#     ~/.kanban-dev-token.

if [[ -n "${_KB_BOARD_LIB_LOADED:-}" ]]; then return 0; fi
_KB_BOARD_LIB_LOADED=1

# Message prefix; a script may set KB_PROG, else its own basename is used.
_kb_prog() { printf '%s' "${KB_PROG:-${0##*/}}"; }

# --- ASCII-safe pattern matching --------------------------------------------
#
# WHY THESE EXIST — the non-obvious constraint. A bracket RANGE in a bash pattern
# (`[[ $x =~ [0-9] ]]`, and glob `case` arms alike) is a COLLATION range, not an
# ASCII range: it means "every character that sorts between these two in the
# CURRENT locale". Under an ordinary en_US.UTF-8 developer shell — measured on the
# reference host — `^[0-9]+$` matches U+0663 ARABIC-INDIC DIGIT THREE and
# `^[A-Za-z0-9_-]+$` matches é, Ⅳ and ﬁ; the same patterns reject all four under
# LC_ALL=C. Writing the class out longhand (`[0123456789]`) fixes it, but only
# where the class is short enough to stay readable, and it cannot be spelled at all
# for a pattern that arrives in a variable. A POSIX class is NOT the fix:
# `[[:alnum:]]` is locale-defined by construction, and `[[:digit:]]` is ASCII only
# because glibc happens to define it so. Matching under LC_ALL=C is what makes a
# class mean what every reader — and every error message quoting it — already
# thinks it says.
#
# WHAT THIS IS AND IS NOT. It is a MECHANISM (what "digit" means), so it belongs in
# the primitive; the POLICY on a refusal — die, warn, fall back, return an rc —
# stays at each caller, unchanged (docs/CONSOLIDATION-PLAN.md ground rule 5).
#
# kb_ere_match <string> <ere>: `[[ string =~ ere ]]` with ASCII bracket semantics.
# LC_ALL is `local`, so the C locale covers exactly this match and is restored on
# return; BASH_REMATCH is deliberately NOT local, so a caller's captures survive.
kb_ere_match() { local LC_ALL=C; [[ "$1" =~ $2 ]]; }

# kb_is_uint <string>: true iff the string is a non-empty run of ASCII digits.
# The shape behind most `^[0-9]+$` guards in these tools.
kb_is_uint() { kb_ere_match "${1-}" '^[0-9]+$'; }

# --- config resolution ------------------------------------------------------
#
# ONE token-file precedence, uniform across every resolver below:
#     a BOARD env's KBCARD_TOKEN_FILE > the HOST env's > an ambient one > ~/.kanban-dev-token
# It falls out of SOURCE ORDER (host first, board second) rather than a ladder of
# explicit tests. KBCARD_API is the mirror image — board-independent, host env only.

# kb_resolve_env <board_env_path>: source the host env then the board env, and
# publish KB_API / KB_BOARD_ID / KB_TOKEN_FILE / KB_BOARD_ENV. Does NOT read the
# token content and does NOT require KB_BOARD_ID — the caller decides those. Quiet
# (return-code only) apart from the rc-4 refusal, so a fail-soft caller can craft its
# own message. Returns:
#   0 ok   2 env unreadable   3 KBCARD_API unset   4 board env sets KBCARD_API
#   5 token file unreadable
kb_resolve_env() {
    local board_env="$1"
    [[ -r "$board_env" ]] || return 2
    local host_env="${KANBAN_HOST_ENV:-$HOME/.kanban-host.env}"
    # Snapshot the AMBIENT values, then clear them so the two sources below reveal only what
    # THEY set. Both are restored before every return: sourcing mutates the caller's shell, so
    # without this a second kb_resolve_env call in one shell would read the FIRST board's
    # values as its ambient tier and hand board B board A's token. Clearing without snapshotting
    # would be worse than the leak — it would silently delete the documented ambient tier.
    local amb_api="${KBCARD_API:-}" amb_tok="${KBCARD_TOKEN_FILE:-}"
    unset KBCARD_TOKEN_FILE
    # HOST first, BOARD second. This restores the pre-v0.8.2 order (v0.8.1:kbcard:440,
    # "so a config-file KBCARD_TOKEN_FILE is honored"): the board env is sourced LAST,
    # so its KBCARD_TOKEN_FILE wins — which is the whole point of a per-board token.
    # The v0.8.2 lib extraction collapsed six divergent copies onto the two that had
    # the order backwards, silently regressing it (#4325).
    # Sourcing the host env is NOT gated on KBCARD_API: that gate conflated "is the API
    # already known" with "should the host's other vars load", so a stray ambient
    # KBCARD_API also dropped the host's KBCARD_TOKEN_FILE. Precedence is preserved
    # explicitly instead — an ambient API still beats the host's.
    # shellcheck disable=SC1090
    [[ -r "$host_env" ]] && source "$host_env"
    local eff_api="${amb_api:-${KBCARD_API:-}}"
    unset KBCARD_API   # so the board source below reveals a BOARD-set value
    # shellcheck disable=SC1090
    source "$board_env"
    local board_api="${KBCARD_API:-}" cfg_tok="${KBCARD_TOKEN_FILE:-}"   # cfg_tok: board's, else host's
    # Restore both before any return — never leave a caller's env mangled.
    export KBCARD_API="$eff_api"
    KBCARD_TOKEN_FILE="$amb_tok"
    if [[ -n "$board_api" ]]; then
        # Refuse LOUD rather than ignore: the API base is board-independent, so a board
        # env setting it means the operator believes something false about their config.
        echo "$(_kb_prog): KBCARD_API is board-independent and is not read from a board env — remove it from $board_env and set it once in ~/.kanban-host.env (docs/INSTALL.md §3)" >&2
        return 4
    fi
    KB_API="$eff_api"
    [[ -n "$KB_API" ]] || return 3
    KB_BOARD_ID="${KB_BOARD_ID:-}"
    KB_TOKEN_FILE="${cfg_tok:-${amb_tok:-$HOME/.kanban-dev-token}}"   # board > host > ambient > default
    KB_BOARD_ENV="$board_env"
    [[ -r "$KB_TOKEN_FILE" ]] || return 5
    return 0
}

# _kb_discovered_boards: the board NAMEs derived from every ~/.kanban-<name>-board.env present
# on this box (comma-separated, on stdout; empty when none exist). Used only to make the
# board-env-missing error self-describing — showing the operator the boards that DO exist turns
# a bare invocation on a non-`dev` box from "tool broken" into an obvious next step.
_kb_discovered_boards() {
    local envf name out=""
    for envf in "$HOME"/.kanban-*-board.env; do
        [[ -e "$envf" ]] || continue          # literal glob when none match → skip
        name="${envf##*/.kanban-}"; name="${name%-board.env}"
        out+="${out:+, }${name}"
    done
    printf '%s' "$out"
}

# kb_board_roster: the boards this box knows about, one `<name><TAB><label>` line per board,
# in roster order. The roster file is ~/.kanban-snapshot-boards (override
# $KANBAN_SNAPSHOT_BOARDS): one `<name>:<label>` per line, `#` comments and blank lines
# skipped, a line with no `:` taking its name as its label. Whitespace inside a NAME is
# stripped (it resolves to a filename); a label is taken verbatim after the first `:`.
#
# When the roster file is absent, unreadable, or holds no usable line, it falls back to
# DISCOVERY — every ~/.kanban-<name>-board.env present, label = name — so a box that never
# wrote a roster reports on the boards it actually has rather than on nothing.
#
# board-snapshot IS NOT YET A CALLER, and that is a deliberate open item rather than an
# oversight: its main block carries the original inline copy of this PARSER (this function is
# that block, unchanged in behavior), but its fallback is a different one — two hardcoded
# board names kept for back-compat — so adopting this there changes what a roster-less box
# renders at SessionStart, which is a decision and not a cleanup. Its OUTPUT also differs:
# this function emits `<name><TAB><label>` (a board name, which resolves to an env file),
# while board-snapshot's inline block emits `<envfile><TAB><label>` — so adopting it there is
# a call-site change too, not a drop-in. Until that decision is made, a parser fix landing here
# must be carried across by hand. The open item is recorded in
# docs/CONSOLIDATION-PLAN.md (post-program dispositions), which owns it.
kb_board_roster() {
    local rosterf="${KANBAN_SNAPSHOT_BOARDS:-$HOME/.kanban-snapshot-boards}"
    local line name label envf n=0
    if [[ -r "$rosterf" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line#"${line%%[![:space:]]*}"}"   # ltrim
            [[ -z "$line" || "$line" == \#* ]] && continue
            name="${line%%:*}"
            label="${line#*:}"
            [[ "$label" == "$line" ]] && label="$name"   # no colon ⇒ label = name
            name="${name//[[:space:]]/}"
            [[ -z "$name" ]] && continue
            printf '%s\t%s\n' "$name" "$label"
            n=$((n + 1))
        done < "$rosterf"
    fi
    [[ "$n" -gt 0 ]] && return 0
    for envf in "$HOME"/.kanban-*-board.env; do
        [[ -e "$envf" ]] || continue          # literal glob when none match → skip
        name="${envf##*/.kanban-}"; name="${name%-board.env}"
        printf '%s\t%s\n' "$name" "$name"
    done
    return 0
}

# kb_load_config [board_name]: public config entry for the name-driven scripts
# (kbcard, dl-a0, dl-a1). Maps the --board NAME to its board env, resolves
# api/board/token, and reads the token into KB_TOKEN. An empty NAME means "no
# --board given" and honors $KBCARD_BOARD_ENV (back-compat); kanban|dev resolves
# the kanban-dev board; any other name → ~/.kanban-<name>-board.env. On failure
# prints the cause and returns 2 (KB_BOARD_ID is published but not required).
kb_load_config() {
    local name="${1:-}"
    local board_env
    case "$name" in
        "")         board_env="${KBCARD_BOARD_ENV:-$HOME/.kanban-dev-board.env}" ;;
        kanban|dev) board_env="$HOME/.kanban-dev-board.env" ;;
        *)          board_env="$HOME/.kanban-${name}-board.env" ;;
    esac
    local rc
    kb_resolve_env "$board_env"; rc=$?
    case "$rc" in
        0) ;;
        2)  # unreadable board env — name the fix like the sibling arms do (roundtable #89)
            echo "$(_kb_prog): board env file not readable: $board_env" >&2
            if [[ -z "$name" ]]; then
                echo "$(_kb_prog):   → no --board given and no default board configured; pass --board <name>, or set KBCARD_BOARD_ENV to your primary board's env file (see agent-board-toolkit docs/INSTALL.md)" >&2
            else
                echo "$(_kb_prog):   → board '$name' has no env file; create $board_env, or pass a --board <name> that exists (see agent-board-toolkit docs/INSTALL.md)" >&2
            fi
            local found; found="$(_kb_discovered_boards)"
            if [[ -n "$found" ]]; then
                echo "$(_kb_prog):   boards found on this box: $found" >&2
            else
                echo "$(_kb_prog):   no ~/.kanban-*-board.env files found on this box" >&2
            fi
            return 2 ;;
        3) echo "$(_kb_prog): KBCARD_API not set — create ~/.kanban-host.env (see agent-board-toolkit docs/INSTALL.md)" >&2; return 2 ;;
        4) return 2 ;;   # kb_resolve_env already named the file and the fix
        5) echo "$(_kb_prog): token file not readable: $KB_TOKEN_FILE" >&2; return 2 ;;
        *) echo "$(_kb_prog): config error ($rc) for $board_env" >&2; return 2 ;;
    esac
    KB_TOKEN="$(cat "$KB_TOKEN_FILE")"
    return 0
}

# kb_load_host_env: the lighter resolver for scripts whose board id comes from
# somewhere other than a --board name (board-snapshot iterates every board env;
# board-card-start reads the repo's config). Sources ONLY the host env and publishes
# KB_API (may be empty) + KB_HOST_TOKEN_FILE — the host-level token default that the
# caller layers a per-board override over. Reads NO token, so it CANNOT fail and has
# no return-code contract; the caller reads its token with kb_read_token once it knows
# which board it wants.
#
# It replaced kb_load_host_token's gated/unconditional mode flag: the two modes only
# ever differed because the gate conflated "source the host env" with "let the host's
# KBCARD_API win". Separating those makes one behavior serve both callers — and fixes
# the gated bug where a stray ambient KBCARD_API skipped the host env entirely, silently
# dropping the host's KBCARD_TOKEN_FILE (board-snapshot was the only gated caller, and
# so the only tool affected).
kb_load_host_env() {
    local amb_api="${KBCARD_API:-}"
    local host_env="${KANBAN_HOST_ENV:-$HOME/.kanban-host.env}"
    # shellcheck disable=SC1090
    [[ -r "$host_env" ]] && source "$host_env"
    KB_API="${amb_api:-${KBCARD_API:-}}"   # an ambient API still beats the host's
    KB_HOST_TOKEN_FILE="${KBCARD_TOKEN_FILE:-}"
    return 0
}

# kb_board_env_for <board_id>: the ~/.kanban-*-board.env whose KB_BOARD_ID is
# <board_id>, on stdout; returns 1 when none matches. Each candidate is sourced in a
# SUBSHELL: a board env must never leak vars into the caller — KANBAN_EXPECTED_HOST
# and KBCARD_TOKEN_FILE are read by the caller's own token guards, and a file being
# inspected must not be able to move the guard that bounds it.
kb_board_env_for() {
    local want="$1" match="" n=0 envf
    for envf in "$HOME"/.kanban-*-board.env; do
        [[ -r "$envf" ]] || continue
        # unset KB_BOARD_ID first: a value inherited from the caller would let an env
        # that sets no KB_BOARD_ID at all false-match every lookup. 2>/dev/null so a
        # board env missing the key stays quiet here rather than emitting raw noise.
        # shellcheck disable=SC1090
        if ( unset KB_BOARD_ID; . "$envf" 2>/dev/null; [ "${KB_BOARD_ID:-}" = "$want" ] ); then
            match="$envf"; n=$((n+1))
        fi
    done
    # Which duplicate wins is arbitrary either way; that it is SILENT is the defect.
    [[ "$n" -gt 1 ]] && echo "$(_kb_prog): ⚠ $n board envs set KB_BOARD_ID=$want — using $match; remove the stale one" >&2
    [[ -n "$match" ]] || return 1
    printf '%s' "$match"
}

# kb_board_env_get <board_env_path> <VAR>...: the value THIS board env gives each named
# var, one per line, in the order asked; empty for one it does not set. Takes the env PATH
# rather than a board id so a caller needing several things from one env (board-card-start
# wants the token AND the stage ids) resolves it ONCE via kb_board_env_for — two matchers
# are free to disagree about which file wins on a duplicate KB_BOARD_ID.
#
# Every requested var is UNSET before the source. This is load-bearing, not hygiene: board
# envs `export` their keys (see examples/kanban-board.env.example), so in an operator shell
# that sourced one board's env, that board's values are already in the environment of every
# tool. Without the unset, a board env that omits an OPTIONAL key (KB_STAGE_HELD, or its
# own KBCARD_TOKEN_FILE) silently inherits the *other* board's value and reports it as its
# own — the same false-read kb_board_env_for's `unset KB_BOARD_ID` prevents.
#
# NEWLINE-delimited, one value per line — never a space-separated tuple, where an empty
# optional field silently SHIFTS every later value left. The trailing '.' sentinel exists
# only so a caller's `$(…)` cannot strip a trailing empty value; it is never read.
kb_board_env_get() {
    local envf="$1"; shift
    (
        local v
        for v in "$@"; do unset "$v"; done
        # shellcheck disable=SC1090
        . "$envf" 2>/dev/null
        for v in "$@"; do printf '%s\n' "${!v:-}"; done
        printf '.\n'
    )
}

# kb_read_token <token_file>: read the bearer token into KB_TOKEN (+ KB_TOKEN_FILE).
# Returns 1 rather than exiting when the file is unreadable — every caller is fail-soft
# and words its own message.
kb_read_token() {
    [[ -r "$1" ]] || return 1
    KB_TOKEN="$(cat "$1")"
    KB_TOKEN_FILE="$1"
    return 0
}

# --- kanban API wrappers ----------------------------------------------------
# Both wrappers use globals KB_API + KB_TOKEN and set KB_HTTP to the status of
# the last call. -sS (not -f) so a 4xx/5xx body is captured and the status is
# inspectable. 2>&1 folds curl's own error text into the captured output so a
# transport failure is logged/visible.
KB_HTTP=""

# kb_auth_header <token>: emit the Authorization header line (no trailing newline)
# for feeding to curl OUT-OF-BAND via a stdin herestring — `curl -H @- … <<<"$(kb_auth_header
# "$tok")"`. The bearer token must never be an argv token: curl's argv is world-readable via
# `ps aux` / /proc/<pid>/cmdline on a multi-user host, so a `-H "Authorization: Bearer $tok"`
# would leak it. The herestring keeps the token off argv AND (unlike a `-H @<(…)` process
# substitution) redirects a regular temp file onto fd 0 rather than a /dev/fd named pipe, so it
# also works on native mingw64/Git-Bash curl where the process-sub fd can't be opened (#34).
kb_auth_header() { printf 'Authorization: Bearer %s' "$1"; }

# kb_require_value <flag> <value>: returns 1 (with a diagnostic) unless a value-taking
# option was given a non-empty value. Callers pass `"$1" "${2:-}"` from the arg loop.
#
# WHY THIS EXISTS. An option that consumes "$2" and is later dispatched with `[[ -n "$var" ]]`
# treats an explicitly-EMPTY value as an ABSENT flag, so `--flag ""` silently selects the
# default path instead of doing what was asked. The unexpanded shell variable is the common
# way in: `--dl "$DL"` with DL unset stamps nothing and still exits 0, so a card that should
# carry a correlation ref silently doesn't — and never promotes at release. In
# promote-released-cards the same shape disabled the anti-resurrection guard while printing a
# summary identical to a guarded run (card#5144, its own mirrored copy). None of these flags
# has a meaningful empty value: an intentional clear is a SPELLED sentinel, as `--swimlane
# none` already is. Dispatching on the FLAG being seen rather than on its VALUE being
# non-empty is what the guard restores.
#
# It also converts a trailing flag with no argument at all — `kbcard patch --task 5 --dl` —
# from a bare `set -u` unbound-variable error naming nothing into a diagnostic naming the flag.
#
# (promote-released-cards carries an inline mirror of this — it is vendored standalone and
# must not source this lib; keep the two in sync, as with kb_require_https_host.)
kb_require_value() {
    [[ -n "${2:-}" ]] && return 0
    echo "$(_kb_prog): $1 requires a non-empty value" >&2
    return 1
}

# kb_require_positional <slot> <arg> <name> [suffix]: the POSITIONAL-axis twin of
# kb_require_value. Returns 1 with a diagnostic when <arg> is empty, or when <slot> — the
# destination variable's CURRENT value — is already set, i.e. <arg> is a SECOND positional.
# <name> is the placeholder as the usage line spells it (`<card-id>`); [suffix] is appended to
# every diagnostic, for a caller whose refusals carry a standing qualifier.
#
# THE CALLER OWNS THE EXIT STATUS, and its own usage line. board-card-start refuses at 0 — it
# runs from a git hook and must never block a checkout (docs/HOOKS.md) — while adopt-to-dl,
# install-board-hooks and kbcard are ordinary CLIs and refuse at 2. An owner that also owned the exit
# would have to pick one and break the other, so it answers the QUESTION and leaves the POLICY
# at the call site, the same split promote-released-cards documents for its own guards.
#
# WHY <slot> IS THE DESTINATION VARIABLE and not a seen-flag: rejecting an EMPTY positional
# outright rather than storing it is exactly what makes `-n "$slot"` a sound "have I seen
# one?". While an empty was invisible to that test, `adopt-to-dl "" 4242` silently adopted
# 4242 though the caller had written two positionals. install-board-hooks tried a separate
# seen-flag and removed it: with empties refused here nothing could reach it, and a mutation
# of it could not be made to fail.
#
# NOT MERGEABLE WITH kb_require_value despite the twin naming. Inside a function `$#` is the
# FUNCTION's arity, and kb_require_value's 1-arg shape is contracted with the OPPOSITE answer
# (`kb_require_value --dl` → rc 1, asserted in tests/kb-board-lib-selftest.sh). The flag-value
# axis and the positional axis need opposite verdicts on the same input shape.
#
# EMPTY IS TESTED FIRST, deliberately: all three call sites tested it first before this hoist,
# so "slot already full AND arg empty" still reports the EMPTY. Reordering would be a silent
# user-visible change on a case nobody would have thought to test.
#
# (install-board-hooks carries an inline mirror of this — it is vendored standalone and does
# not source this lib; keep the two in sync, as with kb_require_https_host.
# tests/kb-positional-guard-selftest.sh runs one assertion matrix against BOTH copies.)
kb_require_positional() {
    local slot="$1" arg="$2" name="$3" suffix="${4:-}"
    if [[ -z "$arg" ]]; then
        echo "$(_kb_prog): $name is empty (an unexpanded variable?)$suffix" >&2
        return 1
    fi
    if [[ -n "$slot" ]]; then
        echo "$(_kb_prog): unexpected extra argument: $arg$suffix" >&2
        return 1
    fi
    return 0
}

# kb_require_https_host <api_base>: fail-closed guard for a CONFIG-supplied API base
# (the .release-pr.json .promote.api_base, which a PR can edit). Asserts the base is
# https:// AND its host is the expected host or a subdomain of it — so a malicious
# api_base pointed at an attacker host cannot exfiltrate the bearer token (#3570). The
# expected host is $KANBAN_EXPECTED_HOST — REQUIRED, no baked default: this toolkit is
# vendored by operators on their own kanban hosts, so there is no host to safely assume.
# If it is unset/empty the guard fails CLOSED (returns 1) and the caller MUST NOT send the
# token. Host is parsed per RFC 3986 — the authority ends at the FIRST of '/', '?' or '#',
# then userinfo before the last '@' is stripped, then :port — so none of
# `https://good.host@evil/` (→ evil), `https://good.host.evil/`, or the delimiter splits
# below slip through. Prints a diagnostic and returns 1 on violation.
# (promote-released-cards carries an inline mirror of this — it is vendored standalone
# and must not source this lib; keep the two in sync, INCLUDING this required-var check.)
# The parser MUST agree with curl about where the authority ends. It once terminated the
# authority at '/' ALONE, so `https://evil.example#@good.host` left the fragment in the
# string, the userinfo strip took everything after the LAST '@', and the guard read the
# host as `good.host` and ACCEPTED — while curl discarded the fragment and sent the bearer
# token to evil.example. A '?' did the same via the query. Any future edit here must keep
# the hostile-URL matrix in tests/kb-board-lib-selftest.sh green: a guard that parses a URL
# differently from the client that fetches it is an exfiltration primitive, not a guard.
kb_require_https_host() {
    local api="$1"
    local expect="${KANBAN_EXPECTED_HOST:-}"
    if [[ -z "$expect" ]]; then
        echo "$(_kb_prog): KANBAN_EXPECTED_HOST must be set to the expected api host before sending the writeback token; refusing to send" >&2
        return 1
    fi
    case "$api" in
        https://*) ;;
        *) echo "$(_kb_prog): refusing to send token — api_base is not https:// ($api)" >&2; return 1 ;;
    esac
    local host="${api#https://}"
    host="${host%%[/?#]*}"   # authority ends at the FIRST of / ? # (RFC 3986) — not '/' alone
    host="${host##*@}"       # strip userinfo — host is after the last '@' (RFC 3986)
    host="${host%%:*}"       # strip :port
    if [[ -n "$host" && ( "$host" == "$expect" || "$host" == *".$expect" ) ]]; then
        return 0
    fi
    echo "$(_kb_prog): refusing to send token — api_base host '$host' is not '$expect' (or a subdomain of it); KANBAN_EXPECTED_HOST is the expected host" >&2
    return 1
}

# kb_api <method> <path> [body]: fail-closed. Prints the response body on a 2xx
# and returns 0; on a non-2xx or transport failure prints a diagnostic to stderr
# and returns 1 (no body on stdout). Knobs (set by the caller):
#   KB_LOG_FILE   append a failure line to this file (kbcard's failure log).
#   KB_API_ERRBODY=1  also echo the error response body to stderr (kbcard).
#   KB_API_QUIET=1    suppress the non-2xx stderr line (dl-a1, which lets its
#                     callers print their own FATAL message); transport failures
#                     are still reported.
#   KB_CURL_MAX_TIME  cap EACH request at N seconds (curl --max-time). Unset = no
#                     cap, so every existing caller is byte-for-byte unaffected
#                     (nothing in this repo sets it but board-snapshot, and it is
#                     never exported).
#                     This is the SAME knob fetch_board_cards honors, and it must
#                     stay that way: a caller has no way to tell which lib function
#                     it reached. When only one of the two honored it, a bounded
#                     paginated read sat beside an unbounded single read under one
#                     knob that looked global — the cap silently did not apply, and
#                     the hang it exists to prevent came back via the sibling.
#                     ⚠ It caps WRITES too, and the parity argument does NOT carry
#                     there: a timed-out POST/PATCH is AMBIGUOUS (the server may
#                     have committed it) yet kb_api returns 1, so a non-idempotent
#                     retry can duplicate a card or burn a DL number. Set it around
#                     a read; do NOT export it process-wide over the bins that WRITE
#                     through this lib — enumerated, not recalled:
#                       kbcard                 POST + PATCH
#                       dl-a0-backfill-triaged PATCH
#                       dl-a1-register-field   POST + PATCH, and the sole
#                                              kb_api_status caller
#                     (next-dl and adopt-to-dl are not themselves on that list:
#                     next-dl's dl-sequence claim is a raw curl outside this lib, so
#                     the knob never reaches it. adopt-to-dl stamps via a `kbcard`
#                     SUBPROCESS, so an EXPORTED cap DOES reach that write — through
#                     kbcard above, which is why exporting is the thing warned
#                     against. It does not burn a DL there: adopt-to-dl surfaces the
#                     minted DL BEFORE the write for exactly this reason, and the
#                     documented retry `--dl N` re-stamps idempotently. What you get
#                     is an ambiguous stamp to resolve by hand — bad, not corrupting.)
#                     ⚠ It bounds a REQUEST, not a caller's total runtime. N
#                     requests can still take N×cap — board-snapshot's cap does not
#                     by itself keep it inside the SessionStart hook timeout.
kb_api() {
    local method="$1" path="$2" body="${3:-}"
    local args=(-sS -X "$method" -H "Accept: application/json")
    [[ -n "${KB_CURL_MAX_TIME:-}" ]] && args+=(--max-time "$KB_CURL_MAX_TIME")
    [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" --data "$body")
    local out
    # Auth fed via stdin herestring (-H @- <<<) so the token never enters argv (#3569) AND
    # the call is portable: a herestring redirects a regular temp file onto fd 0, avoiding the
    # /dev/fd process-substitution path that native mingw64/Git-Bash curl can't open (#34).
    out="$(curl "${args[@]}" -H @- -w $'\n__HTTP__%{http_code}' "$KB_API$path" 2>&1 <<<"$(kb_auth_header "$KB_TOKEN")")" || {
        [[ -n "${KB_LOG_FILE:-}" ]] && echo "$(date -u +%FT%TZ) $method $path FAILED-CURL $out" >> "$KB_LOG_FILE"
        echo "$(_kb_prog): curl failed on $method $path" >&2
        KB_HTTP="000"; return 1
    }
    KB_HTTP="${out##*__HTTP__}"
    local resp="${out%__HTTP__*}"
    if [[ ! "$KB_HTTP" =~ ^2 ]]; then
        [[ -n "${KB_LOG_FILE:-}" ]] && echo "$(date -u +%FT%TZ) $method $path HTTP-$KB_HTTP $resp" >> "$KB_LOG_FILE"
        [[ "${KB_API_QUIET:-}" == 1 ]] || echo "$(_kb_prog): HTTP $KB_HTTP on $method $path" >&2
        [[ "${KB_API_ERRBODY:-}" == 1 ]] && echo "$resp" >&2
        return 1
    fi
    printf '%s' "$resp"
}

# kb_api_status <method> <path> [body]: status-exposing variant. Emits
# "<http>\n<body>" to stdout and ALWAYS returns 0, so a caller capturing the
# output via $() can branch on the EXACT status (e.g. dl-a1's idempotent
# 409/422 = already-registered) — a status the kb_api global can't carry across
# a command substitution. A transport failure yields http "000".
kb_api_status() {
    local method="$1" path="$2" body="${3:-}"
    local args=(-sS -X "$method" -H "Accept: application/json")
    # Honors KB_CURL_MAX_TIME for the same reason kb_api and fetch_board_cards do:
    # the knob means one thing across every fetcher in this lib, because a caller
    # cannot tell which one it reached. This is the THIRD — a parity claim that
    # covers two of three is just a wrong claim.
    [[ -n "${KB_CURL_MAX_TIME:-}" ]] && args+=(--max-time "$KB_CURL_MAX_TIME")
    [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" --data "$body")
    local out
    # Auth via stdin herestring (-H @- <<<) — token stays out of argv (#3569) + portable
    # (no /dev/fd process-sub dependency that breaks native mingw64 curl, #34).
    out="$(curl "${args[@]}" -H @- -w $'\n__HTTP__%{http_code}' "$KB_API$path" 2>&1 <<<"$(kb_auth_header "$KB_TOKEN")")" || { printf '000\n%s' "$out"; return 0; }
    KB_HTTP="${out##*__HTTP__}"
    printf '%s\n%s' "$KB_HTTP" "${out%__HTTP__*}"
}

# kb_parse_resp <response> [jq-opt…] <jq-filter>: the filter applied to a response body,
# printing NOTHING when that body is not JSON at all instead of dying on jq's parse error.
#
# kb_api decides success on the HTTP STATUS CLASS alone, so a 2xx carrying a proxy's HTML error
# page or a truncated read arrives at every projection in every one of these tools as a success.
# An unguarded `jq` there exits 5 under `set -e`, with jq's raw parse error as the caller's whole
# diagnostic — a status these tools document nowhere, from a program the caller never ran.
# Swallowing the parse failure hands the refusal back to the caller's OWN empty-value arm, which
# says it in that tool's words at that tool's rc. Empty is the only thing this can print on a
# parse failure, so it can never turn an unreadable body into a plausible value.
#
# Suppressing jq's stderr means ANY jq fault lands in that same arm — a filter the caller got
# wrong, or a jq that is missing/unrunnable — and so does a body that parsed PERFECTLY WELL but
# holds no such value (a 200 `[]` is valid JSON that `.data` cannot index). So a caller's
# diagnostic states only what is true in EVERY one of those arms — "no <thing> could be read out
# of the body" — never "the body is not JSON" and never "the body could not be parsed": both are
# specific claims about the server that are wrong in the other arms.
#
# IT LIVES HERE, not in one bin, because the shape it fixes is not one bin's. Every tool that
# reads through kb_api / kb_api_status meets the same 2xx, and the alternative to one owner is
# what the tree already grew: several inline near-copies of `jq … 2>/dev/null`, agreeing by
# habit, one of them (dl-a1's) silencing the MESSAGE while still letting the rc kill the script
# — which is the failure the suppression was written to prevent (card#6426, canon #5).
#
# THE CALLER STILL OWNS THE POLICY. This decides only what the value is; whether an empty value
# is fatal, fail-soft, or a fall-back default stays at each call site (the same mechanism/policy
# split kb_ere_match documents above). A caller with no empty-value arm must add one — an empty
# value silently accepted is the silent-empty trap, not a fix for it.
kb_parse_resp() {
    local resp="$1"; shift
    jq "$@" <<<"$resp" 2>/dev/null || true
}

# --- whole-board pagination -------------------------------------------------
# fetch_board_cards <api> <token> <board_id> [page_cap] [query]: read the WHOLE board via
# search.json (limit=200), accumulate VIA STDIN (printf | jq -s, never argv, so a
# page over MAX_ARG_STRLEN can't trip "Argument list too long" — the #3091 /
# #3362 class), dedup by id (order-preserving), and emit ONE JSON array on
# stdout. Stops on a short page (n<200) or meta.last_page, whichever comes first.
# Honors KB_CURL_MAX_TIME (seconds) when set (board-snapshot's 5s startup cap).
#
# [query] IS THE OPTIONAL SEARCH TERM (card#6771) — the same `q=` token stream this endpoint
# already takes, appended after the `board_id=<id>` term this function has always sent, so the
# read is over the board's MATCHING cards rather than all of them. Nothing else changes: same
# paging, same dedup, same rcs, same census. Omitted or empty rebuilds the historic URL byte
# for byte, which is what leaves the whole-board calls — eight of the nine in bin/ — untouched.
#   * The term is percent-encoded as ONE value (jq's @uri — the spelling kbcard's external-id
#     lookup already uses), so a space, `&` or `#` in it adds no query parameter and retargets
#     nothing. A caller's own `board_id=` token does not REPLACE this function's: each
#     structured token adds its own constraint, so the two are ANDed (read at the server's
#     QueryParser::applyStructuredFilter, 2026-08-18).
#   * WHAT THE TERM MEANS IS THE SERVER'S RULE, not this function's — it neither parses nor
#     validates it, and does not know which tokens were understood.
#   * AN EMPTY OR WHITESPACE-ONLY TERM IS THE CALLER'S TO REFUSE. It is not narrowing: the
#     server trims, finds no token, and answers the WHOLE BOARD — at rc 0, indistinguishable
#     here from a search that legitimately matched everything.
#
# Returns — THE rc contract, stated once. A compact second copy used to sit two lines
# above this block and had already drifted (it was the only one naming rc 4), so it is
# deleted rather than re-synced: one list, here.
#   0  full read (array on stdout) — INCLUDING a genuinely empty board, which is a
#      legitimate state and answers `[]` at rc 0 like any other complete read
#   1  page 1 failed, nothing emitted — a fail-soft caller skips the board, and a
#      correctness-sensitive one refuses here as it does on 2/3/4 (the DL minter does,
#      as of card#6631: nothing of the board was read, so the undercount is total).
#      Three causes, one rc: curl could not complete the request, the status was not
#      2xx, or the 2xx body carried no readable card array (see the parse site below)
#   2  incomplete: a page > 1 failed mid-pagination, nothing emitted — a
#      correctness-sensitive caller (the DL minter) MUST refuse rather than risk a
#      truncated scan. The SAME three causes as rc 1, on a later page (card#6630); the
#      page is what selects between the two rcs, not the cause. Still not a closed cause
#      enumeration a caller may quote: rc 1's is closed because next-dl's rc-1-only arm
#      quotes it, and nothing has asked that of rc 2
#   3  page cap hit: the partial array is still emitted (so a display caller can
#      show what it has) but the read is flagged INCOMPLETE on stderr
#   4  SHORT READ: the server's own meta.total exceeds the rows the pages delivered.
#      The partial array is still emitted and flagged INCOMPLETE on stderr; a
#      refuse-policy caller must treat 4 like 2/3
#   5  the [query] could not be encoded: NO request was issued and nothing was read.
#      Reachable ONLY when a query was passed — it is decided above the loop, before the
#      first page — so a whole-board caller cannot see it. Fail-closed on purpose: an
#      unencodable term dropped silently would send the bare board_id read, i.e. answer the
#      WHOLE BOARD as though it were the match set
#
# HOW A CALLER WORDS ITS FAILURE MESSAGE — a rule about the MESSAGE, not about policy.
# What a caller DOES with each rc stays entirely its own (fail-soft skip, refuse,
# render the partial); what it may CLAIM is fixed here, because only this function
# knows why the read failed:
#   - an arm reached by EXACTLY ONE rc may name that rc's causes — the contract above
#     closes them (rc 1's three are the only closed cause set in it);
#   - an arm reached by MORE THAN ONE rc names the rc — `(fetch rc=$rc)` — and names NO
#     cause, because no cause set is true across the rcs it catches. A bare `|| …`
#     catches 1, 2, 3 AND 4, which share nothing but "not a whole read".
#   - THE SAME CONSTRAINT BINDS A CALLER-SIDE COMMENT that states which rcs reach an arm,
#     or what an operator will see when it fires. Such a comment is a claim about this
#     contract and goes stale exactly as a message does — and it is the half no test
#     covers: the selftest below derives arms from EMITTING LINES, so prose beside them is
#     checked only by reading. The rule is what makes that reading cheap. The first
#     instance was minted by the commit that wrote this rule: board-card-start's arm
#     comment said "nothing else is on stderr", which the unconditional rc 3 / rc 4 lines
#     below falsify for two of the four rcs that arm catches.
# A shared OUTCOME word is not a cause and is allowed on a multi-rc arm: "did not
# return a complete card list" / "INCOMPLETE" holds for every non-zero rc, while
# "unreachable", "a non-2xx status" or "over the page cap" each hold for only some.
#
# This is not style. Giving rc 1 a third cause (card#6594) falsified five caller
# messages that had enumerated the old two, and they were then corrected one site per
# round, for three rounds, each round finding another — because a cause enumeration at
# a multi-rc arm is stale the day the contract gains an rc, and the rc never is.
# tests/fetch-board-cards-caller-claims-selftest.sh pins this: it RE-DERIVES both the
# call sites and the ARMS from the tree rather than listing them, so a new consumer (in
# any call spelling), a new call in an existing consumer, a new or deleted arm within the
# derived window after a call, or a reworded arm reds until it is ruled on. Its bounds are
# stated there and are real: an arm further than that window from its call, or one that
# emits through a helper outside the derived emitter vocabulary, is not seen. Its registry
# is the per-consumer table (which rcs reach which arm, and what each arm may say); this
# header owns the rule, that test owns the dispositions, and neither restates the other.
#
# An operator who needs the CAUSE reads this function's own stderr line, the only one
# that knows it — printed unconditionally for rc 3 and rc 4, and only under
# KB_FETCH_LOUD for rc 1 and rc 2 (two of the six consumer bins set it). A caller that
# wants the cause visible sets that knob; it does not guess at the cause itself.
fetch_board_cards() {
    local api="$1" token="$2" board="$3" page_cap="${4:-50}" query="${5:-}"
    local pages="" page=1 last_page="" resp data n total="" read_n out sum_n=0 qextra=""
    # The optional search term, encoded ONCE (it is the same on every page). Refused rather
    # than dropped when the encode yields nothing: an empty qextra is not a narrower read,
    # it is the whole board answered as the match set — the widest wrong answer available
    # here. `%20` is the token separator the q stream already uses between its terms.
    if [[ -n "$query" ]]; then
        qextra="$(jq -rn --arg q "$query" '$q | @uri' 2>/dev/null)"
        [[ -n "$qextra" ]] || {
            echo "fetch_board_cards: the search term for board $board could not be encoded — no request was issued, nothing was read" >&2
            return 5
        }
        qextra="%20$qextra"
    fi
    # Order-preserving dedup-by-id over the slurped per-page arrays.
    local dedup='def _kb_dedup: (add // []) | reduce .[] as $c ([]; if any(.[]; .id == $c.id) then . else . + [$c] end); _kb_dedup'
    # -sS WITHOUT -f (card #4337): -f discards the 4xx/5xx body and collapses every
    # HTTP failure to curl rc 22, making a 403 token-scope failure and a 422
    # validation failure indistinguishable in the failure log. Status is captured
    # via the same -w marker kb_api uses; the body is logged/surfaced on non-2xx.
    local curl_opts=(-sS)
    [[ -n "${KB_CURL_MAX_TIME:-}" ]] && curl_opts+=(--max-time "$KB_CURL_MAX_TIME")
    # KB_FETCH_LOUD=1 makes a page-fetch failure observable (kbcard's list contract):
    # curl's own -S HTTP/transport error reaches stderr instead of the default quiet
    # /dev/null (which backs board-snapshot's fail-soft SessionStart display), and
    # when KB_LOG_FILE is set a failure line is appended to it. Default = silent
    # (return-code only), so board-snapshot's behavior is unchanged.
    #
    # The target is a DESCRIPTOR: redirecting to the PATH /dev/stderr RE-OPENS the file
    # behind the caller's stderr, and a regular-file stderr is re-opened O_TRUNC —
    # destroying everything the caller logged before the first page fetch. fd 9 is the
    # quiet sink, opened on the loop below; bash saves and restores a caller's own fd 9
    # around that redirect, so the number cannot collide with one.
    local errfd=9
    [[ -n "${KB_FETCH_LOUD:-}" ]] && errfd=2
    while :; do
        local url="$api/tasks/search.json?q=board_id=${board}${qextra}&limit=200&page=${page}"
        local rc
        # Auth via stdin herestring (-H @- <<<) so the token never enters argv (#3569) +
        # portable (no /dev/fd process-sub dependency that breaks native mingw64 curl, #34).
        resp="$(curl "${curl_opts[@]}" -H @- -H "Accept: application/json" \
                -w $'\n__HTTP__%{http_code}' \
                "$url" 2>&"$errfd" <<<"$(kb_auth_header "$token")")" || {
            rc=$?
            if [[ -n "${KB_FETCH_LOUD:-}" ]]; then
                echo "fetch_board_cards: page $page read failed for board $board (curl rc=$rc)" >&2
                [[ -n "${KB_LOG_FILE:-}" ]] && \
                    echo "$(date -u +%FT%TZ) GET $url FAILED-FETCH curl-rc=$rc" >> "$KB_LOG_FILE"
            fi
            [[ "$page" -eq 1 ]] && return 1
            return 2
        }
        local http="${resp##*__HTTP__}"
        resp="${resp%__HTTP__*}"
        if [[ ! "$http" =~ ^2 ]]; then
            if [[ -n "${KB_FETCH_LOUD:-}" ]]; then
                echo "fetch_board_cards: page $page read failed for board $board (HTTP $http): $resp" >&2
            fi
            [[ -n "${KB_LOG_FILE:-}" ]] && \
                echo "$(date -u +%FT%TZ) GET $url HTTP-$http $resp" >> "$KB_LOG_FILE"
            [[ "$page" -eq 1 ]] && return 1
            return 2
        fi
        if [[ "$page" -eq 1 ]]; then
            # meta.last_page is a SECONDARY termination signal — the n<200 short-page break
            # (below) is the primary one. Default UNKNOWN (empty), NOT 1 (card #4623): an
            # absent/out-of-range value must fall through to the n<200 break, never break the
            # scan at a full 200-row page 1 (that silently truncates when meta.total is also
            # absent — the miss #4513 guards in the co-vendored promote-released-cards
            # fetch_whole_board). Usable only as a POSITIVE integer; break on it below only
            # when the server positively declares it.
            last_page="$(printf '%s' "$resp" | jq -r '.meta.last_page // empty' 2>/dev/null)"
            kb_is_uint "$last_page" || last_page=""
            [[ -n "$last_page" && "$last_page" -lt 1 ]] && last_page=""
            total="$(printf '%s' "$resp" | jq -r '.meta.total // empty' 2>/dev/null)"
        fi
        # A 2xx whose body carries no card ARRAY is a page that FAILED to read, not a
        # page that was empty — and `.data // []` could not tell the two apart. An HTML
        # 502 interstitial from a proxy, a truncated body, or a JSON error object all
        # became `[]`: byte-identical (rc 0, `[]`, silent) to the answer a genuinely
        # empty board gives, so no caller could refuse it. next-dl then read no
        # dl_number out of that `[]`, dropped the board's DL floor and minted from the
        # local header scan alone — how a DL gets re-minted on a shared board, which is the
        # failure board_dl_max's own exit-code comment in bin/next-dl names ("an undercount
        # could re-mint a used DL"). card#6594. This refusal made that re-mint AUDIBLE rather
        # than impossible, because next-dl's rc-1 policy was fail-soft and it still minted
        # from the local scan; card#6631 has since closed that half at the CALLER — next-dl
        # now refuses on rc 1 as it already did on rc 2/3/4. Policy is still the caller's:
        # the other consumers' rc-1 dispositions are unchanged and are recorded in
        # tests/fetch-board-cards-caller-claims-selftest.sh.
        #
        # The tell is the ENVELOPE, not the row count. Measured against the live API: an
        # empty result is `{"data":[],"links":{…},"meta":{…,"total":0}}` at HTTP 200 —
        # `.data` is present and an array. So "`.data` exists AND is an array" separates
        # a read that returned nothing from a read that returned no answer, and keeps the
        # empty board a rc-0 success. `empty`, not `// []`: on any jq fault the ONE thing
        # this can print is nothing, which is the one value that cannot be mistaken for
        # data (the kb_parse_resp rule above, applied to the whole-board read).
        #
        # The predicate applies to EVERY page; only the rc differs, because only the rc
        # the contract above already assigns differs. Page 1 unreadable = nothing of the
        # board was read = rc 1; a later page unreadable = a page > 1 failed
        # mid-pagination = rc 2, the same rc the curl and non-2xx arms above return for
        # that page, and for the same reason — the difference is which layer noticed.
        # card#6630. Until it, the refusal was page-1 only and a later page's unreadable
        # body fell back to `[]`, which is a SHORT page, which ENDS the scan: the caller
        # got rc 0 and a truncated board. The meta.total census below caught that at rc 4
        # on any server that DECLARES meta.total — observed on every probe taken for
        # card#6594, which was an observation and not a guarantee, so the silent case was
        # a server that omits it. The census is unchanged and still runs; it is now a
        # backstop for a different failure (rows missing from readable pages) rather than
        # the only thing standing between an unreadable page 2 and a truncated answer.
        #
        # This is the fail-closed posture the co-vendored port in
        # bin/promote-released-cards (fetch_whole_board) carries — cited by FUNCTION, not by
        # line: the `:302-304` this comment used to name was correct until card#6630 edited
        # that function, which is the whole life expectancy of a line citation across a file
        # nobody edits in lockstep with this one. On a page > 1 the two now agree in effect
        # (both refuse an unreadable envelope, at each tool's own policy — an rc here, a die
        # there); on PAGE 1 it is deliberately NOT the same predicate: that tool dies
        # on zero CARDS, which it can afford because a board with nothing to promote is
        # never a working state for it. A board read verb cannot — `kbcard list` on an
        # empty board must still succeed — so the lib refuses on an unreadable ENVELOPE
        # instead. Residual, accepted: this API answers a board the token cannot see with
        # the same well-formed empty envelope as a board with no cards, so that case still
        # reads as an empty board HERE. The API behaviour is shared with the mirror; the
        # residual is not — the mirror's zero-CARDS die catches it, and this function must
        # not adopt that predicate, for the reason just given. Closing it needs a membership
        # signal the envelope does not carry, not a stricter row count.
        data="$(printf '%s' "$resp" | jq -c 'if (.data|type) == "array" then .data else empty end' 2>/dev/null)"
        if [[ -z "$data" ]]; then
            if [[ -n "${KB_FETCH_LOUD:-}" ]]; then
                # What the refusal SAVED the caller from differs by page, and saying the
                # wrong one is a false claim about the board: an unreadable page 1 would
                # have read as an EMPTY board, an unreadable later page as a SHORT page,
                # which ends the scan and reads as a complete but truncated one.
                # … and by WHAT THE READ IS OF: under a [query] the same body would have
                # read as a search that matched nothing / a truncated MATCH SET, and calling
                # either one "the board" is a claim about a population this read never had.
                local empty_claim="an empty board" trunc_claim="a TRUNCATED board"
                [[ -z "$query" ]] || { empty_claim="a search that matched nothing"; trunc_claim="a TRUNCATED result set"; }
                local refused="report it as $empty_claim"
                [[ "$page" -eq 1 ]] || refused="end the scan on a short page and report $trunc_claim as a complete read"
                echo "fetch_board_cards: page $page for board $board returned HTTP $http with no readable card array — refusing rather than $refused: $resp" >&2
            fi
            [[ -n "${KB_LOG_FILE:-}" ]] && \
                echo "$(date -u +%FT%TZ) GET $url HTTP-$http UNREADABLE-BODY $resp" >> "$KB_LOG_FILE"
            [[ "$page" -eq 1 ]] && return 1
            return 2
        fi
        n="$(printf '%s' "$data" | jq 'length' 2>/dev/null)"
        pages+="$data"$'\n'
        sum_n=$((sum_n + ${n:-0}))
        [[ "${n:-0}" -lt 200 ]] && break
        [[ -n "$last_page" && "$page" -ge "$last_page" ]] && break
        page=$((page + 1))
        if [[ "$page" -gt "$page_cap" ]]; then
            echo "fetch_board_cards: ⚠ stopped paging at page cap=$page_cap — list may be INCOMPLETE" >&2
            printf '%s\n' "$pages" | jq -c -s "$dedup" 2>/dev/null
            return 3
        fi
    done 9>/dev/null
    out="$(printf '%s\n' "$pages" | jq -c -s "$dedup" 2>/dev/null)"
    read_n="$(printf '%s' "$out" | jq 'length' 2>/dev/null)"
    if kb_is_uint "${total:-}" && kb_is_uint "${read_n:-}" && [[ "$total" -gt "$read_n" ]]; then
        # Distinguish a REAL undercount from a dedup artifact (card #4338): the
        # PRE-dedup page sum is the tell. sum_n < total ⇒ pages genuinely delivered
        # fewer rows than the server claims exist ⇒ emit the partial data and
        # return the DISTINCT rc 4 so refuse-policy callers (next-dl: an
        # undercount could re-mint a used DL; kbcard list: never print a
        # truncated list) can reach it — the warn-then-return-0 shape was a
        # backstop no caller could consume. sum_n >= total with read_n < total ⇒
        # the same card arrived on two pages (a page-boundary shift mid-scan) and
        # dedup collapsed it — the read is complete; warn-only. Residual accepted
        # risk, documented: a server delivering the SAME page twice would also
        # read as an artifact — that is a server fault this client-side census
        # cannot distinguish, and the warn still surfaces the count mismatch.
        if [[ "$sum_n" -lt "$total" ]]; then
            # meta.total is the total of what was ASKED FOR, so under a [query] it is the
            # match count and "board has $total cards" would be a false claim about the board.
            local census_subject="board has $total cards"
            [[ -z "$query" ]] || census_subject="the search over board $board matched $total cards"
            echo "fetch_board_cards: ⚠ $census_subject but pages delivered only $sum_n ($read_n after dedup) — list INCOMPLETE" >&2
            printf '%s' "$out"
            return 4
        fi
        echo "fetch_board_cards: ⚠ read $read_n distinct of $total — duplicates across pages collapsed (page-boundary shift); read complete" >&2
    fi
    printf '%s' "$out"
}

# --- DL canonicalization ----------------------------------------------------
# kb_dl_num <token>: the bare positive integer of a DL token, strict (the kbcard
# form). Accepts an optional DL-/dl- prefix + leading zeros + 1..6 digits,
# anchored — so a pr_url / version / hex fat-fingered in FAILS loudly instead of
# silently becoming a plausible-but-wrong DL. The {1,6} bound keeps base-10
# arithmetic in int range. Prints the integer; returns 2 on a non-DL / zero.
kb_dl_num() {
    kb_ere_match "$1" '^([Dd][Ll]-?)?0*([0-9]{1,6})$' \
        || { echo "$(_kb_prog): '$1' is not a DL number (expect e.g. DL-093 or 93)" >&2; return 2; }
    local n="$((10#${BASH_REMATCH[2]}))"   # 10# forces base-10 so a zero-padded value isn't read as octal
    [[ "$n" -ge 1 ]] || { echo "$(_kb_prog): '$1' resolves to 0 — not a valid DL number" >&2; return 2; }
    printf '%s' "$n"
}

# kb_dl_canon <token>: the ONE canonical stored form DL-NNNN, zero-padded to >=4 — the single
# source of the mint/stamp format (next-dl and adopt-to-dl both render through here). Width is
# cosmetic — every reader extracts digits and compares numerically — so pre-existing 3-padded
# cards stay valid. Returns 2 on a non-DL input.
kb_dl_canon() {
    local n
    n="$(kb_dl_num "$1")" || return 2
    printf 'DL-%04d' "$n"
}

# kb_dl_int_lenient <stored-form>: the bare integer of a dl_number in ANY stored form
# ("DL-088", "DL-0192", bare 88), or "" (rc 0) for a value holding no digits — the client
# mirror of the server's canonicalize('dl') (strip EVERY non-digit, then collapse leading
# zeros; roundtable #14 / DL-SOURCE-CORRELATION.md §2b). Deliberately LENIENT and distinct
# from the strict kb_dl_num: this COERCES a server-echoed stored value to match the server's
# correlation key, where kb_dl_num anchors + bounds + REJECTS non-DL user input loudly. Keep
# both — a raw kb_dl_num on the canonical "DL-NNNN" form is fine, but it throws on a mixed /
# leaked stored value this must tolerate.
kb_dl_int_lenient() {
    local d; d="$(printf '%s' "${1:-}" | tr -cd '0-9')"
    [[ -n "$d" ]] || return 0
    printf '%s' "$((10#$d))"   # 10# forces base-10 so a zero-padded value isn't read as octal
}

# kb_by_ref_hit <by-ref-json> <card-id>: 0 iff the by-ref response contains a row whose
# id == <card-id>. Tolerates BOTH shapes the by-ref endpoint can return — a {"data":[...]}
# envelope OR a bare top-level array — so every caller (adoption verify, field registration)
# shares one predicate instead of forking it. jq -e sets the exit status; any jq/parse error
# is a non-hit (fail-closed).
kb_by_ref_hit() {
    printf '%s' "${1:-}" | jq -e --argjson id "${2:-0}" \
        '(if type=="object" then (.data // []) else . end) | any(.[]?; .id == $id)' >/dev/null 2>&1
}
