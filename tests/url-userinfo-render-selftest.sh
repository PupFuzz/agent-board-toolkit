#!/usr/bin/env bash
# url-userinfo-render-selftest.sh — the CLASS gate for card#7500: no shipped tool may RENDER a
# URL that can carry credentials without masking the userinfo first.
#
# ─────────────────────────────── WHY A GATE AND NOT JUST A FIX ───────────────────────────────
#
# `https://user:password@host/api/v3` is a SUPPORTED api_base. `kb_require_https_host`,
# `kb_require_known_api_host` and promote-released-cards' `host_ok` all ACCEPT it — correctly,
# because they judge the HOST and nothing else, and `tests/kb-host-guard-selftest.sh` pins that
# acceptance as a row. The defect was never the guard; it was the RENDER. TEN error paths across
# three files printed the resolved base verbatim, FOUR of them into a durable on-disk log
# ($KB_LOG_FILE in the lib, $KB_BCS_LOG in board-card-start). Canon #20: a resolved secret must
# never reach an output stream, a log or a transcript, and "already emitted" means leaked.
#
# Fixing ten call sites does not close the class. The eleventh message — the one somebody adds
# next year, on a new error path, in the same scope, reaching for the same `$api` that is right
# there — re-mints it. The shipped fix is `kb_redact_url_userinfo` applied at the point the base
# is RESOLVED, once, into a `*_shown` / `*_SHOWN` variable; THIS file is what makes that stick,
# by re-deriving the population from the tree on every run and reporting any render of a raw one.
#
# ─────────────────────────────── THE PREDICATE, STATED ───────────────────────────────
#
# POPULATION — `bin/` + `hooks/`, one level, shell files only, from `_shipped-shell-lib.sh`'s
# `_shipped_shell_files` (the same expression `.github/workflows/ci.yml` shellchecks, derived
# once and shared rather than hand-copied). Re-derived every run; no file list is stored here.
#
# BASE_IDS(file) — the identifiers in that file that hold a WHOLE URL, derived by USE rather
# than by NAME. A grep for `$API` answers a question about the string "API"; the four sites the
# card was filed with came from exactly that, and re-deriving found six more. Two forms, both
# read only from non-comment lines:
#
#   F1  the identifier is handed to something that TREATS it as a base — one of the two host
#       guards, the standalone `host_ok` mirror, the RFC 3986 authority parser `kb_url_host`,
#       or the paginator `fetch_board_cards`, whose first argument is a base.
#
#   …then the ASSIGNMENT CLOSURE: an identifier whose VALUE BEGINS WITH a member is a member
#   (`local url="$api$qs"`, `KB_API="$api"`, `api="${KB_API:-}"`), iterated to a fixed point.
#
#   ⛔ BEGINS WITH, not merely mentions, and that is load-bearing rather than fussy. `out="$(curl
#   … "$KB_API$path" …)"` MENTIONS the base and holds a RESPONSE BODY; `resp="$(api "$API/…")"`
#   likewise; `host="$(kb_url_host "$api")"` holds a host. Measured: a mentions-anywhere closure
#   pulled `out`, `resp`, `host`, `cid` and a dozen more into the population and turned two dozen
#   ordinary diagnostics into findings — a gate nobody would keep. A URL is BUILT by prefixing a
#   base; anything else derived from one is a different kind of value.
#
#   ⛔ …AND NOT ACROSS A SANITISER. An assignment whose right-hand side calls
#   `kb_redact_url_userinfo` / `redact_userinfo` does NOT propagate: that is the whole point of
#   the primitive, and without this exclusion `api_shown` would join the population and every
#   correctly-redacted render would read as a finding.
#
# A FINDING is a non-comment OUTPUT statement (`echo` / `printf` / `die` / `bcs_skip`, or an
# append redirect `>>`) that interpolates a BASE_ID — subject to two narrowings, each of which
# removes a whole class of false positive rather than one line:
#
#   * SANITISED SUBSTITUTIONS ARE REMOVED FIRST. `$(kb_url_host …)`, `$(kb_redact_url_userinfo …)`
#     and `$(redact_userinfo …)` are dropped from the line before the search, because a base
#     that reaches the output only through one of those is already safe. `board-snapshot`'s
#     SKIPPED line is the live example: it prints `$(kb_url_host "$API")`, and it was clean
#     before this card existed.
#   * ONLY THE TEXT AFTER THE OUTPUT KEYWORD COUNTS. A bash line is often a whole `cmd && echo …`
#     or `cmd || die …`, and the base is routinely the argument of the LEFT half — which is a
#     wire call, not a render. Three live lines have that shape and all three are correct:
#     `kb_require_https_host "$api" || bcs_skip "…'$api_shown'…"`,
#     `[[ -n "$API" ]] || { echo "KBCARD_API not set …"; }`, and `kb_api`'s
#     `out="$(curl … "$KB_API$path" …)" || { …; printf '000\n%s' "$out"; }`. Searching the whole
#     line reports every one of them, so the gate would have to carry three hand-maintained
#     exceptions — which is the shape that goes stale. The position rule needs none.
#
# ⚠ WHAT THIS STRUCTURALLY CANNOT SEE — stated so the gate is not over-cited:
#   R1  A base rendered by a PYTHON helper. `bin/*.py` is excluded — the population is the
#       set CI runs shellcheck over, and that set excludes them by name (SC1071 cannot parse
#       python). Measured at the time of writing no `bin/*.py` renders a URL at all, so this
#       is a shape gap rather than a known miss. (⚑ A comment line whose FIRST word is
#       `shellcheck…` is parsed as a DIRECTIVE — SC1073, watched red on this very line — which
#       is why the sentence above is worded around it rather than starting with the word.)
#   R1b A base that is NEVER guarded and never paginated — handed straight to `curl` and
#       rendered. F1 keys on the guard, so there is nothing to key on. Measured over the tree
#       at the time of writing there is no such value: every config/env-supplied base reaches
#       either a host guard or `fetch_board_cards` first, and the one un-guarded url in `bin/`
#       (`_shellcheck-pinned`'s release tarball) is a hardcoded github address with no channel
#       an operator could put a credential into. A `curl`-argument form was tried and dropped:
#       it matched `"$tmp/$tarball"` and every other path-shaped interpolation on a curl line,
#       so it bought a gap it could not close at the cost of findings it could not defend.
#   R2  A base that reaches output through a variable it was assigned to in ANOTHER file. The
#       closure is per-file, because these are separate processes and the lib's callers pass
#       bases in as arguments — which F1 sees at the callee.
#   R3  CURL'S OWN diagnostics. On a URL-PARSE failure (rc 3 — an unescaped `[` or `{`
#       anywhere in the url) curl prints the ENTIRE url, userinfo included, and `kb_api` folds
#       curl's stderr into `$out` with `2>&1` and logs it. That is a real channel and a
#       separate defect: it is third-party output, so it needs scrubbing or `--globoff`, not a
#       render-site fix. No reachable route to it was found (the one caller-supplied url
#       component, `fetch_board_cards`'s search term, is `@uri`-encoded by jq before
#       interpolation, and card ids are uint-validated), so it is tracked, not fixed here.
#   R4  Whether a message is USEFUL. This asserts that the credential is gone; the paired
#       "…and the HOST is still named" legs live with each site, in the selftest that owns
#       that bin's harness (kb-host-guard, kb-board-lib, board-card-start, promote-stage-guard).
#
# ⛔ EVERY SWEEP USES `command grep`. In an interactive Claude Code shell `grep` is a function
# execing `ugrep --ignore-files`, which honours `.gitignore` and still exits 0 — a truncated
# sweep that looks exactly like a clean one.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_shipped-shell-lib.sh"
ROOT="$HERE/.."

_mktmp_scratch

# The sanitisers, and the things that treat their argument as a base. Both lists are used by the
# derivation below AND printed in the report, so a reader can see what the run keyed on.
_UUR_SANITISERS='kb_redact_url_userinfo|redact_userinfo'
_UUR_BASE_SINKS='kb_url_host|host_ok|kb_require_https_host|kb_require_known_api_host|fetch_board_cards'

# _uur_base_ids <file> — BASE_IDS(file), one per line, C-collated. See THE PREDICATE above.
_uur_base_ids() {
    awk -v sinks="$_UUR_BASE_SINKS" -v san="$_UUR_SANITISERS" '
    function note(id) { if (id != "" && !(id in base)) { base[id] = 1; grew = 1 } }
    { if ($0 !~ /^[[:space:]]*#/) lines[++n] = $0 }
    END {
        # F1 — handed to something that treats it as a base.
        for (i = 1; i <= n; i++) {
            L = lines[i]
            if (match(L, "(^|[^A-Za-z0-9_])(" sinks ")[[:space:]]+\"?\\$\\{?[A-Za-z_][A-Za-z0-9_]*")) {
                s = substr(L, RSTART, RLENGTH)
                if (match(s, /\$\{?[A-Za-z_][A-Za-z0-9_]*$/)) {
                    id = substr(s, RSTART, RLENGTH); sub(/^\$\{?/, "", id); note(id)
                }
            }
        }
        # Assignment closure, to a fixed point, NOT across a sanitiser.
        do {
            grew = 0
            for (i = 1; i <= n; i++) {
                L = lines[i]
                if (!match(L, /(^|[[:space:]]|\(|;)(local[[:space:]]+|export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=/)) continue
                lhs = substr(L, RSTART, RLENGTH)
                sub(/=$/, "", lhs); sub(/^.*[[:space:](;]/, "", lhs)
                rhs = substr(L, RSTART + RLENGTH)
                if (rhs ~ "(" san ")") continue          # the sanitiser breaks the chain
                # The VALUE must BEGIN with the member — one optional opening quote, then the
                # interpolation. Anything else (a command substitution, a literal prefix) is a
                # value derived from a base, not a url built on one.
                head = rhs; sub(/^["'\'']/, "", head)
                if (!match(head, /^\$\{?[A-Za-z_][A-Za-z0-9_]*/)) continue
                id = substr(head, RSTART, RLENGTH); sub(/^\$\{?/, "", id)
                if (id in base && id != lhs) note(lhs)
            }
        } while (grew)
        for (k in base) print k
    }' "$1" | LC_ALL=C sort -u
}

# _uur_findings <file> — every raw render, as "<file>:<lineno>: <line>". Empty = clean.
_uur_findings() {
    local f="$1" ids
    ids="$(_uur_base_ids "$f" | paste -sd'|' -)"
    [[ -n "$ids" ]] || return 0
    awk -v ids="$ids" -v san="$_UUR_SANITISERS" -v f="$f" '
    {
        if ($0 ~ /^[[:space:]]*#/) next
        L = $0
        # Drop every sanitised substitution before looking for a raw id: `$(kb_url_host "$API")`
        # prints a HOST, and a message built from one was never in this population.
        while (match(L, "\\$\\((" san "|kb_url_host)[^)]*\\)")) L = substr(L, 1, RSTART - 1) substr(L, RSTART + RLENGTH)
        # Narrow to what the output statement is actually GIVEN — the text from the FIRST output
        # keyword (or append redirect) to end of line. A keyword occurring later inside the
        # message text cannot move the cut, because the first one wins.
        if (!match(L, /(^|[^A-Za-z0-9_])(echo|printf|die|bcs_skip)([^A-Za-z0-9_]|$)/)) {
            if (!match(L, />>/)) next
        }
        L = substr(L, RSTART)
        if (match(L, "\\$\\{?(" ids ")\\}?([^A-Za-z0-9_]|$)")) printf "%s:%d: %s\n", f, NR, $0
    }' "$f"
}

# _uur_sweep <root> — the findings over the whole shipped population, one per line.
_uur_sweep() {
    local root="$1" rel
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        _uur_findings "$root/$rel" | sed "s|^$root/||"
    done < <(_shipped_shell_files "$root")
}

echo "== the derivation carries real data, and its population is CI's own (positive controls) =="
# An assertion of ABSENCE over an empty population is satisfied by everything and measures
# nothing. Three legs, before the gate itself: the file population is CI's, it is non-empty,
# and the id derivation found the bases that are certainly there.
eq "the shipped population matches what ci.yml shellchecks" "" "$(_ci_shellcheck_drift "$ROOT")"
_POP="$(_shipped_shell_files "$ROOT" | wc -l | tr -d ' ')"
eq "the shipped population is non-empty" "false" "$([[ "$_POP" -eq 0 ]] && echo true || echo false)"
_LIB_IDS="$(_uur_base_ids "$ROOT/bin/_kb-board-lib.sh")"
eq "the lib's own api base is derived as a base" "true" "$(has_line 'KB_API' "$_LIB_IDS")"
eq "…and so is the guards' parameter"            "true" "$(has_line 'api'    "$_LIB_IDS")"
eq "…and the url the paginator builds from it"   "true" "$(has_line 'url'    "$_LIB_IDS")"
eq "⛔ …but NOT the redacted spelling (the sanitiser breaks the chain)" "false" \
   "$(has_line 'api_shown' "$_LIB_IDS")"
eq "…nor the url built from the redacted spelling"                     "false" \
   "$(has_line 'url_shown' "$_LIB_IDS")"
_PRC_IDS="$(_uur_base_ids "$ROOT/bin/promote-released-cards")"
eq "the standalone mover's base is derived too"  "true"  "$(has_line 'API'       "$_PRC_IDS")"
eq "⛔ …and its redacted spelling is not"         "false" "$(has_line 'API_SHOWN' "$_PRC_IDS")"

echo "== the gate DISCRIMINATES — a planted raw render is reported (the control that can fail) =="
# Canon #9: a pass is evidence only if failure was possible. Each mutant is a real shipped file
# with ONE line added or reverted, swept in place, so the control exercises the same code path
# the gate runs in CI.
_plant() {  # <label> <src-rel> <sed-program> <expect-found: true|false>
    local label="$1" src="$2" prog="$3" want="$4" d
    d="$TMP/plant"; rm -rf "$d"; mkdir -p "$d/bin" "$d/hooks"
    # `find -exec cp`, not a glob: a glob plus `|| true` swallows a partial copy, and a mutant
    # swept over a SHORTER population than the real one is the exact failure this file exists to
    # catch elsewhere. The count is asserted below, so a partial copy reds instead of passing.
    find "$ROOT/bin" "$ROOT/hooks" -maxdepth 1 -type f \
        -exec sh -c 'cp "$1" "$2/$(basename "$(dirname "$1")")/"' _ {} "$d" \;
    eq "$label — the mutant tree is a COMPLETE copy of the population" \
       "$(_shipped_shell_files "$ROOT" | wc -l | tr -d ' ')" \
       "$(_shipped_shell_files "$d"    | wc -l | tr -d ' ')"
    sed -i "$prog" "$d/$src"
    local out; out="$(_uur_sweep "$d")"
    eq "$label" "$want" "$([[ -n "$out" ]] && echo true || echo false)"
    _PLANT_OUT="$out"
}

# M1 — a brand-new message on a brand-new error path, exactly the shape this gate exists for.
_plant "M1: a NEW message echoing the raw base is REPORTED" bin/_kb-board-lib.sh \
    '/^kb_redact_url_userinfo() {/i echo "kb: something went wrong talking to $api" >&2' true
eq "M1: …and the report names the file and the line" "true" \
   "$(has 'bin/_kb-board-lib.sh:' "$_PLANT_OUT")"

# M2 — the card's own defect, restored: the durable log line printing the unmasked url.
_plant "M2: reverting the durable FAILED-FETCH log to \$url is REPORTED" bin/_kb-board-lib.sh \
    's/GET \$url_shown FAILED-FETCH/GET $url FAILED-FETCH/' true

# M3 — the standalone mover's refuse-to-send die, reverted to the raw base.
_plant "M3: reverting the promote refusal to \$API is REPORTED" bin/promote-released-cards \
    "s/api_base '\\\$API_SHOWN'/api_base '\\\$API'/" true

# M4 — board-card-start's DURABLE bcs_skip, reverted.
_plant "M4: reverting board-card-start's durable skip to \$api is REPORTED" bin/board-card-start \
    "s/api_base '\\\$api_shown' failed/api_base '\\\$api' failed/" true

# M5 — THE NEGATIVE CONTROL, and the one that decides whether the gate says anything. An
# untouched tree must be CLEAN; a gate that reported every line would satisfy M1–M4 while being
# useless. `true` here is the sed no-op, so the copy is byte-identical to the tree.
_plant "M5: NEGATIVE CONTROL — the untouched tree is clean" bin/_kb-board-lib.sh 'p;d' false

echo "== THE GATE — no shipped tool renders a URL that can carry userinfo (card#7500) =="
_FOUND="$(_uur_sweep "$ROOT")"
if [[ -n "$_FOUND" ]]; then
    bad "a raw URL render reached an output stream — route it through kb_redact_url_userinfo (or redact_userinfo in a standalone) at the point the base is RESOLVED, not at the message:"
    printf '       %s\n' "$_FOUND" >&2
else
    ok "every renderable URL in bin/ + hooks/ ($_POP files) goes out masked"
fi

_summary "url-userinfo-render-selftest"
