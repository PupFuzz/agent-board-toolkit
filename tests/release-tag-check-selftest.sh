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

# A release whose version file carries a version-shaped line ABOVE the version line, so the
# FIRST regex match is 0.28.0 at both ends and only the SET comparison finds 0.29.0 (card#6488).
# It exists to prove the classifier's own explanation reaches this tool's log.
printf '# was 0.28.0\n0.29.0\n' > "$R/VERSION"
g -C "$R" add -A && g -C "$R" commit -qm "release: v0.29.0 (poisoned version file)"
POISON_SHA="$(g -C "$R" rev-parse HEAD)"

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
# "assert a tag on every push" — a predicate that, measured over `main` at v0.29.0, would have
# refused 4 of its 46 first-parent commits (the root commit and three direct pushes). The bin's
# header carries that denominator and the command that RE-DERIVES it, since the number moves
# with the history.
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

# ── the classifier's own EXPLANATION reaches this tool's log, not just the PR gate ─────────────
# When the first version_regex match is equal at both ends, the classifier re-decides from the
# SET of matched values and says so on a `::warning::` naming the value it chose (card#6488).
# That value is the tag being asserted here, so swallowing the line would leave the reasoning
# only on the PR gate — never on the push that acts on it.
echo "== the classifier's explanation of WHICH version is being shipped is relayed =="
g -C "$R" tag v0.29.0 "$POISON_SHA" && g -C "$R" push -q origin v0.29.0
run "$RELEASE_SHA" "$POISON_SHA" --timeout 0
eq "a re-decided release still passes on its tag" "0"    "$RC"
eq "…asserting the version the classifier CHOSE"  "true" "$(has 'v0.29.0 present at ' "$OUT")"
eq "…and relaying the classifier's own warning"   "true" "$(has '::warning::release-artifacts-check' "$OUT")"
eq "…which names the value it classified on"      "true" "$(has "carries 0.29.0 at $POISON_SHA" "$OUT")"
g -C "$R" push -q --delete origin v0.29.0 && g -C "$R" tag -d v0.29.0 >/dev/null

# ── AN UNREADABLE REMOTE IS A THIRD STATE, NOT AN ABSENT TAG ──────────────────────────────────
# A read has three outcomes and the earlier cut of this tool had two: `git ls-remote`'s status
# was captured and then discarded, and the survivor was tested for emptiness, so "the server
# answered and carries no such tag" and "I could not look" were the same empty string. Measured
# on that binary with the tag GENUINELY PRESENT and the remote unreadable, it emitted
# `v0.28.0 does not exist on <remote> after 4s … The release merged and was NOT tagged — check
# the auto-tag-version workflow run`, rc 1 — a true refusal carrying a false cause, pointing the
# operator at a workflow run that was green, with git's own error text dropped by `2>/dev/null`.
echo "== an unreadable remote is refused as UNREADABLE, never as an untagged release =="
# PRESENCE WITNESS, FIRST AND ON THE REAL REMOTE. The release IS tagged in the world this arm
# runs in, so any "the release merged and was NOT tagged" below is the tool asserting something
# false — not the fixture being empty.
g -C "$R" tag v0.28.0 "$RELEASE_SHA" && g -C "$R" push -q origin v0.28.0
eq "witness: the tag really IS on the real remote" "true" \
   "$(has 'refs/tags/v0.28.0' "$(g -C "$R" ls-remote --tags "$REMOTE" 2>&1)")"
# The unreadable remote is a path git CANNOT read at all. That is the shape every real read
# failure takes here — a bad host, refused credentials, a 403 — one non-zero `ls-remote` with
# its reason on stderr. (The same verdict was reproduced by hand against THIS remote with its
# directory chmod'd 000; the missing path is used in the fixture because it does not depend on
# the test not running as root.)
run "$BEFORE_SHA" "$RELEASE_SHA" --remote "$T/no-such-remote.git" --timeout 2 --interval 1
eq "unreadable remote → rc 1 (still fail-closed)" "1"    "$RC"
eq "…names the READ as the thing that failed"     "true" "$(has 'could NOT READ' "$OUT")"
eq "…and says the tag is UNMEASURED"              "true" "$(has 'UNMEASURED, not absent' "$OUT")"
eq "…quoting git's OWN error text"                "true" "$(has 'does not appear to be a git repository' "$OUT")"
eq "…and reporting how many polls failed"         "true" "$(has 'poll(s) failed' "$OUT")"
eq "…and it does NOT claim the tag is absent"     "false" "$(has 'does not exist on' "$OUT")"
eq "…nor that the release was not tagged"         "false" "$(has 'merged and was NOT tagged' "$OUT")"
eq "…nor send the operator to the tagging workflow" "false" "$(has 'auto-tag-version' "$OUT")"
eq "…while still REFUSING to report it shipped"   "true" "$(has 'REFUSING to report this release as shipped' "$OUT")"
eq "…as a GitHub error annotation"                "true" "$(has '::error::' "$OUT")"
# Each retry says so at the time, rather than only at the bound.
eq "…and each failed poll said so as it happened" "true" "$(has 'NOT evidence that v0.28.0 is absent' "$OUT")"
# CONTROL — the identical invocation against the READABLE remote passes. Without it, "reds on an
# unreadable remote" would also be true of a tool that reds on this fixture for any reason.
run "$BEFORE_SHA" "$RELEASE_SHA" --timeout 2 --interval 1
eq "control: the same push, remote readable → rc 0" "0"  "$RC"
eq "control: …and it confirms the tag"            "true" "$(has "v0.28.0 present at $RELEASE_SHA" "$OUT")"

# A MEASURED ABSENCE STAYS A MEASURED ABSENCE. The tag verdict must not be weakened just
# because the third state now exists: with the tag really gone and the remote answering, the
# untagged-release refusal is unchanged, and it is the arm above's opposite.
g -C "$R" push -q --delete origin v0.28.0 && g -C "$R" tag -d v0.28.0 >/dev/null
run "$BEFORE_SHA" "$RELEASE_SHA" --timeout 2 --interval 1
eq "answered + absent → the untagged verdict"     "1"    "$RC"
eq "…naming the tag as absent"                    "true" "$(has 'v0.28.0 does not exist on' "$OUT")"
eq "…and NOT as unreadable"                       "false" "$(has 'could NOT READ' "$OUT")"

# A MIXED RUN — some polls unreadable, the FINAL one answering — reports the measured absence
# AND the reads it lost. Two claims that both have to be true at once: the verdict is about the
# tag (the remote answered at the end), and the run does not quietly drop the polls that never
# measured anything. The remote appears mid-poll by an atomic rename, so the failures are real.
echo "== a run whose reads partly failed reports the absence AND the failed polls =="
MOVABLE="$T/movable.git"
rm -rf "$MOVABLE" "$T/staged.git"
cp -r "$REMOTE" "$T/staged.git"
( sleep 3; mv "$T/staged.git" "$MOVABLE" ) &
MOVE_PID=$!
run "$BEFORE_SHA" "$RELEASE_SHA" --remote "$MOVABLE" --timeout 8 --interval 1
wait "$MOVE_PID" 2>/dev/null || true
eq "mixed run → the untagged verdict"             "1"    "$RC"
eq "…which names the tag as absent"               "true" "$(has 'v0.28.0 does not exist on' "$OUT")"
eq "…and states the absence is MEASURED"          "true" "$(has 'measured, not inferred' "$OUT")"
eq "…while still counting the polls that failed"  "true" "$(has 'could not read' "$OUT")"
# CONTROL — a run with NO failed poll carries no such caveat, so the clause above is reporting
# the mixed state rather than being printed unconditionally.
run "$BEFORE_SHA" "$RELEASE_SHA" --timeout 2 --interval 1
eq "control: an all-answered run → same verdict"  "1"    "$RC"
eq "control: …and no failed-poll caveat"          "false" "$(has 'measured, not inferred' "$OUT")"

# ── EACH POLL IS BOUNDED, so the tool's own --timeout is what fires ────────────────────────────
# `release-promote-cards.yml` states that this tool's bound fires before its `timeout-minutes`
# backstop, "a timeout-minutes kill reports as `cancelled`, not `failure`". Nothing enforced it:
# one hung `ls-remote` could consume the whole job entitlement and produce exactly the
# `cancelled` outcome that comment says it avoids. The hang here is REAL — an `ext::` remote
# helper that sleeps — so the kill is measured, not stubbed.
if command -v timeout >/dev/null 2>&1; then
  echo "== one hung poll is killed and scored as unreadable, not as an absent tag =="
  HANG_START=$SECONDS
  RC=0
  OUT="$( (cd "$R" && GIT_ALLOW_PROTOCOL=ext "$BIN" --before "$BEFORE_SHA" --after "$RELEASE_SHA" \
            --remote 'ext::sleep 20' --read-timeout 1 --timeout 0) 2>&1 )" || RC=$?
  HANG_ELAPSED=$((SECONDS - HANG_START))
  eq "a hung remote → rc 1"                       "1"    "$RC"
  eq "…named as a KILLED read, with its bound"    "true" "$(has 'KILLED after 1s' "$OUT")"
  eq "…scored as unreadable"                      "true" "$(has 'could NOT READ' "$OUT")"
  eq "…and NOT as an absent tag"                  "false" "$(has 'does not exist on' "$OUT")"
  # THE DISCRIMINATING CONTROL. The fixture sleeps 20s, so an unbounded read could only return
  # after 20; returning in a fraction of that is the bound firing, and nothing else.
  [ "$HANG_ELAPSED" -lt 10 ] && ok "…and the BOUND is what ended it (${HANG_ELAPSED}s < the fixture's 20s hang)" \
                             || bad "…took ${HANG_ELAPSED}s — the read was not bounded"
else
  echo "== \`timeout\` is absent on this host: the bound cannot hold, and the tool must SAY so =="
  run "$BEFORE_SHA" "$RELEASE_SHA" --timeout 0
  eq "…it warns that each poll is UNBOUNDED"      "true" "$(has 'UNBOUNDED' "$OUT")"
fi

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
for f in --timeout --interval --read-timeout; do
  rc=0; err="$("$BIN" "$f" "not-a-number" 2>&1)" || rc=$?
  eq "$f non-numeric → rc 2"            "2"    "$rc"
  eq "…names the flag"                  "true" "$(has "$f requires a non-negative integer" "$err")"
done
# ZERO IS A DIFFERENT QUESTION PER FLAG, so it is driven per flag rather than assumed uniform.
# `--interval 0` passed every non-negative test and then polled with no pause at all: measured
# on the pre-fix binary as an unbounded `ls-remote` flood that never advanced its own clock and
# had to be killed from outside (`--timeout 300 --interval 0`, rc 124 under an external 8s
# timeout, a single line of output). `--read-timeout 0` is `timeout 0`, which means NO bound —
# the flag would silently do the opposite of what it is for.
for f in --interval --read-timeout; do
  rc=0; err="$("$BIN" "$f" 0 2>&1)" || rc=$?
  eq "$f 0 → rc 2"                      "2"    "$rc"
  eq "…names the flag and why"          "true" "$(has "$f requires a positive integer" "$err")"
done
# …and --timeout 0 stays LEGAL: it means "look once", which every arm above relies on.
run "$RELEASE_SHA" "$NONRELEASE_SHA" --timeout 0
eq "--timeout 0 is accepted (look once)" "0"   "$RC"
rc=0; err="$("$BIN" --before x 2>&1)" || rc=$?
eq "a missing --after is refused"       "2"    "$rc"
eq "…by name"                           "true" "$(has -- '--after <ref> is required' "$err")"
rc=0; err="$("$BIN" --nope 2>&1)" || rc=$?
eq "an unknown flag is refused"         "2"    "$rc"
eq "…by name"                           "true" "$(has "unknown arg '--nope'" "$err")"

_summary "release-tag-check-selftest"
