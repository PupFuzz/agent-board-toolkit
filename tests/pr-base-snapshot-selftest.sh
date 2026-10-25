#!/usr/bin/env bash
# pr-base-snapshot-selftest.sh — network-free checks for `bin/pr-base-snapshot` against real git
# fixtures (card#12338; ported from agent-webhook-bridge's `PrBaseSnapshotTest`, card#8527).
#
# Each refusal is a shape the tool must not GUESS a base for, and the positive case pins that it
# READS the merge's recorded first parent rather than re-deriving the fork point — the fixture moves
# the base branch after the fork, so the two answers differ and a merge-base rewrite would red here.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
TOOL="$HERE/../bin/pr-base-snapshot"
_need -x "$TOOL"
_mktmp_scratch

g() { git -C "$REPO" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false "$@"; }
commit() { printf "%s\n" "$1" > "$REPO/$1.txt"; g add "$1.txt"; g commit -q -m "$1"; g rev-parse HEAD; }

# snap <args...> — run the tool in $REPO; sets RC, OUT, ERR.
snap() {
  RC=0
  (cd "$REPO" && "$TOOL" "$@") >"$TMP/out" 2>"$TMP/err" || RC=$?
  OUT="$(cat "$TMP/out")"; ERR="$(cat "$TMP/err")"
}

REPO="$TMP/repo"; mkdir -p "$REPO"; g init -q -b dev
fork="$(commit fork)"
g checkout -q -b pr; head="$(commit pr-change)"
g checkout -q dev; moved="$(commit dev-moved-on)"
g checkout -q --detach "$moved"
g merge -q --no-ff --no-edit "$head" >/dev/null 2>&1 || { echo "fixture: merge failed" >&2; exit 1; }
merge="$(g rev-parse HEAD)"

echo "== the merge's recorded first parent, and nothing else =="
snap --head "$head"
eq "rc 0 on this PR's merge" 0 "$RC"
eq "stdout is exactly the first parent" "$moved" "$OUT"
eq "stderr is empty" "" "$ERR"
eq "premise: the fork point differs from the first parent (a merge-base answer would red above)" \
   true "$([ "$(g merge-base "$fork" HEAD)" = "$fork" ] && [ "$fork" != "$moved" ] && echo true || echo false)"

echo "== refusals: no sha printed, a distinct status per shape =="
snap --head "0000000000000000000000000000000000000000"
eq "a merge of some OTHER head is rc 5" 5 "$RC"
eq "…printing no sha" "" "$OUT"
eq "…naming both shas" true "$(has "$head" "$ERR")"
g checkout -q pr
snap --head "$head"
eq "a non-merge HEAD is rc 4" 4 "$RC"
eq "…printing no sha" "" "$OUT"
g checkout -q -b side "$fork"; side="$(commit side)"
g checkout -q --detach "$moved"
g merge -q --no-ff --no-edit "$head" "$side" >/dev/null 2>&1 || true
eq "premise: the octopus fixture has three parents" 4 "$(g rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')"
snap --head "$head"
eq "an octopus merge is rc 4" 4 "$RC"
g checkout -q --detach "$merge"
snap
eq "no --head is rc 2" 2 "$RC"
snap --head ""
eq "an empty --head is rc 2" 2 "$RC"
snap --bogus
eq "an unknown argument is rc 2" 2 "$RC"
REPO="$TMP/empty"; mkdir -p "$REPO"; g init -q -b dev
snap --head "$head"
eq "a repository with no commits is rc 3" 3 "$RC"
eq "…printing no sha" "" "$OUT"

_summary "pr-base-snapshot-selftest"
