#!/usr/bin/env bash
# release-pr-body-selftest.sh — deterministic, network-free checks for the release
# baseline resolution of `bin/release-pr-body`, against real fixture git repos
# (a bare "origin" + a workstation clone; file paths, no network).
#
# Pins the defect shape found cutting v0.14.0: the documented release flow never
# checks out the local main ref (branch off dev → PR → merge on the forge →
# back-merge), so local main drifts a full release behind every cycle — a baseline
# described from it names an already-shipped tag and the generated body reports
# shipped PRs as new. The tool must resolve the baseline against ORIGIN's main
# (fetching it), fail LOUD when the fetch fails, and honor an explicit --base as
# the offline override. Matches the toolkit's selftest-CI convention (no
# bats/shunit2 dep; a runnable script CI invokes).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
BIN="$HERE/../bin/release-pr-body"
_need -x "$BIN"

contains()     { # <label> <haystack> <needle>
  case "$2" in *"$3"*) ok "$1";; *) bad "$1 — expected to find '$3'";; esac
}
not_contains() { # <label> <haystack> <needle>
  case "$2" in *"$3"*) bad "$1 — must NOT contain '$3'";; *) ok "$1";; esac
}

# Deterministic git identity/config, independent of the runner's.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
g() { git -c init.defaultBranch=main -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

_mktmp_scratch; T="$TMP"   # T keeps the fixture's short name; the prelude owns cleanup

# --- fixture: origin + seed (drives the "remote" side) -----------------------
g init --bare -q "$T/origin.git"
g -C "$T/origin.git" symbolic-ref HEAD refs/heads/main

g clone -q "$T/origin.git" "$T/seed" 2>/dev/null
S="$T/seed"
g -C "$S" symbolic-ref HEAD refs/heads/main
echo one > "$S/f"; g -C "$S" add f; g -C "$S" commit -qm "chore: init"
g -C "$S" tag v0.1.0
g -C "$S" push -q origin main --tags
g -C "$S" checkout -qb dev
echo two > "$S/f"; g -C "$S" commit -qam "feat: shipped in cycle one (#1) DL-1"
g -C "$S" push -q origin dev

# Workstation clone — taken BEFORE release cycle 1 lands on origin's main.
g clone -q "$T/origin.git" "$T/work"
W="$T/work"

# Release cycle 1 happens ON THE REMOTE (merged via the forge; the workstation
# never checks out main): merge dev → main, tag v0.2.0, then new dev work.
g -C "$S" checkout -q main
g -C "$S" merge -q --no-ff dev -m "Merge pull request #2 (release v0.2.0)"
g -C "$S" tag v0.2.0
g -C "$S" push -q origin main v0.2.0
g -C "$S" checkout -q dev
echo three > "$S/f"; g -C "$S" commit -qam "feat: new work for cycle two (#3) DL-2"
g -C "$S" push -q origin dev

# Workstation follows only dev (the documented flow): explicit-refspec pull, so
# neither local main nor the main-only tag v0.2.0 comes over.
g -C "$W" checkout -q dev
g -C "$W" pull -q origin dev

cat > "$W/.release-pr.json" <<'EOF'
{
  "main_branch": "main",
  "dev_branch": "dev",
  "ref_token_regex": "DL-[0-9]+",
  "title_prefix": "Release"
}
EOF

echo "== precondition: the fixture reproduces the stale-local-main incident shape =="
stale="$(g -C "$W" describe --tags --abbrev=0 main)"
if [[ "$stale" == v0.1.0 ]]; then ok "local main still describes v0.1.0 (a local-ref baseline would lie)"
else bad "fixture broken: local main describes '$stale', expected v0.1.0"; fi
if g -C "$W" rev-parse -q --verify refs/tags/v0.2.0 >/dev/null; then
  bad "fixture broken: v0.2.0 already local — the tool's own fetch would not be what finds it"
else
  ok "v0.2.0 not yet local (only the tool's fetch can surface it)"
fi

echo "== baseline comes from origin's main, not the stale local ref =="
body="$( (cd "$W" && "$BIN" --version 0.3.0) 2>"$T/err" )" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then ok "generates a body (rc=0)"; else bad "expected rc=0, got rc=$rc ($(cat "$T/err"))"; fi
contains     "baseline is origin's tag"          "$body" "since v0.2.0"
contains     "counts only the unshipped commit"  "$body" "Bundles 1 commit(s)"
contains     "bundles the cycle-two commit"      "$body" "new work for cycle two"
not_contains "already-shipped PR is NOT re-listed" "$body" "shipped in cycle one"
contains     "drift note names local-vs-origin"  "$(cat "$T/err")" "note: local 'main'"

echo "== --manifest sees the same corrected range =="
man="$( (cd "$W" && "$BIN" --version 0.3.0 --manifest) 2>/dev/null )" || man="(rc=$?)"
if [[ "$man" == "DL-2" ]]; then ok "manifest is exactly DL-2"; else bad "manifest expected 'DL-2', got '$man'"; fi

echo "== fetch failure is LOUD, never a silent stale-local fallback =="
g -C "$W" remote set-url origin "$T/nonexistent.git"
out="$( (cd "$W" && "$BIN" --version 0.3.0) 2>&1 )" && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]]; then ok "non-zero exit on unfetchable origin (rc=$rc)"; else bad "expected non-zero exit, got 0"; fi
contains     "error names the fetch + the override" "$out" "cannot fetch origin"
not_contains "no body emitted on a wrong baseline"  "$out" "## Bundled"

echo "== explicit --base is the offline override (skips the fetch) =="
body2="$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0) 2>/dev/null )" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then ok "works offline with --base (rc=0)"; else bad "expected rc=0 with --base, got rc=$rc"; fi
contains "uses the given baseline" "$body2" "since v0.1.0"
contains "full range from v0.1.0"  "$body2" "Bundles 2 commit(s)"

# Restore the real origin (the fetch-failure case above pointed it at a void).
g -C "$W" remote set-url origin "$T/origin.git"

echo "== version-file extraction keeps all 4 segments of a .NET-style version =="
# A 3-segment-only extraction pattern silently truncates 1.22.1.0 → 1.22.1; the
# body's version line makes that visible ('v1.22.1.0' never appears).
echo "AssemblyVersion: 1.22.1.0" > "$W/VERSION.txt"
cat > "$W/.release-pr.json" <<'EOF'
{
  "main_branch": "main",
  "dev_branch": "dev",
  "ref_token_regex": "DL-[0-9]+",
  "title_prefix": "Release",
  "version_file": "VERSION.txt",
  "version_regex": "[0-9]+(\\.[0-9]+){1,3}"
}
EOF
body4="$( (cd "$W" && "$BIN") 2>/dev/null )" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then ok "resolves the version from the file (rc=0)"; else bad "expected rc=0, got rc=$rc"; fi
contains "4-segment version survives extraction" "$body4" "v1.22.1.0"

echo "== tag_format drives the own-tag exclude (re-run after tagging, non-v scheme) =="
# Release cycle 2 lands on the remote under a release-{{version}} tag scheme; a
# re-run for 0.3.0 must exclude release-0.3.0 (its own tag) when resolving BASE.
# A hardcoded v-prefix excludes the nonexistent v0.3.0 instead, so BASE resolves
# to release-0.3.0 itself and the body reports 'since release-0.3.0' with 0 commits.
g -C "$S" checkout -q main
g -C "$S" merge -q --no-ff dev -m "Merge pull request #4 (release 0.3.0)"
g -C "$S" tag release-0.3.0
g -C "$S" push -q origin main release-0.3.0
cat > "$W/.release-pr.json" <<'EOF'
{
  "main_branch": "main",
  "dev_branch": "dev",
  "ref_token_regex": "DL-[0-9]+",
  "title_prefix": "Release",
  "tag_format": "release-{{version}}"
}
EOF
body5="$( (cd "$W" && "$BIN" --version 0.3.0) 2>/dev/null )" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then ok "generates a body under tag_format (rc=0)"; else bad "expected rc=0, got rc=$rc"; fi
contains     "own tag excluded via tag_format"    "$body5" "since v0.2.0"
not_contains "own tag is not its own baseline"    "$body5" "since release-0.3.0"
contains     "range still bundles the dev commit" "$body5" "new work for cycle two"

_summary "release-pr-body-selftest"
