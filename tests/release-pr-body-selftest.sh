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

# NO `main_branch`/`dev_branch` key here, deliberately. This fixture's branches ARE `main` and
# `dev`, so SETTING the keys to those values is a control that cannot discriminate: a pass could
# not tell "the key was read" from "the default fired" (card#7038, instances 4-5). With the keys
# genuinely ABSENT this block asserts the DEFAULTS — a distinct behaviour worth keeping covered —
# and the non-default fixture below asserts the READ. Every fixture here that does not care about
# the branch names omits them for the same reason: the ONE that sets them sets them to names that
# are not the defaults, which is the only setting that can tell the two apart.
cat > "$W/.release-pr.json" <<'EOF'
{
  "ref_token_regex": "DL-[0-9]+"
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
# The config above carries NEITHER branch key, so this is the defaults-when-absent path and the
# header is where both defaults become observable at once.
contains     "absent branch keys ⇒ the defaults fire" "$(printf '%s\n' "$body" | head -1)" '`dev → main` release PR'

echo "== --manifest sees the same corrected range =="
man="$( (cd "$W" && "$BIN" --version 0.3.0 --manifest) 2>/dev/null )" || man="(rc=$?)"
if [[ "$man" == "DL-2" ]]; then ok "manifest is exactly DL-2"; else bad "manifest expected 'DL-2', got '$man'"; fi

echo "== the HEAD leg is resolved from ORIGIN too — a lagging local dev drops PRs from the body AND the manifest (card#7517) =="
# WHAT WAS BROKEN, AND WHY NOTHING SAW IT. `HEAD_REF="${HEAD_REF:-$DEV_BRANCH}"` defaulted the
# head of the range to the LOCAL integration ref — three lines above a `die` whose own words say
# a local ref "is NOT a usable fallback", and feeding the SAME `RANGE` as that refusal. The
# release worktree is cut once and dev keeps moving under it, so the lag is the normal case, not
# an exotic one. A short range is well-formed: the body renders, the count looks plausible, the
# `shipped-cards` footer is valid — and it is simply missing its newest entries, which is the
# input `promote-released-cards` uses to decide which cards reach Released. Measured at the
# v0.30.0 cut: 38 rows instead of 39, no `#298`, and no `7500` — the SECURITY fix's card, which
# would therefore never have been promoted.
#
# THE FIXTURE IS THE INCIDENT. Its origin's dev carries a commit the workstation's LOCAL dev —
# and its remote-tracking ref — do not have, so ONLY the tool's own fetch can surface it. The
# assertions below are PRESENCE assertions on that commit's PR number and card id: pre-fix they
# are all absent (range `v0.29.0..dev`, one commit, `shipped-cards=7494`), post-fix all present.
# That absence-then-presence pair is the proof; a test written only against the fixed code would
# be satisfied by a tool that bundled everything unconditionally.
HO="$T/head-origin.git"; HS="$T/head-seed"; HW="$T/head-work"
g init --bare -q "$HO"
g -C "$HO" symbolic-ref HEAD refs/heads/main
g clone -q "$HO" "$HS" 2>/dev/null
g -C "$HS" symbolic-ref HEAD refs/heads/main
echo one > "$HS/f"; g -C "$HS" add f; g -C "$HS" commit -qm "chore: init"
g -C "$HS" tag v0.29.0
g -C "$HS" push -q origin main --tags
g -C "$HS" checkout -qb dev
echo two > "$HS/f"; g -C "$HS" commit -qam "fix(a): an ordinary change (card#7494) (#297)"
g -C "$HS" push -q origin dev

# The release worktree, cut HERE — while dev is at #297.
g clone -q "$HO" "$HW"
g -C "$HW" checkout -q dev

# …and dev keeps moving under it: the security fix lands on origin AFTER the cut.
echo three > "$HS/f"; g -C "$HS" commit -qam "security(url): mask userinfo on ten error paths (card#7500) (#298)"
g -C "$HS" push -q origin dev

# Branch keys deliberately ABSENT — this block is about the DEFAULT head leg, and a fixture that
# set `dev_branch` to `dev` could not tell "the key was read" from "the default fired" (the same
# discrimination rule the block below states for main_branch/dev_branch).
cat > "$HW/.release-pr.json" <<'EOF'
{
  "card_token_regex": "card#[0-9]+"
}
EOF

echo "-- precondition: the local refs lag the remote, so only a fetch can surface #298"
eq "local dev is still at #297"                    "true"  "$(has '(#297)' "$(g -C "$HW" log -1 --format=%s dev)")"
eq "…and so is the remote-TRACKING ref"            "true"  "$(has '(#297)' "$(g -C "$HW" log -1 --format=%s refs/remotes/origin/dev)")"
eq "…while origin's dev already carries #298"      "true"  "$(has '(#298)' "$(g -C "$HS" log -1 --format=%s dev)")"

rc=0; hbody="$( (cd "$HW" && "$BIN" --version 0.30.0) 2>"$T/herr" )" || rc=$?
eq "generates a body (rc 0)"                       "0"     "$rc"
eq "the baseline is still origin's tag"            "true"  "$(has 'since v0.29.0' "$hbody")"
eq "the range counts BOTH commits"                 "true"  "$(has 'Bundles 2 commit(s)' "$hbody")"
eq "the bundled table carries the remote-only PR"  "true"  "$(has '**#298**' "$hbody")"
eq "…alongside the one the local ref had"          "true"  "$(has '**#297**' "$hbody")"
eq "the shipped-cards footer carries BOTH ids"     "true"  "$(has '<!-- release-manifest:shipped-cards=7500,7494 -->' "$hbody")"
eq "--card-manifest sees the same corrected range" "7500
7494" "$( (cd "$HW" && "$BIN" --version 0.30.0 --card-manifest) 2>/dev/null )"
eq "…and the local drift is NOTED, not silent"     "true"  "$(has "note: local 'dev'" "$(cat "$T/herr")")"

echo "-- an explicit --head still wins, and says when it is behind"
# The v0.30.0 cut's own workaround was an explicit --head, and a caller may legitimately want a
# local or a release-branch ref. The override is honoured verbatim — the ONLY thing the fix adds
# on this path is the note, because the omission it causes leaves no other trace.
rc=0; hlocal="$( (cd "$HW" && "$BIN" --version 0.30.0 --head dev) 2>"$T/herr2" )" || rc=$?
eq "explicit --head → rc 0"                        "0"     "$rc"
eq "…the LOCAL ref is what is used"                "false" "$(has '**#298**' "$hlocal")"
eq "…bundling only what that ref carries"          "true"  "$(has '**#297**' "$hlocal")"
eq "…and its manifest is short, as asked"          "true"  "$(has '<!-- release-manifest:shipped-cards=7494 -->' "$hlocal")"
eq "…with a note naming the gap it costs"          "true"  "$(has "--head 'dev' is 1 commit(s) behind origin/dev" "$(cat "$T/herr2")")"
# CONTROL — the same flag on a ref that is NOT behind draws no note, so the arm above is the
# behind-ness and not "an explicit --head always warns". (The default run above fetched, so
# origin/dev is now local and resolvable here.)
rc=0; hup="$( (cd "$HW" && "$BIN" --version 0.30.0 --head origin/dev) 2>"$T/herr3" )" || rc=$?
eq "control: an up-to-date explicit --head → rc 0" "0"     "$rc"
eq "control: …carries the remote-only PR"          "true"  "$(has '**#298**' "$hup")"
eq "control: …and draws NO behind-note"            "false" "$(has 'behind origin/dev' "$(cat "$T/herr3")")"

echo "-- in sync, the change is a NO-OP: the same range renders the same bytes"
# The constraint this fix had to hold: where the local and remote tips agree, the body must be
# byte-identical to what the old local-ref default produced. Asserted as an equality between the
# DEFAULTED head (origin/dev) and the explicit LOCAL head (dev) over the same commit — the two
# spellings the fix moves between.
g -C "$HW" merge -q --ff-only origin/dev
eq "precondition: local dev now equals origin/dev" "$(g -C "$HW" rev-parse dev)" "$(g -C "$HW" rev-parse refs/remotes/origin/dev)"
sync_default="$( (cd "$HW" && "$BIN" --version 0.30.0) 2>"$T/herr4" )"
sync_local="$(   (cd "$HW" && "$BIN" --version 0.30.0 --head dev) 2>/dev/null )"
eq "default head and local head render identical bytes" "$sync_default" "$sync_local"
eq "…and no drift note is emitted at all"          "false" "$(has 'note: local' "$(cat "$T/herr4")")"

echo "== fetch failure is LOUD, never a silent stale-local fallback =="
g -C "$W" remote set-url origin "$T/nonexistent.git"
out="$( (cd "$W" && "$BIN" --version 0.3.0) 2>&1 )" && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]]; then ok "non-zero exit on unfetchable origin (rc=$rc)"; else bad "expected non-zero exit, got 0"; fi
contains     "error names the fetch + the override" "$out" "cannot fetch origin"
not_contains "no body emitted on a wrong baseline"  "$out" "## Bundled"

echo "== offline takes BOTH overrides now — one per range leg (card#7517) =="
# Each explicit flag skips ITS OWN leg's fetch, and nothing else's. `--base` alone used to be a
# complete offline override only because the head leg silently fell back to the local ref, which
# is the defect: the flag that made the run possible was not the flag that decided the answer.
# With origin unreachable it now refuses, and the refusal names the flag that settles the other
# end rather than making the caller infer it.
rc=0; onlybase="$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0) 2>&1 )" || rc=$?
eq "--base alone on an unreachable origin → rc 2" "2"     "$rc"
eq "…the refusal names the head leg's override"   "true"  "$(has "pass an explicit --head <ref>" "$onlybase")"
eq "…and no body is emitted over a short range"   "false" "$(has '## Bundled' "$onlybase")"

body2="$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0 --head dev) 2>/dev/null )" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then ok "works offline with --base + --head (rc=0)"; else bad "expected rc=0 with --base + --head, got rc=$rc"; fi
contains "uses the given baseline" "$body2" "since v0.1.0"
contains "full range from v0.1.0"  "$body2" "Bundles 2 commit(s)"

echo "== an explicit --base/--head that does not RESOLVE is refused by name (card#7525) =="
# WHAT WAS BROKEN, AND WHY card#7517 DID NOT CLOSE IT. That card hardened the DEFAULTED legs:
# they resolve from the remote, fetch, and die loudly. The explicit legs are deliberately
# exempt from that fetch — the flag is the caller's override, and it is the offline route the
# block above documents — so nothing ever looked the handed-in ref up at all. `git log "$RANGE"`
# runs under `2>/dev/null` at four sites, and the three observable outcomes are all silent:
#   * `--manifest` / `--card-manifest`  → an EMPTY list at rc 0. These are the MACHINE-READ
#     surfaces, and `shipped-cards` is the input deciding which cards get promoted.
#   * the full body                     → the `COUNT=` pipeline fails 128 under pipefail and
#     errexit aborts the script: rc 128 with ZERO BYTES on either stream, naming neither the
#     ref nor the flag. Measured pre-fix, not inferred — it is not the rc-0 empty body the
#     shape suggests, because `set -o pipefail` promotes git's 128 out of the substitution.
# ⇒ a typo'd or deleted ref is indistinguishable from a genuinely empty range, in every one.
#
# THE ARMS BELOW ARE THE FAIL-THEN-PASS PAIR. Pre-fix: rc 128 (body) / rc 0 (manifests), and
# no message anywhere. Post-fix: rc 2 naming the flag AND the value. Origin is still pointed at
# a void here, on purpose — the refusal must not need the network, and the arm that pins that
# is the bad `--base` with the head leg DEFAULTED, which pre-fix could only reach the fetch
# refusal.
badhead="no-such-ref"
rc=0; bh="$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0 --head "$badhead") 2>&1 )" || rc=$?
eq "unresolvable --head → rc 2"                    "2"     "$rc"
eq "…the refusal names the FLAG"                   "true"  "$(has "--head '$badhead'" "$bh")"
eq "…and says it resolves to no commit here"       "true"  "$(has "does not resolve to a commit in this repo" "$bh")"
eq "…and no body is emitted over a dead range"     "false" "$(has '## Bundled' "$bh")"
eq "…nor the empty-bundle placeholder"             "false" "$(has 'no non-merge commits in' "$bh")"

# The manifest modes are where the pre-fix rc was 0 — a valid, empty, machine-read answer.
rc=0; bhm="$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0 --head "$badhead" --manifest) 2>&1 )" || rc=$?
eq "unresolvable --head --manifest → rc 2"         "2"     "$rc"
eq "…rather than an empty list at rc 0"            "true"  "$(has "--head '$badhead'" "$bhm")"
rc=0; bhc="$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0 --head "$badhead" --card-manifest) 2>&1 )" || rc=$?
eq "unresolvable --head --card-manifest → rc 2"    "2"     "$rc"
eq "…rather than a manifest that promotes nothing" "true"  "$(has "--head '$badhead'" "$bhc")"

# A FULL-LENGTH HEX NAMING NO OBJECT — the arm that reds if the `^{commit}` peel is dropped.
# `git rev-parse --verify -q <40-hex>` exits 0 on it (it verifies the SPELLING can become a raw
# object name, not that the object is present — measured, git 2.43.0), while `git log` dies
# `bad object`. This is not a curiosity: a sha copied off a rebased-away branch or an old PR is
# the "deleted ref" case, and a raw sha is the natural offline spelling of --head.
deadsha="0000000000000000000000000000000000000001"
rc=0; ( cd "$W" && g rev-parse --verify -q "$deadsha" ) >/dev/null 2>&1 || rc=$?
eq "precondition: bare --verify passes this sha"   "0"     "$rc"
eq "precondition: …and git log dies on it"         "true" \
   "$(has 'bad object' "$( (cd "$W" && g log "$deadsha" --oneline) 2>&1 || true )")"
rc=0; bs="$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0 --head "$deadsha") 2>&1 )" || rc=$?
eq "a hex sha naming no object → rc 2"             "2"     "$rc"
eq "…named in the refusal"                         "true"  "$(has "--head '$deadsha'" "$bs")"

# --base has the IDENTICAL shape — verified rather than assumed. It skips its own leg's fetch,
# `require_value` has already made it non-empty, and it goes straight into `$BASE..$HEAD_REF`.
rc=0; bb="$( (cd "$W" && "$BIN" --version 0.3.0 --base no-such-tag --head dev) 2>&1 )" || rc=$?
eq "unresolvable --base → rc 2"                    "2"     "$rc"
eq "…the refusal names --base and its value"       "true"  "$(has "--base 'no-such-tag'" "$bb")"
eq "…and emits no body"                            "false" "$(has '## Bundled' "$bb")"

# ORDERING: the base leg is checked BEFORE the head leg's fetch, so a bad baseline refuses
# without touching the network. Origin is a void here, so pre-ordering-fix this would report
# the FETCH failure instead — a true statement about a run that should never have got that far.
rc=0; bo="$( (cd "$W" && "$BIN" --version 0.3.0 --base no-such-tag) 2>&1 )" || rc=$?
eq "bad --base + defaulted head → rc 2"            "2"     "$rc"
eq "…refuses on the BASE, before any fetch"        "true"  "$(has "--base 'no-such-tag'" "$bo")"
eq "…not on the unreachable origin"                "false" "$(has 'cannot fetch origin' "$bo")"

# POSITIVE CONTROLS — without them a check that refuses EVERYTHING passes every arm above.
# Three resolvable --head spellings, all still rc 0 over the same unreachable origin: a branch
# name, `HEAD`, and a raw sha (the spelling the `^{commit}` peel must not break); the annotated
# tag below is the fourth, on the --base leg, where a peel that refused non-commit objects would
# be the way this check breaks a good run.
devsha="$(g -C "$W" rev-parse dev)"
for spelling in dev HEAD "$devsha"; do
  rc=0; okbody="$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0 --head "$spelling") 2>&1 )" || rc=$?
  eq "control: --head '$spelling' still renders (rc 0)" "0"    "$rc"
  eq "control: …with the bundled section"               "true" "$(has '## Bundled' "$okbody")"
  eq "control: …over the given baseline"                "true" "$(has 'since v0.1.0' "$okbody")"
done
# …and the guard adds NOTHING to a good run's output: the resolvable invocation renders the same
# bytes as $body2, generated by the identical invocation earlier in this file. An IN-RUN
# consistency arm, honestly labelled — not a pre/post comparison, which a selftest cannot make
# because it cannot hold two versions of its own bin. It reds if this check ever grows a warning
# on stdout. The pre/post identity was measured out of band against the unguarded binary over 16
# invocations (rc + stdout + stderr sha256 each); docs/CHANGELOG.md records the result.
eq "control: a resolvable run is byte-identical to the unguarded one" "$body2" \
   "$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0 --head dev) 2>/dev/null )"
# An annotated tag must peel through `^{commit}` rather than be refused as "not a commit".
g -C "$W" tag -a -m "annotated" v0.1.0-annot v0.1.0
rc=0; annot="$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0-annot --head dev) 2>&1 )" || rc=$?
eq "control: an ANNOTATED tag resolves (rc 0)"     "0"     "$rc"
eq "control: …and is used as the baseline"         "true"  "$(has 'since v0.1.0-annot' "$annot")"
g -C "$W" tag -d v0.1.0-annot >/dev/null

# --tag returns BEFORE the range block and builds no range, so it must still answer with a
# nonsense --head — `release-tag-check` asks it in a CI job with no promise the refs are there.
rc=0; tagok="$( (cd "$W" && "$BIN" --tag --version 0.3.0 --head "$badhead") 2>&1 )" || rc=$?
eq "control: --tag answers despite a bogus --head" "0"      "$rc"
eq "control: …with the tag name alone"             "v0.3.0" "$tagok"

# Restore the real origin (the fetch-failure case above pointed it at a void).
g -C "$W" remote set-url origin "$T/origin.git"

echo "== main_branch / dev_branch are READ, not defaulted (card#7038 instances 4-5) =="
# WHAT WAS UNCOVERED. Every fixture in this file used to SET these two keys to their own
# default values (`main`/`dev`). The assertions were real and the fixtures were real, and the
# coverage was still zero for the thing the keys exist to do: a pass could not distinguish "the
# key was read" from "the default fired". Measured, not argued — deleting either `cfg_opt` read
# left the whole suite green.
#
# THE FIXTURE IS WHAT DISCRIMINATES. Non-default branch names alone are not enough: if `main`
# and `dev` simply did not exist here, ignoring the keys would merely CRASH the tool, and a red
# would prove nothing more than "it ran". So this origin ALSO carries decoy `main` and `dev`
# branches, on their own commits, under their own tag. A build that ignores the config still
# produces a complete, rc-0 body — a WRONG one, naming the decoys. That is the only shape that
# separates read-the-key from fired-the-default.
AO="$T/alt-origin.git"; AW="$T/alt"
g init --bare -q "$AO"
g -C "$AO" symbolic-ref HEAD refs/heads/trunk
g clone -q "$AO" "$AW" 2>/dev/null
g -C "$AW" symbolic-ref HEAD refs/heads/trunk
echo one > "$AW/f"; g -C "$AW" add f; g -C "$AW" commit -qm "chore: init"
g -C "$AW" tag v0.1.0
g -C "$AW" checkout -qb main
echo decoy > "$AW/f"; g -C "$AW" commit -qam "chore: decoy on main (#98)"
g -C "$AW" tag v9.9.9                       # a default-`main` baseline describes THIS
g -C "$AW" checkout -qb dev v0.1.0
echo devdecoy > "$AW/f"; g -C "$AW" commit -qam "feat: decoy on dev (#99) DL-99"
g -C "$AW" checkout -qb integration v0.1.0
echo real > "$AW/f"; g -C "$AW" commit -qam "feat: integration work (#7) DL-7"
g -C "$AW" push -q origin trunk main dev integration --tags

cat > "$AW/.release-pr.json" <<'EOF'
{
  "main_branch": "trunk",
  "dev_branch": "integration",
  "ref_token_regex": "DL-[0-9]+"
}
EOF
rc=0; altbody="$( (cd "$AW" && "$BIN" --version 0.3.0) 2>/dev/null )" || rc=$?
eq "non-default branch config → rc 0" "0" "$rc"
alt_hdr="$(printf '%s\n' "$altbody" | head -1)"
contains     "header names the CONFIGURED branches"   "$alt_hdr" '`integration → trunk` release PR'
not_contains "…and not the defaults"                  "$alt_hdr" '`dev → main`'
# main_branch reaches the BASELINE, not just the header: v0.1.0 is on trunk, v9.9.9 on the decoy.
contains     "baseline comes from the configured main" "$altbody" "since v0.1.0"
not_contains "…not the default branch's tag"           "$altbody" "since v9.9.9"
# dev_branch is what HEAD defaults to, so it decides which commits are bundled at all.
contains     "head defaults to the configured dev"     "$altbody" "integration work"
not_contains "…not the default 'dev' branch"           "$altbody" "decoy on dev"

echo "== the version SHAPE is version_regex's to declare, and bin/ holds no second pattern (card#7208) =="
# WHAT THIS BLOCK USED TO BE, AND WHY IT PROVED NOTHING. One case: a 4-segment version file
# read through a config whose version_regex was ITSELF 4-segment-capable. A pass could not tell
# "the config governs" from "the hardcoded `[0-9]+(\.[0-9]+){1,3}` in the bin rescued it" — and
# the bin's pattern could rescue nothing, because it ran SECOND, over a first stage that had
# already applied the config regex. With a 3-segment version_regex, 1.22.1.0 reached it as
# 1.22.1; the comment sitting above that line named exactly that truncation as prevented.
#
# The literal is gone. What these cases pin is that version_regex — the same key
# `auto-tag-version.yml` anchors at merge time — is the ONLY thing that decides the shape:
# a config that admits four segments gets four, one that admits three gets three (even over a
# 4-segment file), and the two shapes the old literal quietly overrode (one segment, five)
# now resolve as declared. Cases 4 and 5 are the red-when-reverted pair: re-adding the literal
# turns 4 into an rc-2 refusal and cuts 5 to four segments.
_verhdr() { # <version-file content> <version_regex, JSON-escaped> → the body's first line, or "rc=N"
  local content="$1" re="$2" b rc=0
  printf '%s\n' "$content" > "$W/VERSION.txt"
  # Unquoted heredoc so $re expands; a parameter expansion's RESULT is not rescanned for
  # backslash escapes, so the JSON's `\\.` arrives intact.
  cat > "$W/.release-pr.json" <<EOF
{
  "ref_token_regex": "DL-[0-9]+",
  "version_file": "VERSION.txt",
  "version_regex": "$re"
}
EOF
  b="$( (cd "$W" && "$BIN") 2>/dev/null )" || rc=$?
  if [[ "$rc" -ne 0 ]]; then printf 'rc=%s\n' "$rc"; else printf '%s\n' "$b" | head -1; fi
}
# The needle carries the header's closing `.**`, so `v1.22.1.**` cannot match a body that
# rendered `v1.22.1.0` — without it every truncation assertion would pass on both behaviours.

# (1) PAIRED WITNESS — an ordinary 3-segment release, byte-identical before and after. Without
#     it, "stopped truncating" is indistinguishable from "stopped extracting".
contains "3-segment config + 3-segment file → the whole version" \
  "$(_verhdr '0.29.0' '[0-9]+\\.[0-9]+\\.[0-9]+')" 'release PR — v0.29.0.**'

# (2) a config that ADMITS four segments keeps all four (the case this block always had).
contains "4-segment-capable config + .NET version → all four segments" \
  "$(_verhdr 'AssemblyVersion: 1.22.1.0' '[0-9]+(\\.[0-9]+){1,3}')" 'release PR — v1.22.1.0.**'

# (3) …and a 3-segment config over the SAME file yields three, honestly. This is the case the
#     old comment claimed was prevented; it never was, and now nothing says it is.
hdr3="$(_verhdr 'AssemblyVersion: 1.22.1.0' '[0-9]+\\.[0-9]+\\.[0-9]+')"
contains     "3-segment config + .NET version → three segments, because the config says three" \
  "$hdr3" 'release PR — v1.22.1.**'
not_contains "…and no pattern inside the bin widens it back" "$hdr3" 'v1.22.1.0'

# (4) RED WHEN REVERTED — the deleted literal needed two segments, so it turned a legal
#     single-segment version_regex into `could not resolve version` (rc 2).
contains "a single-segment version_regex resolves" \
  "$(_verhdr '7' '[0-9]+')" 'release PR — v7.**'

# (5) RED WHEN REVERTED — …and it cut a legal five-segment one down to four.
contains "a five-segment version_regex is not cut to four" \
  "$(_verhdr '1.2.3.4.5' '[0-9]+(\\.[0-9]+){1,4}')" 'release PR — v1.2.3.4.5.**'

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
  "ref_token_regex": "DL-[0-9]+",
  "tag_format": "release-{{version}}"
}
EOF
body5="$( (cd "$W" && "$BIN" --version 0.3.0) 2>/dev/null )" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then ok "generates a body under tag_format (rc=0)"; else bad "expected rc=0, got rc=$rc"; fi
contains     "own tag excluded via tag_format"    "$body5" "since v0.2.0"
not_contains "own tag is not its own baseline"    "$body5" "since release-0.3.0"
contains     "range still bundles the dev commit" "$body5" "new work for cycle two"

echo "== body header renders the real tag via tag_format (card#4762) =="
# The display header must name the tag that actually exists (per tag_format), not a
# hardcoded v-prefix. $body was generated with the default scheme (no tag_format);
# $body5 with tag_format=release-{{version}}. not_contains is scoped to the header
# LINE so a legitimate v-prefixed baseline elsewhere in the body can't false-match.
dflt_hdr="$(printf '%s\n' "$body" | head -1)"
contains "default scheme header names the v-prefixed tag" "$dflt_hdr" "release PR — v0.3.0."

tf_hdr="$(printf '%s\n' "$body5" | head -1)"
contains     "tag_format header names release-<version>" "$tf_hdr" "release PR — release-0.3.0."
not_contains "tag_format header has no phantom v-tag"     "$tf_hdr" "v0.3.0"

# Explicit --base skips the baseline block where THIS_TAG was formerly assigned; the
# hoist makes it live on this path too. Pre-hoist this renders the wrong hardcoded
# v-tag — or, once the header references THIS_TAG, crashes under `set -u` (unbound).
body6="$( (cd "$W" && "$BIN" --version 0.3.0 --base v0.1.0) 2>/dev/null )" && rc=0 || rc=$?
if [[ "$rc" -eq 0 ]]; then ok "renders a body under --base + tag_format (rc=0)"; else bad "expected rc=0 with --base+tag_format, got rc=$rc"; fi
base_hdr="$(printf '%s\n' "$body6" | head -1)"
contains "--base header still honors tag_format" "$base_hdr" "release PR — release-0.3.0."
contains "--base uses the given baseline"        "$body6"    "since v0.1.0"

echo "== a range with no ref-token match still exits 0 (card#5874) =="
# The manifest footer is optional by contract ("an empty range yields an empty (but valid)
# bundled section, not a failure"), but the generator's LAST statement was
# `[ -n "$MANIFEST" ] && printf …` — the failed test became the script's own exit status, so
# a complete, correct body was reported as a failed generation. `set -e` cannot catch it: the
# left arm of an `&&` list is exempt. Only the regex varies between the two arms below.
tokencfg() { # <ref_token_regex> — everything else held constant
  cat > "$W/.release-pr.json" <<EOF
{
  "ref_token_regex": "$1",
  "tag_format": "release-{{version}}"
}
EOF
}

tokencfg 'card#[0-9]+'   # matches nothing in this range (the fixture's tokens are DL-N)
rc=0; body7="$( (cd "$W" && "$BIN" --version 0.3.0) 2>/dev/null )" || rc=$?
eq "no-token range exits 0"                  "0"     "$rc"
eq "…and the body is still complete"         "true"  "$(has '## Bundled' "$body7")"
eq "…with the range's commit in it"          "true"  "$(has 'new work for cycle two' "$body7")"
eq "…and simply carries no manifest footer"  "false" "$(has 'release-manifest:shipped-refs' "$body7")"

# CONTROL — same tool, same range, same config but a regex that DOES match. It must exit 0
# *and* emit the footer, so the arm above is discriminating rather than vacuously green.
tokencfg 'DL-[0-9]+'
rc=0; body8="$( (cd "$W" && "$BIN" --version 0.3.0) 2>/dev/null )" || rc=$?
eq "control: matching range exits 0"         "0"     "$rc"
eq "control: footer names the shipped token" "true"  "$(has 'release-manifest:shipped-refs=DL-2' "$body8")"

echo "== the card-coverage gate can FIRE on a card#-spelled range (card#5877) =="
# WHAT WAS BROKEN. `card_coverage_section` computed its manifest from `ref_token_regex` only,
# and short-circuited on an empty one with a confident `_No shipped DL refs in range._`. This
# repo's commit subjects had migrated to `card#NNNN` while that key still said `DL-`, so the
# manifest was unconditionally empty and the section rendered clean WITHOUT CHECKING — the
# canon-#9 shape, a check that cannot fail. Nothing here exercised it: every case above runs
# without a board token, so before card#7038 they all rendered the "_Not checked here_"
# placeholder branch — and now render no coverage section at all (see the block below).
#
# WHY NOT JUST RE-SPELL ref_token_regex. Measured, not argued: promote-released-cards reads the
# SAME key and matches the token's NUMERIC part against `payload.dl_number`, so a `card#`
# spelling makes `card#42` correlate with whatever card carries DL-42 — it moves that card and
# reports "0 no-card". Hence a second key, `card_token_regex`, whose numeric part means a card ID.
#
# END-TO-END ON PURPOSE. This drives the REAL bin/promote-released-cards over a stubbed `curl`,
# not a stub promoter: the two halves agree via a flag name and a WARNING line format, and a
# hand-written stub would pin release-pr-body to a format promote could then change freely.
# The only thing that varies between the two arms is WHICH CARDS THE BOARD HOLDS.
COV="$T/cov"; mkdir -p "$COV"
g init -q "$COV/repo"; CR="$COV/repo"
echo one > "$CR/f"; g -C "$CR" add f; g -C "$CR" commit -qm "chore: init"; g -C "$CR" tag v0.1.0
echo two > "$CR/f"; g -C "$CR" commit -qam "feat: a thing (card#9999) (#42)"

mkdir -p "$COV/bin"
# `curl` stand-in: serves $BOARD_FILE on the paged GET. A PATCH must never happen on this path
# (--dry-run), so it exits non-zero rather than succeeding quietly — a move here would otherwise
# be invisible to a section that only reads the report.
cat > "$COV/bin/curl" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in -X) echo "selftest curl stub: unexpected write on a dry-run path" >&2; exit 9 ;; esac; done
cat "$BOARD_FILE"
STUB
chmod +x "$COV/bin/curl"

cat > "$CR/.release-pr.json" <<'EOF'
{
  "ref_token_regex": "DL-[0-9]+",
  "card_token_regex": "card#[0-9]+",
  "promote": { "board_id": 12, "released_stage_id": 85, "api_base": "https://kanban.test/api/v3" }
}
EOF

export BOARD_FILE="$COV/board.json"
# coverage_body — the whole body, generated with the real promote tool reachable on PATH.
coverage_body() {
  ( cd "$CR" \
    && PATH="$COV/bin:$HERE/../bin:$PATH" \
       KANBAN_WRITEBACK_TOKEN=tkn KANBAN_EXPECTED_HOST=kanban.test \
       "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD 2>/dev/null )
}

# PROVE-IT-CAN-FAIL: card#9999 is shipped in the range and the board holds no such card.
cat > "$BOARD_FILE" <<'EOF'
{"data":[{"id":42,"workflow_stage_id":51,"payload":{"dl_number":"DL-42"}}],"meta":{"last_page":1,"total":1}}
EOF
covmiss="$(coverage_body)"
eq "an uncarded card# ref is REPORTED"                "true"  "$(has '**Shipped refs with no tracking card:** card#9999' "$covmiss")"
# The presence of the heading is now itself the claim that a measurement ran (card#7038), so
# that is what this arm asserts. It replaces a `has 'Not checked here'` == false line: that
# string no longer exists anywhere in the tool, and this arm supplies a board token, so it
# could not have failed in either direction — a decoration, not a check.
eq "…and the section is there because it MEASURED"    "true"  "$(has '## Card coverage' "$covmiss")"
eq "…nor the pre-fix false-clean short-circuit"       "false" "$(has 'No shipped refs in range' "$covmiss")"
# The id-space confusion the second key exists to prevent, asserted rather than described: the
# board's only card carries DL-42, and 42 is NOT what card#9999 asks about.
eq "the unrelated DL-42 card is not read as coverage" "false" "$(has 'card#42' "$covmiss")"

# CONTROL: same tool, same range, same config — the board now holds card 9999. Without this the
# assertions above are satisfied by a section that reports every ref unconditionally.
cat > "$BOARD_FILE" <<'EOF'
{"data":[{"id":42,"workflow_stage_id":51,"payload":{"dl_number":"DL-42"}},
         {"id":9999,"workflow_stage_id":51,"payload":{}}],"meta":{"last_page":1,"total":2}}
EOF
covok="$(coverage_body)"
eq "control: a carded ref reports clean"              "true"  "$(has 'All shipped refs have a tracking card' "$covok")"
eq "control: nothing is reported missing"             "false" "$(has 'no tracking card' "$covok")"

echo "== the coverage section is EMITTED ONLY when it carries a measurement (card#7038) =="
# WHAT CHANGED. The section used to render unconditionally, and when it could not check
# anything it SAID so — a heading whose entire content was "not checked here, go run another
# tool". That is a placeholder, not a measurement: it tells the merger nothing about what the
# merge contains, and it was struck BY HAND from a real release PR body — which does not hold,
# because the next release re-emits it. The section is now emitted only when the check ran, so
# its PRESENCE is itself the signal that coverage was measured. The obligation it used to
# narrate is stated in the release docs instead (`VERSIONING.md` § Release flow, and
# `docs/INSTALL.md` §4 for consumers), where a reader looks for release process.
#
# Each arm removes exactly ONE leg of the can-we-measure guard and holds the range, the commit
# subjects and the token keys constant. `$covok` above — same fixture, every leg present — is
# the positive control: it DOES emit the section, carrying a verdict.
eq "control: every leg present ⇒ the section IS emitted" "true" "$(has '## Card coverage' "$covok")"
eq "control: …carrying a verdict, not a placeholder"     "true" "$(has 'All shipped refs have a tracking card' "$covok")"

# LEG 1 — no board token. This is the historical case, not a hypothetical: every other block in
# this file runs without one, which is why they all used to render the placeholder branch.
#
# The token is EMPTIED here rather than inherited, for the same reason LEG 2 below derives its
# own PATH: an arm must not take the property it isolates from the runner. An ambient token
# turns this silently into the MEASURED case — the section IS emitted and the arm reds — and
# `VERSIONING.md` § Release flow has the releaser export one while preparing a release body, so
# a seat running this suite around a release does carry one. Asserted, not assumed.
eq "precondition: no board token reaches the arm" "" \
   "$( PATH="$COV/bin:$HERE/../bin:$PATH" KANBAN_WRITEBACK_TOKEN= KANBAN_EXPECTED_HOST=kanban.test \
       sh -c 'printf %s "${KANBAN_WRITEBACK_TOKEN-}"' )"
rc=0; notoken="$( cd "$CR" \
  && PATH="$COV/bin:$HERE/../bin:$PATH" KANBAN_WRITEBACK_TOKEN= KANBAN_EXPECTED_HOST=kanban.test \
     "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD 2>/dev/null )" || rc=$?
eq "no board token → still rc 0"                  "0"     "$rc"
eq "…body is still complete (no token)"           "true"  "$(has '## Bundled' "$notoken")"
eq "…and NO coverage section is emitted (no token)"       "false" "$(has '## Card coverage' "$notoken")"
eq "…nor the placeholder it used to carry"        "false" "$(has 'Not checked here' "$notoken")"

# LEG 2 — the promote tool is unreachable. The bin is run from a directory of its own, so
# neither `command -v` nor the `dirname "$0"` sibling lookup finds a promoter; the board token
# and the `.promote` config are both present, so this leg alone decides the outcome.
#
# The PATH is DERIVED, not inherited: a developer host commonly has the toolkit installed on
# `~/.local/bin`, so `PATH="$COV/bin:$PATH"` still resolves a promoter and this arm passes for
# the wrong reason locally while discriminating on a bare CI runner (observed, on this arm's
# first run). Drop exactly the directories that carry the property under test, and assert the
# precondition rather than assuming it.
promoterless_path() {  # $PATH minus every directory that holds a promote-released-cards
  local out="" d; local IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    # a plain `if`, not `[ -e … ] && continue`: this file already rules against the
    # trailing-test form (card#5874, in bin/release-pr-body's own comment).
    if [ -e "$d/promote-released-cards" ]; then continue; fi
    out="${out:+$out:}$d"
  done
  printf '%s' "$out"
}
NOPROM_PATH="$COV/bin:$(promoterless_path)"
eq "precondition: no promoter on the derived PATH" "" \
   "$(PATH="$NOPROM_PATH" command -v promote-released-cards 2>/dev/null || true)"
mkdir -p "$COV/lonebin"; cp "$BIN" "$COV/lonebin/release-pr-body"
rc=0; nopromote="$( cd "$CR" \
  && PATH="$NOPROM_PATH" KANBAN_WRITEBACK_TOKEN=tkn KANBAN_EXPECTED_HOST=kanban.test \
     "$COV/lonebin/release-pr-body" --version 0.2.0 --base v0.1.0 --head HEAD 2>/dev/null )" || rc=$?
eq "no promote tool → still rc 0"                 "0"     "$rc"
eq "…body is still complete (no promoter)"        "true"  "$(has '## Bundled' "$nopromote")"
eq "…and NO coverage section is emitted (no promoter)"    "false" "$(has '## Card coverage' "$nopromote")"
# CONTROL for this leg: the SAME lone copy with the promoter back on PATH does emit — so the
# absence above is the missing promoter, not "a copy outside bin/ cannot check anything".
withpromote="$( cd "$CR" \
  && PATH="$HERE/../bin:$NOPROM_PATH" KANBAN_WRITEBACK_TOKEN=tkn KANBAN_EXPECTED_HOST=kanban.test \
     "$COV/lonebin/release-pr-body" --version 0.2.0 --base v0.1.0 --head HEAD 2>/dev/null )"
eq "control: the same copy WITH a promoter emits" "true"  "$(has '## Card coverage' "$withpromote")"

# LEG 3 — no `.promote` config. Handed over as a sibling --config so the fixture repo's own
# config, which every later block reads, is left exactly as it is.
jq 'del(.promote)' "$CR/.release-pr.json" > "$COV/nopromote.json"
rc=0; nocfg="$( cd "$CR" \
  && PATH="$COV/bin:$HERE/../bin:$PATH" KANBAN_WRITEBACK_TOKEN=tkn KANBAN_EXPECTED_HOST=kanban.test \
     "$BIN" --config "$COV/nopromote.json" --version 0.2.0 --base v0.1.0 --head HEAD 2>/dev/null )" || rc=$?
eq "no .promote config → still rc 0"              "0"     "$rc"
eq "…body is still complete (no .promote)"        "true"  "$(has '## Bundled' "$nocfg")"
eq "…and NO coverage section is emitted (no .promote)"    "false" "$(has '## Card coverage' "$nocfg")"

echo "== the card manifest + footer carry BARE ids, and the bundled list shows the token =="
# The DL side upper-cases every token to fold dl-1/DL-1; applied to a card token that reaches a
# consumer as CARD#9999. Card ids are emitted as bare integers instead — there is no spelling to
# fold, and the id space is what a consumer correlates on.
cardman="$( (cd "$CR" && "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD --card-manifest) 2>/dev/null )"
eq "--card-manifest prints the bare id"          "9999"  "$cardman"
eq "--manifest is unchanged (DL side, no match)" ""      "$( (cd "$CR" && "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD --manifest) 2>/dev/null )"
eq "the footer carries the bare id"              "true"  "$(has '<!-- release-manifest:shipped-cards=9999 -->' "$covok")"
eq "…and never the case-folded token spelling"   "false" "$(has 'CARD#9999' "$covok")"
eq "the bundled line shows the card token"       "true"  "$(has '(`card#9999`)' "$covok")"

# The id is the token's TRAILING digit run, per matched token. `card_token_regex` is
# operator-supplied and need not be `card#…`; a prefix carrying its own digits makes a
# stream-wide `grep -oE '[0-9]+'` yield an extra id that belongs to an unrelated card.
# Only the regex varies here — the fixture's subject and range are held constant.
python3 - "$CR/.release-pr.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["card_token_regex"] = "PROJ2-card#[0-9]+"
json.dump(d, open(p, "w"), indent=2)
PY
g -C "$CR" commit -q --allow-empty -m "feat: a prefixed token (PROJ2-card#77) (#43)"
eq "a digit-bearing token prefix yields ONE id" "77" \
   "$( (cd "$CR" && "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD --card-manifest) 2>/dev/null )"
g -C "$CR" reset -q --hard HEAD~1
# Put the fixture's spelling back — `reset --hard` does not touch this file (it is written,
# never committed), and leaving the prefixed regex in place makes every later card-manifest
# read answer "" for a reason unrelated to what is being asserted.
python3 - "$CR/.release-pr.json" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["card_token_regex"] = "card#[0-9]+"
json.dump(d, open(p, "w"), indent=2)
PY

echo "== the two query modes refuse to answer a question that was not asked =="
# Each mode REPLACES the body with one list, so accepting both would print one and drop the
# other in silence — the card#5429 shape (an argument read, then discarded, at rc 0), and
# worse here because the output is machine-read.
# --base is passed so the baseline FETCH is skipped: this fixture repo has no origin, and a
# fetch failure is also rc 2 — without it the rc assertion passes for the wrong reason and
# stays green with the guard removed (observed).
rc=0; xerr="$( (cd "$CR" && "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD --manifest --card-manifest) 2>&1 )" || rc=$?
eq "--manifest --card-manifest → rc 2"           "2"     "$rc"
eq "…and names the conflict"                     "true"  "$(has 'mutually exclusive' "$xerr")"
eq "…printing neither list"                      "false" "$(has '9999' "$xerr")"
# CONTROL — each flag ALONE on the same invocation still answers, so the rc above is the
# guard's and not "this invocation cannot run".
eq "control: --card-manifest alone still answers" "9999" \
   "$( (cd "$CR" && "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD --card-manifest) 2>/dev/null )"

echo "== a repo that sets NEITHER token key still renders (no new required config) =="
cat > "$CR/.release-pr.json" <<'EOF'
{ "promote": { "board_id": 12, "released_stage_id": 85, "api_base": "https://kanban.test/api/v3" } }
EOF
rc=0; notok="$(coverage_body)" || rc=$?
eq "no token keys → still rc 0"                  "0"     "$rc"
eq "…body is complete"                           "true"  "$(has '## Bundled' "$notok")"
eq "…and the coverage section is omitted whole"  "false" "$(has '## Card coverage' "$notok")"
unset BOARD_FILE

echo "== the artifacts checklist RENDERS, with {{version}} expanded (card#7038 instance 3) =="
# `artifacts` was a declared OUTPUT with no assertion of effect: wrapping the whole
# `## Release artifacts` block in `if false;` left this entire suite green. Nothing anywhere
# covered it — `release-artifacts-selftest.sh` drives `bin/release-artifacts-check`, a DIFFERENT
# tool (the asserter, not this printer), and never runs this bin at all.
#
# The LAST member is asserted alongside the first, so a render that stops after one entry reds
# rather than passing on a prefix; and the raw placeholder is asserted ABSENT, so dropping the
# template expansion reds too instead of shipping `{{version}}` into a release PR body.
cat > "$CR/.release-pr.json" <<'EOF'
{
  "ref_token_regex": "DL-[0-9]+",
  "artifacts": [
    "VERSION → {{version}}",
    "docs/CHANGELOG.md → [{{version}}] section",
    "README.md § Recent releases row"
  ]
}
EOF
rc=0; arts="$( (cd "$CR" && "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD) 2>/dev/null )" || rc=$?
eq "artifacts config → rc 0"                      "0"     "$rc"
eq "the checklist section is rendered"            "true"  "$(has '## Release artifacts' "$arts")"
eq "…first member, {{version}} expanded"          "true"  "$(has '- [ ] VERSION → 0.2.0' "$arts")"
eq "…a member templated mid-string"               "true"  "$(has '- [ ] docs/CHANGELOG.md → [0.2.0] section' "$arts")"
eq "…and the LAST member, verbatim"               "true"  "$(has '- [ ] README.md § Recent releases row' "$arts")"
eq "…no raw {{version}} placeholder survives"     "false" "$(has '{{version}}' "$arts")"

# CONTROL — same tool, same range, the same config minus `artifacts`. Without this arm the
# assertions above are equally satisfied by a generator that prints the section unconditionally,
# and emitting it only when the key is declared is a behaviour in its own right.
# The config is DERIVED from the one above by deleting exactly the key under test and handed
# over as a sibling --config, so the two arms cannot drift the way a second hand-written fixture
# would; nothing after this block reads the fixture repo's own config.
jq 'del(.artifacts)' "$CR/.release-pr.json" > "$COV/noartifacts.json"
rc=0; noarts="$( (cd "$CR" && "$BIN" --config "$COV/noartifacts.json" \
                   --version 0.2.0 --base v0.1.0 --head HEAD) 2>/dev/null )" || rc=$?
eq "control: no artifacts key → rc 0"             "0"     "$rc"
eq "control: …body is still complete"             "true"  "$(has '## Bundled' "$noarts")"
eq "control: …and NO artifacts section is emitted" "false" "$(has '## Release artifacts' "$noarts")"

echo "== value-taking flags reject an EMPTY value (card#5146) =="
# `--base ""` previously fell through to deriving the baseline from LOCAL tags — the exact
# reading this tool takes pains to make explicit, silently substituted for the one the caller
# named. Every value-taking flag now dies by name instead.
# The population is DERIVED from the bin, not typed here (card#6645). A hand list cannot go red
# when the bin grows a flag, so a totality claim made over one narrows silently with every
# release — measured on this repo: `promote-stage-guard-selftest` named five of
# `promote-released-cards`' six guarded flags for two minor versions under the same claim.
# `expect_value_flags` compares the list below against the bin's own guard call sites and reds
# in both directions, so this block's claim cannot outlive the population it is about.
VALUE_FLAGS=(--version --base --head --config)
expect_value_flags "$BIN" "${VALUE_FLAGS[@]}"
for f in "${VALUE_FLAGS[@]}"; do
    rc=0; err="$("$BIN" "$f" "" 2>&1)" || rc=$?
    eq "$f \"\" → rc 2"           "2"    "$rc"
    eq "$f \"\" names the flag"   "true" "$(case "$err" in *"$f requires a non-empty value"*) echo true ;; *) echo false ;; esac)"
done
rc=0; err="$("$BIN" --base 2>&1)" || rc=$?
eq "trailing --base → rc 2"                   "2"     "$rc"
eq "trailing --base does not leak set -u"     "false" "$(case "$err" in *'unbound variable'*) echo true ;; *) echo false ;; esac)"

echo "== --tag prints just the tag name, without touching the network (card#7203) =="
# `tag_format` had ONE reader — this tool — and `bin/release-tag-check` needed the same answer,
# so it hardcoded `v${VERSION}` and polled for a tag that cannot exist under any other scheme.
# `--tag` is how that second caller asks the owner instead of carrying a second copy of the
# mapping, and it must answer WITHOUT the baseline fetch below it: the caller is a CI gate whose
# whole job is to survive a remote it may not be able to read.
tokencfg 'DL-[0-9]+'   # config still carries tag_format: release-{{version}}
rc=0; tagout="$( (cd "$W" && "$BIN" --tag --version 0.3.0) 2>&1 )" || rc=$?
eq "--tag → rc 0"                            "0"                "$rc"
eq "…prints the tag_format tag, alone"       "release-0.3.0"    "$tagout"

# THE NO-NETWORK PROPERTY, MEASURED rather than asserted from reading: origin is repointed at a
# path that is not a repository, which makes the baseline fetch fail HARD (the tool's documented
# fail-loud). `--tag` must still answer.
g -C "$W" remote set-url origin "$T/no-such-origin.git"
rc=0; tagout2="$( (cd "$W" && "$BIN" --tag --version 0.3.0) 2>&1 )" || rc=$?
eq "--tag answers with origin unreachable"   "0"                "$rc"
eq "…with the same tag"                      "release-0.3.0"    "$tagout2"
# CONTROL — the SAME invocation without --tag must fail on that unreachable origin, or the arm
# above proves nothing about the early return (it would pass for a tool that never fetches).
rc=0; out="$( (cd "$W" && "$BIN" --version 0.3.0) 2>&1 )" || rc=$?
eq "control: a full body on the same remote fails" "2"          "$rc"
eq "control: …because the baseline fetch is fatal" "true"       "$(has 'cannot fetch origin' "$out")"
g -C "$W" remote set-url origin "$T/origin.git"

# The DEFAULT scheme is unchanged: no key ⇒ v<version>. A fixture that sets a key to its own
# default cannot discriminate, so both spellings are driven — absent, and explicitly-default.
cat > "$W/.release-pr.json" <<'EOF'
{ "ref_token_regex": "DL-[0-9]+" }
EOF
eq "control: no tag_format ⇒ v<version>"     "v0.3.0"           "$( (cd "$W" && "$BIN" --tag --version 0.3.0) 2>&1 )"
cat > "$W/.release-pr.json" <<'EOF'
{ "ref_token_regex": "DL-[0-9]+", "tag_format": "{{version}}" }
EOF
eq "an unprefixed scheme ⇒ the bare version" "0.3.0"            "$( (cd "$W" && "$BIN" --tag --version 0.3.0) 2>&1 )"

# The version may also come from version_file+version_regex, which is the path a caller with no
# --version takes.
cat > "$W/.release-pr.json" <<'EOF'
{ "ref_token_regex": "DL-[0-9]+", "version_file": "VERSION", "version_regex": "[0-9]+\\.[0-9]+\\.[0-9]+", "tag_format": "release-{{version}}" }
EOF
printf '0.9.9\n' > "$W/VERSION"
eq "…and --tag resolves it from version_file" "release-0.9.9"   "$( (cd "$W" && "$BIN" --tag) 2>&1 )"

echo "== the query modes are mutually exclusive, COUNTED not pairwise =="
# Each mode replaces the whole output with one answer, so any two means one is silently lost.
# The check was a single `--manifest && --card-manifest` test; with a third mode a pairwise
# test admits exactly the combination nobody wrote down.
for pair in "--tag --manifest" "--tag --card-manifest" "--manifest --card-manifest"; do
  # shellcheck disable=SC2086  # the pair IS two arguments
  rc=0; err="$( (cd "$W" && "$BIN" $pair --version 0.3.0) 2>&1 )" || rc=$?
  eq "$pair → rc 2"                          "2"                "$rc"
  eq "…naming both modes"                    "true"             "$(has 'mutually exclusive query modes' "$err")"
done
# CONTROL — one mode alone is accepted, so the refusal above is about the COMBINATION.
rc=0; (cd "$W" && "$BIN" --tag --version 0.3.0) >/dev/null 2>&1 || rc=$?
eq "control: one mode alone is fine"         "0"                "$rc"

_summary "release-pr-body-selftest"
