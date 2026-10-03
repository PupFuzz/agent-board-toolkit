#!/usr/bin/env bash
# xtrace-token-selftest.sh — `bash -x <tool>` must never print the board bearer token (card#11204).
#
# WHAT HAPPENED. A diagnostic agent ran `bash -x kbcard …` to see why a `list` was slow, and the
# trace printed a live board token into its transcript, which then had to be rotated (rt#592).
# xtrace prints every simple command with its words EXPANDED: the token-file read, the
# `kb_auth_header "$KB_TOKEN"` that builds the header, and the token argument of every
# fetch_board_cards / kb_mask_token call all went to stderr with the value in them. The
# herestring feeding curl was worse than visible: under kb_api's `2>&1` the trace of the
# `$(kb_auth_header …)` it expanded landed INSIDE the captured response, so a traced kbcard also
# misread every answer (`show` exited 1, `comment` 3).
#
# THE FIX this file holds is the lib's kb_xtrace_off / kb_xtrace_restore pair (its header owns the
# rule): every line that expands the token suspends xtrace on that same line, and the caller's own
# trace state comes back afterwards.
#
# THE LEGS, each answering a question the others cannot:
#   § 1–2  BEHAVIOUR. The real bins, as processes, under `bash -x`, against the stub API, with a
#          planted token whose bytes are asserted ABSENT from everything the run printed. Each
#          run carries two controls, without which the absence proves nothing: the stub RECEIVED
#          that token as the bearer (so it was read and sent, not skipped), and the trace is
#          still ON after the token was handled (so nothing simply turned tracing off).
#   § 3    THE HELPER'S SEMANTICS, in-process: re-entrancy, and that a caller's `set -x` is on
#          again when a token-handling lib call returns — and stays off for a caller without it.
#   § 4    THE CALL-SITE RULE, statically, over every shipped shell file (CI's own population,
#          `_shipped_shell_files`). § 1–2 can only see the verbs they run; this reads every line,
#          and catches the common shapes of a token line run with xtrace on — a heuristic, bounded
#          below.
#   § 5    KBCARD_DEBUG=1, the per-request view offered instead of `-x`: present, and token-free.
#   § 6    A second leak, no `-x` needed: a secret pasted into a token-PATH slot is not echoed by
#          the refusal (kb_path_shown), driven through the bins, and held statically over every
#          message line that names a token-path variable — the names DERIVED to a fixed point.
#   § 7    The same pasted path under `bash -x`, at the board-env, host-env and ambient tiers,
#          through every lib-sourcing bin that resolves one and the runtime check.
#   § 8    The same pasted path under `bash -v` / `bash -xv` (card#11224): verbose mode echoes
#          every line a sourced env file holds, so the pair suspends `-v` too.
#
# WHAT A GREEN RUN DOES NOT COVER — read before citing it:
#   * § 4 IS A HEURISTIC OVER COMMON SHAPES, NOT A PROOF. The gate on a leak is the `bash -x`
#     runs (§ 1–2, § 7) and the `bash -v` / `-xv` runs (§ 8), on the paths they drive; § 4 adds a
#     line scan over every shipped file that catches the common ways to get the suspension wrong.
#     Its full predicate is stated at the leg, and is stated nowhere else — README and CHANGELOG
#     point here.
#   * § 4 sees only an expansion of, or an assignment to, a variable whose name contains `TOKEN`
#     (not `*_FILE` / `*_REGEX`), and a CALL of fetch_board_cards, kb_mask_token or
#     kb_auth_header. A token held under a name WITHOUT `TOKEN` in it (a `token` / `tok` local, a
#     header variable), or reached through an indirect `${!v}`, is invisible to it.
#   * KNOWN FALSE NEGATIVES of § 4, each scored `ok` (or not a member) while the line traces the
#     token. They are named here rather than patched into the scanner, which reads lines, not the
#     shell's grammar:
#       - a comment or a string that opens a region: `x=1  # note; kb_xtrace_off _v`, or
#         `echo "a; kb_xtrace_off _v"`, opens one the shell never ran;
#       - a multi-line `$(` / `(` block: a region opened inside it stays open past the `)` that
#         ended the subshell, and so the suspension;
#       - `set -x` inside a region: the lines after it are traced but scored `ok`;
#       - `;;` at the case arm's BODY indent: only a closer indented less than the opener closes
#         a region, so a suspension in one arm covers the next arm's lines;
#       - `select` is left out of the call-position keywords (the word after it is a name, not
#         a command); a call in its word list or body is still seen through `$(` and `do`, and
#         no false negative through it has been shown — it is named here as an exclusion;
#       - a token-named variable filled by `read`, `mapfile` / `readarray`, or as an array element
#         (`KB_TOKEN[0]=…`): not members.
#   * § 6's message rule is bounded by its PRINTER list (named at the leg; `logger`, `kb_warn` and
#     any other printer outside it are not seen) and does not follow a path into a callee's
#     positional parameters, out of a multi-field printf, into a heredoc body, or through a
#     nameref (`local -n`). § 7 and § 8 drive the bins they name; a token-path line on another
#     path is held only by § 6's message rule, which does not look at traces.
#   * A server that ECHOES the request's Authorization header into its response body (a debug
#     error page, measured once — card#9301) puts the token into the traced response variables.
#     That is a body the server sent back, not an expansion of the token, and nothing here
#     suppresses it; the stub never echoes.
#   * The standalone bins that cannot source the lib — promote-released-cards, card-completeness,
#     agent-board-toolkit-runtime-check — suspend xtrace by hand (`case $- in *x*) V=x; set +x`),
#     which § 4 reads as a region. The `bash -x` legs of the first two live in their own selftests
#     (promote-refusal-detail-selftest.sh, card-completeness-selftest.sh); release-pr-body's is in
#     release-pr-body-selftest.sh. That hand form suspends `-x` only, not `-v`, and § 8 does not
#     drive these bins: none of them sources an env file onto a live stderr today (the runtime
#     check's env reads run under `>/dev/null 2>&1`), which is what keeps them out of `-v`'s reach.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_kb-api-stub.sh"
# shellcheck source=/dev/null
source "$HERE/_shipped-shell-lib.sh"

LIB="$ROOT/bin/_kb-board-lib.sh"
KBC="$ROOT/bin/kbcard"
SNAP="$ROOT/bin/board-snapshot"
_need -r "$LIB"
_need -x "$KBC"
_need -x "$SNAP"

_mktmp_scratch --home
kb_stub_scrub_env
# shellcheck disable=SC2086
unset ${!KB_STAGE_@}
kb_stub_board_config dev 42 'export KB_STAGE_BACKLOG=48' 'export KB_STAGE_IN_PROGRESS=84'
kb_stub_install

# Low-entropy and self-describing, so no secret scanner mistakes the fixture for a credential and
# no reader mistakes a hit for anything but this token.
TOK='FAKE-BOARD-TOKEN-NOT-SECRET-000'
printf '%s\n' "$TOK" > "$KB_STUB_TOKEN_FILE"

kb_stub_route() {
    case "$1 $2" in
        "POST "*/tasks/505/comments.json)
            printf '201\n{"data":{"id":13,"task_id":505,"content":"hi"}}' ;;
        "GET "*/tasks/search.json*)
            printf '200\n{"data":[{"id":505,"name":"probe","workflow_stage_id":84,"tags":[]}],"meta":{"total":1,"last_page":1}}' ;;
        "GET "*/preload.json*)
            printf '200\n{"data":{"workflows":[{"stages":[{"id":84,"name":"In Progress"}]}]}}' ;;
        "GET "*/tasks/505.json*)
            printf '200\n{"data":{"id":505,"name":"probe","workflow_stage_id":48,"comments":[{"id":13,"task_id":505,"user_id":1,"content":"hi","deleted_at":null,"created_at":"t","updated_at":"t"}]}}' ;;
    esac
}
export -f kb_stub_route

# _resumed <stderr-file> — `true` when the trace has a line AFTER its last suspension: xtrace came
# back on once the token was handled. `false` when no suspension is in the trace at all, so a run
# that never reached a token line cannot pass this as "resumed".
_resumed() {
    awk '/^\++ kb_xtrace_off/ { last = NR } /^\++ / { if (last && NR > last) after = 1 }
         END { print (last && after) ? "true" : "false" }' "$1"
}

# _traced_leg <label> <bin> <args…> — run <bin> twice, plain and under `bash -x`, and assert the
# token is nowhere in what the traced run printed, with the controls that make that absence
# mean something.
_traced_leg() {
    local label="$1" bin="$2"; shift 2
    local rc_plain=0 rc_x=0
    kb_stub_reset
    bash "$bin" "$@" >"$TMP/plain.out" 2>"$TMP/plain.err" || rc_plain=$?
    kb_stub_reset
    bash -x "$bin" "$@" >"$TMP/x.out" 2>"$TMP/x.err" || rc_x=$?
    eq "$label: the token is NOT in the traced run's stderr"   "false" "$(_contains "$TOK" "$TMP/x.err")"
    eq "$label: …nor in its stdout"                            "false" "$(_contains "$TOK" "$TMP/x.out")"
    # Every request carried exactly the planted token — the auth log's third field is the bearer.
    eq "$label: control — the stub RECEIVED that token as the bearer" "$TOK" \
        "$(cut -f3 "$KB_STUB_AUTH_LOG" | sort -u | tr -d '\n')"
    eq "$label: control — the run WAS traced"                  "true"  "$(grep -q '^+ ' "$TMP/x.err" && echo true || echo false)"
    eq "$label: control — tracing RESUMED after the token was handled" "true" "$(_resumed "$TMP/x.err")"
    eq "$label: the traced run answers as the plain one does"  "$rc_plain" "$rc_x"
    eq "$label: …and the plain one succeeded"                  "0"     "$rc_plain"
}

echo "== § 1. kbcard under bash -x: a read, a write, and a whole-board walk =="
# RED on the pre-fix lib: every verb printed the token (the file read alone traces it), and the
# `show`/`comment` rc rows red too, because the traced herestring corrupted the response.
_traced_leg "kbcard show"    "$KBC" --board dev show --task 505
_traced_leg "kbcard comment" "$KBC" --board dev comment --task 505 --content hi
eq "kbcard comment: control — the write was really sent" "1" "$(kb_stub_count POST /tasks/505/comments.json)"
_traced_leg "kbcard list"    "$KBC" --board dev list
eq "kbcard list: control — the walk really read the board" "true" \
    "$([[ "$(kb_stub_count GET /tasks/search.json)" -ge 1 ]] && echo true || echo false)"

echo "== § 2. another lib-sourcing bin: board-snapshot under bash -x =="
printf 'dev:D\n' > "$HOME/.kanban-snapshot-boards"
export KANBAN_SNAPSHOT_BOARDS="$HOME/.kanban-snapshot-boards"
# The staleness guard board-snapshot folds in depends on the HOST, not on this test.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/agent-board-toolkit-runtime-check"
chmod +x "$TMP/bin/agent-board-toolkit-runtime-check"
_traced_leg "board-snapshot" "$SNAP"
eq "board-snapshot: control — the card is in the snapshot" "true" "$(_contains '#505' "$TMP/x.out")"

echo "== § 3. the helper: re-entrant, and the caller's own trace state survives a lib call =="
# Run in a child bash so `set -x` here cannot leak into this file's own output.
# shellcheck disable=SC2016
h="$(bash -c '
    source "$1"
    KB_API="$2"; KB_TOKEN="$3"
    say() { printf "%s=%s\n" "$1" "$(case $- in *x*) echo on ;; *) echo off ;; esac)"; } 2>/dev/null
    set -x
    f() { local a b
          kb_xtrace_off a; say outer-off
          kb_xtrace_off b; say inner-off
          kb_xtrace_restore b; say inner-restored
          kb_xtrace_restore a; say outer-restored; }
    f
    kb_token_file_read t "$4"; say after-token-read
    kb_api GET /tasks/505.json >/dev/null; say after-kb_api
    out="$(kb_xtrace_off; fetch_board_cards "$KB_API" "$KB_TOKEN" 42)"; say after-fetch
    set +x
    kb_token_file_read t "$4"; say untraced-after-token-read
    kb_xtrace_off c; kb_xtrace_restore c; say untraced-after-pair
' _ "$LIB" "$KB_STUB_API" "$TOK" "$KB_STUB_TOKEN_FILE" 2>"$TMP/h.err")"
eq "a pair turns tracing off"                                 "true" "$(has 'outer-off=off' "$h")"
eq "a NESTED pair's restore leaves it off (the outer one is still open)" "true" "$(has 'inner-restored=off' "$h")"
eq "the OUTERMOST restore turns it back on"                   "true" "$(has 'outer-restored=on' "$h")"
eq "the caller's set -x is on after kb_token_file_read"       "true" "$(has 'after-token-read=on' "$h")"
eq "…after kb_api"                                            "true" "$(has 'after-kb_api=on' "$h")"
eq "…after a fetch_board_cards call made the documented way"  "true" "$(has 'after-fetch=on' "$h")"
eq "a caller WITHOUT -x does not get it turned on by a token read" "true" "$(has 'untraced-after-token-read=off' "$h")"
eq "…nor by a pair"                                           "true" "$(has 'untraced-after-pair=off' "$h")"
eq "control: the in-process run printed no token"             "false" "$(_contains "$TOK" "$TMP/h.err")"
eq "control: …and its trace was live"                         "true"  "$(grep -q '^+ ' "$TMP/h.err" && echo true || echo false)"
# The same pair suspends `set -v` too (card#11224): verbose mode echoes every line the shell READS,
# so a sourced env file's `KBCARD_TOKEN_FILE=…` line reaches stderr verbatim. RED on the pre-fix
# pair: `v` stays on inside it. `say` reads `$-` outside any `$(…)`: bash clears `v` in a command
# substitution, so a probe inside one reads `off` whatever the caller's state.
# shellcheck disable=SC2016
hv="$(bash -c '
    source "$1"
    say() { local s=off; case $- in *v*) s=on ;; esac; printf "%s=%s\n" "$1" "$s"; }
    set -v
    f() { local a b
          kb_xtrace_off a; say outer-off
          kb_xtrace_off b; say inner-off
          kb_xtrace_restore b; say inner-restored
          kb_xtrace_restore a; say outer-restored; }
    f
    set +v
    g() { local c; kb_xtrace_off c; kb_xtrace_restore c; say untraced-after-pair; }
    g
    set -xv
    k() { local d; kb_xtrace_off d; say xv-off; kb_xtrace_restore d; say xv-restored; }
    k
' _ "$LIB" 2>/dev/null)"
eq "-v: a pair turns verbose off"                             "true" "$(has 'outer-off=off' "$hv")"
eq "-v: a NESTED pair's restore leaves it off"                "true" "$(has 'inner-restored=off' "$hv")"
eq "-v: the OUTERMOST restore turns it back on"               "true" "$(has 'outer-restored=on' "$hv")"
eq "-v: a caller WITHOUT -v does not get it turned on"        "true" "$(has 'untraced-after-pair=off' "$hv")"
eq "-xv: a pair turns verbose off with xtrace on"             "true" "$(has 'xv-off=off' "$hv")"
eq "-xv: …and its restore turns verbose back on"              "true" "$(has 'xv-restored=on' "$hv")"

echo "== § 4. the call-site rule, over every shipped shell file =="
# _xt_scan <file…> — "<file>:<line>:<ok|bad>:<text>" for every MEMBER: a non-comment line that
# expands a token-bearing variable, ASSIGNS one, or CALLS one of the three functions that take the
# token by value. THIS IS THE RULE'S ONE FULL STATEMENT; the file header says what it is worth.
#   * A token-bearing variable is DERIVED from its name, not listed: any name containing `TOKEN`,
#     except one ending `_FILE` (a path, § 6–7's subject) or `_REGEX` (a pattern), expanded as
#     `$NAME` or `${NAME…}`. `${NAME:+…}` / `${NAME+…}` and `${#NAME}` expand to a fixed word or a
#     length, never the value, and are not members — `${KANBAN_WRITEBACK_TOKEN:+set}` is the
#     spelling for "is it set". An indirect `${!v}` is not seen at all.
#   * An assignment is `NAME=<value>` at a word start (after line start, whitespace, `;` `&` `|`
#     `(` `{`, so `local NAME=…` too) whose value word holds a `$` or a backquote — xtrace prints
#     it as `NAME=<expanded value>`; a literal value (`KB_TOKEN=""`) is not a member — and
#     `printf -v NAME`, whatever follows it.
#   * A call is the name in command position — line start, or after `;` `&` `|` `(` `{` `$(`, or
#     after `then`/`do`/`else`, or after a WHOLE word `if`/`elif`/`while`/`until`/`!`/`command`/
#     `time` and whitespace — followed by whitespace. A name in an argument list, a message, or
#     its own definition is not a call.
# EVERY expansion and call on a member line is judged, not only the first; the line is `ok` only
# when xtrace is off at each of them:
#   * a `kb_xtrace_off <var>` EARLIER on the line that is UNCONDITIONAL — it starts the line, or
#     follows a plain `;` with no `if`/`then`/`do`/`else`/`elif`/`while`/`until`/`for`/`case`/
#     `select`, `{`, `}`, `(`, `)`, `|`, `&`, `&&` or `||` before it on the line — with no
#     `kb_xtrace_restore <var>` between it and the expansion;
#   * or a `kb_xtrace_off` (bare or not) directly after `(` / `$(`, with the expansion inside
#     that same parenthesis — the subshell ends the suspension, so the bare form is sound there;
#   * or the line is inside a REGION and no restore of it comes earlier on the line. A region
#     OPENS on a line holding an unconditional `kb_xtrace_off <var>` (as above) with no restore
#     of <var> after it on that line — never inside `then`/`do`/`else`/`{`/`||`/`&&`. It CLOSES
#     on any line holding `kb_xtrace_restore <var>`, anywhere on the line; on a line starting
#     `}` in column 0; or on a block closer (`fi`, `done`, `esac`, `else`, `elif`, `}`, `;;`)
#     indented LESS than the opening line, so a suspension inside a block does not cover the
#     lines after it. The standalone bins' form, `case $- in *x*) V=x; set +x …` (unconditional,
#     as above), is a region closed by any line holding `[ -z "$V" ] || set -x`, or by a
#     less-indented block closer.
# Anything else — a suspension after the expansion, one in a trailing comment, a bare one outside
# a subshell, a conditional one, an expansion after a same-line restore — is `bad`. The rule reads
# lines, not the shell's grammar. Some constructs it cannot place are scored `bad`, the safe
# direction (a region opened after a `$(…)` on the same line, a `{ …; }` group); others are
# scored `ok` while the line traces the token — the header's KNOWN FALSE NEGATIVES.
_xt_scan() {
    awk '
        function cmdpos_all(s, name,   r, rest, off, out) {
            # every position where <name> stands in command position in s (the start of the
            # match, separator included), space-separated
            r = "(([;&|({]|\\$\\(|then|do|else)[[:space:]]*|(^|[^A-Za-z0-9_])(if|elif|while|until|command|time|!)[[:space:]]+)" name "([[:space:]]|;|\\)|$)"
            out = ""
            if (match(s, "^[[:space:]]*" name "([[:space:]]|;|\\)|$)")) out = " 1"
            rest = s; off = 0
            while (match(rest, r)) {
                out = out " " (off + RSTART)
                off += RSTART + RLENGTH - 1; rest = substr(rest, RSTART + RLENGTH)
            }
            return out
        }
        function exps(s,   rest, off, p, m, nm, after, out) {
            out = ""
            rest = s; off = 0
            while (match(rest, /\$\{?#?[A-Za-z_][A-Za-z0-9_]*/)) {
                p = off + RSTART; m = substr(rest, RSTART, RLENGTH)
                nm = m; sub(/^\$\{?/, "", nm)
                after = substr(rest, RSTART + RLENGTH, 2)
                if (nm !~ /^#/ && nm ~ /TOKEN/ && nm !~ /_FILE$/ && nm !~ /_REGEX$/ &&
                    !(m ~ /^\$\{/ && (after ~ /^:\+/ || after ~ /^\+/)))
                    out = out " " p
                off += RSTART + RLENGTH - 1; rest = substr(rest, RSTART + RLENGTH)
            }
            # an ASSIGNMENT to a token-named variable whose value expands something — traced as
            # `NAME=<value>` — and a `printf -v NAME`
            rest = s; off = 0
            while (match(rest, /(^|[[:space:];&|({])[A-Za-z_][A-Za-z0-9_]*=/)) {
                p = off + RSTART; m = substr(rest, RSTART, RLENGTH)
                if (m !~ /^[A-Za-z_]/) { p++; m = substr(m, 2) }
                nm = m; sub(/=$/, "", nm)
                after = substr(rest, RSTART + RLENGTH)
                match(after, "^(\"[^\"]*\"|\047[^\047]*\047|[^[:space:];&|\047\"])*")
                if (nm ~ /TOKEN/ && nm !~ /_FILE$/ && nm !~ /_REGEX$/ && substr(after, 1, RLENGTH) ~ /[$`]/)
                    out = out " " p
                rest = after; off = p + length(m) - 1
            }
            rest = s; off = 0
            while (match(rest, /printf[[:space:]]+-v[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                p = off + RSTART; m = substr(rest, RSTART, RLENGTH)
                nm = m; sub(/^printf[[:space:]]+-v[[:space:]]+/, "", nm)
                if (nm ~ /TOKEN/ && nm !~ /_FILE$/ && nm !~ /_REGEX$/) out = out " " p
                off += RSTART + RLENGTH - 1; rest = substr(rest, RSTART + RLENGTH)
            }
            return out cmdpos_all(s, "(fetch_board_cards|kb_mask_token|kb_auth_header)")
        }
        # plain(pre) — the text before a statement runs it unconditionally
        function plain(pre) {
            if (pre ~ /^[[:space:]]*$/) return 1
            if (pre !~ /;[[:space:]]*$/) return 0
            if (pre ~ /[{}()|&]/) return 0
            if (pre ~ /(^|[^A-Za-z0-9_])(if|then|do|else|elif|while|until|for|case|select)([^A-Za-z0-9_]|$)/) return 0
            return 1
        }
        function rre(v) { return "kb_xtrace_restore[[:space:]]+" v "([^A-Za-z0-9_]|$)" }
        function srestored(s, v) { return s ~ /\|\|[[:space:]]*set -x/ && index(s, "\"$" v "\"") }
        function ind(s) { match(s, /^[[:space:]]*/); return RLENGTH }
        function closer(s, i) { return s ~ /^[[:space:]]*(fi|done|esac|else|elif|\}|;;)([[:space:];]|$)/ && ind(s) < i }
        # inparen(s, a, b) — position b is still inside the parenthesis opened at position a
        function inparen(s, a, b,   i, d, c) {
            d = 0
            for (i = a; i < b; i++) {
                c = substr(s, i, 1)
                if (c == "(") d++
                else if (c == ")" && --d == 0) return 0
            }
            return d > 0
        }
        function covered(s, q,   pq, rest, off, p, pre, post, v) {
            pq = substr(s, 1, q - 1)
            if (reg != "" && pq !~ rre(reg)) return 1
            if (sreg != "" && !srestored(pq, sreg)) return 1
            rest = pq; off = 0
            while (match(rest, /kb_xtrace_off/)) {
                p = off + RSTART
                pre = substr(s, 1, p - 1); post = substr(s, p + 13)
                if (pre ~ /\([[:space:]]*$/ && inparen(s, p - 1, q)) return 1
                if (match(post, /^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                    v = substr(post, RSTART, RLENGTH); sub(/^[[:space:]]+/, "", v)
                    if (plain(pre) && substr(s, p, q - p) !~ rre(v)) return 1
                }
                off = p + 12; rest = substr(pq, off + 1)
            }
            return 0
        }
        FNR == 1 { reg = ""; sreg = "" }
        /^[[:space:]]*#/ { next }
        {
            line = $0
            e = exps(line)
            if (e != "") {
                n = split(e, Q, " "); v = "ok"
                for (i = 1; i <= n; i++) if (Q[i] != "" && !covered(line, Q[i] + 0)) { v = "bad"; break }
                printf "%s:%d:%s:%s\n", FILENAME, FNR, v, line
            }
            # region bookkeeping, AFTER the verdict: an opening line does not cover itself
            if (reg != "" && (line ~ rre(reg) || line ~ /^}/ || closer(line, regi))) reg = ""
            if (sreg != "" && (srestored(line, sreg) || closer(line, sregi))) sreg = ""
            if (reg == "") {
                rest = line; off = 0
                while (match(rest, /kb_xtrace_off[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                    p = off + RSTART; rs = RSTART; rl = RLENGTH
                    o = substr(rest, rs, rl); sub(/^kb_xtrace_off[[:space:]]+/, "", o)
                    if (plain(substr(line, 1, p - 1)) && substr(line, p + 13) !~ rre(o)) { reg = o; regi = ind(line) }
                    off += rs + rl - 1; rest = substr(rest, rs + rl)
                }
            }
            if (sreg == "" && match(line, /case \$- in \*x\*\) [A-Za-z_][A-Za-z0-9_]*=x; set \+x/) && plain(substr(line, 1, RSTART - 1))) {
                o = substr(line, RSTART, RLENGTH); sub(/^case \$- in \*x\*\) /, "", o); sub(/=x.*/, "", o)
                sreg = o; sregi = ind(line)
            }
        }
    ' "$@"
}
_xt_violations() { grep -E '^[^:]+:[0-9]+:bad:' || true; }

mapfile -t SHIPPED < <(_shipped_shell_files "$ROOT")
eq "the population of shipped shell files is non-empty" "true" "$([[ ${#SHIPPED[@]} -gt 0 ]] && echo true || echo false)"
members="$(cd "$ROOT" && _xt_scan "${SHIPPED[@]}")"
echo "  denominator — every token-expanding line in the shipped shell (re-derived each run):"
printf '%s\n' "$members" | cut -d: -f1-3 | sed 's/^/    /'
eq "the rule has members to hold (an empty set would pass vacuously)" "true" "$([[ -n "$members" ]] && echo true || echo false)"
# A member whose trace prints no token, dispositioned by file and text with the reason; a
# disposition outliving its line reds below.
XT_DISPOSED=(
  'bin/promote-released-cards|body="${body//"$TOKEN"/***}"|an assignment is traced as its RESULT, and the result is the body with every occurrence of the token replaced'
)
_xt_undisposed() {
    local m d f rest t ok
    while IFS= read -r m; do
        [[ -n "$m" ]] || continue
        ok=""
        for d in "${XT_DISPOSED[@]}"; do
            f="${d%%|*}"; rest="${d#*|}"; t="${rest%%|*}"
            [[ "$m" == "$f:"* && "$m" == *"$t"* ]] && ok=1
        done
        [[ -n "$ok" ]] || printf '%s\n' "$m"
    done
}
eq "every member suspends xtrace before its first expansion" "" "$(printf '%s\n' "$members" | _xt_violations | _xt_undisposed)"
for d in "${XT_DISPOSED[@]}"; do
    f="${d%%|*}"; rest="${d#*|}"; t="${rest%%|*}"
    eq "§ 4 disposition still names a live member: $f" "true" "$(has "$t" "$(printf '%s\n' "$members" | grep -F "$f:" || true)")"
done

# CONTROLS on the predicate, each a planted line in a scratch file.
cat > "$TMP/plant.sh" <<'PLANT'
cards="$(fetch_board_cards "$KB_API" "$KB_TOKEN" 42)"
x=1; kb_mask_token out "$tok" "$body"
hdr="$(kb_auth_header "$t")"
tok_copy="$KB_TOKEN"
declare -F kb_mask_token >/dev/null
for f in kb_mask_token fetch_board_cards; do :; done
# fetch_board_cards "$KB_API" "$KB_TOKEN" in a comment
cards="$(kb_xtrace_off; fetch_board_cards "$KB_API" "$KB_TOKEN" 42)"
kb_mask_token() {
  if [ -z "$board" ] || [ -z "${KANBAN_WRITEBACK_TOKEN:-}" ] || [ -z "$promote" ]; then
  if [ -z "$board" ] || [ -z "${KANBAN_WRITEBACK_TOKEN:+set}" ] || [ -z "$promote" ]; then
f="$KBCARD_TOKEN_FILE" r="$CARD_TOKEN_REGEX" n="${#KB_TOKEN}"
hdr="$(kb_auth_header "$KB_TOKEN")"; kb_xtrace_off _x; kb_xtrace_restore _x
tok_copy="$KB_TOKEN"   # kb_xtrace_off _x
kb_xtrace_off; tok_copy="$KB_TOKEN"
kb_xtrace_off _r
tok_copy="$GH_TOKEN"
kb_xtrace_restore _r
tok_copy="$GH_TOKEN"
case $- in *x*) _p_x=x; set +x ;; *) _p_x= ;; esac
RAW_TOKEN="${KANBAN_WRITEBACK_TOKEN:-}"
[ -z "$_p_x" ] || set -x
echo "$RAW_TOKEN"
kb_xtrace_off _s; x="$KB_TOKEN"; kb_xtrace_restore _s
y="$KB_TOKEN"
(kb_xtrace_off; fetch_board_cards "$API" "$KB_TOKEN" 1)
kb_xtrace_off _m
x=1; kb_xtrace_restore _m
echo "leak $KB_TOKEN"
if [[ -n "$z" ]]; then kb_xtrace_off _c; fi
echo "leak $KB_TOKEN"
kb_xtrace_restore _c
[[ -n "$z" ]] && kb_xtrace_off _e
echo "$KB_TOKEN"
kb_xtrace_restore _e
[[ -n "$z" ]] || kb_xtrace_off _f
echo "$KB_TOKEN"
kb_xtrace_restore _f
for _z in $list; do kb_xtrace_off _l; done
echo "$KB_TOKEN"
kb_xtrace_restore _l
{ kb_xtrace_off _d; }
echo "$KB_TOKEN"
kb_xtrace_restore _d
if [[ -n "$z" ]]; then
    kb_xtrace_off _h
fi
echo "$KB_TOKEN"
kb_xtrace_restore _h
local _g; kb_xtrace_off _g
echo "$KB_TOKEN"
kb_xtrace_restore _g
kb_xtrace_off _i; kb_xtrace_restore _i; echo "$KB_TOKEN"
[[ -n "$z" ]] || kb_xtrace_off _j; echo "$KB_TOKEN"; kb_xtrace_restore _j
kb_xtrace_off _k
kb_xtrace_restore _k; echo "$KB_TOKEN"
kb_xtrace_off _s; x="$KB_TOKEN"; kb_xtrace_restore _s; echo "$KB_TOKEN"
x="$(kb_xtrace_off; fetch_board_cards "$A" "$KB_TOKEN" 1)"; echo "$KB_TOKEN"
case $- in *x*) _q=x; set +x ;; *) _q= ;; esac
[ -z "$_q" ] || set -x; echo "$KB_TOKEN"
if kb_mask_token out "$t" "$b"; then :; fi
elif kb_auth_header "$t" >/dev/null; then :
while fetch_board_cards "$A" "$t" 1; do :; done
until fetch_board_cards "$A" "$t" 1; do :; done
! kb_mask_token out "$t" "$b"
command kb_auth_header "$t"
time fetch_board_cards "$A" "$t" 1
echo runtime kb_mask_token is a word here
KB_TOKEN="$(cat -- "$f")"
local GH_TOKEN="$raw"
printf -v KB_TOKEN '%s' "$raw"
KB_TOKEN=""
kb_xtrace_off _t; KB_TOKEN="$(cat -- "$f")"; kb_xtrace_restore _t
for _z in $list; do x=1; kb_xtrace_off _ka; done; echo "$KB_TOKEN"; kb_xtrace_restore _ka
[[ -n "$z" ]] || { x=1; kb_xtrace_off _kb; }; echo "$KB_TOKEN"; kb_xtrace_restore _kb
PLANT
planted="$(_xt_scan "$TMP/plant.sh")"
pv="$(printf '%s\n' "$planted" | _xt_violations)"
_pm() { has ":$1:" "$planted"; }
_pv() { has ":$1:bad:" "$pv"; }
eq "control: an unguarded fetch_board_cards call is a violation"   "true"  "$(_pv 1)"
eq "control: an unguarded kb_mask_token after ';' is a violation"  "true"  "$(_pv 2)"
eq "control: a kb_auth_header inside \$( is a violation"           "true"  "$(_pv 3)"
eq "control: a bare \$KB_TOKEN expansion is a violation"           "true"  "$(_pv 4)"
eq "control: declare -F naming it is NOT a member"                 "false" "$(_pm 5)"
eq "control: a loop word list naming it is NOT a member"           "false" "$(_pm 6)"
eq "control: a comment naming it is NOT a member"                  "false" "$(_pm 7)"
eq "control: the guarded \$( spelling is a member…"                "true"  "$(_pm 8)"
eq "control: …and NOT a violation"                                 "false" "$(_pv 8)"
eq "control: its own definition line is NOT a member"              "false" "$(_pm 9)"
eq "control: release-pr-body's pre-fix line (\${KANBAN_WRITEBACK_TOKEN:-}) is a violation" "true" "$(_pv 10)"
eq "control: the \${…:+set} spelling of that line is NOT a member" "false" "$(_pm 11)"
eq "control: *_FILE, *_REGEX and \${#…} are NOT members"           "false" "$(_pm 12)"
eq "control: a suspension AFTER the expansion is a violation"      "true"  "$(_pv 13)"
eq "control: a suspension in a trailing COMMENT is a violation"    "true"  "$(_pv 14)"
eq "control: a BARE suspension outside a subshell is a violation"  "true"  "$(_pv 15)"
eq "control: a line inside an open kb_xtrace_off region is ok"     "false" "$(_pv 17)"
eq "control: …and the line after its restore is a violation"       "true"  "$(_pv 19)"
eq "control: a line inside a standalone \`case \$- …set +x\` region is ok" "false" "$(_pv 21)"
eq "control: …and the line after its \`|| set -x\` is a violation"  "true"  "$(_pv 23)"
eq "control: a same-line pair does not leave a region open"        "true"  "$(_pv 25)"
eq "control: a bare suspension directly after \`(\` is ok"         "false" "$(_pv 26)"
# Rows 27–60: each line below was scored ok by the previous scanner, and each but the `{ …; }`
# group and the plain `;` control traces the token when run (the group is a shape the rule does
# not place, scored bad on purpose).
eq "control: a MID-LINE restore closes the region — the next token line is a violation" "true" "$(_pv 29)"
eq "control: a region is not opened inside \`then … fi\`"         "true"  "$(_pv 31)"
eq "control: …nor after \`&&\`"                                    "true"  "$(_pv 34)"
eq "control: …nor after \`||\`"                                    "true"  "$(_pv 37)"
eq "control: …nor inside \`do … done\` (zero iterations skip it)"  "true"  "$(_pv 40)"
eq "control: …nor inside a \`{ …; }\` group"                       "true"  "$(_pv 43)"
eq "control: a suspension inside a block does not cover the lines after its less-indented \`fi\`" "true" "$(_pv 48)"
eq "control: a suspension after a plain \`;\` does open a region"  "false" "$(_pv 51)"
eq "control: an expansion after a same-line pair is a violation"     "true"  "$(_pv 53)"
eq "control: a same-line suspension after \`||\` does not count"   "true"  "$(_pv 54)"
eq "control: inside a region, an expansion after a same-line restore is a violation" "true" "$(_pv 56)"
eq "control: EVERY expansion on a line is judged, not only the first" "true" "$(_pv 57)"
eq "control: …an expansion after a suspended \$(…) closes is a violation" "true" "$(_pv 58)"
eq "control: …and one after the standalone form's same-line \`|| set -x\`" "true" "$(_pv 60)"
# Rows 61–75 (card#11224). 61–67: a call in command position after `if`, `elif`, `while`,
# `until`, `!`, `command` or `time` — none was a member before, so each traced the token unseen.
eq "control: a call after \`if\` is a violation"                    "true"  "$(_pv 61)"
eq "control: a call after \`elif\` is a violation"                  "true"  "$(_pv 62)"
eq "control: a call after \`while\` is a violation"                 "true"  "$(_pv 63)"
eq "control: a call after \`until\` is a violation"                 "true"  "$(_pv 64)"
eq "control: a call after \`!\` is a violation"                     "true"  "$(_pv 65)"
eq "control: a call after \`command\` is a violation"               "true"  "$(_pv 66)"
eq "control: a call after \`time\` is a violation"                  "true"  "$(_pv 67)"
eq "control: a keyword ending another word (\`runtime\`) does not make a call" "false" "$(_pm 68)"
# 69–73: an ASSIGNMENT to a TOKEN-named variable is traced as `NAME=<value>`, so it is a member
# when its value expands something; a literal value (`KB_TOKEN=""`) traces nothing secret.
eq "control: \`KB_TOKEN=\"\$(cat …)\"\` is a violation"             "true"  "$(_pv 69)"
eq "control: \`local GH_TOKEN=\"\$raw\"\` is a violation"            "true"  "$(_pv 70)"
eq "control: \`printf -v KB_TOKEN …\` is a violation"              "true"  "$(_pv 71)"
eq "control: a literal assignment (\`KB_TOKEN=\"\"\`) is NOT a member" "false" "$(_pm 72)"
eq "control: a suspended assignment is a member…"                  "true"  "$(_pm 73)"
eq "control: …and NOT a violation"                                 "false" "$(_pv 73)"
# 74–75: plain()'s two sub-rules, each the only test that rejects its line's suspension.
eq "control: a suspension after \`;\` inside \`do … done\` does not count (the keyword test)" "true" "$(_pv 74)"
eq "control: a suspension after \`;\` inside \`|| { …; }\` does not count (the [{}()|&] test)" "true" "$(_pv 75)"

echo "== § 5. KBCARD_DEBUG=1: the request a trace would show, without the token =="
# The alternative this card offers to reaching for `-x`: one stderr line per request. RED when the
# line is missing, carries the bearer, or prints when the knob is unset.
kb_stub_reset
rc=0; KBCARD_DEBUG=1 bash "$KBC" --board dev show --task 505 >/dev/null 2>"$TMP/dbg.err" || rc=$?
eq "debug: the verb still succeeds"                       "0"     "$rc"
eq "debug: the request is named with its method, url and status" "true" \
    "$(grep -qE '^kbcard: debug: GET https://kanban\.test/api/v3/tasks/505\.json -> HTTP 200 \([0-9]+ ms\)$' "$TMP/dbg.err" && echo true || echo false)"
eq "debug: …and the token is not in it"                   "false" "$(_contains "$TOK" "$TMP/dbg.err")"
kb_stub_reset
KBCARD_DEBUG=1 bash "$KBC" --board dev list >/dev/null 2>"$TMP/dbg-list.err" || true
eq "debug: control — the walk read at least one page"     "true" \
    "$([[ "$(kb_stub_count GET /tasks/search.json)" -ge 1 ]] && echo true || echo false)"
eq "debug: a whole-board walk prints one line per page it read" \
    "$(kb_stub_count GET /tasks/search.json)" "$(grep -c 'debug: GET .*/tasks/search\.json' "$TMP/dbg-list.err" || true)"
kb_stub_reset
bash "$KBC" --board dev show --task 505 >/dev/null 2>"$TMP/nodbg.err" || true
eq "control: without the knob there is no debug line"     "false" "$(_contains 'debug:' "$TMP/nodbg.err")"

echo "== § 6. a credential pasted into a token-PATH slot is not echoed by the refusal (card#11204) =="
# A different leak from the trace, and no `-x` is needed for it: a secret pasted where a token FILE
# is declared was treated as a path, and the refusal that the path is unreadable printed it
# (`token file not readable: <the secret>`). The refusals now go through the lib's kb_path_shown,
# which prints only a value shaped like a path whose directory exists (the predicate rows below).
# RED on the pre-fix lib: the value is in stderr. CONTROLS: the refusal still names the problem,
# and a real path is still printed whole.
PASTED='FAKE-BOARD-TOKEN-NOT-SECRET-001'
printf 'export KB_BOARD_ID=43\nexport KB_STAGE_BACKLOG=48\nexport KBCARD_TOKEN_FILE="%s"\n' "$PASTED" > "$HOME/.kanban-pasted-board.env"
printf 'export KB_BOARD_ID=44\nexport KBCARD_TOKEN_FILE="%s"\n' "$TMP/no-such-token-file" > "$HOME/.kanban-gone-board.env"
kb_stub_reset
rc=0; bash "$KBC" --board pasted show --task 505 >"$TMP/p.out" 2>"$TMP/p.err" || rc=$?
eq "kbcard, pasted slot: refused before any request (rc 2)"        "2"     "$rc"
eq "kbcard, pasted slot: …and nothing was sent"                    "0"     "$(kb_stub_total)"
eq "kbcard, pasted slot: the value is NOT in stderr"               "false" "$(_contains "$PASTED" "$TMP/p.err")"
eq "kbcard, pasted slot: …nor in stdout"                           "false" "$(_contains "$PASTED" "$TMP/p.out")"
eq "kbcard, pasted slot: the refusal still names the problem"      "true"  "$(_contains 'token file not readable: <value not shown: not a path>' "$TMP/p.err")"
# A pasted secret whose alphabet includes `/` (standard base64) is path-SHAPED; it is withheld
# because its directory part does not exist.
PASTED_SL='abcd/EFGH+ijkl/MNOP0123456789qrst'
printf 'export KB_BOARD_ID=46\nexport KB_STAGE_BACKLOG=48\nexport KBCARD_TOKEN_FILE="%s"\n' "$PASTED_SL" > "$HOME/.kanban-pastedsl-board.env"
rc=0; bash "$KBC" --board pastedsl show --task 505 >"$TMP/psl.out" 2>"$TMP/psl.err" || rc=$?
eq "kbcard, pasted slot holding a '/': refused before any request (rc 2)" "2" "$rc"
eq "kbcard, pasted slot holding a '/': the value is in neither stream" "false" "$(has "$PASTED_SL" "$(cat "$TMP/psl.out" "$TMP/psl.err")")"
eq "kbcard, pasted slot holding a '/': the refusal still names the problem" "true" "$(_contains 'token file not readable: <value not shown: not a path>' "$TMP/psl.err")"
rc=0; bash "$KBC" --board gone show --task 505 >/dev/null 2>"$TMP/g.err" || rc=$?
eq "control: a real but missing path is refused the same way (rc 2)" "2"    "$rc"
eq "control: …and that PATH is still printed whole"                "true"  "$(_contains "token file not readable: $TMP/no-such-token-file" "$TMP/g.err")"

printf 'pasted:P\n' > "$HOME/.kanban-snapshot-boards"
bash "$SNAP" >"$TMP/ps.out" 2>"$TMP/ps.err" || true
eq "board-snapshot, pasted slot: the value is in neither stream"   "false" "$(has "$PASTED" "$(cat "$TMP/ps.out" "$TMP/ps.err")")"
eq "board-snapshot, pasted slot: the board is still reported unread, naming why" "true" \
    "$(has 'token file unreadable: <value not shown: not a path>' "$(cat "$TMP/ps.out" "$TMP/ps.err")")"

# THE HELPER'S PREDICATE, row by row: shown only when the value is shaped like a path — a `/` or
# `\`, or a leading `~` or `.` — carries no whitespace, AND its directory part (everything before
# the last `/` or `\`, `~` expanded; `.` when there is no separator) exists. Run from a directory
# holding `rel/` and a Linux directory literally named `C:\creds`, so the `\` split is exercised.
# The secret with `/` in it is the standard-base64 shape a shape-only predicate printed.
P6D="$TMP/pshown"; mkdir -p "$P6D/rel" "$P6D/C:\creds"
P6S='abcd/EFGH+ijkl/MNOP0123456789qrst'
h6="$(cd "$P6D" && bash -c 'source "$1"; shift; for v in "$@"; do printf "%s\t%s\n" "$v" "$(kb_path_shown "$v")"; done' _ "$LIB" \
    "$TMP/tok" '~/tok' ./tok rel/tok 'C:\creds\tok' .kanban-tok /tok \
    "$PASTED" ghp_NOTAREALTOKEN0000 'tok en' '/a b/tok' '' \
    "$P6S" /no-such-dir-c11204/tok rel-missing/tok '~/no-such-dir-c11204/tok' 'C:\nowhere\tok')"
for v in "$TMP/tok" '~/tok' ./tok rel/tok 'C:\creds\tok' .kanban-tok /tok; do
    eq "kb_path_shown prints the path [$v]" "true" "$(has_line "$v"$'\t'"$v" "$h6")"
done
for v in "$PASTED" ghp_NOTAREALTOKEN0000 'tok en' '/a b/tok' '' \
         "$P6S" /no-such-dir-c11204/tok rel-missing/tok '~/no-such-dir-c11204/tok' 'C:\nowhere\tok'; do
    eq "kb_path_shown withholds [$v]" "true" "$(has_line "$v"$'\t<value not shown: not a path>' "$h6")"
done

# THE MESSAGE RULE, over every shipped shell file. Its variables are DERIVED, not listed: the
# token-PATH names are KBCARD_TOKEN_FILE and KB_TOKEN_FILE, plus every name ASSIGNED from one of
# them, from a call of kb_declared_token_file (or the store-pointer readers
# kb_coord_store_token_file / _rc_store_pointer), from `kb_board_env_get … KBCARD_TOKEN_FILE` (to
# the array ELEMENT that key lands in), from a jq `.token_file`, or from a PRODUCER — a function
# whose output is one such value, `printf '%s' "$x"` — iterated until a pass adds no name. An
# assignment counts through `=`, `local`/`declare` lists, `read` and `mapfile`, with a `\`
# continuation joined first. A name `local` to a function is scoped to that function; any other
# name is scoped to its file, or to every file when the lib sets it. A value passed through
# kb_path_shown does not propagate. The program is the awk below; the names it derived and the
# pass count are printed with the denominator.
# A MESSAGE is a non-comment line with a printer in command position — `echo`, `printf`, `die`,
# `warn`, `fail`, `say`, `bcs_skip`, `board_unread`, `fails+=`, `tokn=` (the printers the shipped
# bins use; a new printer is outside this leg) — that expands a member anywhere AFTER the printer,
# quoted or not. It is a violation unless every such member is the argument of kb_path_shown. A
# producer's own `printf` is a TRANSPORT, not a message — only on a line where it is the SOLE
# printer: a message beside it, or `echo "$(printf '%s' …)"`, is judged as a message. Outside the
# bound: a heredoc body (`cat >&2 <<EOF … $KB_TOKEN_FILE`), a nameref (`local -n r=KB_TOKEN_FILE`),
# and `logger`, `kb_warn` or any other printer not in the list. A value passed as a function
# ARGUMENT is not followed into the callee's positional parameters, and a value packed into a
# multi-field printf (next-dl's resolve_board_cfg) is followed only to that printf.
cat > "$TMP/xt-paths.awk" <<'XTAWK'
# c11204 — the token-PATH name set, derived to a fixed point (see the selftest § 6 header).
# Output modes (-v mode=…):
#   names  "<scope>\t<name>" for every derived member (scope: * = every file, a file, or file@func)
#   msgs   "<file>:<line>:<ok|bad|transport>:<text>" for every message line naming a member
function split_words(s,   i, c, nx, n, w, sp, top) {
    delete W; n = 0; w = ""; sp = 0
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1); nx = substr(s, i + 1, 1)
        top = sp ? ST[sp] : ""
        if (top == "'") { w = w c; if (c == "'") sp--; continue }
        if (c == "\\") { w = w c nx; i++; continue }
        if (top == "\"") {
            w = w c
            if (c == "\"") sp--
            else if (c == "$" && (nx == "(" || nx == "{")) { w = w nx; i++; ST[++sp] = nx }
            continue
        }
        if (c == "'") { w = w c; ST[++sp] = "'"; continue }
        if (c == "\"") { w = w c; ST[++sp] = "\""; continue }
        if (c == "$" && (nx == "(" || nx == "{")) { w = w c nx; i++; ST[++sp] = nx; continue }
        if (top == "(" && c == "(") { w = w c; ST[++sp] = "("; continue }
        if (top == "(" && c == ")") { w = w c; sp--; continue }
        if (top == "{" && c == "}") { w = w c; sp--; continue }
        if (top == "") {
            if (c ~ /[ \t]/) { if (w != "") W[++n] = w; w = ""; continue }
            if (c ~ /[;&|()]/) { if (w != "") W[++n] = w; w = ""; W[++n] = c; continue }
        }
        w = w c
    }
    if (w != "") W[++n] = w
    return n
}
function sep(x) { return x == ";" || x == "&" || x == "|" }
# member_in(text, file, func) — does text expand a member in scope here, or call a seed/producer?
function unrouted(t) { gsub(/kb_path_shown[[:space:]]+"[^"]*"/, "", t); return t }
function member_in(t, f, fn,   k, nm, sc, re) {
    t = unrouted(t)
    if (t ~ /(^|[^A-Za-z0-9_])kb_declared_token_file([^A-Za-z0-9_]|$)/) return 1
    if (t ~ /(^|[^A-Za-z0-9_])(kb_coord_store_token_file|_rc_store_pointer)([^A-Za-z0-9_]|$)/) return 1
    if (t ~ /\.token_file/) return 1
    if (t ~ /kb_board_env_get/ && t ~ /KBCARD_TOKEN_FILE/) return 1
    for (k in PROD) if (t ~ ("\\$\\([[:space:]]*" k "([^A-Za-z0-9_]|$)")) return 1
    for (k in MEM) {
        split(k, a, SUBSEP); sc = a[1]; nm = a[2]
        if (!(sc == "*" || sc == f || sc == f "@" fn)) continue
        if (nm ~ /\[/) { re = nm; gsub(/\[/, "\\[", re); gsub(/\]/, "\\]", re); re = "\\$\\{" re }
        else re = "\\$\\{?" nm "([^A-Za-z0-9_\\[]|$)"
        if (t ~ re) return 1
    }
    return 0
}
function scope_of(nm, f, fn,   base) {
    base = nm; sub(/\[.*/, "", base)
    if (fn != "" && ((f SUBSEP fn SUBSEP base) in LOCAL)) return f "@" fn
    if (f ~ /_kb-board-lib\.sh$/) return "*"
    return f
}
function add(nm, f, fn,   sc) {
    sc = scope_of(nm, f, fn)
    if (!((sc SUBSEP nm) in MEM)) { MEM[sc, nm] = 1; changed = 1 }
}
function kbeg_index(   i, j, n) {
    # index (0-based) of KBCARD_TOKEN_FILE among kb_board_env_get's KEY words in W, else -1
    for (i = 1; i <= NW; i++) if (W[i] ~ /kb_board_env_get$/) {
        n = 0
        for (j = i + 2; j <= NW && !sep(W[j]) && W[j] != ")"; j++) { if (W[j] == "KBCARD_TOKEN_FILE") return n; n++ }
    }
    return -1
}
function scan_assign(t, f, fn,   i, j, nm, rhs, d, tg, ix) {
    NW = split_words(t)
    for (i = 1; i <= NW; i++) {
        if (W[i] ~ /^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=/) {
            nm = W[i]; sub(/(\[[^]]*\])?\+?=.*/, "", nm)
            rhs = W[i]; sub(/^[^=]*=/, "", rhs)
            if (rhs == "" && W[i + 1] == "(") { d = 0; for (j = i + 1; j <= NW; j++) { rhs = rhs " " W[j]; if (W[j] == "(") d++; if (W[j] == ")" && --d == 0) break } }
            if (member_in(rhs, f, fn)) add(nm, f, fn)
        } else if (W[i] == "read" || W[i] == "mapfile" || W[i] == "readarray") {
            delete TG; tg = 0
            for (j = i + 1; j <= NW && !sep(W[j]) && W[j] !~ /^</; j++) {
                # an option that takes an argument: read's -a -d -i -n -N -p -t -u, mapfile's -d -n -O -s -u -C -c
                if ((W[i] == "read" && W[j] ~ /^-[a-zA-Z]*[adinNptu]$/ && W[j] !~ /a$/) || (W[i] != "read" && W[j] ~ /^-[a-zA-Z]*[dnOsuCc]$/)) { j++; continue }
                if (W[j] ~ /^-/) continue
                if (W[j] ~ /^[A-Za-z_][A-Za-z0-9_]*$/) TG[++tg] = W[j]
            }
            rhs = ""; d = 0
            for (; j <= NW; j++) { if (W[j] == "(") d++; if (W[j] == ")") d--; if (d <= 0 && sep(W[j])) break; rhs = rhs " " W[j] }
            if (!tg || !member_in(rhs, f, fn)) continue
            ix = (rhs ~ /kb_board_env_get/) ? kbeg_index() : -1
            if (W[i] != "read" && ix >= 0) add(TG[tg] "[" ix "]", f, fn)
            else add(TG[1], f, fn)
        }
    }
}
FNR == 1 { fn = ""; cont = ""; contno = 0 }
{
    raw = $0
    if (raw ~ /^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*[({]/) { fn = raw; sub(/\(\).*/, "", fn) }
    if (raw ~ /^[)}]/) { L[++NL] = FILENAME SUBSEP FNR SUBSEP fn SUBSEP raw; fn = ""; next }
    if (raw ~ /^[[:space:]]*#/) next
    if (cont != "") { cont = cont " " raw } else { cont = raw; contno = FNR }
    if (cont ~ /\\$/) { sub(/\\$/, "", cont); next }
    L[++NL] = FILENAME SUBSEP contno SUBSEP fn SUBSEP cont
    if (fn != "" && cont ~ /(^|[;&|{[:space:]])(local|declare|typeset)[[:space:]]/) {
        n = split_words(cont)
        for (i = 1; i <= n; i++) if (W[i] == "local" || W[i] == "declare" || W[i] == "typeset") {
            for (j = i + 1; j <= n && !sep(W[j]); j++) { v = W[j]; sub(/=.*/, "", v); if (v ~ /^[A-Za-z_][A-Za-z0-9_]*$/) LOCAL[FILENAME, fn, v] = 1 }
        }
    }
    cont = ""
}
END {
    PRINTER = "(^|[;&|({[:space:]])(echo|printf|die|warn|fail|say|bcs_skip|board_unread|fails\\+=|tokn=)"
    MEM["*", "KBCARD_TOKEN_FILE"] = 1; MEM["*", "KB_TOKEN_FILE"] = 1
    changed = 1; passes = 0
    while (changed && passes < 50) {
        changed = 0; passes++
        for (i = 1; i <= NL; i++) {
            split(L[i], a, SUBSEP); f = a[1]; ln = a[2]; fn = a[3]; t = a[4]
            scan_assign(t, f, fn)
            # a PRODUCER: a function whose output is ONE member value — `printf '%s' "$member"`
            if (fn != "" && t ~ /(^|[;&|({[:space:]])printf[[:space:]]+'%s'[[:space:]]+"[^"]*"[[:space:]]*($|[;)|])/) {
                q = t; sub(/.*printf[[:space:]]+'%s'[[:space:]]+/, "", q)
                if (member_in(q, f, fn)) {
                    if (!(fn in PROD)) changed = 1; PROD[fn] = 1
                    # A TRANSPORT only when that printf is the line's SOLE printer: a message on
                    # the same line, or a printer whose argument captures the printf, is judged.
                    r = t; sub(/(^|[;&|({[:space:]])printf[[:space:]]+'%s'[[:space:]]+"[^"]*"/, " ", r)
                    if (r !~ PRINTER) TRANSPORT[f, ln] = 1
                }
            }
        }
    }
    if (mode == "names") {
        for (k in MEM) { split(k, a, SUBSEP); printf "%s\t%s\n", a[1], a[2] }
        for (k in PROD) printf "producer\t%s\n", k
        printf "passes\t%d\n", passes
        exit
    }
    for (i = 1; i <= NL; i++) {
        split(L[i], a, SUBSEP); f = a[1]; ln = a[2]; fn = a[3]; t = a[4]
        if (!match(t, PRINTER)) continue
        # From the printer on: a quoted ARGUMENT before it (`kb_read_token "$f" || die …`) is not
        # part of the message. A member there at all makes the line a message member; one left
        # after removing every routed `kb_path_shown "$x"` makes it a violation.
        s = substr(t, RSTART)
        if (!member_exp(s, f, fn)) continue
        v = member_exp(unrouted(s), f, fn) ? "bad" : "ok"
        if ((f SUBSEP ln) in TRANSPORT) v = "transport"
        printf "%s:%d:%s:%s\n", f, ln, v, t
    }
}
# member_exp — a member expansion, or a seed/producer call, anywhere in t (routing NOT removed)
function member_exp(t, f, fn,   k, nm, sc, re) {
    if (t ~ /(^|[^A-Za-z0-9_])(kb_declared_token_file|kb_coord_store_token_file|_rc_store_pointer)([^A-Za-z0-9_]|$)/) return 1
    for (k in PROD) if (t ~ ("\\$\\([[:space:]]*" k "([^A-Za-z0-9_]|$)")) return 1
    for (k in MEM) {
        split(k, a2, SUBSEP); sc = a2[1]; nm = a2[2]
        if (!(sc == "*" || sc == f || sc == f "@" fn)) continue
        if (nm ~ /\[/) { re = nm; gsub(/\[/, "\\[", re); gsub(/\]/, "\\]", re); re = "\\$\\{" re }
        else re = "\\$\\{?" nm "([^A-Za-z0-9_\\[]|$)"
        if (t ~ re) return 1
    }
    return 0
}
XTAWK
_xt_paths() { local mode="$1"; shift; awk -v mode="$mode" -f "$TMP/xt-paths.awk" "$@"; }
pnames="$(cd "$ROOT" && _xt_paths names "${SHIPPED[@]}")"
pmsgs="$(cd "$ROOT" && _xt_paths msgs "${SHIPPED[@]}")"
echo "  derived token-PATH names (scope<TAB>name), re-derived each run:"
printf '%s\n' "$pnames" | sort | sed 's/^/    /'
echo "  denominator — every message line naming one (re-derived each run):"
printf '%s\n' "$pmsgs" | cut -d: -f1-3 | sed 's/^/    /'
eq "the derivation found names past its two seeds"                 "true" "$(has_line $'bin/board-card-start\ttokfile' "$pnames")"
eq "the message rule has members to hold"                          "true" "$([[ -n "$pmsgs" ]] && echo true || echo false)"
# Members whose value is never a pasted secret, or never reaches a reader, dispositioned by file
# and text with the reason. A disposition outliving its line reds below.
PATH_MSG_DISPOSED=(
  "bin/next-dl|printf '%s\t%s\t%s' \"\$KB_API\" \"\$KB_BOARD_ID\" \"\$KB_TOKEN_FILE\"|resolve_board_cfg hands the resolved config to its caller through \$(…), after kb_resolve_env found the path readable; it is read back, never printed"
  "bin/agent-board-toolkit-runtime-check|keep \$keep|\$keep is a TOK_PATHS key or rc_store_real, and both are admitted only for a file that passes -r and -s — a real file, never a pasted value"
)
undisposed="$(printf '%s\n' "$pmsgs" | grep -E '^[^:]+:[0-9]+:bad:' | while IFS= read -r m; do
    ok=""
    for d in "${PATH_MSG_DISPOSED[@]}"; do
        f="${d%%|*}"; rest="${d#*|}"; t="${rest%%|*}"
        [[ "$m" == "$f:"* && "$m" == *"$t"* ]] && ok=1
    done
    [[ -n "$ok" ]] || printf '%s\n' "$m"
done)"
eq "every such message routes each token-path value through kb_path_shown (or is dispositioned)" "" "$undisposed"
for d in "${PATH_MSG_DISPOSED[@]}"; do
    f="${d%%|*}"; rest="${d#*|}"; t="${rest%%|*}"
    eq "disposition still names a live violation: $f" "true" "$(has "$t" "$(printf '%s\n' "$pmsgs" | grep -F "$f:" || true)")"
done
# CONTROLS: a fixture whose aliases no list names. hop2 is assigned from hop1 BEFORE hop1 is
# assigned, so only a second pass can find it.
cat > "$TMP/plant6.sh" <<'PLANT'
hop2="$hop1"
hop1="$KB_TOKEN_FILE"
echo "x: cannot read $hop2" >&2
f() {
    local mytok
    mytok="$(kb_declared_token_file "$e" "$x")"
    local alias2="$mytok"
    warn "cannot read $alias2"
    warn "cannot read $(kb_path_shown "$alias2")"
    echo "a $(kb_path_shown "$KB_TOKEN_FILE") b $KB_TOKEN_FILE"
    kb_read_token "$alias2" || die "unreadable: $(kb_path_shown "$alias2")"
}
g() { echo "unrelated $alias2"; }
mapfile -t vals < <(kb_board_env_get "$e" KB_BOARD_ID \
    KBCARD_TOKEN_FILE)
id="${vals[0]}"; tf="${vals[1]}"
say "board $id"
say "token file $tf"
shown="$(kb_path_shown "$hop1")"
echo "$shown"
pick() {
    local c="$KB_TOKEN_FILE"
    printf '%s' "$c"; echo "pick: using $c" >&2
}
show() {
    echo "$(printf '%s' "$KB_TOKEN_FILE")"
}
prod() {
    printf '%s' "$KB_TOKEN_FILE"
}
PLANT
p6n="$(_xt_paths names "$TMP/plant6.sh")"
p6="$(_xt_paths msgs "$TMP/plant6.sh")"
_p6v() { grep -q "^$TMP/plant6.sh:$1:$2:" <<<"$p6" && echo true || echo false; }
eq "control: a two-hop alias (needs a second pass) is a violation"  "true"  "$(_p6v 3 bad)"
eq "control: a function-local alias of a seed call is a violation"  "true"  "$(_p6v 8 bad)"
eq "control: …routed through kb_path_shown it is not"               "true"  "$(_p6v 9 ok)"
eq "control: ONE routed and ONE raw on a line is a violation"       "true"  "$(_p6v 10 bad)"
eq "control: a quoted ARGUMENT before the printer is not the message" "true" "$(_p6v 11 ok)"
eq "control: a local alias is not a member in ANOTHER function"     "false" "$(has ':13:' "$p6")"
eq "control: the kb_board_env_get element NOT holding the path is not a member" "false" "$(has ':17:' "$p6")"
eq "control: the element holding it (continuation joined) is a violation" "true" "$(_p6v 18 bad)"
eq "control: a value that went THROUGH kb_path_shown does not propagate" "false" "$(has ':20:' "$p6")"
eq "control: a message on a producer's own line is judged, not exempted as transport" "true" "$(_p6v 23 bad)"
eq "control: …and so is a printer whose argument captures the producer's printf" "true" "$(_p6v 26 bad)"
eq "control: a printf that is its line's sole printer is still a transport" "true" "$(_p6v 29 transport)"
eq "control: the derivation took more than one pass"                "true"  "$(awk -F'\t' '$1=="passes" { r = ($2 > 2) ? "true" : "false" } END { print r ? r : "false" }' <<<"$p6n")"

echo "== § 7. bash -x and a credential pasted into a token-PATH slot, at each declaring tier =="
# The trace half of § 6's leak. A secret in a path slot is not a token the lib reads, so § 1–4 do
# not see it; under `bash -x` the env's `export KBCARD_TOKEN_FILE=…` line, the tier locals, the
# `[[ -r ]]` and the call of every helper handed the path all used to print it. Each tier is
# driven through every lib-sourcing bin that resolves one, plus the runtime check. RED on the
# previous head: the pasted value is in the trace. CONTROLS on every run: the run WAS traced,
# and the refusal that follows resolution was traced too, carrying `<value not shown…>` — so
# tracing came back after the suspended region rather than staying off.
PB='FAKE-BOARD-TOKEN-NOT-SECRET-001'    # board-env tier (the § 6 env)
PH='FAKE-BOARD-TOKEN-NOT-SECRET-003'    # host-env tier
PA='FAKE-BOARD-TOKEN-NOT-SECRET-004'    # ambient tier
grep -v '^export KBCARD_TOKEN_FILE=' "$KANBAN_HOST_ENV" > "$TMP/host-notok.env"
{ cat "$TMP/host-notok.env"; printf 'export KBCARD_TOKEN_FILE="%s"\n' "$PH"; } > "$TMP/host-pasted.env"
printf 'export KB_BOARD_ID=45\nexport KB_STAGE_BACKLOG=48\n' > "$HOME/.kanban-notok-board.env"
# _x7 <label> <value> <host env> <ambient> <cmd…> — one traced run, from $X7_DIR
_x7() {
    local label="$1" val="$2" henv="$3" amb="$4"; shift 4
    local all
    kb_stub_reset
    ( cd "${X7_DIR:-$TMP}" && KANBAN_HOST_ENV="$henv" KBCARD_TOKEN_FILE="$amb" KB_BCS_LOG="$TMP/bcs.log" \
        bash -x "$@" ) >"$TMP/x7.out" 2>"$TMP/x7.err" || true
    all="$(cat "$TMP/x7.out" "$TMP/x7.err" "$TMP/bcs.log" 2>/dev/null)"
    eq "$label: the pasted value is in no stream (nor the durable log)" "false" "$(has "$val" "$all")"
    eq "$label: control — the run WAS traced"                    "true" "$(grep -q '^+ ' "$TMP/x7.err" && echo true || echo false)"
    eq "$label: control — tracing came back, and traced the masked refusal" "true" \
        "$(grep -qE '^\++ .*<value not shown: not a path>' "$TMP/x7.err" && echo true || echo false)"
}
_x7 "kbcard, board-env tier"   "$PB" "$KANBAN_HOST_ENV"     ""    "$KBC" --board pasted show --task 505
_x7 "kbcard, host-env tier"    "$PH" "$TMP/host-pasted.env" ""    "$KBC" --board notok show --task 505
_x7 "kbcard, ambient tier"     "$PA" "$TMP/host-notok.env"  "$PA" "$KBC" --board notok show --task 505
printf 'pasted:P\n' > "$HOME/.kanban-snapshot-boards"
_x7 "board-snapshot, board-env tier" "$PB" "$KANBAN_HOST_ENV"     ""    "$SNAP"
printf 'notok:N\n' > "$HOME/.kanban-snapshot-boards"
_x7 "board-snapshot, host-env tier"  "$PH" "$TMP/host-pasted.env" ""    "$SNAP"
_x7 "board-snapshot, ambient tier"   "$PA" "$TMP/host-notok.env"  "$PA" "$SNAP"
_x7 "board-stats, board-env tier"    "$PB" "$KANBAN_HOST_ENV"     ""    "$ROOT/bin/board-stats" --board pasted
_x7 "board-stats, host-env tier"     "$PH" "$TMP/host-pasted.env" ""    "$ROOT/bin/board-stats" --board notok
_x7 "board-stats, ambient tier"      "$PA" "$TMP/host-notok.env"  "$PA" "$ROOT/bin/board-stats" --board notok
# board-card-start reads the board from the repo's own git config, on a card branch.
X7_DIR="$TMP/x7repo"
git init -q "$X7_DIR"
( cd "$X7_DIR" && echo a > a && git add a && git -c user.name=t -c user.email=t@t commit -qm a && git checkout -q -b fix/card-505-x )
git -C "$X7_DIR" config kanban.board-id 43
_x7 "board-card-start, board-env tier" "$PB" "$KANBAN_HOST_ENV"     ""    "$ROOT/bin/board-card-start"
eq "board-card-start: control — it reached the token read (the skip is in its durable log)" "true" \
    "$(_contains 'token file not readable: <value not shown: not a path>' "$TMP/bcs.log")"
git -C "$X7_DIR" config kanban.board-id 45
_x7 "board-card-start, host-env tier"  "$PH" "$TMP/host-pasted.env" ""    "$ROOT/bin/board-card-start"
_x7 "board-card-start, ambient tier"   "$PA" "$TMP/host-notok.env"  "$PA" "$ROOT/bin/board-card-start"
X7_DIR=""
# move-board reads the TARGET env --no-token: its path is never checked readable, and is carried
# through the target JSON. The dry run reads the card and stops before any write.
kb_stub_reset
( KBCARD_TOKEN_FILE="" bash -x "$KBC" --board dev move-board --task 505 --to-board pasted --column backlog --dry-run ) \
    >"$TMP/mb.out" 2>"$TMP/mb.err" || true
eq "kbcard move-board, target's pasted path: in no stream" "false" "$(has "$PB" "$(cat "$TMP/mb.out" "$TMP/mb.err")")"
eq "kbcard move-board: control — the run WAS traced"      "true"  "$(grep -q '^+ ' "$TMP/mb.err" && echo true || echo false)"
eq "kbcard move-board: control — the target was resolved and the card read" "true" \
    "$([[ "$(kb_stub_count GET /tasks/505.json)" -ge 1 ]] && echo true || echo false)"
# …nor on any jq argv: a process's argv is world-readable (/proc/<pid>/cmdline). A jq shim on PATH
# records every argv and the target-building call's output. RED when the path went `--arg tok`.
mkdir -p "$TMP/jqshim"
printf '#!/usr/bin/env bash
printf "%%s\n" "$*" >> "%s"
if [[ " $* " == *" --arg env "* ]]; then %s "$@" | tee -a "%s"; else exec %s "$@"; fi
' \
    "$TMP/jq-argv.log" "$(command -v jq)" "$TMP/jq-target.log" "$(command -v jq)" > "$TMP/jqshim/jq"
chmod +x "$TMP/jqshim/jq"
: > "$TMP/jq-argv.log"; : > "$TMP/jq-target.log"; kb_stub_reset
( PATH="$TMP/jqshim:$PATH" KBCARD_TOKEN_FILE="" bash "$KBC" --board dev move-board --task 505 --to-board pasted --column backlog --dry-run ) \
    >/dev/null 2>&1 || true
eq "kbcard move-board: the target's pasted path is on no jq argv"  "false" "$(_contains "$PB" "$TMP/jq-argv.log")"
eq "kbcard move-board: control — the shim saw the target-building call" "true" "$(_contains '--arg env' "$TMP/jq-argv.log")"
eq "kbcard move-board: control — the target still carries that path, through the environment" "true" \
    "$(has "\"token_file\":\"$PB\"" "$(cat "$TMP/jq-target.log")")"
# kb_path_shown's own body runs untraced, so a caller that forgets to suspend leaks the value on
# its CALL line only, not again from the body's `local`. RED without the body's suspension (2+).
h7="$(bash -c 'source "$1"; set -x; kb_path_shown "$2" >/dev/null' _ "$LIB" "$PB" 2>&1)"
eq "kb_path_shown: an unsuspended call traces the value once, on the call line" "1" "$(grep -c "$PB" <<<"$h7" || true)"
eq "kb_path_shown: control — that one line IS the call"       "true" "$(grep -q "^+ kb_path_shown $PB\$" <<<"$h7" && echo true || echo false)"
# The runtime check is a standalone bin; it walks every declaring tier in one run.
( KANBAN_HOST_ENV="$TMP/host-pasted.env" KBCARD_TOKEN_FILE="$PA" bash -x "$ROOT/bin/agent-board-toolkit-runtime-check" ) \
    >"$TMP/rc.out" 2>"$TMP/rc.err" || true
rcall="$(cat "$TMP/rc.out" "$TMP/rc.err")"
for v in "$PB" "$PH" "$PA"; do
    eq "runtime-check: the pasted value [$v] is in no stream" "false" "$(has "$v" "$rcall")"
done
eq "runtime-check: control — the run WAS traced"           "true" "$(grep -q '^+ ' "$TMP/rc.err" && echo true || echo false)"
eq "runtime-check: control — it judged the pasted declarations (and named them as credential-shaped)" "true" \
    "$(has 'SHAPE OF A CREDENTIAL' "$rcall")"

echo "== § 8. bash -v / -xv and a credential pasted into a token-PATH slot (card#11224) =="
# Verbose mode echoes every line the shell READS, so sourcing an env file printed its
# `export KBCARD_TOKEN_FILE="<pasted secret>"` line verbatim, whatever xtrace did. The pair now
# suspends `v` with `x`. RED on the pre-fix pair: the pasted value is in stderr. The ambient tier
# is not driven: an ambient value is never read as shell input, so `-v` cannot echo it. CONTROLS:
# the run WAS verbose (the bin's own source text is in stderr), and it reached the refusal that
# follows resolution.
# _v8 <label> <flags> <value> <host env> <cmd…> — one run under `bash <flags>`, from $X7_DIR
_v8() {
    local label="$1" flags="$2" val="$3" henv="$4"; shift 4
    kb_stub_reset
    ( cd "${X7_DIR:-$TMP}" && KANBAN_HOST_ENV="$henv" KBCARD_TOKEN_FILE="" KB_BCS_LOG="$TMP/bcs.log" \
        bash "$flags" "$@" ) >"$TMP/v8.out" 2>"$TMP/v8.err" || true
    eq "$label: the pasted value is in no stream" "false" "$(has "$val" "$(cat "$TMP/v8.out" "$TMP/v8.err" "$TMP/bcs.log" 2>/dev/null)")"
    eq "$label: control — the run WAS verbose"    "true"  "$(_contains 'source "$KB_LIB"' "$TMP/v8.err")"
    eq "$label: control — it reached the refusal" "true" \
        "$(has '<value not shown: not a path>' "$(cat "$TMP/v8.out" "$TMP/v8.err" "$TMP/bcs.log" 2>/dev/null)")"
}
for fl in -v -xv; do
    _v8 "kbcard $fl, board-env tier"   "$fl" "$PB" "$KANBAN_HOST_ENV"     "$KBC" --board pasted show --task 505
    _v8 "kbcard $fl, host-env tier"    "$fl" "$PH" "$TMP/host-pasted.env" "$KBC" --board notok show --task 505
done
printf 'pasted:P\n' > "$HOME/.kanban-snapshot-boards"
_v8 "board-snapshot -v, board-env tier" -v "$PB" "$KANBAN_HOST_ENV"     "$SNAP"
printf 'notok:N\n' > "$HOME/.kanban-snapshot-boards"
_v8 "board-snapshot -v, host-env tier"  -v "$PH" "$TMP/host-pasted.env" "$SNAP"
X7_DIR="$TMP/x7repo"
git -C "$X7_DIR" config kanban.board-id 45
_v8 "board-card-start -v, host-env tier" -v "$PH" "$TMP/host-pasted.env" "$ROOT/bin/board-card-start"
X7_DIR=""
# In-process: the resolver runs inside a caller's `set -v`, and a file sourced AFTER it is still
# echoed — so verbose came back once the pasted path was handled, rather than staying off.
printf 'echo marker-after-resolve >/dev/null\n' > "$TMP/marker.sh"
# shellcheck disable=SC2016
( KANBAN_HOST_ENV="$TMP/host-pasted.env" KBCARD_TOKEN_FILE="" bash -c '
    source "$1"
    set -v
    kb_resolve_env "$2" >/dev/null
    kb_load_host_env
    source "$3"
' _ "$LIB" "$HOME/.kanban-pasted-board.env" "$TMP/marker.sh" ) >/dev/null 2>"$TMP/v8in.err" || true
eq "in-process -v: kb_resolve_env does not echo the board env's pasted value" "false" "$(_contains "$PB" "$TMP/v8in.err")"
eq "in-process -v: kb_load_host_env does not echo the host env's pasted value" "false" "$(_contains "$PH" "$TMP/v8in.err")"
eq "in-process -v: control — a file sourced after them IS echoed (verbose resumed)" "true" \
    "$(_contains 'echo marker-after-resolve' "$TMP/v8in.err")"

_summary "xtrace-token-selftest"
