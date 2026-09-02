#!/usr/bin/env bash
# promote-source-qualify-selftest.sh — deterministic, network-free end-to-end checks for the
# REPO QUALIFICATION guard (`.promote.source` / `--source`) in bin/promote-released-cards.
#
# WHY THIS FILE EXISTS (card#8421). `dl_number` and `pr_number` are REPO-SCOPED counters: repo
# A's PR #15 and repo B's PR #15 are different pull requests wearing the same number. This tool
# correlated on the BARE number and writes into a TERMINAL stage, so on a board tracking several
# repos it promoted OTHER repos' cards. Measured by a reporting peer on a three-repo board: one
# release's 15 shipped PRs matched 24 cards across all three lanes, including cards already at a
# released stage from a different repo's version line.
#
# The fix is a REQUIRED `.promote.source` with no default — absent is a refusal before any read
# — plus `"*"` as the explicit single-repo DECLARATION that restores the prior behaviour byte
# for byte. Both halves are properties an ordinary refactor can silently drop, which is what
# this file is for: § 6 runs a MUTATION BATTERY, re-driving § 4's fixture against copies of the
# bin with each half removed, and asserts the observable FLIPS. A guard nothing can red is a
# decoration (canon #9), and the mutants are how these arms are shown to discriminate rather
# than merely to pass.
#
# SCOPE — what a green run here proves, at its weakest:
#   * a config with no `source` refuses at rc 2, before any board GET and before any PATCH,
#     with a message naming the key, the file and the `"*"` answer;
#   * the accept set for the value is exactly `<owner>/<repo>` or `*`, case-folded and trimmed;
#   * on one shipped ref, a qualified run promotes only THIS repo's card, names the other
#     repo's and the unattributable one, and counts both;
#   * a `"*"` run over the same fixture promotes all of them and prints the pre-card#8421
#     summary line byte for byte;
#   * the card source is derived through the server's field-preference order;
#   * `--source` beats the config, and `--cards` is exempt and says so.
# It proves nothing about a live board, and nothing about the server's own normalizer beyond
# the corpus in § 5 — that mirror is bound by this corpus, not by inspection.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
PRC="$HERE/../bin/promote-released-cards"
_need -x "$PRC"

_mktmp_scratch --home

# shellcheck source=/dev/null
source "$HERE/_promote-curl-stub.sh"
promote_install_curl_stub "$TMP/bin"

export KANBAN_WRITEBACK_TOKEN=tkn
export KANBAN_EXPECTED_HOST=kanban.test
export PATCH_LOG="$TMP/patches.log"
export BOARD_FILE="$TMP/board.json"

# mkcfg <path> <source-json-or-OMIT> — a promote config, with or without the key under test.
mkcfg() {
  if [ "$2" = OMIT ]; then
    jq -n '{ref_token_regex:"DL-[0-9]+",promote:{board_id:"12",released_stage_id:"85",api_base:"https://kanban.test/api/v3"}}' > "$1"
  else
    jq -n --arg s "$2" '{ref_token_regex:"DL-[0-9]+",promote:{board_id:"12",released_stage_id:"85",api_base:"https://kanban.test/api/v3",source:$s}}' > "$1"
  fi
}
CFG_NONE="$TMP/cfg-none.json";  mkcfg "$CFG_NONE" OMIT
CFG_STAR="$TMP/cfg-star.json";  mkcfg "$CFG_STAR" '*'
CFG_REPO="$TMP/cfg-repo.json";  mkcfg "$CFG_REPO" 'acme/widget'

# THE BOARD, and every row of it is load-bearing. One shipped ref (PR 15) matches four cards:
#   #1 belongs to acme/widget — the release's own repo, the only card a qualified run may move;
#   #2 belongs to acme/other  — the card#8421 defect, held still: same number, different repo;
#   #3 has no source-yielding field at all — unattributable, so a qualified run must not move it;
#   #4 carries an UNRELATED PR number and must stay put under every configuration, which is what
#      separates "the guard works" from "this run matched nothing".
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"pr_number":"15","pr_url":"https://github.com/acme/widget/pull/15"}},
  {"id":2,"workflow_stage_id":51,"payload":{"pr_number":"15","pr_url":"https://github.com/acme/other/pull/15"}},
  {"id":3,"workflow_stage_id":51,"payload":{"pr_number":"15"}},
  {"id":4,"workflow_stage_id":51,"payload":{"pr_number":"99","pr_url":"https://github.com/acme/widget/pull/99"}}
],"meta":{"last_page":1,"total":4}}
JSON

# The PR leg has no flag: shipped PR numbers come from the trailing `(#NNN)` squash marker in
# `git log <base>..<head>`. The tip is a MERGE commit, so the 0-promoted completeness die has
# nothing to say about this fixture either way, and $GITHUB_ACTIONS is pinned so the
# derived-baseline NOTE is suppressed identically here and on a runner.
GITDIR="$TMP/gitfx"; mkdir -p "$GITDIR"
git -C "$GITDIR" init -q -b main
git -C "$GITDIR" config user.email t@t
git -C "$GITDIR" config user.name t
git -C "$GITDIR" commit -q --allow-empty -m "baseline"
git -C "$GITDIR" tag v0.0.1
git -C "$GITDIR" checkout -q -b feat
git -C "$GITDIR" commit -q --allow-empty -m "feat: a thing (#15)"
git -C "$GITDIR" checkout -q main
git -C "$GITDIR" merge -q --no-ff feat -m "Merge feat"

# run_bin <bin> <config> <extra-args...> — <bin> over the git fixture, capturing rc / stdout
# (out) / stderr (err) / the PATCH set (patched) / the GET set (gets).
run_bin() {
  local bin="$1" cfg="$2"; shift 2
  : > "$PATCH_LOG"; : > "$TMP/gets.log"; rc=0
  out="$( (cd "$GITDIR" && env GITHUB_ACTIONS=1 GET_LOG="$TMP/gets.log" "$bin" --config "$cfg" "$@") 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"; gets="$(cat "$TMP/gets.log")"
}
run_promote() { run_bin "$PRC" "$@"; }
moved() { has "/tasks/$1.json" "$patched"; }

# ───────────────────────────────────────────────────────────────────────────────────────────
echo "== 1. .promote.source ABSENT → refuse, BEFORE any read, naming its own fix =="
# "Before any read" is the load-bearing half and is asserted on the GET log, not inferred from
# the absence of a PATCH: a run that read the board and then declined to move anything would
# satisfy an empty PATCH set while having already sent the writeback token.
run_promote "$CFG_NONE"
eq "no source → dies rc 2"                          "2"     "$rc"
eq "…no card was PATCHed"                           ""      "$patched"
eq "…and NO board GET was issued at all"            ""      "$gets"
eq "…no summary line was printed"                   "false" "$(has 'moved,' "$out")"
eq "refusal names the key"                          "true"  "$(has '.promote.source' "$err")"
eq "…says it is REQUIRED with no default"           "true"  "$(has 'REQUIRED and has no default' "$err")"
eq "…names the FILE the key goes in"                "true"  "$(has "$CFG_NONE" "$err")"
eq "…names the promote block it goes in"            "true"  "$(has 'promote' "$err")"
eq "…spells the multi-repo answer"                  "true"  "$(has '"source": "<owner>/<repo>"' "$err")"
eq "…spells the SINGLE-repo answer"                 "true"  "$(has '"source": "*"' "$err")"
eq "…names the flag that overrides it"              "true"  "$(has '--source' "$err")"
eq "…states WHY (repo-scoped counters)"             "true"  "$(has 'REPO-SCOPED counters' "$err")"

echo "== 1b. the token guard is NOT what refused (the check is genuinely earlier) =="
# Without this the arm above is satisfied by any refusal at all. Same config, a token present:
# still refused, and still on the source. And the CONTROL in the other direction — a config
# that DOES carry the key gets past this point and reaches the board.
eq "…the refusal is not about the token"            "false" "$(has 'KANBAN_WRITEBACK_TOKEN' "$err")"
run_promote "$CFG_STAR"
eq "control: a config WITH the key reaches the board" "true" "$(has '/tasks/search.json' "$gets")"

echo "== 2. an explicitly EMPTY --source dies; it never falls through to the config =="
# The card#5144 shape, one flag over: a `${X:-$(cfg …)}` resolution would let an unexpanded
# shell variable run UNGUARDED off a `"*"` config while the caller believed it had qualified.
run_promote "$CFG_STAR" --source ""
eq "--source \"\" → dies rc 2"                      "2"     "$rc"
eq "…naming the flag"                               "true"  "$(has '--source requires a non-empty value' "$err")"
eq "…and nothing was PATCHed"                       ""      "$patched"
run_promote "$CFG_STAR" --source
eq "a trailing --source with no argument → rc 2"    "2"     "$rc"
eq "…names the flag, not an unbound variable"       "true"  "$(has '--source requires a non-empty value' "$err")"
eq "…no set -u leak"                                "false" "$(has 'unbound variable' "$err")"

echo "== 3. the accept set is exactly '<owner>/<repo>' or '*' =="
# Each rejected row is a spelling that would otherwise look CONFIGURED while correlating to
# nothing — a silently zero-promotion release, which is worse than the refusal it replaces.
# `<value>|<needle the refusal must carry>`.
for row in \
    "https://github.com/acme/widget|not a URL" \
    "git@github.com:acme/widget|only letters, digits" \
    "acme/widget.git|.git" \
    "acme/*|not a glob" \
    "*/widget|not a glob" \
    "**|not a glob" \
    "widget|or the single-repo declaration" \
    "acme/widget/extra|exactly" \
    "/widget|exactly" \
    "acme/|exactly" \
    "acme widget/x|whitespace" \
    "   |REQUIRED and has no default"; do
  bad="${row%%|*}"; needle="${row#*|}"
  run_promote "$CFG_STAR" --source "$bad"
  eq "--source '$bad' → rc 2"                       "2"     "$rc"
  eq "--source '$bad' → nothing PATCHed"            ""      "$patched"
  eq "--source '$bad' → refusal says why"           "true"  "$(has "$needle" "$err")"
done
# POSITIVE CONTROLS — without them a validator that refused EVERYTHING passes every row above.
# Canonicalisation is asserted here rather than separately: a trimmed and case-folded value must
# reach the SAME verdict as its canonical spelling (card #1 moves, card #2 does not).
for good in "acme/widget" "ACME/Widget" "  acme/widget  "; do
  run_promote "$CFG_STAR" --source "$good"
  eq "control: --source '$good' runs (rc 0)"        "0"     "$rc"
  eq "control: …and qualifies as acme/widget"       "true"  "$( [ "$(moved 1)" = true ] && [ "$(moved 2)" = false ] && echo true || echo false )"
done
run_promote "$CFG_STAR" --source '*'
eq "control: --source '*' runs (rc 0)"              "0"     "$rc"
eq "control: …and qualification is OFF"             "true"  "$(has 'repo-qualification OFF' "$err")"

echo "== 3b. a refusal echoes the OPERATOR'S spelling, not only the canonical one =="
# A message naming only the canonicalized value is a message the operator cannot GREP FOR. The
# worked case is the committed placeholder: `"source": "REPLACE_ME"` reads back as `replace_me`,
# which appears nowhere in their config or their workflow file, so the one search that would
# find the line they have to edit comes up empty.
run_promote "$CFG_STAR" --source "REPLACE_ME"
eq "the refusal carries the RAW spelling"           "true"  "$(has 'REPLACE_ME' "$err")"
run_promote "$CFG_STAR" --source "ACME/Widget.git"
eq "a mixed-case bad value shows the raw form"      "true"  "$(has 'ACME/Widget.git' "$err")"
eq "…and the canonical form it was checked as"      "true"  "$(has 'acme/widget.git' "$err")"
# CONTROL — an ALREADY-canonical value is rendered exactly once, so the "(canonicalized to …)"
# half is a real conditional and not noise appended to every message.
run_promote "$CFG_STAR" --source "acme/widget.git"
eq "an already-canonical value is not double-printed" "false" "$(has 'canonicalized to' "$err")"
eq "…and is still named"                              "true"  "$(has 'acme/widget.git' "$err")"

echo "== 4. THE DEFECT, held still: one shipped ref, three cards, two of them not ours =="
# This is card#8421 reproduced in miniature. Under `"*"` the tool promotes all three — that is
# the pre-fix behaviour and it is CORRECT there, because `*` is a declaration that no such
# collision exists on this board. Under a repo-qualified config the same fixture moves one.
run_promote "$CFG_STAR"
eq "star: rc 0"                                     "0"     "$rc"
eq "star: our own card #1 promoted"                 "true"  "$(moved 1)"
eq "star: the OTHER repo's card #2 also promoted"   "true"  "$(moved 2)"
eq "star: the unsourced card #3 also promoted"      "true"  "$(moved 3)"
eq "star: the unrelated PR 99 card #4 stays put"    "false" "$(moved 4)"
# The byte-identical claim: under `*` the summary is the line this tool printed before the key
# existed — no other-repo column, no unsourced column.
eq "star: summary is the pre-card#8421 line"        "3 moved, 0 already-released, 0 no-card, 0 failed." \
   "$(printf '%s' "$out" | sed -n 's/^promote-released-cards: //p' | grep 'moved,' || true)"
eq "star: the state line says qualification is OFF" "true"  "$(has 'repo-qualification OFF' "$err")"
eq "star: …and names the remedy for a multi-repo board" "true" "$(has "set .promote.source to '<owner>/<repo>'" "$err")"

run_promote "$CFG_REPO"
eq "qualified: rc 0"                                "0"     "$rc"
eq "qualified: our own card #1 IS promoted"         "true"  "$(moved 1)"
eq "qualified: the OTHER repo's card #2 is NOT"     "false" "$(moved 2)"
eq "qualified: the unsourced card #3 is NOT"        "false" "$(moved 3)"
eq "qualified: the unrelated card #4 still stays"   "false" "$(moved 4)"
eq "qualified: the foreign card is NAMED, by id"    "true"  "$(has '(#2): card source "acme/other" is NOT "acme/widget"' "$err")"
eq "qualified: …and says it was not promoted"       "true"  "$(has 'not promoted' "$err")"
eq "qualified: the unsourced card is NAMED, by id"  "true"  "$(has '(#3): card has NO by-ref source' "$err")"
eq "qualified: …and names the fix for it"           "true"  "$(has 'kbcard patch --pr-url' "$err")"
eq "qualified: both are COUNTED in the summary"     "true"  "$(has '1 other-repo, 1 unsourced,' "$out")"
eq "qualified: the state line says ON, with the repo" "true" "$(has "repo-qualification ON (source 'acme/widget'" "$err")"
eq "qualified: neither rejection changes the exit code" "0" "$rc"
eq "qualified: rejections go to stderr, not stdout" "false" "$(has 'DIFFERENT repo' "$out")"

echo "== 4b. GITHUB_STEP_SUMMARY carries the unsourced report (a green job hides stderr) =="
: > "$PATCH_LOG"; : > "$TMP/step-summary.md"; rc=0
( cd "$GITDIR" && env GITHUB_ACTIONS=1 GITHUB_STEP_SUMMARY="$TMP/step-summary.md" \
    "$PRC" --config "$CFG_REPO" ) >/dev/null 2>&1 || rc=$?
summ="$(cat "$TMP/step-summary.md")"
eq "step summary names the unsourced count"         "true"  "$(has '1 ref-matched card(s) had NO by-ref source' "$summ")"
eq "…and carries the per-card line"                 "true"  "$(has '(#3)' "$summ")"
eq "…and names the declared source"                 "true"  "$(has 'acme/widget' "$summ")"
# The FOREIGN list reaches the step summary too, and for the identical stated reason: the
# rejection is WARN-only, so it lands in a GREEN job, where a stderr line is invisible in a
# collapsed log. Its lines are the guard's proof it fired at all, which is the half an
# operator auditing a `.promote.source` change actually goes looking for.
eq "step summary names the other-repo count"        "true"  "$(has '1 ref-matched card(s) belong to ANOTHER repo' "$summ")"
eq "…and carries that card's per-card line"         "true"  "$(has '(#2)' "$summ")"
eq "…naming the repo it actually belongs to"        "true"  "$(has 'acme/other' "$summ")"

echo "== 4c. an UNSOURCED card's ref is NOT reported as 'no card' (the single-report contract) =="
# THE DEFECT THIS SECTION HOLDS STILL. `MATCHED_DLS` is computed from the PLAN — matches only —
# so under qualification the DL of a card the run REFUSED to attribute fell into $MISSING and
# was printed by the one `matched NO card` WARNING line. `bin/release-pr-body`'s coverage
# section greps exactly that line, so a release PR body told its author to "Create (or correct)
# a board card" for a card that is already on the board and needs a STAMP. The two kinds need
# OPPOSITE remedies, so they get two lines and release-pr-body reads both.
#
# `foreign` deliberately STAYS on the no-card line: "no card OF THIS REPO carries this ref" is
# exactly true of it, and the per-card ⊘ line above already names the other repo's card that
# did. Only `unsourced` moves, because only there does a card of possibly-this-repo exist.
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":42,"workflow_stage_id":51,"payload":{"dl_number":"DL-77"}},
  {"id":43,"workflow_stage_id":51,"payload":{"dl_number":"DL-88","pr_url":"https://github.com/acme/other/pull/2"}}
],"meta":{"last_page":1,"total":2}}
JSON
run_promote "$CFG_REPO" --dls "DL-77,DL-88,DL-99"
nocard_line="$(printf '%s\n' "$err" | grep -F 'matched NO card' || true)"
stranded_line="$(printf '%s\n' "$err" | grep -F 'matched ONLY an unsourced card' || true)"
eq "4c: rc 0"                                       "0"     "$rc"
eq "4c: nothing was promoted"                       ""      "$patched"
eq "4c: the genuinely cardless DL-99 IS on the no-card line" "true"  "$(has 'DL-99' "$nocard_line")"
eq "4c: the FOREIGN-only DL-88 stays on it"                 "true"  "$(has 'DL-88' "$nocard_line")"
eq "4c: the UNSOURCED card's DL-77 is NOT on it"            "false" "$(has 'DL-77' "$nocard_line")"
eq "4c: …it is reported on its OWN line"                    "true"  "$(has 'DL-77' "$stranded_line")"
eq "4c: …saying the card EXISTS and carries the ref"        "true"  "$(has 'the card exists and carries the ref' "$stranded_line")"
# The REMEDY belongs on the per-card ⊘ line, NOT on this one, and that is a constraint rather
# than a layout choice: release-pr-body cuts this line at its FIRST colon to get the ref list,
# so a `https://…` ahead of the refs would truncate it. The two lines together are the report.
eq "4c: …and the per-card line carries the remedy"          "true"  "$(has 'kbcard patch --pr-url' "$err")"
# THE CROSS-BIN CONTRACT, pinned on the PRODUCER side: release-pr-body extracts the ref list
# with this exact grep+sed, so the anchor phrase must carry no colon of its own. The consumer
# side is driven for real in tests/release-pr-body-selftest.sh — this arm is what reds HERE, in
# the file that owns the line, if a future edit puts a `https://…` ahead of the refs.
eq "4c: …and the consumer's reader extracts exactly the refs" "DL-77" \
   "$(printf '%s\n' "$err" | grep -oE 'matched ONLY an unsourced card[^:]*: .*' | sed 's/[^:]*: //')"
eq "4c: …and carries no OTHER ref"                          "false" "$(has 'DL-88' "$stranded_line")"
# The second line must not satisfy release-pr-body's no-card grep, or it re-creates the defect
# through the other door.
eq "4c: the new line does NOT read 'matched NO card'"       "false" "$(has 'matched NO card' "$stranded_line")"
eq "4c: the no-card COUNT excludes the unsourced ref"       "true"  "$(has '2 no-card,' "$out")"
# CONTROL — the SAME board and the SAME refs under the single-repo declaration. Card #42 is
# attributable there (qualification is off), so DL-77 is COVERED and there is no second line at
# all: the split above is the qualification's doing, not this fixture's.
run_promote "$CFG_STAR" --dls "DL-77,DL-88,DL-99"
eq "4c control: under '*' card #42 IS promoted"             "true"  "$(moved 42)"
eq "4c control: …DL-77 is on no report at all"              "false" "$(has 'DL-77' "$err")"
eq "4c control: …and no unsourced line is printed"          ""      "$(printf '%s\n' "$err" | grep -F 'matched ONLY an unsourced card' || true)"
# restore the four-card board for everything below
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"pr_number":"15","pr_url":"https://github.com/acme/widget/pull/15"}},
  {"id":2,"workflow_stage_id":51,"payload":{"pr_number":"15","pr_url":"https://github.com/acme/other/pull/15"}},
  {"id":3,"workflow_stage_id":51,"payload":{"pr_number":"15"}},
  {"id":4,"workflow_stage_id":51,"payload":{"pr_number":"99","pr_url":"https://github.com/acme/widget/pull/99"}}
],"meta":{"last_page":1,"total":4}}
JSON

echo "== 5. a card's source is derived through the server's field-preference order =="
# The jq `derive_source` is a FOURTH runtime expressing one rule (server PHP, bridge PHP, the
# python client, this). Nothing binds it to the others by inspection, so it is bound by this
# corpus: `<card-payload-json>|<yes|no: does it qualify as acme/widget>|<label>`.
# ⛔ EVERY ROW BELOW REPORTS `<rc>/<moved>`, NOT `<moved>` ALONE, and the rc half is the
# load-bearing one for the four non-string-derivation arms. Those assert that a card does NOT
# move, and "did not move" is also what happens when the bin DIES: mutate the type guard to
# `if false then null` and jq throws mid-correlation, promote exits 5 with an empty patch log,
# and all four arms went on PASSING while the tool they certify had crashed (measured). An
# absence-only assertion certifies whatever replaces the behaviour it describes; the rc is the
# PRESENCE witness that says the run completed and then declined, rather than never ruling.
src_case() { # <payload-json> — does a card carrying it get promoted under acme/widget?
  cat > "$BOARD_FILE" <<JSON
{"data":[{"id":7,"workflow_stage_id":51,"payload":$1}],"meta":{"last_page":1,"total":1}}
JSON
  run_promote "$CFG_REPO"
  printf '%s/%s' "$rc" "$(moved 7)"
}
ext_case() { # <external_link> — the top-level field, last in the preference order
  cat > "$BOARD_FILE" <<JSON
{"data":[{"id":7,"workflow_stage_id":51,"external_link":"$1","payload":{"pr_number":"15"}}],"meta":{"last_page":1,"total":1}}
JSON
  run_promote "$CFG_REPO"
  printf '%s/%s' "$rc" "$(moved 7)"
}
ext_json_case() { # <external_link-as-RAW-JSON> — the same field, non-string values included
  cat > "$BOARD_FILE" <<JSON
{"data":[{"id":7,"workflow_stage_id":51,"external_link":$1,"payload":{"pr_number":"15"}}],"meta":{"last_page":1,"total":1}}
JSON
  run_promote "$CFG_REPO"
  printf '%s/%s' "$rc" "$(moved 7)"
}
eq "payload.repo wins outright"                  "0/true"  "$(src_case '{"pr_number":"15","repo":"acme/widget","pr_url":"https://github.com/acme/other/pull/1"}')"
eq "…including when it disqualifies the card"    "0/false" "$(src_case '{"pr_number":"15","repo":"acme/other","pr_url":"https://github.com/acme/widget/pull/1"}')"
eq "a repo string with no slash is NOT a source" "0/false" "$(src_case '{"pr_number":"15","repo":"widget"}')"
eq "pr_url is preferred over issue_url"          "0/false" "$(src_case '{"pr_number":"15","pr_url":"https://github.com/acme/other/pull/1","issue_url":"https://github.com/acme/widget/issues/1"}')"
eq "issue_url is read when pr_url is absent"     "0/true"  "$(src_case '{"pr_number":"15","issue_url":"https://github.com/acme/widget/issues/1"}')"
eq "html_url is read after those two"            "0/true"  "$(src_case '{"pr_number":"15","html_url":"https://github.com/acme/widget/commit/abc"}')"
eq "a trailing .git in the URL is trimmed"       "0/true"  "$(src_case '{"pr_number":"15","pr_url":"https://github.com/acme/widget.git/pull/1"}')"
eq "the URL host is case-insensitive"            "0/true"  "$(src_case '{"pr_number":"15","pr_url":"https://GitHub.com/ACME/Widget/pull/1"}')"
eq "a BARE repo URL yields no source (the rule)" "0/false" "$(src_case '{"pr_number":"15","pr_url":"https://github.com/acme/widget"}')"
eq "a non-github URL yields no source"           "0/false" "$(src_case '{"pr_number":"15","pr_url":"https://git.example.com/acme/widget/pull/1"}')"
# A NON-STRING url field derives NOTHING, because the server guards `is_string` before it
# parses one (`sourceFor`, and `is_string($externalLink)` for the top-level field). The jq
# mirror used to `tostring` the value first, so an object or an array whose JSON TEXT happens
# to contain a GitHub url derived a source here and null on the server — and the direction of
# that disagreement is toward PROMOTING, which is the one direction this whole guard exists to
# close. The two shapes below are the JSON renderings that carry a matchable url.
eq "an OBJECT pr_url is not a string"            "0/false" "$(src_case '{"pr_number":"15","pr_url":{"u":"https://github.com/acme/widget/pull/1"}}')"
eq "an ARRAY pr_url is not a string either"      "0/false" "$(src_case '{"pr_number":"15","pr_url":["https://github.com/acme/widget/pull/1"]}')"
# Not a discriminating row — a bare number carries no url under either implementation. It is
# here as a NO-THROW guard on the type test: jq `capture` on a non-string is a runtime error,
# so a mirror written without either a `tostring` or a type arm dies mid-correlation.
eq "control: a NUMBER url derives nothing, no throw" "0/false" "$(src_case '{"pr_number":"15","pr_url":1234}')"
eq "an object external_link is not a string"     "0/false" "$(ext_json_case '{"u":"https://github.com/acme/widget/pull/1"}')"
# CONTROL — the SAME url as a bare string DOES qualify, so the three arms above are about the
# TYPE and not about the fixture having stopped matching anything.
eq "control: the same url as a STRING qualifies" "0/true"  "$(src_case '{"pr_number":"15","pr_url":"https://github.com/acme/widget/pull/1"}')"
eq "external_link is read last, and IS read"     "0/true"  "$(ext_case 'https://github.com/acme/widget/pull/1')"
eq "…and an external_link for another repo is not ours" "0/false" "$(ext_case 'https://github.com/acme/other/pull/1')"
# restore the four-card board for everything below
cat > "$BOARD_FILE" <<'JSON'
{"data":[
  {"id":1,"workflow_stage_id":51,"payload":{"pr_number":"15","pr_url":"https://github.com/acme/widget/pull/15"}},
  {"id":2,"workflow_stage_id":51,"payload":{"pr_number":"15","pr_url":"https://github.com/acme/other/pull/15"}},
  {"id":3,"workflow_stage_id":51,"payload":{"pr_number":"15"}},
  {"id":4,"workflow_stage_id":51,"payload":{"pr_number":"99","pr_url":"https://github.com/acme/widget/pull/99"}}
],"meta":{"last_page":1,"total":4}}
JSON

echo "== 5b. --source beats the config, and the run says which channel it used =="
run_promote "$CFG_STAR" --source "acme/widget"
eq "flag over a '*' config: the foreign card is refused" "false" "$(moved 2)"
eq "…and the state line names the FLAG as the channel"   "true"  "$(has "from --source" "$err")"
run_promote "$CFG_REPO" --source '*'
eq "flag over a repo config: the foreign card moves"     "true"  "$(moved 2)"
run_promote "$CFG_REPO"
eq "no flag: the state line names the CONFIG as the channel" "true" "$(has "from $CFG_REPO .promote.source" "$err")"

echo "== 5c. --cards is EXEMPT from qualification, and never silently =="
# A card `id` is not a repo-scoped counter — it names one card on one board — so an explicitly
# named id has no collision for the guard to break, and refusing it would refuse an unambiguous
# instruction. The exemption is REPORTED rather than assumed.
run_promote "$CFG_REPO" --cards 2
eq "an explicitly named foreign id IS promoted"     "true"  "$(moved 2)"
eq "…and the exemption is stated on stderr"         "true"  "$(has 'promoted by EXPLICIT card id' "$err")"
eq "…naming the card and the declared source"       "true"  "$(has '(#2)' "$err")"
eq "…and it is not on stdout"                       "false" "$(has 'EXPLICIT card id' "$out")"
# CONTROL — the same card, reached by its REF instead of its id, is still refused. Without this
# the arm above is satisfied by qualification being off altogether.
run_promote "$CFG_REPO"
eq "control: the same card by REF is still refused" "false" "$(moved 2)"
eq "control: …and no exemption line is printed"     "false" "$(has 'EXPLICIT card id' "$err")"

echo "== 6. MUTATION BATTERY — each half of the guard, removed, reds the arms above =="
# A pass is evidence only if failure was possible (canon #9). Each mutant is a copy of the bin
# with ONE property deleted; the assertion is that § 1 or § 4's observable FLIPS. Without this
# section every arm above could be satisfied by a tool that had never qualified anything.
# mutant <label> <sed-expr> — sets $MUT to a copy of the bin with <sed-expr> applied.
# It ASSIGNS rather than printing: `eq` writes its ok/FAIL lines to stdout, so a
# `$(mutant …)` capture would swallow them into the path and every arm below would run a
# binary that does not exist (measured: rc 127, which satisfied no assertion honestly).
mutant() {
  MUT="$TMP/mutant-$1"
  sed "$2" "$PRC" > "$MUT"; chmod +x "$MUT"
  # A mutant that failed to apply, or that no longer parses, would make every arm below pass
  # for the wrong reason — so each is compared to the original and syntax-checked.
  eq "mutant $1: the edit actually changed the bin" "false" "$(cmp -s "$MUT" "$PRC" && echo true || echo false)"
  eq "mutant $1: …and still parses"                 "0"     "$(bash -n "$MUT" >/dev/null 2>&1; echo $?)"
}

# M1 — the guard switched off wholesale: QUALIFY_SRC forced empty.
mutant qualify-off 's|^if \[ "$SOURCE" = .\*. \]; then QUALIFY_SRC=""; else QUALIFY_SRC="$SOURCE"; fi|QUALIFY_SRC=""|'
run_bin "$MUT" "$CFG_REPO"
eq "M1 (qualification dropped): the foreign card is promoted again" "true" "$(moved 2)"
eq "M1: …and so is the unattributable one"                          "true" "$(moved 3)"
eq "M1: …and § 4 would therefore red on both"                       "true" \
   "$( [ "$(moved 2)" = true ] && [ "$(moved 3)" = true ] && echo true || echo false )"

# M2 — only the FOREIGN arm dropped: a different repo's card classifies as a match.
mutant foreign-arm 's|else                     "foreign" end),|else                     "match" end),|'
run_bin "$MUT" "$CFG_REPO"
eq "M2 (foreign arm dropped): the other repo's card is promoted" "true"  "$(moved 2)"
eq "M2: …and the unsourced card is STILL refused (the arms are independent)" "false" "$(moved 3)"

# M3 — only the UNSOURCED arm dropped: an unattributable card classifies as a match.
mutant unsourced-arm 's|elif $csrc == null  then "unsourced"|elif $csrc == null  then "match"|'
run_bin "$MUT" "$CFG_REPO"
eq "M3 (unsourced arm dropped): the unattributable card is promoted" "true"  "$(moved 3)"
eq "M3: …and the foreign card is STILL refused"                      "false" "$(moved 2)"

# M4 — the key made OPTIONAL again, defaulting to the permissive declaration. This is the exact
# regression the card names: "a silent permissive default is what makes this class dangerous".
mutant optional-key 's|^\[ -n "$SOURCE" \] |[ -n "${SOURCE:=*}" ] |'
run_bin "$MUT" "$CFG_NONE"
eq "M4 (key made optional): a source-less config RUNS"    "0"     "$rc"
eq "M4: …and promotes the other repo's card"              "true"  "$(moved 2)"
eq "M4: …so § 1's refusal arms would all red"             "false" "$(has 'REQUIRED and has no default' "$err")"

# CONTROL for the whole battery — the UNMUTATED bin over the same fixture answers the other way
# on every observable the mutants flipped. Without it, a fixture that promoted everything under
# any binary would satisfy each mutant arm above.
run_promote "$CFG_REPO"
eq "control: the shipped bin refuses the foreign card"        "false" "$(moved 2)"
eq "control: …refuses the unattributable card"                "false" "$(moved 3)"
eq "control: …and still promotes our own"                     "true"  "$(moved 1)"
run_promote "$CFG_NONE"
eq "control: …and still refuses a source-less config"         "2"     "$rc"

_summary "promote-source-qualify-selftest"
