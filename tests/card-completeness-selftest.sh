#!/usr/bin/env bash
# card-completeness-selftest.sh — hermetic, network-free acceptance for `bin/card-completeness`,
# the COMPLETENESS ORACLE `promote-released-cards --require-complete` consults (toolkit
# card#10176). Adopted with the oracle from the framework repo's
# `templates/release/card-completeness.selftest.sh` (framework card#9869), where every case below
# was first written; card numbers in the case comments are the framework board's.
#
# WHY THIS FILE EXISTS. The oracle is the single place that decides whether a card's work is
# finished, and the release mover refuses a TERMINAL board write on its answer. Both failure
# directions are silent and both are expensive:
#   - a false COMPLETE promotes a partially-implemented card into a stage nobody re-reads;
#   - a false INCOMPLETE stalls a finished card forever.
# So every case runs THE REAL SCRIPT end-to-end with `curl` stubbed on PATH — no network, no
# assertion on an exit code alone, and a control wherever a pass could be vacuous.
#
# RED-FIRST EVIDENCE. Every block carries a `RED when:` line naming a mutation of the oracle that
# turns it red. That line is a CLAIM, re-verified by applying the mutation whenever the block
# changes — it is not re-applied by this file.
set -uo pipefail   # NOT -e: ported case bodies read an rc from a failing call in a
                   # plain assignment (`grep -c`, a refusal path), which -e would abort on.

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
CC="$HERE/../bin/card-completeness"
_need -x "$CC"
_mktmp_scratch --home

# ── fake curl on PATH ────────────────────────────────────────────────────────────────
# Serves the OPEN-PR read from per-page fixtures and records every call's argv. `000` is a
# TRANSPORT failure served the way curl serves one: `000` on stdout, exit 7, and the `-o` file
# NEITHER created NOR truncated — which is what makes the stale-body property assertable.
mkdir -p "$TMP/bin" "$TMP/fix"
FIX="$TMP/fix"; export FIX
export CALL_LOG="$TMP/calls.log" ARGV_LOG="$TMP/argv.log"
cat > "$TMP/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; want=""
for a in "$@"; do
  case "$want" in o) out="$a"; want=""; continue ;; esac
  case "$a" in -o) want=o ;; http://*|https://*) url="$a" ;; esac
done
printf '%s\n' "$url" >> "$CALL_LOG"
printf '%s\n' "$*" >> "$ARGV_LOG"
# STDIN IS RECORDED TOO, and that is the control for the argv assertion: proving a credential
# is absent from argv proves nothing unless it is shown to be PRESENT somewhere it belongs.
cat >> "$TMP_STDIN_LOG" 2>/dev/null || true
page="${url##*page=}"; page="${page%%&*}"
# THREE populations, one fixture namespace each (card#9869 r1): the OPEN-PR list (`page<N>`),
# the release-head…integration COMPARE (`compare.page<N>`), and one per-commit PR lookup per
# window commit (`ghc.<sha>.page<N>`). The per-commit lookup is matched FIRST — its path also
# ends in `/pulls?`. Each DEFAULT is the healthy empty state, so a case that is not about a
# population is not asserting it.
case "$url" in
  */commits/*/pulls\?*) c="${url##*/commits/}"; kind="ghc.${c%%/pulls*}."; dflt='[]' ;;
  */compare/*)          kind="compare.";                             dflt='{"ahead_by":0,"commits":[]}' ;;
  *)                    kind="";                                     dflt='[]' ;;
esac
code="$(cat "$FIX/${kind}page$page.code" 2>/dev/null || echo 200)"
[ "$code" = 000 ] && { printf '000'; exit 7; }
if [ -n "$out" ]; then
  if [ -f "$FIX/${kind}page$page.body" ]; then cat "$FIX/${kind}page$page.body" > "$out"
  else printf '%s' "$dflt" > "$out"; fi
fi
printf '%s' "$code"
STUB
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
export TMP_STDIN_LOG="$TMP/stdin.log"

# page <n> <json-array-or-status:NNN> — install one page of the open-PR read.
page() {
  case "$2" in
    status:*) printf '%s' "${2#status:}" > "$FIX/page$1.code"; printf '{"message":"nope"}' > "$FIX/page$1.body" ;;
    *)        printf '200' > "$FIX/page$1.code"; printf '%s' "$2" > "$FIX/page$1.body" ;;
  esac
}
# prs <json-array> — page 1 is the given set, page 2 is empty (so the explicit `page=N` walk
# ends on a real SHORT page rather than on a 404, which the oracle would correctly call
# UNMEASURED and every case would then be asserting the wrong thing).
# It also RESETS the release-cut window to empty (every case not about clause (b) runs with
# nothing merged-but-unreleased).
prs() { rm -f "$FIX"/*page*.code "$FIX"/*page*.body; page 1 "$1"; page 2 '[]'
        : > "$CALL_LOG"; : > "$ARGV_LOG"; : > "$TMP_STDIN_LOG"; }
# window <ahead_by> <sha>… — page 1 of the compare: <ahead_by> and the listed commits.
window() {
  local ahead="$1" cs="" sep="" c; shift
  for c in "$@"; do cs="$cs$sep{\"sha\":\"$c\"}"; sep=","; done
  printf '200' > "$FIX/compare.page1.code"
  printf '{"ahead_by":%s,"commits":[%s]}' "$ahead" "$cs" > "$FIX/compare.page1.body"
}
# cpr <sha> <json-array|status:NNN> — what the PR lookup of window commit <sha> returns.
cpr() {
  case "$2" in
    status:*) printf '%s' "${2#status:}" > "$FIX/ghc.$1.page1.code"; printf '{"message":"nope"}' > "$FIX/ghc.$1.page1.body" ;;
    *)        printf '200' > "$FIX/ghc.$1.page1.code"; printf '%s' "$2" > "$FIX/ghc.$1.page1.body" ;;
  esac
}
# merged_pr <number> <merge-sha> <branch> [title] — one MERGED PR object, as the lookup returns it.
merged_pr() {
  printf '{"number":%s,"state":"closed","merged_at":"2026-09-20T03:02:02Z","merge_commit_sha":"%s","head":{"ref":"%s"},"title":"%s"}' \
    "$1" "$2" "$3" "${4:-}"
}

export GITHUB_REPOSITORY=acme/widget
export GITHUB_TOKEN='gh_SENTINEL-T0KEN-do-not-leak'

# The release the verdicts are about. Every `run` passes both; § 10 drives their absence.
RH=(--release-head relhead0 --integration dev)
# run <args…> — the REAL oracle; captures rc/out/err.
run() {
  rc=0
  out="$("$CC" "${RH[@]}" "$@" 2>"$TMP/err")" || rc=$?
  err="$(cat "$TMP/err")"
}
# verdict <id> — the VERDICT column the oracle printed for that card, or NONE.
verdict() { awk -F'\t' -v id="$1" '$1 == id { print $2; f=1 } END { if (!f) print "NONE" }' <<<"$out"; }
# detail <id> — the DETAIL column.
detail() { awk -F'\t' -v id="$1" '$1 == id { print $3 }' <<<"$out"; }

echo "== 1. THE HEADLINE: an OPEN PR whose HEAD BRANCH names the card ⇒ INCOMPLETE =="
# RED when: the branch surface stops being read, or an open PR stops blocking.
prs '[{"number":674,"head":{"ref":"card-9606-bluetooth-disable-impl"},"title":"the implementation half"}]'
run --cards 9606
eq "the card is INCOMPLETE"                    "INCOMPLETE" "$(verdict 9606)"
eq "  … and the PR is NAMED, with its branch"  "true"  "$(has '#674 card-9606-bluetooth-disable-impl' "$(detail 9606)")"
eq "  … exit 5"                                "5"     "$rc"

echo "== 2. THE PASS SIDE: no open PR names it ⇒ COMPLETE =="
# POSITIVE-ONLY is the whole safety argument in the other direction. A finished card's normal
# state is exactly this absence, so if absence blocked, nothing would ever promote again.
# RED when: the oracle starts inferring incompleteness from an absence of any kind.
prs '[{"number":900,"head":{"ref":"card-7777-someone-else"},"title":"card#7777"}]'
run --cards 9606
eq "an unrelated open PR does not block"       "COMPLETE" "$(verdict 9606)"
eq "  … exit 0"                                "0"     "$rc"
prs '[]'
run --cards 9606
eq "an EMPTY open-PR set is COMPLETE"          "COMPLETE" "$(verdict 9606)"
eq "  … exit 0"                                "0"     "$rc"

echo "== 3. OVER-COLLECTION, LEG 1: a TITLE-only citation REPORTS but never blocks =="
# Measured: gating on branch-or-title took the terminal-stage match count from 3 to 4. The
# branch is the surface this install's tooling MINTS; a title is prose. So a title token the
# branch does not back is UNCORROBORATED — warned, so the author's miss is not silent, and
# never blocking. RED when: the title is read as authoritative (then case 3's card stalls).
prs '[{"number":977,"head":{"ref":"card-555-unrelated"},"title":"card#555: follow-up to card#9606"}]'
run --cards 9606
eq "a title-only citation leaves it COMPLETE"  "COMPLETE" "$(verdict 9606)"
eq "  … but WARNs, naming the PR"              "true"  "$(has 'UNCORROBORATED' "$err")"
eq "  … and says which PR"                     "true"  "$(has '#977' "$err")"
eq "  … and the WARN is on STDERR, not stdout" "false" "$(has 'UNCORROBORATED' "$out")"
eq "  … exit 0"                                "0"     "$rc"

echo "== 4. OVER-COLLECTION, LEG 2: the PR BODY is not a surface at all =="
# Measured: gating on ANY surface took the match count from 3 to 10, and SEVEN of those were a
# body citing a prior card as background or as a sibling — a gate on the body would refuse to
# close seven cards over a MENTION. The oracle does not even FETCH bodies, so this asserts the
# absence of the capability rather than a choice made per-PR.
# RED when: a body/`mentions` field is added to the read and consulted.
prs '[{"number":939,"head":{"ref":"card-1111-other"},"title":"card#1111","body":"context: see card#9606 for background"}]'
run --cards 9606
eq "a BODY mention does not block"             "COMPLETE" "$(verdict 9606)"
eq "  … and is not even warned about"          "false" "$(has 'UNCORROBORATED' "$err")"
eq "  … exit 0"                                "0"     "$rc"

echo "== 5. UNMEASURED IS NOT COMPLETE =="
# "No open PR names this card" and "I could not read the open PRs" are the same silence unless
# something refuses to let them be. Each arm names its own cause, because a caller's operator
# has to know whether to grant a permission, fix a slug, or retry.
# RED when: any read failure degrades to COMPLETE (the silent-green this exists to close).
prs '[]'; page 1 status:403
run --cards 9606
eq "a 403 is UNMEASURED"                       "UNMEASURED" "$(verdict 9606)"
eq "  … naming the permission to grant"        "true"  "$(has 'pull-requests: read' "$(detail 9606)")"
# ⛔ AND THE OTHER CAUSE, which this arm used to assert away. Clause (b) issues one
# `commits/<sha>/pulls` request PER unreleased commit, GitHub answers a secondary rate limit
# with 403, and `curl --retry` does not retry a 403 — so the MOST LIKELY 403 on a wide window is
# a rate limit, and a message naming only the permission sends the operator to grant one they
# already granted (canon #10). RED when: either cause is dropped, or one is asserted over the
# other.
eq "  … and the RATE LIMIT that answers alike" "true"  "$(has 'RATE-LIMITING' "$(detail 9606)")"
eq "  … exit 6 (more severe than 5)"           "6"     "$rc"
# A 401 is NOT ambiguous, and must not inherit the 403's hedge: no token, or a token this repo
# rejects. RED when: the two statuses collapse back into one arm.
prs '[]'; page 1 status:401
run --cards 9606
eq "a 401 is UNMEASURED"                       "UNMEASURED" "$(verdict 9606)"
eq "  … naming the credential as the cause"    "true"  "$(has 'credential is missing or was REJECTED' "$(detail 9606)")"
eq "  … and NOT blaming a rate limit"          "false" "$(has 'RATE-LIMITING' "$(detail 9606)")"
prs '[]'; page 1 status:404
run --cards 9606
eq "a 404 is UNMEASURED"                       "UNMEASURED" "$(verdict 9606)"
eq "  … naming the wrong-slug cause"           "true"  "$(has 'wrong repo slug' "$(detail 9606)")"
prs '[]'; page 1 status:000
run --cards 9606
eq "a TRANSPORT failure is UNMEASURED"         "UNMEASURED" "$(verdict 9606)"
eq "  … naming it as transport"                "true"  "$(has 'transport failure' "$(detail 9606)")"
eq "  … exit 6"                                "6"     "$rc"
prs '[]'; printf '200' > "$FIX/page1.code"; printf '{"message":"not an array"}' > "$FIX/page1.body"
run --cards 9606
eq "a NON-ARRAY body is UNMEASURED"            "UNMEASURED" "$(verdict 9606)"
eq "  … exit 6"                                "6"     "$rc"

echo "== 6. EVERY REQUESTED CARD GETS EXACTLY ONE LINE, in the order asked =="
# The callers key on the id, and a card the oracle SILENTLY OMITTED would read to a naive
# caller as "nothing to say". (Both movers additionally treat a missing line as UNMEASURED —
# belt and braces, because this is the failure that would un-gate a terminal write.)
# RED when: the verdict loop skips a card (e.g. `continue`s past an id with no PR rows) or
# iterates the PR rows instead of the requested ids.
prs '[{"number":674,"head":{"ref":"card-9606-impl"},"title":"x"}]'
run --cards "9606,card#9451,card-101"
eq "three cards asked, three lines back"       "3"     "$(printf '%s\n' "$out" | grep -c .)"
eq "  … in the order asked"                    "9606 9451 101 " "$(awk -F'\t' '{printf "%s ", $1}' <<<"$out")"
eq "  … mixed spellings all resolve"           "COMPLETE" "$(verdict 101)"
eq "  … and the blocked one is blocked"        "INCOMPLETE" "$(verdict 9606)"
eq "  … exit 5 (ANY incomplete)"               "5"     "$rc"

echo "== 7. THE SHARED GRAMMAR, driven through the real branch surface =="
# The accept-set is owned by the bridge (`CardTokenGrammar::PATTERN` — see the oracle's header).
# Nothing in this repo can read that pattern, so the rows below ARE this side's binding of the
# copy: each one is a shape the bridge's grammar accepts or refuses. They also pin that the
# oracle actually APPLIES the grammar to a branch name — a correct constant read by nothing is
# a decoration.
# RED when: `CARD_RE` loses an alternative (the glued or the `#` form), gains a `_` separator
# or a single-digit glued form, or `ids_in` stops being applied to the head ref.
prs '[{"number":1,"head":{"ref":"card-42-dash"},"title":""},
      {"number":2,"head":{"ref":"feat/card#43-hash"},"title":""},
      {"number":3,"head":{"ref":"card44-glued"},"title":""},
      {"number":4,"head":{"ref":"card-45-suffix_fix"},"title":""},
      {"number":5,"head":{"ref":"card_46-underscore"},"title":""},
      {"number":6,"head":{"ref":"card4-single-digit-glued-is-not-a-token"},"title":""}]'
run --cards "42,43,44,45,46,4"
eq "dash form correlates"                      "INCOMPLETE" "$(verdict 42)"
eq "hash form correlates"                      "INCOMPLETE" "$(verdict 43)"
eq "GLUED at two digits correlates"            "INCOMPLETE" "$(verdict 44)"
eq "a _-suffixed token still correlates"       "INCOMPLETE" "$(verdict 45)"
eq "card_46 is a NEAR-MISS: does NOT correlate" "COMPLETE"  "$(verdict 46)"
eq "single-digit glued card4 does NOT correlate" "COMPLETE" "$(verdict 4)"

echo "== 8. THE PAGE WALK is explicit, bounded, and never silently short =="
# A truncated read is UNMEASURED, never "no PR cites this card" — the 200-but-empty class.
# RED when: the walk breaks on page 1, or the cap degrades to a clean answer.
# A FULL page (100 rows), built in bash — deliberately NOT an embedded `python3 -` heredoc:
# this suite ships into an adopter's repo, and an embedded interpreter is a second language's
# encoding and line-ending contract riding along inside a shell file.
big="["; sep=""
for i in $(seq 1 100); do
  big="$big$sep{\"number\":$i,\"head\":{\"ref\":\"branch-$i\"},\"title\":\"\"}"; sep=","
done
big="$big]"
prs "$big"; page 2 '[{"number":674,"head":{"ref":"card-9606-impl"},"title":""}]'; page 3 '[]'
run --cards 9606
eq "a FULL page 1 does not end the walk"       "INCOMPLETE" "$(verdict 9606)"
eq "  … page 2 was actually fetched"           "true"  "$(has 'page=2' "$(cat "$CALL_LOG")")"
# Every page full, forever: an API that ignores `page=` must hit the cap and report it.
rm -f "$FIX"/page*.code "$FIX"/page*.body
for p in $(seq 1 25); do page "$p" "$big"; done
: > "$CALL_LOG"
run --cards 9606
eq "an unbounded walk hits the cap"            "UNMEASURED" "$(verdict 9606)"
eq "  … and says the read was TRUNCATED"       "true"  "$(has 'TRUNCATED' "$(detail 9606)")"
eq "  … exit 6"                                "6"     "$rc"

echo "== 9. THE CREDENTIAL NEVER ENTERS ARGV =="
# /proc/<pid>/cmdline is world-readable on a multi-user host, so a resolved bearer must not be
# an argument to an external command. THE CONTROL is the second assertion:
# proving absence from argv proves nothing unless the token is shown to be present where it
# BELONGS. RED when: `-H @-` is "simplified" to `-H "Authorization: Bearer $TOKEN"`.
prs '[]'
run --cards 9606
eq "the token is in NO argv"                   "false" "$(has "$GITHUB_TOKEN" "$(cat "$ARGV_LOG")")"
eq "  … control: it IS on stdin"               "true"  "$(has "$GITHUB_TOKEN" "$(cat "$TMP_STDIN_LOG")")"
eq "  … control: argv was recorded at all"     "true"  "$([ -s "$ARGV_LOG" ] && echo true || echo false)"
# And a TOKENLESS run sends no Authorization header at all rather than an empty bearer (whose
# 401 would be a message about the token's VALUE, not about its absence).
prs '[]'
( unset GITHUB_TOKEN GH_TOKEN; "$CC" "${RH[@]}" --cards 9606 >/dev/null 2>&1 )
eq "tokenless: control — the reads DID happen"   "true"  "$([ -s "$CALL_LOG" ] && echo true || echo false)"
eq "tokenless: no Authorization on stdin"      "false" "$(has 'Authorization' "$(cat "$TMP_STDIN_LOG")")"

echo "== 10. REFUSALS are refusals (rc 2), never a guessed answer =="
# RED when: any refusal below falls through to a read (an empty --cards read as "all
# complete", a plain-http base sent the credential, an absent --release-head/--integration
# answered clause (a) alone, or a missing repo guessed).
prs '[]'
run --cards ""
eq "no cards → rc 2"                           "2"     "$rc"
eq "  … and no verdict lines"                  ""      "$out"
run --cards 9606 --api "http://api.github.test"
eq "a non-https api base → rc 2"               "2"     "$rc"
eq "  … naming the refusal"                    "true"  "$(has 'refusing to send a credential' "$err")"
# The refusal must not echo the base: it is the path guaranteed to fire on a misconfigured one,
# and a base can carry userinfo (card#7500's class). RED when: the value is interpolated again.
run --cards 9606 --api "http://user:s3cr3t-pw@api.github.test"
eq "  … and does not echo a userinfo password" "false" "$(has 's3cr3t-pw' "$err")"
eq "  … (control: it did refuse)"              "2"     "$rc"
run --cards
eq "a missing option argument → rc 2"          "2"     "$rc"
run --cards 9606 --release-head ""
eq "an EMPTY --release-head → rc 2"            "2"     "$rc"
eq "  … naming the flag, not read as absent"   "true"  "$(has '--release-head requires a non-empty value' "$err")"
run --nonsense
eq "an unknown arg → rc 2"                     "2"     "$rc"
# NO --release-head / NO --integration. Clause (b)'s population is defined by the pair, and
# answering clause (a) alone would be the release-cut-window false COMPLETE itself — so each
# absence refuses, by name, before a single read.
: > "$CALL_LOG"
rc=0; out="$("$CC" --integration dev --cards 9606 2>"$TMP/err")" || rc=$?
eq "no --release-head → rc 2"                  "2"     "$rc"
eq "  … naming it"                             "true"  "$(has 'no --release-head' "$(cat "$TMP/err")")"
eq "  … and no verdict lines"                  ""      "$out"
rc=0; out="$("$CC" --release-head relhead0 --cards 9606 2>"$TMP/err")" || rc=$?
eq "no --integration → rc 2"                   "2"     "$rc"
eq "  … naming it"                             "true"  "$(has 'no --integration' "$(cat "$TMP/err")")"
eq "  … before any read"                       "false" "$([ -s "$CALL_LOG" ] && echo true || echo false)"
# NO repo derivable: GITHUB_REPOSITORY unset AND a cwd from which `git config --get
# remote.origin.url` yields nothing. The population a terminal-stage decision rests on is never
# guessed. A PLAIN DIRECTORY, not a `git init` — this suite ships, and a test that runs `git`
# with the ambient environment is the shape the framework's env-scrub guard exists to catch.
prs '[]'
noorigin="$TMP/noorigin"; mkdir -p "$noorigin"
rc=0; out="$(cd "$noorigin" && env -u GITHUB_REPOSITORY "$CC" "${RH[@]}" --cards 9606 2>"$TMP/err")" || rc=$?
eq "no derivable repo → rc 2"                  "2"     "$rc"
eq "  … and refuses to guess"                  "true"  "$(has 'Refusing to guess the population' "$(cat "$TMP/err")")"

echo "== 11. --help prints the WHOLE header and nothing but the header =="
# Same contract as the movers (tests/help-output-selftest.sh holds it over every bin too): a LINE-COUNT EQUALITY against the file's own comment block,
# never a fixed range (which truncates in one direction and leaks the script body in the other).
# RED when: `--help` is switched to a fixed `sed -n` range, or stops at a blank line rather
# than at the first non-comment line.
hdr_lines="$(awk 'NR>1 { if (substr($0,1,1) == "#") c++; else exit } END { print c }' "$CC")"
rc=0; helpout="$("$CC" --help 2>&1)" || rc=$?
eq "--help rc 0"                               "0"     "$rc"
eq "--help prints EXACTLY the header block"    "$hdr_lines" "$(printf '%s\n' "$helpout" | wc -l | tr -d ' ')"
eq "--help states the PREDICATE"               "true"  "$(has 'THE COMPLETENESS PREDICATE' "$helpout")"
eq "--help leaks no script body"               "false" "$(has 'set -euo pipefail' "$helpout")"

echo "== 12. THE RELEASE-CUT WINDOW: MERGED to the integration branch, NOT in the release head ⇒ INCOMPLETE =="
# card#9869 r1 review, M1 — the open-PR-only predicate's false COMPLETE, measured on the
# framework repo: PR #959 (`card-9451-waypoint-refs`) merged to dev after the v0.55.0 cut, so
# it was no longer open and not in the release, and card#9451 read COMPLETE against v0.55.0.
# RED when: clause (b) is not read (load_unreleased_prs skipped or its rows dropped), or the
# compare is asked the wrong way round (integration...head lists the RELEASED side).
prs '[]'
window 2 c0ffee0 facade0
cpr c0ffee0 "[$(merged_pr 959 c0ffee0 card-9451-waypoint-refs 'feat(waypoint): card#9451 part 3')]"
cpr facade0 "[$(merged_pr 960 facade0 card-555-other 'follow-up to card#9451')]"
run --cards 9451
eq "a merged-but-unreleased PR ⇒ INCOMPLETE"   "INCOMPLETE" "$(verdict 9451)"
eq "  … naming it, and WHY it blocks"          "true"  "$(has '#959 card-9451-waypoint-refs (merged to dev, not in the release head)' "$(detail 9451)")"
eq "  … exit 5"                                "5"     "$rc"
eq "  … the compare is <release-head>...<integration>" "true" "$(has '/compare/relhead0...dev?' "$(cat "$CALL_LOG")")"
eq "  … EVERY window commit was looked up"     "true"  "$(has '/commits/facade0/pulls' "$(cat "$CALL_LOG")")"
eq "  … a TITLE-only merged citation WARNs"    "true"  "$(has '#960' "$err")"
eq "  … and does not block"                    "false" "$(has '#960' "$(detail 9451)")"
# THE PASS SIDE of the same fixture: an empty window, same everything else ⇒ COMPLETE. Without
# it the case above could be passing because clause (b) blocks on anything.
prs '[]'
run --cards 9451
eq "an EMPTY window ⇒ COMPLETE"                "COMPLETE" "$(verdict 9451)"
eq "  … exit 0"                                "0"     "$rc"
# AN EMPTY FIELD STAYS EMPTY. A PR row carries a field AFTER the title (why it blocks), so a
# blank title must not shift it. RED when: the row separator goes back to TAB, which `read`
# collapses as IFS whitespace — the blank title then swallows the state label.
prs '[]'
window 1 c0ffee0
cpr c0ffee0 "[$(merged_pr 959 c0ffee0 card-9451-waypoint-refs '')]"
run --cards 9451
eq "a BLANK title does not shift the row"      "true"  "$(has '#959 card-9451-waypoint-refs (merged to dev, not in the release head)' "$(detail 9451)")"

echo "== 13. A PR IS THE WINDOW COMMIT'S MERGER ONLY IF ITS merge_commit_sha IS THAT COMMIT =="
# `commits/<sha>/pulls` ALSO returns every OPEN PR whose branch merely CONTAINS the commit —
# measured on the framework repo: one window commit's lookup returned its merging PR among
# every open PR based on top of it. Read as "merged by this commit", each of those would block
# its card on work it merely sits on.
# RED when: the `merge_commit_sha == $sha` / `merged_at != null` filter is dropped or loosened.
prs '[]'
window 1 c0ffee0
cpr c0ffee0 '[{"number":990,"state":"open","merged_at":null,"merge_commit_sha":"0ther00","head":{"ref":"card-9451-based-on-top"},"title":""},
             {"number":991,"state":"closed","merged_at":"2026-09-19T00:00:00Z","merge_commit_sha":"e1sewhere","head":{"ref":"card-9451-older"},"title":""}]'
run --cards 9451
eq "a PR that only CONTAINS the commit does not block" "COMPLETE" "$(verdict 9451)"
eq "  … exit 0"                                "0"     "$rc"

echo "== 14. THE WINDOW READ is complete, paged, bounded, or UNMEASURED =="
# RED when: the compare's commit list is trusted without its own `ahead_by` (a truncated window
# reads as released), the compare stops paging, a failed lookup is skipped, or the cap degrades
# to a clean answer.
prs '[]'
window 2 c0ffee0
run --cards 9451
eq "a list SHORTER than ahead_by is UNMEASURED" "UNMEASURED" "$(verdict 9451)"
eq "  … saying the window read is TRUNCATED"   "true"  "$(has 'TRUNCATED' "$(detail 9451)")"
eq "  … exit 6"                                "6"     "$rc"
prs '[]'
printf '404' > "$FIX/compare.page1.code"; printf '{"message":"Not Found"}' > "$FIX/compare.page1.body"
run --cards 9451
eq "an unknown release head is UNMEASURED"     "UNMEASURED" "$(verdict 9451)"
eq "  … naming the unpushed/wrong-branch cause" "true" "$(has 'unknown to GitHub' "$(detail 9451)")"
prs '[]'
window 1 c0ffee0; cpr c0ffee0 status:403
run --cards 9451
eq "a failed per-commit lookup is UNMEASURED"  "UNMEASURED" "$(verdict 9451)"
eq "  … naming that commit"                    "true"  "$(has 'c0ffee0' "$(detail 9451)")"
# PAGING: a FULL first page of 100 window commits must not end the walk, and a PR merged by a
# commit on page 2 must still be found. Built in bash (see § 8 for why not python).
prs '[]'
cs=""; sep=""
for i in $(seq 1 100); do cs="$cs$sep{\"sha\":\"p1c$i\"}"; sep=","; done
printf '200' > "$FIX/compare.page1.code"; printf '{"ahead_by":101,"commits":[%s]}' "$cs" > "$FIX/compare.page1.body"
printf '200' > "$FIX/compare.page2.code"; printf '{"ahead_by":101,"commits":[{"sha":"p2c1"}]}' > "$FIX/compare.page2.body"
cpr p2c1 "[$(merged_pr 777 p2c1 card-9451-page-two)]"
run --cards 9451
eq "a window commit on compare page 2 is read" "INCOMPLETE" "$(verdict 9451)"
eq "  … page 2 was actually fetched"           "true"  "$(has '/compare/relhead0...dev?per_page=100&page=2' "$(cat "$CALL_LOG")")"
# THE CAP: a window wider than WINDOW_CAP is refused before any per-commit lookup. The count is
# the fixture's own, derived from the constant in the script, never written here.
cap="$(sed -n 's/^WINDOW_CAP=\([0-9][0-9]*\)$/\1/p' "$CC")"
eq "  (fixture: WINDOW_CAP is extractable)"    "true"  "$([ -n "$cap" ] && echo true || echo false)"
prs '[]'
cs=""; sep=""; over=$((cap + 1))
for i in $(seq 1 "$over"); do cs="$cs$sep{\"sha\":\"w$i\"}"; sep=","; done
# Served across as many 100-commit pages as the oracle's own walk asks for, so the list DOES
# add up to ahead_by and the only thing left to refuse the window is the cap.
for pg in $(seq 1 $(( (over + 99) / 100 ))); do
  lo=$(( (pg - 1) * 100 + 1 )); hi=$(( pg * 100 )); [ "$hi" -gt "$over" ] && hi="$over"
  pcs=""; sep=""; for i in $(seq "$lo" "$hi"); do pcs="$pcs$sep{\"sha\":\"w$i\"}"; sep=","; done
  printf '200' > "$FIX/compare.page$pg.code"; printf '{"ahead_by":%s,"commits":[%s]}' "$over" "$pcs" > "$FIX/compare.page$pg.body"
done
run --cards 9451
eq "a window over the cap is UNMEASURED"       "UNMEASURED" "$(verdict 9451)"
eq "  … naming the cap"                        "true"  "$(has "${cap}-commit cap" "$(detail 9451)")"
eq "  … and looked up NO commit"               "false" "$(has '/commits/' "$(cat "$CALL_LOG")")"

_summary "card-completeness-selftest"
