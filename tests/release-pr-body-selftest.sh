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
eq "…rather than an empty card manifest at rc 0"   "true"  "$(has "--head '$badhead'" "$bhc")"

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

echo "== version_extract_cmd: the repo's own extractor answers, and the config regex stops being one (card#7599) =="
# THE INCIDENT, REPRODUCED RATHER THAN DESCRIBED. kanban-board declares its version INSIDE
# `config/app.php`, so its `version_regex` has to match the surrounding context to pick the
# number out of the file at all — and `grep -oiE` returns the WHOLE match. `$VERSION` became
# the string `'version' => '0.43.0'` and the release PR's scope line rendered
# `release PR — v'version' => '0.43.0'.` The fixture below is that config verbatim.
#
# The key does NOT add a second way to say what version_regex says. That repo ALREADY had a
# correct extractor — `bin/extract-version.sh`, which its `auto-tag-version.yml` mints the
# release TAG from — so the question had two implementations and the cosmetic one was the
# wrong one. These cases pin that the config can now name the authoritative one.
mkdir -p "$W/config" "$W/xbin"
printf "<?php\nreturn [\n    'name' => 'App',\n    'version' => '0.43.0',\n];\n" > "$W/config/app.php"
# A stand-in for the consumer's own extractor: same shape as the real one (a `#!` script that
# prints one line), and it is the FIXTURE's, so no other repo's file is read.
_xscript() { # <path> <body-line...>
  local p="$W/$1"; shift
  mkdir -p "$(dirname "$p")"
  { printf '#!/usr/bin/env bash\n'; printf '%s\n' "$@"; } > "$p"
  chmod +x "$p"
}
_xscript xbin/extract-version.sh 'printf "%s\n" 0.43.0'

# _xcfg [version_extract_cmd] — the kanban-shaped config, with the key only when one is given.
# The ABSENT spelling is a real case, not a formality: it is the byte-identity control for
# every consumer that never sets the key.
_xcfg() {
  { printf '{ "ref_token_regex": "DL-[0-9]+", "version_file": "config/app.php",'
    printf ' "version_regex": "%s",' "'version' => '[0-9.]+'"
    [ -z "${1:-}" ] || printf ' "version_extract_cmd": "%s",' "$1"
    printf ' "artifacts": ["config/app.php \\u2192 {{version}}"] }\n'
  } > "$W/.release-pr.json"
}
_xbody() { # → the whole body, or "rc=N"
  local b rc=0
  b="$( (cd "$W" && "$BIN") 2>/dev/null )" || rc=$?
  if [[ "$rc" -ne 0 ]]; then printf 'rc=%s\n' "$rc"; else printf '%s\n' "$b"; fi
}
_xerr() { # → "rc=N|<stderr+stdout>" for the refusal cases
  local o rc=0
  o="$( (cd "$W" && "$BIN" --tag) 2>&1 )" || rc=$?
  printf 'rc=%s|%s\n' "$rc" "$o"
}

# (1) CONTROL — with NO key, resolution is exactly what it always was, malformation included.
# This asserts the defect's own output on purpose: it is what proves the fallback path was not
# touched, and it is the line that would red if the fix had "helpfully" narrowed the regex path.
_xcfg
contains "no key ⇒ the version_regex path is unchanged, whole match and all" \
  "$(printf '%s\n' "$(_xbody)" | head -1)" "release PR — v'version' => '0.43.0'.**"

# (2) THE FIX — the config names the repo's own extractor and its stdout IS the version.
_xcfg xbin/extract-version.sh
xbody="$(_xbody)"; xhdr="$(printf '%s\n' "$xbody" | head -1)"
contains     "the extractor's answer is the version"      "$xhdr" "release PR — v0.43.0.**"
not_contains "…and the matched context is gone from it"   "$xhdr" "'version' =>"

# (3) …and it reaches the OTHER consumers of \$VERSION, not just the header: the artifact
# checklist's {{version}} expansion and the tag name. A fix that only corrected the scope line
# would leave both rendering the malformed string.
contains "the artifact checklist expands with it" "$xbody" '- [ ] config/app.php → 0.43.0'
eq       "--tag maps it through tag_format"       "v0.43.0" "$( (cd "$W" && "$BIN" --tag) 2>&1 )"

# (4) THE COMMAND IS THE SOURCE, not a narrowed regex. Cases 2-3 use an extractor that agrees
# with the file, which is the real consumer's shape — but agreement is exactly what makes them
# unable to tell "the command answered" from "the regex was quietly fixed". This one disagrees.
_xscript xbin/other.sh 'printf "%s\n" 9.9.9'
_xcfg xbin/other.sh
eq "the command WINS over version_regex, and its value is what renders" "v9.9.9" \
   "$( (cd "$W" && "$BIN" --tag) 2>&1 )"

# (5) `--version` REMAINS A COMPLETE BYPASS — the documented workaround for the incident, and
# the escape hatch for a repo whose extractor is itself broken. The marker file is what makes
# "not used" distinguishable from "used and overridden": the command is never RUN at all.
_xscript xbin/marker.sh 'touch xbin/RAN' 'printf "%s\n" 1.1.1'
rm -f "$W/xbin/RAN"
_xcfg xbin/marker.sh
eq "--version beats version_extract_cmd"     "v3.2.1" "$( (cd "$W" && "$BIN" --tag --version 3.2.1) 2>&1 )"
eq "…and the command was not run at all"     "false"  "$([[ -e "$W/xbin/RAN" ]] && echo true || echo false)"

# (6) NO $PATH SEARCH. A value with no `/` is the repo's own file or nothing: resolved via
# $PATH, a same-named script anywhere on it would answer for this repo — silently, and with a
# value that looks exactly like a real one. The decoy is on PATH and is what a lookup WOULD
# find, asserted rather than assumed, so this case cannot pass by the decoy being unreachable.
mkdir -p "$T/decoybin"
{ printf '#!/usr/bin/env bash\nprintf "%%s\\n" 6.6.6\n'; } > "$T/decoybin/repo-version.sh"
chmod +x "$T/decoybin/repo-version.sh"
_xscript repo-version.sh 'printf "%s\n" 0.43.0'
_xcfg repo-version.sh
eq "control: the decoy IS what \$PATH resolves that name to" "$T/decoybin/repo-version.sh" \
   "$( PATH="$T/decoybin:$PATH"; command -v repo-version.sh )"
eq "a bare name runs the REPO's file, never \$PATH's" "v0.43.0" \
   "$( cd "$W" && PATH="$T/decoybin:$PATH" "$BIN" --tag 2>&1 )"

# (7) THE REFUSALS. Each is rc 2 with a message naming the value — and each is a case the
# pre-fix tool answered rc 0 by ignoring the key and falling back to the regex, i.e. by
# rendering the malformed version the key exists to remove. A silent fall-back is precisely
# what must not happen: this key is set BECAUSE the fallback answers differently.
_xcfg /etc/hostname
xr="$(_xerr)"
eq       "an absolute path is refused"       "rc=2" "${xr%%|*}"
contains "…naming why"                       "$xr"  "is an absolute path"

_xcfg ../evil.sh
xr="$(_xerr)"
eq       "a '..' component is refused"       "rc=2" "${xr%%|*}"
contains "…naming why"                       "$xr"  "has a '..' path component"

_xcfg xbin/nope.sh
xr="$(_xerr)"
eq       "a path naming no file is refused"  "rc=2" "${xr%%|*}"
contains "…naming why"                       "$xr"  "is not a file here"

_xscript xbin/noexec.sh 'printf "%s\n" 0.43.0'
chmod -x "$W/xbin/noexec.sh"
_xcfg xbin/noexec.sh
xr="$(_xerr)"
eq       "a non-executable file is refused"  "rc=2" "${xr%%|*}"
contains "…naming the fix"                   "$xr"  "chmod +x"

# NO SHELL — the value is an argv[0], not a command line. Arguments, a redirection and a
# pipeline are each refused as "no such file", and the redirection's target is asserted absent:
# an implementation that ran this through `sh -c` would create it while still looking correct.
rm -f "$W/pwned"
for xv in 'xbin/extract-version.sh --verbose' 'xbin/extract-version.sh > pwned' 'xbin/extract-version.sh | head -1'; do
  _xcfg "$xv"
  xr="$(_xerr)"
  eq       "no shell: '$xv' is refused"      "rc=2" "${xr%%|*}"
  contains "…as a path, not a command line"  "$xr"  "is not a file here"
done
eq "…and the redirection target was never created" "false" \
   "$([[ -e "$W/pwned" ]] && echo true || echo false)"

# The command's own failure is FATAL, never a fall-back: the regex is what this key overrides,
# so quietly answering with it would restore the divergence. Its stderr reaches the caller.
_xscript xbin/fails.sh 'echo "the extractor could not read the version" >&2' 'exit 3'
_xcfg xbin/fails.sh
xr="$(_xerr)"
eq       "a failing extractor is fatal"                 "rc=2" "${xr%%|*}"
contains "…naming its exit status"                      "$xr"  "exited 3"
contains "…and its own message is passed through"       "$xr"  "could not read the version"
not_contains "…and it does NOT fall back to the regex"  "$xr"  "'version' => '0.43.0'"

# Empty and multi-line stdout are the two answers that are not a version at all. Both would
# otherwise be rendered, silently, into the scope header AND the tag name.
_xscript xbin/silent.sh 'exit 0'
_xcfg xbin/silent.sh
xr="$(_xerr)"
eq       "empty stdout is refused"           "rc=2" "${xr%%|*}"
contains "…naming why"                       "$xr"  "printed nothing on stdout"

_xscript xbin/chatty.sh 'printf "%s\n" 0.43.0' 'printf "%s\n" "and a second line"'
_xcfg xbin/chatty.sh
xr="$(_xerr)"
eq       "multi-line stdout is refused"      "rc=2" "${xr%%|*}"
contains "…naming why"                       "$xr"  "printed more than one line"

# CONTROL for the whole refusal battery: the same fixture with a WORKING extractor is rc 0, so
# the rc 2s above are attributable to each value under test and not to the fixture.
_xcfg xbin/extract-version.sh
eq "control: the same fixture with a good extractor is rc 0" "rc=0|v0.43.0" "$(_xerr)"

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

echo "== an EMPTY manifest over a NON-EMPTY range is a FINDING, not silence (card#8538) =="
# WHAT WAS SILENT. The two arms directly above pin that a no-match range still exits 0 and
# "simply carries no manifest footer" — correct, and exactly the hole: an omitted footer and a
# footer whose range legitimately had nothing to say are the SAME bytes to every reader of this
# body. Measured on a real release: a consumer whose `card_token_regex` was absent got 0
# `shipped-cards` lines over a range carrying eight card ids, at rc 0, under a `## Card
# coverage` section reading "All shipped refs have a tracking card" (card#8423). The run now
# says which of the two it is — on STDERR, as `release-pr-body: correlation gap:` lines, since
# DL-224 moved builder diagnostics out of the installer-facing body (card#9248). It still exits
# 0 — this tool GENERATES the release PR body, and a non-zero would block the very PR the
# finding is written for.
gapcfg() { printf '%s\n' "$1" > "$W/.release-pr.json"; }
gapbody() { rc=0; GAPBODY="$( (cd "$W" && "$BIN" --version 0.3.0) 2>"$T/gap.err" )" || rc=$?; GAPERR="$(cat "$T/gap.err")"; }

# A: BOTH keys declared, only one yields — the half-empty case, and the one the card names.
gapcfg '{ "ref_token_regex": "DL-[0-9]+", "card_token_regex": "card#[0-9]+", "tag_format": "release-{{version}}" }'
gapbody
eq "a declared key matching nothing still exits 0"   "0"     "$rc"
eq "…and stderr carries a correlation-gap report"   "true"  "$(has 'release-pr-body: correlation gap: ' "$GAPERR")"
eq "…naming the key that matched nothing"            "true"  "$(has '`card_token_regex` is declared' "$GAPERR")"
eq "…and saying WHICH manifest is empty"             "true"  "$(has 'The `shipped-cards` manifest is EMPTY' "$GAPERR")"
eq "…while the key that DID yield is not named"      "false" "$(has '`ref_token_regex` is declared (`DL-[0-9]+`) and matched no' "$GAPERR")"
eq "…the strong headline does NOT fire (one key yielded)" "false" "$(has 'NOTHING in' "$GAPERR")"
eq "…and the BODY carries none of it"                "false" "$(has 'card_token_regex' "$GAPBODY")"
eq "…the shipped-refs footer is still emitted"       "true"  "$(has 'release-manifest:shipped-refs=DL-2' "$GAPBODY")"

# B: NEITHER key yields — the strong shape. Both manifests empty, so the run correlates
# nothing at all, and an UNDECLARED key becomes a finding too (it is not one when the other
# key yields — a repo that uses one spelling is not owed a warning about the other).
gapcfg '{ "ref_token_regex": "card#[0-9]+", "tag_format": "release-{{version}}" }'
gapbody
eq "nothing correlated → still rc 0"                 "0"     "$rc"
eq "…the headline names the range and its size"      "true"  "$(has 'NOTHING in' "$GAPERR")"
eq "…the DECLARED key that matched nothing is named" "true"  "$(has '`ref_token_regex` is declared' "$GAPERR")"
eq "…and the UNDECLARED one is named as undeclared"  "true"  "$(has '`card_token_regex` is not declared' "$GAPERR")"
# THE HEADLINE USED TO ASSERT ANOTHER TOOL'S BEHAVIOUR, FALSELY (card#9248). It said "no card can
# be promoted from this release" — but `bin/promote-released-cards`, in this same repo, derives
# its shipped refs from `git log <base>..<head>` and never reads a manifest, so cards ARE promoted
# from a range this headline called unpromotable. It now says only what this generator
# establishes. ABSENCE on BOTH streams, plus a PRESENCE witness for the replacement — an
# absence-only arm is satisfied by deleting the headline outright.
eq "…the false promotion claim is gone from stderr"  "false" "$(has 'can be promoted' "$GAPERR")"
eq "…and from the body"                              "false" "$(has 'can be promoted' "$GAPBODY")"
eq "…replaced by what THIS generator establishes"    "true"  "$(has 'the body carries no `release-manifest` footer, and card coverage was not measured here' "$GAPERR")"
eq "…naming what it does NOT establish"              "true"  "$(has 'What a card promoter does with this range is not established here' "$GAPERR")"
eq "…and the headline is NOT in the body"            "false" "$(has 'NOTHING in' "$GAPBODY")"
eq "…nor its 'correlates' wording"                  "false" "$(has 'correlates' "$GAPBODY")"

# C: NEITHER key declared at all — the shape `release-artifacts-check` reds a promoting config
# for, seen from the range's side. A repo with no `.promote` block is outside that check's
# population, so this body is the only surface that can say it.
gapcfg '{ "tag_format": "release-{{version}}" }'
gapbody
eq "neither key declared → still rc 0"               "0"     "$rc"
eq "…both keys are named as undeclared"              "true"  \
   "$( [ "$(has '`ref_token_regex` is not declared' "$GAPERR")" = true ] \
       && [ "$(has '`card_token_regex` is not declared' "$GAPERR")" = true ] && echo true || echo false )"
eq "…and the body is otherwise complete"             "true"  "$(has '## Bundled' "$GAPBODY")"
eq "…the headline fires on stderr"                   "true"  "$(has 'NOTHING in' "$GAPERR")"
eq "…and NOT in the body"                            "false" "$(has 'NOTHING in' "$GAPBODY")"
eq "…nor its 'correlates' wording"                  "false" "$(has 'correlates' "$GAPBODY")"

# NEGATIVE CONTROL 1 — both declared, both yield: NO section at all. Without it every arm above
# is satisfied by a tool that prints the section unconditionally.
# The fixture is NOT mutated to produce this arm: the range's head is resolved from
# `origin/dev`, so a local commit would not enter it, and pushing one would move the commit
# count every later case asserts. The range's one subject is
# `feat: new work for cycle two (#3) DL-2`, so a second key spelled `#[0-9]+` yields `3` off
# the same commit — two keys, two id spaces, both non-empty, which is all this control needs.
gapcfg '{ "ref_token_regex": "DL-[0-9]+", "card_token_regex": "#[0-9]+", "tag_format": "release-{{version}}" }'
gapbody
eq "control: both keys yielding → rc 0"              "0"     "$rc"
eq "control: …and NO correlation-gap report"         "false" "$(has 'correlation gap:' "$GAPERR")"
eq "control: …both footers present"                  "true"  \
   "$( [ "$(has 'shipped-refs=DL-2' "$GAPBODY")" = true ] && [ "$(has 'shipped-cards=3' "$GAPBODY")" = true ] && echo true || echo false )"

# NEGATIVE CONTROL 2 — an EMPTY range says nothing. "No tokens over zero commits" is not a
# finding, and a section that fired there would cry wolf on every no-op range.
gapcfg '{ "ref_token_regex": "ZZZ-[0-9]+", "card_token_regex": "QQQ#[0-9]+", "tag_format": "release-{{version}}" }'
rc=0; (cd "$W" && "$BIN" --version 0.3.0 --base HEAD --head HEAD) >/dev/null 2>"$T/emptyrange.err" || rc=$?
eq "control: an empty range → rc 0"                  "0"     "$rc"
eq "control: …and no correlation-gap report"         "false" "$(has 'correlation gap:' "$(cat "$T/emptyrange.err")")"

echo "== the card-coverage gate can FIRE on a card#-spelled range (card#5877) =="
# WHAT WAS BROKEN. `card_coverage_section` computed its manifest from `ref_token_regex` only,
# and short-circuited on an empty one with a confident `_No shipped DL refs in range._`. This
# repo's commit subjects had migrated to `card#NNNN` while that key still said `DL-`, so the
# manifest was unconditionally empty and the section rendered clean WITHOUT CHECKING — the
# canon-#9 shape, a check that cannot fail. Nothing here exercised it: every case above runs
# without a board token, so before card#7038 they all rendered the "_Not checked here_"
# placeholder branch — and now print no coverage report at all (see the block below).
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
#
# ⚠ IT HONOURS `-o` AND `-w`: `promote-released-cards`' api() no longer leaves the response body
# on stdout (card#9301 — `curl -f` discarded the HTTP error body, so a refusal was unreportable).
# The body now goes to curl's `-o` target and the HTTP status is returned through `-w`, so a stub
# writing to stdout hands the tool an EMPTY board and a status made of JSON — which reds this
# whole section for a reason that has nothing to do with card coverage.
cat > "$COV/bin/curl" <<'STUB'
#!/usr/bin/env bash
ofile=""; wfmt=""; want=""
for a in "$@"; do
  case "$want" in ofile) ofile="$a"; want=""; continue ;; wfmt) wfmt="$a"; want=""; continue ;; esac
  case "$a" in
    -X) echo "selftest curl stub: unexpected write on a dry-run path" >&2; exit 9 ;;
    -o|--output) want=ofile ;;
    -w|--write-out) want=wfmt ;;
  esac
done
if [ -n "$ofile" ]; then cat "$BOARD_FILE" > "$ofile"; else cat "$BOARD_FILE"; fi
[ -n "$wfmt" ] && printf '%s' "${wfmt//'%{http_code}'/200}"
exit 0
STUB
chmod +x "$COV/bin/curl"

cat > "$CR/.release-pr.json" <<'EOF'
{
  "ref_token_regex": "DL-[0-9]+",
  "card_token_regex": "card#[0-9]+",
  "promote": { "board_id": 12, "released_stage_id": 85, "api_base": "https://kanban.test/api/v3", "source": "*" }
}
EOF

export BOARD_FILE="$COV/board.json"
# coverage_body — the whole body on stdout, generated with the real promote tool reachable on
# PATH. The run's stderr — where the coverage report lives since card#9248 — is left in
# $COV/cov.err, because a command substitution cannot hand a second stream back to its caller.
coverage_body() {
  ( cd "$CR" \
    && PATH="$COV/bin:$HERE/../bin:$PATH" \
       KANBAN_WRITEBACK_TOKEN=tkn KANBAN_EXPECTED_HOST=kanban.test \
       "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD 2>"$COV/cov.err" )
}

# PROVE-IT-CAN-FAIL: card#9999 is shipped in the range and the board holds no such card.
cat > "$BOARD_FILE" <<'EOF'
{"data":[{"id":42,"workflow_stage_id":51,"payload":{"dl_number":"DL-42"}}],"meta":{"last_page":1,"total":1}}
EOF
covmiss="$(coverage_body)"; covmisserr="$(cat "$COV/cov.err")"
eq "an uncarded card# ref is REPORTED"                "true"  "$(has '**Shipped refs with no tracking card:** card#9999' "$covmisserr")"
# The presence of the report is itself the claim that a measurement ran (card#7038), so that is
# what this arm asserts — on stderr, where the report lives since card#9248. It replaces a `has 'Not checked here'` == false line: that
# string no longer exists anywhere in the tool, and this arm supplies a board token, so it
# could not have failed in either direction — a decoration, not a check.
eq "…and the report is there because it MEASURED"     "true"  "$(has 'release-pr-body: card coverage: ' "$covmisserr")"
eq "…nor the pre-fix false-clean short-circuit"       "false" "$(has 'No shipped refs in range' "$covmisserr")"
# The id-space confusion the second key exists to prevent, asserted rather than described: the
# board's only card carries DL-42, and 42 is NOT what card#9999 asks about.
eq "the unrelated DL-42 card is not read as coverage" "false" "$(has 'card#42' "$covmisserr")"

# card#11204: `bash -x release-pr-body` must not print the writeback token. The coverage arm tests
# it as `${KANBAN_WRITEBACK_TOKEN:+set}`; the `${…:-}` spelling it replaced traced the value. RED on
# that spelling. CONTROLS: the run was traced, and the coverage report still measured.
covx_tok='FAKE-WRITEBACK-TOKEN-NOT-SECRET-005'
( cd "$CR" && PATH="$COV/bin:$HERE/../bin:$PATH" KANBAN_WRITEBACK_TOKEN="$covx_tok" KANBAN_EXPECTED_HOST=kanban.test \
    bash -x "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD >"$COV/covx.out" 2>"$COV/covx.err" ) || true
eq "bash -x: the writeback token is in neither stream"  "false" "$(has "$covx_tok" "$(cat "$COV/covx.out" "$COV/covx.err")")"
eq "bash -x: control — the run WAS traced"              "true"  "$(grep -q '^+ ' "$COV/covx.err" && echo true || echo false)"
eq "bash -x: control — the coverage report still MEASURED" "true" "$(has 'release-pr-body: card coverage: ' "$(cat "$COV/covx.err")")"

# CONTROL: same tool, same range, same config — the board now holds card 9999. Without this the
# assertions above are satisfied by a section that reports every ref unconditionally.
cat > "$BOARD_FILE" <<'EOF'
{"data":[{"id":42,"workflow_stage_id":51,"payload":{"dl_number":"DL-42"}},
         {"id":9999,"workflow_stage_id":51,"payload":{}}],"meta":{"last_page":1,"total":2}}
EOF
covok="$(coverage_body)"; covokerr="$(cat "$COV/cov.err")"
eq "control: a carded ref reports clean"              "true"  "$(has 'All shipped refs have a tracking card' "$covokerr")"
eq "control: nothing is reported missing"             "false" "$(has 'no tracking card' "$covokerr")"

echo "== a card that EXISTS but carries no by-ref source is NOT reported as cardless (card#8421) =="
# THE DEFECT, END TO END ACROSS THE TWO BINS. Under a repo-qualified `.promote.source`,
# promote-released-cards will not MOVE a ref-matched card whose by-ref source it cannot derive
# — but that card EXISTS and carries the ref. Its DL used to fall into the one `matched NO
# card` WARNING line this section greps, so a release PR body told its author to "Create (or
# correct) a board card" for a card already on the board. The remedy is the opposite one:
# stamp the card that is there. Measured on the pre-fix pair, on exactly this fixture.
#
# EVERY BLOCK ABOVE RUNS UNDER `"source": "*"`, where no card can be unsourced — which is why
# nothing here covered it. This block gets its OWN repo and config so that fixture is untouched.
QC="$COV/qrepo"
g init -q "$QC"
echo one > "$QC/f"; g -C "$QC" add f; g -C "$QC" commit -qm "chore: init"; g -C "$QC" tag v0.1.0
echo two > "$QC/f"; g -C "$QC" commit -qam "feat: a tracked thing (DL-77) (#43)"
echo three > "$QC/f"; g -C "$QC" commit -qam "feat: an untracked thing (DL-99) (#44)"
cat > "$QC/.release-pr.json" <<'EOF'
{
  "ref_token_regex": "DL-[0-9]+",
  "promote": { "board_id": 12, "released_stage_id": 85, "api_base": "https://kanban.test/api/v3", "source": "acme/widget" }
}
EOF
# The board holds card #42 for DL-77 with NO source-yielding field at all. DL-99 is on no card.
cat > "$BOARD_FILE" <<'EOF'
{"data":[{"id":42,"workflow_stage_id":51,"payload":{"dl_number":"DL-77"}}],"meta":{"last_page":1,"total":1}}
EOF
qbody() {  # <head-ref> — the STDERR (where the coverage report lives) for v0.1.0..<head-ref> of the qualified fixture repo
  ( cd "$QC" \
    && PATH="$COV/bin:$HERE/../bin:$PATH" \
       KANBAN_WRITEBACK_TOKEN=tkn KANBAN_EXPECTED_HOST=kanban.test \
       "$BIN" --version 0.2.0 --base v0.1.0 --head "$1" 2>&1 >/dev/null )
}
# ONLY the unsourced ref is shipped, so a body that still says "no tracking card" anywhere is
# the defect, and there is no cardless ref to make the phrase legitimately appear.
qonly="$(qbody HEAD~1)"
eq "the coverage report MEASURED (qualified)"         "true"  "$(has 'release-pr-body: card coverage: ' "$qonly")"
eq "the unsourced ref is NOT called cardless"         "false" "$(has 'no tracking card' "$qonly")"
eq "…so the author is NOT told to create a card"      "false" "$(has 'Create (or correct) a board card' "$qonly")"
eq "…it is reported as a card lacking a SOURCE"       "true"  "$(has 'no by-ref source' "$qonly")"
eq "…naming the ref"                                  "true"  "$(has 'DL-77' "$qonly")"
eq "…and the remedy is to STAMP the existing card"    "true"  "$(has 'kbcard patch --pr-url' "$qonly")"
eq "…and it does not read as all-clear either"        "false" "$(has 'All shipped refs have a tracking card' "$qonly")"
# BOTH kinds at once: the two reports are independent lines, each carrying only its own ref.
qboth="$(qbody HEAD)"
eq "both: the cardless DL-99 IS reported cardless"    "true"  "$(has '**Shipped refs with no tracking card:** DL-99' "$qboth")"
eq "both: …and the unsourced DL-77 is not in it"      "false" "$(has 'no tracking card:** DL-77' "$qboth")"
eq "both: the unsourced line names DL-77"             "true"  "$(has 'no by-ref source:** DL-77' "$qboth")"
eq "both: …and the create-a-card advice IS present"   "true"  "$(has 'Create (or correct) a board card' "$qboth")"
# CONTROL — the SAME repo, the SAME range, the SAME board, under the single-repo DECLARATION.
# Card #42 is attributable there, so DL-77 is simply covered and no second line exists: the
# split above is repo qualification acting, not this fixture being unusual.
# The key is flipped in the repo's OWN config, not handed over as a sibling --config:
# `card_coverage_report` invokes the promoter with no --config at all, so the promoter reads
# `.release-pr.json` from the CWD and a sibling file would leave this control re-running the
# qualified case (observed — it failed for that reason before this line existed).
jq '.promote.source = "*"' "$QC/.release-pr.json" > "$COV/qstar.json"
cp "$COV/qstar.json" "$QC/.release-pr.json"
qstar="$(qbody HEAD~1)"
eq "control: under '*' the same ref reports clean"    "true"  "$(has 'All shipped refs have a tracking card' "$qstar")"
eq "control: …with no unsourced line at all"          "false" "$(has 'no by-ref source' "$qstar")"
# restore the board the blocks below read
cat > "$BOARD_FILE" <<'EOF'
{"data":[{"id":42,"workflow_stage_id":51,"payload":{"dl_number":"DL-42"}},
         {"id":9999,"workflow_stage_id":51,"payload":{}}],"meta":{"last_page":1,"total":2}}
EOF

echo "== the coverage report is EMITTED ONLY when it carries a measurement (card#7038) =="
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
eq "control: every leg present ⇒ the report IS emitted" "true" "$(has 'release-pr-body: card coverage: ' "$covokerr")"
eq "control: …carrying a verdict, not a placeholder"    "true" "$(has 'All shipped refs have a tracking card' "$covokerr")"

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
     "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD 2>"$COV/notoken.err" )" || rc=$?
eq "no board token → still rc 0"                  "0"     "$rc"
eq "…body is still complete (no token)"           "true"  "$(has '## Bundled' "$notoken")"
eq "…and NO coverage report is emitted (no token)"        "false" "$(has 'card coverage:' "$(cat "$COV/notoken.err")")"
eq "…nor the placeholder it used to carry"        "false" "$(has 'Not checked here' "$notoken$(cat "$COV/notoken.err")")"

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
     "$COV/lonebin/release-pr-body" --version 0.2.0 --base v0.1.0 --head HEAD 2>"$COV/nopromote.err" )" || rc=$?
eq "no promote tool → still rc 0"                 "0"     "$rc"
eq "…body is still complete (no promoter)"        "true"  "$(has '## Bundled' "$nopromote")"
eq "…and NO coverage report is emitted (no promoter)"     "false" "$(has 'card coverage:' "$(cat "$COV/nopromote.err")")"
# CONTROL for this leg: the SAME lone copy with the promoter back on PATH does emit — so the
# absence above is the missing promoter, not "a copy outside bin/ cannot check anything".
withpromote="$( cd "$CR" \
  && PATH="$HERE/../bin:$NOPROM_PATH" KANBAN_WRITEBACK_TOKEN=tkn KANBAN_EXPECTED_HOST=kanban.test \
     "$COV/lonebin/release-pr-body" --version 0.2.0 --base v0.1.0 --head HEAD 2>&1 >/dev/null )"
eq "control: the same copy WITH a promoter emits" "true"  "$(has 'card coverage:' "$withpromote")"

# LEG 3 — no `.promote` config. Handed over as a sibling --config so the fixture repo's own
# config, which every later block reads, is left exactly as it is.
jq 'del(.promote)' "$CR/.release-pr.json" > "$COV/nopromote.json"
rc=0; nocfg="$( cd "$CR" \
  && PATH="$COV/bin:$HERE/../bin:$PATH" KANBAN_WRITEBACK_TOKEN=tkn KANBAN_EXPECTED_HOST=kanban.test \
     "$BIN" --config "$COV/nopromote.json" --version 0.2.0 --base v0.1.0 --head HEAD 2>"$COV/nocfg.err" )" || rc=$?
eq "no .promote config → still rc 0"              "0"     "$rc"
eq "…body is still complete (no .promote)"        "true"  "$(has '## Bundled' "$nocfg")"
eq "…and NO coverage report is emitted (no .promote)"     "false" "$(has 'card coverage:' "$(cat "$COV/nocfg.err")")"

echo "== the header's CARD COVERAGE PRECONDITIONS are exactly the gates the function has (card#10039) =="
# The header block above card_coverage_report is the ONE statement of when the report runs, and
# other repos' release docs point at it, so a line there that the function does not evaluate is a
# false contract with readers who were told not to keep a copy. It was: the header said "a
# `.promote` config" while the code tests `.promote.board_id`, and it never named the token-regex
# guard at all. This block reads the DECLARED set out of the bin and drives one falsifier per
# name, so the two cannot drift without a red:
#   * a name declared there with no falsifier here reds the set leg (add its arm below);
#   * a declared precondition the function does NOT evaluate reds its own arm — its falsified run
#     still prints a coverage line;
#   * the all-present control reds if the function grows a gate this fixture does not satisfy.
# That is `declared ⇒ real` only. `real ⇒ declared` is the SOURCE-DERIVED block further down:
# the falsifier table below is only as wide as the header it reads, so a NEW gate the fixture
# happens to satisfy passes every arm here unnoticed — measured, in the r1 review of the PR that
# added this block: `[ -n "${KANBAN_EXPECTED_HOST:-}" ] || return 0` inserted as the function's
# first statement left the whole suite at rc 0.
cov_err() {  # <config> <token> <PATH> <bin> — the run's stderr on stdout
  ( cd "$CR" && PATH="$3" KANBAN_WRITEBACK_TOKEN="$2" KANBAN_EXPECTED_HOST=kanban.test \
      "$4" --config "$1" --version 0.2.0 --base v0.1.0 --head HEAD 2>&1 >/dev/null ) || true
}
_pc_path="$COV/bin:$HERE/../bin:$PATH"
cp "$CR/.release-pr.json" "$COV/pc-all.json"
_pc_declared="$(sed -n 's/^#   precondition: \([a-z-]*\) .*/\1/p' "$BIN" | LC_ALL=C sort | paste -sd' ' -)"
eq "control: every precondition held ⇒ a coverage line" "true" \
   "$(has 'release-pr-body: card coverage: ' "$(cov_err "$COV/pc-all.json" tkn "$_pc_path" "$BIN")")"
for _pc in $_pc_declared; do
  case "$_pc" in
    token-regex)
      jq 'del(.ref_token_regex, .card_token_regex)' "$COV/pc-all.json" > "$COV/pc-f.json"
      _pc_err="$(cov_err "$COV/pc-f.json" tkn "$_pc_path" "$BIN")" ;;
    board-id)
      # The block STAYS — only the key goes. The pre-card#10039 header called this state satisfied.
      jq 'del(.promote.board_id)' "$COV/pc-all.json" > "$COV/pc-f.json"
      eq "precondition board-id: the falsified config still HAS a .promote block" "true" \
         "$(jq 'has("promote")' "$COV/pc-f.json")"
      _pc_err="$(cov_err "$COV/pc-f.json" tkn "$_pc_path" "$BIN")" ;;
    writeback-token)
      _pc_err="$(cov_err "$COV/pc-all.json" "" "$_pc_path" "$BIN")" ;;
    promoter)
      _pc_err="$(cov_err "$COV/pc-all.json" tkn "$NOPROM_PATH" "$COV/lonebin/release-pr-body")" ;;
    *) bad "precondition '$_pc' is declared in the header and has no falsifier in this block"; continue ;;
  esac
  eq "precondition $_pc: falsified alone ⇒ NO coverage line" "false" "$(has 'card coverage:' "$_pc_err")"
done
# The promoter's DISJUNCTION, asserted rather than read: not on PATH, but executable beside the
# script, satisfies it — the half the header used to leave out and `docs/INSTALL.md` said as "on PATH".
mkdir -p "$COV/besidebin"
cp "$BIN" "$COV/besidebin/release-pr-body"
cp "$HERE/../bin/promote-released-cards" "$COV/besidebin/promote-released-cards"
eq "precondition promoter: absent from PATH ..." "" "$(PATH="$NOPROM_PATH" command -v promote-released-cards 2>/dev/null || true)"
eq "... but beside the script ⇒ the report RUNS" "true" \
   "$(has 'release-pr-body: card coverage: ' "$(cov_err "$COV/pc-all.json" tkn "$NOPROM_PATH" "$COV/besidebin/release-pr-body")")"

echo "== ...and the function has no gate the header does not declare (card#10039 review r1) =="
# THE OTHER DIRECTION, and the one that was asserted without a check. The header claims both;
# the block above only holds `declared ⇒ real`. What stood in for `real ⇒ declared` was a
# hand-pinned four-name literal right here — a restatement of the set the header owns, whose
# natural repair on a red is to edit the literal, after which nothing reds at all. It is gone.
# Everything below is RE-DERIVED from the function's own source on every run, and no figure is
# left in the block at all: the degeneracy guards test for EMPTINESS — the extractor stopped
# reading — never for a count of what it should have found.
#
# THE GATE REGION — the function's first line through its last SILENT return, i.e. the last
# `return 0` reached before any `coverage_line` call. Past it the function has measured
# something and every exit says so, which is leg 4's job.
_pc_src="$(_fn_src "$BIN" card_coverage_report)"
_pc_first_print="$(printf '%s\n' "$_pc_src" | { command grep -n 'coverage_line ' || true; } | head -1 | cut -d: -f1)"
[ -n "$_pc_first_print" ] || { bad "gate region: card_coverage_report makes no coverage_line call — the window moved"; _pc_first_print=2; }
_pc_last_gate="$(printf '%s\n' "$_pc_src" | head -n "$((_pc_first_print - 1))" \
                 | { command grep -n 'return 0' || true; } | tail -1 | cut -d: -f1)"
[ -n "$_pc_last_gate" ] || { bad "gate region: no silent return before the first coverage_line — the window moved"; _pc_last_gate=1; }
_pc_region="$(printf '%s\n' "$_pc_src" | head -n "$_pc_last_gate")"
# CONTROLS on the cut itself — without them every leg below could be measuring an empty or a
# runaway window and still agree with a header that says nothing.
eq "gate region: reaches the last silent gate arm"     "true"  "$(has 'KANBAN_WRITEBACK_TOKEN' "$_pc_region")"
eq "gate region: stops before the measured-path tests" "false" "$(has 'dl_manifest' "$_pc_region")"

# LEG 1 — the extractor can read every test in the region. A set comparison is only as good as
# its parser, and an unreadable spelling (`[ -n $x ]`, unquoted) would otherwise contribute no
# subject and pass silently. Openings counted against parsed tests, so it cannot.
_pc_open_n="$(printf '%s\n' "$_pc_region" | { command grep -oE '\[\[? -[a-z] ' || true; } | command grep -c . || true)"
_pc_read_n="$(printf '%s\n' "$_pc_region" | { command grep -oE '\[\[? -[a-z] "[^"]*" \]\]?' || true; } | command grep -c . || true)"
eq "leg 1: every test in the gate region is one this extractor can read" "$_pc_open_n" "$_pc_read_n"

# LEG 2 — every silent return in the region is REACHED through such a test. A gate spelled as a
# command's exit status (`grep -q … || return 0`) has no subject to attribute, so it must red
# rather than be skipped.
_pc_stray=""; _pc_carry=0
while IFS= read -r _pc_line; do
  _pc_t="${_pc_line#"${_pc_line%%[![:space:]]*}"}"
  case "$_pc_t" in ''|'#'*) continue ;; esac
  # `[[ -n "$x" ]]` CONTAINS the substring `[ -n`, so one pattern reads both spellings.
  _pc_has=false; case "$_pc_t" in *'[ -'*) _pc_has=true ;; esac
  case "$_pc_t" in *'return '*)
    { [ "$_pc_has" = true ] || [ "$_pc_carry" = 1 ]; } || _pc_stray="$_pc_stray | $_pc_t" ;;
  esac
  case "$_pc_t" in
    fi|fi\ *|'}') _pc_carry=0 ;;
    if\ *|elif\ *) if [ "$_pc_has" = true ]; then _pc_carry=1; else _pc_carry=0; fi ;;
  esac
done <<< "$_pc_region"
eq "leg 2: every silent return in the gate region is reached through such a test" "" "$_pc_stray"

# THE SUBJECT EXTRACTOR — ONE READER, TWO SPANS. Legs 3 and 5 ask one question of two
# different spans (which identifiers does this text TEST), so they ask it through one
# function. They were two regex sets, and they had already drifted: leg 3's required the
# closing `]` and normalised only `${V:-}`, so a region test spelled `[ -z "${KANBAN_X:-0}" ]`
# yielded the subject `{KANBAN_X:-0}` to leg 3 and `KANBAN_X` to leg 5, and no
# `gates:`/`non-gates:` declaration could satisfy both — the function became UNDECLARABLE.
#
# WHOLE-LINE comments are stripped first: the function carries one that spells a test inside
# backticks (card#5874's note above `args`), and a comment is not code. A trailing comment is
# left alone — `#` inside a string is not a comment, and no regex here knows the difference;
# a test it hides is still read, an invented one still reds.
_pc_uncomment() { printf '%s\n' "$1" | sed -E 's/^[[:space:]]*#.*$//'; }
# Normalisation, spelled here rather than in the header: `${V:-…}`, `${V:+…}` (the spelling a
# credential is tested in, so a trace never prints it — card#11204) and `$V` reduce to `V`, and a `$dir/name` operand reduces to `name` (that is the promoter's
# beside-the-script half, which the header names as `promote-released-cards`).
# BINARY tests are read as well as unary ones, and `test -z "$x"` is read alongside
# `[ … ]`/`[[ … ]]`: `test` is a command's exit status by SPELLING, but it carries a quoted
# operand, so there IS a subject to declare and no ground for it to evade (see leg 5's
# residual note — the reason the residual gives is *no operand*, not *not a bracket*).
# Emits one subject per line, in source order and NOT deduplicated, so a caller can count
# what was parsed as well as compare the set.
_pc_subjects() {
  local _pct _pcn _pcu _pcb
  _pct="$(_pc_uncomment "$1")"
  _pcn='s/^\$\{([A-Za-z_][A-Za-z0-9_]*)(:[-+][^}]*)?\}$/\1/; s|^\$[A-Za-z_][A-Za-z0-9_]*/||; s/^\$//'
  _pcu="$(printf '%s\n' "$_pct" | { command grep -oE '(\[\[? |test )-[a-z] "[^"]*"' || true; } \
    | sed -E 's/^(\[\[? |test )-[a-z] "//; s/"$//' | sed -E "$_pcn")"
  _pcb="$(printf '%s\n' "$_pct" \
    | { command grep -oE '(\[\[? |test )"[^"]*" (=|!=|-eq|-ne|-gt|-lt|-ge|-le) ' || true; } \
    | sed -E 's/^(\[\[? |test )"//; s/" .*$//' | sed -E "$_pcn")"
  printf '%s\n%s\n' "$_pcu" "$_pcb" | { command grep -v '^$' || true; }
}

# LEG 3 — THE CLAIM ITSELF. The subjects the function tests before printing, against the
# subjects the header's `gates:` lines declare. An undeclared gate reds; a declared non-gate
# reds. It reads through `_pc_subjects` above — the same extractor leg 5 reads the WHOLE
# function with, so the two legs cannot disagree about what a subject is.
_pc_real_gates="$(_pc_subjects "$_pc_region" | LC_ALL=C sort -u | paste -sd' ' -)"
[ -n "$_pc_real_gates" ] || bad "leg 3: no gate subject derived from the function — the extractor read nothing"
_pc_decl_gates="$(sed -n 's/^#  *gates: //p' "$BIN" | tr ' ' '\n' | { command grep -v '^$' || true; } \
  | LC_ALL=C sort -u | paste -sd' ' -)"
eq "leg 3: the header's gates: lines are exactly the subjects the function tests before printing" \
   "$_pc_real_gates" "$_pc_decl_gates"
# …and each declared precondition carries one, so a name cannot be added without its subjects.
eq "leg 3: every declared precondition carries a gates: line" \
   "$(printf '%s\n' "$_pc_declared" | tr ' ' '\n' | command grep -c . || true)" \
   "$(sed -n 's/^#  *gates: //p' "$BIN" | command grep -c . || true)"

# LEG 4 — past the region, every return must be immediately preceded by a `coverage_line` call
# and none may carry a test of its own. That is the leg's whole predicate, and the header states
# it as the predicate rather than as "no gate can be parked below the region", which is the
# claim it CANNOT support:
#   `else` OPENS AN ARM THAT HAS PRINTED NOTHING, so it clears the carried print rather than
#   letting a `return` under it inherit the `then` arm's one. A STANDALONE `else` line needs no
#   rule — it becomes the previous line and carries no print. The arm that does is the one-line
#   `else return 0`, which without the clear inherits the `then` arm's `coverage_line`: MEASURED
#   BOTH WAYS in r2 — that gate passes the whole suite at rc 0 with the clear removed and reds
#   with it. ⛔ Clearing must NOT `continue`: the return check below is on the same line.
#   ⚑ `fi` deliberately does NOT clear: the shipped `if COUNT; then coverage_line …; else
#   coverage_line …; fi; return 0` prints on every arm and must stay green. So a gate whose
#   print is CONDITIONAL (`if …; then coverage_line …; fi; return 0`) passes this leg —
#   MEASURED in r2, whole suite rc 0 with an undeclared `KANBAN_XYZ_UNSET` gate in that shape.
#   ⛔ THIS LEG CANNOT CLOSE THAT SHAPE and does not try: a print-state machine strict enough to
#   red on it also reds on this function's own last statement, a conditional print with no `else`
#   and no trailing return. LEG 5 closes it on the declaration side instead, reading no print
#   state at all. The falsifier arms above are what cover a gate that keeps its declared subject.
_pc_below=""; _pc_prev=""
while IFS= read -r _pc_line; do
  _pc_t="${_pc_line#"${_pc_line%%[![:space:]]*}"}"
  case "$_pc_t" in ''|'#'*|fi|fi\ *|'}') continue ;; esac
  # NO `continue` HERE: `else return 0` on ONE line must still reach the return check below.
  # Clearing and skipping is what let that spelling through at rc 0 (measured, r2).
  case "$_pc_t" in else|else\ *) _pc_prev="" ;; esac
  case "$_pc_t" in *'return '*)
    case "$_pc_t" in
      *'[ -'*) _pc_below="$_pc_below | gate: $_pc_t" ;;
      *) case "$_pc_prev" in *'coverage_line '*) ;; *) _pc_below="$_pc_below | silent: $_pc_t" ;; esac ;;
    esac ;;
  esac
  _pc_prev="$_pc_t"
done <<< "$(printf '%s\n' "$_pc_src" | tail -n +"$((_pc_last_gate + 1))")"
eq "leg 4: past the gate region every return has already printed a coverage line" "" "$_pc_below"

# LEG 5 — COMPLETENESS OVER THE WHOLE FUNCTION, which is what closes leg 4's residual. Legs 1–3
# read the gate region and leg 4 reads returns past it; neither sees a gate whose print is
# conditional (`if …; then coverage_line …; fi; return 0`), and the print-state machine that
# would is the one that reds on the function's own last statement. This leg reads no print state:
# EVERY subject the function tests, at any depth, anywhere in it, must be DECLARED in the bin —
# as a `gates:` name, or on its `non-gates:` line. An undeclared gate has an undeclared subject,
# so it reds wherever it is parked, in either bracket spelling and in the `test` spelling.
#
# ⚠ THE RESIDUAL — what this leg does NOT reach — stated by the property that puts a shape
# outside it rather than by a spelling: a gate past the region whose test offers no quoted
# operand to a bracket or `test` reader, with its print CONDITIONAL. That is a command's exit
# status (`if ! command -v x; then …coverage_line… fi`, `grep -q`) or an arithmetic
# `(( ${X:-0} == 0 ))` — MEASURED, whole suite rc 0 for each. There is no subject in either to
# declare, which is why widening a reader cannot close them. Two shapes that ARE reached, and
# were once thought not to be: `cmd && return 0` is caught by leg 4 (the `return` carries a test
# of its own), and `case "$X" in "") …print… ;; esac` is caught by leg 4 too — `esac` is not in
# its skip list, so the print-carry does not survive it. Both measured. ⛔ A SECOND residual is
# not stated here but on the bin's `non-gates:` paragraph, which is its home: a test that REUSES
# an already-declared subject is invisible to a set comparison, which is exactly why naming a
# subject there is written as a CLAIM that its test cannot end the run in silence.
#
# Both directions, as leg 3 has them: an undeclared subject reds, and a declared name the
# function does not test reds. Reads through `_pc_subjects` — the same extractor leg 3 uses,
# over the whole function rather than the region — so binary and `test`-spelled tests are read
# here too. Leg 2 covers a binary gate in the REGION by a different route (it reaches no silent
# return); past the region there is no such route.
# Leg 1's technique, widened to the function: a spelling the extractor does not parse would
# contribute no subject and pass in silence, so openings are counted against tests actually read.
# The opening counter anchors `test` on a command boundary where the reader does not, so the
# two can disagree in EITHER direction — a `test` the counter will not count, or one it counts
# that carries no readable operand (`test "$a"`). Both RED, which is the leg's whole job: a
# spelling the extractor cannot read must not pass in silence.
_pc_subj_all="$(_pc_subjects "$_pc_src")"
_pc_open5="$(_pc_uncomment "$_pc_src" | { command grep -oE '(\[\[? |(^|[;&|( ])test )' || true; } \
  | command grep -c . || true)"
_pc_read5="$(printf '%s\n' "$_pc_subj_all" | command grep -c . || true)"
eq "leg 5: every test in the function is one this extractor can read" "$_pc_open5" "$_pc_read5"
_pc_real_all="$(printf '%s\n' "$_pc_subj_all" | { command grep -v '^$' || true; } \
  | LC_ALL=C sort -u | paste -sd' ' -)"
_pc_nongates="$(sed -n 's/^#  *non-gates: //p' "$BIN" | tr ' ' '\n' | { command grep -v '^$' || true; } \
  | LC_ALL=C sort -u | paste -sd' ' -)"
[ -n "$_pc_real_all" ] || bad "leg 5: no test subject derived from the function — the extractor read nothing"
[ -n "$_pc_nongates" ] || bad "leg 5: the bin declares no non-gates: line — the declared half is missing"
_pc_decl_all="$( { printf '%s\n' "$_pc_decl_gates" | tr ' ' '\n'; printf '%s\n' "$_pc_nongates" | tr ' ' '\n'; } \
  | { command grep -v '^$' || true; } | LC_ALL=C sort -u | paste -sd' ' -)"
eq "leg 5: every subject the function tests is declared in the bin, and every declared name is tested" \
   "$_pc_real_all" "$_pc_decl_all"

unset -f cov_err _pc_uncomment _pc_subjects
unset _pc _pc_err _pc_path _pc_declared
unset _pc_src _pc_first_print _pc_last_gate _pc_region _pc_open_n _pc_read_n
unset _pc_stray _pc_carry _pc_line _pc_t _pc_has _pc_real_gates _pc_decl_gates _pc_below _pc_prev
unset _pc_subj_all _pc_open5 _pc_read5 _pc_real_all _pc_nongates _pc_decl_all

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
eq "…and the coverage report is omitted whole"   "false" "$(has 'card coverage:' "$(cat "$COV/cov.err")")"
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

echo "== the BODY is installer content only; builder diagnostics MOVE to stderr, kept (DL-224, card#9248) =="
# THE DEFECT. `## Correlation gaps` and `## Card coverage` were H2 sections of the body: builder
# diagnostics about manifests and promotion, not content for the person installing the release.
# Reported on card#9248: the framework's PR-body lint reds on both and admits `## Release
# artifacts`, so every generated release body was hand-edited at every cut. DL-224 ruled the body to the scope line,
# `## Highlights`, `## Bundled`, `## Release artifacts` (when `artifacts` is configured) and the
# machine lines — and the two diagnostics to STDERR, kept, beside an `announce:begin`…`announce:end`
# block a release tool lifts instead of re-deriving.
#
# ONE RUN, BOTH STREAMS, BOTH DIRECTIONS. A body-only assertion passes on an implementation that
# DELETED the diagnostics — so the same invocation that is asserted to carry no stray H2 on stdout
# is asserted to carry both diagnostics and the block on stderr. The fixture makes every emitter
# fire at once: `artifacts` configured (the conditional H2 is PRESENT, so the allow-list is
# exercised rather than vacuous), `ref_token_regex` matching nothing (a correlation gap), and a
# promote config whose board lacks card#9999 (a measured coverage finding). Both token keys are
# declared, so every announce field the contract declares is emitted and the declared-vs-emitted
# comparison below runs over the whole set.
SPL="$COV/split"; mkdir -p "$SPL"
cat > "$CR/.release-pr.json" <<'EOF'
{
  "ref_token_regex": "DL-[0-9]+",
  "card_token_regex": "card#[0-9]+",
  "artifacts": [ "VERSION → {{version}}" ],
  "promote": { "board_id": 12, "released_stage_id": 85, "api_base": "https://kanban.test/api/v3", "source": "*" }
}
EOF
cat > "$SPL/board.json" <<'EOF'
{"data":[{"id":42,"workflow_stage_id":51,"payload":{"dl_number":"DL-42"}}],"meta":{"last_page":1,"total":1}}
EOF
SPL_HEAD="$(g -C "$CR" rev-parse HEAD)"; SPL_BASE="$(g -C "$CR" rev-parse 'v0.1.0^{commit}')"
rc=0
( cd "$CR" && PATH="$COV/bin:$HERE/../bin:$PATH" BOARD_FILE="$SPL/board.json" \
    KANBAN_WRITEBACK_TOKEN=tkn KANBAN_EXPECTED_HOST=kanban.test \
    "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD ) >"$SPL/out" 2>"$SPL/err" || rc=$?
SPL_OUT="$(cat "$SPL/out")"; SPL_ERR="$(cat "$SPL/err")"
eq "split run → rc 0"                                   "0"     "$rc"

# stdout: the H2 allow-list, as a set difference over the H2 lines actually emitted.
SPL_STRAY="$(printf '%s\n' "$SPL_OUT" | awk '
  /^## / && $0 != "## Highlights" && $0 != "## Bundled (generated — do not hand-edit)" && $0 != "## Release artifacts"')"
eq "the body carries NO H2 outside the ruled set"       ""      "$SPL_STRAY"
eq "…presence: ## Highlights"                           "true"  "$(has_line '## Highlights' "$SPL_OUT")"
eq "…presence: ## Bundled"                              "true"  "$(has_line '## Bundled (generated — do not hand-edit)' "$SPL_OUT")"
eq "…presence: ## Release artifacts (configured here)"  "true"  "$(has_line '## Release artifacts' "$SPL_OUT")"
eq "…presence: the shipped-cards footer"                "true"  "$(has_line '<!-- release-manifest:shipped-cards=9999 -->' "$SPL_OUT")"
eq "…and no announce line leaks into the body"          "false" "$(has 'announce:' "$SPL_OUT")"
# The H2 allow-list cannot see a diagnostic that leaks into the body WITHOUT a heading. So the
# tail is pinned too: after the last ruled section's own lines (here, the `## Release artifacts`
# checklist), every non-blank stdout line is a `release-manifest` footer — nothing else may
# follow. The two phrases below are the coverage finding's own words, asserted absent from the
# body in the same run that asserts them present on stderr.
SPL_TAIL="$(printf '%s\n' "$SPL_OUT" | awk '
  $0 == "## Release artifacts" { s = 1; next }
  s == 1 && /^- \[ \] / { next }
  s >= 1 { s = 2; if (NF && $0 !~ /^<!-- release-manifest:[a-z-]+=[^ ]* -->$/) print }')"
eq "…after the last ruled section, only manifest footers" ""    "$SPL_TAIL"
eq "…the coverage finding is NOT in the body"           "false" "$(has 'Shipped refs with no tracking card' "$SPL_OUT")"
eq "…nor its remedy line"                               "false" "$(has 'Create (or correct)' "$SPL_OUT")"

# stderr: the diagnostics are PRESENT — the half a deletion would fail.
eq "stderr carries the correlation gap"                 "true"  "$(has 'release-pr-body: correlation gap: ⚠ **`ref_token_regex` is declared' "$SPL_ERR")"
eq "stderr carries the measured coverage finding"       "true"  "$(has 'release-pr-body: card coverage: ⚠ **Shipped refs with no tracking card:** card#9999' "$SPL_ERR")"
eq "…and no stderr line is an H2 (a 2>&1 merge adds none)" "" "$(printf '%s\n' "$SPL_ERR" | awk '/^## /')"

# stderr: the announce block — once, whole, last.
SPL_BLOCK="$(printf '%s\n' "$SPL_ERR" | sed -n '/^announce:begin$/,/^announce:end$/p')"
eq "announce:begin appears exactly once"                "1"     "$(printf '%s\n' "$SPL_ERR" | awk '$0=="announce:begin"{n++} END{print n+0}')"
eq "announce:end appears exactly once"                  "1"     "$(printf '%s\n' "$SPL_ERR" | awk '$0=="announce:end"{n++} END{print n+0}')"
eq "…and it is the LAST line of stderr"                 "announce:end" "$(printf '%s\n' "$SPL_ERR" | tail -n 1)"
eq "block: format"                                      "true"  "$(has_line 'format: 1' "$SPL_BLOCK")"
eq "block: version"                                     "true"  "$(has_line 'version: 0.2.0' "$SPL_BLOCK")"
eq "block: range pinned by sha"                         "true"  "$(has_line "range: $SPL_BASE..$SPL_HEAD" "$SPL_BLOCK")"
eq "block: the range re-prints as a git command"        "true"  "$(has_line "range-cmd: git log --no-merges --format=%s $SPL_BASE..$SPL_HEAD" "$SPL_BLOCK")"
eq "block: shipped cards, as the manifest has them"     "true"  "$(has_line 'shipped-cards: 9999' "$SPL_BLOCK")"
eq "block: …and the command that re-prints them"        "true"  "$(has_line "shipped-cards-cmd: release-pr-body --card-manifest --version 0.2.0 --base $SPL_BASE --head $SPL_HEAD" "$SPL_BLOCK")"
eq "block: a declared key that matched nothing is present-and-empty" "true" "$(has_line 'shipped-refs: ' "$SPL_BLOCK")"
# THE DERIVATIONS ARE REAL: each *-cmd, run as printed, re-prints the value beside it.
SPL_CARDS_CMD="$(printf '%s\n' "$SPL_BLOCK" | sed -n 's/^shipped-cards-cmd: //p')"
eq "shipped-cards-cmd re-prints shipped-cards"          "9999"  "$( cd "$CR" && PATH="$HERE/../bin:$PATH" bash -c "$SPL_CARDS_CMD" 2>/dev/null )"
SPL_RANGE_CMD="$(printf '%s\n' "$SPL_BLOCK" | sed -n 's/^range-cmd: //p')"
eq "range-cmd re-prints the bundled subject"            "feat: a thing (card#9999) (#42)" "$( cd "$CR" && bash -c "$SPL_RANGE_CMD" )"
SPL_REFS_CMD="$(printf '%s\n' "$SPL_BLOCK" | sed -n 's/^shipped-refs-cmd: //p')"
rc=0; SPL_REFS="$( cd "$CR" && PATH="$HERE/../bin:$PATH" bash -c "$SPL_REFS_CMD" 2>/dev/null )" || rc=$?
eq "shipped-refs-cmd runs (rc 0)…"                      "0"     "$rc"
eq "…and re-prints shipped-refs (empty here)"           "$(printf '%s\n' "$SPL_BLOCK" | sed -n 's/^shipped-refs: //p')" "$SPL_REFS"

# DECLARE ↔ EMIT, both ways and IN ORDER (canon #7 — the declaring end checks its declaration is
# TRUE OF ITS OWN CODE). The declared field list is read from the usage header, which `--help`
# prints and a consumer outside this repo reads; the emitted list from the block above, with a
# repeated key collapsed to its first appearance. An ordered comparison, because the header
# declares the order.
SPL_DECLARED="$("$BIN" --help | sed -n '/^#     announce:begin$/,/^#     announce:end$/p' \
  | sed -e '1d;$d' -e 's/^#     //' -e 's/:.*//' | awk '!seen[$0]++')"
SPL_EMITTED="$(printf '%s\n' "$SPL_BLOCK" | sed -e '1d;$d' -e 's/:.*//' | awk '!seen[$0]++')"
eq "precondition: the header declares a field list"     "true"  "$(has_line 'shipped-cards-cmd' "$SPL_DECLARED")"
eq "every DECLARED field is emitted, in order, and nothing else" "$SPL_DECLARED" "$SPL_EMITTED"

# CONTROL — a query mode is not a body run: it prints no diagnostics and no block.
rc=0; ( cd "$CR" && "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD --card-manifest ) >/dev/null 2>"$SPL/q.err" || rc=$?
eq "control: --card-manifest → rc 0"                    "0"     "$rc"
eq "control: …and emits no announce block"              "false" "$(has 'announce:begin' "$(cat "$SPL/q.err")")"

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
# test admits exactly the combination nobody wrote down. The modes are DERIVED from the bin's
# own `query_mode` registrations and every pair is driven, so a mode added there is covered here
# the day it lands; the two named witnesses keep an empty derivation from passing.
mapfile -t QMODES < <(command grep -oE '^query_mode "\$[A-Z_]+"[[:space:]]+--[a-z-]+' "$BIN" | awk '{print $NF}')
eq "derivation witness: --tag is a query mode"          "true" "$(has_line --tag "$(printf '%s\n' "${QMODES[@]}")")"
eq "derivation witness: --tool-version is a query mode" "true" "$(has_line --tool-version "$(printf '%s\n' "${QMODES[@]}")")"
# Completeness: a registration spelled in a shape the pattern above misses would otherwise drop
# its pairs silently. Every `query_mode` call line must have been derived.
eq "derivation covers every query_mode registration line" \
   "$(command grep -cE '^[[:space:]]*query_mode[[:space:]]' "$BIN")" "${#QMODES[@]}"
for ((i = 0; i < ${#QMODES[@]}; i++)); do
  for ((j = i + 1; j < ${#QMODES[@]}; j++)); do
    pair="${QMODES[i]} ${QMODES[j]}"
    rc=0; err="$( (cd "$W" && "$BIN" "${QMODES[i]}" "${QMODES[j]}" --version 0.3.0) 2>&1 )" || rc=$?
    eq "$pair → rc 2"                          "2"                "$rc"
    eq "…naming both modes"                    "true"             "$(has "${QMODES[i]}, ${QMODES[j]} are mutually exclusive query modes" "$err")"
  done
done
# CONTROL — one mode alone is accepted, so the refusal above is about the COMBINATION.
rc=0; (cd "$W" && "$BIN" --tag --version 0.3.0) >/dev/null 2>&1 || rc=$?
eq "control: one mode alone is fine"         "0"                "$rc"

echo "== --tool-version prints the toolkit version this FILE is — from a copy, with no checkout =="
# `--version` is an INPUT naming the release; `--tool-version` asks the tool what it is. The
# answer must come from the file itself: a seat's copy under ~/.local/bin has no checkout, no
# VERSION beside it and no config, and every one of those is absent or a DECOY below.
TOOLKIT_VERSION="$(tr -d '\n' < "$HERE/../VERSION")"
printf '%s\n' "$TOOLKIT_VERSION" > "$T/tv-want"
SEAT="$T/seat"; mkdir -p "$SEAT/bin" "$SEAT/cwd"
cp "$BIN" "$SEAT/bin/release-pr-body"
if git -C "$SEAT/cwd" rev-parse --git-dir >/dev/null 2>&1; then
  bad "fixture broken: the copy's cwd is inside a git work tree"
else
  ok "the copy runs outside every git work tree"
fi
if [ -L "$SEAT/bin/release-pr-body" ] || [ -e "$SEAT/VERSION" ] || [ -e "$SEAT/cwd/.release-pr.json" ]; then
  bad "fixture broken: the copy is a symlink or has a VERSION/config beside it"
else
  ok "the copy is a plain file with no VERSION or config beside it"
fi

# _tv <dir> <bin> <args...> — run from <dir>; stdout/stderr to tv-out/tv-err, rc to TV_RC.
_tv() { local d="$1"; shift; TV_RC=0; (cd "$d" && "$@") >"$T/tv-out" 2>"$T/tv-err" || TV_RC=$?; }

_tv "$SEAT/cwd" "$SEAT/bin/release-pr-body" --tool-version
eq "copy: --tool-version → rc 0"                   "0"    "$TV_RC"
eq "copy: stdout is exactly VERSION and a newline" "true" "$(cmp -s "$T/tv-out" "$T/tv-want" && echo true || echo false)"
eq "copy: stderr is silent"                        ""     "$(cat "$T/tv-err")"

# DECOYS — a VERSION where a path-relative read would look (beside bin/, and in the cwd) and a
# config naming a different release. An implementation reading any of them prints 6.6.6.
printf '6.6.6\n' > "$SEAT/VERSION"; printf '6.6.6\n' > "$SEAT/cwd/VERSION"
printf '{ "version_file": "VERSION", "version_regex": "[0-9.]+" }\n' > "$SEAT/cwd/.release-pr.json"
_tv "$SEAT/cwd" "$SEAT/bin/release-pr-body" --tool-version
eq "decoys: still exactly the toolkit version"     "true" "$(cmp -s "$T/tv-out" "$T/tv-want" && echo true || echo false)"
eq "decoys: control — the release version IS 6.6.6 here" "v6.6.6" "$( (cd "$SEAT/cwd" && "$SEAT/bin/release-pr-body" --tag) 2>&1 )"

echo "== --version keeps its meaning: the RELEASE version, an input =="
# Presence witnesses, green before and after: the flag the card could not repurpose still names
# the release and still demands a value.
eq "--tag --version maps the RELEASE version"      "release-3.4.5" "$( (cd "$W" && "$BIN" --tag --version 3.4.5) 2>&1 )"
_tv "$W" "$BIN" --version
eq "bare --version → rc 2"                         "2"    "$TV_RC"
eq "…still asking for the release version's value" "true" "$(has '--version requires a non-empty value' "$(cat "$T/tv-err")")"
eq "…and prints nothing on stdout"                 ""     "$(cat "$T/tv-out")"

echo "== --tool-version with other arguments =="
# Inputs are ignored: the answer needs no config, no range and no release version, so neither a
# missing config nor unresolvable refs are consulted. Another QUERY mode is refused (the pairs
# above); a malformed argument is still refused, wherever it sits.
_tv "$W" "$BIN" --tool-version --version 3.4.5 --config "$T/no-such.json" --base no-such-ref --head no-such-ref
eq "with every input flag → rc 0"                  "0"    "$TV_RC"
eq "…printing the TOOL version, not 3.4.5 or 0.9.9" "true" "$(cmp -s "$T/tv-out" "$T/tv-want" && echo true || echo false)"
_tv "$W" "$BIN" --version 3.4.5 --tool-version
eq "flag order does not matter"                    "true" "$(cmp -s "$T/tv-out" "$T/tv-want" && echo true || echo false)"
_tv "$W" "$BIN" --tool-version --no-such-flag
eq "an unknown argument after it → rc 2"           "2"    "$TV_RC"
eq "…named"                                        "true" "$(has "unknown arg '--no-such-flag'" "$(cat "$T/tv-err")")"
eq "…and no version printed"                       ""     "$(cat "$T/tv-out")"
_tv "$W" "$BIN" --tool-version --base
eq "a value flag missing its value → rc 2"         "2"    "$TV_RC"
eq "…named"                                        "true" "$(has '--base requires a non-empty value' "$(cat "$T/tv-err")")"

echo "== --help lists --tool-version =="
eq "usage names the flag"                          "true" "$(has_line '#   release-pr-body --tool-version    # print the agent-board-toolkit version THIS FILE is, and exit' "$("$BIN" --help)")"

echo "== the Review: sentence reports each bundled change's review record, and never blocks (card#11149) =="
# THE CONTRACT (rt#557): one verifier call per bundled PR, `<verifier> <owner>/<repo>#<pr>`; exit 0
# is a record, 1 is none, 2 is unmeasured, and any other exit, a timeout or a missing verifier is
# unmeasured too. The sentence states its denominator and never folds unmeasured into either of the
# other two. Every case asserts the EXACT sentence and rc 0: the result is reported, never gated.
#
# THE FIXTURE. v0.1.0 → #11, #12, #13 (RV_MID) → a commit with no PR number → a second #11 commit.
# `v0.1.0..RV_MID` is three PRs; `v0.1.0..HEAD` adds the PR-less line (named by its short sha) and
# a repeated PR number, which must count once — M is the bundled PRs, not the commits.
RV="$T/rv"; RVR="$RV/repo"; RVB="$RV/bin"; mkdir -p "$RVB"
g init -q "$RVR"
echo 0 > "$RVR/f"; g -C "$RVR" add f; g -C "$RVR" commit -qm "chore: init"; g -C "$RVR" tag v0.1.0
echo 1 > "$RVR/f"; g -C "$RVR" commit -qam "feat: eleven (#11)"
echo 2 > "$RVR/f"; g -C "$RVR" commit -qam "fix: twelve (#12)"
echo 3 > "$RVR/f"; g -C "$RVR" commit -qam "docs: thirteen (#13)"
RV_MID="$(g -C "$RVR" rev-parse HEAD)"
echo 4 > "$RVR/f"; g -C "$RVR" commit -qam "chore: a direct push with no pull request"
RV_NOPR="$(g -C "$RVR" log -1 --format=%h)"
echo 5 > "$RVR/f"; g -C "$RVR" commit -qam "fix: eleven again (#11)"
echo '{}' > "$RVR/.release-pr.json"

# The stub verifier: exit code per PR from RV_MAP ("11=0 12=1"), RV_DEFAULT otherwise; it sleeps
# RV_SLEEP seconds first when the PR is RV_SLOW (`all`: every PR), and appends every argument it was given to RV_LOG.
cat > "$RVB/coord-review-verify" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RV_LOG"
pr="${1##*#}"
if [ "$pr" = "${RV_SLOW:-}" ] || [ "${RV_SLOW:-}" = all ]; then sleep "${RV_SLEEP:-0}"; fi
for kv in ${RV_MAP:-}; do
  if [ "${kv%%=*}" = "$pr" ]; then exit "${kv#*=}"; fi
done
exit "${RV_DEFAULT:-0}"
EOF
chmod +x "$RVB/coord-review-verify"
printf '#!/usr/bin/env bash\nexit 0\n' > "$RV/not-executable"

# A PATH with every directory that carries a real `coord-review-verify` removed, so the no-verifier
# case is not decided by whatever the host running this suite has installed.
RV_PATH=""
IFS=: read -r -a _rv_dirs <<< "$PATH"
for _d in "${_rv_dirs[@]}"; do
  [[ -x "$_d/coord-review-verify" ]] && continue
  RV_PATH="${RV_PATH:+$RV_PATH:}$_d"
done
eq "witness: the scrubbed PATH finds no coord-review-verify" "" "$(PATH="$RV_PATH" command -v coord-review-verify || true)"

# _rv <head> [VAR=value ...] — run the generator over v0.1.0..<head> under the scrubbed PATH with
# the stub dir prepended, GITHUB_REPOSITORY=acme/widget, and the extra env given. Sets RV_RC,
# RV_OUT (stdout), RV_ERR (stderr), RV_LINE (the line after the `## Bundled` heading) and RV_CALLS.
_rv() {
  local head="$1"; shift
  : > "$RV/log"; RV_RC=0
  ( cd "$RVR" && env -u RELEASE_PR_REVIEW_VERIFIER -u RELEASE_PR_REVIEW_VERIFIER_TIMEOUT \
      PATH="$RVB:$RV_PATH" GITHUB_REPOSITORY=acme/widget RV_LOG="$RV/log" "$@" \
      "$BIN" --version 0.2.0 --base v0.1.0 --head "$head" ) >"$RV/out" 2>"$RV/err" || RV_RC=$?
  RV_OUT="$(cat "$RV/out")"; RV_ERR="$(cat "$RV/err")"; RV_CALLS="$(cat "$RV/log")"
  RV_LINE="$(printf '%s\n' "$RV_OUT" | awk 'p { print; exit } $0 == "## Bundled (generated — do not hand-edit)" { p = 1 }')"
}

_rv "$RV_MID"
eq "all records → rc 0"                                  "0" "$RV_RC"
eq "…the sentence is the first line under ## Bundled"   "Review: 3 of 3 bundled changes have an independent review record." "$RV_LINE"
eq "…the verifier was asked <owner>/<repo>#<pr>, once per PR" "$(printf 'acme/widget#%s\n' 11 12 13)" "$(printf '%s\n' "$RV_CALLS" | sort)"
eq "…and the bundled rows still follow it"              "true" "$(has_line '- **#12** fix: twelve' "$RV_OUT")"

_rv "$RV_MID" RV_MAP="11=0 12=1 13=2"
eq "mixed 0/1/2 → rc 0"                                  "0" "$RV_RC"
eq "…1 is not covered and 2 is not measured, each by name" "Review: 1 of 3 bundled changes have an independent review record; not covered: #12; not measured: #13." "$RV_LINE"
eq "…the exit-2 PR is named on stderr"                  "true" "$(has 'release-pr-body: review: #13 not measured' "$RV_ERR")"

_rv "$RV_MID" RV_MAP="12=7"
eq "unexpected exit code → rc 0"                         "0" "$RV_RC"
eq "…exit 7 is not measured, never a record or a no"   "Review: 2 of 3 bundled changes have an independent review record; not measured: #12." "$RV_LINE"
eq "…and stderr names the exit code"                    "true" "$(has 'release-pr-body: review: #12 not measured (the verifier exited 7)' "$RV_ERR")"

RV_T0="$(date +%s)"
_rv "$RV_MID" RV_SLOW=13 RV_SLEEP=20 RELEASE_PR_REVIEW_VERIFIER_TIMEOUT=1
RV_SECS=$(( $(date +%s) - RV_T0 ))
eq "a hanging verifier → rc 0"                           "0" "$RV_RC"
eq "…the hung call is not measured"                     "Review: 2 of 3 bundled changes have an independent review record; not measured: #13." "$RV_LINE"
eq "…the generator did not wait it out (<10s of a 20s hang)" "true" "$([[ "$RV_SECS" -lt 10 ]] && echo true || echo false)"
eq "…and stderr says it was killed"                     "true" "$(has 'release-pr-body: review: #13 not measured (the verifier was killed after 1s)' "$RV_ERR")"

_rv "$RV_MID" PATH="$RV_PATH"
eq "no verifier on PATH → rc 0"                          "0" "$RV_RC"
eq "…the no-verifier sentence, with its denominator"    "Review: not measured for any of the 3 bundled changes (no review-record verifier on this machine)." "$RV_LINE"

_rv "$RV_MID" RELEASE_PR_REVIEW_VERIFIER=off
eq "RELEASE_PR_REVIEW_VERIFIER=off → rc 0"               "0" "$RV_RC"
eq "…the turned-off sentence, with its denominator"     "Review: not measured for any of the 3 bundled changes (the review-record verifier is turned off on this machine)." "$RV_LINE"
eq "…and the verifier on PATH was never called"        "" "$RV_CALLS"

_rv "$RV_MID" RV_SLOW=all RV_SLEEP=20 RELEASE_PR_REVIEW_VERIFIER_TIMEOUT=1
eq "a verifier that hangs on EVERY PR → rc 0"            "0" "$RV_RC"
eq "…the first timeout ends the asking: only the first PR was asked, so the wait is one bound, not M" "acme/widget#11" "$RV_CALLS"
eq "…and every PR is not measured"                      "Review: 0 of 3 bundled changes have an independent review record; not measured: #11, #12, #13." "$RV_LINE"
eq "…the rest are named on stderr as not asked"         "true" "$(has 'release-pr-body: review: #12 not measured (not asked: the verifier timed out on #11)' "$RV_ERR")"

for _bad in 0 abc; do
  _rv "$RV_MID" RELEASE_PR_REVIEW_VERIFIER_TIMEOUT="$_bad"
  eq "RELEASE_PR_REVIEW_VERIFIER_TIMEOUT=$_bad → rc 0"   "0" "$RV_RC"
  eq "…falls back to 30s, so the calls still answer"    "Review: 3 of 3 bundled changes have an independent review record." "$RV_LINE"
  eq "…and stderr names the bad value"                  "true" "$(has "release-pr-body: review: RELEASE_PR_REVIEW_VERIFIER_TIMEOUT='$_bad' is not a positive whole number of seconds; using 30" "$RV_ERR")"
done
_rv "$RV_MID" RELEASE_PR_REVIEW_VERIFIER_TIMEOUT=5
eq "control: a valid bound draws no note"               "false" "$(has 'RELEASE_PR_REVIEW_VERIFIER_TIMEOUT=' "$RV_ERR")"

_rv v0.1.0
eq "zero bundled changes, with a verifier"              "Review: no bundled changes." "$RV_LINE"
eq "…and nothing is asked"                              "" "$RV_CALLS"
_rv v0.1.0 RELEASE_PR_REVIEW_VERIFIER=off
eq "zero bundled changes, verifier turned off"          "Review: no bundled changes." "$RV_LINE"
_rv v0.1.0 PATH="$RV_PATH"
eq "zero bundled changes, no verifier"                  "Review: no bundled changes." "$RV_LINE"

# CTRL-C REACHES IT. A terminal's Ctrl-C is a SIGINT to the foreground process GROUP; `timeout`
# runs the verifier in a group of its own, so only an interrupt the generator itself acts on stops
# the wait. The generator runs as its own group leader (setsid) under a wrapper that records its
# rc; SIGINT goes to that group while the verifier hangs 20s on the first PR, under a 30s bound.
_need -x "$(command -v setsid || echo setsid)" setsid
printf '%s\n' '#!/usr/bin/env bash' 'echo $$ > "$RV_PG"' "trap ':' INT" '"$@"' 'echo $? > "$RV_RCF"' > "$RV/int-run"
chmod +x "$RV/int-run"
rm -f "$RV/pg" "$RV/rcf"
RV_T0="$(date +%s)"
( cd "$RVR" && RV_PG="$RV/pg" RV_RCF="$RV/rcf" setsid "$RV/int-run" env -u RELEASE_PR_REVIEW_VERIFIER_TIMEOUT \
    PATH="$RVB:$RV_PATH" GITHUB_REPOSITORY=acme/widget RV_LOG="$RV/log" RV_SLOW=all RV_SLEEP=20 \
    "$BIN" --version 0.2.0 --base v0.1.0 --head "$RV_MID" >"$RV/out" 2>"$RV/err" & )
for _i in $(seq 1 50); do [[ -s "$RV/pg" ]] && break; sleep 0.1; done
sleep 1.5
kill -INT -- "-$(cat "$RV/pg")" 2>/dev/null || true
for _i in $(seq 1 300); do [[ -s "$RV/rcf" ]] && break; sleep 0.1; done
RV_SECS=$(( $(date +%s) - RV_T0 ))
eq "SIGINT while the verifier hangs: the generator stops promptly (<10s of a 20s hang)" "true" "$([[ -s "$RV/rcf" && "$RV_SECS" -lt 10 ]] && echo true || echo false)"
eq "…as an interrupted run (rc 130), not a finished one" "130" "$(cat "$RV/rcf" 2>/dev/null)"
eq "…and it prints no body"                              "" "$(cat "$RV/out")"

_rv HEAD
eq "a bundled line with no PR number → rc 0"             "0" "$RV_RC"
eq "…it is not measured, named by its short sha; a repeated PR counts once" "Review: 3 of 4 bundled changes have an independent review record; not measured: $RV_NOPR." "$RV_LINE"
eq "…and the repeated PR is asked about once"           "$(printf 'acme/widget#%s\n' 11 12 13)" "$(printf '%s\n' "$RV_CALLS" | sort)"

cp "$RVB/coord-review-verify" "$RV/override"
_rv "$RV_MID" PATH="$RV_PATH" RELEASE_PR_REVIEW_VERIFIER="$RV/override" RV_MAP="11=1"
eq "RELEASE_PR_REVIEW_VERIFIER=<path> is the verifier"   "Review: 2 of 3 bundled changes have an independent review record; not covered: #11." "$RV_LINE"

_rv "$RV_MID" RELEASE_PR_REVIEW_VERIFIER="$RV/not-executable"
eq "an override that is not executable → rc 0"           "0" "$RV_RC"
eq "…every PR is not measured, and the PATH verifier is not used instead" "Review: 0 of 3 bundled changes have an independent review record; not measured: #11, #12, #13." "$RV_LINE"
eq "…the stub on PATH was never called"                "" "$RV_CALLS"

_rv "$RV_MID" GITHUB_REPOSITORY=
eq "an empty GITHUB_REPOSITORY and no origin → rc 0"           "0" "$RV_RC"
eq "…nothing can be asked, so nothing is measured"     "Review: 0 of 3 bundled changes have an independent review record; not measured: #11, #12, #13." "$RV_LINE"
eq "…and the verifier was never called"                "" "$RV_CALLS"

g -C "$RVR" remote add origin git@github.com:acme/gadget.git
_rv "$RV_MID" GITHUB_REPOSITORY=
eq "the repo falls back to the origin remote"           "$(printf 'acme/gadget#%s\n' 11 12 13)" "$(printf '%s\n' "$RV_CALLS" | sort)"
_rv "$RV_MID"
eq "…and GITHUB_REPOSITORY outranks it"                 "$(printf 'acme/widget#%s\n' 11 12 13)" "$(printf '%s\n' "$RV_CALLS" | sort)"

echo "== a merge-train range is bundled and reviewed per PR, not per commit (card#11580) =="
# THE DEFECT (measured on agent-board-framework v0.64.0): a range carrying a merge-train commit
# listed the train's PRs as raw branch-commit subjects with no PR number, and the Review: sentence's
# denominator counted commits. Rows and sentence are now both one unit per bundled PR.
#
# (a) A range with NO merge commit is byte-identical to the per-commit generator: the GOLDEN body
# below is that generator's output over the card#11149 fixture's `v0.1.0..HEAD` (squash commits, a
# direct push with no PR number, a repeated PR number), verifier turned off.
_rv HEAD RELEASE_PR_REVIEW_VERIFIER=off
RV_GOLDEN="$(cat <<EOF
**\`dev → main\` release PR — v0.2.0.** Bundles 5 commit(s) since v0.1.0.

## Highlights
<!-- AUTHOR: write the 1–3 human-readable highlights of this release here. This is
     the ONLY non-deterministic section — everything below is generated from git. -->

## Bundled (generated — do not hand-edit)
Review: not measured for any of the 4 bundled changes (the review-record verifier is turned off on this machine).

- **#11** fix: eleven again
- chore: a direct push with no pull request
- **#13** docs: thirteen
- **#12** fix: twelve
- **#11** feat: eleven
EOF
)"
eq "(a) squash-only range: the body is byte-identical to the per-commit generator's" "$RV_GOLDEN" "$RV_OUT"

# (b)/(c) THE TRAIN FIXTURE, built on `main` from v0.1.0, first-parent oldest → newest:
#   #21 squash · #22 squash · `Merge pull request #30` (the train) · #23 squash ·
#   `Merge branch 'hotfix'` (no PR number; two raw commits) · `Merge branch 'catchup'` (no PR
#   number; its side is only the squash #40).
# The train's side, oldest → newest: `Merge pull request #31` and `#32` (each over two raw branch
# commits), a raw commit made on the train itself, `Merge pull request #33` (a NESTED train: a
# `Merge pull request #34` over raw commits, then a squash #35), and `Merge branch 'main' into
# train` (a back-merge bringing #22, which mainline already carries).
TR="$RV/train"
g init -q "$TR"
echo 0 > "$TR/f"; g -C "$TR" add f; g -C "$TR" commit -qm "chore: init"; g -C "$TR" tag v0.1.0
_trc() { echo "$RANDOM$2" >> "$TR/$1"; g -C "$TR" add "$1"; g -C "$TR" commit -qm "$2"; }
_trm() { g -C "$TR" merge -q --no-ff "$1" -m "$2" ${3:+-m "$3"}; }
_trc a "feat: twenty-one (#21)"
g -C "$TR" checkout -qb train
for _n in 31 32; do
  g -C "$TR" checkout -qb "f$_n" train
  _trc "b$_n" "wip: $_n part one"; _trc "b$_n" "wip: $_n part two"
  g -C "$TR" checkout -q train
  _trm "f$_n" "Merge pull request #$_n from acme/f$_n" "$([ "$_n" = 31 ] && echo "feat: thirty-one card#9031" || echo "feat: thirty-two")"
done
_trc c "chore: train bookkeeping"
g -C "$TR" checkout -qb t2 train
g -C "$TR" checkout -qb f34 t2
_trc d "wip: 34 part one"; _trc d "wip: 34 part two"
g -C "$TR" checkout -q t2
_trm f34 "Merge pull request #34 from acme/f34" "feat: thirty-four"
_trc e "fix: thirty-five (#35)"
g -C "$TR" checkout -q train
_trm t2 "Merge pull request #33 from acme/t2" "train: the nested one"
g -C "$TR" checkout -q main
_trc g "feat: twenty-two (#22)"
g -C "$TR" checkout -q train
_trm main "Merge branch 'main' into train"
g -C "$TR" checkout -q main
_trm train "Merge pull request #30 from acme/train" "release train"
_trc h "fix: twenty-three (#23)"
g -C "$TR" checkout -qb hotfix
_trc i "fix: hot one"; _trc i "fix: hot two"
g -C "$TR" checkout -q main
_trm hotfix "Merge branch 'hotfix'"
TR_HOT="$(g -C "$TR" log -1 --format=%h)"
g -C "$TR" checkout -qb catchup
_trc j "feat: forty (#40)"
g -C "$TR" checkout -q main
_trm catchup "Merge branch 'catchup'"
echo '{"card_token_regex": "card#[0-9]+"}' > "$TR/.release-pr.json"
g -C "$TR" add .release-pr.json; g -C "$TR" commit -qm "chore: config (#41)"

# _tr [VAR=value ...] — _rv's run, over the train fixture's v0.1.0..HEAD. Sets the same RV_* names.
_tr() {
  : > "$RV/log"; RV_RC=0
  ( cd "$TR" && env -u RELEASE_PR_REVIEW_VERIFIER -u RELEASE_PR_REVIEW_VERIFIER_TIMEOUT \
      PATH="$RVB:$RV_PATH" GITHUB_REPOSITORY=acme/widget RV_LOG="$RV/log" "$@" \
      "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD ) >"$RV/out" 2>"$RV/err" || RV_RC=$?
  RV_OUT="$(cat "$RV/out")"; RV_ERR="$(cat "$RV/err")"; RV_CALLS="$(cat "$RV/log")"
  RV_LINE="$(printf '%s\n' "$RV_OUT" | awk 'p { print; exit } $0 == "## Bundled (generated — do not hand-edit)" { p = 1 }')"
}
_tr
TR_ROWS="$(printf '%s\n' "$RV_OUT" | awk '/^## Bundled/ { p = 1; next } /^## / { p = 0 } p && /^- /')"
eq "(b) a merge-train range → rc 0"                      "0" "$RV_RC"
eq "(b) one row per bundled PR, each with its number — the train's, the nested train's and every PR they carry, in first-parent order" \
"$(cat <<EOF
- **#41** chore: config
- **#40** feat: forty
- Merge branch 'hotfix'
- **#23** fix: twenty-three
- **#30** release train
- **#33** train: the nested one
- **#35** fix: thirty-five
- **#34** feat: thirty-four
- **#32** feat: thirty-two
- **#31** (\`card#9031\`) feat: thirty-one card#9031
- **#22** feat: twenty-two
- **#21** feat: twenty-one
EOF
)" "$TR_ROWS"
eq "(b) …no raw branch commit of a numbered PR is a row of its own" "false" "$(has 'wip:' "$TR_ROWS")"
eq "(b) …nor the train's own raw commit, which #30 stands for" "false" "$(has 'bookkeeping' "$TR_ROWS")"
eq "(b) …the back-merge into the train brings nothing new and is not a row; #22 is listed once" "1" "$(printf '%s\n' "$TR_ROWS" | grep -c '#22')"
eq "(b) the Review: denominator is the bundled PRs, plus the one unit with no PR number" \
   "Review: 11 of 12 bundled changes have an independent review record; not measured: $TR_HOT." "$RV_LINE"
eq "(b) …and the verifier is asked once per bundled PR" \
   "$(printf 'acme/widget#%s\n' 21 22 23 30 31 32 33 34 35 40 41)" "$(printf '%s\n' "$RV_CALLS" | sort)"
eq "(c) a merge with no PR number that carries unnumbered commits is a row, not dropped" "true" "$(has_line "- Merge branch 'hotfix'" "$TR_ROWS")"
eq "(c) …and stderr names it as not measured, by short sha" "true" "$(has "release-pr-body: review: $TR_HOT not measured" "$RV_ERR")"
eq "(c) a merge with no PR number whose side is only PRs is not a row: its PR is" "false" "$(has "catchup" "$TR_ROWS")"

echo "== a direct-push revert is not credited to the PR it reverts (card#11587) =="
# THE DEFECT: `git revert` of squash-merged #21, pushed straight to the integration branch, has the
# subject `Revert "feat: x (#21)"`. Its LAST `(#N)` is #21's, inside the quoted original, so it was
# bundled as `**#21**` and, #21 having a review record, counted as reviewed. A revert never takes
# the PR number of the commit it reverts: where its message carries git's `This reverts commit
# <sha>` line, a trailing `(#N)` equal to the reverted subject's is inherited, not its own.
# EVERY REVERT HERE IS WRITTEN BY `git revert`, so the fixture follows the installed git's spelling:
# git 2.43 and later writes a revert of a revert as `Reapply "…"`, older git as `Revert "Revert "…""`.
# A "through a PR" revert is a squash: git's subject with ` (#N)` appended, body kept, as GitHub's
# default squash message keeps it. On separate files, first-parent oldest → newest:
#   #21 · #22 · #23 · #24 · #28 (squash PRs)
#   A1 A2 A3 — direct pushes, each reverting the one before it, starting from #21
#   B1 = #22 reverted through PR #25 · B2 = B1 reverted through PR #26
#   C1 = #23 reverted by a direct push · C2 = C1 reverted through PR #27
#   E1 = #28 reverted through PR #29 · E2 = E1 reverted by a direct push: on git 2.43 and later
#        `Reapply "feat: v (#28)" (#29)`, whose subject alone reads #29
#   #30 — squashed from a branch commit, which is then pruned; F = that pruned branch commit
#        reverted through PR #31: the commit its revert line names is not an ancestor of F and is
#        unreadable in this full clone, so the line is ignored and the subject rule reads #31
#   #50 · #51 — multi-commit PRs whose branch holds a `git revert`, squashed with GitHub's default
#        body, which keeps the branch revert's `This reverts commit <branch-sha>.` line; the branch
#        is kept for #50 (readable, not an ancestor) and deleted for #51 (unreadable): both are
#        credited
#   #40 — the same, where the branch's own commit is titled `(#40)` as well: the squash shares the
#        reverted commit's number and is still #40
#   U  — a hand-written `Revert "feat: x (#21)` with no body line and a quote never closed: the
#        subject rule reads all of it as the original
#   M  — `Merge branch 'r'` (no PR number) whose side is one direct-push revert of #24: the merge-side
#        walk reads the same primitive, so M is a row of its own.
RVT="$RV/revert"
g init -q "$RVT"
echo 0 > "$RVT/f"; g -C "$RVT" add f; g -C "$RVT" commit -qm "chore: init"; g -C "$RVT" tag v0.1.0
_rvtc() { echo "$RANDOM" >> "$RVT/$1"; g -C "$RVT" add "$1"; g -C "$RVT" commit -qm "$2"; g -C "$RVT" rev-parse HEAD; }
_rvtr() { # <sha> [<pr>] — `git revert` <sha>; with <pr>, append the squash ` (#<pr>)`. Prints the new sha.
  g -C "$RVT" revert --no-edit "$1" >/dev/null
  if [ -n "${2:-}" ]; then
    g -C "$RVT" commit -q --amend -m "$(g -C "$RVT" log -1 --format=%s) (#$2)" -m "$(g -C "$RVT" log -1 --format=%b)"
  fi
  g -C "$RVT" rev-parse HEAD
}
RVT_21="$(_rvtc a "feat: x (#21)")"; RVT_22="$(_rvtc b "fix: y (#22)")"
RVT_23="$(_rvtc c "docs: z (#23)")"; RVT_24="$(_rvtc e "chore: w (#24)")"
RVT_A1="$(_rvtr "$RVT_21")"; RVT_A2="$(_rvtr "$RVT_A1")"; RVT_A3="$(_rvtr "$RVT_A2")"
RVT_B1="$(_rvtr "$RVT_22" 25)"; RVT_B2="$(_rvtr "$RVT_B1" 26)"
RVT_C1="$(_rvtr "$RVT_23")"; RVT_C2="$(_rvtr "$RVT_C1" 27)"
RVT_28="$(_rvtc v "feat: v (#28)")"; RVT_E1="$(_rvtr "$RVT_28" 29)"; RVT_E2="$(_rvtr "$RVT_E1")"
g -C "$RVT" checkout -qb gone; RVT_GONE="$(_rvtc q "chore: q")"; g -C "$RVT" checkout -q main
g -C "$RVT" cherry-pick -n "$RVT_GONE"; g -C "$RVT" commit -qm "chore: q (#30)"; RVT_30="$(g -C "$RVT" rev-parse HEAD)"; RVT_F="$(_rvtr "$RVT_GONE" 31)"
# A multi-commit PR whose branch holds a `git revert`, squashed with GitHub's default body, which
# lists the branch revert's `This reverts commit <branch-sha>.` line. _rvtq <pr> <file> <keep|prune>.
_rvtq() {
  local br="q$1" w r
  g -C "$RVT" checkout -qb "$br"; w="$(_rvtc "$2" "wip $1")"; r="$(_rvtr "$w")"
  g -C "$RVT" checkout -q main
  g -C "$RVT" commit -q --allow-empty -m "feat: g$1 (#$1)" -m "* wip $1

* $(g -C "$RVT" log -1 --format=%s "$r")

$(g -C "$RVT" log -1 --format=%b "$r")"
  RVT_Q="$(g -C "$RVT" rev-parse HEAD)"; RVT_QW="$w"
  if [ "$3" = prune ]; then g -C "$RVT" branch -qD "$br"; fi
}
_rvtq 50 g50 keep;  RVT_Q50="$RVT_Q"; RVT_Q50W="$RVT_QW"
_rvtq 51 g51 prune; RVT_Q51="$RVT_Q"; RVT_Q51W="$RVT_QW"
# The coincidence: the branch's own commit carries `(#40)`, is reverted on the branch, and the
# squash is titled `(#40)` too, so its body line names a reverted commit with the squash's number.
g -C "$RVT" checkout -qb q40; RVT_H="$(_rvtc h40 "feat: h (#40)")"; RVT_HR="$(_rvtr "$RVT_H")"
g -C "$RVT" checkout -q main
g -C "$RVT" commit -q --allow-empty -m "feat: h (#40)" -m "$(g -C "$RVT" log -1 --format=%b "$RVT_HR")"; RVT_Q40="$(g -C "$RVT" rev-parse HEAD)"
g -C "$RVT" branch -qD gone; g -C "$RVT" reflog expire --expire=now --all; g -C "$RVT" gc -q --prune=now
RVT_U="$(_rvtc d 'Revert "feat: x (#21)')"
g -C "$RVT" checkout -qb r "$RVT_U"; _rvtr "$RVT_24" >/dev/null
g -C "$RVT" checkout -q main
g -C "$RVT" merge -q --no-ff r -m "Merge branch 'r'"; RVT_M="$(g -C "$RVT" rev-parse HEAD)"
echo '{}' > "$RVT/.release-pr.json"
# _rvt_row <sha> [<pr>] — the row a unit renders: its own ` (#<pr>)` dropped, nothing else.
_rvt_row() { local s; s="$(g -C "$RVT" log -1 --format=%s "$1")"; if [ -n "${2:-}" ]; then printf -- '- **#%s** %s\n' "$2" "${s% (#$2)}"; else printf -- '- %s\n' "$s"; fi; }
_rvt_h() { g -C "$RVT" rev-parse --short "$1"; }
: > "$RV/log"; RV_RC=0
( cd "$RVT" && env -u RELEASE_PR_REVIEW_VERIFIER -u RELEASE_PR_REVIEW_VERIFIER_TIMEOUT \
    PATH="$RVB:$RV_PATH" GITHUB_REPOSITORY=acme/widget RV_LOG="$RV/log" \
    "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD ) >"$RV/out" 2>"$RV/err" || RV_RC=$?
RV_OUT="$(cat "$RV/out")"; RV_ERR="$(cat "$RV/err")"; RV_CALLS="$(cat "$RV/log")"
RV_LINE="$(printf '%s\n' "$RV_OUT" | awk 'p { print; exit } $0 == "## Bundled (generated — do not hand-edit)" { p = 1 }')"
RVT_ROWS="$(printf '%s\n' "$RV_OUT" | awk '/^## Bundled/ { p = 1; next } /^## / { p = 0 } p && /^- /')"
eq "fixture: the reverted #30 commit is gone, so F's revert line names nothing readable" \
   "false" "$(g -C "$RVT" cat-file -e "$RVT_GONE^{commit}" 2>/dev/null && echo true || echo false)"
eq "fixture: the pruned branch revert of #51 is gone; the kept one of #50 and #40 are not" \
   "false|true|true" "$(for c in "$RVT_Q51W" "$RVT_Q50W" "$RVT_H"; do g -C "$RVT" cat-file -e "$c^{commit}" 2>/dev/null && printf true || printf false; printf '|'; done | sed 's/|$//')"
eq "fixture: a through-a-PR revert keeps git's \`This reverts commit\` line, as a squash does" \
   "true" "$(has "This reverts commit $RVT_22" "$(g -C "$RVT" log -1 --format=%b "$RVT_B1")")"
eq "a range with direct-push reverts → rc 0"              "0" "$RV_RC"
eq "a direct-push revert, of any depth, carries no PR number; a revert made through a PR carries its own" \
"$(_rvt_row "$RVT_M"; _rvt_row "$RVT_U"; _rvt_row "$RVT_Q40" 40; _rvt_row "$RVT_Q51" 51; _rvt_row "$RVT_Q50" 50
   _rvt_row "$RVT_F" 31; _rvt_row "$RVT_30" 30
   _rvt_row "$RVT_E2"; _rvt_row "$RVT_E1" 29; _rvt_row "$RVT_28" 28; _rvt_row "$RVT_C2" 27; _rvt_row "$RVT_C1"
   _rvt_row "$RVT_B2" 26; _rvt_row "$RVT_B1" 25; _rvt_row "$RVT_A3"; _rvt_row "$RVT_A2"; _rvt_row "$RVT_A1"
   _rvt_row "$RVT_24" 24; _rvt_row "$RVT_23" 23; _rvt_row "$RVT_22" 22; _rvt_row "$RVT_21" 21)" "$RVT_ROWS"
eq "…a direct-push reapply of revert-PR #29 is not credited to #29" "false" "$(has "**#29** $(g -C "$RVT" log -1 --format=%s "$RVT_E2" | sed 's/ (#29)$//')" "$RVT_ROWS")"
eq "…the direct-push reverts and reapplies, and only those, are not measured" \
   "Review: 14 of 21 bundled changes have an independent review record; not measured: $(_rvt_h "$RVT_M"), $(_rvt_h "$RVT_U"), $(_rvt_h "$RVT_E2"), $(_rvt_h "$RVT_C1"), $(_rvt_h "$RVT_A3"), $(_rvt_h "$RVT_A2"), $(_rvt_h "$RVT_A1")." "$RV_LINE"
eq "…and the verifier is asked about each bundled PR once" \
   "$(printf 'acme/widget#%s\n' 21 22 23 24 25 26 27 28 29 30 31 40 50 51)" "$(printf '%s\n' "$RV_CALLS" | sort)"

# THE ONE PATH THAT STAYS NOT MEASURED: a revert whose reverted commit is unreadable in a SHALLOW
# clone, where it may be an ancestor the clone cut off. History: x (#60) · base · a squash revert of
# x through PR #61; a depth-2 clone holds the last two commits only.
SH="$RV/shal-src"; g init -q "$SH"
echo 0 > "$SH/f"; g -C "$SH" add f; g -C "$SH" commit -qm "chore: init"
echo 1 > "$SH/f"; g -C "$SH" commit -qam "feat: s (#60)"; SH_S="$(g -C "$SH" rev-parse HEAD)"
echo 2 > "$SH/o"; g -C "$SH" add o; g -C "$SH" commit -qm "chore: base"; g -C "$SH" tag v0.1.0
g -C "$SH" revert --no-edit "$SH_S" >/dev/null
g -C "$SH" commit -q --amend -m "Revert \"feat: s (#60)\" (#61)" -m "This reverts commit $SH_S."
rm -rf "$RV/shal"; g clone -q --depth 2 "file://$SH" "$RV/shal" 2>/dev/null
echo '{}' > "$RV/shal/.release-pr.json"
: > "$RV/log"; SH_RC=0
( cd "$RV/shal" && env -u RELEASE_PR_REVIEW_VERIFIER -u RELEASE_PR_REVIEW_VERIFIER_TIMEOUT \
    PATH="$RVB:$RV_PATH" GITHUB_REPOSITORY=acme/widget RV_LOG="$RV/log" \
    "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD ) >"$RV/sh-out" 2>/dev/null || SH_RC=$?
SH_LINE="$(awk 'p { print; exit } $0 == "## Bundled (generated — do not hand-edit)" { p = 1 }' "$RV/sh-out")"
eq "fixture: the clone is shallow and cannot read the reverted commit" \
   "true|false" "$(g -C "$RV/shal" rev-parse --is-shallow-repository)|$(g -C "$RV/shal" cat-file -e "$SH_S^{commit}" 2>/dev/null && echo true || echo false)"
eq "a revert whose reverted commit is unreadable in a shallow clone is not measured, not credited" \
   "0|Review: 0 of 1 bundled changes have an independent review record; not measured: $(g -C "$RV/shal" rev-parse --short HEAD)." "$SH_RC|$SH_LINE"
eq "…and the verifier is not asked about it" "" "$(cat "$RV/log")"

echo "== a card or DL a revert names is not shipped; a reverted change is named in the body (card#11602) =="
# THE DEFECT: `feat: x DL-5 (closes card#7) (#21)` is squash-merged, then `git revert`ed by a direct
# push whose subject is `Revert "feat: x DL-5 (closes card#7) (#21)"`. The manifests read every
# subject in the range for its tokens, the revert's included, so card#7 and DL-5 were SHIPPED and
# the promoter moved card#7 to its released stage with its work gone. A revert is known by git's
# `This reverts commit <sha>` body line, never by its subject; it ships no card or DL of its own,
# and a change it reverts inside the range ships nothing. On separate files, oldest → newest:
#   Z  `feat: z DL-2 (card#3) (#11)` — tagged v0.1.0, so OUTSIDE the range
#   O  `feat: x DL-5 (closes card#7) (#21)` · K `fix: keep DL-6 (card#8) (#23)`
#   R  O reverted by a direct push
#   P  `fix: a (#12) and b card#9` — its `(#12)` is not trailing, so it is no PR number, in this
#      tool as in the promoter (one rule, not two)
#   Y  `fix: y (card#4) (#22)` · Y1 = Y reverted through PR #25 · Y2 = Y1 reverted by a direct
#      push, spelled as git 2.43 and later spell it whatever git wrote it here:
#      `Reapply "fix: y (card#4) (#22)" (#25)` — Y is back, so card#4 ships; #25 does not
#   RZ Z reverted by a direct push — its original shipped before this range
RX="$T/rx"; g init -q "$RX"
_rxc() { echo "$RANDOM" >> "$RX/$1"; g -C "$RX" add "$1"; g -C "$RX" commit -qm "$2"; g -C "$RX" rev-parse HEAD; }
_rxr() { g -C "$RX" revert --no-edit "$1" >/dev/null; g -C "$RX" rev-parse HEAD; }
echo 0 > "$RX/f"; g -C "$RX" add f; g -C "$RX" commit -qm "chore: init"
RX_Z="$(_rxc z "feat: z DL-2 (card#3) (#11)")"; g -C "$RX" tag v0.1.0
RX_O="$(_rxc o "feat: x DL-5 (closes card#7) (#21)")"; RX_K="$(_rxc k "fix: keep DL-6 (card#8) (#23)")"
RX_R="$(_rxr "$RX_O")"
RX_P="$(_rxc p "fix: a (#12) and b card#9")"
RX_Y="$(_rxc y "fix: y (card#4) (#22)")"
RX_Y1="$(_rxr "$RX_Y")"
g -C "$RX" commit -q --amend -m "Revert \"fix: y (card#4) (#22)\" (#25)" -m "This reverts commit $RX_Y."; RX_Y1="$(g -C "$RX" rev-parse HEAD)"
g -C "$RX" revert --no-edit "$RX_Y1" >/dev/null
g -C "$RX" commit -q --amend -m "Reapply \"fix: y (card#4) (#22)\" (#25)" -m "This reverts commit $RX_Y1."; RX_Y2="$(g -C "$RX" rev-parse HEAD)"
RX_RZ="$(_rxr "$RX_Z")"
echo '{"ref_token_regex":"DL-[0-9]+","card_token_regex":"card#[0-9]+"}' > "$RX/.release-pr.json"
_rxh() { g -C "$RX" rev-parse --short "$1"; }
_rx() { (cd "$RX" && env -u RELEASE_PR_REVIEW_VERIFIER RELEASE_PR_REVIEW_VERIFIER=off "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD "$@"); }
eq "fixture: R carries git's \`This reverts commit\` line naming O" "true" "$(has "This reverts commit $RX_O" "$(g -C "$RX" log -1 --format=%b "$RX_R")")"
RX_RC=0; RX_OUT="$(_rx 2>"$T/rx-err")" || RX_RC=$?
RX_ROWS="$(printf '%s\n' "$RX_OUT" | awk '/^## Bundled/ { p = 1; next } /^## / { p = 0 } p && /^- /')"
eq "a range holding reverts → rc 0" "0" "$RX_RC"
eq "--card-manifest: a reverted change's card, and a card only a revert names, are not shipped" \
   "4 8 9" "$(_rx --card-manifest 2>/dev/null | sort -n | paste -sd' ' -)"
eq "--manifest: the same, for DL refs" "DL-6" "$(_rx --manifest 2>/dev/null | paste -sd' ' -)"
eq "…the body's shipped-cards footer agrees" "true" "$(has '<!-- release-manifest:shipped-cards=' "$RX_OUT")"
eq "…and carries none of 3, 7" "4,8,9" "$(printf '%s\n' "$RX_OUT" | sed -nE 's/^<!-- release-manifest:shipped-cards=([0-9,]*) -->$/\1/p' | tr ',' '\n' | sort -n | paste -sd, -)"
eq "the body names the change reverted inside the range, with the refs it no longer ships" \
   "true" "$(has_line "Reverted in this range, so not shipped by it: #21 (DL-5, card#7), reverted by $(_rxh "$RX_R")." "$RX_OUT")"
eq "…and the change this range reverts that shipped before it" \
   "true" "$(has_line "Reverted by this range, shipped before it: #11 (DL-2, card#3), reverted by $(_rxh "$RX_RZ")." "$RX_OUT")"
eq "…a reapplied change is not named reverted, and neither is the revert that was itself reverted" \
   "false|false" "$(has '#22' "$(printf '%s\n' "$RX_OUT" | grep '^Reverted' || true)")|$(has '#25' "$(printf '%s\n' "$RX_OUT" | grep '^Reverted' || true)")"
eq "…both lines sit inside the generated \`## Bundled\` section, never under an H2 of their own" \
   "## Bundled (generated — do not hand-edit)" "$(printf '%s\n' "$RX_OUT" | awk '/^## / { h = $0 } /^Reverted/ { print h; exit }')"
eq "\`fix: a (#12) and b\` is no PR number: its row carries none" "true" "$(has_line "- (\`card#9\`) fix: a (#12) and b card#9" "$RX_ROWS")"
eq "a direct-push \`Reapply \"… (#22)\" (#25)\` of revert-PR #25 carries no PR number" \
   "true" "$(has_line "- (\`card#4\`) Reapply \"fix: y (card#4) (#22)\" (#25)" "$RX_ROWS")"

# THE SHARED PRIMITIVE'S OWN ANSWER, which bin/promote-released-cards reads instead of parsing a
# subject of its own: `<class> US <sha> US <shipped pr> US <related sha(s)> US <shipped text>`.
RX_CC="$(cd "$RX" && "$BIN" --classify-commits --base v0.1.0 --head HEAD 2>&1)" && RX_CC_RC=0 || RX_CC_RC=$?
_rxcc() { printf '%s\n' "$RX_CC" | awk -v s="$1" 'BEGIN { FS = "\037" } $2 == s { print $1 "|" $3 "|" $4 "|" $5 }'; }
eq "--classify-commits → rc 0" "0" "$RX_CC_RC"
eq "…O is reverted by R and ships nothing" "reverted||$RX_R|" "$(_rxcc "$RX_O")"
eq "…R is a revert of O: no PR, no shipped text" "revert||$RX_O|" "$(_rxcc "$RX_R")"
eq "…K ships #23 and its subject" "shipped|23||fix: keep DL-6 (card#8) (#23)" "$(_rxcc "$RX_K")"
eq "…P ships no PR number" "shipped|||fix: a (#12) and b card#9" "$(_rxcc "$RX_P")"
eq "…Y is back, and ships #22" "shipped|22||fix: y (card#4) (#22)" "$(_rxcc "$RX_Y")"
eq "…Y1, revert-PR #25, was itself reverted and ships nothing" "revert-reverted||$RX_Y2|" "$(_rxcc "$RX_Y1")"
eq "…Y2, the direct-push reapply, has no PR number of its own" "revert||$RX_Y1|" "$(_rxcc "$RX_Y2")"
eq "…RZ reverts Z, which is outside the range" "revert||$RX_Z|" "$(_rxcc "$RX_RZ")"
eq "…one row per non-merge commit in the range, and no other" \
   "$(g -C "$RX" rev-list --no-merges v0.1.0..HEAD | sort)" "$(printf '%s\n' "$RX_CC" | awk 'BEGIN { FS = "\037" } { print $2 }' | sort)"
RX_CC_BAD_RC=0; (cd "$RX" && "$BIN" --classify-commits --head HEAD) >/dev/null 2>&1 || RX_CC_BAD_RC=$?
eq "--classify-commits without --base refuses rc 2 rather than fetching or guessing one" "2" "$RX_CC_BAD_RC"

# A REVERTED MERGE COMMIT takes back every commit on its merged side: `git revert -m 1` of a PR merged
# with a merge commit names the merge in its body line, and the merge is no row of commit_rows' own
# (it reads non-merge commits), so the side commit is what must stop shipping.
MX="$T/mx"; g init -q "$MX"
echo 0 > "$MX/f"; g -C "$MX" add f; g -C "$MX" commit -qm "chore: init"; g -C "$MX" tag v0.1.0
g -C "$MX" checkout -qb m; echo 1 > "$MX/m"; g -C "$MX" add m; g -C "$MX" commit -qm "feat: m DL-8 (card#10) (#30)"
g -C "$MX" checkout -q main; echo 2 > "$MX/o"; g -C "$MX" add o; g -C "$MX" commit -qm "fix: other (#29)"
g -C "$MX" merge -q --no-ff m -m "Merge pull request #31 from acme/m"; MX_M="$(g -C "$MX" rev-parse HEAD)"
g -C "$MX" revert --no-edit -m 1 "$MX_M" >/dev/null; MX_R="$(g -C "$MX" rev-parse HEAD)"
echo '{"ref_token_regex":"DL-[0-9]+","card_token_regex":"card#[0-9]+"}' > "$MX/.release-pr.json"
_mx() { (cd "$MX" && RELEASE_PR_REVIEW_VERIFIER=off "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD "$@"); }
eq "fixture: the merge's revert names the merge in its body line" "true" "$(has "This reverts commit $MX_M" "$(g -C "$MX" log -1 --format=%b "$MX_R")")"
eq "a reverted merge: the card on its merged side is not shipped" "" "$(_mx --card-manifest 2>/dev/null)"
eq "…nor its DL" "" "$(_mx --manifest 2>/dev/null)"
eq "…and the body names the side commit as reverted in the range" \
   "true" "$(has_line "Reverted in this range, so not shipped by it: #30 (DL-8, card#10), reverted by $(g -C "$MX" rev-parse --short "$MX_R")." "$(_mx 2>/dev/null)")"

# A SHALLOW CLONE CANNOT READ WHAT A REVERT REVERTS, so that commit is not measured: it ships
# nothing, and the body says so by name rather than leaving its refs out in silence. History:
# init · T `feat: t DL-9 (card#6) (#60)` · B (tagged v0.1.0) · RT = T reverted by a direct push ·
# Q `feat: q (card#5) (#62)`; a depth-3 clone holds Q, RT and B, not T.
SX="$T/sx-src"; g init -q "$SX"
echo 0 > "$SX/f"; g -C "$SX" add f; g -C "$SX" commit -qm "chore: init"
echo 1 > "$SX/t"; g -C "$SX" add t; g -C "$SX" commit -qm "feat: t DL-9 (card#6) (#60)"; SX_T="$(g -C "$SX" rev-parse HEAD)"
echo 2 > "$SX/b"; g -C "$SX" add b; g -C "$SX" commit -qm "chore: base"; g -C "$SX" tag v0.1.0
g -C "$SX" revert --no-edit "$SX_T" >/dev/null; SX_RT="$(g -C "$SX" rev-parse HEAD)"
echo 3 > "$SX/q"; g -C "$SX" add q; g -C "$SX" commit -qm "feat: q (card#5) (#62)"
rm -rf "$T/sx"; g clone -q --depth 3 "file://$SX" "$T/sx" 2>/dev/null
echo '{"ref_token_regex":"DL-[0-9]+","card_token_regex":"card#[0-9]+"}' > "$T/sx/.release-pr.json"
eq "fixture: the clone is shallow and cannot read T" \
   "true|false" "$(g -C "$T/sx" rev-parse --is-shallow-repository)|$(g -C "$T/sx" cat-file -e "$SX_T^{commit}" 2>/dev/null && echo true || echo false)"
_sx() { (cd "$T/sx" && RELEASE_PR_REVIEW_VERIFIER=off "$BIN" --version 0.2.0 --base v0.1.0 --head HEAD "$@"); }
eq "shallow: the unmeasured revert's card is not shipped" "5" "$(_sx --card-manifest 2>/dev/null | paste -sd' ' -)"
eq "shallow: nor its DL" "" "$(_sx --manifest 2>/dev/null)"
SX_OUT="$(_sx 2>/dev/null)" || true
eq "shallow: the body names the revert as not measured, by short sha" \
   "true" "$(has "Not measured for a revert: $(g -C "$T/sx" rev-parse --short "$SX_RT")" "$SX_OUT")"
eq "shallow: --classify-commits says unmeasured, never shipped" \
   "unmeasured" "$(cd "$T/sx" && "$BIN" --classify-commits --base v0.1.0 --head HEAD | awk -v s="$SX_RT" 'BEGIN { FS = "\037" } $2 == s { print $1 }')"

_summary "release-pr-body-selftest"
