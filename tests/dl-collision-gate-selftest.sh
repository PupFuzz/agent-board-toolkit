#!/usr/bin/env bash
# dl-collision-gate-selftest.sh — network-free checks for `bin/dl-collision-gate` and the
# `dl-collision-gate/` composite action over real git fixtures (card#12338; ported from
# agent-webhook-bridge's `DlCollisionGateTest`, card#7157 / card#8527).
#
# WHY A REAL ORIGIN. The second assertion reads the log at the LIVE tip of the target branch, which
# the gate FETCHES — the whole reason it can catch a number the target took after the merge was
# built. So each fixture is an upstream repository the work tree is cloned from, and "the target
# moved under the PR" cases advance it for real. EVERY FIXTURE WORK TREE IS A REAL `--no-ff` MERGE
# of the PR head into the base, because the gate reads its base OUT OF that merge (HEAD^1).
#
# THE ACTION LEG runs the action's SHIPPED run step through `tests/_composite-step-run.sh`, so a
# wrapper that swallowed the script's status, or dropped an input, reds here.
#
# THE FAIL-CLOSED LEG (the `*)` arm) runs the gate beside a stand-in predicate exiting a status the
# gate does not enumerate, and beside one that crashes, and asserts a non-zero, non-refusal status.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$(cd "$HERE/.." && pwd)"
GATE="$ROOT/bin/dl-collision-gate"
STEPRUN="$HERE/_composite-step-run.sh"
_need -x "$GATE"
_need -x "$STEPRUN"
command -v python3 >/dev/null || { echo "selftest: python3 not found" >&2; exit 1; }
_mktmp_scratch

log() {
  printf '# Decision log\n\n> Append-only.\n\n'
  local e
  for e in "$@"; do printf '## DL-%s — an entry\n\nMirrors kanban-board DL-999.\n\n' "$e"; done
}

gx() { local d="$1"; shift; git -C "$d" -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false "$@"; }

n=0
LOGF=CLAUDE_DECISIONS.md   # the log file name the fixtures write
# make <base-log> <head-log> [<moved-target-log>] — upstream `dev` at <base-log>; a clone whose PR
# branch carries <head-log>; the clone left ON the merge of that head into the base; and, when
# given, upstream `dev` moved on to <moved-target-log> AFTER the merge was built. Sets WORK, UP,
# HEAD_SHA, BASE_SHA.
make() {
  n=$((n + 1))
  UP="$TMP/f$n/upstream"; WORK="$TMP/f$n/work"; mkdir -p "$UP"
  gx "$UP" init -q -b dev
  printf '%s' "$1" > "$UP/$LOGF"; gx "$UP" add -A; gx "$UP" commit -q -m base
  BASE_SHA="$(gx "$UP" rev-parse HEAD)"
  git clone -q "$UP" "$WORK"
  gx "$WORK" checkout -q -b pr
  printf '%s' "$2" > "$WORK/$LOGF"; gx "$WORK" add -A; gx "$WORK" commit -q --allow-empty -m head
  HEAD_SHA="$(gx "$WORK" rev-parse HEAD)"
  merge_onto "$BASE_SHA" "$HEAD_SHA"
  if [ $# -ge 3 ]; then
    printf '%s' "$3" > "$UP/$LOGF"; gx "$UP" add -A; gx "$UP" commit -q -m "dev moves on"
  fi
}

# merge_onto <base> <head> [<resolved log>] — leave WORK on <head> merged into <base>, as GitHub's
# refs/pull/N/merge: first parent the base, second the PR head.
merge_onto() {
  gx "$WORK" checkout -q --detach "$1"
  gx "$WORK" merge -q --no-ff --no-commit "$2" >/dev/null 2>&1 || true
  [ $# -ge 3 ] && printf '%s' "$3" > "$WORK/$LOGF"
  gx "$WORK" add -A; gx "$WORK" commit -q -m "Merge pull request"
  local p; p="$(gx "$WORK" rev-list --parents -n 1 HEAD)"
  [ "$p" = "$(gx "$WORK" rev-parse HEAD) $1 $2" ] || { echo "fixture: the work tree is not the merge of $2 into $1" >&2; exit 1; }
}

# gate [<gate path>] — run the gate in WORK; sets RC, OUT (stdout+stderr).
gate() {
  RC=0
  OUT="$(cd "$WORK" && "${1:-$GATE}" --head-sha "$HEAD_SHA" --base-ref dev 2>&1)" || RC=$?
}

echo "== refusals (rc 1) =="
make "$(log 293)" "$(log 293 294)" "$(log 293 294)"
gate
eq "a number the target took after this PR branched is refused" 1 "$RC"
eq "…as already in use on dev" true "$(has 'already in use on dev' "$OUT")"
eq "…naming the number" true "$(has 'DL-294 (added at' "$OUT")"

make "$(log 293)" "$(log 293 294 294)"
gate
eq "a number this PR uses twice is refused" 1 "$RC"
eq "…naming it" true "$(has 'DL-294 is used TWICE' "$OUT")"

make "$(log 293)" "$(log 293)"$'\n## DL-TBD — a draft\n'
gate
eq "a placeholder heading this PR adds is refused" 1 "$RC"
eq "…as carrying no well-formed number" true "$(has 'carries no well-formed number' "$OUT")"

make "$(log 343)" "$(log 343)"$'\n## DL-0344a — suffixed\n'
gate
eq "a suffixed heading this PR adds is refused (H3)" 1 "$RC"

make "$(log 293)" "$(log 293)"$'\n```\nnever closed\n\n## DL-294 — hidden\n'
gate
eq "a log this PR leaves inside an unclosed fence is refused (H1)" 1 "$RC"
eq "…as an unclosed fence" true "$(has 'unclosed code fence' "$OUT")"
eq "…whose remedy, the fence being this PR's, is to close it" true "$(has_line 'Fix: close the fence.' "$OUT")"

# The PR that CLOSES a fence left open on the target branch is refused too — base is the target's.
make "$(log 293)"$'\n```\nnever closed\n' "$(log 293)"$'\n```\nclosed here\n```\n'
gate
eq "a PR closing the TARGET branch's unclosed fence is still refused" 1 "$RC"
eq "…and is told to close it on dev itself, by a path the gate does not block" true \
   "$(has 'Fix: close the fence on dev itself, by a path this gate does not block' "$OUT")"
eq "…not the head-side remedy" false "$(has_line 'Fix: close the fence.' "$OUT")"

# A fence INHERITED from the base: the PR only appends an entry, which lands inside the base's open
# fence. Head is base plus the PR, so head is unclosed too — a head-side ownership read names the
# PR's remedy here, which the PR cannot act on. Only the base/target side can say whose it is.
make "$(log 293)"$'
```
never closed
' "$(log 293)"$'
```
never closed
'"$(log 294 | tail -n +5)"
gate
eq "a PR appending under the base's unclosed fence is refused" 1 "$RC"
eq "…and is told to close it on dev itself (the fence is the target branch's)" true \
   "$(has 'Fix: close the fence on dev itself, by a path this gate does not block' "$OUT")"
eq "…not the head-side remedy" false "$(has_line 'Fix: close the fence.' "$OUT")"

# The target alone gains the open fence after the merge was built: base and head are closed.
make "$(log 293)" "$(log 293 294)" "$(log 293)"$'
```
never closed
'
gate
eq "a fence the live target gained after this PR's merge was built is refused" 1 "$RC"
eq "…with the target-branch remedy" true \
   "$(has 'Fix: close the fence on dev itself, by a path this gate does not block' "$OUT")"

make "$(log 293)" "$(log 293 294)" "$(log 293)"$'\n  ## DL-294 — an indented heading\n'
gate
eq "an INDENTED heading the target took is still a collision (H2)" 1 "$RC"

eq "every refusal tells the author how to allocate" true "$(has 'next-dl <project>' "$OUT")"

echo "== pinned negatives (rc 0) =="
make "$(log 293)" "$(log 293 295)" "$(log 293 294)"
gate
eq "a genuinely new number passes" 0 "$RC"
eq "…naming what it added" true "$(has 'adds 1 DL entries (DL-295)' "$OUT")"

make "$(log 293)" "$(log 293)" "$(log 293 294)"
gate
eq "a PR that mints no DL passes" 0 "$RC"

make "$(log 293 294)" "$(log 293 294 295)"
gate
eq "an entry the target already carried at branch time passes" 0 "$RC"

echo "== the stated bound: two open PRs minting one number both pass, until one merges =="
make "$(log 293)" "$(log 293 294)"
gate
eq "PR A (mints 294) passes while PR B is open" 0 "$RC"
b_work="$TMP/f$n/workb"; git clone -q "$UP" "$b_work"
gx "$b_work" checkout -q -b prb; log 293 294 > "$b_work/CLAUDE_DECISIONS.md"; gx "$b_work" add -A; gx "$b_work" commit -q -m b
b_head="$(gx "$b_work" rev-parse HEAD)"
WORK="$b_work"; HEAD_SHA="$b_head"; merge_onto "$BASE_SHA" "$b_head"
gate
eq "PR B (also mints 294) passes too — neither is on dev yet" 0 "$RC"
# A merges: upstream dev now carries its DL-294 (the squash a merge lands).
log 293 294 > "$UP/$LOGF"; gx "$UP" add -A; gx "$UP" commit -q -m "Merge PR A"
gate
eq "PR B reds once A has merged and B re-runs" 1 "$RC"

echo "== the pairing: the base is HEAD^1, never a lagging base.sha or the fork point =="
make "$(log 293)" "$(log 293 295)"
fork="$BASE_SHA"
log 293 294 > "$UP/$LOGF"; gx "$UP" add -A; gx "$UP" commit -q -m "dev gains 294"
gx "$WORK" fetch -q origin
newbase="$(gx "$WORK" rev-parse origin/dev)"
merge_onto "$newbase" "$HEAD_SHA" "$(log 293 294 295)"
gate
eq "with dev's own DL-294 in the merge, the gate passes (it pairs HEAD with HEAD^1)" 0 "$RC"
gx "$WORK" show "$fork:CLAUDE_DECISIONS.md" > "$TMP/fork.md"
gx "$WORK" show "origin/dev:CLAUDE_DECISIONS.md" > "$TMP/tgt.md"
rc=0; (cd "$WORK" && python3 "$ROOT/bin/_decision-log.py" check --head CLAUDE_DECISIONS.md --base "$TMP/fork.md" --target "$TMP/tgt.md") >/dev/null 2>&1 || rc=$?
eq "CONTROL: the retired pairing (base = the fork point / a lagging base.sha) FALSELY refuses, rc 6" 6 "$rc"

echo "== could not measure (rc 2) =="
make "$(log 293)" "$(log 293 294)"
gx "$WORK" checkout -q pr
gate
eq "a work tree that is not this PR's merge is rc 2, not a guessed base" 2 "$RC"
eq "…saying no base snapshot exists" true "$(has 'no base snapshot' "$OUT")"

make "$(log 293)" "$(log 293 294)"
HEAD_SHA="$BASE_SHA"
gate
eq "a merge of a different head is rc 2" 2 "$RC"

n=$((n + 1)); UP="$TMP/f$n/upstream"; WORK="$TMP/f$n/work"; mkdir -p "$UP"
gx "$UP" init -q -b dev; printf 'x\n' > "$UP/README"; gx "$UP" add -A; gx "$UP" commit -q -m base
BASE_SHA="$(gx "$UP" rev-parse HEAD)"; git clone -q "$UP" "$WORK"; gx "$WORK" checkout -q -b pr
log 1 > "$WORK/$LOGF"; gx "$WORK" add -A; gx "$WORK" commit -q -m head
HEAD_SHA="$(gx "$WORK" rev-parse HEAD)"; merge_onto "$BASE_SHA" "$HEAD_SHA"
gate
eq "a log absent at the base snapshot is rc 2, not an empty log" 2 "$RC"
eq "…naming the read" true "$(has 'at the base snapshot' "$OUT")"

make "$(log 293)" "$(log 293 294)"
RC=0; OUT="$(cd "$WORK" && "$GATE" --head-sha "$HEAD_SHA" --base-ref no-such-branch 2>&1)" || RC=$?
eq "an unfetchable target branch is rc 2" 2 "$RC"

echo "== fail closed: a predicate status the gate does not enumerate is never a pass =="
make "$(log 293)" "$(log 293 294)"
for stub in 'raise SystemExit(3)' 'raise SystemExit(0 if False else 9)' 'raise RuntimeError("boom")'; do
  sb="$TMP/stubbin$n"; rm -rf "$sb"; mkdir -p "$sb"
  cp "$GATE" "$ROOT/bin/pr-base-snapshot" "$sb/"
  printf 'import sys\n%s\n' "$stub" > "$sb/_decision-log.py"
  gate "$sb/dl-collision-gate"
  eq "stand-in predicate '$stub' → rc 2" 2 "$RC"
  eq "…stated as a gate failure, not a verdict" true "$(has 'does not enumerate' "$OUT")"
done
sb="$TMP/stubbin-clean"; mkdir -p "$sb"; cp "$GATE" "$ROOT/bin/pr-base-snapshot" "$sb/"
printf 'import sys\nsys.exit(0)\n' > "$sb/_decision-log.py"
gate "$sb/dl-collision-gate"
eq "CONTROL: the same stand-in exiting 0 passes (the arm above keys on the status)" 0 "$RC"

echo "== usage =="
make "$(log 293)" "$(log 293)"
RC=0; OUT="$(cd "$WORK" && "$GATE" --base-ref dev 2>&1)" || RC=$?
eq "no --head-sha is rc 2" 2 "$RC"
RC=0; OUT="$(cd "$WORK" && "$GATE" --head-sha "" --base-ref dev 2>&1)" || RC=$?
eq "an empty --head-sha is rc 2" 2 "$RC"
RC=0; OUT="$(cd "$WORK" && "$GATE" --head-sha "$HEAD_SHA" --base-ref dev --log nope.md 2>&1)" || RC=$?
eq "an unreadable --log is rc 2" 2 "$RC"

echo "== the composite action's shipped run step =="
make "$(log 293)" "$(log 293 294)" "$(log 293 294)"
RC=0; OUT="$(cd "$WORK" && "$STEPRUN" "$ROOT/dl-collision-gate" --input head-sha="$HEAD_SHA" --input base-ref=dev 2>&1)" || RC=$?
eq "the action refuses a taken number with the script's status (1)" 1 "$RC"
eq "…through the script" true "$(has 'already in use on dev' "$OUT")"
make "$(log 293)" "$(log 293 295)" "$(log 293 294)"
RC=0; OUT="$(cd "$WORK" && "$STEPRUN" "$ROOT/dl-collision-gate" --input head-sha="$HEAD_SHA" --input base-ref=dev 2>&1)" || RC=$?
eq "the action passes a genuinely new number (0)" 0 "$RC"
eq "…having read the default log-path" true "$(has 'adds 1 DL entries (DL-295)' "$OUT")"
LOGF=DECISIONS.md
make "$(log 293)" "$(log 293 295)" "$(log 293 294)"
RC=0; OUT="$(cd "$WORK" && "$STEPRUN" "$ROOT/dl-collision-gate" --input head-sha="$HEAD_SHA" --input base-ref=dev --input log-path=DECISIONS.md 2>&1)" || RC=$?
eq "log-path reaches the script: a log at a non-default path is judged (0)" 0 "$RC"
eq "…and was read" true "$(has 'adds 1 DL entries (DL-295)' "$OUT")"
RC=0; OUT="$(cd "$WORK" && "$STEPRUN" "$ROOT/dl-collision-gate" --input head-sha="$HEAD_SHA" --input base-ref=dev 2>&1)" || RC=$?
eq "CONTROL: the same fixture without log-path reads the default and cannot measure (2)" 2 "$RC"
LOGF=CLAUDE_DECISIONS.md
make "$(log 293)" "$(log 293)"
RC=0; OUT="$(cd "$WORK" && "$STEPRUN" "$ROOT/dl-collision-gate" --input head-sha= --input base-ref=dev 2>&1)" || RC=$?
eq "a blank head-sha input fails closed at rc 2" 2 "$RC"

echo "== the declared trigger list: action.yml and INSTALL.md §6f's workflow name one set =="
# Two copies that cannot be one: action.yml's description is the action's own declaration, and
# §6f's workflow is YAML a consumer copies whole. README points at §6f rather than restating it.
# Each list is read as a SET (order carries no meaning in `types:`); an empty read is a failure,
# so a reflowed or renamed line reds here instead of comparing two empties.
# action_types <action.yml> / install_types <INSTALL.md> — the event types, sorted, comma-joined.
_types_set() { tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d' | sort | paste -sd, -; }
action_types() {
  tr '\n' ' ' <"$1" | tr -s ' ' | sed -n 's/.*`pull_request: \[\([^]]*\)\]`.*/\1/p' | _types_set
}
install_types() {
  awk '/^### 6f\./ {on=1; next} on && /^##/ {exit} on' "$1" \
    | sed -n 's/^[[:space:]]*types:[[:space:]]*\[\([^]]*\)\].*/\1/p' | _types_set
}
A_TYPES="$(action_types "$ROOT/dl-collision-gate/action.yml")"
I_TYPES="$(install_types "$ROOT/docs/INSTALL.md")"
eq "action.yml's trigger list was read" true "$([ -n "$A_TYPES" ] && echo true || echo false)"
eq "INSTALL.md §6f's trigger list was read" true "$([ -n "$I_TYPES" ] && echo true || echo false)"
eq "INSTALL.md §6f's workflow lists the event types action.yml declares" "$A_TYPES" "$I_TYPES"
sed 's/types: \[opened, edited, reopened, synchronize\]/types: [opened, reopened, synchronize]/' \
  "$ROOT/docs/INSTALL.md" >"$TMP/INSTALL-drift.md"
eq "control: the drift fixture really differs from INSTALL.md" false \
   "$(cmp -s "$ROOT/docs/INSTALL.md" "$TMP/INSTALL-drift.md" && echo true || echo false)"
eq "control: the §6f reader sees a list missing \`edited\` as a different set" "edited,opened,reopened,synchronize|opened,reopened,synchronize" \
   "$I_TYPES|$(install_types "$TMP/INSTALL-drift.md")"

_summary "dl-collision-gate-selftest"
