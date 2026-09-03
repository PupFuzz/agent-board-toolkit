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
#   * `--source` beats the config, and `--cards` is exempt and says so;
#   * a resolved source other than `*` that is not $GITHUB_REPOSITORY refuses before any board
#     read, case-folded on both sides, and does not fire when that variable is absent (§ 7).
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
# $GITHUB_REPOSITORY is absent from these runs because the PRELUDE removes it for the whole
# suite (see the note there): every arm below drives a fixture source, and on a runner the
# repo-identity leg would refuse them for the wrong reason. § 7 sets it explicitly per arm,
# and asserts the floor still holds.
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

echo "== 3c. ONE ACCEPT SET, TWO COPIES: one corpus, driven through both of them =="
# WHY THIS EXISTS (card#8421). `.promote.source` here and `--repo` at bin/adopt-to-dl and
# bin/run-coverage-check are THE SAME VALUE at the two ends of ONE correlation — the `owner/repo`
# a card's `source` is derived from, and the `owner/repo` a release qualifies against — so a
# spelling one end accepts and the other refuses is a card that can be stamped and never matched.
# The two copies (`kb_is_repo_slug` in bin/_kb-board-lib.sh, and `src_charset_ok` plus the shape
# `case` in this bin) were sync-paired BY COMMENT ONLY, and they had already drifted: this bin
# lowercases before its `case`, so it refused `acme/widget.GIT`, while the lib arm was written
# `*.git)` — case-SENSITIVE — and ACCEPTED it, which reached adopt-to-dl's mint/stamp path and
# left exactly the half-applied write that arm exists to prevent. Two comments asserting "keep
# these in sync" is not a contract; this corpus is.
#
# WHY NOT THE EXTRACT-AND-EXERCISE PATTERN tests/kb-host-guard-selftest.sh uses on `host_ok`:
# this bin's half is not one function to lift — it is `src_charset_ok` PLUS the shape `case`
# inline in the main flow — so a RUN is the only place both halves exist together, and the
# promote side is therefore driven end-to-end (rc 0 = accepted, rc 2 = refused). The lib side
# needs no such ceremony and is called directly: both its callers — `bin/adopt-to-dl`, at its
# readiness gate, and `bin/run-coverage-check`, at its `--repo` gate — hand it the RAW flag
# value with no canonicalization of their own, so the predicate's verdict IS the deployed
# verdict at both of them.
LIB="$HERE/../bin/_kb-board-lib.sh"
_need -r "$LIB"
# A fresh shell per row, so nothing this harness has defined can stand in for the lib.
lib_verdict() {
  if bash -c 'source "$1"; kb_is_repo_slug "$2"' _ "$LIB" "$1" >/dev/null 2>&1; then echo A; else echo R; fi
}
# rc 2 is promote's DOCUMENTED refusal (every `die`); rc 0 is acceptance. Any other rc is a
# CRASH, and folding it into R would let a bin that died read as a bin that refused.
promote_verdict() { run_promote "$CFG_STAR" --source "$1"; case "$rc" in 0) echo A;; 2) echo R;; *) echo "CRASHED-rc$rc";; esac; }
# `<A|R>|<value>` — the verdict BOTH copies must reach. The pin is per-side, not a bare
# "they agree": a mutant that refused everything would satisfy an equality-only check, and the
# accept rows below are what stops it (canon #9).
while IFS='|' read -r want value; do
  [ -n "$want" ] || continue
  eq "corpus '$value' → lib predicate $want"    "$want" "$(lib_verdict "$value")"
  eq "corpus '$value' → promote's copy $want"   "$want" "$(promote_verdict "$value")"
done <<'ROWS'
A|acme/widget
A|acme/widget.js
A|acme_org/my-repo
A|acme2/widget3
A|acme.github/widget
A|ACME/Widget
A|acme/widget.gitignore
R|acme/widget.git
R|acme/widget.GIT
R|acme/widget.Git
R|git@github.com:acme/widget
R|https://github.com/acme/widget
R|ssh://git@github.com/acme/widget
R|acme/*
R|*/widget
R|**
R|widget
R|acme/widget/extra
R|/widget
R|acme/
R|acme widget/x
R|acme:x/widget
R|acme/wid+get
R|acme/wid~get
R|acme/wid%get
R|
ROWS
# THE TWO DIVERGENCES ARE DECLARED, not discovered — every other spelling above is a row where a
# disagreement is a defect, and these two are the complete list of where the copies may differ.
#   1. `*` is a DECLARATION this tool accepts ("this board tracks exactly one repo") and is not a
#      repo name, so the predicate that vouches for repo names must refuse it. A `--repo '*'` at
#      adopt-to-dl would stamp a card with a URL naming no repository.
#   2. This tool CANONICALIZES an operator's config value before judging it (trim, 255-cap,
#      lowercase); the lib's two callers judge the raw flag value. So a padded spelling is
#      accepted here and refused there — benign in that direction only: adopt-to-dl refuses it
#      loudly before anything is stamped, which is why `_ata_canon_source` in bin/adopt-to-dl
#      can omit the trim its promote-side mirror performs.
# Both rows are asserted in BOTH directions, so a change that accidentally unified the copies
# here would red rather than pass quietly.
eq "declared divergence 1: '*' is a promote DECLARATION"  "A" "$(promote_verdict '*')"
eq "declared divergence 1: …and not a repo name"          "R" "$(lib_verdict '*')"
eq "declared divergence 2: promote trims before judging"  "A" "$(promote_verdict '  acme/widget  ')"
eq "declared divergence 2: …the lib's callers do not"     "R" "$(lib_verdict '  acme/widget  ')"

echo "== 3d. LOCATING the canonicalizeSource MIRRORS under bin/ — BEST-EFFORT; § 3e is what BINDS them (card#8538) =="
# WHY THIS EXISTS. `canonicalizeSource` is the kanban server's rule, and this repo carries THREE
# copies of it across two vendored bins that must not share an implementation. Two hand-kept
# comments — one per bin — claim to enumerate every copy, and until this leg that comment WAS the
# mechanism. It failed the way a comment fails: a FOURTH copy was minted in
# `bin/promote-released-cards` (the $GITHUB_REPOSITORY side of the identity check in § 7),
# byte-identical to the config-side copy six lines of comment away, and both censuses went stale
# in the same commit with nothing red. That copy is gone — `src_canon` is the one shell spelling
# and both sides call it — and this leg is what catches the next one WHEN THE PREDICATE BELOW CAN
# SEE IT, which is a real guarantee and a bounded one; the bound is stated below, not implied. A
# census that enumerates copies with no check behind it is a comment, not a contract; the cost is
# not theoretical, since card#8421 already forced one correction to this rule across this pair.
#
# ⛔ AN INCLUSION LIST FAILS OPEN, AND THAT IS WHY THE NAMED HALF OF THIS PREDICATE IS
# DELIBERATELY OVER-BROAD — the SPELLED half is still one, and says so below.
# This leg's predicate has been an ALLOW-LIST OF SPELLINGS twice, and both times a legal fifth
# mirror walked through it while the leg answered rc 0. First it was two spellings
# (`tr '[:upper:]' '[:lower:]'` and `ascii_downcase`), covering 5 of the 12 folds present, and
# `${SOURCE_ALT,,}` defeated it. Then it was a 16-row table of constructs, derived per language
# — and `${1,,}`, `${1@L}`, `tr "A-Z" "a-z"`, `tr -- 'A-Z' 'a-z'` and a `perl -pe '$_=lc'` after
# a `then` all defeated THAT, each minted into the real bin, each answering rc 0 / 0 FAIL / 344
# ok. Four of those five are inside rows the table claimed: the rows required an
# IDENTIFIER-shaped parameter name, or a single-quoted `tr` operand. The lesson is structural
# rather than about the missing cells: an allow-list of spellings can always be defeated by a
# spelling nobody listed, and the control that was supposed to prove otherwise minted THE ROW'S
# OWN SAMPLE — which demonstrates that the sample matches its own regex, never that the regex
# covers the construct. A control that cannot fail for the property it appears to guarantee is
# the same defect this whole section exists to catch, sitting inside the catcher.
#
# So the polarity was flipped — ON THE NAMED HALF, and that is where the good news stops. NAMED
# is genuinely over-broad now: bare substrings, no command position, no language, 22 admitted
# lines under `bin/`, each declared below by name and reason. It has not been defeated. THE
# SPELLED HALF NEVER GOT THE SAME TREATMENT, and what follows is the account of what that leaves
# rather than a claim that nothing is left.
#
# ⛔ § 3d LOCATES MIRRORS ON A BEST-EFFORT BASIS; IT DOES NOT BOUND THE SET. `_FOLD_SPELLED`'s
# alphabet arms are an INCLUSION LIST of three tokens — `A-Z`, `ABCDEFGHIJKLMNOPQRSTUVWXYZ` and
# `[:upper:]` — so a `tr` whose alphabets are written some other way is a real, legal, literal
# case fold that this predicate scores 0. Six such spellings are known, measured against the
# predicate below rather than reasoned about:
#     tr '\101-\132' '\141-\172'          octal alphabets — and the LOCALE-SAFE `tr` idiom,
#                                         since a letter RANGE is collation-dependent, so this
#                                         is what a careful author writes
#     tr 'A-MN-Z' 'a-mn-z'                one `tr`, both operands literal, no `A-Z` substring
#     tr 'A-M' 'a-m' | tr 'N-Z' 'n-z'     two stages, four literal operands
#     sed 's/A/a/g;s/B/b/g;...'           a per-character mapping written out
#     awk '{ gsub(/A/, "a"); ... }'       the same, one interpreter over
#     a `case`-per-letter mapping         the same, in bash
# ⛔ READ THAT AS A DECLARED RESIDUAL, NOT AS SIX MISSING CELLS. Three consecutive rounds of this
# leg were each closed by adding the spellings the round before had missed, and each next round
# found more; a widening to cover these six was costed and REFUSED for exactly that reason. An
# inclusion list cannot be finished, so this one is DECLARED instead of extended — and the six
# are named here so that a maintainer auditing against this section gets the question rather than
# the confidence.
#
# ⭐ SO IF YOU CAME HERE FOR A GUARANTEE, THE ONE THAT EXISTS IS § 3e'S — AND IT IS BOUNDED TOO.
# § 3d asks "are there more copies than the censuses name", usefully but not completely. § 3e asks
# the question card#8421 actually posed, "do the copies AGREE", and answers it properly: it
# extracts the THREE NAMED copies from the shipped files and EXECUTES them over one corpus, so a
# divergence between them reds whatever spelling minted it — drop `| ascii_downcase` from the jq
# copy and § 3e reds while nothing here moves. ⛔ ITS POPULATION IS THOSE THREE. An unnamed fifth
# mirror is outside § 3e exactly as it is outside this predicate, so the two sections do NOT close
# each other's gap and must not be read as doing so. § 3d is a locator with a declared residual;
# § 3e is a contract over the copies that are named. Neither is a bound on the copies that are not.
#
# ⛔ WHAT § 3d CANNOT SEE — any one of these escapes:
#   * a fold spelled outside `_FOLD_SPELLED`'s alphabet tokens — the six above, and an OPEN class,
#     which is why this section no longer claims a bound;
#   * a fold whose evidence is not in the file's TEXT: the alphabets held in variables
#     (`tr "$UP" "$LO"`), the mapping computed arithmetically (`chr(ord(c) + 32)`), or the
#     program text assembled at run time. Two of those shapes are minted below and asserted to
#     ESCAPE, which pins THOSE TWO as still-escaping; it does not bound the residual;
#   * a mirror that reaches its fold through a helper defined in ANOTHER file — leg 1 is what
#     reds if a third file under `bin/` starts naming the rule;
#   * any copy outside `bin/`. Out of the population by choice: the two bins are the only
#     vendored standalones carrying the rule.
#
# ⭐ AND WHAT IT IS STILL WORTH, so the demotion does not read as a deletion: the census is
# re-derived from `bin/` on every run instead of trusted from a comment; a named copy that is
# renamed, moved or dropped reds at leg 2 or leg 4; the walk is recursive, so a copy one directory
# down is inside the population; and the battery below keeps, VERBATIM, the spellings that defeated
# this predicate's two allow-list predecessors, so those widenings cannot be quietly undone.
# ⛔ The six spellings named above defeat the CURRENT predicate and are deliberately NOT in that
# battery. Adding them as caught rows is the widening this round refused; adding them as rows
# asserted to ESCAPE would cement the escape as intended behaviour instead of declaring it as a
# limitation. They are declared in prose, where a limitation belongs, and § 3e is what a reader
# who needs more than a declaration should be reading.
BINDIR="$HERE/../bin"

# ── THE PREDICATE ────────────────────────────────────────────────────────────────────────────
# Two disjuncts over one LOGICAL line — backslash continuations are joined before matching, so a
# construct split across a wrapped pipeline is still one subject (a line-scoped predecessor
# missed `tr '[:upper:]' \` / `'[:lower:]'` entirely). Comment lines are dropped.
#
#   NAMED — the line NAMES a lowercase operation. Matched against the line LOWERCASED, so
#     `tolower`, `toLowerCase`, `TOLOWER` and `mb_strtolower` are one case of one rule.
#     `lower`, `downcase` and `casefold` are BARE SUBSTRINGS on purpose — `ascii_downcase`,
#     `.lower()` and `str.lower` all carry one, and requiring a boundary is exactly the
#     over-specification that let the last predicate be defeated. `lc`/`lcase`/`lcfirst` are the
#     one exception: word-bounded on `[^a-z0-9_]`, which is what keeps every `LC_ALL=C` locale
#     pin in this tree out while still admitting perl's `lc` and a variable named `lc`.
#   SPELLED — the line WRITES a fold whose operation it does not name: bash's case-modification
#     operators and `-l` attribute, `sed`/`perl`'s `\L`, `\l` and `y///`, `dd conv=lcase`, and
#     any line carrying an UPPER alphabet and a LOWER alphabet AS TWO OPERANDS. That last one is
#     what catches every `tr` spelling at once, in place of three rows that each pinned a
#     quoting style: two operands need a separator between them, so `A-Z` … `a-z` with a space,
#     quote or slash in between is admitted, while `[A-Za-z]` — which has NOTHING between them —
#     is not. The bash arms are bounded by bash's own grammar rather than by observation: a
#     case-modification expansion is `${`, an optional `#`/`!`, a name, an optional subscript,
#     then `,`; a transform is `@` and one letter before the `}`. `${1,,}` and `${1@L}` — the
#     two the predecessor missed — are inside those bounds, and no cell was added for them.
_FOLD_NAMED='lower|downcase|casefold|[^a-z0-9_](lc|lcase|lcfirst)[^a-z0-9_]|conv=[^[:space:]]*case'
_FOLD_SPELLED='\$\{[#!]?[A-Za-z0-9_@*]+(\[[^]]*\])?,'
_FOLD_SPELLED="$_FOLD_SPELLED"'|\$\{[^}]*@[A-Za-z]\}'
_FOLD_SPELLED="$_FOLD_SPELLED"'|[^[:alnum:]_](declare|typeset|local|readonly)[[:space:]]+-[[:alnum:]]*l[^[:alnum:]]'
_FOLD_SPELLED="$_FOLD_SPELLED"'|\\[Ll][^[:alnum:]]'
_FOLD_SPELLED="$_FOLD_SPELLED"'|A-Z[^[:alnum:]]*[[:space:]/'"'"'"][^[:alnum:]]*a-z'
_FOLD_SPELLED="$_FOLD_SPELLED"'|\[:upper:\][^[:alnum:]]*\[:lower:\]'
_FOLD_SPELLED="$_FOLD_SPELLED"'|[^[:alnum:]_]y/[^/]*/[^/]*/'
_FOLD_SPELLED="$_FOLD_SPELLED"'|ABCDEFGHIJKLMNOPQRSTUVWXYZ'
# awk, not a `grep | grep` chain: the continuation join, the comment exclusion and the two
# matches are one stateless pass. It reads STDIN, so the same predicate answers for a whole file
# and for an extracted block. Both regexes travel through the ENVIRONMENT rather than `-v`,
# because awk expands escape sequences in a `-v` value and half of `_FOLD_SPELLED` is
# backslashes. The line is padded with a space at each end so a word boundary can be written
# `[^[:alnum:]_]` — POSIX ERE has no `\b`.
_fold_count() {
  _N="$_FOLD_NAMED" _S="$_FOLD_SPELLED" awk '
    function admits(l,   s) {
      if (l ~ /^[[:space:]]*#/) return 0
      s = " " l " "
      return (tolower(s) ~ ENVIRON["_N"] || s ~ ENVIRON["_S"]) ? 1 : 0 }
    { line = (cont ? line : "") $0 }
    /\\$/ { cont = 1; sub(/\\$/, "", line); next }
    { cont = 0; n += admits(line) }
    END { if (cont) n += admits(line); print n+0 }'
}
# The sort is LC_ALL=C because the expected block below is written in BYTE order, and this repo
# has already been bitten by a locale-sensitive range (tests/locale-range-guard-selftest.sh):
# under en_US.UTF-8 collation `_shellcheck-pinned` sorts AFTER `promote-released-cards`, so the
# same census would read as a different one on a differently-configured runner. Measured here,
# not assumed — it is how this leg first failed.
# ⛔ THE WALK IS RECURSIVE, AND THAT IS A HOLE THIS ROUND CLOSED. Every predecessor iterated
# `"$d"/*` behind an `[ -f ]`, which SKIPS a directory silently — so a fifth mirror written to
# `bin/helpers/canon.sh` was invisible to every census this leg has ever taken, while leg 1's
# `grep -rl` (recursive) would only have seen it had it also carried the word
# `canonicalizeSource`. `bin/` is flat today, so the expected block below is byte-identical
# either way; what changes is that it stays true the day it is not. `! -type d` rather than
# `-type f` keeps a symlinked member in, which `[ -f ]` also admitted. The key is the path
# RELATIVE to `bin/`, not the basename, so two files with one name cannot merge into one row.
_fold_census() {
  local d="$1" f n
  while IFS= read -r f; do
    n="$(_fold_count < "$f")"
    if [ "$n" -gt 0 ]; then printf '%s=%s\n' "${f#"$d"/}" "$n"; fi
  done < <(find "$d" ! -type d) | LC_ALL=C sort
}

# ── EVERY ADMISSION, DECLARED — 22 lines, 10 files ───────────────────────────────────────────
# An over-broad predicate owes an account of what it over-admits, and this is it. Nothing here
# is subtracted from the census: leg 2 pins the whole 22, so an admission that disappears reds
# just as loudly as one that appears.
#
# THE MIRROR SET — 3, and legs 1 and 3 pin which function each of them lives in:
#   * bin/adopt-to-dl x1            `_ata_canon_source`
#   * bin/promote-released-cards x2 `src_canon` (shell) and the jq `canon_source`
#
# REAL FOLDS THAT ARE NOT MIRRORS — 9. None of them takes a repo slug:
#   * bin/_kb-board-lib.sh x3 — `_kb_looks_like_pasted_secret` folds a candidate TOKEN before
#     matching known credential prefixes, and its awk env-file parser folds a KEY NAME twice for
#     the case-insensitive lookup;
#   * bin/agent-board-toolkit-runtime-check x3 — the same two, mirrored into that vendored bin
#     as `_rc_looks_like_pasted_secret` and its own copy of the parser. That mirroring is
#     deliberate, dispositioned and separately guarded: `docs/CONSOLIDATION-PLAN.md`
#     § Post-program dispositions owns the reasoning (the bin JUDGES the lib, so it must not
#     source it) and `tests/token-duplication-selftest.sh` drives both copies against each other
#     row by row — so it is not a finding to re-raise here;
#   * bin/kbcard x1 — `stage_name` folds a `KB_STAGE_*` VARIABLE NAME, not a repo slug;
#   * bin/_shellcheck-pinned x1 — folds `uname -s` into a release-asset name;
#   * bin/release-artifacts-check x1 — folds a CHANGELOG heading for its section selector.
#
# ADMITTED AND NOT A LOWERCASE FOLD AT ALL — 10. This is the price of the polarity, paid openly:
#   * bin/_kb-board-lib.sh x2 and bin/agent-board-toolkit-runtime-check x2 — `local v="${1-}" lc`
#     and the `case "$lc" in` that reads it: a VARIABLE NAMED `lc`, in the two files that
#     genuinely fold beside it. Admitted rather than excluded, because narrowing `lc` to a
#     command position is how `perl -pe '$_=lc'` escaped the predecessor;
#   * bin/kbcard x1 and bin/release-pr-body x2 — `tr '[:lower:]' '[:upper:]'`, the UPPER
#     direction. The NAMED disjunct sees `lower` on either side of the arrow, and there is no
#     cheap way to tell an upper fold from a lower one that a lower fold cannot then be written
#     to evade;
#   * bin/gitignore-secret-family-check x2 — the words `LOWER BOUND` in two report strings;
#   * bin/_kbc-stale-blocker.py x1 — `answered lower down` in the module docstring.
#
# ⛔ NO LANGUAGE CENSUS ANY MORE, AND THAT IS A DELETION, NOT AN OMISSION. The predecessor
# derived the set of LANGUAGES under `bin/` first, purely to bound a per-language construct
# table, and asserted `awk bash jq python3 sed tr`. The table is gone, so that assertion bounds
# nothing — and it was itself defeated: its command-position anchor missed `perl` after `then`,
# after `do`, at an absolute path, through `"$VAR"`, under `xargs`, under `command` and after
# `!` — seven of ten ordinary invocation shapes. Keeping a broken check whose only purpose has
# been removed would be churn that reads as coverage. The predicate above is language-blind by
# construction: it asks what the LINE says, not which interpreter would run it.

# LEG 1 — the bins that NAME the rule are exactly the bins that mirror it. A third file starting
# to carry a copy has to say so here first, which is the cheapest place to catch it.
eq "the bins naming canonicalizeSource are exactly the two that mirror it" \
   "adopt-to-dl promote-released-cards" \
   "$(command grep -rl 'canonicalizeSource' "$BINDIR" | sed 's|.*/||' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"

# LEG 2 — the whole population, per file, as ONE assertion, so a miss names the file that moved.
_FOLD_CENSUS_EXPECTED="$(printf '%s\n' '_kb-board-lib.sh=5' '_kbc-stale-blocker.py=1' \
                                       '_shellcheck-pinned=1' 'adopt-to-dl=1' \
                                       'agent-board-toolkit-runtime-check=5' \
                                       'gitignore-secret-family-check=2' 'kbcard=2' \
                                       'promote-released-cards=2' 'release-artifacts-check=1' \
                                       'release-pr-body=2')"
eq "every line under bin/ this predicate admits, attributed per file" \
   "$_FOLD_CENSUS_EXPECTED" "$(_fold_census "$BINDIR")"
# …and the DECLARATION above accounts for every one of them. The groups are prose — 3 mirrors,
# 9 other real folds, 10 lines that are not lowercase folds — and prose does not red on its own,
# so a file added to the block above without a line added to the declaration would ship a census
# that describes fewer lines than it counts. This arm is the arithmetic that binds the two.
eq "the declared groups account for every admitted line (3 + 9 + 10)" "22" \
   "$(printf '%s\n' "$_FOLD_CENSUS_EXPECTED" | awk -F= '{ n += $2 } END { print n+0 }')"

# LEG 3 — each mirror is WHERE its census says it is. Leg 2's counts alone are satisfied by two
# folds sitting anywhere in the file, which is the state this leg exists to distinguish from.
eq "promote's shell fold is inside src_canon, and only there" "1" \
   "$(_fn_src "$BINDIR/promote-released-cards" src_canon | _fold_count)"
# A FLOOR, not an exact count. The regression this catches is a side that STOPS canonicalizing
# — folds stay at 2 and the caller count drops to 1, which leg 2 cannot see. Pinning it at
# exactly 2 would instead red on a THIRD caller, i.e. on reuse of the primitive that was just
# hoisted, which is the behaviour this whole section exists to encourage.
eq "…and BOTH sides of the identity comparison call it"       "true" \
   "$( [ "$(command grep -c 'src_canon "' "$BINDIR/promote-released-cards")" -ge 2 ] && echo true || echo false )"
eq "promote's jq fold is inside canon_source"                 "1" \
   "$(awk '/def canon_source:/ {f=1} f {print} f && /end;[[:space:]]*$/ {exit}' "$BINDIR/promote-released-cards" | _fold_count)"
eq "adopt-to-dl's fold IS _ata_canon_source"                  "1" \
   "$(awk '/^_ata_canon_source\(\)/ {print}' "$BINDIR/adopt-to-dl" | _fold_count)"

# LEG 4 — the DOC half, which is the half that actually went stale. Every mirror symbol above is
# named in BOTH censuses; a copy added, renamed or hoisted without both being updated reds here
# rather than shipping a census that enumerates a set it no longer describes.
#
# ⛔ WORD-BOUNDED, AND THAT IS A CORRECTION. These arms used the prelude's `has`, a LITERAL
# substring test, and `_ata_canon_source` CONTAINS `canon_source` — so two of the six arms could
# not fail: deleting every standalone mention of the jq def from both censuses still answered
# `true`. `grep -w` is the fix and it is exact here, because `_` is a word constituent to grep,
# so `_ata_canon_source` does not satisfy `-w canon_source`. A herestring, not a pipeline —
# `tests/piped-match-gate-selftest.sh` owns that rule.
_names_sym() { command grep -qw -- "$1" <<< "$2" && echo true || echo false; }
# _redact_sym <symbol> <census> — the control's other half: strip the STANDALONE mentions of
# <symbol> and re-ask. awk with an explicit boundary class, NOT `sed` with `\b`: `\b` is a GNU
# extension, and a control that silently redacted nothing under a BSD sed would answer `true`
# and read as exactly the arm it exists to disprove. Each line is padded so a symbol sitting at
# either end still has a boundary character to match.
_redact_sym() {
  _names_sym "$1" "$(_S="$1" awk '{ s = " " $0 " "
      gsub("[^A-Za-z0-9_]" ENVIRON["_S"] "[^A-Za-z0-9_]", " REDACTED ", s)
      print substr(s, 2, length(s) - 2) }' <<< "$2")"
}
_census_of() { sed -n '/MIRRORS OF/,/^[^#]/p' "$1" | command grep '^#'; }
_PRC_CENSUS="$(_census_of "$BINDIR/promote-released-cards")"
_ATD_CENSUS="$(_census_of "$BINDIR/adopt-to-dl")"
for _sym in src_canon canon_source _ata_canon_source; do
  eq "promote's census names $_sym"     "true" "$(_names_sym "$_sym" "$_PRC_CENSUS")"
  eq "adopt-to-dl's census names $_sym" "true" "$(_names_sym "$_sym" "$_ATD_CENSUS")"
  # CONTROL, per symbol and per census — each of the six arms watched to fail on the one input
  # it exists to reject. `\b` does not match inside `_ata_canon_source`, so redacting
  # `canon_source` leaves the containing symbol intact: exactly the state the old arms passed on.
  eq "control: promote's census with $_sym redacted does NOT name it"     "false" \
     "$(_redact_sym "$_sym" "$_PRC_CENSUS")"
  eq "control: adopt-to-dl's census with $_sym redacted does NOT name it" "false" \
     "$(_redact_sym "$_sym" "$_ATD_CENSUS")"
done

# ── CONTROLS — the instrument discriminates in BOTH directions (canon #9) ────────────────────
_MIRROR_MUT="$TMP/mirror-mutant"
eq "promote-released-cards carries exactly its two mirror folds" "2" \
   "$(_fold_count < "$BINDIR/promote-released-cards")"

# ⭐ THE CAUGHT CORPUS. `<id>|<what the sample must print>|<a sample that must REALLY fold AbC>`.
# ⛔ THIS IS A REGRESSION BATTERY, NOT THE PREDICATE, and that is the whole difference from the
# predecessor. There it was the same table twice — the rows WERE the predicate and the control
# minted each row's own sample, so it could only ever demonstrate that a sample matches its own
# regex. Here the predicate is the two EREs above, written once, and every sample below is an
# independent program that knows nothing about them: an arm reds exactly when a real fold
# escapes the predicate, which is the property the leg claims. The corpus is every construct the
# languages under `bin/` provide, PLUS every spelling that has ever defeated a predecessor of
# this leg — kept verbatim so a widening can never be undone quietly.
# Each row is checked three ways: its expectation is a case-ONLY transform that folded at least
# one character (so a row cannot declare `want=AbC` and certify a construct that folds nothing);
# the sample is EXECUTED and must really fold; and the sample is minted as a fifth mirror inside
# `bin/promote-released-cards`, which must move that file's count by EXACTLY ONE.
# ⚑ SAMPLES WITH A USERLAND FLOOR, NAMED HERE RATHER THAN GUARDED AWAY: `sed-fold-rest`,
# `sed-fold-one` and `perl-lc-after-then` need GNU sed / perl, `dd-lcase` GNU coreutils'
# `conv=lcase`, and the `@L` rows bash >= 5.1 (its own cell below, so an older bash reports the
# FLOOR rather than an unexplained mismatch). On a BSD userland those rows fail naming
# themselves — a loud, self-describing red rather than a silent pass, which is why there is no
# `skip` arm. CI and this repo's reference host are both GNU with perl 5.
_FOLD_ROWS=()
while IFS= read -r _row; do [ -n "$_row" ] && _FOLD_ROWS+=("$_row"); done <<'ROWS'
bash-comma|abc|v=AbC; printf %s "${v,,}"
bash-comma-first|abC|v=AbC; printf %s "${v,}"
bash-comma-positional|abc|f() { printf %s "${1,,}"; }; f AbC
bash-at-L|abc|v=AbC; printf %s "${v@L}"
bash-at-L-positional|abc|f() { printf %s "${1@L}"; }; f AbC
bash-declare-l|abc|declare -l v; v=AbC; printf %s "$v"
bash-typeset-l|abc|typeset -l v; v=AbC; printf %s "$v"
bash-local-l|abc|f() { local -l v=AbC; printf %s "$v"; }; f
tr-posix|abc|printf %s AbC | tr '[:upper:]' '[:lower:]'
tr-range|abc|printf %s AbC | tr -s A-Z a-z
tr-range-dquoted|abc|printf %s AbC | tr "A-Z" "a-z"
tr-range-ddash|abc|printf %s AbC | tr -- 'A-Z' 'a-z'
tr-explicit|abc|printf %s AbC | tr ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz
sed-fold-rest|abc|printf %s AbC | sed 's/.*/\L&/'
sed-fold-one|abc|printf %s AbC | sed 's/\(.\)\(.\)\(.\)/\l\1\l\2\l\3/'
sed-y|abc|printf %s AbC | sed 'y/AC/ac/'
awk-tolower|abc|printf %s AbC | awk '{ printf "%s", tolower($0) }'
jq-ascii-downcase|abc|printf '"AbC"' | jq -rj ascii_downcase
py-lower|abc|python3 -c 'import sys; sys.stdout.write("".join(map(str.lower, "AbC")))'
py-casefold|abc|python3 -c 'import sys; sys.stdout.write("AbC".casefold())'
dd-lcase|abc|printf %s AbC | dd conv=lcase 2>/dev/null
perl-lc-after-then|abc|if true; then perl -pe '$_=lc' <<< AbC | tr -d '\n'; fi
perl-tr-slashed|abc|printf %s AbC | perl -pe 'tr/A-Z/a-z/'
ROWS
eq "this bash can execute the \${v@L} rows (bash >= 5.1)" "true" \
   "$( ((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 501)) && echo true || echo false )"
for _row in "${_FOLD_ROWS[@]}"; do
  IFS='|' read -r _id _want _sample <<< "$_row"
  eq "row $_id: its expected output is a case-only fold of AbC" "ABC/folded" \
     "$(printf '%s' "$_want" | tr 'a-z' 'A-Z')/$( [ "$_want" != AbC ] && echo folded || echo unfolded )"
  eq "row $_id: the construct really folds case" "$_want" "$(bash -c "$_sample" 2>&1)"
  cp "$BINDIR/promote-released-cards" "$_MIRROR_MUT"
  printf '%s\n' "$_sample" >> "$_MIRROR_MUT"
  eq "row $_id: minted as a fifth mirror it is COUNTED, not missed" "3" "$(_fold_count < "$_MIRROR_MUT")"
done

# THE MUTANT THAT DEFEATED THE TWO-SPELLING PREDICATE, verbatim, as its own named control — a
# new site with nothing removed, against which that predicate answered rc 0, 0 FAIL, § 3d 14/14.
cp "$BINDIR/promote-released-cards" "$_MIRROR_MUT"
cat >> "$_MIRROR_MUT" <<'FIFTH'
SOURCE_ALT="${SOURCE_IN:-}"; SOURCE_ALT="${SOURCE_ALT:0:255}"; SOURCE_ALT="${SOURCE_ALT,,}"
FIFTH
eq "control: the \${SOURCE_ALT,,} mirror that defeated the TWO-SPELLING predicate is counted" "3" \
   "$(_fold_count < "$_MIRROR_MUT")"
# AND THE MUTANT THAT DEFEATED THE 16-ROW TABLE ON A PROPERTY NO ROW HAD: a `tr` fold — a
# construct that table DID carry — split across a backslash continuation. Every predicate this
# leg has had until now read one PHYSICAL line, so the fold was invisible while both halves sat
# in plain sight. It is a wrapped pipeline, which is ordinary style, not an evasion. The operands
# are `A-Z`/`a-z` rather than the POSIX classes ON PURPOSE: a `[:lower:]` operand carries the
# word `lower`, so that half-line matches the NAMED disjunct alone and the arm would pass with
# the continuation join deleted — a control that cannot fail for the property it names, which is
# the defect this whole round removed. With these operands neither half matches anything alone.
cp "$BINDIR/promote-released-cards" "$_MIRROR_MUT"
cat >> "$_MIRROR_MUT" <<'WRAPPED'
SOURCE_ALT="$(printf '%s' "$SOURCE_IN" \
  | tr A-Z \
       a-z)"
WRAPPED
eq "control: a fold SPLIT ACROSS A CONTINUATION is one logical line, and counted" "3" \
   "$(_fold_count < "$_MIRROR_MUT")"
# …and NEITHER HALF is admitted on its own, which is what makes the arm above about the JOIN
# rather than about `tr`.
eq "control: …while neither half of it is admitted alone" "0" \
   "$(printf '%s\n' '  | tr A-Z' '       a-z)' | _fold_count)"
# …and it moves the CENSUS, not merely one file's count — the census is what leg 2 asserts, so
# the two are bound rather than adjacent.
_MUT_BIN="$TMP/mirror-mutant-bin"
rm -rf "$_MUT_BIN"; cp -r "$BINDIR" "$_MUT_BIN"
cp "$_MIRROR_MUT" "$_MUT_BIN/promote-released-cards"
eq "control: …and the per-file CENSUS moves with it" \
   "$(printf '%s\n' "$_FOLD_CENSUS_EXPECTED" | sed 's/^promote-released-cards=2$/promote-released-cards=3/')" \
   "$(_fold_census "$_MUT_BIN")"
rm -rf "$_MUT_BIN"
# ⭐ …AND A COPY IN A SUBDIRECTORY OF `bin/` MOVES IT TOO. This is the arm that would have
# stayed green through every predecessor of this leg: the walk skipped directories, so a mirror
# one level down was outside the population without anything saying so.
rm -rf "$_MUT_BIN"; cp -r "$BINDIR" "$_MUT_BIN"; mkdir -p "$_MUT_BIN/helpers"
printf '%s\n' '#!/usr/bin/env bash' 'canon() { printf %s "${1,,}"; }' > "$_MUT_BIN/helpers/canon.sh"
eq "control: a mirror in a SUBDIRECTORY of bin/ is inside the census" \
   "$(printf '%s\n%s\n' "$_FOLD_CENSUS_EXPECTED" 'helpers/canon.sh=1' | LC_ALL=C sort)" \
   "$(_fold_census "$_MUT_BIN")"
rm -rf "$_MUT_BIN"

# ⭐ TWO NAMED MEMBERS OF THE RESIDUAL, MEASURED. ⛔ THESE ARMS DO NOT BOUND THE RESIDUAL AND
# MUST NOT BE READ AS DOING SO — the residual is an open class (the six spellings named at the top
# of this section escape too, and are not minted here). What these two arms buy is narrower and
# still worth having: each is a REAL fold, executed here, whose INVOCATION LINE carries no evidence
# of a fold, minted the same way as the caught corpus and asserted to move the count by ZERO — so
# if a later widening catches one, its arm reds and the residual paragraph at the top of this
# section has to be revisited in the same commit instead of drifting out of date quietly.
eq "residual: alphabets reached through variables really do fold" "abc" \
   "$(bash -c 'UP=A-Z; LO=a-z; printf %s AbC | tr "$UP" "$LO"' 2>&1)"
cp "$BINDIR/promote-released-cards" "$_MIRROR_MUT"
cat >> "$_MIRROR_MUT" <<'ESCAPE1'
SOURCE_ALT="$(printf '%s' "$SOURCE_IN" | tr "$UP_ALPHA" "$LO_ALPHA")"
ESCAPE1
eq "residual: …and its invocation line ESCAPES, exactly as stated above" "2" \
   "$(_fold_count < "$_MIRROR_MUT")"
eq "residual: an arithmetic fold really does fold" "abc" \
   "$(bash -c 'python3 -c '\''import sys; sys.stdout.write("".join(chr(ord(c)+32) if "A"<=c<="Z" else c for c in "AbC"))'\''' 2>&1)"
cp "$BINDIR/promote-released-cards" "$_MIRROR_MUT"
cat >> "$_MIRROR_MUT" <<'ESCAPE2'
SOURCE_ALT="$(python3 -c 'import sys; sys.stdout.write("".join(chr(ord(c)+32) if "A"<=c<="Z" else c for c in sys.argv[1]))' "$SOURCE_IN")"
ESCAPE2
eq "residual: …and so does an arithmetic one" "2" "$(_fold_count < "$_MIRROR_MUT")"

# ⛔ THE NEGATIVE CONTROLS AN OVER-BROAD PREDICATE OWES. Every `minted ⇒ 3` arm above is
# satisfied by a predicate that matches EVERYTHING, so without these the whole battery is
# vacuous — the same shape as the leg-B defect this round removed, one level up. Each line below
# is a real line of this tree, or one modelled on one, that must NOT be admitted.
while IFS='|' read -r _id _line; do
  cp "$BINDIR/promote-released-cards" "$_MIRROR_MUT"
  printf '%s\n' "$_line" >> "$_MIRROR_MUT"
  eq "negative control: $_id is not admitted" "2" "$(_fold_count < "$_MIRROR_MUT")"
done <<'NEGATIVES'
a fold NAMED in a comment|# a comment naming ascii_downcase and ${v,,} is prose, not a fold
a plain assignment|SOURCE_ALT="$SOURCE_IN"
an LC_ALL=C locale pin|uint_ok2() { local LC_ALL=C; case "${1:-}" in ''|*[!0-9]*) return 1 ;; esac; }
an A-Za-z character class|kb_ere_match "$1" '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'
a ${!prefix@} name expansion|unset ${!KB_STAGE_@}
a -l flag on another command|NLINES="$(wc -l < "$f")"
NEGATIVES
echo "== 3e. THE THREE canonicalizeSource COPIES, BOUND BY BEHAVIOUR: one corpus, all three (card#8538) =="
# WHY NAME AND COUNT ARE NOT ENOUGH, and why this section exists beside § 3d rather than instead
# of it. § 3d LOCATES copies — it checks that the three the censuses name are where they say, and
# it catches a fourth spelled in a way its predicate admits; it is best-effort and says so, and a
# copy spelled outside that predicate is invisible to it. This section is the one that does not
# depend on any of that, because it does not read for a spelling at all. What it covers is also
# the class that has already cost this repo a defect: card#8421's divergence was BEHAVIOURAL, between two copies that were
# both present, both named and both counted (the `.GIT` casing). Concretely, what a divergence
# buys here is a SILENT ZERO in both directions — a `src_canon` ↔ `canon_source` disagreement
# over the admitted charset makes the config and card sides of promote's ONE comparison answer
# differently, so a release promotes 0 at rc 0 or promotes another repo's cards; an
# `_ata_canon_source` disagreement makes the source STAMPED at adopt time unmatchable at promote
# time, the same zero one bin over. This is § 3c's one-corpus-through-both pattern, applied to
# the folds instead of to the accept set.
#
# THE COPIES ARE DRIVEN, NOT READ. Each is extracted from the shipped file by the same awk § 3d
# uses to locate it, and executed — the two shell copies in a FRESH bash, so nothing this harness
# has defined can stand in for them, and the jq def as a program string, which is the only way it
# is ever reachable (a bash function cannot be called from inside `jq`, which is exactly why the
# copy exists).
#
# THE CORPUS IS RESTRICTED TO VALUES `kb_is_repo_slug` ADMITS, AND THAT IS THE CONTRACT, not a
# convenience: `_ata_canon_source` deliberately omits the trim and the 255-cap because its
# caller's gate has already refused every value either would change. Over that set all three must
# agree EXACTLY. The two omissions are then asserted SEPARATELY and in both directions as the
# DECLARED divergence, so unifying the copies by accident reds here rather than passing quietly.
_SRC_CANON_SRC="$(_fn_src "$BINDIR/promote-released-cards" src_canon)"
_ATA_CANON_SRC="$(awk '/^_ata_canon_source\(\)/ {print; exit}' "$BINDIR/adopt-to-dl")"
_JQ_CANON_SRC="$(awk '/def canon_source:/ {f=1} f {print} f && /end;[[:space:]]*$/ {exit}' "$BINDIR/promote-released-cards")"
eq "the three copies were all extracted (non-empty)" "yes yes yes" \
   "$( [ -n "$_SRC_CANON_SRC" ] && printf yes || printf no
      [ -n "$_ATA_CANON_SRC" ] && printf ' yes' || printf ' no'
      [ -n "$_JQ_CANON_SRC" ] && printf ' yes' || printf ' no' )"
# <function source> <function name> <value> — a fresh shell per call.
_fold_sh() { bash -c 'eval "$1"; "$2" "$3"' _ "$1" "$2" "$3"; }
# The jq def with `// ""` on the tail: `canon_source` answers null for a value that canonicalizes
# to nothing, and the shell copies answer the empty string; rendering null as "" is what makes
# the two comparable rather than papering over a difference (the empty row below pins it).
_fold_jq() { jq -rn --arg v "$1" "$_JQ_CANON_SRC (\$v | canon_source) // \"\""; }

while IFS= read -r _v; do
  [ -n "$_v" ] || continue
  _v="${_v#|}"
  _want="$(_fold_sh "$_SRC_CANON_SRC" src_canon "$_v")"
  eq "corpus '$_v' → jq canon_source agrees with src_canon"        "$_want" "$(_fold_jq "$_v")"
  eq "corpus '$_v' → _ata_canon_source agrees with src_canon"      "$_want" \
     "$(_fold_sh "$_ATA_CANON_SRC" _ata_canon_source "$_v")"
done <<'FOLDROWS'
|acme/widget
|ACME/Widget
|ACME/WIDGET
|AcMe/WiDgEt
|acme_org/My-Repo
|acme2/WIDGET3
|acme.github/Widget
|acme/widget.GITIGNORE
|A/B
|acme/Widget.js
FOLDROWS
# The empty value, and the one row where the shell copies and the jq def are TYPED differently:
# jq answers `null`, both shell copies answer the empty string, and the rendering above is what
# binds them. Asserted, because a future `// "-"` or a dropped `//` would change what promote
# compares against and nothing else here would see it.
eq "an empty value: src_canon"                     ""     "$(_fold_sh "$_SRC_CANON_SRC" src_canon '')"
eq "an empty value: _ata_canon_source"             ""     "$(_fold_sh "$_ATA_CANON_SRC" _ata_canon_source '')"
eq "an empty value: the jq def answers null"       "null" "$(jq -rn --arg v '' "$_JQ_CANON_SRC (\$v | canon_source) | type")"

# THE TWO DECLARED DIVERGENCES — `_ata_canon_source` omits the trim and the 255-cap. Both are
# asserted in BOTH directions: the two full copies must perform them and the partial copy must
# not, so a well-meaning "fix" that unifies the three reds here and meets the reason first.
_PADDED='  ACME/Widget  '
eq "declared divergence: src_canon TRIMS"          "acme/widget"     "$(_fold_sh "$_SRC_CANON_SRC" src_canon "$_PADDED")"
eq "…and so does the jq def"                       "acme/widget"     "$(_fold_jq "$_PADDED")"
eq "…while _ata_canon_source does NOT"             "  acme/widget  " "$(_fold_sh "$_ATA_CANON_SRC" _ata_canon_source "$_PADDED")"
_LONG="acme/$(printf 'W%.0s' {1..300})"
eq "declared divergence: src_canon CAPS at 255"    "255" "$(_fold_sh "$_SRC_CANON_SRC" src_canon "$_LONG" | wc -c | tr -d ' ')"
eq "…and so does the jq def"                       "255" "$(_fold_jq "$_LONG" | tr -d '\n' | wc -c | tr -d ' ')"
eq "…while _ata_canon_source does NOT"             "305" "$(_fold_sh "$_ATA_CANON_SRC" _ata_canon_source "$_LONG" | wc -c | tr -d ' ')"

# CONTROLS — the corpus DISCRIMINATES, and each control is pinned on the mutant's OWN output
# rather than on "they now differ": a mutation that merely broke the function would also make
# them differ, and would certify nothing. Each mutant must answer the UNFOLDED value exactly,
# which is only true if the harness really reached that copy and the fold really was what moved.
# Each mutation is applied to the EXTRACTED source, never to the file under `bin/`.
eq "control: src_canon with its fold removed answers the UNFOLDED value" "ACME/Widget" \
   "$(_fold_sh "$(printf '%s' "$_SRC_CANON_SRC" | sed "s/LC_ALL=C tr '\[:upper:\]' '\[:lower:\]'/cat/")" src_canon 'ACME/Widget')"
eq "control: the jq def with ascii_downcase removed does the same"       "ACME/Widget" \
   "$(jq -rn --arg v 'ACME/Widget' "$(printf '%s' "$_JQ_CANON_SRC" | sed 's/ | ascii_downcase//') (\$v | canon_source) // \"\"")"
eq "control: _ata_canon_source with its fold removed does the same"      "ACME/Widget" \
   "$(_fold_sh "$(printf '%s' "$_ATA_CANON_SRC" | sed "s/tr '\[:upper:\]' '\[:lower:\]'/cat/")" _ata_canon_source 'ACME/Widget')"

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

echo "== 7. THE DECLARATION IS CHECKED AGAINST THE REPO IT IS MADE IN (card#8538) =="
# WHAT § 1-§ 6 CANNOT SEE. Every arm above asks whether the declared source is well SHAPED and
# whether the correlation honours it. None asks whether the declaration is TRUE: a typo'd or
# copy-pasted slug — `acme/wdiget`, or a slug lifted from the repo the config was copied from —
# passes the shape `case`, passes `src_charset_ok`, and then correlates against NO card. The
# run prints `⊘` lines nobody reads and exits 0 having promoted nothing. A guard whose failure
# mode is a clean exit is the class this whole file exists for, one level up.
#
# $GITHUB_REPOSITORY is set EXPLICITLY on each arm: the variable IS the subject here, so
# inheriting it from the runner would make the arms mean different things in CI and on a laptop.
# The first assertion is the FLOOR the rest of the suite depends on — the prelude's `unset`. It
# is vacuous on a laptop by construction (nothing sets the variable there) and is the only thing
# in the suite that reds IN CI if that line is deleted, which is exactly where it is needed.
# Watched red: delete the prelude's `unset`, export GITHUB_REPOSITORY, re-run this file and the
# two named there — this arm reds, and so do the arms it protects.
eq "the prelude floor holds: no runner \$GITHUB_REPOSITORY reaches this suite" "" "${GITHUB_REPOSITORY+set}"
run7() { # run7 <GITHUB_REPOSITORY value or OMIT> <config> [args...]
  local gh="$1"; shift
  local cfg="$1"; shift
  : > "$PATCH_LOG"; : > "$TMP/gets.log"; rc=0
  if [ "$gh" = OMIT ]; then
    out="$( (cd "$GITDIR" && env -u GITHUB_REPOSITORY GITHUB_ACTIONS=1 GET_LOG="$TMP/gets.log" "$PRC" --config "$cfg" "$@") 2>"$TMP/err")" || rc=$?
  else
    out="$( (cd "$GITDIR" && env GITHUB_REPOSITORY="$gh" GITHUB_ACTIONS=1 GET_LOG="$TMP/gets.log" "$PRC" --config "$cfg" "$@") 2>"$TMP/err")" || rc=$?
  fi
  err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"; gets="$(cat "$TMP/gets.log")"
}

# THE REFUSAL, and like § 1 it is asserted on the GET log rather than on an empty PATCH set: a
# run that read the board and then moved nothing would satisfy an empty PATCH while the
# writeback token had already gone over the wire.
run7 acme/other "$CFG_REPO"
eq "a source naming a DIFFERENT repo → rc 2"        "2"     "$rc"
eq "…no card was PATCHed"                           ""      "$patched"
eq "…and NO board GET was issued at all"            ""      "$gets"
eq "refusal names the declared source"              "true"  "$(has "'acme/widget'" "$err")"
eq "…names the repo the run is actually in"         "true"  "$(has "GITHUB_REPOSITORY = 'acme/other'" "$err")"
eq "…names the channel the value came from"         "true"  "$(has ".promote.source" "$err")"
eq "…and spells the fix with the real value"        "true"  "$(has "to 'acme/other'" "$err")"

# CASE-FOLDED, both sides, because GitHub slugs are case-insensitive and a config written
# `Acme/Widget` names the same repository as a runner saying `acme/widget`. Without this arm the
# leg would refuse a correct config on any repo whose owner is capitalised — which is most.
run7 Acme/Widget "$CFG_REPO"
eq "a case-different but EQUAL slug is accepted"    "true"  "$(has '/tasks/search.json' "$gets")"
eq "…and promotes our own card"                     "true"  "$(moved 1)"

# THE TWO NON-FIRING ARMS, each for a stated reason, and each is a control: without them the
# refusal above is satisfied by a leg that simply refuses everything.
run7 OMIT "$CFG_REPO"
eq "OFF a runner (no GITHUB_REPOSITORY) the leg does not fire" "true" "$(has '/tasks/search.json' "$gets")"
eq "…and the run proceeds normally"                 "true"  "$(moved 1)"
run7 '' "$CFG_REPO"
eq "an EMPTY GITHUB_REPOSITORY does not fire either" "true" "$(has '/tasks/search.json' "$gets")"
run7 acme/other "$CFG_STAR"
eq "'*' is a DECLARATION, not a repo name — exempt"  "true" "$(has '/tasks/search.json' "$gets")"
eq "…and it still promotes every matched card"       "true" "$(moved 2)"

# THE FLAG IS NOT AN ESCAPE HATCH. `--source` is the per-run override of the VALUE, and the leg
# applies to whatever it resolved to: a run that promotes another repo cards is the failure, not
# the channel that asked for it. Asserted because the opposite is the natural implementation.
run7 acme/other "$CFG_STAR" --source acme/widget
eq "--source cannot escape the check"               "2"     "$rc"
eq "…and the refusal names the flag as the channel" "true"  "$(has 'from --source' "$err")"

# MUTANT — the leg deleted. Without this the arms above pass under a bin that never had it.
mutant identity-off '/GH_REPO="${GITHUB_REPOSITORY:-}"/,/^fi$/d'
: > "$PATCH_LOG"; : > "$TMP/gets.log"; rc=0
out="$( (cd "$GITDIR" && env GITHUB_REPOSITORY=acme/other GITHUB_ACTIONS=1 GET_LOG="$TMP/gets.log" "$MUT" --config "$CFG_REPO") 2>"$TMP/err")" || rc=$?
err="$(cat "$TMP/err")"; patched="$(cat "$PATCH_LOG")"; gets="$(cat "$TMP/gets.log")"
eq "M5 (identity leg deleted): the mismatched run reads the board" "true" "$(has '/tasks/search.json' "$gets")"
eq "M5: …and exits 0 having promoted our own card"  "0"     "$rc"
eq "M5: …so § 7's refusal arms would all red"       "false" "$(has 'is not the repository this run is in' "$err")"

_summary "promote-source-qualify-selftest"
