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
_need -x "$HERE/../bin/release-pr-body"          # the tag_format reader this tool delegates to

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
# the tool starts and appears while it polls.
#
# ⛔ THE ARRIVAL IS SEQUENCED ON THE TOOL'S OWN READS, NEVER ON A WALL CLOCK (card#8485). This
# arm used to push the tag from a `( sleep 2; … ) &` forked immediately before the run. That
# timer starts at the FORK, but the event it must beat is the tool's FIRST POLL — and the tool
# does not poll for an UNBOUNDED interval after it starts: `git rev-parse`, then the
# `release-artifacts-check` and `release-pr-body` delegations, each spawning git of its own.
# The elapsed clocks this file carried at the time — both since re-based off the tool's own
# reads by card#8533 — put that startup at 2–9s across the 21 red runs of a 30-run baseline at
# load ~26, against a 2s timer: the tag was already present when poll 1 looked, `POLLS` was 1,
# and the tool printed its (correct) no-wait form — reddening the `WAITED` cell on 19 of 30 runs
# with the tool right every time. A fixture whose precondition is "the tool is faster than N
# seconds" measures the box, not the tool.
# `_counting_remote` below counts REAL reads instead: the ref is created just before a chosen
# read is served, so it is still a real arrival discovered by a real `ls-remote`, but "the tag
# was already there when the tool first looked" is now unrepresentable rather than merely
# unlikely.

# _counting_remote <helper> <count-file> <refuse-first> <refuse-after> <arrive-before-read|never> [remote] [hang-seconds]
# — write an `ext::` remote helper that serves a bare remote ($REMOTE unless a sixth argument
# names another) and TALLIES every read it is asked for, so an arm can sequence its fixture
# events on the tool's own polls instead of on a wall clock. ONE owner for every `ext::` remote
# in this file — the late-tag arm, the mixed-poll arm, the unreadable-follow-up arm, the
# wrong-commit arm, the hung-read arm, and each one's control — because they are one behaviour
# with settings, and a second copy of "count the reads, then serve" is how two of those arms
# drifted apart in the first place (card#8485):
#   <refuse-first>        reads 1..N are refused; 0 refuses none.
#   <refuse-after>        reads N+1.. are refused; 0 refuses none. A refusal is a REAL non-zero
#                         read, git's own stderr reaching the tool — and the cheapest path this
#                         helper has (no upload-pack, no objects), so a refused poll is over in
#                         milliseconds and cannot eat the tool's own --timeout.
#   <arrive-before-read>  v0.28.0 is created on that remote immediately before that read is
#                         served — a REAL ref found by a real `ls-remote` — or `never`.
#   <hang-seconds>        serve nothing and sleep instead, so the read never answers; 0 serves
#                         normally. The count and the stamp below are still written first, so a
#                         hung read is a COUNTED, TIMED read and not an invisible one.
# IT ALSO STAMPS WHEN READ 1 BEGAN, in epoch seconds, at `<count-file>.read1` (card#8533). An
# arm that must bound a read's own DURATION cannot start its clock in the test: everything the
# tool does before its first poll — `git rev-parse`, the `release-artifacts-check` and
# `release-pr-body` delegations, at the loaded-host figure the header above measures — sits
# inside that interval, and none of it is the thing under test. Reading the stamp puts that
# startup OUTSIDE the measured window, so the bound is the read's and the box's load is not.
_counting_remote() {
  local helper="$1" count="$2" refuse_first="$3" refuse_after="$4" arrive="$5" remote="${6:-$REMOTE}" hang="${7:-0}"
  rm -f "$count" "$count.read1"
  cat > "$helper" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$count" 2>/dev/null || echo 0) + 1 )); printf '%s' "\$n" > "$count"
if [ "\$n" -eq 1 ]; then date +%s > "$count.read1"; fi
if [ "\$n" -le "$refuse_first" ] || { [ "$refuse_after" -gt 0 ] && [ "\$n" -gt "$refuse_after" ]; }; then
  echo "fixture: read \$n refused" >&2; exit 1
fi
if [ "$arrive" != never ] && [ "\$n" -ge "$arrive" ]; then
  git --git-dir="$remote" update-ref refs/tags/v0.28.0 "$RELEASE_SHA"
fi
if [ "$hang" -gt 0 ]; then exec sleep "$hang"; fi
exec git upload-pack "$remote"
EOF
  chmod +x "$helper"
}

echo "== a tag that ARRIVES during the poll is accepted =="
LATE_READS="$T/late-remote.reads"
_counting_remote "$T/late-remote" "$LATE_READS" 0 0 2
RC=0
OUT="$( (cd "$R" && GIT_ALLOW_PROTOCOL=ext "$BIN" --before "$BEFORE_SHA" --after "$RELEASE_SHA" \
          --remote "ext::$T/late-remote" --timeout 30 --interval 1) 2>&1 )" || RC=$?
eq "late tag → rc 0"                    "0"    "$RC"
eq "…and it reports it WAITED"          "true" "$(has '(after ' "$OUT")"
# THE FIXTURE'S OWN PRECONDITION, ASSERTED RATHER THAN ASSUMED — which is the entire defect the
# `sleep 2` carried. This cell is about a tag that was ABSENT on the first look; had the tool
# read only once it could not have been, and the two cells above would then be reporting the
# fixture's failure to set up as the tool's failure to wait.
eq "…having actually read the remote more than once" "true" \
   "$([ "$(cat "$LATE_READS" 2>/dev/null || echo 0)" -ge 2 ] && echo true || echo false)"

# CONTROL: the SAME fixture with the tag never arriving must still red — otherwise the case
# above would pass for a tool that ignores the tag entirely.
g --git-dir="$REMOTE" update-ref -d refs/tags/v0.28.0
_counting_remote "$T/never-remote" "$T/never-remote.reads" 0 0 never
RC=0
OUT="$( (cd "$R" && GIT_ALLOW_PROTOCOL=ext "$BIN" --before "$BEFORE_SHA" --after "$RELEASE_SHA" \
          --remote "ext::$T/never-remote" --timeout 2 --interval 1) 2>&1 )" || RC=$?
eq "…control: no tag ever ⇒ still rc 1" "1"    "$RC"

# ── a tag present at a DIFFERENT commit is refused immediately, not waited out ────────────────
# "DOES NOT WAIT" IS COUNTED IN READS, NOT IN SECONDS (card#8533). This arm used to bound the
# test's own `SECONDS` at 30 against a `--timeout 60 --interval 5` run. That clock starts before
# the tool does, so the tool's startup — `git rev-parse` plus the two delegations, at the figure
# this file's header measures (card#8485) — was inside the bound, and a slower box reds the cell
# for a defect the tool does not have. It is also the weaker predicate: waiting out that timeout
# means roughly `--timeout / --interval` polls rather than one, so the property is "it looked
# once and refused", which the read counter states exactly and a wall clock only approximates.
# ⚑ THE EXACT POLL COUNT IS NOT A CONSTANT AND IS NOT ASSERTED ANYWHERE. `bin/release-tag-check`
# truncates its own `WAITED` to whole seconds and breaks at `WAITED -ge TIMEOUT`, so whether the
# last poll happens depends on where in the second its `START=$SECONDS` landed: 13 or 14 on this
# arm, host-decided. What the cell below asserts is `1` — any count above it is the regression,
# whatever the ceiling would have been.
echo "== a tag at the wrong commit is refused without waiting =="
g -C "$R" tag v0.28.0 "$BEFORE_SHA" && g -C "$R" push -q origin v0.28.0
WRONG_READS="$T/wrong-commit-remote.reads"
_counting_remote "$T/wrong-commit-remote" "$WRONG_READS" 0 0 never
RC=0
OUT="$( (cd "$R" && GIT_ALLOW_PROTOCOL=ext "$BIN" --before "$BEFORE_SHA" --after "$RELEASE_SHA" \
          --remote "ext::$T/wrong-commit-remote" --timeout 60 --interval 5) 2>&1 )" || RC=$?
eq "wrong-commit tag → rc 1"            "1"    "$RC"
eq "…names both commits"                "true" "$(has "at $BEFORE_SHA, but this push is $RELEASE_SHA" "$OUT")"
eq "…diagnoses the version collision"   "true" "$(has 'claimed the same version' "$OUT")"
eq "…and refuses on the FIRST look, without polling again" "1" \
   "$(cat "$WRONG_READS" 2>/dev/null || echo 0)"
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

# ── THE TAG NAME COMES FROM `tag_format`, NOT A HARDCODED `v` PREFIX (card#7203) ──────────────
# `.release-pr.json`'s `tag_format` maps a version to its git tag name, and `release-pr-body`
# has read it since card#4761. This tool hardcoded `TAG="v${VERSION}"` — right for the default
# scheme and wrong for every other one, which is worse here than a wrong string: it polled for a
# tag that CANNOT EXIST, waited out the whole bound, and refused the release. A consumer on a
# .NET or date scheme (the schemes docs/INSTALL.md §4 documents the key FOR) got a hard refusal
# on every single release — the exact outcome the wait exists to prevent.
#
# ONE FIXTURE, FOUR SCHEMES, selected by --config: the configs are all COMMITTED at both ends of
# the range because the classifier reads its copy out of git, while the tag name is resolved
# from the checkout. Watched RED on the pre-card#7203 binary — every arm below except the two
# controls, which is what makes the controls controls.
echo "== the tag asserted is the one tag_format names, not v<version> =="
R2="$T/tagfmt"; REMOTE2="$T/tagfmt-remote.git"
g init --bare -q "$REMOTE2"; mkdir -p "$R2"; g init -q "$R2"
_tf_cfg() { # _tf_cfg <path> [tag_format]
  if [ $# -eq 2 ]; then
    printf '{\n  "version_file": "VERSION",\n  "version_regex": "[0-9]+\\\\.[0-9]+\\\\.[0-9]+",\n  "tag_format": "%s",\n  "artifacts": ["VERSION → {{version}}"]\n}\n' "$2" > "$R2/$1"
  else
    printf '{\n  "version_file": "VERSION",\n  "version_regex": "[0-9]+\\\\.[0-9]+\\\\.[0-9]+",\n  "artifacts": ["VERSION → {{version}}"]\n}\n' > "$R2/$1"
  fi
}
_tf_cfg .release-pr.json                       # no tag_format key at all — the historical default
_tf_cfg tf-v.json        'v{{version}}'        # the default, stated explicitly
_tf_cfg tf-release.json  'release-{{version}}' # a prefixed non-v scheme
_tf_cfg tf-bare.json     '{{version}}'         # the version IS the tag (date schemes)
# A NEWLINE IN THE VALUE. `\n` here is two literal characters in the JSON source, which is a real
# newline once jq reads it — the shape a config file can actually carry. Written with the other
# fixtures because the classifier reads every config from the COMMIT, not the working tree.
_tf_cfg tf-inject.json   'v{{version}}\n::error::INJECTED'
printf '0.27.0\n' > "$R2/VERSION"
g -C "$R2" add -A && g -C "$R2" commit -qm "v0.27.0 state"
TF_BEFORE="$(g -C "$R2" rev-parse HEAD)"
printf '0.28.0\n' > "$R2/VERSION"
g -C "$R2" add -A && g -C "$R2" commit -qm "release: v0.28.0"
TF_RELEASE="$(g -C "$R2" rev-parse HEAD)"
g -C "$R2" remote add origin "$REMOTE2" && g -C "$R2" push -q origin main

tf_run() { # tf_run <config> [args...]
  local c="$1"; shift
  RC=0
  OUT="$( (cd "$R2" && "$BIN" --before "$TF_BEFORE" --after "$TF_RELEASE" --remote "$REMOTE2" \
            --config "$c" --timeout 0 "$@") 2>&1 )" || RC=$?
}
tf_tag() { g -C "$R2" tag "$1" "$TF_RELEASE" && g -C "$R2" push -q origin "$1"; }
tf_untag() { g -C "$R2" push -q --delete origin "$1" && g -C "$R2" tag -d "$1" >/dev/null; }

# CONTROL A — no key: the historical `v<version>` behaviour, byte-for-byte. If this arm ever
# moves, the change was not additive.
tf_tag v0.28.0
tf_run .release-pr.json
eq "control: no tag_format ⇒ still v0.28.0"       "0"    "$RC"
eq "…named as such"                               "true" "$(has "v0.28.0 present at $TF_RELEASE" "$OUT")"
# CONTROL B — the key set to its OWN default. A fixture that sets a key to its default value
# cannot discriminate "the key was read" from "the default fired", so this is a control and NOT
# coverage: the arms below are what prove the key is read.
tf_run tf-v.json
eq "control: tag_format v{{version}} ⇒ v0.28.0"   "0"    "$RC"

# THE DISCRIMINATING NEGATIVE, RUN FIRST. `v0.28.0` — the tag a hardcoded prefix would find —
# is on the remote and `release-0.28.0` is not. A tool reading tag_format must REFUSE here; the
# pre-fix one passed, which is exactly the false "shipped" this card is about.
tf_run tf-release.json
eq "a v-tag does NOT satisfy a release- scheme"   "1"    "$RC"
eq "…and the refusal names the tag_format tag"    "true" "$(has 'release-0.28.0 does not exist' "$OUT")"
eq "…not the v-prefixed one"                      "false" "$(has 'v0.28.0 does not exist' "$OUT")"

# …AND THE REFUSAL NAMES ITS OWN CAUSE, WHICH THIS ARM IS THE SECOND WORLD OF. `tag_format` made
# "no ${TAG} at this commit" ambiguous: the release may be untagged, or tagged under a name this
# check was not waiting for. The fixture is the second one — the tagging workflow ran and pushed
# `v0.28.0` — so the old wording ("The release merged and was NOT tagged — check the
# auto-tag-version workflow run") sent the operator to a run that succeeded. Watched RED on the
# pre-fix binary, every line of this block.
eq "…the refusal names the tag that IS at the commit" "true" "$(has 'carrying: v0.28.0' "$OUT")"
eq "…and says this commit IS tagged"              "true" "$(has 'IS tagged on' "$OUT")"
eq "…naming tag_format as the thing to check"     "true" "$(has "does NOT change what your tagging workflow creates" "$OUT")"
eq "…and does NOT blame the tagging workflow run" "false" "$(has 'auto-tag-version' "$OUT")"
eq "…nor claim the release was never tagged"      "false" "$(has 'merged and was NOT tagged' "$OUT")"
tf_untag v0.28.0

# THE CONTROL THAT MAKES THE BLOCK ABOVE A MEASUREMENT: the same push with NO tag of any name at
# the commit keeps the untagged-release verdict — and now says the alternative was measured and
# excluded, rather than assuming it. Without this arm, "does not blame the tagging workflow"
# would also be true of a tool that never names it at all.
tf_run tf-release.json
eq "control: no tag at the commit → untagged verdict" "1"    "$RC"
eq "…stating the exclusion was MEASURED"          "true" "$(has 'No tag of ANY name points at' "$OUT")"
eq "…and it DOES name the tagging workflow here"  "true" "$(has 'auto-tag-version' "$OUT")"

# …and with the tag the scheme actually produces, the same push passes.
tf_tag release-0.28.0
tf_run tf-release.json
eq "a release-<version> tag satisfies it"         "0"    "$RC"
eq "…naming the tag it waited for"                "true" "$(has "release-0.28.0 present at $TF_RELEASE" "$OUT")"
tf_untag release-0.28.0

# The unprefixed scheme: the version string IS the tag.
tf_tag 0.28.0
tf_run tf-bare.json
eq "an unprefixed {{version}} scheme passes"      "0"    "$RC"
eq "…naming the bare version as the tag"          "true" "$(has "0.28.0 present at $TF_RELEASE" "$OUT")"
eq "…and never invents a v prefix"                "false" "$(has "v0.28.0" "$OUT")"
tf_untag 0.28.0

# ── THE COMBINATION NOTHING DROVE: the key ABSENT, and another tag AT the commit ──────────────
# Every arm above reaches the tag-elsewhere cause with a fixture that HAS `tag_format`, so the
# message was free to say the config MAPS this version to that name — while the unset key is
# the NORMAL case (`docs/INSTALL.md` §6d: "a repo that leaves the key unset gets `v<version>`"),
# because the default is applied by the sibling that reads the file, not written in the file.
# The operator was sent to look up a key they will not find. This is the missing cell.
echo "== the tag-elsewhere cause holds with NO tag_format key in the config =="
tf_tag release-0.28.0
tf_run .release-pr.json
eq "no key + another tag at the commit → rc 1"    "1"    "$RC"
# Anchored on the message's own prefix, not on the bare tag: `v0.28.0 does not exist` is a
# SUBSTRING of what a wrong tag name would print (`Xv0.28.0 does not exist`), so the unanchored
# needle passes under a mutation of the very thing it is asserting.
eq "…naming v0.28.0 as the tag it waited for"     "true" \
   "$(has 'release-tag-check: v0.28.0 does not exist' "$OUT")"
eq "…and the tag that IS at the commit"           "true" "$(has 'carrying: release-0.28.0' "$OUT")"
# PRESENCE AND ABSENCE BOTH, because an assertion of absence alone certifies whatever replaces
# the text it forbids — including nothing at all.
eq "…saying the key may not be set at all"        "true" \
   "$(has 'its tag_format if that key is set, else the default v{{version}}' "$OUT")"
eq "…never asserting the config carries the key"  "false" "$(has 'tag_format maps version' "$OUT")"
tf_untag release-0.28.0

# ── A CONTROL CHARACTER IN THE TAG NAME IS A WORKFLOW COMMAND ─────────────────────────────────
# `${TAG}` is interpolated into a `::error::` annotation, so a NEWLINE in `tag_format` makes the
# refusal carry a second, attacker-chosen workflow command into the promote job's log. No legal
# ref can hold one anyway (`git check-ref-format` forbids space and control characters), so the
# name is refused fail-closed before any poll rather than sanitised.
_wf_lines() { printf '%s\n' "$1" | awk '/^::/ { n++ } END { print n + 0 }'; }
echo "== a tag name carrying a control character is refused, never emitted =="
tf_run tf-inject.json
eq "a newline in tag_format → rc 2"               "2"    "$RC"
eq "…named as whitespace/control in the tag"      "true" "$(has 'contains whitespace or a control character' "$OUT")"
eq "…and NO workflow command is emitted"          "0"    "$(_wf_lines "$OUT")"
# CONTROL — the same counter over an ordinary refusal, which DOES emit one. Without it, "no
# workflow command" would also be true of a counter that can only ever answer zero.
tf_tag release-0.28.0
tf_run .release-pr.json
# NON-ZERO, not a fixed count: a host with no coreutils `timeout` legitimately adds a
# `::warning::` of its own, and a control that reds on THAT is measuring the host, not the tool.
eq "control: an ordinary refusal DOES emit one"   "false" \
   "$([ "$(_wf_lines "$OUT")" -eq 0 ] && echo true || echo false)"
tf_untag release-0.28.0

# ── THE SECOND LOOK IS A READ, SO IT HAS THREE OUTCOMES TOO ───────────────────────────────────
# The cause-naming look above can itself fail, and a refusal that answered "the release was NOT
# tagged" because the look that would have found another tag never completed would be the same
# wrong-but-specific cause one layer down. The remote here is `_counting_remote` set to serve the
# POLL and refuse the next read: with `--timeout 0` the tool looks exactly once, so the absence
# is measured and the follow-up look is the read that fails — deterministically, not on a timing
# race.
echo "== a follow-up look that cannot READ leaves the CAUSE unmeasured, not guessed =="
_counting_remote "$T/follow-up-remote" "$T/follow-up-remote.reads" 0 1 never "$REMOTE2"
RC=0
OUT="$( (cd "$R2" && GIT_ALLOW_PROTOCOL=ext "$BIN" --before "$TF_BEFORE" --after "$TF_RELEASE" \
          --remote "ext::$T/follow-up-remote" --config tf-release.json --timeout 0) 2>&1 )" || RC=$?
eq "an unreadable follow-up look → still rc 1"  "1"    "$RC"
eq "…the absence itself is still reported"      "true" "$(has 'release-0.28.0 does not exist' "$OUT")"
eq "…the CAUSE is named as unmeasured"          "true" "$(has 'CAUSE here is unmeasured' "$OUT")"
eq "…quoting the follow-up read's own error"    "true" "$(has 'read 2 refused' "$OUT")"
eq "…and it does NOT pick a cause anyway"       "false" "$(has 'merged and was NOT tagged' "$OUT")"
eq "…nor claim the commit carries another tag"  "false" "$(has 'IS tagged on' "$OUT")"
# CONTROL — the same helper re-written to refuse nothing serves BOTH reads, and the verdict is
# the ordinary measured-absent one. Without it, "reds as unmeasured" would also be true of a tool
# that reports every absence that way.
_counting_remote "$T/follow-up-remote" "$T/follow-up-remote.reads" 0 0 never "$REMOTE2"
RC=0
OUT="$( (cd "$R2" && GIT_ALLOW_PROTOCOL=ext "$BIN" --before "$TF_BEFORE" --after "$TF_RELEASE" \
          --remote "ext::$T/follow-up-remote" --config tf-release.json --timeout 0) 2>&1 )" || RC=$?
eq "control: both reads served → rc 1"          "1"    "$RC"
eq "control: …and the cause IS measured"        "true" "$(has 'No tag of ANY name points at' "$OUT")"
eq "control: …never reported as unmeasured"     "false" "$(has 'CAUSE here is unmeasured' "$OUT")"

# ── the tag_format read is DELEGATED to its one owner, not re-implemented here ─────────────────
echo "== the tag name is resolved by the sibling that owns tag_format =="
eq "release-tag-check calls release-pr-body"      "true" \
   "$(has 'release-pr-body' "$(cat "$BIN")")"
# The tool reads NO config of its own — both config-derived facts come from a sibling. `jq` is
# the witness: every config read in this repo goes through it, so its absence is the property.
# Asserted over the CODE, with comment lines stripped: the first cut of this line greped the
# whole file and read `true` off the word "jq" inside a comment explaining the delegation — an
# instrument that greps a NAME answers about the NAME, not about what the program does.
TAGCHECK_CODE="$(grep -v '^[[:space:]]*#' "$BIN")"
eq "…and reads no config itself (no jq in its code)" "false" "$(has 'jq' "$TAGCHECK_CODE")"
eq "witness: the stripper kept the code"          "true"  "$(has 'ls-remote' "$TAGCHECK_CODE")"
# A MISSING sibling is refused by name, not defaulted. Driven for real: a bin/ directory holding
# the tool and its classifier but NOT the tag reader.
NOBIN="$T/nobin"; mkdir -p "$NOBIN"
cp "$BIN" "$HERE/../bin/release-artifacts-check" "$NOBIN/"
rc=0; err="$( (cd "$R2" && "$NOBIN/release-tag-check" --before "$TF_BEFORE" --after "$TF_RELEASE" \
                --remote "$REMOTE2" --timeout 0) 2>&1 )" || rc=$?
eq "a missing tag reader → rc 2"                  "2"    "$rc"
eq "…named, with what it owns"                    "true" "$(has 'release-pr-body is missing or not executable' "$err")"
eq "…and no tag was asserted from a guessed name" "false" "$(has 'must exist at' "$err")"
# …AND IT REFUSES ON AN ORDINARY PUSH TOO, which is the whole point of checking both siblings up
# front. The tag reader is only USED on a release push, so a check at its first use let a
# mis-vendored bin/ — the exact scenario docs/INSTALL.md §6b's vendoring rule exists for — run
# green on every ordinary push and die rc 2 at the first real release: the highest-cost moment
# to discover it. Measured before the hoist: this same invocation printed "not a release push"
# and exited 0.
rc=0; err="$( (cd "$R" && "$NOBIN/release-tag-check" --before "$RELEASE_SHA" --after "$NONRELEASE_SHA" \
                --remote "$REMOTE" --timeout 0) 2>&1 )" || rc=$?
eq "a NON-release push refuses too → rc 2"        "2"    "$rc"
eq "…naming the missing sibling"                  "true" "$(has 'release-pr-body is missing or not executable' "$err")"
eq "…rather than passing as a non-release push"   "false" "$(has 'not a release push' "$err")"
# CONTROL — the same non-release push through a COMPLETE bin/ still asserts nothing and exits 0,
# so the refusal above is about the missing sibling and not about this range.
cp "$HERE/../bin/release-pr-body" "$NOBIN/"
rc=0; err="$( (cd "$R" && "$NOBIN/release-tag-check" --before "$RELEASE_SHA" --after "$NONRELEASE_SHA" \
                --remote "$REMOTE" --timeout 0) 2>&1 )" || rc=$?
eq "control: a complete bin/ → rc 0"              "0"    "$rc"
eq "control: …and it asserts nothing"             "true" "$(has 'not a release push' "$err")"
rm -f "$NOBIN/release-pr-body"

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
# measured anything.
#
# ⛔ THE FAILED READ IS SEQUENCED ON THE TOOL'S OWN READS, NEVER ON A WALL CLOCK (card#8485) —
# the late-tag arm's defect in its mirror image, and the one the card was filed against. The
# remote used to APPEAR mid-run by an atomic rename out of a `( sleep 3; mv … ) &`, so the
# fixture needed the tool's unbounded startup (the two sibling delegations above) to finish
# inside 3s for even ONE poll to fail. The elapsed clocks this file then carried — since
# re-based off the tool's own reads by card#8533 — put that startup at the figure this file's
# header measures, over the 21 red runs of that same 30-run baseline at load ~26: every poll
# then answered, `UNREADABLE` was 0, and this cell and the one below it went red TOGETHER on 16
# of 30 runs — the perfect correlation being the tell, since both clauses hang off that single
# counter. The tool was CORRECT on every one of those runs: an all-answered absence carries no
# caveat, which is precisely what the control below asserts. The refusal is still a REAL failed
# read — a real `git ls-remote` against a helper that exits non-zero, with git's own stderr
# reaching the tool — and it is now the FIRST read by construction.
echo "== a run whose reads partly failed reports the absence AND the failed polls =="
# ONLY THE FIRST READ IS REFUSED. That is what keeps the FINAL poll an answering one without the
# fixture having to know, or care, how many polls the tool fits inside its own 8s bound — one
# refusal costs milliseconds (see `_counting_remote`), so the bound cannot expire on it.
_counting_remote "$T/flaky-remote" "$T/flaky-remote.reads" 1 0 never
RC=0
OUT="$( (cd "$R" && GIT_ALLOW_PROTOCOL=ext "$BIN" --before "$BEFORE_SHA" --after "$RELEASE_SHA" \
          --remote "ext::$T/flaky-remote" --timeout 8 --interval 1) 2>&1 )" || RC=$?
eq "mixed run → the untagged verdict"             "1"    "$RC"
eq "…which names the tag as absent"               "true" "$(has 'v0.28.0 does not exist on' "$OUT")"
eq "…and states the absence is MEASURED"          "true" "$(has 'measured, not inferred' "$OUT")"
eq "…while still counting the polls that failed"  "true" "$(has 'could not read' "$OUT")"
# HOW MANY, not merely THAT — the count is the fixture's own decision now rather than a race's,
# so it can be pinned, and pinning it is what keeps this arm's SUBJECT from drifting. Every
# other cell here is satisfied by ANY non-zero count: a helper that came to refuse three of
# five reads, with the last still answering, would leave all of them green while no longer
# testing the one-lost-read case anyone wrote this for. (It does NOT stand in for the
# all-failed verdict — refusing every read reds `…states the absence is MEASURED` above, since
# that is the UNREADABLE branch and it prints no such caveat at all.)
eq "…naming HOW MANY of them failed"              "true" "$(has '(1 of ' "$OUT")"
# CONTROL — the SAME helper, re-driven. Its one refusal is already spent, so every read now
# answers: identical transport, identical remote, identical binary, differing in exactly the
# failed poll under test. A run with NO failed poll must carry no such caveat, or the clause
# above is printed unconditionally and asserts nothing.
RC=0
OUT="$( (cd "$R" && GIT_ALLOW_PROTOCOL=ext "$BIN" --before "$BEFORE_SHA" --after "$RELEASE_SHA" \
          --remote "ext::$T/flaky-remote" --timeout 2 --interval 1) 2>&1 )" || RC=$?
eq "control: an all-answered run → same verdict"  "1"    "$RC"
# THE PRESENCE WITNESS. rc 1 is shared by the measured-absence and the UNREADABLE verdicts, and
# the caveat cell below is an absence-only check the UNREADABLE branch also satisfies (it prints
# no such caveat at all) — so without this line a helper that refused EVERY read would leave
# both control cells green with the control's subject false.
eq "control: …whose reads ANSWERED"               "true" "$(has 'v0.28.0 does not exist on' "$OUT")"
eq "control: …and no failed-poll caveat"          "false" "$(has 'measured, not inferred' "$OUT")"

# ── EACH POLL IS BOUNDED, so the tool's own --timeout is what fires ────────────────────────────
# `release-promote-cards.yml` states that this tool's bound fires before its `timeout-minutes`
# backstop, "a timeout-minutes kill reports as `cancelled`, not `failure`". Nothing enforced it:
# one hung `ls-remote` could consume the whole job entitlement and produce exactly the
# `cancelled` outcome that comment says it avoids. The hang here is REAL — an `ext::` remote
# helper that sleeps — so the kill is measured, not stubbed.
if command -v timeout >/dev/null 2>&1; then
  echo "== one hung poll is killed and scored as unreadable, not as an absent tag =="
  # THE CLOCK STARTS WHEN THE HUNG READ DOES, NOT WHEN THE TEST DOES (card#8533). This bound is
  # the one assertion in this file whose subject really IS elapsed time — a read's own duration
  # — so it cannot be re-expressed in reads. It was measured from a `SECONDS` set in the TEST,
  # which put that same startup inside a 10s window; the fixture is `_counting_remote` now
  # precisely so the helper can stamp the instant read 1 began, and the window below starts
  # there. What is measured is the read plus the tool's own teardown, and nothing before it.
  HANG_READS="$T/hang-remote.reads"
  _counting_remote "$T/hang-remote" "$HANG_READS" 0 0 never "$REMOTE" 20
  RC=0
  OUT="$( (cd "$R" && GIT_ALLOW_PROTOCOL=ext "$BIN" --before "$BEFORE_SHA" --after "$RELEASE_SHA" \
            --remote "ext::$T/hang-remote" --read-timeout 1 --timeout 0) 2>&1 )" || RC=$?
  HANG_ELAPSED="$(_since_stamp "$HANG_READS.read1")"
  eq "a hung remote → rc 1"                       "1"    "$RC"
  eq "…named as a KILLED read, with its bound"    "true" "$(has 'KILLED after 1s' "$OUT")"
  eq "…scored as unreadable"                      "true" "$(has 'could NOT READ' "$OUT")"
  eq "…and NOT as an absent tag"                  "false" "$(has 'does not exist on' "$OUT")"
  # THE FIXTURE'S OWN PRECONDITION, ASSERTED RATHER THAN ASSUMED, as the late-tag arm does: the
  # window below is "from read 1", so a run in which the helper was never reached would measure
  # an interval that never happened. Without this cell that shows up only as a wrong number.
  eq "…the hung read was actually TAKEN (the window below is that read's)" "true" \
     "$(_stamp_taken "$HANG_READS.read1")"
  # THE DISCRIMINATING CONTROL. The fixture sleeps 20s, so an unbounded read could only return
  # after 20; returning in a fraction of that is the bound firing, and nothing else.
  #
  # THE BOUND IS 5 BECAUSE THE WINDOW IS NOW ~1s, AND THE COMPANION CELL CANNOT COVER FOR IT.
  # `…named as a KILLED read, with its bound` reads `KILLED after ${READ_BOUND}s` off the FLAG
  # VALUE, never off the measured duration, so it is green for any bound the tool was told to
  # use — including one it then failed to apply. A read that regressed to several seconds while
  # still announcing `1s` therefore has this cell as its ONLY witness, and the 10 it inherited
  # — sized for a window that still contained the startup this file's header measures — left
  # exactly that regression green.
  # Measured 1s on three consecutive runs at load ~8 with the startup outside the window; 5 is
  # 5x that, and it is watched red against a 6s read that still prints `KILLED after 1s`.
  [ "$HANG_ELAPSED" -lt 5 ] && ok "…and the BOUND is what ended it (${HANG_ELAPSED}s from read 1 < the fixture's 20s hang)" \
                            || bad "…the read ran ${HANG_ELAPSED}s from its own start — it was not bounded"
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
