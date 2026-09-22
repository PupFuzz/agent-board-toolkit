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
# ⚠ WHAT IT CANNOT SEE: a NEW gate the fixture happens to satisfy passes the control unnoticed —
# the falsifier table is only as wide as the header it reads.
cov_err() {  # <config> <token> <PATH> <bin> — the run's stderr on stdout
  ( cd "$CR" && PATH="$3" KANBAN_WRITEBACK_TOKEN="$2" KANBAN_EXPECTED_HOST=kanban.test \
      "$4" --config "$1" --version 0.2.0 --base v0.1.0 --head HEAD 2>&1 >/dev/null ) || true
}
_pc_path="$COV/bin:$HERE/../bin:$PATH"
cp "$CR/.release-pr.json" "$COV/pc-all.json"
_pc_declared="$(sed -n 's/^#   precondition: \([a-z-]*\) .*/\1/p' "$BIN" | sort | paste -sd' ' -)"
eq "the header declares exactly the preconditions this block can falsify" \
   "board-id promoter token-regex writeback-token" "$_pc_declared"
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
unset -f cov_err
unset _pc _pc_err _pc_path _pc_declared

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

_summary "release-pr-body-selftest"
