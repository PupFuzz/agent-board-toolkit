#!/usr/bin/env bash
# framework-mirror-check-selftest.sh — drive `tests/framework-mirror-check.sh` over FIXTURES, so
# each verdict is observed firing on the input that earns it and staying silent on the one that
# does not (card#9939).
#
# WHY FIXTURES. The check's real subject — the agent-board-framework's `templates/release/` —
# lives in a PRIVATE repo this CI holds no credential for, so CI cannot run the check itself.
# What it can run is this: a toolkit fixture with two tags, and framework fixtures in both
# layouts the check accepts, each built to be exactly one verdict.
#
# WHAT A GREEN RUN PROVES — the weakest property the assertions support: on these fixtures the
# check names IN-STEP / STALE / DIVERGED / UNMEASURED for the inputs built to be each, exits with
# the rc its header documents, derives its population from names shared with `bin/`, reads the
# git ref it was given rather than the working tree, holds a stamped copy to the tag its stamp
# claims, and says which artifact it read. It proves nothing about the real framework mirror —
# run the check itself for that (VERSIONING.md's release flow).
#
# Every rc-0 assertion is paired with a one-line mutation of the SAME fixture observed red,
# because an IN-STEP answer from a check that compared nothing would pass the rc-0 half alone.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
TOOLKIT="$(cd "$HERE/.." && pwd)"
CHECK="$HERE/framework-mirror-check.sh"
_need -x "$CHECK"
_need -x "$TOOLKIT/bin/release-pr-body"
_need -r "$TOOLKIT/.release-pr.json"
_mktmp_scratch

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# _run <args...> — run the check as a process; sets RC/OUT (stdout+stderr: the verdict rows are
# on stdout and the summary on stderr, and every assertion below reads one or the other).
_run() { RC=0; OUT="$("$CHECK" "$@" 2>&1)" || RC=$?; }

# ── toolkit fixture: v0.1.0 then v0.2.0, each carrying a distinct promote and a stamped
# release-pr-body. The stamped file is the REAL bin with only its stamp rewritten, because the
# check maps a stamp to a tag by calling the toolkit's own `release-pr-body --tag`.
TK="$TMP/tk"
mkdir -p "$TK/bin"
git -C "$TK" init -q
cp "$TOOLKIT/.release-pr.json" "$TK/.release-pr.json"
_stamp() { sed "s/^ABTK_TOOL_VERSION=.*/ABTK_TOOL_VERSION='$1'/" "$TOOLKIT/bin/release-pr-body" > "$TK/bin/release-pr-body"; chmod +x "$TK/bin/release-pr-body"; }
printf 'promote v1\nline two\n' > "$TK/bin/promote-released-cards"
printf 'not mirrored\n' > "$TK/bin/kbcard"
_stamp 0.1.0
git -C "$TK" add -A && GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git -C "$TK" commit -qm one && git -C "$TK" tag v0.1.0
printf 'promote v2\nline two\n' > "$TK/bin/promote-released-cards"
_stamp 0.2.0
git -C "$TK" add -A && GIT_COMMITTER_DATE='2026-02-01T00:00:00Z' git -C "$TK" commit -qm two && git -C "$TK" tag v0.2.0

eq "premise: the stamp maps to its tag through the toolkit's own release-pr-body" "v0.2.0" \
   "$("$TK/bin/release-pr-body" --config "$TK/.release-pr.json" --version 0.2.0 --tag)"

# _mirror <dir> <tag> — a framework-repo-layout fixture whose release dir holds <tag>'s copies,
# plus a file that is NOT a toolkit bin (must not join the population).
_mirror() {
  local d="$1/plugins/coord/templates/release"
  mkdir -p "$d"
  git -C "$TK" show "$2:bin/promote-released-cards" > "$d/promote-released-cards"
  git -C "$TK" show "$2:bin/release-pr-body" > "$d/release-pr-body"
  printf 'framework-only\n' > "$d/release-pr.json.template"
}

echo "== bad invocation exits 2, naming the fault =="
_bad() { local label="$1" want="$2"; shift 2; _run "$@"; eq "$label: rc 2" "2" "$RC"; eq "$label: says '$want'" "true" "$(has "$want" "$OUT")"; }
_bad "no arguments" "usage: framework-mirror-check"
_bad "empty path" "<framework-path> is empty" --toolkit "$TK" ""
_bad "unknown flag" "unknown flag: --nope" --nope "$TMP"
_bad "--ref without a value" "--ref needs a non-empty value" "$TMP" --ref
_bad "extra positional" "unexpected extra argument: b" --toolkit "$TK" "$TMP" b
_bad "missing dir" "no such directory" --toolkit "$TK" "$TMP/absent"
mkdir -p "$TMP/neither"
_bad "neither layout" "not a framework repo or coord plugin root" --toolkit "$TK" "$TMP/neither"

echo "== IN-STEP: both copies equal the newest tag's =="
FW="$TMP/fw-instep"; _mirror "$FW" v0.2.0
_run --toolkit "$TK" "$FW"
eq "in-step: rc 0" "0" "$RC"
eq "in-step: promote row" "true" "$(has "IN-STEP   promote-released-cards — byte-identical to v0.2.0" "$OUT")"
eq "in-step: release-pr-body row" "true" "$(has "IN-STEP   release-pr-body — byte-identical to v0.2.0" "$OUT")"
eq "population: the two shared names, and only those" "true" "$(has_line "MIRRORED: promote-released-cards release-pr-body" "$OUT")"
eq "names the artifact and layout it read" "true" "$(has "READ:     framework repo at $FW" "$OUT")"
eq "names what it cannot see" "true" "$(has "NOT SEEN: any other framework artifact" "$OUT")"
eq "names the newest tag it read" "true" "$(has "newest read: v0.2.0" "$OUT")"
# the mutation witness for the rc-0 above: one changed byte in the SAME fixture reds
printf 'x' >> "$FW/plugins/coord/templates/release/promote-released-cards"
_run --toolkit "$TK" "$FW"
eq "in-step witness: one appended byte → rc 1" "1" "$RC"

echo "== STALE: a copy equal to an OLDER tag =="
FW="$TMP/fw-stale"; _mirror "$FW" v0.2.0
git -C "$TK" show v0.1.0:bin/promote-released-cards > "$FW/plugins/coord/templates/release/promote-released-cards"
_run --toolkit "$TK" "$FW"
eq "stale: rc 1" "1" "$RC"
eq "stale: names the tag it equals and the newest" "true" \
   "$(has "STALE     promote-released-cards — byte-identical to v0.1.0's bin/promote-released-cards; the newest tag carrying it, v0.2.0, differs" "$OUT")"
eq "stale: the other file is still judged on its own" "true" "$(has "IN-STEP   release-pr-body" "$OUT")"
eq "stale: summary names the remedy" "true" "$(has "re-sync FROM a toolkit tag, never a hand edit" "$OUT")"

echo "== DIVERGED: a copy equal to no tag, with the nearest named =="
FW="$TMP/fw-div"; _mirror "$FW" v0.2.0
printf 'promote v2\nFRAMEWORK EDIT\n' > "$FW/plugins/coord/templates/release/promote-released-cards"
_run --toolkit "$TK" "$FW"
eq "diverged: rc 1" "1" "$RC"
eq "diverged: nearest tag and distance" "true" "$(has "nearest is v0.2.0 at 2 differing lines, newest is v0.2.0" "$OUT")"

echo "== a stamp is a CLAIM, held to its tag =="
FW="$TMP/fw-claim"; _mirror "$FW" v0.2.0
printf '# a framework-local line\n' >> "$FW/plugins/coord/templates/release/release-pr-body"
_run --toolkit "$TK" "$FW"
eq "false claim: rc 1" "1" "$RC"
eq "false claim: names the claimed tag" "true" "$(has "DIVERGED  release-pr-body — its stamp claims v0.2.0 but its bytes are not v0.2.0's" "$OUT")"
FW="$TMP/fw-claim-old"; _mirror "$FW" v0.2.0
git -C "$TK" show v0.1.0:bin/release-pr-body > "$FW/plugins/coord/templates/release/release-pr-body"
_run --toolkit "$TK" "$FW"
eq "true claim of an older tag: STALE, not DIVERGED" "true" "$(has "STALE     release-pr-body — byte-identical to v0.1.0" "$OUT")"
FW="$TMP/fw-claim-none"; _mirror "$FW" v0.2.0
sed -i "s/^ABTK_TOOL_VERSION=.*/ABTK_TOOL_VERSION='9.9.9'/" "$FW/plugins/coord/templates/release/release-pr-body"
_run --toolkit "$TK" "$FW"
eq "claim of a tag this checkout lacks: rc 3" "3" "$RC"
eq "claim of a tag this checkout lacks: says so" "true" "$(has "UNMEASURED release-pr-body — stamp claims v9.9.9, which this checkout does not have" "$OUT")"

echo "== the plugin-install layout, and its provenance =="
PL="$TMP/plugin"; mkdir -p "$PL/templates/release" "$PL/.claude-plugin"
cp "$TMP/fw-instep/plugins/coord/templates/release/release-pr-body" "$PL/templates/release/"
git -C "$TK" show v0.2.0:bin/promote-released-cards > "$PL/templates/release/promote-released-cards"
printf '{"name":"coord","version":"7.7.7"}\n' > "$PL/.claude-plugin/plugin.json"
_run --toolkit "$TK" "$PL"
eq "plugin layout: rc 0" "0" "$RC"
eq "plugin layout: named, with its plugin.json version" "true" "$(has "READ:     coord plugin install at $PL — templates/release/ (plugin.json version 7.7.7)" "$OUT")"

echo "== --ref reads the committed tree, not the working tree =="
FR="$TMP/fw-git"; _mirror "$FR" v0.2.0
git -C "$FR" init -q && git -C "$FR" add -A && git -C "$FR" commit -qm mirror
git -C "$TK" show v0.1.0:bin/promote-released-cards > "$FR/plugins/coord/templates/release/promote-released-cards"
_run --toolkit "$TK" "$FR"
eq "working tree (stale edit): rc 1" "1" "$RC"
eq "working tree: provenance flags the uncommitted change" "true" "$(has "WITH UNCOMMITTED CHANGES under plugins/coord/templates/release" "$OUT")"
_run --toolkit "$TK" --ref HEAD "$FR"
eq "--ref HEAD (in-step commit): rc 0" "0" "$RC"
eq "--ref HEAD: provenance names the ref and its commit" "true" "$(has "(git ref HEAD = $(git -C "$FR" rev-parse HEAD))" "$OUT")"
_bad "--ref that does not resolve" "--ref 'nope' does not resolve" --toolkit "$TK" --ref nope "$FR"

echo "== UNMEASURED is never a pass =="
FW="$TMP/fw-nothing"; mkdir -p "$FW/plugins/coord/templates/release"
printf 'x\n' > "$FW/plugins/coord/templates/release/unrelated"
_run --toolkit "$TK" "$FW"
eq "no shared name: rc 3" "3" "$RC"
eq "no shared name: says nothing to compare" "true" "$(has "shares a name with the toolkit's bin/ — nothing to compare" "$OUT")"
NT="$TMP/tk-notags"; mkdir -p "$NT/bin"; git -C "$NT" init -q
_run --toolkit "$NT" "$TMP/fw-instep"
eq "toolkit with no tags: rc 3" "3" "$RC"
eq "toolkit with no tags: says so" "true" "$(has "has no tags" "$OUT")"

_summary "framework-mirror-check-selftest"
