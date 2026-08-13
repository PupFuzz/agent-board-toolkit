#!/usr/bin/env bash
# release-artifacts-selftest.sh — deterministic, network-free checks for
# `bin/release-artifacts-check`, against a THROWAWAY fixture git repo under mktemp.
#
# WHY THIS FILE EXISTS. `.release-pr.json`'s `artifacts` array names the must-move-together
# release set, and its only consumer was a PRINTER (`release-pr-body` renders it as a `- [ ]`
# checklist). Nothing asserted a member actually moved, so the class defect — a guard that
# reads a proper SUBSET of a must-move-together file set cannot fail on the member it never
# reads — had a subset of size zero here (card#5910).
#
# AND THE SUBSET IS EDITABLE BY THE PR UNDER REVIEW (card#6055). The declared set and the
# release-PR classification keys both live in a file the PR can change, so a head-only read
# lets a PR narrow the verdict it is judged by: delete an `artifacts` entry while still
# updating the file it named and every leg passes, rc 0, no trace anywhere — and from the next
# release the fork point no longer carries the entry either. The verdict surface is therefore
# read from the FORK POINT, and the cases below pin each half of that: what a head edit may
# still do (widen), what it may not (narrow, silently), and the one explicit channel
# (`retired_artifacts`) through which a legitimate retirement gets through.
#
# EVERY DEFECT CLASS THE TOOL CLAIMS TO CATCH IS WATCHED TO FAIL BELOW — the git-state ones
# on their own fixture branch, the config ones on their own config file:
#   * a declared member that did not move;
#   * a `docs/CHANGELOG.md` that moved without gaining its `## [V]` section;
#   * a member DELETED — which APPEARS in the diff, so the moved-leg alone passes it;
#   * two failing members reported as two, not as the first one;
#   * an unreadable version file at either end — which must refuse, rc 2, and never classify
#     as "not a release PR", since that is a silent non-run of the whole gate;
#   * a config entry that expands to NO path (an empty brace set, or a leading-whitespace
#     entry) — which would drop a declared member from both the assertions and the count;
#   * a declared entry that head DELETED, with and without an acknowledgement;
#   * classification keys retargeted at head, so the PR classifies as "not a release PR";
#   * a member that is a symlink, a directory or a gitlink at head — each of which answers
#     the content read with something (a target path, a tree listing, a commit log) that can
#     carry the version string while asserting nothing about a release artifact.
# That expands-to-nothing pair is the tool's own defect class one layer up, and its rc
# assertion is not decoration: `_expand_braces` is consumed through a process substitution, so
# a `die` placed INSIDE it printed the right message and then let the run finish rc 0 with the
# member silently dropped. Only the exit-status leg saw that.
#
# SEVEN CASES PIN BEHAVIOUR THAT IS RC 0 TODAY (before card#6055): the entry deletion (2), the
# classification retarget (3), the wholesale deletion (8), the symlink (11), the directory
# arm A (12), the gitlink (13), and the merge-base-unresolvable opt-out (16). Each names the
# pre-fix verdict in its own comment, so the fix is *seen* to change a verdict rather than
# asserted to.
#
# FOUR MORE CASES (26–29) CAME FROM THE REVIEW ROUND, and each pins a verdict the fork-point
# read got wrong on its first pass: a `--config` inside a DIFFERENT repository, which answered
# confidently about THIS repo's own root config (26); a fork-point entry whose boundary refusal
# fired rc 2, so the PR repairing it was redded by the entry it deleted (27); a config blob
# that PARSES AND THEN ERRORS, which slipped both guards and died rc 5 with a raw jq traceback
# on either side of the range (28); and an empty-string entry, silently dropped where its
# whitespace-only twin died rc 2 (29). Cases 27 and 29 also pin the SOURCE-dependence itself:
# the same shapes declared at HEAD keep rc 2, so the fork-point warning is a decision about
# which ref declared the entry, not a weakening of the boundary check.
#
# The happy paths are equally load-bearing, as the controls for all of the above: a
# version-unchanged PR and a fully-correct release PR must both exit 0, else "fails on defect
# X" would also be true of a tool that fails on everything.
#
# HARNESS RULE — A CASE'S CONFIG LIVES IN THE TREE *AND* IN A COMMIT. `run()` never checks
# anything out and the fixture tree sits on `base-0.1.0`, while the tool now reads the config
# from the COMMIT at each end of the range. A tree-only config therefore makes the SHA reads
# miss (that is case 24's whole subject) and a commit-only config exercises the
# not-in-the-checkout fallback rather than the case's own subject (case 21's). So every
# ordinary case writes its config with `cfg`, which both stages it for the case's head commit
# and records it for re-materialization into the tree after the final checkout; the two
# deliberate one-sided fixtures use `cfg_commit_only` / `TREE_ONLY_CFG` instead, on branches
# of their own so neither can mask the other.
#
# NEVER OPERATES ON THE REAL CHECKOUT. The fixture is built by `git init` under mktemp and
# removed by the prelude's EXIT trap. No `git checkout --` anywhere: that command destroys
# uncommitted work in whatever tree it is pointed at, and a selftest is not a place to find
# out which tree that was.
#
# WHAT A GREEN RUN HERE PROVES — the weakest property the assertions support: that the tool
# reports the defect shapes above on fixtures carrying them, and exits 0 on the clean shapes.
# It says nothing about whether any REAL repo's `artifacts` array enumerates the right set —
# an under-declared set is invisible to this tool by construction, and so is an entry whose
# prose downgrades it to the weak arm (open by decision; case 4 pins that it stays rc 0).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/release-artifacts-check"
_need -x "$BIN"

# Deterministic git identity/config, independent of the runner's.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
g() { git -c init.defaultBranch=main -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

_mktmp_scratch; T="$TMP"     # the prelude owns cleanup
R="$T/repo"

# run <base> <head> [extra args...] — invoke the tool in the fixture repo ROOT, capturing both
# streams together (the failure lines go to stdout as `::error::`, the summary to stderr) and
# the exit status. Sets RC and OUT.
run() {
  local base="$1" head="$2"; shift 2
  RC=0
  OUT="$( (cd "$R" && "$BIN" --base "$base" --head "$head" "$@") 2>&1 )" || RC=$?
}
# run_in <subdir> <base> <head> [extra args...] — the same, invoked from a SUBDIRECTORY of the
# fixture repo. `--config` is CWD-relative while every blob read is root-relative, and a plain
# `ls-tree` pathspec is CWD-relative too, so a subdirectory invocation is the only shape that
# can tell a normalized implementation from one that silently reads the wrong paths.
run_in() {
  local sub="$1" base="$2" head="$3"; shift 3
  RC=0
  OUT="$( (cd "$R/$sub" && "$BIN" --base "$base" --head "$head" "$@") 2>&1 )" || RC=$?
}

# --- config materialization --------------------------------------------------
# cfg <path> <json> — write a config into the tree (for the case's head commit, which is made
# by the caller's `add -A`) AND record it so it is re-materialized into the working tree after
# the fixture's final checkout. Both halves are needed: see the harness rule in the header.
declare -A TREE_CFG=()
cfg() { printf '%s\n' "$2" > "$R/$1"; TREE_CFG["$1"]="$2"; }
# cfg_commit_only <path> <json> — committed on the case's branch, deliberately NOT recorded,
# so the working tree never carries it (case 21).
cfg_commit_only() { printf '%s\n' "$2" > "$R/$1"; }

# The four-entry declared set the whole fixture is built around: a plain version-bearing file,
# the `[{{version}}] section` shape, a prose-suffixed row shape, and a brace-set whose
# FILENAME carries the version (so the "path contains V ⇒ agrees" arm is exercised). Five
# comparison units from four entries.
CFG_BASE='{
  "main_branch": "main",
  "dev_branch": "dev",
  "version_file": "VERSION",
  "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": [
    "VERSION → {{version}}",
    "docs/CHANGELOG.md → [{{version}}] section",
    "NOTES.md § Recent releases row",
    "sboms/v{{version}}.{a,b}.json"
  ]
}'
# A FORK-POINT set carrying two well-formed entries and every unusable entry shape at once —
# a leading-whitespace entry, an empty brace set, a literal comparison sentinel, and the empty
# string. All four are rc 2 when they are read from HEAD (the PR that wrote them can fix them);
# read from the fork point they are a merged commit no PR can edit, and the PR that repairs one
# repairs it by DELETING it — so refusing there reds the repair on the very entry it removes.
CFG_BADENTRY_BASE='{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": [
    "VERSION → {{version}}",
    "NOTES.md § Recent releases row",
    "   docs/CHANGELOG.md → [{{version}}] section",
    "sboms/v{{version}}{}.json",
    "sboms/v@@ABTK_VERSION@@.a.json § the sbom",
    ""
  ] }'
# A PARSE-THEN-ERROR blob: a complete JSON value followed by trailing junk. `jq` PRINTS the
# value and THEN exits non-zero, so an output-only parse test reads it as valid.
CFG_TRAILING_JUNK='{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["VERSION → {{version}}"] } and then some trailing junk'

# The same set with the NOTES.md entry DELETED — E1, the narrowing this card exists to catch.
CFG_NO_NOTES='{
  "version_file": "VERSION",
  "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": [
    "VERSION → {{version}}",
    "docs/CHANGELOG.md → [{{version}}] section",
    "sboms/v{{version}}.{a,b}.json"
  ]
}'

# --- fixture -----------------------------------------------------------------
mkdir -p "$R"
g init -q "$R"
mkdir -p "$R/docs" "$R/sboms" "$R/sub" "$R/docs2"

# c0 — a root commit that predates the version file, kept as its own branch. It is an ANCESTOR
# of everything below, so `merge-base pre-version <head>` resolves to it — which is what makes
# the unreadable-version-file case reachable through a real fork point rather than only
# through two refs with no common history (that case has its own fixture further down).
echo "seed" > "$R/src.txt"
g -C "$R" add -A; g -C "$R" commit -qm "chore: root, before the version file exists"
g -C "$R" branch pre-version

# c1 — the version file and every declared member exist, but NOT the release config. This is
# the fork point for the no-baseline (N3) case: a repo that has not yet adopted the config,
# which is exactly the shape of all three real adoption PRs (the config is created INSIDE a
# release PR, so the fork point never carries it).
echo "0.1.0" > "$R/VERSION"
printf '# Changelog\n\n## [0.1.0] - 2026-01-01\n\n- first\n' > "$R/docs/CHANGELOG.md"
printf '# Notes\n\n| Version | Date |\n| --- | --- |\n| v0.1.0 | 2026-01-01 |\n' > "$R/NOTES.md"
echo '{"v":"0.1.0"}' > "$R/sboms/v0.1.0.a.json"
echo '{"v":"0.1.0"}' > "$R/sboms/v0.1.0.b.json"
echo "unrelated" > "$R/src.txt"
echo "s" > "$R/sub/inner.txt"
# A blob at a path a later head replaces with a DIRECTORY (case 12 arm A), and a constant
# carrying a version-shaped string, for the classification-retarget case (3).
echo "a release bundle, as a file" > "$R/bundle"
echo "pinned 9.9.9 forever" > "$R/CONST.txt"
g -C "$R" add -A; g -C "$R" commit -qm "chore: version file and members at 0.1.0, no release config yet"
g -C "$R" branch pre-config

# c2 — the release config, plus the three auxiliary configs whose FORK-POINT state is the
# subject of a case (unparseable, key-less, empty-at-both-ends). They must exist here rather
# than on a head branch: the fork point is what the case is about.
printf '%s\n' "$CFG_BASE" > "$R/.release-pr.json"
printf '%s\n' '{ "version_file": "VERSION", "artifacts": [,] }' > "$R/cfg-brokenbase.json"
printf '%s\n' '{ "artifacts": ["VERSION → {{version}}"] }'      > "$R/cfg-keyless.json"
# Two copies of the unusable-entry baseline, because the two runs over it want different heads:
# one repairs the bad entries and keeps both good ones, the other also drops a good one.
printf '%s\n' "$CFG_BADENTRY_BASE"   > "$R/cfg-badentry.json"
printf '%s\n' "$CFG_BADENTRY_BASE"   > "$R/cfg-badentry-narrow.json"
printf '%s\n' "$CFG_TRAILING_JUNK"   > "$R/cfg-trailingjunk-base.json"
printf '%s\n' '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": [] }' > "$R/cfg-empty-both.json"
# A config RESIDENT in a subdirectory, at both ends. `--config sub-cfg.json` from `sub/` names
# `sub/sub-cfg.json`, and the root-relative spelling of that is the only one every blob read
# can use — so this is the fixture that tells a normalized `--config` from an unnormalized one.
printf '%s\n' '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": ["VERSION → {{version}}"] }' > "$R/sub/sub-cfg.json"
g -C "$R" add -A; g -C "$R" commit -qm "chore: adopt the release config at 0.1.0"
g -C "$R" branch base-0.1.0

# bump_tree <mode> — materialize the 0.2.0 release state in the working tree. One builder, so
# each case differs from the correct one by exactly the defect it is named for (a per-case
# hand-built tree would let two things drift at once).
bump_tree() {
  local mode="$1"
  case "$mode" in
    nonrelease)
      echo "changed, but no version bump" > "$R/src.txt"
      return;;
    poison)
      # E5 — the version file's CONTENT, which head owns, decides the classification, and the
      # extraction takes the FIRST regex match. One prepended line and a real release PR reads
      # as "version unchanged".
      printf '# was 0.1.0\n0.2.0\n' > "$R/VERSION";;
    *)
      echo "0.2.0" > "$R/VERSION";;
  esac
  case "$mode" in
    no-section)
      # moved, but the new section header is missing — the exact shape a hand-edited
      # changelog takes when the entry lands under the previous version's heading.
      printf '# Changelog\n\n## [0.1.0] - 2026-01-01\n\n- first\n- second, filed under the OLD heading\n' > "$R/docs/CHANGELOG.md";;
    *)
      printf '# Changelog\n\n## [0.2.0] - 2026-02-02\n\n- second\n\n## [0.1.0] - 2026-01-01\n\n- first\n' > "$R/docs/CHANGELOG.md";;
  esac
  case "$mode" in
    not-moved|two-bad|poison) : ;;   # NOTES.md deliberately left at its 0.1.0 content
    *) printf '# Notes\n\n| Version | Date |\n| --- | --- |\n| v0.2.0 | 2026-02-02 |\n| v0.1.0 | 2026-01-01 |\n' > "$R/NOTES.md" ;;
  esac
  echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.a.json"
  case "$mode" in
    two-bad) : ;;             # the `b` member of the brace set is never created
    *) echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.b.json" ;;
  esac
  # Removed from the WORKING TREE, then staged by `add -A` — `git rm` would refuse a path
  # whose modification is already staged, and `-f` to force it is not worth the reach.
  if [ "$mode" = deleted ]; then rm -f "$R/NOTES.md"; fi
}

mk_head() { # <branch> <mode> — a head carrying the stock config
  g -C "$R" checkout -q -B "$1" base-0.1.0
  bump_tree "$2"
  g -C "$R" add -A; g -C "$R" commit -qm "release: $2"
}
mk_cfg_head() { # <branch> <mode> <config-json> — a head that also EDITS `.release-pr.json`
  g -C "$R" checkout -q -B "$1" base-0.1.0
  bump_tree "$2"
  printf '%s\n' "$3" > "$R/.release-pr.json"
  g -C "$R" add -A; g -C "$R" commit -qm "release: $1"
}

for m in nonrelease good not-moved no-section deleted two-bad; do mk_head "head-$m" "$m"; done

# --- the fork-point comparison heads (card#6055) ------------------------------
# E1 — the entry is deleted while the file it named IS still updated, so every remaining leg
# passes. Pre-fix: rc 0, no trace. The deletion is only visible against the fork point.
mk_cfg_head head-e1            good       "$CFG_NO_NOTES"
# …the same narrowing, ACKNOWLEDGED through the one declared channel.
mk_cfg_head head-e1-retired    good       "${CFG_NO_NOTES%\}}, \"retired_artifacts\": [\"NOTES.md\"] }"
# …a tombstone planted against a member that is STILL declared.
mk_cfg_head head-e1-both       good       "${CFG_BASE%\}}, \"retired_artifacts\": [\"NOTES.md\"] }"
# …the same narrowing on a PR that is not a release at all.
mk_cfg_head head-e1-nonrelease nonrelease "$CFG_NO_NOTES"
# …and the retirement channel given a non-array value (the type guard).
mk_cfg_head head-retired-bad   good       "${CFG_NO_NOTES%\}}, \"retired_artifacts\": \"NOTES.md\" }"
# Wholesale: the whole `artifacts` key is gone at head, which head-only reads answer with
# "no artifacts declared — nothing to assert".
mk_cfg_head head-wholesale     good       '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+" }'
# E2 — the classification keys retargeted at a constant present at both ends. Pre-fix the run
# reads head's keys, both ends say 9.9.9, and the gate exits 0 on a PR missing a member.
mk_cfg_head head-e2            not-moved  "${CFG_BASE/\"version_file\": \"VERSION\",/\"version_file\": \"CONST.txt\",}"
# N1 — head relocates the version file and updates its own config to match; the fork point
# still names the old path.
g -C "$R" checkout -q -B head-relocate base-0.1.0
bump_tree good
g -C "$R" mv VERSION VERSION.txt
printf '%s\n' "${CFG_BASE/\"version_file\": \"VERSION\",/\"version_file\": \"VERSION.txt\",}" > "$R/.release-pr.json"
g -C "$R" add -A; g -C "$R" commit -qm "release: version file relocated at head"
# E5 — the version file's content poisoned so the PR misclassifies, with and without a
# narrowing riding along.
mk_head     head-e5      poison
mk_cfg_head head-e5-lost poison "$CFG_NO_NOTES"
# WIDENING — a third alternative added to the live brace set. Under a string-identity
# comparison unit this reds (the old entry string is gone), which is exactly what the expanded
# unit exists to prevent.
g -C "$R" checkout -q -B head-wider base-0.1.0
bump_tree good
echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.c.json"
printf '%s\n' "${CFG_BASE/sboms\/v\{\{version\}\}.\{a,b\}.json/sboms/v{{version\}\}.{a,b,c\}.json}" > "$R/.release-pr.json"
g -C "$R" add -A; g -C "$R" commit -qm "release: widen the brace set"

# --- heads for the AGREES arms ----------------------------------------------
# Each carries a CHANGELOG that mentions 0.2.0 in a way the WEAK (content-mention) arm accepts
# but the STRONG (heading-line) arm must not, so the two arms are separable: if the strong arm
# ever silently downgraded to the weak one, these would go green.
#
# The three selector spellings are three COMMITTED config files rather than one file rewritten
# per invocation: the tool reads the config from the commit, so a rewritten tree copy would
# change nothing and every case would silently answer about the same config.
mk_agrees_head() { # <branch> <changelog-body>
  g -C "$R" checkout -q -B "$1" base-0.1.0
  echo "0.2.0" > "$R/VERSION"
  printf '%s' "$2" > "$R/docs/CHANGELOG.md"
  printf '# Notes\n\n| v0.2.0 | 2026-02-02 |\n| v0.1.0 | 2026-01-01 |\n' > "$R/NOTES.md"
  echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.a.json"
  echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.b.json"
  local sel
  for sel in 'section:strong-section.json' 'entry:strong-entry.json' 'SECTION:strong-upper.json'; do
    cfg "${sel#*:}" "{ \"version_file\": \"VERSION\", \"version_regex\": \"[0-9]+\\\\.[0-9]+\\\\.[0-9]+\",
      \"artifacts\": [\"VERSION → {{version}}\", \"docs/CHANGELOG.md → [{{version}}] ${sel%%:*}\"] }"
  done
  g -C "$R" add -A; g -C "$R" commit -qm "release: $1"
}
# (1) the version appears only as INLINE PROSE — never at the start of a line.
mk_agrees_head head-inline-mention \
  '# Changelog

## [0.1.0] - 2026-01-01

- bumped to 0.2.0, see ## [0.2.0] below for the entry
'
# (2) a heading whose brackets hold a REGEX-METACHAR LOOK-ALIKE of the version. `0.2.0` as an
# unescaped regex matches `0x2x0`; as a fixed string it must not.
mk_agrees_head head-metachar-heading \
  '# Changelog

## [0x2x0] - 2026-02-02

- 0.2.0 is mentioned here in prose so the WEAK arm would still pass
'

# A head that deletes the version file — the HEAD-side unreadable read, with a readable fork
# point, so the two ends fail closed independently rather than one masking the other.
g -C "$R" checkout -q -B head-noversion base-0.1.0
rm -f "$R/VERSION"
g -C "$R" add -A; g -C "$R" commit -qm "chore: head with no VERSION file"

# --- §C — a declared member that is not a regular file -----------------------
# SYMLINK. `git show <ref>:<symlink>` yields the TARGET PATH STRING, which here carries the
# version, so the weak content-mention arm passes it: rc 0 pre-fix.
g -C "$R" checkout -q -B head-symlink base-0.1.0
echo "0.2.0" > "$R/VERSION"
echo "the real notes for 0.2.0" > "$R/notes-0.2.0.md"
ln -s notes-0.2.0.md "$R/LINK.md"
cfg cfg-symlink.json '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["VERSION → {{version}}", "LINK.md § notes row"] }'
g -C "$R" add -A; g -C "$R" commit -qm "release: a symlink member"

# DIRECTORY, arm A — a blob at the member path at the fork point, REPLACED by a directory at
# head. Only this shape makes `diff --name-only` emit a row EQUAL to the member path (the
# deleted blob), so the moved leg passes; the tree listing carries `v0.2.0.json`, so the weak
# arm passes too. rc 0 pre-fix — the 0 → 1 discriminator.
g -C "$R" checkout -q -B head-dir-a base-0.1.0
echo "0.2.0" > "$R/VERSION"
rm -f "$R/bundle"; mkdir -p "$R/bundle"; echo '{}' > "$R/bundle/v0.2.0.json"
cfg cfg-dir.json '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["VERSION → {{version}}", "bundle § release bundle"] }'
g -C "$R" add -A; g -C "$R" commit -qm "release: a directory member replacing a blob"

# DIRECTORY, arm B — a FRESH directory, with no pre-existing blob at the path. The moved leg
# already reds today (no diff row equals the member path), so this arm is 1 → 1: the control
# here is the DIAGNOSIS, not the rc.
g -C "$R" checkout -q -B head-dir-b base-0.1.0
echo "0.2.0" > "$R/VERSION"
mkdir -p "$R/fresh"; echo '{}' > "$R/fresh/v0.2.0.json"
cfg cfg-dir-b.json '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["VERSION → {{version}}", "fresh § release bundle"] }'
g -C "$R" add -A; g -C "$R" commit -qm "release: a freshly added directory member"

# GITLINK whose commit IS in this store (a superproject-commit gitlink, not an ordinary
# submodule — an ordinary one's commit is absent, so `cat-file -e` already reds it today).
# `git show <ref>:<gitlink>` yields the COMMIT LOG, whose subject here carries the version.
g -C "$R" checkout -q -B gl-target base-0.1.0
echo "x" > "$R/gl.txt"
g -C "$R" add -A; g -C "$R" commit -qm "chore: gitlink target for 0.2.0"
GL_SHA="$(g -C "$R" rev-parse gl-target)"
g -C "$R" checkout -q -B head-gitlink base-0.1.0
echo "0.2.0" > "$R/VERSION"
cfg cfg-gitlink.json '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["VERSION → {{version}}", "gl § the pinned bundle"] }'
g -C "$R" add -A
g -C "$R" update-index --add --cacheinfo "160000,$GL_SHA,gl"
g -C "$R" commit -qm "release: a gitlink member"

# A member path containing glob METACHARACTERS, with siblings a glob would have matched. The
# literal `docs2/gone?.md` is deliberately NOT created while `docs2/goneX.md` is: a globbing
# moved-leg or a globbing mode read would find the sibling and report "does not agree" instead
# of "missing at head".
g -C "$R" checkout -q -B head-glob base-0.1.0
echo "0.2.0" > "$R/VERSION"
echo "release 0.2.0" > "$R/docs2/star*.md"
echo "a sibling a glob would match, with NO version in it" > "$R/docs2/starX.md"
echo "release 0.2.0" > "$R/docs2/goneX.md"
cfg cfg-glob.json '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["VERSION → {{version}}", "docs2/star*.md § a literal star", "docs2/gone?.md § a literal question mark"] }'
g -C "$R" add -A; g -C "$R" commit -qm "release: glob-metacharacter member paths"

# --- config-location fixtures (complements, one branch each) -----------------
# COMMITTED AT HEAD, ABSENT FROM THE CHECKOUT. Pre-fix this died rc 2 with the false diagnosis
# "no config in this repo". `cfg-tree-only.json` is committed here too, as case 24's control:
# the same config, committed, must produce a normal verdict.
g -C "$R" checkout -q -B head-cfg-committed-only base-0.1.0
echo "0.2.0" > "$R/VERSION"
CFG_ONE_MEMBER='{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["VERSION → {{version}}"] }'
cfg_commit_only cfg-committed-only.json "$CFG_ONE_MEMBER"
cfg_commit_only cfg-tree-only.json      "$CFG_ONE_MEMBER"
g -C "$R" add -A; g -C "$R" commit -qm "release: a config committed but absent from the checkout"

# IN THE CHECKOUT, NOT COMMITTED. Its own branch: sharing one with the case above would let
# either fixture mask the other's failure.
g -C "$R" checkout -q -B head-cfg-tree-only base-0.1.0
echo "0.2.0" > "$R/VERSION"
g -C "$R" add -A; g -C "$R" commit -qm "release: a head that never commits the config"

# The reserved comparison token written literally into a declared entry, and the same entry
# spelled correctly as its control.
g -C "$R" checkout -q -B head-sentinel base-0.1.0
echo "0.2.0" > "$R/VERSION"
echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.a.json"
cfg cfg-sentinel.json '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["VERSION → {{version}}", "sboms/v@@ABTK_VERSION@@.a.json § the sbom"] }'
cfg cfg-sentinel-ok.json '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["VERSION → {{version}}", "sboms/v{{version}}.a.json § the sbom"] }'
g -C "$R" add -A; g -C "$R" commit -qm "release: a literal sentinel in a declared entry"

# A head that REPAIRS the two auxiliary configs whose fork-point copies are unusable, so the
# N3 fallback can be observed producing a normal verdict rather than a refusal.
g -C "$R" checkout -q -B head-fixcfg base-0.1.0
echo "0.2.0" > "$R/VERSION"
cfg cfg-brokenbase.json "$CFG_ONE_MEMBER"
cfg cfg-keyless.json    "$CFG_ONE_MEMBER"
g -C "$R" add -A; g -C "$R" commit -qm "release: repair the auxiliary configs at head"

# --- the BASE-DRIFT scenario (the two-dot defect) ----------------------------
# `drift-fork` is the fork point, and it ALREADY carries NOTES.md's v0.2.0 row — the realistic
# case where a member was updated on the integration branch before the release branch was cut.
# `drift-base` is the base branch moving ON after the fork (a hotfix touching that same
# member). `drift-head` is the release PR: it bumps the version and moves everything EXCEPT
# NOTES.md, which it never touches.
#
# Under a base-TIP (two-dot) diff, NOTES.md differs between drift-base and drift-head, so it
# appears in the diff and satisfies the MOVED leg; it exists at head and its content carries
# 0.2.0, so AGREES passes too — a full, silent, spurious PASS for a member this PR never
# touched. Against the merge base it is correctly absent. This is the fixture that tells the
# two implementations apart, so both verdicts are asserted explicitly below.
g -C "$R" checkout -q -B drift-fork base-0.1.0
printf '# Notes\n\n| Version | Date |\n| --- | --- |\n| v0.2.0 | 2026-02-02 |\n| v0.1.0 | 2026-01-01 |\n' > "$R/NOTES.md"
g -C "$R" add -A; g -C "$R" commit -qm "docs: NOTES.md row added before the release branch was cut"

g -C "$R" checkout -q -B drift-base drift-fork
printf '# Notes\n\n| Version | Date |\n| --- | --- |\n| v0.2.0 | 2026-02-02 (hotfix touched this line) |\n| v0.1.0 | 2026-01-01 |\n' > "$R/NOTES.md"
g -C "$R" add -A; g -C "$R" commit -qm "fix: a hotfix lands on the base branch after the fork"

g -C "$R" checkout -q -B drift-head drift-fork
echo "0.2.0" > "$R/VERSION"
printf '# Changelog\n\n## [0.2.0] - 2026-02-02\n\n- second\n\n## [0.1.0] - 2026-01-01\n\n- first\n' > "$R/docs/CHANGELOG.md"
echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.a.json"
echo '{"v":"0.2.0"}' > "$R/sboms/v0.2.0.b.json"
g -C "$R" add -A; g -C "$R" commit -qm "release: 0.2.0 without touching NOTES.md"

# --- the BASE-BUMP scenario (the two-dot MISCLASSIFICATION) ------------------
# The base branch acquires the SAME version as the PR after the fork. Reading base's tip then
# says "version unchanged ⇒ not a release PR" and the entire gate silently does not run, on a
# PR that IS a release and IS missing a member.
g -C "$R" checkout -q -B bump-base base-0.1.0
echo "0.2.0" > "$R/VERSION"
g -C "$R" add -A; g -C "$R" commit -qm "chore: a version bump lands on the base branch after the fork"

# --- a NON-ASCII member path ------------------------------------------------
# git C-quotes such a path in `diff --name-only` output unless core.quotePath=false, so an
# artifact that genuinely moved reads as "not moved" — a false failure with a wrong diagnosis.
# The name is written as explicit UTF-8 BYTES, not a literal: the bytes are what reach git, and
# a byte escape cannot be re-encoded by the shell's locale or mangled by an editor.
ACCENT=$'\xc3\xa9'                      # U+00E9 LATIN SMALL LETTER E WITH ACUTE
UPATH="docs/caf${ACCENT}.md"
g -C "$R" checkout -q -B head-utf8 base-0.1.0
echo "0.2.0" > "$R/VERSION"
printf '# Changelog\n\n## [0.2.0] - 2026-02-02\n\n## [0.1.0] - 2026-01-01\n' > "$R/docs/CHANGELOG.md"
printf 'release 0.2.0\n' > "$R/$UPATH"
cfg utf8.json "{ \"version_file\": \"VERSION\", \"version_regex\": \"[0-9]+\\\\.[0-9]+\\\\.[0-9]+\",
  \"artifacts\": [\"VERSION → {{version}}\", \"$UPATH → {{version}}\"] }"
g -C "$R" add -A; g -C "$R" commit -qm "release: a non-ASCII member path"

# --- the config/usage-surface configs, committed on head-good ----------------
# One committed path per variant. A single rewritten file cannot serve them: the verdict is a
# function of the BLOB at head, so four rewrites of one path would be four runs against
# whichever content was committed.
g -C "$R" checkout -q -B head-good base-0.1.0
bump_tree good
cfg no-artifacts.json    '{ "version_file": "NO-SUCH-FILE", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+" }'
cfg empty-artifacts.json '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": [] }'
cfg empty-brace.json     '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": ["VERSION → {{version}}", "sboms/v{{version}}{}.json"] }'
cfg leading-space.json   '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": ["VERSION → {{version}}", "   docs/CHANGELOG.md → [{{version}}] section"] }'
cfg two-well-formed.json '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": ["VERSION → {{version}}", "docs/CHANGELOG.md → [{{version}}] section"] }'
cfg empty-entry.json     '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": ["VERSION → {{version}}", ""] }'
# The head halves of the three fork-point fixtures committed at c2. The badentry pair is the
# REPAIR: the unusable entries are gone, which is the only way to repair them.
cfg cfg-badentry.json        '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": ["VERSION → {{version}}", "NOTES.md § Recent releases row"] }'
cfg cfg-badentry-narrow.json '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "artifacts": ["VERSION → {{version}}"] }'
cfg cfg-trailingjunk-base.json "$CFG_ONE_MEMBER"
cfg cfg-trailingjunk.json      "$CFG_TRAILING_JUNK"
cfg no-version-file.json '{ "artifacts": ["VERSION → {{version}}"] }'
cfg bad-syntax.json      '{"artifacts": [,]}'
cfg empty-cfg.json       ''
cfg bad-obj-array.json   '[1,2]'
cfg bad-obj-string.json  '"hello"'
cfg bad-obj-number.json  '42'
cfg bad-obj-null.json    'null'
for bad in 'object:{"a":1}' 'string:"docs/CHANGELOG.md"' 'number:7' 'boolean:true'; do
  cfg "bad-art-${bad%%:*}.json" "{ \"version_file\": \"VERSION\", \"version_regex\": \"[0-9]+\\\\.[0-9]+\\\\.[0-9]+\", \"artifacts\": ${bad#*:} }"
done
g -C "$R" add -A; g -C "$R" commit -qm "release: good"

# Two refs with NO common ancestor — the merge base itself is unresolvable.
g -C "$R" checkout -q --orphan unrelated
g -C "$R" rm -rq --cached . >/dev/null 2>&1 || true
g -C "$R" clean -qfd
echo "an unrelated history" > "$R/other.txt"
g -C "$R" add -A; g -C "$R" commit -qm "chore: an unrelated root"

g -C "$R" checkout -q base-0.1.0

# Re-materialize every recorded config into the WORKING TREE, now that no further checkout
# happens. `cfg-committed-only.json` is deliberately absent from this map (case 21), and
# `cfg-tree-only.json` is written here and nowhere else (case 24).
for p in "${!TREE_CFG[@]}"; do printf '%s\n' "${TREE_CFG[$p]}" > "$R/$p"; done
printf '%s\n' "$CFG_ONE_MEMBER" > "$R/cfg-tree-only.json"
# A config outside any repository, for the --config normalization refusal.
mkdir -p "$T/outside"; printf '%s\n' "$CFG_ONE_MEMBER" > "$T/outside/.release-pr.json"

# A config inside a DIFFERENT repository, with the same BASENAME as this one's root config —
# the shape an rc guard alone does not catch. `git -C <that dir> rev-parse --show-prefix`
# answers rc 0 there (it is a repository, just not this one), so the normalization composes a
# path that is root-relative to the WRONG repo and every blob read below applies it to THIS
# one: the run then answers, confidently and at rc 0, about a config the caller never named.
mkdir -p "$T/otherrepo"
g init -q "$T/otherrepo"
printf '%s\n' '{ "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+",
  "artifacts": ["OTHER-REPO-ONLY.md → {{version}}"] }' > "$T/otherrepo/.release-pr.json"
echo "0.1.0" > "$T/otherrepo/VERSION"
g -C "$T/otherrepo" add -A; g -C "$T/otherrepo" commit -qm "chore: a second repository's release config"

# two_dot_moved / merge_base_moved <base> <head> <path> — what each range says about the MOVED
# leg, computed from raw git rather than from the tool, so the fixture's discriminating power
# is established independently of the implementation being tested.
two_dot_moved() {
  local d; d="$(g -C "$R" diff --name-only "$1" "$2")"
  case $'\n'"$d"$'\n' in *$'\n'"$3"$'\n'*) echo true ;; *) echo false ;; esac
}
merge_base_moved() {
  local mb d; mb="$(g -C "$R" merge-base "$1" "$2")"; d="$(g -C "$R" diff --name-only "$mb" "$2")"
  case $'\n'"$d"$'\n' in *$'\n'"$3"$'\n'*) echo true ;; *) echo false ;; esac
}
ver_at() { g -C "$R" show "$1:VERSION" 2>/dev/null | tr -d '[:space:]'; }

echo "== precondition: the fixture is a throwaway repo, not this checkout =="
eq "fixture root is under the temp dir" "true" \
   "$(case "$(g -C "$R" rev-parse --show-toplevel)" in "$T"/*) echo true ;; *) echo false ;; esac)"

# ---------------------------------------------------------------------------
# The two clean shapes. They are also the CONTROLS for every defect case below: without
# them, "reports defect X" would be equally true of a tool that reports everything.
# ---------------------------------------------------------------------------
echo "== (i) a non-release PR (version unchanged) asserts nothing and exits 0 =="
run base-0.1.0 head-nonrelease
eq "rc 0"                              "0"    "$RC"
eq "…and says why it asserted nothing" "true" "$(has 'version unchanged (0.1.0)' "$OUT")"
eq "…and names no artifact"            "false" "$(has '::error::' "$OUT")"

echo "== (ii) a correct release PR passes every declared member and exits 0 =="
run base-0.1.0 head-good
eq "rc 0"                                   "0"    "$RC"
eq "VERSION passes"                         "true" "$(has 'OK — VERSION moved' "$OUT")"
eq "the [V] section member passes"          "true" "$(has 'OK — docs/CHANGELOG.md moved' "$OUT")"
eq "the prose-suffixed row member passes"   "true" "$(has 'OK — NOTES.md moved' "$OUT")"
eq "brace-set member a passes"              "true" "$(has 'OK — sboms/v0.2.0.a.json moved' "$OUT")"
eq "brace-set member b passes"              "true" "$(has 'OK — sboms/v0.2.0.b.json moved' "$OUT")"
# The count is what proves the brace set EXPANDED rather than being asserted as one literal
# path: four declared entries, five members.
eq "the summary counts 5 members from 4 entries" "true" \
   "$(has 'all 5 declared artifact member(s) moved and agree with 0.2.0' "$OUT")"
eq "no failure lines"                       "false" "$(has '::error::' "$OUT")"
eq "…and no baseline warning (the fork point carries the same config)" "false" \
   "$(has '::warning::' "$OUT")"

# ---------------------------------------------------------------------------
# PROVE IT CAN FAIL — one fixture per defect class, each seen to red.
# ---------------------------------------------------------------------------
echo "== (case 1 / iii-a) CONTROL: a declared member that did not move is REPORTED =="
run base-0.1.0 head-not-moved
eq "rc 1"                                    "1"    "$RC"
eq "the failure is an ::error:: annotation"  "true" "$(has '::error::release artifact not moved' "$OUT")"
eq "…and names the member path"              "true" "$(has "'NOTES.md' is absent from this PR's own changes" "$OUT")"
eq "…and names the original declared entry"  "true" "$(has 'declared as: NOTES.md § Recent releases row' "$OUT")"
eq "…while the moved siblings still pass (witness: the run got past member 1)" "true" \
   "$(has 'OK — VERSION moved' "$OUT")"
eq "the summary counts exactly one failure"  "true" "$(has '1 of 5 artifact member(s) failed' "$OUT")"

echo "== (iii-b) POSITIVE CONTROL: a CHANGELOG that moved without its ## [V] section =="
run base-0.1.0 head-no-section
eq "rc 1"                                   "1"    "$RC"
eq "the failure is the AGREES leg, not the moved leg" "true" \
   "$(has "::error::release artifact does not agree: 'docs/CHANGELOG.md'" "$OUT")"
eq "…and names the heading line it wanted"  "true" "$(has "has no line beginning '## [0.2.0]'" "$OUT")"
eq "…and the moved leg did NOT fire for it" "false" \
   "$(has "not moved: 'docs/CHANGELOG.md'" "$OUT")"
eq "exactly one member failed"              "true" "$(has '1 of 5 artifact member(s) failed' "$OUT")"

echo "== (iii-c) POSITIVE CONTROL: a DELETED member fails, though it IS in the diff =="
# The whole point of the exists-at-head leg: a deletion satisfies "moved". A moved-only guard
# passes this fixture, so the witness below (the moved leg staying silent) is load-bearing.
run base-0.1.0 head-deleted
eq "rc 1"                                    "1"    "$RC"
eq "witness: the deletion DOES satisfy the moved leg" "false" \
   "$(has "not moved: 'NOTES.md'" "$OUT")"
eq "…and the exists-at-head leg is what fails" "true" \
   "$(has "::error::release artifact missing at head: 'NOTES.md'" "$OUT")"
eq "exactly one member failed"               "true" "$(has '1 of 5 artifact member(s) failed' "$OUT")"

echo "== (iii-d) POSITIVE CONTROL: an unreadable version_file at the FORK POINT refuses (rc 2) =="
# It must NOT read as "version unchanged ⇒ not a release PR": that misclassification is a
# silent non-run of the entire gate, which is strictly worse than a loud refusal.
run pre-version head-good
eq "rc 2"                                        "2"    "$RC"
eq "the error names the file"                    "true" "$(has "cannot read 'VERSION' at" "$OUT")"
# The resolved merge base appears in none of the caller's inputs, so the message must say
# which END of the range it is, not just print a bare SHA.
eq "…and names WHICH end of the range it is"     "true" "$(has "the fork point of 'pre-version' and 'head-good'" "$OUT")"
eq "…and names the fetch-depth precondition"     "true" "$(has 'fetch-depth: 0' "$OUT")"
eq "…and did NOT classify it as a non-release PR" "false" "$(has 'version unchanged' "$OUT")"
eq "…and asserted no member"                     "false" "$(has 'artifact member(s) failed' "$OUT")"

echo "== an unreadable version_file at HEAD refuses the same way (both ends fail closed) =="
# A readable fork point, so this end fails on its own rather than being masked by the other.
run base-0.1.0 head-noversion
eq "rc 2"                                 "2"    "$RC"
eq "the error names the head end"         "true" "$(has "cannot read 'VERSION' at head 'head-noversion'" "$OUT")"

echo "== two refs with no common ancestor refuse — never a 'not a release PR' pass =="
run unrelated head-good
eq "rc 2"                                    "2"    "$RC"
eq "the error names both refs"               "true" "$(has "merge base of 'unrelated' and 'head-good'" "$OUT")"
eq "…and the fetch-depth precondition"       "true" "$(has 'fetch-depth: 0' "$OUT")"
eq "…and did NOT classify it as non-release" "false" "$(has 'version unchanged' "$OUT")"

echo "== (iii-e) EVERY failing member is reported, not just the first =="
# NOTES.md never moves AND the brace set's `b` member is never created: two independent
# failures, in two different legs, from two different declared entries.
run base-0.1.0 head-two-bad
eq "rc 1"                                     "1"    "$RC"
eq "failure 1 named (a whole entry that did not move)" "true" \
   "$(has "not moved: 'NOTES.md'" "$OUT")"
eq "failure 2 named (one member of a brace set)"       "true" \
   "$(has "not moved: 'sboms/v0.2.0.b.json'" "$OUT")"
eq "the sibling brace member still passes"    "true" "$(has 'OK — sboms/v0.2.0.a.json moved' "$OUT")"
eq "the summary counts BOTH"                  "true" "$(has '2 of 5 artifact member(s) failed' "$OUT")"

# ---------------------------------------------------------------------------
# THE VERDICT SURFACE IS READ FROM THE FORK POINT (card#6055).
# ---------------------------------------------------------------------------
echo "== (case 2) E1: head DELETES an artifacts entry while still updating the file =="
# PRE-FIX: rc 0, silently. Every remaining leg passes and NOTES.md itself was updated, so a
# flow-through implementation — one that folded the fork-point set into the member legs rather
# than giving it its own verdict — would ALSO pass this. That is why leg-independence is what
# the assertions below pin.
run base-0.1.0 head-e1
eq "rc 1"                                          "1"    "$RC"
eq "the failure names the narrowing, not a member leg" "true" \
   "$(has '::error::release artifact declaration NARROWED' "$OUT")"
eq "…and names the removed member"                 "true" "$(has "'NOTES.md' is declared at the fork point" "$OUT")"
eq "…and prints the remedy as a pasteable entry"   "true" "$(has 'adding "NOTES.md" to .retired_artifacts' "$OUT")"
eq "witness: the removed member's own legs would ALL have passed" "false" \
   "$(has "not moved: 'NOTES.md'" "$OUT")"
eq "witness: …and it is not reported missing either"             "false" \
   "$(has "missing at head: 'NOTES.md'" "$OUT")"
eq "the four remaining members still pass"         "true" "$(has 'OK — VERSION moved' "$OUT")"
eq "the summary counts the removal separately from member failures" "true" \
   "$(has '1 declared artifact(s) removed without acknowledgement' "$OUT")"
eq "…and no member leg failed"                     "false" "$(has 'artifact member(s) failed' "$OUT")"

echo "== (case 5) …the same removal, ACKNOWLEDGED in retired_artifacts, is rc 0 =="
run base-0.1.0 head-e1-retired
eq "rc 0"                                   "0"    "$RC"
eq "the retirement is logged"               "true" "$(has 'RETIRED: NOTES.md' "$OUT")"
eq "…and says it was not asserted"          "true" "$(has 'acknowledged in .retired_artifacts; not asserted' "$OUT")"
eq "…and nothing is reported as narrowed"   "false" "$(has 'NARROWED' "$OUT")"
eq "…and the remaining four members are asserted" "true" \
   "$(has 'all 4 declared artifact member(s) moved and agree with 0.2.0' "$OUT")"

echo "== (case 6) a member in BOTH artifacts and retired_artifacts is a config error =="
# A tombstone cannot be PRE-PLANTED against a still-declared member (nor left behind by a
# retire-then-re-add), because the removal would then already be acknowledged when it lands.
run base-0.1.0 head-e1-both
eq "rc 2"                             "2"    "$RC"
eq "…naming the member"               "true" "$(has "'NOTES.md' is declared in BOTH .artifacts and .retired_artifacts" "$OUT")"
eq "…and not as a narrowing"          "false" "$(has 'NARROWED' "$OUT")"

echo "== (case 7) the narrowing reds on a NON-RELEASE PR too (classification-independent) =="
# rev 8 specified rc 0 + a warning here. This rc-1 expectation IS the regression guard: a
# classification-gated severity is bought back by poisoning the version file's CONTENT, which
# costs no config edit at all (case 22).
run base-0.1.0 head-e1-nonrelease
eq "rc 1"                                   "1"    "$RC"
eq "…the narrowing is reported"             "true" "$(has 'NARROWED' "$OUT")"
eq "…while the PR is still classified as a non-release one" "true" \
   "$(has 'not a release PR, so no member was asserted' "$OUT")"
eq "…and no member leg ran"                 "false" "$(has 'OK — VERSION moved' "$OUT")"

echo "== (case 8) a WHOLESALE deletion of the artifacts key cannot opt the repo out =="
# PRE-FIX: rc 0, `no artifacts declared — nothing to assert`. The opt-out tests the UNION of
# both ends, so the fork point alone keeps the gate live.
run base-0.1.0 head-wholesale
eq "rc 1"                                   "1"    "$RC"
eq "…and does NOT report an opt-out"        "false" "$(has 'no artifacts declared' "$OUT")"
eq "every fork-point unit is reported"      "true" "$(has '5 declared artifact(s) removed without acknowledgement' "$OUT")"
eq "…including one member of the brace set" "true" "$(has "'sboms/v{{version}}.b.json' is declared at the fork point" "$OUT")"
eq "…and no vacuous all-clear line"         "false" "$(has 'declared artifact member(s) moved and agree' "$OUT")"
# CONTROL — `artifacts` empty at BOTH ends really is the opt-out.
run base-0.1.0 head-good --config cfg-empty-both.json
eq "control: empty at both ends → rc 0"     "0"    "$RC"
eq "control: …and reports the opt-out"      "true" "$(has 'no artifacts declared' "$OUT")"

echo "== widening is NOT a narrowing: a brace alternative added at head stays rc 0 =="
# The comparison unit is the EXPANDED member, not the entry string. Under a string-identity
# unit, adding an alternative changes the entry text, so the OLD string reads as removed and a
# pure widening reds — the defect this witness pins.
eq "witness: the fork point declares a 2-element brace set" "true" \
   "$(has 'sboms/v{{version}}.{a,b}.json' "$(g -C "$R" show base-0.1.0:.release-pr.json)")"
eq "witness: …and head declares a 3-element one"            "true" \
   "$(has 'sboms/v{{version}}.{a,b,c}.json' "$(g -C "$R" show head-wider:.release-pr.json)")"
run base-0.1.0 head-wider
eq "rc 0"                                 "0"    "$RC"
eq "…nothing reported as narrowed"        "false" "$(has 'NARROWED' "$OUT")"
eq "…and the new alternative is asserted" "true" "$(has 'all 6 declared artifact member(s)' "$OUT")"

echo "== (case 3) E2: head retargets the classification keys at a constant =="
# PRE-FIX: head's keys are read, both ends say 9.9.9, and the run exits 0 with `version
# unchanged` on a PR that IS a release and IS missing a member — a silent non-run of the whole
# gate. The retarget is IGNORED rather than refused, so this leg has no false-positive surface.
eq "witness: the retargeted file reads the SAME at both ends" "9.9.9" \
   "$(g -C "$R" show head-e2:CONST.txt | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
eq "witness: …and head really did retarget version_file" "true" \
   "$(has '"version_file": "CONST.txt"' "$(g -C "$R" show head-e2:.release-pr.json)")"
run base-0.1.0 head-e2
eq "rc 1"                                        "1"     "$RC"
eq "…and did NOT classify it as a non-release PR" "false" "$(has 'version unchanged' "$OUT")"
eq "…naming the member that did not move"         "true"  "$(has "not moved: 'NOTES.md'" "$OUT")"

echo "== (case 10) N1: head relocates the version file the fork point still names =="
run base-0.1.0 head-relocate
eq "rc 2"                                   "2"    "$RC"
eq "…naming the path that could not be read" "true" "$(has "cannot read 'VERSION' at head 'head-relocate'" "$OUT")"
eq "…and naming WHERE that path came from"   "true" "$(has 'version_file declared by .release-pr.json at the fork point' "$OUT")"
eq "…and saying relocation is a cause"       "true" "$(has 'head relocated the file the fork point still names' "$OUT")"
# CONTROL — a head that does not relocate takes the same path and passes.
run base-0.1.0 head-good
eq "control: no relocation → rc 0"          "0"    "$RC"

echo "== (case 22) E5: poisoning the version file's CONTENT silently skips the member legs =="
# Reproduced and DOCUMENTED, not fixed: classification is by version VALUE and head owns the
# file's content, which is a property of the tool's founding design rather than of this change.
# What this card closes is the COMPOUNDING — see the second half.
eq "witness: head's version file really carries 0.2.0 as well" "true" \
   "$(has '0.2.0' "$(g -C "$R" show head-e5:VERSION)")"
run base-0.1.0 head-e5
eq "documented today: rc 0"                 "0"    "$RC"
eq "…reading as 'not a release PR'"         "true" "$(has 'version unchanged (0.1.0)' "$OUT")"
eq "…so the missing member is never named"  "false" "$(has "not moved: 'NOTES.md'" "$OUT")"
# CONTROL — the same PR unpoisoned reds, which is what makes the non-run above a real skip
# rather than a PR with nothing wrong with it.
run base-0.1.0 head-not-moved
eq "control: unpoisoned, the same PR reds"  "1"    "$RC"
eq "control: …naming the member"            "true" "$(has "not moved: 'NOTES.md'" "$OUT")"
# …and the compounding IS closed: E5 buys no leniency on the narrowing check.
run base-0.1.0 head-e5-lost
eq "E1 + E5 still reds"                     "1"    "$RC"
eq "…on the narrowing"                      "true" "$(has 'NARROWED' "$OUT")"
eq "…even though the PR reads as a non-release one" "true" \
   "$(has 'not a release PR, so no member was asserted' "$OUT")"

echo "== (case 20) retired_artifacts of a non-array type is a config error =="
# Unguarded, `.retired_artifacts[]` on a string is a jq runtime error swallowed by the `while
# read` consuming it: the tombstone/retirement comparison would run against an EMPTY set with
# a raw traceback as the only sign that the guard was off.
run base-0.1.0 head-retired-bad
eq "rc 2"                              "2"     "$RC"
eq "…naming the type it found"         "true"  "$(has ".retired_artifacts of type 'string'" "$OUT")"
eq "…with no raw jq traceback"         "false" "$(has 'Cannot iterate' "$OUT")"
# CONTROL — the array-typed spelling of the same key is accepted (case 5, rc 0).
run base-0.1.0 head-e1-retired
eq "control: array-typed → rc 0"       "0"     "$RC"

echo "== (case 25) a literal comparison sentinel in a declared entry is refused =="
run base-0.1.0 head-sentinel --config cfg-sentinel.json
eq "rc 2"                                   "2"    "$RC"
eq "…naming the reserved token"             "true" "$(has "contains the reserved comparison token '@@ABTK_VERSION@@'" "$OUT")"
eq "…and pointing at the spelling to use"   "true" "$(has "write '{{version}}'" "$OUT")"
# CONTROL — the same entry spelled with {{version}} is an ordinary declaration.
run base-0.1.0 head-sentinel --config cfg-sentinel-ok.json
eq "control: {{version}} → normal verdict"  "0"    "$RC"
eq "control: …and the member is asserted"   "true" "$(has 'OK — sboms/v0.2.0.a.json moved' "$OUT")"

# ---------------------------------------------------------------------------
# NO USABLE FORK-POINT CONFIG ⇒ WARN + FALL BACK, never a refusal. Those keys can only enter
# the fork point through a merged release, so an rc 2 here is an rc NO PR CAN FIX.
# ---------------------------------------------------------------------------
echo "== (case 9) N3: no config at the fork point warns and falls back =="
eq "witness: the fork point really has no config" "false" \
   "$(g -C "$R" cat-file -e pre-config:.release-pr.json 2>/dev/null && echo true || echo false)"
eq "witness: …but it does have the version file"  "0.1.0" "$(ver_at pre-config)"
run pre-config head-e1
eq "rc 0 (no baseline ⇒ nothing can be reported as removed)" "0" "$RC"
eq "…and says so on a ::warning:: line"     "true" "$(has '::warning::' "$OUT")"
eq "…naming the fallback"                   "true" "$(has "Falling back to head's version_file/version_regex" "$OUT")"
eq "…and saying the baseline is empty"      "true" "$(has 'comparing the declared set against an EMPTY baseline' "$OUT")"
eq "…and asserting head's set normally"     "true" "$(has 'all 4 declared artifact member(s)' "$OUT")"
# CONTROL — the SAME head against a fork point that DOES carry the config reds on the removal,
# which is what proves the warning above comes from the config's ABSENCE and not from the head.
run base-0.1.0 head-e1
eq "control: with a fork-point config → rc 1" "1"    "$RC"
eq "control: …on the narrowing"               "true" "$(has 'NARROWED' "$OUT")"

echo "== (case 17) an UNPARSEABLE fork-point config warns and falls back, never rc 2 =="
run base-0.1.0 head-fixcfg --config cfg-brokenbase.json
eq "rc 0"                                  "0"    "$RC"
eq "…warning that the fork-point copy is unusable" "true" \
   "$(has 'no usable cfg-brokenbase.json at the fork point' "$OUT")"
eq "…naming the reason"                    "true" "$(has 'it is not valid JSON there' "$OUT")"
eq "…and the verdict still runs"           "true" "$(has 'all 1 declared artifact member(s)' "$OUT")"
# CONTROL — the two ends are distinct: an unparseable config at HEAD is still rc 2.
run base-0.1.0 head-good --config cfg-brokenbase.json
eq "control: unparseable at HEAD → rc 2"   "2"    "$RC"
eq "control: …named as invalid JSON"       "true" "$(has 'is not valid JSON' "$OUT")"

echo "== (case 23) a fork-point config that LACKS the classification keys warns and falls back =="
# Left falling through, this was an rc 2 no PR could fix: the keys can only reach the fork
# point through a merged release, which the gate would be redding.
run base-0.1.0 head-fixcfg --config cfg-keyless.json
eq "rc 0"                                  "0"    "$RC"
eq "…warning about the missing keys"       "true" \
   "$(has 'declares no version_file/version_regex' "$OUT")"
eq "…and naming head as the fallback"      "true" "$(has "falling back to head's" "$OUT")"
eq "…and the verdict still runs"           "true" "$(has 'all 1 declared artifact member(s)' "$OUT")"
# CONTROL — head lacking them too is still a config error, so the two ends stay distinct.
run base-0.1.0 head-good --config cfg-keyless.json
eq "control: key-less at HEAD too → rc 2"  "2"    "$RC"
eq "control: …naming what is missing"      "true" "$(has 'no version_file' "$OUT")"
eq "control: …and naming the BLOB it read, not a bare path" "true" "$(has 'cfg-keyless.json at head' "$OUT")"

echo "== (case 27) an unusable ENTRY at the fork point warns and is EXCLUDED, never rc 2 =="
# The config-level rule applied per entry. Every one of these four shapes is rc 2 when it is
# read from HEAD (see the head-side controls below), and each is an rc NO PR CAN CLEAR when it
# is read from the fork point: the fork point is a merged commit, the only repair for a
# malformed entry is to DELETE it, and the run carrying that deletion is the run that would red
# — blaming the very entry the PR removes. So the PR that repairs them must go green.
FORK_SHA="$(g -C "$R" rev-parse base-0.1.0)"
eq "witness: the fork point declares all four unusable shapes" "true" \
   "$(case "$(g -C "$R" show base-0.1.0:cfg-badentry.json)" in *'   docs/CHANGELOG.md'*'{}.json'*'@@ABTK_VERSION@@'*'""'*) echo true ;; *) echo false ;; esac)"
eq "witness: …and head repairs them by deleting them, keeping both good entries" "true" \
   "$(case "$(g -C "$R" show head-good:cfg-badentry.json)" in *'{}'*|*'@@ABTK_'*) echo false ;; *'VERSION → {{version}}'*'NOTES.md § Recent releases row'*) echo true ;; *) echo false ;; esac)"
run base-0.1.0 head-good --config cfg-badentry.json
eq "the repair PR is NOT refused"                 "0"    "$RC"
eq "…the leading-whitespace entry is warned about" "true" \
   "$(has "::warning::release-artifacts-check: artifact entry has no leading path token: '   docs/CHANGELOG.md → [{{version}}] section'" "$OUT")"
eq "…the empty brace set is warned about"          "true" \
   "$(has "::warning::release-artifacts-check: artifact path 'sboms/v@@ABTK_VERSION@@{}.json' expands to no member (an empty brace set?) — declared as: sboms/v{{version}}{}.json" "$OUT")"
eq "…the reserved sentinel is warned about"        "true" \
   "$(has "::warning::release-artifacts-check: artifact entry contains the reserved comparison token '@@ABTK_VERSION@@'" "$OUT")"
eq "…the EMPTY entry is warned about too"          "true" \
   "$(has "::warning::release-artifacts-check: artifact entry has no leading path token: ''" "$OUT")"
eq "…and each warning names WHICH ref the entry came from" "true" \
   "$(has "That entry is declared at the fork point ($FORK_SHA)" "$OUT")"
eq "…saying the entry is excluded rather than refused"     "true" \
   "$(has 'EXCLUDED from the baseline rather than refused' "$OUT")"
# EXCLUDED FROM THE COMPARISON, not merely tolerated: all four are absent from head, so a
# baseline that still carried them would report four narrowings.
eq "…and nothing is reported as narrowed"          "false" "$(has 'NARROWED' "$OUT")"
eq "…while the two well-formed entries ARE asserted" "true" \
   "$(has 'all 2 declared artifact member(s) moved and agree with 0.2.0' "$OUT")"

# The same baseline against a head that ALSO drops a GOOD entry: the exclusion must be
# per-entry, so exactly ONE narrowing is reported — not five, and not zero.
run base-0.1.0 head-good --config cfg-badentry-narrow.json
eq "a good entry dropped alongside them still reds" "1"   "$RC"
eq "…naming that entry"                             "true" "$(has "'NOTES.md' is declared at the fork point" "$OUT")"
eq "…and counting the unusable four as ZERO of it"  "true" \
   "$(has '1 declared artifact(s) removed without acknowledgement' "$OUT")"
eq "…with the same four warnings still printed"     "true" \
   "$(has "::warning::release-artifacts-check: artifact entry has no leading path token: ''" "$OUT")"

# HEAD-SIDE CONTROLS — the same four shapes, declared at head, keep today's rc 2. One class,
# one disposition per source; these are what make the warn above a SOURCE decision rather than
# a weakening of the boundary check.
for c in leading-space.json empty-brace.json empty-entry.json; do
  run base-0.1.0 head-good --config "$c"
  eq "control: $c at HEAD is still rc 2"            "2"     "$RC"
  eq "control: …and not a warning"                  "false" "$(has '::warning::release-artifacts-check: artifact' "$OUT")"
done
run base-0.1.0 head-sentinel --config cfg-sentinel.json
eq "control: a sentinel entry at HEAD is still rc 2" "2"    "$RC"

echo "== (case 28) a config that PARSES AND THEN ERRORS is a JSON refusal, not a jq traceback =="
# `{…} trailing junk`: jq prints the leading value and THEN dies rc 5, so a parse test that
# reads only the OUTPUT sees a non-empty string and passes it, the type guard reads `object`
# and passes it too, and the first real `.key` read dies on the same input — surfacing as the
# script's own rc 5 with a raw jq parse error, where the header promises rc 2.
eq "witness: the blob really is a value followed by junk" "true" \
   "$(has 'and then some trailing junk' "$(g -C "$R" show head-good:cfg-trailingjunk.json)")"
eq "witness: …and jq PRINTS a value from it while failing" "true" \
   "$(rc=0; out="$(g -C "$R" show head-good:cfg-trailingjunk.json | jq -c . 2>/dev/null)" || rc=$?; [ -n "$out" ] && [ "$rc" -ne 0 ] && echo true || echo false)"
run base-0.1.0 head-good --config cfg-trailingjunk.json
eq "rc 2"                                    "2"     "$RC"
eq "…named as invalid JSON"                  "true"  "$(has 'is not valid JSON' "$OUT")"
eq "…with no raw jq diagnostic leaking"      "false" "$(has 'jq:' "$OUT")"
eq "…and no undocumented rc behind it"       "false" "$(has 'parse error' "$OUT")"

# THE FORK SIDE — the same blob at the fork point was a SECOND rc no PR could fix, since the
# `.artifacts` read that died was reached before any classification.
eq "witness: the fork-point copy is the junk blob" "true" \
   "$(has 'and then some trailing junk' "$(g -C "$R" show base-0.1.0:cfg-trailingjunk-base.json)")"
eq "witness: …while head's copy is repaired"       "false" \
   "$(has 'and then some trailing junk' "$(g -C "$R" show head-good:cfg-trailingjunk-base.json)")"
run base-0.1.0 head-good --config cfg-trailingjunk-base.json
eq "rc 0"                                    "0"     "$RC"
eq "…warning that the fork-point copy is unusable" "true" \
   "$(has 'no usable cfg-trailingjunk-base.json at the fork point' "$OUT")"
eq "…naming it as invalid JSON there"        "true"  "$(has 'it is not valid JSON there' "$OUT")"
eq "…and the verdict still runs"             "true"  "$(has 'all 1 declared artifact member(s)' "$OUT")"
eq "…with no raw jq diagnostic leaking"      "false" "$(has 'jq:' "$OUT")"

echo "== (case 16) an unresolvable merge base refuses even when artifacts is absent =="
# PRE-FIX: the opt-out was taken first, so this exited 0 without ever resolving a fork point.
# The merge base now decides the baseline and the classification keys, so it is resolved first
# and fails closed.
run unrelated head-good --config no-artifacts.json
eq "rc 2"                                  "2"    "$RC"
eq "…on the merge base"                    "true" "$(has "merge base of 'unrelated' and 'head-good'" "$OUT")"
# CONTROL — a resolvable merge base with the same config is the opt-out, rc 0.
run base-0.1.0 head-good --config no-artifacts.json
eq "control: resolvable → rc 0"            "0"    "$RC"
eq "control: …and says so"                 "true" "$(has 'no artifacts declared — nothing to assert' "$OUT")"

# ---------------------------------------------------------------------------
# §C — a declared member must be a REGULAR FILE.
# ---------------------------------------------------------------------------
echo "== (case 11) a SYMLINK member is refused, not read =="
# PRE-FIX rc 0: `git show <ref>:<symlink>` yields the TARGET PATH STRING, and that string
# carries the version here, so the weak content-mention arm passed on a file never read.
eq "witness: git show yields the symlink's TARGET, not a file's contents" "notes-0.2.0.md" \
   "$(g -C "$R" show head-symlink:LINK.md)"
eq "witness: …and that target string carries the version" "true" \
   "$(has '0.2.0' "$(g -C "$R" show head-symlink:LINK.md)")"
run base-0.1.0 head-symlink --config cfg-symlink.json
eq "rc 1"                              "1"    "$RC"
eq "…diagnosed as a symlink"           "true" "$(has "'LINK.md' at head-symlink is a symlink" "$OUT")"
eq "…and not as a content disagreement" "false" "$(has "does not agree: 'LINK.md'" "$OUT")"

echo "== (case 12) a DIRECTORY member — arm A, the 0 → 1 discriminator =="
# The conjunction that makes today's verdict rc 0: a blob existed at the member path at the
# fork point, head REPLACED it with a directory (so the deleted blob emits a diff row equal to
# the member path, satisfying MOVED), and the tree listing carries the version (satisfying the
# content-mention arm). Any other directory shape already reds on MOVED — see arm B.
eq "witness: the member was a BLOB at the fork point" "blob" \
   "$(g -C "$R" cat-file -t base-0.1.0:bundle)"
eq "witness: …a TREE at head"                         "tree" \
   "$(g -C "$R" cat-file -t head-dir-a:bundle)"
eq "witness: …the diff carries a row EQUAL to the member path (so MOVED passes)" "true" \
   "$(merge_base_moved base-0.1.0 head-dir-a bundle)"
eq "witness: …and the tree listing carries the version (so the weak arm passes)" "true" \
   "$(has '0.2.0' "$(g -C "$R" show head-dir-a:bundle)")"
run base-0.1.0 head-dir-a --config cfg-dir.json
eq "rc 1"                                "1"     "$RC"
eq "…diagnosed as a directory"           "true"  "$(has "'bundle' at head-dir-a is a directory" "$OUT")"
eq "…and the moved leg did NOT fire"     "false" "$(has "not moved: 'bundle'" "$OUT")"

echo "== (case 12-b) …arm B, a freshly added directory: 1 → 1, so the DIAGNOSIS is the control =="
eq "witness: no diff row equals the member path, so MOVED already reds today" "false" \
   "$(merge_base_moved base-0.1.0 head-dir-b fresh)"
run base-0.1.0 head-dir-b --config cfg-dir-b.json
eq "rc 1 (unchanged from today)"         "1"    "$RC"
eq "…but now diagnosed as a directory"   "true" "$(has "'fresh' at head-dir-b is a directory" "$OUT")"
eq "…in addition to the moved leg"       "true" "$(has "not moved: 'fresh'" "$OUT")"

echo "== (case 13) a GITLINK whose commit is in this store is refused =="
# PRE-FIX rc 0: `cat-file -e` returns 0 and `git show` yields the COMMIT LOG, whose subject
# here carries the version — a content assertion satisfied by a commit message.
eq "witness: cat-file -e says the gitlink EXISTS" "true" \
   "$(g -C "$R" cat-file -e head-gitlink:gl 2>/dev/null && echo true || echo false)"
eq "witness: …and git show yields a commit log carrying the version" "true" \
   "$(has 'gitlink target for 0.2.0' "$(g -C "$R" show head-gitlink:gl)")"
run base-0.1.0 head-gitlink --config cfg-gitlink.json
eq "rc 1"                             "1"    "$RC"
eq "…diagnosed as a gitlink"          "true" "$(has "'gl' at head-gitlink is a gitlink (submodule entry)" "$OUT")"
eq "…not as 'missing at head'"        "false" "$(has "missing at head: 'gl'" "$OUT")"

echo "== (case 14) a member path with glob metacharacters is asserted LITERALLY =="
eq "witness: a sibling a glob would have matched exists at head" "true" \
   "$(has 'docs2/goneX.md' "$(g -C "$R" ls-tree --full-tree --name-only head-glob -- docs2/)")"
eq "witness: …while the declared literal path does NOT" "false" \
   "$(g -C "$R" cat-file -e 'head-glob:docs2/gone?.md' 2>/dev/null && echo true || echo false)"
run base-0.1.0 head-glob --config cfg-glob.json
eq "rc 1"                                       "1"    "$RC"
eq "the literal star path passes"               "true" "$(has 'OK — docs2/star*.md moved' "$OUT")"
eq "the absent literal is MISSING, not consulted through its sibling" "true" \
   "$(has "missing at head: 'docs2/gone?.md'" "$OUT")"
eq "…and the moved leg did not match the sibling either" "true" \
   "$(has "not moved: 'docs2/gone?.md'" "$OUT")"
eq "…and no content disagreement was reported (which is what a glob read would have said)" "false" \
   "$(has "does not agree: 'docs2/gone?.md'" "$OUT")"

# ---------------------------------------------------------------------------
# Where the config lives, and where the tool is invoked from.
# ---------------------------------------------------------------------------
echo "== (case 21) a config committed at head but ABSENT from the checkout proceeds =="
# PRE-FIX: rc 2 with the false diagnosis "no config in this repo". Every read is a blob read,
# and the checkout is not necessarily head (on a `pull_request` event it is the merge ref).
eq "witness: the tree really does not carry it" "false" \
   "$([ -f "$R/cfg-committed-only.json" ] && echo true || echo false)"
eq "witness: …but head does"                    "true" \
   "$(g -C "$R" cat-file -e head-cfg-committed-only:cfg-committed-only.json 2>/dev/null && echo true || echo false)"
run base-0.1.0 head-cfg-committed-only --config cfg-committed-only.json
eq "rc 0"                                       "0"    "$RC"
eq "…and never claims the repo has no config"   "false" "$(has 'no cfg-committed-only.json in this repo' "$OUT")"
eq "…and the verdict runs"                      "true" "$(has 'all 1 declared artifact member(s)' "$OUT")"

echo "== (case 24) a config in the checkout but NOT COMMITTED at head is refused =="
# The complement of case 21, on its own branch: sharing a fixture would let either mask the
# other. This is a rc CHANGE (0 → 2) — the tool used to read the tree copy and answer from it.
eq "witness: the tree carries it"               "true" \
   "$([ -f "$R/cfg-tree-only.json" ] && echo true || echo false)"
eq "witness: …and head does NOT"                "false" \
   "$(g -C "$R" cat-file -e head-cfg-tree-only:cfg-tree-only.json 2>/dev/null && echo true || echo false)"
run base-0.1.0 head-cfg-tree-only --config cfg-tree-only.json
eq "rc 2"                                       "2"    "$RC"
eq "…naming the commit-vs-tree rule"            "true" \
   "$(has 'is not committed at head' "$OUT")"
eq "…and saying which one is read"              "true" \
   "$(has 'reads the config from the COMMIT, not the working tree' "$OUT")"
# CONTROL — the SAME config path, committed on the other branch, gives a normal verdict.
run base-0.1.0 head-cfg-committed-only --config cfg-tree-only.json
eq "control: committed → normal verdict"        "0"    "$RC"

echo "== (case 19) a --config outside the repository is refused by name =="
# MUTATION CONTROL (recorded, not automatable here): with the rc guard dropped from the
# `rev-parse --show-prefix` capture, that command exits 128 with EMPTY stdout on a directory
# outside any repo, so the normalization composes "" + basename and the run silently reads
# THIS repo's own root config as the baseline for a config the caller pointed elsewhere.
eq "witness: the out-of-repo config really exists" "true" \
   "$([ -f "$T/outside/.release-pr.json" ] && echo true || echo false)"
run base-0.1.0 head-good --config "$T/outside/.release-pr.json"
eq "rc 2"                                       "2"    "$RC"
eq "…naming the config"                         "true" "$(has "--config '$T/outside/.release-pr.json'" "$OUT")"
eq "…and naming the directory as the reason"    "true" "$(has "does not resolve inside a git repository" "$OUT")"

echo "== (case 26) a --config inside a DIFFERENT repository is refused, not silently re-rooted =="
# The rc guard above answers "is this a repository at all", which is the wrong question one step
# out: a directory inside ANOTHER repository answers `--show-prefix` at rc 0, and the prefix it
# returns is root-relative to THAT repo. Applied to this repo's refs it names this repo's own
# root config — so the tool would report a clean verdict about a file the caller never pointed
# at. Fail-closed here is not a nicety: a silent answer about the wrong config is exactly the
# defect class this whole card exists to close, one layer out.
eq "witness: the two directories really are different repositories" "true" \
   "$(case "$(g -C "$T/otherrepo" rev-parse --show-toplevel)" in "$(g -C "$R" rev-parse --show-toplevel)") echo false ;; *) echo true ;; esac)"
eq "witness: …the foreign config declares a set THIS repo has never heard of" "true" \
   "$(has 'OTHER-REPO-ONLY.md' "$(cat "$T/otherrepo/.release-pr.json")")"
eq "witness: …and this repo carries a root config of the same basename to be mistaken for it" "true" \
   "$(g -C "$R" cat-file -e head-good:.release-pr.json 2>/dev/null && echo true || echo false)"
run base-0.1.0 head-good --config "$T/otherrepo/.release-pr.json"
eq "rc 2"                                       "2"    "$RC"
eq "…naming the config the caller gave"         "true" "$(has "--config '$T/otherrepo/.release-pr.json'" "$OUT")"
eq "…and saying it is a DIFFERENT repository"   "true" "$(has 'resolves inside a DIFFERENT repository' "$OUT")"
eq "…naming both toplevels"                     "true" \
   "$(has "('$(g -C "$T/otherrepo" rev-parse --show-toplevel)') from the one whose refs are being compared ('$(g -C "$R" rev-parse --show-toplevel)')" "$OUT")"
eq "…and never answers about THIS repo's own config" "false" \
   "$(has 'declared artifact member(s) moved and agree' "$OUT")"
eq "…nor names a member of it"                  "false" "$(has 'OK — VERSION moved' "$OUT")"

echo "== (case 18) invoked from a SUBDIRECTORY, the verdict is identical to the root one =="
# `--config` is CWD-relative; every blob read is root-relative.
#
# THE `../` SPELLING CANNOT DISCRIMINATE, and it is worth saying why rather than leaving a
# control that looks like one: git resolves a `<rev>:path` whose path begins `./` or `../`
# relative to the CWD, so `HEAD:../.release-pr.json` read from `sub/` lands on the SAME blob
# as the root-relative `HEAD:.release-pr.json`. An unnormalized implementation passes this leg
# by accident. It is kept because verdict-identity across invocation directories is a real
# property, and it is followed by the leg that actually discriminates.
run base-0.1.0 head-e1
eq "root invocation: rc 1"                      "1"    "$RC"
ROOT_RC="$RC"
run_in sub base-0.1.0 head-e1 --config ../.release-pr.json
eq "subdirectory invocation: the same rc"       "$ROOT_RC" "$RC"
eq "…and the same narrowing verdict"            "true" "$(has 'NARROWED' "$OUT")"
eq "…with no no-baseline warning"               "false" "$(has 'no usable' "$OUT")"

# THE DISCRIMINATING LEG — a config that lives IN the subdirectory, named without any `./`
# prefix. Only the root-relative spelling `sub/sub-cfg.json` reaches it from a blob read;
# unnormalized, `HEAD:sub-cfg.json` names a path at the repo ROOT that does not exist, and the
# run dies rc 2 claiming the config is not committed at head.
eq "witness: the config is at sub/sub-cfg.json in BOTH ends" "true" \
   "$(g -C "$R" cat-file -e base-0.1.0:sub/sub-cfg.json 2>/dev/null && g -C "$R" cat-file -e head-good:sub/sub-cfg.json 2>/dev/null && echo true || echo false)"
eq "witness: …and nothing of that name exists at the repo root" "false" \
   "$(g -C "$R" cat-file -e head-good:sub-cfg.json 2>/dev/null && echo true || echo false)"
run_in sub base-0.1.0 head-good --config sub-cfg.json
eq "rc 0"                                       "0"     "$RC"
eq "…the member is asserted"                    "true"  "$(has 'all 1 declared artifact member(s)' "$OUT")"
eq "…and the fork-point copy WAS found (no no-baseline warning)" "false" \
   "$(has 'no usable' "$OUT")"

echo "== (case 15) the member mode read is root-relative from a subdirectory too =="
# A plain `ls-tree` pathspec is CWD-relative and returns EMPTY AT RC 0 from a subdirectory — a
# silent no-row, which the mode read would translate into "every member is missing at head".
# The MODE field is what the tool consumes, so the witness reads that field rather than the
# printed path (which git C-quotes for a non-ASCII name under the default core.quotePath —
# irrelevant here, and the reason rev 7's `core.quotePath` control for this leg could not
# fail and is not reproduced).
_subdir_mode() { local row; row="$( (cd "$R/sub" && g ls-tree "$@" -- "$UPATH") )"; printf '%s' "${row%% *}"; }
eq "witness: without --full-tree, a subdirectory read finds NOTHING" "" \
   "$(_subdir_mode head-utf8)"
eq "witness: …while --full-tree returns the member's blob mode"      "100644" \
   "$(_subdir_mode --full-tree head-utf8)"
run_in sub base-0.1.0 head-utf8 --config ../utf8.json
eq "rc 0"                                       "0"     "$RC"
eq "…and no member reads as missing at head"    "false" "$(has 'missing at head' "$OUT")"
eq "…and both members are asserted"             "true"  "$(has 'all 2 declared artifact member(s)' "$OUT")"

# ---------------------------------------------------------------------------
# THE RANGE IS THE PR'S OWN CHANGES — merge-base(base, head)..head, never base's tip.
# Both legs below are RED under a base-tip (two-dot) range and GREEN against the merge base,
# and the raw-git facts that make them differ are asserted FIRST — otherwise "the tool says
# rc 1" would be equally true of a tool that had never been fixed.
# ---------------------------------------------------------------------------
echo "== base drift after the fork must not satisfy the MOVED leg (two-dot defect) =="
# The fixture's discriminating power, established from raw git, independent of the tool:
eq "witness: a base-tip range WOULD have called NOTES.md moved" "true" \
   "$(two_dot_moved drift-base drift-head NOTES.md)"
eq "…while the PR's own changes do NOT contain it"              "false" \
   "$(merge_base_moved drift-base drift-head NOTES.md)"
# …and the member is otherwise fully satisfiable, which is what makes the two-dot pass SILENT
# rather than merely wrong on one leg: it exists at head and its content carries the version.
eq "witness: NOTES.md at head carries 0.2.0 (so AGREES would have passed too)" "true" \
   "$(has 'v0.2.0' "$(g -C "$R" show drift-head:NOTES.md)")"

run drift-base drift-head
eq "the tool FAILS on the unmoved member"        "1"    "$RC"
eq "…naming it"                                  "true" "$(has "not moved: 'NOTES.md'" "$OUT")"
eq "…and describing the range as the PR's own changes" "true" \
   "$(has "this PR's own changes (drift-base...drift-head)" "$OUT")"
eq "…while the members the PR DID move still pass" "true" \
   "$(has 'OK — docs/CHANGELOG.md moved' "$OUT")"
# CONTROL — the same head against the fork point itself. Identical verdict, which is the
# point: the merge-base resolution NORMALIZES base drift away rather than reacting to it.
run drift-fork drift-head
eq "control: against the fork point directly, the same verdict" "1"    "$RC"
eq "control: …and the same member"                              "true" "$(has "not moved: 'NOTES.md'" "$OUT")"

echo "== a version bump landing on BASE after the fork must not misclassify the PR =="
# The worst of the two shapes: a base-tip read makes a real release PR look like a non-release
# one, so the gate exits 0 and asserts NOTHING while a member is genuinely missing.
eq "witness: base's TIP and head carry the SAME version (two-dot ⇒ 'unchanged')" "0.2.0" \
   "$(ver_at bump-base)"
eq "witness: …and head does too"                                   "0.2.0" "$(ver_at head-not-moved)"
eq "witness: …while the FORK POINT carries the older one"          "0.1.0" \
   "$(ver_at "$(g -C "$R" merge-base bump-base head-not-moved)")"

run bump-base head-not-moved
eq "the tool classifies it as a release PR and FAILS"  "1"     "$RC"
eq "…rather than exiting 0 as 'version unchanged'"     "false" "$(has 'version unchanged' "$OUT")"
eq "…naming the missing member"                        "true"  "$(has "not moved: 'NOTES.md'" "$OUT")"
eq "…and counting the full declared set"               "true"  "$(has 'of 5 artifact member(s) failed' "$OUT")"

# ---------------------------------------------------------------------------
# THE AGREES ARMS. Which arm a member took is REPORTED, because the strong arm is selected by
# a magic substring in free prose: a prose edit downgrades the member to the weak
# content-mention arm, and before the arm was named that downgrade was byte-identical to a
# strong pass in the CI log. Both anchors of the strong arm are witnessed here too — nothing
# asserted either, so a mutation dropping the left anchor or unescaping the version stayed
# green across the whole suite.
# ---------------------------------------------------------------------------
echo "== the OK line NAMES the arm each member's agreement was decided by =="
run base-0.1.0 head-good
eq "the heading-line arm is named"      "true" "$(has "OK — docs/CHANGELOG.md moved, exists at head-good, agrees with 0.2.0 via '## [0.2.0]' heading line" "$OUT")"
eq "the version-bearing-path arm is named" "true" "$(has 'OK — sboms/v0.2.0.a.json moved, exists at head-good, agrees with 0.2.0 via version-bearing path' "$OUT")"
eq "the content-mention arm is named"   "true" "$(has 'OK — NOTES.md moved, exists at head-good, agrees with 0.2.0 via content mention' "$OUT")"

echo "== (case 4) E3: an unrecognized selector DOWNGRADES to the weak arm — and now says so =="
# Open BY DECISION: enforcing the fork-point entry's prose would close it, but attacker- and
# legitimate-weakening are the same observable, and the fork point is the previous release —
# so the corrected prose could never land. This case asserts only that card#6055 does not
# change the shipped verdict.
# The fixture mentions 0.2.0 only in inline prose, so the strong arm fails and the weak one
# passes. That is what makes the downgrade observable rather than a difference of nothing.
run base-0.1.0 head-inline-mention --config strong-section.json
eq "the CORRECT selector still reds on a missing heading" "1"    "$RC"
eq "…naming the heading line"                             "true" "$(has "has no line beginning '## [0.2.0]'" "$OUT")"

run base-0.1.0 head-inline-mention --config strong-entry.json
eq "the typo'd selector passes (the downgrade is real)"   "0"    "$RC"
eq "…but the OK line names the WEAK arm, so it is legible" "true" \
   "$(has 'agrees with 0.2.0 via content mention' "$OUT")"
eq "…and does NOT claim the heading-line arm"             "false" "$(has 'heading line' "$OUT")"

echo "== the selector is case-insensitive =="
run base-0.1.0 head-inline-mention --config strong-upper.json
eq "an upper-case selector still takes the STRONG arm" "1"    "$RC"
eq "…reporting the missing heading"                    "true" "$(has "has no line beginning '## [0.2.0]'" "$OUT")"

echo "== the strong arm's LEFT anchor: a mid-line mention is not a heading line =="
# Witness first, from raw content: the text the weak arm sees DOES contain the needle, so the
# strong arm's refusal is the anchor working — not the string being absent.
eq "witness: the file DOES contain '## [0.2.0]' somewhere" "true" \
   "$(has '## [0.2.0]' "$(g -C "$R" show head-inline-mention:docs/CHANGELOG.md)")"
eq "witness: …but never at the start of a line"            "false" \
   "$(has "$(printf '\n## [0.2.0]')" "$(g -C "$R" show head-inline-mention:docs/CHANGELOG.md)")"
run base-0.1.0 head-inline-mention --config strong-section.json
eq "the tool refuses the mid-line mention" "1" "$RC"

echo "== the strong arm's RIGHT anchor: the version is a FIXED string, not a regex =="
# `0.2.0` as an unescaped ERE matches `0x2x0`. The heading here is `## [0x2x0]`.
eq "witness: the heading is a metachar look-alike, at a line start" "true" \
   "$(has "$(printf '\n## [0x2x0]')" "$(g -C "$R" show head-metachar-heading:docs/CHANGELOG.md)")"
run base-0.1.0 head-metachar-heading --config strong-section.json
eq "the tool refuses the look-alike heading" "1"    "$RC"
eq "…naming the heading it wanted"           "true" "$(has "has no line beginning '## [0.2.0]'" "$OUT")"

echo "== a NON-ASCII member path that moved is not reported as 'not moved' =="
# Default core.quotePath C-quotes such a path in the diff, matching no declared member.
eq "witness: git's DEFAULT diff output C-quotes the path" "true" \
   "$(has '\303\251' "$(g -C "$R" -c core.quotePath=true diff --name-only base-0.1.0 head-utf8)")"
eq "witness: …and quotePath=false emits it verbatim"      "true" \
   "$(has "$UPATH" "$(g -C "$R" -c core.quotePath=false diff --name-only base-0.1.0 head-utf8)")"
run base-0.1.0 head-utf8 --config utf8.json
eq "the tool passes the non-ASCII member"  "0"    "$RC"
eq "…and never claims it did not move"     "false" "$(has 'not moved' "$OUT")"

# ---------------------------------------------------------------------------
# Config / usage surface.
# ---------------------------------------------------------------------------
echo "== a config with no artifacts array asserts nothing and exits 0 =="
# Checked BEFORE the version legs: a repo that never opted in must not be refused by a
# fail-closed version read it has no reason to satisfy.
run base-0.1.0 head-good --config no-artifacts.json
eq "rc 0"                        "0"    "$RC"
eq "…and says so"                "true" "$(has 'no artifacts declared — nothing to assert' "$OUT")"
# CONTROL — same repo, same range, a config that DOES declare a set must assert it, so the
# arm above is discriminating rather than vacuously green.
run base-0.1.0 head-good
eq "control: the real config DOES assert" "true" "$(has 'all 5 declared artifact member(s)' "$OUT")"

echo "== an EMPTY artifacts array is the same non-opt-in, not a vacuous pass =="
run base-0.1.0 head-good --config empty-artifacts.json
eq "rc 0"          "0"     "$RC"
eq "…and says so"  "true"  "$(has 'no artifacts declared' "$OUT")"
eq "…and claims no members passed" "false" "$(has 'declared artifact member(s) moved' "$OUT")"

echo "== a declared member that would expand to NOTHING is refused, never dropped =="
# Both shapes silently produce zero paths, so the member would be neither asserted nor
# counted — this tool's own defect class (a declared member no assertion ever reads) one
# layer up. Each is paired with the count the CORRECT config produces, so "refused" is
# distinguishable from "the run never got that far".
run base-0.1.0 head-good --config empty-brace.json
eq "an empty brace set → rc 2"       "2"     "$RC"
eq "…and names the offending path"   "true"  "$(has 'expands to no member' "$OUT")"
# The refusal must reach the SCRIPT's exit status, not just its stderr. `_expand_braces` is
# consumed through a process substitution, whose `exit` unwinds the subshell only — a `die`
# placed there printed this very message and then let the run finish rc 0 with the member
# dropped from both the assertions and the count. rc alone is the check that saw that.
eq "…rather than quietly finishing with the member dropped" "false" \
   "$(has 'artifact member(s) moved and agree' "$OUT")"

run base-0.1.0 head-good --config leading-space.json
eq "a leading-whitespace entry → rc 2" "2"    "$RC"
eq "…and echoes the entry"             "true" "$(has 'no leading path token' "$OUT")"

echo "== (case 29) an EMPTY entry is the same class as a whitespace-only one, and answers alike =="
# One question, one answer per source. An empty entry was DROPPED by a `[ -n "$raw" ]` guard at
# each consumer while a whitespace-only entry died rc 2 two lines further in — two dispositions
# for one shape, and the silent one is this tool's own defect class: a declared member that no
# assertion reads and no count mentions.
eq "witness: the config really declares an empty entry beside a good one" "true" \
   "$(has '"VERSION → {{version}}", ""' "$(g -C "$R" show head-good:empty-entry.json)")"
run base-0.1.0 head-good --config empty-entry.json
eq "an EMPTY entry → rc 2, as a whitespace-only one does" "2" "$RC"
eq "…diagnosed by the same message"    "true"  "$(has "no leading path token: ''" "$OUT")"
eq "…rather than finishing with the entry dropped from the count" "false" \
   "$(has 'artifact member(s) moved and agree' "$OUT")"

# CONTROL — the same two entries, well-formed, DO assert and count.
run base-0.1.0 head-good --config two-well-formed.json
eq "control: the well-formed pair passes"  "0"    "$RC"
eq "control: …and counts BOTH members"     "true" "$(has 'all 2 declared artifact member(s)' "$OUT")"

echo "== a config that is valid JSON but not an OBJECT is rc 2, not a jq traceback =="
# `.artifacts` — and every other `.key` read — is a jq RUNTIME ERROR on a non-object top level
# (`Cannot index array with "artifacts"`, jq rc 5), which `set -e` propagates as the script's
# own exit status: an undocumented rc plus a raw traceback, where the header promises rc 2 for
# every config error. `null` is in the set because it is a SHAPE error that `jq -e .` reports
# as a parse failure, so it must be diagnosed by the object check rather than mis-named.
for bad in 'array:[1,2]' 'string:"hello"' 'number:42' 'null:null'; do
  run base-0.1.0 head-good --config "bad-obj-${bad%%:*}.json"
  eq "top-level ${bad#*:} → rc 2 (the documented config-error code)" "2" "$RC"
  eq "…the message names the config file"       "true"  "$(has "bad-obj-${bad%%:*}.json" "$OUT")"
  eq "…and says an object is expected"          "true"  "$(has 'not a JSON object at the top level' "$OUT")"
  eq "…with no raw jq traceback"                "false" "$(has 'Cannot index' "$OUT")"
  eq "…and no undocumented rc leaking through"  "false" "$(has 'jq: error' "$OUT")"
done
# CONTROL — a genuine syntax error still reports as one, so the two verdicts stay distinct.
run base-0.1.0 head-good --config bad-syntax.json
eq "control: a syntax error is rc 2"          "2"     "$RC"
eq "control: …and is named as invalid JSON"   "true"  "$(has 'is not valid JSON' "$OUT")"
eq "control: …not as a shape error"           "false" "$(has 'not a JSON object' "$OUT")"

echo "== an EMPTY config is a syntax error, not a shape error naming no type =="
# `jq .` exits 0 on empty input and prints nothing, so a status-only parse test accepts an
# empty committed config and the object check then reports its type as the empty string — a
# refusal whose message names nothing at all.
eq "witness: the committed blob really is empty" "" \
   "$(g -C "$R" show head-good:empty-cfg.json)"
run base-0.1.0 head-good --config empty-cfg.json
eq "rc 2"                                     "2"     "$RC"
eq "…named as invalid JSON"                   "true"  "$(has 'is not valid JSON' "$OUT")"
eq "…and NOT as a shape error naming no type" "false" "$(has 'it is )' "$OUT")"

echo "== a MALFORMED artifacts is a config error — never 'no artifacts declared' =="
# Opt-out and malformed are opposite verdicts. Answering a malformed declaration with "no
# artifacts declared" states something false about the config AND silently disables the gate
# for a repo that plainly meant to enable it.
for wanted in object string number boolean; do
  run base-0.1.0 head-good --config "bad-art-$wanted.json"
  eq "artifacts of type $wanted → rc 2"        "2"     "$RC"
  eq "…naming the type it found ($wanted)"     "true"  "$(has "of type '$wanted'" "$OUT")"
  eq "…and NOT claiming none were declared"    "false" "$(has 'no artifacts declared' "$OUT")"
done

echo "== a declared set with no version_file is a CONFIG error, not a pass =="
run base-0.1.0 head-good --config no-version-file.json
eq "rc 2"                    "2"    "$RC"
eq "…and names what is missing" "true" "$(has 'no version_file' "$OUT")"

echo "== value-taking flags reject an EMPTY value, and both refs are required =="
for f in --base --head --config; do
  rc=0; err="$("$BIN" "$f" "" 2>&1)" || rc=$?
  eq "$f \"\" → rc 2"         "2"    "$rc"
  eq "$f \"\" names the flag" "true" "$(has "$f requires a non-empty value" "$err")"
done
rc=0; err="$("$BIN" --base 2>&1)" || rc=$?
eq "trailing --base → rc 2"               "2"     "$rc"
eq "trailing --base does not leak set -u" "false" "$(has 'unbound variable' "$err")"
rc=0; err="$( (cd "$R" && "$BIN" --head head-good) 2>&1 )" || rc=$?
eq "a missing --base is refused"          "2"     "$rc"
eq "…by name"                             "true"  "$(has '--base <ref> is required' "$err")"
rc=0; err="$( (cd "$R" && "$BIN" --base base-0.1.0) 2>&1 )" || rc=$?
eq "a missing --head is refused"          "2"     "$rc"
eq "…by name"                             "true"  "$(has '--head <ref> is required' "$err")"
rc=0; err="$("$BIN" --nope 2>&1)" || rc=$?
eq "an unknown flag is refused"           "2"     "$rc"
eq "…by name"                             "true"  "$(has "unknown arg '--nope'" "$err")"

_summary "release-artifacts-selftest"
