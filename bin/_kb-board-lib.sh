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
#   - The resolved API base must be a host somebody DECLARED — $KANBAN_EXPECTED_HOST,
#     the same variable the api_base trust guard reads. An undeclared or mismatched
#     host is a refusal, never a fallback — see kb_require_known_api_host.
#   - Board env is ~/.kanban-<name>-board.env; kanban|dev (and "no --board") map
#     to the kanban-dev board.
#   - Token file is $KBCARD_TOKEN_FILE, DECLARED by a board env, a host env, or the
#     invoking environment; failing all three, the coord credential store's
#     `[kanban] api_token_file` POINTER is discovered. There is NO baked default — see
#     kb_declared_token_file and kb_coord_store_token_file.

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

# kb_is_uint <string>: true iff the string is the CANONICAL decimal spelling of a
# non-negative integer — `0`, or a run of ASCII digits that does not start with one.
# A leading zero is REFUSED: `0`, `1`, `42` accept; `00`, `08`, `010`, `007` refuse.
#
# WHY A LEADING ZERO IS REFUSED RATHER THAN NORMALISED. Every caller feeds the value it
# accepts straight to bash arithmetic (`[[ x -gt 0 ]]`, `[[ a -eq b ]]`, `$(( ))`), and
# bash reads a leading-zero literal as BASE 8 — measured: `[[ 010 -eq 10 ]]` is FALSE
# (010 is 8), and `08` is not a legal octal literal at all, so it dies mid-guard with
# `[[: 08: value too great for base` instead of refusing. That made this predicate answer
# "yes, that is a uint" about a string whose VALUE the next line then got wrong or faulted
# on. This is a PREDICATE: its job is to answer truthfully about the shape it is asked
# about, not to silently reinterpret the caller's spelling — a `010` that means ten and a
# `010` that is a typo are indistinguishable here, and the caller is the only layer that
# knows which. Normalisation therefore stays at the WRITE site (`$((10#$x))` the moment a
# value is accepted), where the tool that owns the input can also say what it did.
#
# `0` itself is still a uint — it is the one spelling of zero. NON-NEGATIVE is the whole
# claim: a caller that needs POSITIVE re-tests with its own `-gt 0` / `-ge 1`, which is the
# policy half and stays at the caller (see the mechanism-vs-policy note above). Multi-zero
# `00` is refused for the same reason as `08`: it is a second spelling of a value that
# already has one, and this predicate vouches for exactly one spelling per value.
kb_is_uint() { kb_ere_match "${1-}" '^(0|[1-9][0-9]*)$'; }

# kb_is_repo_slug <string>: true iff the string is a BARE GitHub `<owner>/<name>` —
# exactly one `/`, both sides non-empty, and only ASCII letters, digits, `.`, `_`
# and `-` either side of it. A `.git` suffix is refused.
#
# WHY THIS IS A PRIMITIVE AND NOT A SHAPE TEST AT EACH CALLER (card#8421). Every
# caller spends this value the same way: it becomes a `<owner>/<name>` segment of a
# GitHub URL or a request path, and — for the adoption path — of BOTH sides of one
# comparison (the placeholder `pr_url` a card is STAMPED with, and the `source=` of
# the by-ref VERIFY that is supposed to prove the stamp correlatable). A spelling
# that gets past the guard therefore derives the SAME garbage on both sides, so the
# verify passes VACUOUSLY: "adopted ⇒ correlatable" certified by a check that could
# not fail. A SHAPE-only predicate (`^[^[:space:]/]+/[^[:space:]/]+$`) is what did
# that — measured, it ACCEPTS `git@github.com:acme/widget` and `acme/*`, which are
# one slash and two non-empty parts apiece. Shape and charset are ONE pair and
# neither half stands alone: the shape admits the scp-style remote, the charset
# admits `acme/a/b`. The pair is spelled here once, as one regex.
#
# `.git` NEEDS ITS OWN ARM, and it is not an oversight that the regex does not carry
# it: `.git` is inside the charset and IS a legal repo-name ending, and ERE has no
# negative lookahead to exclude a suffix with. It is refused because the two
# derivations disagree about it — the server's source canonicalizer does not trim a
# `.git` while `repoFromGitHubUrl` does, so `acme/widget.git` stamps a card whose
# derived source is `acme/widget` and then verifies against `acme/widget.git`: it
# fails LOUD, but only AFTER the write. Refusing here leaves nothing half-applied.
#
# THE ARM IS CASE-INSENSITIVE because the disagreement it encodes is a property of the
# SUFFIX and not of its casing: GitHub `<owner>/<name>` is case-insensitive and the
# server's `repoFromGitHubUrl` is `/i`, so `acme/widget.GIT` derives the same
# `acme/widget` and half-applies exactly as the lowercase spelling does. A
# case-SENSITIVE arm accepted it (card#8421) while the duplicate in
# `bin/promote-released-cards` — which lowercases before its own `case` — refused it:
# one accept set, two verdicts. `[Gg][Ii][Tt]` is a bracket LIST of explicit ASCII
# members, not a bracket RANGE, so no collation order is consulted and the arm needs no
# `LC_ALL=C` window of its own — contrast the ranges tests/locale-range-guard-selftest.sh
# scans for, which do.
#
# ⛔ ONE ACCEPT PREDICATE, and callers may not re-spell it. `bin/promote-released-cards`
# is the one exception and cannot be fixed by adoption: it is VENDORED STANDALONE into
# consumer repos and MUST NOT source this lib, so its `src_charset_ok` plus its shape
# `case` are a deliberate duplicate of this function gating the SAME value at the other
# end of the SAME correlation. The two are held in sync BY A TEST rather than by two
# comments agreeing — the same regime kb_require_https_host's duplicate has in
# tests/kb-host-guard-selftest.sh: § 3c of tests/promote-source-qualify-selftest.sh
# drives ONE corpus through both and asserts the verdicts match row for row, with the
# only divergences (`*`, and promote-side trimming) declared there by name.
kb_is_repo_slug() {
    kb_ere_match "${1-}" '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1
    case "${1-}" in *.[Gg][Ii][Tt]) return 1 ;; esac
    return 0
}

# --- config resolution ------------------------------------------------------
#
# ONE token-file precedence, uniform across every resolver below:
#     a BOARD env's KBCARD_TOKEN_FILE > the HOST env's > an ambient one
#       > the coord credential store's `[kanban] api_token_file` POINTER
# The first three fall out of SOURCE ORDER (host first, board second) rather than a ladder of
# explicit tests; the fourth is a DISCOVERY, reached only when all three declared nothing —
# see kb_coord_store_token_file. KBCARD_API is the mirror image — board-independent, host
# env only.
#
# ⛔ THE FOURTH TIER IS A POINTER SOMEBODY WROTE DOWN, NOT A BAKED DEFAULT — and that
# distinction is card#7245's whole ruling, not a loophole in it. `~/.kanban-dev-token` was a
# baked default under those three until card#7245, and being a DEFAULT is what made it
# dangerous: NOT ONE board env on the reference host set KBCARD_TOKEN_FILE, so every board —
# three real ones and a test harness's — resolved to the SAME file, and a single write to it
# took all of them out at once. (The name is also a trap: `dev` there names the AGENT, not an
# environment; the file held a prod-capable token.) The invariant that replaced it survives
# intact: every tier is something a human wrote down in a named place. This toolkit still
# ships no path of its own — the store rung resolves whatever path an operator put in their
# own credential store — and a box with no store, or a store that declares no
# `[kanban] api_token_file`, still gets the refusal naming the file to add the line to.
#
# ⚠ THE STORE RUNG IS BOARD-INDEPENDENT, which is worth knowing before relying on it. The
# store holds ONE `[kanban] api_token_file`, so two boards that both declare nothing both
# discover the same file — the shared-credential SHAPE the old default had, minus the two
# properties that made the incident: nothing here invents the path, and the file it names is
# one the operator wrote, manages and can rotate. A board that must not share it declares its
# own KBCARD_TOKEN_FILE, which wins; that is why the discovery is LAST. See
# kb_declared_token_file.

# kb_coord_store_token_file: the token file the coord credential store POINTS AT, on stdout.
# Returns 1 with nothing on stdout when there is nothing this rung can use — SILENTLY when
# the store is simply absent, with a message when the store is present and says something
# this rung will not act on.
#
# WHY IT EXISTS (card#7316). Two packages resolve the same kanban secret through two
# conventions that are unaware of each other, so a seat whose credential store is already
# hardened had to mint a SECOND plaintext copy of the token for this toolkit to find one.
# This rung reads the store's own pointer instead. It is the LAST tier because an operator's
# own declaration must beat a discovered one.
#
# ⛔ POINTER-ONLY. THE INLINE FORM IS REFUSED BY NAME, even though the framework's own
# resolver still honours it. That store file is also the framework's first-stop DIAGNOSTIC
# surface — the file every seat greps when auth breaks — so reading an inline value would put
# a secret's VALUE through this toolkit's code and give the inline form a second consumer at
# the moment the framework is removing its first. The refusal names the pointer form, and
# that message IS the migration prompt, which is the useful behaviour.
#
# ⛔ NOTHING HERE PRINTS A STORE VALUE — not the pointer's text, not a basename, not a
# prefix. The realistic operator error under a store migration is pasting the TOKEN into the
# `_file` slot, and then the pointer's text IS the secret. This toolkit's callers name
# KB_TOKEN_FILE in their own failure messages (board-card-start's 401 arm does), so handing a
# pasted token back as a "path" would leak it through messages written before this rung
# existed. A credential-SHAPED pointer is refused HERE instead, and every message names the
# store COORDINATE plus a non-reversible fingerprint — the same rule the framework's resolver
# holds, where the leak it closed was a traceback that had rendered a live PAT.
#
# WHAT IT DELIBERATELY DOES NOT DO: it never reads the token, so a DISCOVERED path is handed
# back exactly as a declared one is, and a pointer at a missing file lands on the caller's
# existing "token file unreadable" arm — which is the right verdict. A source that is set but
# broken is a misconfiguration, never a reason to fall through to a weaker one.
#
# THE PARSE is awk over the ini — NO dependency on the framework's Python, so the toolkit
# stays standalone and keeps resolving on a box that has none. It follows configparser's
# reading of the shape it cares about: `#`/`;` FULL-LINE comments only (an inline `#` is part
# of a value), the first `=` or `:` is the delimiter, the section name is case-SENSITIVE and
# the key is matched exactly then case-folded. It is a READER FOR ONE KEY, not a validator:
# it does not re-implement configparser's strict duplicate/section checks, and an indented
# continuation line is not understood as one. The single exception is where guessing would
# hand out a token — a duplicated `api_token_file` is refused rather than resolved to one of
# the two.
_kb_coord_store_path() { printf '%s' "${COORD_CREDENTIALS:-$HOME/.config/coord/credentials.ini}"; }

# _kb_pointer_fingerprint <value>: `sha256:1a2b3c4d` — correlatable across two messages or two
# runs, and nowhere near invertible. The value reaches sha256sum over a PIPE from a shell
# BUILTIN: never argv (`ps` is world-readable), never a temp file. No digest tool ⇒ the label
# says so rather than the message losing its correlation silently.
_kb_pointer_fingerprint() {
    local h
    if h="$(printf '%s' "${1-}" | sha256sum 2>/dev/null)"; then
        printf 'sha256:%s' "${h:0:8}"
    else
        printf 'sha256:unavailable'
    fi
}

# _kb_looks_like_pasted_secret <value>: true when a value that is supposed to be a PATH has
# the shape of a CREDENTIAL instead. Ported from the framework's resolver so both tools
# recognise the same mis-paste rather than diverging on it.
#
# Conservative on purpose — a false positive here is a wrong-but-specific cause: it takes a
# value with NO directory separator and no leading `~`, AND either a known token prefix or a
# long extension-less blob. `REPLACE_ME` is not flagged, and neither are `tok.txt`,
# `~/.config/coord/tok` or `C:\creds\tok`. Matched under LC_ALL=C for the reason the ASCII
# helpers at the top of this file exist.
_kb_looks_like_pasted_secret() {
    local LC_ALL=C
    local v="${1-}" lc
    [[ -n "$v" ]] || return 1
    case "$v" in
        '~'*|*/*|*\\*) return 1 ;;
    esac
    lc="${v,,}"
    case "$lc" in
        ghp_*|gho_*|ghu_*|ghs_*|ghr_*|github_pat_*|glpat-*|xoxb-*|xoxp-*) return 0 ;;
    esac
    [[ ${#v} -ge 24 && "$v" != *.* ]]
}

# _kb_expand_home <value>: expand a LEADING `~`, `$HOME` or `${HOME}` — each only when it is
# the whole value or is followed by `/`. NEVER eval: the input is a value out of a credential
# store, and an eval on it is an arbitrary-command door.
#
# `~` is what the framework resolver's `Path.expanduser()` does. `$HOME` is a deliberate
# SUPERSET of it (asked for when this rung was specced): `expanduser()` does not expand
# environment variables, so a store spelling `$HOME/…` is unreadable to the framework and
# readable here. It cannot change an answer the framework gets RIGHT — no seat has a
# directory literally named `$HOME` — so the superset can only rescue a path, never redirect
# one. `~user` is NOT expanded (it needs a passwd lookup); spell it `~/…` or absolute.
_kb_expand_home() {
    local v="${1-}"
    # SC2088 is about a tilde that will not EXPAND; these are case PATTERNS, where a literal
    # `~` is precisely what has to match, and the expansion is the printf on the same line.
    # shellcheck disable=SC2088
    case "$v" in
        '~')         printf '%s' "$HOME" ;;
        '~/'*)       printf '%s%s' "$HOME" "${v#\~}" ;;
        '$HOME')     printf '%s' "$HOME" ;;
        '$HOME/'*)   printf '%s%s' "$HOME" "${v#\$HOME}" ;;
        '${HOME}')   printf '%s' "$HOME" ;;
        '${HOME}/'*) printf '%s%s' "$HOME" "${v#\$\{HOME\}}" ;;
        *)           printf '%s' "$v" ;;
    esac
}

kb_coord_store_token_file() {
    local store; store="$(_kb_coord_store_path)"
    # ABSENT IS SILENT, and that is the decision rather than an omission: a box with no coord
    # framework at all must not be told about a store it does not have, and its refusal has to
    # read exactly as it did before this rung existed. PRESENT-BUT-UNREADABLE is NOT absence —
    # it is a fault hiding a credential the operator believes is configured — so it says so.
    [[ -e "$store" ]] || return 1
    if [[ ! -r "$store" ]]; then
        echo "$(_kb_prog): the coord credential store $store exists but is not readable, so its [kanban] api_token_file (if any) was not consulted" >&2
        return 1
    fi

    local parsed verdict ptr coord="[kanban] api_token_file"
    parsed="$(awk -v sec='kanban' -v want='api_token_file' -v inl='api_token' '
        function trim(s) { sub(/^[ \t\r]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        {
            l = trim($0)
            if (l == "") next
            if (substr(l, 1, 1) == "#" || substr(l, 1, 1) == ";") next
            if (substr(l, 1, 1) == "[") {
                p = 0
                for (i = length(l); i >= 2; i--) if (substr(l, i, 1) == "]") { p = i; break }
                cur = p ? substr(l, 2, p - 2) : ""
                next
            }
            if (cur != sec) next
            e = index(l, "="); c = index(l, ":")
            if (e && c) d = (e < c) ? e : c; else d = e ? e : c
            if (!d) next
            k = trim(substr(l, 1, d - 1))
            v = trim(substr(l, d + 1))
            if (k == want) { nexact++; if (nexact == 1) pv = v }
            else if (tolower(k) == want) { if (!nfold) { nfold++; fv = v } }
            else if ((k == inl || tolower(k) == inl) && v != "") ninline++
        }
        END {
            if (nexact > 1) { print "dup"; exit }
            if (ninline) { if (nexact || nfold) print "inline_ptr"; else print "inline"; exit }
            if (nexact) { printf "ok\n%s\n", pv; exit }
            if (nfold)  { printf "ok\n%s\n", fv; exit }
            print "none"
        }
    ' "$store" 2>/dev/null)"
    verdict="${parsed%%$'\n'*}"
    ptr=""
    [[ "$parsed" == *$'\n'* ]] && ptr="${parsed#*$'\n'}"

    case "$verdict" in
        ok) ;;
        dup)
            echo "$(_kb_prog): $coord is declared more than once in $store — refusing to guess which token to send (the framework's own resolver refuses that store outright); remove the duplicate" >&2
            return 1 ;;
        inline|inline_ptr)
            echo "$(_kb_prog): $store holds an INLINE [kanban] api_token — this reads POINTERS only, because that file is also the first surface a transcript captures. Write the token to a file (chmod 600) and declare   api_token_file = <path>   instead (card#7316)" >&2
            [[ "$verdict" == "inline_ptr" ]] && \
                echo "$(_kb_prog):   an api_token_file is declared too, but the framework's own resolver prefers the INLINE value — honouring the pointer here would send a different credential than the rest of the framework does, so remove the inline value" >&2
            return 1 ;;
        *) return 1 ;;
    esac

    [[ -n "$ptr" ]] || return 1
    if [[ "$ptr" == *'%%'* || "$ptr" == *'%('* ]]; then
        echo "$(_kb_prog): $coord in $store contains \`%%\` or \`%(\`, whose meaning is not the same before and after the framework stopped %-interpolating that file — guessing would resolve a path that differs by one character, so this refuses; spell it literally ($(_kb_pointer_fingerprint "$ptr"))" >&2
        return 1
    fi
    if _kb_looks_like_pasted_secret "$ptr"; then
        echo "$(_kb_prog): $coord in $store holds something with the SHAPE OF A CREDENTIAL, not a path ($(_kb_pointer_fingerprint "$ptr")) — a \`_file\` slot takes the path of a file CONTAINING the token, never the token itself. Its text is deliberately not echoed: if it is live, echoing it is the leak that indirection exists to stop" >&2
        return 1
    fi
    _kb_expand_home "$ptr"
}

# kb_declared_token_file <where> <candidate>…: the FIRST non-empty candidate, on stdout —
# else the coord credential store's pointer, if it has one. Prints nothing and returns 1 when
# every candidate is empty AND the store declares nothing usable — i.e. when no config file,
# no invoking environment and no credential store named a token file for this board.
#
# THE DISCOVERY IS LAST, AND ONLY THE ORDER OF THESE LINES SAYS SO. Every <candidate> is a
# DECLARATION — a line an operator wrote into a board env, the host env, or the invoking
# command — and a declaration must beat something a tool went looking for, or an operator who
# pinned a board to its own token would silently be given another. That is also why the store
# rung lives here, at the one primitive all four resolvers already funnel through, rather than
# at four call sites that could drift apart on it (canon #5).
#
# WHY A REFUSAL AND NOT A DEFAULT (card#7245). The candidates are the declaration tiers of
# whichever resolver called this; what it replaced at all four call sites was a trailing
# `:-$HOME/.kanban-dev-token`, and that trailing default is the whole defect. A default is a
# declaration by NOBODY: it makes one file the credential for every board that forgot to
# name one, so its blast radius is the box rather than the board, and it does that silently
# — a board using a token nobody chose for it looks exactly like a board using its own.
#
# <where> is the config surface the operator must edit — a board env path, or a label for a
# resolver that has no single file. It is the whole value of the message: a refusal that
# named only the missing variable would leave the reader hunting for which of four files to
# put it in. The remediation is spelled as the literal line to add, because that is what the
# reader has to type.
#
# MECHANISM, NOT POLICY — like every other guard in this lib. It answers "was one declared,
# and which", never "what should happen now": kb_resolve_env turns a 1 into its rc 7,
# board-snapshot into a per-board fail-soft notice, board-card-start into a hook skip.
kb_declared_token_file() {
    local where="$1"; shift
    local c
    for c in "$@"; do
        [[ -n "$c" ]] && { printf '%s' "$c"; return 0; }
    done
    # Nothing was DECLARED. Ask the coord credential store whether it points at one — the
    # rung's own messages cover the states it refuses, and an absent store is silent, so a box
    # without one reaches the refusal below with exactly the wording it had before this tier
    # existed.
    if c="$(kb_coord_store_token_file)"; then
        printf '%s' "$c"; return 0
    fi
    echo "$(_kb_prog): no token file is declared for $where — there is no default (card#7245: one shared default made a single overwrite take out every board at once)" >&2
    echo "$(_kb_prog):   → add   export KBCARD_TOKEN_FILE=\"\$HOME/.kanban-<board>-token\"   to $where, or a host-wide one to ~/.kanban-host.env (docs/INSTALL.md §3)" >&2
    return 1
}

# kb_resolve_env <board_env_path>: source the host env then the board env, and
# publish KB_API / KB_BOARD_ID / KB_TOKEN_FILE / KB_BOARD_ENV. Does NOT read the
# token content and does NOT require KB_BOARD_ID — the caller decides those. Quiet
# (return-code only) apart from the rc-4, rc-6 and rc-7 refusals, which speak for
# themselves, so a fail-soft caller can craft its own message for the rest. Returns:
#   0 ok   2 env unreadable   3 KBCARD_API unset   4 board env sets KBCARD_API
#   5 token file unreadable   6 API host refused   7 no token file declared
#
# THE THREE LOUD ARMS ARE LOUD FOR ONE REASON: each says the operator believes something
# false about their config, and the fix is a specific line in a specific file. A bare rc
# reaches the operator through a caller that can only say "config incomplete (rc=N)" —
# next-dl's arm, verbatim — which is why rc 4's refusal was already written this way.
kb_resolve_env() {
    local board_env="$1"
    # CLEARED FIRST, not on the success path only. These are globals, and five of the seven
    # rcs below return before assigning them — so after a FAILED resolve of board B they
    # would still hold board A's values from an earlier call in the same shell, and a
    # credential path left standing after a refusal is the exact cross-call leak the ambient
    # snapshot further down exists to prevent.
    #
    # ⛔ THE SCOPE OF THAT CLAIM IS THESE TWO, NOT ALL FOUR PUBLISHED GLOBALS. It used to read
    # "Nothing publishes what it did not resolve", which is false as written: KB_API and
    # KB_BOARD_ID are also published by this function and are NOT cleared here, so an rc 2
    # (unreadable board env) returns with board A's KB_API still standing. That is not a live
    # bug — no in-tree caller reads either after a nonzero rc, they all branch on the rc first —
    # and the two are treated differently on purpose rather than by omission:
    #   * KB_TOKEN_FILE / KB_BOARD_ENV name a CREDENTIAL and the file that chose it. A stale one
    #     survives as a path something might later read, which is the leak above.
    #   * KB_BOARD_ID must NOT be cleared here. `KB_BOARD_ID="${KB_BOARD_ID:-}"` below reads its
    #     own prior value on purpose — that is the documented AMBIENT tier, the one a caller sets
    #     for a board whose env does not. Clearing it at the top would silently delete that tier,
    #     which is precisely the mistake the ambient snapshot below is written to avoid.
    # Widening the clear is therefore a behaviour change, not a tidy-up. If this comment and the
    # line under it ever disagree again, the comment is the thing that drifted.
    KB_TOKEN_FILE=""; KB_BOARD_ENV=""
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
    KB_BOARD_ID="${KB_BOARD_ID:-}"
    [[ -n "$KB_API" ]] || return 3
    # BEFORE the token file is even located, let alone read: a base nobody vouched for is
    # not a base this process should go looking for credentials to send to (card#7245).
    kb_require_known_api_host "$KB_API" || return 6
    KB_TOKEN_FILE="$(kb_declared_token_file "$board_env" "$cfg_tok" "$amb_tok")" || return 7   # board > host > ambient > coord store
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
        6|7) return 2 ;; # the guard already named the value, the file and the line to add
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
# (promote-released-cards carries an inline mirror of this, as do release-pr-body,
# release-artifacts-check and release-tag-check — each is vendored standalone and must not source
# this lib. As with kb_require_https_host the agreement is CHECKED rather than asked for:
# tests/mirror-pair-parity-selftest.sh derives the copy set from the tree and drives every copy
# against this one over one corpus, so a fifth is compared on the day it lands.)
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

# kb_url_host <url>: the AUTHORITY HOST of a URL, per RFC 3986 — with no opinion about
# scheme, port or path. Empty when the string has no authority. A bracketed IPv6 literal
# comes back WITH its brackets ("[::1]"), which is the RFC 3986 host and the spelling an
# operator declares; a single trailing dot (the absolute/FQDN form) is stripped, because
# it names the same host to DNS and to curl.
#
# IT DOES NOT CASE-FOLD, and both callers compare its result literally. DNS names are
# case-insensitive, so `https://Kanban.Example/` against KANBAN_EXPECTED_HOST=kanban.example
# is a FALSE REFUSAL. That is deliberate rather than overlooked, and the constraint is the
# VENDORED MIRROR, not the two lib callers — those both read their host from this one
# function, so they cannot disagree about a string whatever it does. `host_ok` in
# bin/promote-released-cards is the copy that must not source this lib, so a fold here that
# is not also made there splits one guard into two policies, and the case matrix in
# tests/kb-host-guard-selftest.sh asserts the two copies AGREE on every row. Fold in BOTH
# copies or in neither. Meanwhile the refusal prints both spellings side by side, so an
# operator hitting the false refusal sees the cause.
#
# ⛔ THIS PARSER MUST AGREE WITH CURL ABOUT WHERE THE AUTHORITY ENDS, and the reason is in
# tests/kb-host-guard-selftest.sh's header: it once terminated the authority at '/' ALONE,
# so `https://evil.example#@good.host` left the fragment in the string, the userinfo strip
# took everything after the LAST '@', and the guard read `good.host` and ACCEPTED while curl
# discarded the fragment and sent the bearer token to evil.example. A guard that parses a
# URL differently from the client that fetches it is an exfiltration primitive, not a guard.
#
# IT IS ONE FUNCTION BECAUSE THERE ARE TWO CALLERS AND THE MATRIX ABOVE IS THE COST OF
# GETTING IT WRONG (canon #5). kb_require_https_host guards a PR-editable committed
# api_base; kb_require_known_api_host guards the operator's own resolved KBCARD_API. Two
# policies, two schemes admitted — but exactly ONE answer to "what host is this".
# kb_redact_url_userinfo below is the third reader of that boundary and takes it from the
# same prose, for the same reason — see its own ⛔ note.
#
# The scheme is stripped only when the string actually starts with one: `${u#*://}` alone
# would match the FIRST `://` anywhere, so a schemeless `host/p?x://y` would parse as `y`.
kb_url_host() {
    local u="$1"
    kb_ere_match "$u" '^[A-Za-z][A-Za-z0-9+.-]*://' && u="${u#*://}"
    u="${u%%[/?#]*}"   # authority ends at the FIRST of / ? # (RFC 3986) — not '/' alone
    u="${u##*@}"       # strip userinfo — host is after the last '@' (RFC 3986)
    # THE PORT STRIP CANNOT START AT THE FIRST ':' — an IPv6 IP-literal is nothing but
    # colons, so `[::1]:8080` cut there yields `[`, and `[fe80::1]` yields `[fe80`. RFC 3986
    # ends the IP-literal at ']' and curl agrees (measured: `https://[::1]:8080/api`
    # connects to `::1` port 8080), so the host is everything through the FIRST ']'. An
    # unclosed '[' has no host to find: it keeps the plain strip, and curl rejects such a
    # URL outright (exit 3, "bad range specification"), so nothing is ever sent with it.
    case "$u" in
        \[*\]*) u="${u%%\]*}]" ;;
        *)      u="${u%%:*}" ;;
    esac
    # ONE trailing dot, not a run: `kanban.example.com.` is the absolute spelling of the same
    # name and resolves identically, while `kanban.example.com..` is not a name at all and
    # must keep failing the comparison rather than be normalised into one.
    printf '%s' "${u%.}"
}

# KB_URL_USERINFO_MASK — what a redacted userinfo component reads as. A constant so the two
# copies of the redactor (here and the promote-released-cards mirror) cannot disagree about
# the spelling, and so an assertion can name it once. Same plain-assignment reasoning as
# KB_API_RC_TRANSPORT below: the lib is sourced more than once in some shells, where a
# `readonly` re-assignment is fatal.
KB_URL_USERINFO_MASK='***'

# kb_redact_url_userinfo <url>: the url with any RFC 3986 USERINFO component replaced by
# $KB_URL_USERINFO_MASK — scheme, host, port, path, query and fragment byte-identical. A url
# carrying NO userinfo comes back UNCHANGED, so every message about an ordinary api_base
# reads exactly as it did before this function existed.
#
# WHY IT EXISTS (card#7500). `https://user:password@host/api/v3` is a SUPPORTED api_base and
# the host guards ACCEPT it — correctly: they judge the HOST and nothing else, and
# tests/kb-host-guard-selftest.sh pins that acceptance as a row. The defect was never the
# guard, it was the RENDER. Ten error paths printed the resolved base verbatim, four of them
# into a durable on-disk log ($KB_LOG_FILE here, $KB_BCS_LOG in board-card-start), so a
# password reached stderr — hence any CI log — and outlived the run on disk. Canon #20: a
# resolved secret must never reach an output stream, and "already emitted" means leaked.
#
# ⛔ IT REDACTS A URL, NEVER A FINISHED MESSAGE. A caller redacts at the point the base is
# RESOLVED — once, into a `*_shown` / `*_SHOWN` variable that every message in that scope
# then prints — so a message added later inherits the redaction instead of having to
# remember a regex. tests/url-userinfo-render-selftest.sh is the gate that keeps that true:
# it re-derives the renderable-URL population from the shipped tree every run and reds on a
# render of a raw one.
#
# ⛔ IT USES kb_url_host's AUTHORITY BOUNDARY, AND IT MUST. `https://evil.example#@good.host`
# has no userinfo at all: the '@' is in the FRAGMENT, curl discards the fragment, and the
# authority is evil.example — which is why the guard refuses it (the #4346 row). A redactor
# that cut at the last '@' anywhere in the string would rewrite that exact hostile input into
# `***@good.host`, printing a refusal that names the host the guard was protecting as though
# it were the one being contacted. The authority ends at the FIRST of / ? # and the userinfo
# is what precedes the LAST '@' INSIDE it.
#
# THE WHOLE USERINFO GOES, not just the password half. A username is a credential component
# in its own right (and is routinely an email address), and splitting at ':' to preserve it
# is a second parse bought for nothing. The '@' SURVIVES the mask, so `***@host` still tells
# an operator that the base carried userinfo — a fact they may need and cannot recover from
# the host alone.
kb_redact_url_userinfo() {
    local u="$1" scheme="" auth rest
    # Scheme stripped only when the string actually STARTS with one — the same reasoning as
    # kb_url_host: a bare `${u#*://}` matches the FIRST `://` anywhere, so a schemeless
    # `host/p?x://y` would lose everything up to it.
    if kb_ere_match "$u" '^[A-Za-z][A-Za-z0-9+.-]*://'; then
        scheme="${u%%://*}://"; u="${u#*://}"
    fi
    auth="${u%%[/?#]*}"        # authority ends at the FIRST of / ? # (RFC 3986)
    rest="${u:${#auth}}"       # …and everything from there on is returned untouched
    case "$auth" in
        *@*) auth="$KB_URL_USERINFO_MASK@${auth##*@}" ;;
    esac
    printf '%s' "$scheme$auth$rest"
}

# kb_require_known_api_host <api_base>: the PREFLIGHT (card#7245). Returns 0 only when the
# resolved API base names a host somebody DECLARED in $KANBAN_EXPECTED_HOST — that host, or
# a subdomain of it. Anything else, INCLUDING an unset/empty KANBAN_EXPECTED_HOST, is a
# refusal at rc 1 with the remediation on stderr.
#
# ⛔ ITS PREDICATE IS THE HOST AND ONLY THE HOST — deliberately narrower than
# kb_require_https_host's, which also requires https:// because the value it judges is
# PR-editable and its caller is about to send a release-CI writeback token. This one judges
# the operator's own ~/.kanban-host.env, where an http://127.0.0.1 board is a legitimate
# install; adding a scheme rule here would refuse those with a message about a host.
#
# WHY IT REFUSES WHEN NOTHING IS DECLARED, rather than waving an undeclared host through.
# With no expected host on record, EVERY host is unrecognised — "no opinion" and "any host
# is fine" are the same behaviour, and the second is what took the reference host down: an
# E2E harness replaced ~/.kanban-host.env wholesale, which both re-pointed KBCARD_API at a
# name that does not resolve on that box AND deleted the KANBAN_EXPECTED_HOST line, so a
# guard keyed on "set and mismatched" would have stayed silent through the one write it
# existed to catch. The operator learned instead from `Could not resolve host` and then, for
# twenty minutes, HTTP 401. That is the same fail-closed regime kb_require_https_host has
# had since v0.9.0, on the same variable, so a host that already satisfies one satisfies
# both and no second thing has to be configured.
kb_require_known_api_host() {
    local api="$1"
    # The same one-trailing-dot normalisation kb_url_host applies to the parsed host, applied
    # to the DECLARED one — an operator who copied the FQDN spelling out of their own
    # KBCARD_API would otherwise be refused with `'h' is not 'h.'`. It runs BEFORE the
    # empty test, so a declaration of "." alone normalises to empty and fails CLOSED rather
    # than becoming a wildcard.
    local expect="${KANBAN_EXPECTED_HOST:-}"; expect="${expect%.}"
    # THE ONLY SPELLING OF THE BASE THAT MAY BE RENDERED, resolved once here so every message
    # below — including one added later — prints it rather than $api (card#7500). An api_base
    # is allowed to carry userinfo and this function's messages are stderr.
    local api_shown; api_shown="$(kb_redact_url_userinfo "$api")"
    if [[ -z "$expect" ]]; then
        echo "$(_kb_prog): KANBAN_EXPECTED_HOST is not set, so no api host is recognised — refusing to use '$api_shown'" >&2
        echo "$(_kb_prog):   → add   export KANBAN_EXPECTED_HOST=\"<the host part of KBCARD_API>\"   to ~/.kanban-host.env (docs/INSTALL.md §3)" >&2
        return 1
    fi
    local host; host="$(kb_url_host "$api")"
    if [[ -n "$host" && ( "$host" == "$expect" || "$host" == *".$expect" ) ]]; then
        return 0
    fi
    echo "$(_kb_prog): api base host '$host' is not '$expect' (or a subdomain of it) — refusing to use '$api_shown'" >&2
    echo "$(_kb_prog):   → if '$host' IS your board host, set KANBAN_EXPECTED_HOST=\"$host\" in ~/.kanban-host.env; otherwise KBCARD_API in ~/.kanban-host.env (or \$KANBAN_HOST_ENV) is pointing somewhere you did not intend — check whether something rewrote it" >&2
    return 1
}

# kb_require_https_host <api_base>: fail-closed guard for a CONFIG-supplied API base
# (the .release-pr.json .promote.api_base, which a PR can edit). Asserts the base is
# https:// AND its host is the expected host or a subdomain of it — so a malicious
# api_base pointed at an attacker host cannot exfiltrate the bearer token (#3570). The
# expected host is $KANBAN_EXPECTED_HOST — REQUIRED, no baked default: this toolkit is
# vendored by operators on their own kanban hosts, so there is no host to safely assume.
# If it is unset/empty the guard fails CLOSED (returns 1) and the caller MUST NOT send the
# token. The host comes from kb_url_host above — ONE parser, which owns the RFC 3986
# reasoning and the hostile-URL history; it is not restated here. So none of
# `https://good.host@evil/` (→ evil), `https://good.host.evil/`, or the delimiter splits
# slip through. Prints a diagnostic and returns 1 on violation.
# (promote-released-cards carries an inline mirror of this — it is vendored standalone
# and must not source this lib; keep the two in sync, INCLUDING this required-var check.)
# Any future edit here or to kb_url_host must keep the hostile-URL matrix in
# tests/kb-host-guard-selftest.sh green — that file asserts every case against BOTH copies.
kb_require_https_host() {
    local api="$1"
    local expect="${KANBAN_EXPECTED_HOST:-}"; expect="${expect%.}"   # see kb_require_known_api_host
    if [[ -z "$expect" ]]; then
        echo "$(_kb_prog): KANBAN_EXPECTED_HOST must be set to the expected api host before sending the writeback token; refusing to send" >&2
        return 1
    fi
    # See kb_require_known_api_host — one resolution of the renderable spelling per guard.
    local api_shown; api_shown="$(kb_redact_url_userinfo "$api")"
    case "$api" in
        https://*) ;;
        *) echo "$(_kb_prog): refusing to send token — api_base is not https:// ($api_shown)" >&2; return 1 ;;
    esac
    local host; host="$(kb_url_host "$api")"
    if [[ -n "$host" && ( "$host" == "$expect" || "$host" == *".$expect" ) ]]; then
        return 0
    fi
    echo "$(_kb_prog): refusing to send token — api_base host '$host' is not '$expect' (or a subdomain of it); KANBAN_EXPECTED_HOST is the expected host" >&2
    return 1
}

# KB_API_RC_TRANSPORT — the rc kb_api returns when the request DID NOT COMPLETE, as
# distinct from rc 1, which means the server ANSWERED and the answer was not a 2xx
# (card#6680). Callers branch on the NAME; the number itself is arbitrary and pinned here.
# It is deliberately NOT 1 (the answered-non-2xx state — every existing caller's `|| …`
# reading of that must not change), NOT 2 (every CLI in this repo exits 2 for a usage error,
# so an rc propagated onward by a future `|| return $?` would read as one), and NOT 3–5
# (fetch_board_cards' own rc vocabulary, which this must not be mistaken for — the two
# fetchers have separate contracts). It is also NOT curl's exit status: curl's rc is LOGGED,
# never returned.
#
# A plain assignment, not `readonly` and not `${…:=}`: the lib is sourced more than once in
# some shells (a selftest sources it, then sources a bin that sources it again), where a
# readonly re-assignment is fatal — and a `:=` default would let an ambient environment
# variable redefine what "the request never completed" means, up to and including 0.
KB_API_RC_TRANSPORT=7

# kb_api <method> <path> [body]: fail-closed. Prints the response body on a 2xx and
# returns 0; on any failure prints a diagnostic to stderr and returns non-zero with NO
# body on stdout.
#
# Returns — THE rc contract. THE TWO NON-ZERO rcs ARE TWO DIFFERENT STATES, and a caller
# that reports the outcome of a WRITE must not merge them (card#6680):
#   rc 0                     2xx. The response body is on stdout.
#   rc 1                     THE SERVER ANSWERED and the answer was not a 2xx (403 / 404 /
#                            422 / 500 …). The outcome is KNOWN — for a write, it did not
#                            land, and the status says why. KB_HTTP carries that status.
#   rc $KB_API_RC_TRANSPORT  THE REQUEST DID NOT COMPLETE — curl exited non-zero, so this
#                            call read no answer at all and KB_HTTP is "000". For a write
#                            the outcome is UNKNOWN, NOT "nothing was written": a
#                            --max-time 28 or a connection reset mid-response answers a
#                            transaction the server may already have COMMITTED exactly as
#                            one that never arrived does.
# (The `rc N` spelling is deliberate. `^#   [0-4]  ` is fetch_board_cards' contract shape and
# tests/fetch-board-cards-caller-claims-selftest.sh asserts that exactly five lines in this
# file take it — one per rc — so that a second copy of THAT list cannot grow beside it. A
# second function's contract wearing the same shape is what that assertion cannot tell from
# the copy it exists to catch, so this one wears a different one.)
#
# WHY THE rc CARRIES IT, when KB_HTTP already holds the status. KB_HTTP is a global set
# INSIDE this function, and the caller shape that dominates this tree is
# `resp="$(kb_api …)" || …` — a command substitution, i.e. a subshell, whose assignment to
# KB_HTTP the parent never sees. The rc is the only channel that crosses that boundary,
# which is also why kb_api_status exists (see below for why the two spell one distinction
# two ways). KB_HTTP is still set on both paths and is the right read for a caller that
# does NOT capture stdout through `$(…)` — board-card-start's `_bcs_patch` is one.
#
# EXISTING CALLERS ARE UNAFFECTED: both failure rcs are non-zero, so every `|| …`, `if !`
# and `if` bucket behaves exactly as it did, and rc 1 still means what it meant on the
# non-2xx path it was reached by most. A caller that wants the distinction tests
# `[[ $rc -eq $KB_API_RC_TRANSPORT ]]`.
#
# Knobs (set by the caller):
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
#                     have committed it) and the most kb_api can say is that the
#                     request did not complete ($KB_API_RC_TRANSPORT — which is
#                     exactly that ambiguity, not a claim that nothing was
#                     written), so a non-idempotent retry can duplicate a card or
#                     burn a DL number. Set it around a read; do NOT export it
#                     process-wide over the bins that WRITE through this lib —
#                     enumerated, not recalled:
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
        # NOT rc 1 — nothing was read here, while rc 1 below means the server answered.
        KB_HTTP="000"; return "$KB_API_RC_TRANSPORT"
    }
    KB_HTTP="${out##*__HTTP__}"
    local resp="${out%__HTTP__*}"
    if [[ ! "$KB_HTTP" =~ ^2 ]]; then
        [[ -n "${KB_LOG_FILE:-}" ]] && echo "$(date -u +%FT%TZ) $method $path HTTP-$KB_HTTP $resp" >> "$KB_LOG_FILE"
        [[ "${KB_API_QUIET:-}" == 1 ]] || echo "$(_kb_prog): HTTP $KB_HTTP on $method $path" >&2
        [[ "${KB_API_ERRBODY:-}" == 1 ]] && echo "$resp" >&2
        # The server ANSWERED: rc 1, the outcome is known, and KB_HTTP names it.
        return 1
    fi
    printf '%s' "$resp"
}

# kb_api_status <method> <path> [body]: status-exposing variant. Emits
# "<http>\n<body>" to stdout and ALWAYS returns 0, so a caller capturing the
# output via $() can branch on the EXACT status (e.g. dl-a1's idempotent
# 409/422 = already-registered) — a status the kb_api global can't carry across
# a command substitution. A transport failure yields http "000".
#
# ITS DISCRIMINATOR IS THE STATUS LINE, NOT AN rc — deliberately, and this is the sibling
# half of card#6680. "000" is the ONE sentinel both functions use for "the request did not
# complete" (kb_api puts it on KB_HTTP and answers $KB_API_RC_TRANSPORT; this one puts it
# on the status line), so a caller here can already tell a transport failure from a 500 the
# server answered without parsing any message — board-card-start's card read does exactly
# that, and dl-a1's register call falls through to its FATAL arm on it.
#
# GIVING THIS FUNCTION A NON-ZERO rc TOO WOULD BREAK ITS CALLERS, which is why the one
# distinction is spelled two ways here rather than one: they capture it with a BARE
# assignment under `set -e` (`reg_out="$(kb_api_status …)"`, dl-a1-register-field), where
# any non-zero rc kills the script before the status line is ever read. "ALWAYS returns 0"
# is load-bearing, not incidental.
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
    # KB_HTTP is set on THIS path too, so the global agrees with the status line the caller
    # reads. Leaving it alone here left the PREVIOUS request's status standing while the
    # status line said 000 — two answers to one question, from one call (card#6680).
    out="$(curl "${args[@]}" -H @- -w $'\n__HTTP__%{http_code}' "$KB_API$path" 2>&1 <<<"$(kb_auth_header "$KB_TOKEN")")" || { KB_HTTP="000"; printf '000\n%s' "$out"; return 0; }
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
    # THE RENDERABLE BASE, resolved ONCE for the whole scan (card#7500). Every failure line
    # below goes to $KB_LOG_FILE, which is DURABLE — a password in it outlives the run — and
    # an api_base is allowed to carry userinfo. The two prefixes differ only in that mask;
    # the varying half is built once as $qs and shared, so the logged url and the fetched one
    # cannot drift into describing different requests.
    local api_shown; api_shown="$(kb_redact_url_userinfo "$api")"
    while :; do
        local qs="/tasks/search.json?q=board_id=${board}${qextra}&limit=200&page=${page}"
        local url="$api$qs" url_shown="$api_shown$qs"
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
                    echo "$(date -u +%FT%TZ) GET $url_shown FAILED-FETCH curl-rc=$rc" >> "$KB_LOG_FILE"
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
                echo "$(date -u +%FT%TZ) GET $url_shown HTTP-$http $resp" >> "$KB_LOG_FILE"
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
                echo "$(date -u +%FT%TZ) GET $url_shown HTTP-$http UNREADABLE-BODY $resp" >> "$KB_LOG_FILE"
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
#
# ⚠ THE MIRROR IS EXACT ONLY FOR A VALUE CARRYING ONE DIGIT RUN. kanban DL-251 narrowed the
# server's rule to exactly one run — a stored value with several ("1.5", "2026-08-23") now
# derives NO ref there, while this still concatenates them (15, 20260823). So "mirror of the
# server's canonicalize", which is what a future caller would rely on, is NOT unconditional.
#
# The two live callers are NOT alike on provenance, and saying so is the point:
#   * adopt-to-dl's MINT leg passes next-dl's output — this repo's own "DL-NNNN", one run, exact.
#   * adopt-to-dl's ALREADY-ADOPTED guard passes a card's STORED payload.dl_number, whose
#     provenance is whatever wrote the card (board UI, another tool, a human). The divergence is
#     LIVE there. It does not mis-stamp, and the direction is why: a multi-run stored value
#     yields a non-empty int here, which that guard reads as "already adopted" and REFUSES on —
#     fail-closed, no write — where the server would have derived no ref at all. What it does
#     cost is a diagnostic naming a DL that does not exist ("already adopted as DL-20042").
# Do not adopt this for a value of unknown provenance without ruling on that difference.
kb_dl_int_lenient() {
    local d; d="$(printf '%s' "${1:-}" | tr -cd '0-9')"
    [[ -n "$d" ]] || return 0
    printf '%s' "$((10#$d))"   # 10# forces base-10 so a zero-padded value isn't read as octal
}

# KB_JQ_REF_CANON — the ONE-DECORATED-INTEGER rule as a jq program fragment, for every
# lib-sourcing reader of a STORED correlation stamp. It defines `def norm:`, which answers the
# bare zero-stripped integer of a value that is exactly one digit run with optional non-digit
# decoration, and "" for anything else — the rule the board itself applies (kanban DL-251,
# `^\D*(\d+)\D*$`). A stamp that answers "" correlates to NO card.
#
# ⛔ WHY IT EXISTS, and why it is a READ-side rule. Stripping every non-digit CONCATENATES the
# runs of a multi-run value; taking the FIRST run TRUNCATES it. `1.5` becomes 15 one way and 1
# the other, and both name a real, unrelated ref. Measured, both directions, on live tools:
# promote-released-cards PATCHed a card onto an unrelated pull request (card#7587), and
# board-card-start MOVED the wrong card on an ordinary branch checkout (card#7592). The stamp
# provenance is whatever wrote the card — the board UI, another tool, an API caller, a human —
# so refusing at the MINT site alone cannot close it; the reader is where it has to be answered.
# Refusing is the recoverable direction: a card left alone is moved by hand, a card moved onto
# somebody else's ref is a durable board event that looks legitimate afterwards.
#
# ⚠ THE SECOND COPY, AND WHY IT IS NOT AN UNPINNED THIRD. `bin/promote-released-cards` carries
# this exact jq text inline: it is a vendored standalone that must not source this lib, so it
# cannot read this constant. `tests/reader-ref-canon-selftest.sh` asserts the two texts are
# BYTE-IDENTICAL and drives both through the shared table in `tests/_ref-canon-cases.sh`, so
# neither can move alone. The bash half of the same rule lives at the MINT site
# (`_kbc_require_ref_int` in bin/kbcard) and is held by that same table to CONTAINMENT, not
# equality — it is deliberately narrower (card#7536).
#
# ⚑ NOT the same thing as kb_dl_int_lenient above, which CONCATENATES on purpose for its one
# fail-closed caller. Reading a stamp of unknown provenance for a value a tool then ACTS on is
# what this constant is for.
#
# USAGE — prepend as a separate shell word; never interpolate into a double-quoted program:
#     jq -r "$KB_JQ_REF_CANON"'.payload.dl_number | norm'
# The caller filter stays SINGLE-quoted so its own jq variables survive the shell.
#
# ⛔ NO APOSTROPHE ANYWHERE IN THE VALUE BELOW. It is a single-quoted shell string; an
# apostrophe ends it and everything after is re-parsed as shell — which fails at RUNTIME, not
# at shellcheck time.
#
# `\A`/`\z`, NOT `^`/`$`: jq regexes are Oniguruma, where `^`/`$` are LINE anchors unless the
# syntax in force sets SINGLELINE, so a stored "1\n5" could satisfy an `^…$` test on its first
# line alone and normalize to 15 — the defect, straight through the guard. ⚠ HONEST SCOPE:
# measured on jq 1.7 the two spellings answer identically and no jq separating them has been
# exercised here, so the selftest pins the embedded-newline VALUE and CANNOT discriminate the
# two spellings. `[^0-9]` is a NEGATED set of ASCII bytes, so no locale collation widens it.
KB_JQ_REF_CANON='def norm: (. // "")|tostring|if test("\\A[^0-9]*[0-9]+[^0-9]*\\z") then gsub("[^0-9]";"")|sub("^0+(?=.)";"") else "" end;'

# kb_by_ref_hit <by-ref-json> <card-id>: 0 iff the by-ref response contains a row whose
# id == <card-id>. Tolerates BOTH shapes the by-ref endpoint can return — a {"data":[...]}
# envelope OR a bare top-level array — so every caller (adoption verify, field registration)
# shares one predicate instead of forking it. jq -e sets the exit status; any jq/parse error
# is a non-hit (fail-closed).
kb_by_ref_hit() {
    printf '%s' "${1:-}" | jq -e --argjson id "${2:-0}" \
        '(if type=="object" then (.data // []) else . end) | any(.[]?; .id == $id)' >/dev/null 2>&1
}
