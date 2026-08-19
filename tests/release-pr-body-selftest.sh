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
  "main_branch": "main",
  "dev_branch": "dev",
  "ref_token_regex": "$1",
  "title_prefix": "Release",
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
# without a board token, so they all take the "_Not checked here_" branch.
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
  "main_branch": "main",
  "dev_branch": "dev",
  "ref_token_regex": "DL-[0-9]+",
  "card_token_regex": "card#[0-9]+",
  "title_prefix": "Release",
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
eq "…and the section is not the never-checked branch" "false" "$(has 'Not checked here' "$covmiss")"
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
{ "main_branch": "main", "dev_branch": "dev", "title_prefix": "Release",
  "promote": { "board_id": 12, "released_stage_id": 85, "api_base": "https://kanban.test/api/v3" } }
EOF
rc=0; notok="$(coverage_body)" || rc=$?
eq "no token keys → still rc 0"                  "0"     "$rc"
eq "…body is complete"                           "true"  "$(has '## Bundled' "$notok")"
eq "…and the coverage section is omitted whole"  "false" "$(has '## Card coverage' "$notok")"
unset BOARD_FILE

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

_summary "release-pr-body-selftest"
