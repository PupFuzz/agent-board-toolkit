#!/usr/bin/env bash
# release-tag-check-selftest.sh — network-free fixture coverage for bin/release-tag-check.
#
# WHY THIS FILE EXISTS (card#6579). `release-tag-check` is the assertion that stops
# `release-promote-cards.yml` reporting a release as shipped when the release is not tagged.
# The defect it closes was SILENT — on the v0.28.0 release, auto-tag's push was refused with a
# 403 and promote reported "2 moved / success" three seconds later — so the one thing this test
# must never be is a check that cannot fail. Every arm below is driven against a real fixture
# repository with a real bare remote; nothing is stubbed.
#
# THE CENTRAL CASE IS THE ONE THAT WAITS. Because both workflows fire on the same `push: main`
# with no `needs:` between them, promote wins the race on EVERY release, not only broken ones.
# So "tag absent at the instant we look" is the NORMAL state and must not fail — the tool has to
# wait and re-ask. `a tag that ARRIVES mid-poll is accepted` is therefore the load-bearing case:
# it is the only one that distinguishes wait-then-verify from a check that happens to pass
# because it looked late. A test suite that only covered present-vs-absent would go green on an
# implementation that never polled at all.
#
# WHAT A GREEN RUN HERE DOES NOT PROVE — stated so this is not over-cited. It proves nothing
# about whether GitHub grants the tag push; that is unfixable from here and untestable locally,
# and the 403's mechanism remains unnamed. It proves this tool's verdicts, not the incident's
# cause.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/release-tag-check"
_need -x "$BIN"
_need -x "$HERE/../bin/release-artifacts-check"   # the classifier this tool delegates to

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
g() { git -c init.defaultBranch=main -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

_mktmp_scratch; T="$TMP"
R="$T/repo"; REMOTE="$T/remote.git"

# ── fixture: a bare remote + a clone whose main carries a release commit then a non-release one
g init --bare -q "$REMOTE"
mkdir -p "$R"; g init -q "$R"
cat > "$R/.release-pr.json" <<'JSON'
{
  "version_file": "VERSION",
  "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["VERSION → {{version}}"]
}
JSON
printf '0.27.0\n' > "$R/VERSION"
g -C "$R" add -A && g -C "$R" commit -qm "v0.27.0 state"
BEFORE_SHA="$(g -C "$R" rev-parse HEAD)"

printf '0.28.0\n' > "$R/VERSION"
g -C "$R" add -A && g -C "$R" commit -qm "release: v0.28.0"
RELEASE_SHA="$(g -C "$R" rev-parse HEAD)"

printf 'note\n' > "$R/NOTES.md"
g -C "$R" add -A && g -C "$R" commit -qm "docs: not a release"
NONRELEASE_SHA="$(g -C "$R" rev-parse HEAD)"

g -C "$R" remote add origin "$REMOTE"
g -C "$R" push -q origin main

# run <before> <after> [args...] — invoke in the fixture root against the fixture remote,
# capturing both streams together. Sets RC and OUT.
run() {
  local b="$1" a="$2"; shift 2
  RC=0
  OUT="$( (cd "$R" && "$BIN" --before "$b" --after "$a" --remote "$REMOTE" "$@") 2>&1 )" || RC=$?
}

# ── CONTROL 4 (negative): a NON-release push asserts nothing, and is unaffected by the tag ────
# Driven with NO tag in the remote at all, deliberately: if classification were skipped or
# inverted, this arm would red here. It is the arm that proves the tool is not simply
# "assert a tag on every push", which measured against this repo's real history false-alarmed
# on all six non-release merges.
echo "== a non-release push asserts nothing =="
run "$RELEASE_SHA" "$NONRELEASE_SHA" --timeout 0 --interval 1
eq "non-release push → rc 0"            "0"    "$RC"
eq "…and says so"                       "true" "$(has 'not a release push' "$OUT")"
eq "…and asserts no tag"                "false" "$(has 'REFUSING' "$OUT")"

# ── CONTROL 2 + 3 (fire-first): the v0.28.0 incident state — release merged, tag ABSENT ───────
# This reproduces 2026-08-15T01:59:46Z: VERSION is 0.28.0 at the merge commit and no v0.28.0
# exists on the remote. Asserted on the EMITTED MESSAGE, not the exit code alone — an rc-only
# assertion passes for a tool that fails for any reason at all.
echo "== a release push with NO tag is refused, loudly (reproduces the v0.28.0 incident) =="
run "$BEFORE_SHA" "$RELEASE_SHA" --timeout 0 --interval 1
eq "untagged release → rc 1"            "1"    "$RC"
eq "…names the tag"                     "true" "$(has 'v0.28.0 does not exist' "$OUT")"
eq "…says the release was NOT tagged"   "true" "$(has 'merged and was NOT tagged' "$OUT")"
eq "…REFUSES to report it shipped"      "true" "$(has 'REFUSING to report this release as shipped' "$OUT")"
eq "…is a GitHub error annotation"      "true" "$(has '::error::' "$OUT")"
eq "…points at the responsible workflow" "true" "$(has 'auto-tag-version' "$OUT")"

# ── CONTROL 1: tag present at the pushed commit ⇒ passes, promote proceeds unchanged ──────────
echo "== a release push WITH its tag passes =="
g -C "$R" tag v0.28.0 "$RELEASE_SHA" && g -C "$R" push -q origin v0.28.0
run "$BEFORE_SHA" "$RELEASE_SHA" --timeout 0 --interval 1
eq "tagged release → rc 0"              "0"    "$RC"
eq "…confirms the tag and the commit"   "true" "$(has "v0.28.0 present at $RELEASE_SHA" "$OUT")"
# The CONTRAST that makes the late-tag arm's "(after Ns)" assertion mean something: a tag that
# was already present must NOT claim to have waited.
eq "…and does not claim to have waited" "false" "$(has '(after ' "$OUT")"

# ── an ANNOTATED tag is dereferenced to its commit, not compared as a tag object ──────────────
# auto-tag-version.yml creates a lightweight tag today; this must not silently depend on that.
echo "== an annotated tag is compared as its commit =="
g -C "$R" push -q --delete origin v0.28.0 && g -C "$R" tag -d v0.28.0 >/dev/null
g -C "$R" tag -a v0.28.0 -m "release" "$RELEASE_SHA" && g -C "$R" push -q origin v0.28.0
run "$BEFORE_SHA" "$RELEASE_SHA" --timeout 0 --interval 1
eq "annotated tag → rc 0"               "0"    "$RC"
g -C "$R" push -q --delete origin v0.28.0 && g -C "$R" tag -d v0.28.0 >/dev/null

# ── THE LOAD-BEARING CASE: a tag that ARRIVES mid-poll is accepted ────────────────────────────
# This is the only arm that separates wait-then-verify from look-once. The tag is absent when
# the tool starts and is pushed while it polls.
echo "== a tag that ARRIVES during the poll is accepted =="
( sleep 2; g -C "$R" tag v0.28.0 "$RELEASE_SHA" >/dev/null 2>&1; g -C "$R" push -q origin v0.28.0 >/dev/null 2>&1 ) &
LATE_PID=$!
run "$BEFORE_SHA" "$RELEASE_SHA" --timeout 30 --interval 1
wait "$LATE_PID" 2>/dev/null || true
eq "late tag → rc 0"                    "0"    "$RC"
eq "…and it reports it WAITED"          "true" "$(has '(after ' "$OUT")"

# CONTROL: the SAME fixture with the tag never arriving must still red — otherwise the case
# above would pass for a tool that ignores the tag entirely.
g -C "$R" push -q --delete origin v0.28.0 && g -C "$R" tag -d v0.28.0 >/dev/null
run "$BEFORE_SHA" "$RELEASE_SHA" --timeout 2 --interval 1
eq "…control: no tag ever ⇒ still rc 1" "1"    "$RC"

# ── a tag present at a DIFFERENT commit is refused immediately, not waited out ────────────────
echo "== a tag at the wrong commit is refused without waiting =="
g -C "$R" tag v0.28.0 "$BEFORE_SHA" && g -C "$R" push -q origin v0.28.0
SECONDS=0
run "$BEFORE_SHA" "$RELEASE_SHA" --timeout 60 --interval 5
ELAPSED=$SECONDS
eq "wrong-commit tag → rc 1"            "1"    "$RC"
eq "…names both commits"                "true" "$(has "at $BEFORE_SHA, but this push is $RELEASE_SHA" "$OUT")"
eq "…diagnoses the version collision"   "true" "$(has 'claimed the same version' "$OUT")"
[ "$ELAPSED" -lt 30 ] && ok "…and does not wait out the timeout (${ELAPSED}s)" \
                      || bad "…waited ${ELAPSED}s for a verdict that cannot change"
g -C "$R" push -q --delete origin v0.28.0 && g -C "$R" tag -d v0.28.0 >/dev/null

# ── an unclassifiable range is rc 2 and is NEVER softened into "not a release" ────────────────
echo "== an unclassifiable range refuses, rather than passing as a non-release =="
run "$BEFORE_SHA" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" --timeout 0
eq "unresolvable --after → rc 2"        "2"    "$RC"
eq "…and does not claim non-release"    "false" "$(has 'not a release push' "$OUT")"

UNREL="$T/unrelated"; g init -q "$UNREL"
printf '9.9.9\n' > "$UNREL/VERSION"; cp "$R/.release-pr.json" "$UNREL/.release-pr.json"
g -C "$UNREL" add -A && g -C "$UNREL" commit -qm "unrelated root"
g -C "$R" remote add unrel "$UNREL" && g -C "$R" fetch -q unrel
UNREL_SHA="$(g -C "$R" rev-parse unrel/main 2>/dev/null || g -C "$R" rev-parse FETCH_HEAD)"
run "$UNREL_SHA" "$RELEASE_SHA" --timeout 0
eq "no common ancestor → rc 2"          "2"    "$RC"
eq "…refuses rather than classifying"   "true" "$(has 'refusing' "$OUT")"
# ASSERTED ON THE PROPAGATION MESSAGE, NOT THE rc. Both the propagation branch and the
# fall-through "unrecognised verdict" arm exit 2, so an rc-only assertion here passes even when
# propagation is removed entirely — measured: deleting the branch left this block green. Only
# this line distinguishes them, and it names the classifier's own rc so the operator is not
# sent to the wrong tool.
eq "…propagates the CLASSIFIER's failure, by name" "true" \
   "$(has 'could not classify' "$OUT")"
eq "…and carries the classifier's rc"   "true" "$(has 'release-artifacts-check rc 2' "$OUT")"
eq "…and relays the classifier's own diagnosis" "true" "$(has 'common ancestor' "$OUT")"

# ── the classifier delegation is REAL, not re-implemented here ────────────────────────────────
echo "== the release classification is delegated, not re-derived =="
eq "release-tag-check calls the classifier" "true" \
   "$(has 'release-artifacts-check' "$(cat "$BIN")")"
eq "…and does not carry its own version regex" "false" \
   "$(has 'version_regex' "$(cat "$BIN")")"

# ── --help lands on STDOUT and prints the whole header ────────────────────────────────────────
echo "== --help =="
HELP="$("$BIN" --help 2>/dev/null)"
eq "--help goes to stdout"              "true" "$(has 'release-tag-check' "$HELP")"
eq "…documents the wait"                "true" "$(has '--timeout' "$HELP")"
eq "…states the bound is a cost decision" "true" "$(has 'COST DECISION' "$HELP")"

# ── value-taking flags ────────────────────────────────────────────────────────────────────────
echo "== value-taking flags reject an EMPTY value =="
# DERIVED from the bin, not typed here (card#6645). `--timeout`/`--interval` are guarded by
# require_uint rather than require_value, so they are invisible to that predicate by
# construction — they are driven separately below rather than left unasserted.
VALUE_FLAGS=(--before --after --config --remote)
expect_value_flags "$BIN" "${VALUE_FLAGS[@]}"
for f in "${VALUE_FLAGS[@]}"; do
  rc=0; err="$("$BIN" "$f" "" 2>&1)" || rc=$?
  eq "$f \"\" → rc 2"                   "2"    "$rc"
  eq "…names the flag"                  "true" "$(has "$f requires a non-empty value" "$err")"
done
for f in --timeout --interval; do
  rc=0; err="$("$BIN" "$f" "not-a-number" 2>&1)" || rc=$?
  eq "$f non-numeric → rc 2"            "2"    "$rc"
  eq "…names the flag"                  "true" "$(has "$f requires a non-negative integer" "$err")"
done
rc=0; err="$("$BIN" --before x 2>&1)" || rc=$?
eq "a missing --after is refused"       "2"    "$rc"
eq "…by name"                           "true" "$(has -- '--after <ref> is required' "$err")"
rc=0; err="$("$BIN" --nope 2>&1)" || rc=$?
eq "an unknown flag is refused"         "2"    "$rc"
eq "…by name"                           "true" "$(has "unknown arg '--nope'" "$err")"

_summary "release-tag-check-selftest"
