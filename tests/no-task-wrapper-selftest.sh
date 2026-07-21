#!/usr/bin/env bash
# no-task-wrapper-selftest.sh — a STATIC regression guard: no script in bin/ may send a
# v3 task-write request body wrapped in a `{"task":{...}}` envelope. Kanban dropped that
# wrapper in DL-219; #4772 removed every wrapped send, but two of them hid for two review
# rounds because they were hand-built ESCAPED-QUOTE string literals (`"{\"task\":{...}}"`)
# that a plain `"task":` grep never saw.
#
# Why a static test and not a code helper: `bin/promote-released-cards` is standalone-vendored
# and CANNOT source the shared lib, so a runtime helper could never cover it — and post-DL-219
# there is no shared wrapper primitive left to centralize on. A grep over the source catches a
# re-introduced wrapper in ANY bin/ file regardless of how it is built.
#
# The matcher catches all three re-introduction shapes and none of the legitimate `task`-prefixed
# tokens (task_id / to_task_id / from_task_id / task_links / .task-list / `_action` bodies):
#   1. unescaped JSON literal   {"task":{...}}      -> "task"\s*:
#   2. escaped string literal    "{\"task\":{...}}" -> \"task\"\s*:
#   3. jq object construction    {task: {...}} / {task: $t}
#                                                   -> (^|[ ({,])task\s*:
# The jq arm matches the wrapper KEY alone (not requiring a following `{`) on purpose: the
# argjson form `{task: $var}` is a real wrapper the brace-requiring form would miss. That
# breadth is why the comment filter is load-bearing rather than decorative — the current tree's
# one legitimate mention (`# ... {task: ...}` in bin/kbcard) is matched raw and MUST be excluded;
# the zero-offender assertion below proves the filter fires on real input (canon #9).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin"
_need -r "$BIN/kbcard"

# The three-shape wrapper matcher. Each alternative is independent and self-proving below:
# an escaped literal `\"task\"` has a backslash between `k` and the second quote, so arm 1
# (bare "task") cannot see it and arm 2 is what catches it — and vice-versa.
WRAP_RE='("task"[[:space:]]*:)|(\\"task\\"[[:space:]]*:)|((^|[ ({,])task[[:space:]]*:)'

# scan_wrappers <dir> — emit `file:lineno:content` for every NON-COMMENT line under <dir>
# (regular files, one level deep) whose content matches WRAP_RE. Lines whose first
# non-whitespace char is `#` are excluded. No match => no output, rc 0.
scan_wrappers() {
    local dir="$1" hit content trimmed
    local files=()
    while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -maxdepth 1 -type f | sort)
    [[ ${#files[@]} -gt 0 ]] || return 0
    grep -HnE "$WRAP_RE" "${files[@]}" 2>/dev/null | while IFS= read -r hit; do
        content="${hit#*:}"; content="${content#*:}"          # strip `path:` then `lineno:`
        trimmed="${content#"${content%%[![:space:]]*}"}"      # left-trim whitespace
        [[ "$trimmed" == \#* ]] && continue                   # drop comment lines
        printf '%s\n' "$hit"
    done || true
    return 0
}

n_offenders() {
    [[ -z "$1" ]] && { printf '0'; return 0; }
    printf '%s\n' "$1" | wc -l | tr -d ' '
}

echo "== the guard: bin/ must contain ZERO task-wrapper sends (current tree) =="
tree_hits="$(scan_wrappers "$BIN")"
eq "current bin/ has zero task-wrapper offenders" "0" "$(n_offenders "$tree_hits")"
if [[ -n "$tree_hits" ]]; then
    printf '  offending lines:\n%s\n' "$tree_hits" >&2
fi

echo "== positive control: the matcher FLAGS every re-introduction shape =="
_mktmp_scratch
pos="$TMP/pos"; mkdir -p "$pos"
# arm 1 — unescaped JSON literal
printf '%s\n' 'kb_api PATCH "/tasks/$x.json" '"'"'{"task":{"workflow_stage_id":5}}'"'"'' > "$pos/wrapped-unescaped"
# arm 2 — hand-built escaped string literal (the shape that hid through two #4772 rounds)
printf '%s\n' 'body="{\"task\":{\"workflow_stage_id\":5}}"' > "$pos/wrapped-escaped"
# arm 3 — jq argjson wrapper with NO brace after the key (the form a brace-requiring regex misses)
printf '%s\n' 'body="$(jq -n --argjson t "$inner" '"'"'{task: $t}'"'"')"' > "$pos/wrapped-jq-argjson"

pos_hits="$(scan_wrappers "$pos")"
eq "positive control flags all three wrapper files" "3" "$(n_offenders "$pos_hits")"
case "$pos_hits" in *"wrapped-unescaped:"*) ok "unescaped literal flagged";; *) bad "unescaped literal NOT flagged";; esac
case "$pos_hits" in *"wrapped-escaped:"*)   ok "escaped literal flagged";;   *) bad "escaped literal NOT flagged (the #4772 blind spot)";; esac
case "$pos_hits" in *"wrapped-jq-argjson:"*) ok "jq argjson wrapper flagged";; *) bad "jq argjson wrapper NOT flagged";; esac

# Prove the escaped arm is doing independent work: a bare `"task":` matcher cannot see the
# escaped shape, so arm 2 is the ONLY thing catching wrapped-escaped.
if grep -qE '"task"[[:space:]]*:' "$pos/wrapped-escaped"; then
    bad "escaped shape unexpectedly matched a bare \"task\": grep — arm 2 not proven independent"
else
    ok "escaped shape is invisible to a bare \"task\": grep (arm 2 is load-bearing)"
fi

echo "== no false positives: benign task-prefixed tokens + a #-comment mention =="
ben="$TMP/ben"; mkdir -p "$ben"
{
    printf '%s\n' 'payload='"'"'{"task_id":5,"to_task_id":6,"from_task_id":7}'"'"''
    printf '%s\n' 'jq -n --argjson id "$id" '"'"'{task_id: $id, task_links: []}'"'"''
    printf '%s\n' 'sel=".task-list"'
    printf '%s\n' 'body="$(build_action_body archive)"   # _action bodies, not a wrapper'
    printf '%s\n' '    # historical: the old {"task": {...}} body wrapper was dropped in DL-219'
} > "$ben/benign"
ben_hits="$(scan_wrappers "$ben")"
eq "benign tokens + comment mention are NOT flagged" "0" "$(n_offenders "$ben_hits")"
if [[ -n "$ben_hits" ]]; then
    printf '  false positives:\n%s\n' "$ben_hits" >&2
fi

_summary "no-task-wrapper-selftest"
