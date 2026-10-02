#!/usr/bin/env bash
# mirror-pair-parity-selftest.sh — the extract-and-exercise pin for the `bin/` mirror pairs that
# were held by a `keep the two in sync` COMMENT and by nothing else (card#8529).
#
# WHAT A MIRROR PAIR IS HERE. `bin/` ships four tools that are vendored STANDALONE into consumer
# repos and must not source `bin/_kb-board-lib.sh` — `promote-released-cards`,
# `release-artifacts-check`, `release-pr-body`, `release-tag-check`. Each therefore carries its
# own inline copy of a rule that ANOTHER shipped file owns. That duplication is not an oversight
# to remove: `docs/CONSOLIDATION-PLAN.md` § Stage D DECIDED (2026-08-01) against making them
# source the lib, and chose GUARDED duplication instead. This file is some of that guard.
#
# ⚠ THE OTHER END IS USUALLY THE LIB AND IS NOT ALWAYS THE LIB (§ 6, card#9938). A standalone that
# cannot source the lib cannot exec a sibling BIN either — it is vendored alone — so a rule owned
# by `bin/kbcard` (the write-outcome ladder, card#8556) reaches it by the same duplication, under
# the same policy, and drifts the same way. The pairs below are therefore "the standalone's copy
# ↔ the file that OWNS the rule", not "↔ the lib"; nothing about the pin changes with the end.
#
# ⚑ AND A PAIR NEED NOT HAVE A LIB ORIGINAL TO BELONG HERE. `require_resolvable` below is two
# STANDALONES compared against each other, and § 7 is a standalone compared against a bin that DOES
# source the lib. What makes something a member is the property, not the topology: one ruling
# written twice, with nothing that reds when a fix lands in one copy and misses the other.
#
# WHY IT EXISTS. `kb-host-guard-selftest.sh`, `kb-positional-guard-selftest.sh`,
# `url-userinfo-render-selftest.sh`, `promote-pagination-selftest.sh`,
# `promote-source-qualify-selftest.sh` and `token-duplication-selftest.sh` already pin one pair
# each, row-by-row, by EXTRACTING the standalone copy and driving it beside the lib's. The pairs
# below had no such file: a fix landing in one copy and missing its twin shipped a guard that was
# right in the tool and wrong in the lib, with a green suite, because nothing compared them. That
# is not hypothetical — PR #322's MF-1 was a case-sensitive `.git` arm fixed in one repo-slug copy
# while the published contract was case-insensitive, under exactly such a comment.
#
# `tests/mirror-pair-census.sh` beside this file re-derives the POPULATION of mirror candidates
# in `bin/` and prints a per-copy verdict; it is the instrument, this is the pin. Neither one
# enumerates the pairs in prose: the `require_value` block below DERIVES its copy set from the
# tree, so a fifth standalone growing one is driven on the day it lands rather than on the day
# somebody remembers this file.
#
# WEAKEST PROPERTY OF A GREEN RUN. Each block proves its copies agree on the corpus it feeds, and
# nothing about an input class absent from that corpus. It proves nothing about a call SITE left
# hand-rolled — a tool that never calls its own copy passes every row here (the call sites are
# pinned by `expect_value_flags` in the per-tool selftests, which is the other half). Where two
# copies DELIBERATELY disagree, the disagreement is asserted as a value rather than skipped, so
# "declared divergence" cannot quietly grow a member.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_shipped-shell-lib.sh"
ROOT="$(cd "$HERE/.." && pwd)"
LIB="$ROOT/bin/_kb-board-lib.sh"
PRC="$ROOT/bin/promote-released-cards"
RPB="$ROOT/bin/release-pr-body"
NDL="$ROOT/bin/next-dl"
_need -r "$LIB"
_need -x "$PRC"
_need -x "$RPB"
_need -x "$NDL"

# shellcheck source=/dev/null
source "$LIB"
KB_PROG="mirror-pair-parity-selftest"

_mktmp_scratch --home

# ═══════════════════════ 1 — `require_value` × N standalones vs `kb_require_value` ═══════════
#
# THE POPULATION IS DERIVED, NOT LISTED. Every shipped shell file defining `require_value` at
# column zero is a copy, found through `_shipped_shell_files` — the ONE derivation of the set CI's
# own analyser step covers, owned by `tests/_shipped-shell-lib.sh`. A hand list here would be the defect this
# card is about, one layer up: it could not red on the fifth copy.
echo "== the require_value copy set, derived from the tree =="
RV_COPIES=()
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    command grep -qE '^require_value[[:space:]]*\(\)' "$ROOT/$f" && RV_COPIES+=("$f")
done < <(_shipped_shell_files "$ROOT")
# A witness before any comparison: an empty copy set satisfies every loop below and would report
# a clean parity run having compared nothing.
eq "witness: the derivation found copies at all" "false" \
   "$([[ "${#RV_COPIES[@]}" -eq 0 ]] && echo true || echo false)"
eq "…and the lib owns the original" "true" \
   "$(has_line 'kb_require_value() {' "$(cat "$LIB")")"
printf '   copies: %s\n' "${RV_COPIES[*]}"

# _rv_src <relpath> — the copy's source TEXT, extracted at top level so a rename ends the run
# HERE rather than inside a subshell, where an empty extraction reads as a refusal (the
# `_fn_src` docblock's own warning). One line: these copies are one-line functions, which is
# what the primitive's one-line mode is for.
declare -A RV_SRC=()
for f in "${RV_COPIES[@]}"; do RV_SRC["$f"]="$(_fn_src "$ROOT/$f" require_value)"; done

# _tool_verdict <src-text> <args...> — accept|refuse for one extracted copy. The copies `die`
# (exit 2 with the tool's own prefix) where the lib RETURNS 1 with a `$(_kb_prog)` prefix; the
# exit path and the message are DIFFERENT BY DESIGN — each tool names itself, and promote's
# refusal policy is its own — so the compared property is the DECISION, which is the half that
# must not diverge.
_tool_verdict() {
    local src="$1"; shift
    local out rc=0
    out="$( exec 2>/dev/null
            die() { printf 'die: %s\n' "$*" >&2; exit 2; }
            eval "$src"
            require_value "$@" && printf 'accept' )" || rc=$?
    [[ "$rc" -eq 0 && "$out" == accept ]] && printf 'accept' || printf 'refuse'
}
_lib_verdict() {
    local rc=0
    kb_require_value "$@" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 0 ]] && printf 'accept' || printf 'refuse'
}

# THE CORPUS, written ONCE and driven by both the parity rows and the control below — a control
# fed a different corpus proves the comparison discriminates on inputs the rows never see.
# `--flag` with NO second argument is the trailing-flag case both copies exist to convert from a
# bare `set -u` error into a diagnostic naming the flag; `" "` and `"0"` are the falsy-looking
# values a `[ "$2" ]` spelling would wrongly refuse.
#
# ⛔ EVERY ROW ENDS IN A SENTINEL FIELD, and that is not decoration. Args are unit-separator joined
# so an empty and a whitespace argument survive being carried in a list — but bash `read -a` drops
# a TRAILING empty field, so `--flag ""` written as a trailing separator arrived as `--flag` alone
# and the EMPTY-VALUE row, the one input this whole guard family exists for (card#5144: an empty
# `--shipped-stages` silently selecting the no-guard default), was never driven. It passed, because
# both spellings refuse. The sentinel keeps the empty field non-terminal; `_row_args` strips it,
# and the witness below asserts the row really parses to two arguments with the second empty —
# without it this file would regress to measuring nothing exactly where it looks strongest.
US=$'\x1f'
EOR='<end-of-row>'
RV_CORPUS=(
    "a non-empty value${US}--flag${US}value${US}$EOR"
    "an EMPTY value${US}--flag${US}${US}$EOR"
    "no second argument at all${US}--flag${US}$EOR"
    "whitespace is NOT empty${US}--flag${US} ${US}$EOR"
    "a falsy-looking real value${US}--flag${US}0${US}$EOR"
    "a value shaped like a flag${US}--flag${US}--other${US}$EOR"
)
# _row_args <row> — sets ROW_LABEL and the ROW_ARGS array. The sentinel is asserted present rather
# than assumed: a row that lost it would silently pass its literal text in as an argument.
_row_args() {
    local -a f=()
    IFS="$US" read -r -a f <<< "$1"
    [[ "${f[${#f[@]}-1]}" == "$EOR" ]] || { bad "corpus row lost its sentinel: $1"; return 1; }
    ROW_LABEL="${f[0]}"
    ROW_ARGS=("${f[@]:1:${#f[@]}-2}")
}

_row_args "${RV_CORPUS[1]}"
eq "witness: the EMPTY-value row carries two arguments"        "2"  "${#ROW_ARGS[@]}"
eq "witness: …and the second of them is genuinely empty"       "''" "'${ROW_ARGS[1]}'"
_row_args "${RV_CORPUS[2]}"
eq "witness: the no-second-argument row carries one, so the two rows are DIFFERENT inputs" "1" "${#ROW_ARGS[@]}"

echo "== require_value: every copy agrees with kb_require_value, row by row =="
for _row in "${RV_CORPUS[@]}"; do
    _row_args "$_row" || continue
    _want="$(_lib_verdict "${ROW_ARGS[@]}")"
    for _f in "${RV_COPIES[@]}"; do
        _got="$(_tool_verdict "${RV_SRC["$_f"]}" "${ROW_ARGS[@]}")"
        if [[ "$_got" != "$_want" ]]; then
            bad "$ROW_LABEL — $_f says $_got, bin/_kb-board-lib.sh says $_want"
        else
            ok "$ROW_LABEL — $_f agrees ($_want)"
        fi
    done
done

# THE CONTROL, on a REAL copy rather than a fixture this file wrote. One shipped copy's `-n` is
# flipped to `-z` in memory and driven through the SAME corpus: the rows above are the copies
# AGREEING with the lib, not a comparison that passes whatever it is handed. `-z` is the exact
# negation of the predicate, so it must disagree on EVERY row — asserted as that count and not as
# "at least one", because a control that silently stopped extracting (empty source ⇒ every row
# refuses at rc 127) disagrees on only the accept rows and would satisfy a weaker bar.
echo "== control: a MUTATED copy of a real bin is caught by the same comparison =="
RV_MUT="${RV_SRC["${RV_COPIES[0]}"]//-n /-z }"
eq "control: the mutation changed the source text" "false" \
   "$([[ "$RV_MUT" == "${RV_SRC["${RV_COPIES[0]}"]}" ]] && echo true || echo false)"
mut_disagree=0
for _row in "${RV_CORPUS[@]}"; do
    _row_args "$_row" || continue
    [[ "$(_tool_verdict "$RV_MUT" "${ROW_ARGS[@]}")" == "$(_lib_verdict "${ROW_ARGS[@]}")" ]] \
        || mut_disagree=$((mut_disagree + 1))
done
eq "control: the flipped copy disagrees on every corpus row" "${#RV_CORPUS[@]}" "$mut_disagree"

# ═══════════════════════ 2 — `require_resolvable`: promote ↔ release-pr-body ═════════════════
#
# The two release bins carry the same predicate — `git rev-parse --verify -q "$2^{commit}"` —
# and the `^{commit}` peel is the load-bearing half: `--verify` alone exits 0 for a 40-hex string
# naming NO object (measured, git 2.43.0), so a sha copied off a rebased-away branch would build
# a range that walks NOTHING and be reported as "nothing to do" at rc 0. Each tool's own selftest
# has a hex-sha arm, which reds if THAT copy loses the peel; nothing compared the two copies, so a
# NEW input class handled differently by each was invisible. The MESSAGES diverge on purpose (each
# names what its own tool does with a dead range) and are not compared.
echo "== require_resolvable: the two release copies agree over one corpus =="
RR_A="$(_fn_src "$PRC" require_resolvable)"
RR_B="$(_fn_src "$RPB" require_resolvable)"
eq "control: both copies extracted with a body" "true" \
   "$([[ "$RR_A" == *'rev-parse'* && "$RR_B" == *'rev-parse'* ]] && echo true || echo false)"

REPO="$TMP/gitrepo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@invalid -c user.name=t commit -q --allow-empty -m first
git -C "$REPO" -c user.email=t@invalid -c user.name=t tag -a v1 -m v1
REAL_SHA="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" -c user.email=t@invalid -c user.name=t commit -q --allow-empty -m second
# A 40-hex string that names no object: the class the peel exists for. Derived by rotating a real
# sha's hex digits rather than typed, so it cannot accidentally BE an object in this repo.
DEAD_SHA="$(printf '%s' "$REAL_SHA" | tr '0123456789abcdef' 'fedcba9876543210')"
eq "control: the dead sha is 40 hex and is not an object here" "true" \
   "$([[ "${#DEAD_SHA}" -eq 40 ]] && ! git -C "$REPO" cat-file -e "$DEAD_SHA" 2>/dev/null && echo true || echo false)"

_rr_verdict() { # <src-text> <ref>
    local src="$1" ref="$2" rc=0
    ( cd "$REPO" || exit 9
      die() { printf 'die: %s\n' "$*" >&2; exit 2; }
      eval "$src"
      require_resolvable --head "$ref" ) >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 0 ]] && printf 'accept' || printf 'refuse'
}
_rr_case() { # <label> <ref> <want>
    local label="$1" ref="$2" want="$3"
    local a b
    a="$(_rr_verdict "$RR_A" "$ref")"; b="$(_rr_verdict "$RR_B" "$ref")"
    if [[ "$a" != "$want" ]]; then
        bad "$label — promote-released-cards says $a, want $want"
    elif [[ "$b" != "$a" ]]; then
        bad "$label — the two copies DISAGREE: promote=$a release-pr-body=$b"
    else
        ok "$label (both copies $want)"
    fi
}
_rr_case "a live commit sha"          "$REAL_SHA" accept
_rr_case "HEAD"                       "HEAD"      accept
_rr_case "an ANNOTATED tag peels"     "v1"        accept
_rr_case "a 40-hex non-object"        "$DEAD_SHA" refuse
_rr_case "a ref that does not exist"  "no-such"   refuse
_rr_case "an empty ref"               ""          refuse

# THE CONTROL, again on the real text: strip the `^{commit}` peel from ONE copy and the 40-hex row
# must invert. Without it every row above would pass just as well for two copies that had both
# lost the peel — the shape `docs/CONSOLIDATION-PLAN.md` records the host-guard mirror losing.
echo "== control: dropping the ^{commit} peel from one copy inverts the 40-hex row =="
RR_NOPEEL="${RR_A//\^\{commit\}/}"
eq "control: the peel really came out"      "false" "$(has '^{commit}' "$RR_NOPEEL")"
eq "control: unpeeled, the 40-hex non-object is ACCEPTED" "accept" "$(_rr_verdict "$RR_NOPEEL" "$DEAD_SHA")"
eq "control: …while the peeled copy still refuses it"     "refuse" "$(_rr_verdict "$RR_A" "$DEAD_SHA")"

# ═══════════════════════ 3 — `uint_ok` vs `kb_is_uint`: a DECLARED divergence ════════════════
#
# promote-released-cards' `uint_ok`/`uint_csv_ok` sat under "Mirrors kb_ere_match/kb_is_uint in
# _kb-board-lib.sh — … the guard is duplicated; keep the two in sync". That claim was FALSE on the
# accept set and had been since both were written: `kb_is_uint` is `^(0|[1-9][0-9]*)$` and refuses
# a leading zero, `uint_ok` is a `*[!0-9]*` glob and accepts one. What the two genuinely share is
# the LC_ALL=C pin — a bracket range is a COLLATION range, so under en_US.UTF-8 both admit
# U+0663 without it — and `tests/locale-range-guard-selftest.sh` owns that leg and drives both
# copies under both locales. It is not repeated here.
#
# What is pinned here is the part nothing held: the divergence itself, as a VALUE. A "declared
# divergence" with no row asserting it is indistinguishable from a drift nobody noticed, and it
# can grow a member silently — which is how a comment claiming equality survived.
echo "== uint_ok vs kb_is_uint: agreement, and the ONE declared divergence =="
_adopt_fn "$PRC" uint_ok
_uv() { local rc=0; uint_ok "$1" || rc=1; [[ "$rc" -eq 0 ]] && printf accept || printf refuse; }
_kv() { local rc=0; kb_is_uint "$1" || rc=1; [[ "$rc" -eq 0 ]] && printf accept || printf refuse; }
for v in 0 1 42 999999 "" " " "1x" "x" "-1" "1.0" "1,2"; do
    eq "uint_ok agrees with kb_is_uint on [$v]" "$(_kv "$v")" "$(_uv "$v")"
done
# THE DIVERGENCE, asserted in both directions so neither side can quietly move onto the other.
eq "declared divergence: kb_is_uint REFUSES a leading zero"  "refuse" "$(_kv 007)"
eq "declared divergence: uint_ok ACCEPTS one"                "accept" "$(_uv 007)"
eq "declared divergence: …and the same on a longer run (lib)" "refuse" "$(_kv 093)"
eq "declared divergence: …and on the mirror"                 "accept" "$(_uv 093)"
# The divergence set is CLOSED over the corpus above: exactly two inputs may differ, and both are
# leading-zero forms. A third would land in the agreement rows and red there.

# ═══════════════════════ 4 — retired: the owner-tag clear (card#10868) ═══════════════════════
#
# promote-released-cards used to strip `owner:*` tags from a card it released, through its own
# copies of the lib's tag rules, and this section held the two together. card#10868 retired the
# clear — a released card keeps its assignee and tags (README.md § The card owner) — so neither
# copy exists any more and there is nothing to pair. The number is kept so the sections below keep
# the numbers other files cite.

# ═══════════════════════ 5 — `repo_from_gh_url`: promote ↔ KB_JQ_REPO_FROM_GH_URL ══════════════
#
# The board attributes a card (by-ref `source`) from a GitHub URL — where no `payload.repo`
# that is a string containing `/` outranks it — through one rule, which
# promote-released-cards mirrors in jq as `def repo_from_gh_url:`. `kbcard patch` and `adopt-to-dl`
# ask the SAME question — does a URL written without its number still attribute the card to a
# repo? (card#9846) — through the lib's `KB_JQ_REPO_FROM_GH_URL`, which is that def's text. The
# standalone must not source the lib, so the def exists twice; what holds them together is THIS:
# the two texts are identical line for line (indentation aside — the standalone's copy sits
# indented inside a larger program), and both are driven over one corpus so an extraction that
# found the wrong lines cannot pass by comparing two empties.
echo "== repo_from_gh_url: the lib constant IS the standalone's def, line for line =="
_rfg_strip() { sed 's/^[[:space:]]*//'; }
_rfg_prc="$(awk '/^[[:space:]]*def repo_from_gh_url:/ {on=1} on {print} on && /^[[:space:]]*end;[[:space:]]*$/ {exit}' "$PRC" | _rfg_strip)"
eq "witness: the lib defines KB_JQ_REPO_FROM_GH_URL" "false" "$([[ -z "${KB_JQ_REPO_FROM_GH_URL:-}" ]] && echo true || echo false)"
eq "witness: the extraction found the def's head and its close" "true|true" \
   "$(has 'def repo_from_gh_url:' "$_rfg_prc")|$([[ "${_rfg_prc##*$'\n'}" == "end;" ]] && echo true || echo false)"
eq "⭐ the standalone's def IS KB_JQ_REPO_FROM_GH_URL, line for line" \
   "$(printf '%s\n' "$KB_JQ_REPO_FROM_GH_URL" | _rfg_strip)" "$_rfg_prc"
echo "== repo_from_gh_url: both copies agree over one corpus =="
# _rfg <def-text> <json-value> — the def's answer for one payload value, `null` when none.
_rfg() { jq -cn --argjson v "$2" "$1"' $v | repo_from_gh_url'; }
_rfg_corpus=('"https://github.com/acme/widget/pull/1"' '"https://GitHub.com/acme/widget.git/commit/abc"'
    '"https://github.com/acme/widget/tree/main"' '"https://github.com/acme/widget/blob/main/x.md"'
    '"https://github.com/acme/widget/issues/"' '"https://user:t@github.com/acme/widget/pull/abc"'
    '" see https://github.com/acme/widget/issues/9 "' '"https://github.com/acme/widget"'
    '"https://github.com/acme/widget/wiki"' '"https://example.com/acme/widget/pull/1"' '""'
    '{"u":"https://github.com/acme/widget/pull/1"}' '["https://github.com/acme/widget/pull/1"]' '42' 'null')
for _v in "${_rfg_corpus[@]}"; do
    eq "repo_from_gh_url agrees on [$_v]" "$(_rfg "$KB_JQ_REPO_FROM_GH_URL" "$_v")" "$(_rfg "$_rfg_prc" "$_v")"
done
eq "witness: the corpus holds a URL that yields a repo and one that yields none" "acme/widget|null" \
   "$(_rfg "$KB_JQ_REPO_FROM_GH_URL" '"https://github.com/acme/widget/tree/main"' | jq -r .)|$(_rfg "$KB_JQ_REPO_FROM_GH_URL" '"https://github.com/acme/widget"')"
echo "== control: a standalone copy that drops a segment is caught by both comparisons =="
_rfg_mut="${_rfg_prc/|tree|blob/|tree}"
eq "control: the mutation applied" "false" "$([[ "$_rfg_mut" == "$_rfg_prc" ]] && echo true || echo false)"
eq "control: the line-for-line comparison reds on it" "false" \
   "$([[ "$(printf '%s\n' "$KB_JQ_REPO_FROM_GH_URL" | _rfg_strip)" == "$_rfg_mut" ]] && echo true || echo false)"
eq "control: …and so does the corpus, on a /blob/ URL" "false" \
   "$([[ "$(_rfg "$KB_JQ_REPO_FROM_GH_URL" '"https://github.com/acme/widget/blob/main/x.md"')" == "$(_rfg "$_rfg_mut" '"https://github.com/acme/widget/blob/main/x.md"')" ]] && echo true || echo false)"
unset -f _rfg _rfg_strip
unset _rfg_prc _rfg_mut _rfg_corpus _v

# ═══════════════════════ 5b — `pr_url_ref`: promote ↔ KB_JQ_PR_URL_REF ═══════════════════════
#
# Which pull request a pr_url NAMES (agent-webhook-bridge DL-429): promote-released-cards reads it
# as `def pr_url_ref:` to decide what a release promotes, and `kbcard` asks the lib's
# `KB_JQ_PR_URL_REF` whether a write leaves a pr_number that no pr_url names. A second reading here
# once accepted `…/PULL/179` as naming PR 179 while promote read the same card as bare. Same hold
# as § 5: the texts are identical line for line, and both copies are driven over one corpus.
echo "== pr_url_ref: the lib constant IS the standalone's def, line for line =="
_pur_strip() { sed 's/^[[:space:]]*//'; }
_pur_prc="$(awk '/^[[:space:]]*def pr_url_ref:/ {on=1} on {print} on && /^[[:space:]]*end;[[:space:]]*$/ {exit}' "$PRC" | _pur_strip)"
eq "witness: the lib defines KB_JQ_PR_URL_REF" "false" "$([[ -z "${KB_JQ_PR_URL_REF:-}" ]] && echo true || echo false)"
eq "witness: the extraction found the def's head and its close" "true|true" \
   "$(has 'def pr_url_ref:' "$_pur_prc")|$([[ "${_pur_prc##*$'\n'}" == "end;" ]] && echo true || echo false)"
eq "⭐ the standalone's def IS KB_JQ_PR_URL_REF, line for line" \
   "$(printf '%s\n' "$KB_JQ_PR_URL_REF" | _pur_strip)" "$_pur_prc"
echo "== pr_url_ref: both copies agree over one corpus, and it reads what the rule says =="
# _pur <def-text> <json-value> — the def's answer for one pr_url value, `null` when none.
_pur() { jq -cn --argjson v "$2" "$KB_JQ_REF_CANON$KB_JQ_REPO_FROM_GH_URL$1"' $v | pr_url_ref'; }
# <json-value>|<expected answer>. THE RULE (card#10736, the pair of bridge card#10735): the number
# is read from the SAME match that gives the repo — the value's first `github.com/<owner>/<repo>
# (.git)?/<segment>/`, which is repo_from_gh_url's match — and only when that segment is a
# lower-case `pull` followed by digits. So a `/pull/<N>` past it (under /tree/, /blob/,
# /issues/<M>/, or in a later URL) names no pull request. The rows marked `# was` classified
# differently before card#10736, and the comment gives the old answer; every other row is unchanged.
_pur_rows=(
    '"https://github.com/acme/widget/pull/179"|{"repo":"acme/widget","n":"179"}'
    '"https://GitHub.com/Acme/Widget.git/pull/0179"|{"repo":"Acme/Widget","n":"179"}'
    '"https://github.com/acme/widget/pull/179/files"|{"repo":"acme/widget","n":"179"}'
    '"https://github.com/acme/widget/pull/179#discussion_r1"|{"repo":"acme/widget","n":"179"}'
    '"http://www.github.com/acme/widget/pull/179"|{"repo":"acme/widget","n":"179"}'
    '"https://github.com/acme/widget/PULL/179"|null'
    '"https://github.com/acme/widget/Pull/179"|null'
    '"https://github.com/acme/widget/pull/0"|null'
    '"https://github.com/acme/widget/pull/"|null'
    '"https://github.com/acme/widget/issues/179"|null'
    '"https://github.com/acme/widget/commit/179"|null'
    '"https://example.com/acme/widget/pull/179"|null'
    '"https://github.com/acme/widget/tree/main/pull/179"|null'                                  # was acme/widget#179
    '"https://github.com/acme/widget/blob/main/pull/179"|null'                                  # was acme/widget#179
    '"https://github.com/acme/widget/issues/5/pull/179"|null'                                   # was acme/widget#179
    '"https://github.com/a/x/issues/5 https://github.com/b/y/pull/179"|null'                    # was a/x#179
    '"https://github.com/acme/widget/issues/179 https://github.com/other/repo/pull/179"|null'   # was acme/widget#179
    '"https://github.com/acme/widget/commit/abc https://github.com/acme/widget/pull/179"|null'  # was acme/widget#179
    '"https://github.com/acme/widget/pull/5 https://github.com/b/y/pull/179"|{"repo":"acme/widget","n":"5"}'
    '"https://example.com/x/pull/9 https://github.com/acme/widget/pull/179"|{"repo":"acme/widget","n":"179"}'  # was acme/widget#9
    '"https://github.com/acme/widget/commit/abc/pull/179"|null'                                  # was acme/widget#179
    '"https://github.com/acme/widget/pull/abc https://github.com/acme/widget/pull/5"|null'      # was acme/widget#5
    '"https://github.com/o/r/PULL/1 https://github.com/o/r/pull/5"|null'                        # was o/r#5
    '"https://github.com/o/r/Pull/5 https://github.com/o/r/pull/6"|null'                        # was o/r#6
    '"https://github.com/o/pull/7 https://github.com/a/b/pull/9"|{"repo":"a/b","n":"9"}'        # was a/b#7
    '"https://github.com/pull/12/pull/9"|{"repo":"pull/12","n":"9"}'                            # was pull/12#12
    '"https://github.com/Acme/Widget.GIT/pull/179"|{"repo":"Acme/Widget","n":"179"}'
    '"https://github.com/acme/widget/pull/000"|null'
    '""|null' '42|null' 'null|null'
    '{"u":"https://github.com/acme/widget/pull/179"}|null')
for _row in "${_pur_rows[@]}"; do
    _v="${_row%|*}"; _want="${_row##*|}"
    eq "pr_url_ref agrees on [$_v]" "$(_pur "$KB_JQ_PR_URL_REF" "$_v")" "$(_pur "$_pur_prc" "$_v")"
    eq "⭐ pr_url_ref reads [$_v] as $_want" "$_want" "$(_pur "$KB_JQ_PR_URL_REF" "$_v")"
done
echo "== pr_url_ref: both copies answer every vector of the bridge's published corpus =="
# THE BRIDGE OWNS THIS RULE (agent-webhook-bridge DL-431, App\Bridge\Writeback\PrUrlRef::parse) and
# publishes its behavioural corpus; the file below is a BYTE-IDENTICAL VENDORED COPY of it:
#     from    PupFuzz/agent-webhook-bridge : docs/pr-url-ref-parity-corpus.json
#     copied  at bridge commit 86fb506b1ceecfca73adceedd859735f20288bf0 (bridge PR #810, card#10735)
#     blob    the git blob id pinned in _pur_vblob below, which is that commit's blob of the file
# ⛔ THIS REPO CANNOT DETECT DRIFT FROM THE BRIDGE'S COPY. Nothing here reads the bridge repo: a
# vector the bridge adds or changes reaches this check only when the file is re-vendored (copy it
# byte for byte, update the commit above and _pur_vblob). The blob pin below catches a LOCAL edit
# of the vendored copy — never a bridge-side change. The bridge, for its part, states that it does
# not check this repo's copy of the rule (the file's own `not_checked_by_this_repo`).
# HOW A VECTOR MAPS ONTO pr_url_ref (the file's `how_the_far_end_runs_this`, in this rule's shape):
# pr_url_ref answers `{repo, n}` only when the value names a pull request, and null otherwise — the
# `.../pull/0` placeholder included — with the repo AS DERIVED (callers canonicalize) and n a
# string. So: expect null, or names_pr false → pr_url_ref null; names_pr true → {repo, n} with the
# repo compared lower-cased and n == expect.number. A names_pr-false vector's repo (the placeholder
# names a repo) is held against repo_from_gh_url, the repo that URL yields (§ 5's pair).
_pur_vfile="$HERE/vendored/agent-webhook-bridge/pr-url-ref-parity-corpus.json"
_pur_vblob=92d5b472028e52d7eb94f09e52048fe0f7f0df5c
_need -r "$_pur_vfile"
# _pur_vec <def-text> <corpus-file> — one TSV line per vector: <index> <ok|DRIFT> <input> <want> <got>.
_pur_vec() {
    jq -rn --slurpfile c "$2" "$KB_JQ_REF_CANON$KB_JQ_REPO_FROM_GH_URL$1"'
        $c[0].vectors | to_entries[] | .key as $i | .value as $v
        | (if $v.expect == null or ($v.expect.names_pr | not) then null
           else {repo: $v.expect.repo, n: ($v.expect.number | tostring)} end) as $want
        | ($v.input | pr_url_ref | if . == null then null else {repo: (.repo | ascii_downcase), n: .n} end) as $got
        | (if $v.expect != null and ($v.expect.names_pr | not)
           then ($v.input | repo_from_gh_url | if . == null then null else ascii_downcase end) == $v.expect.repo
           else true end) as $repo_ok
        | [$i, (if $got == $want and $repo_ok then "ok" else "DRIFT" end), ($v.input | tojson), ($want | tojson), ($got | tojson)]
        | @tsv'
}
_pur_vn="$(jq '.vectors | length' "$_pur_vfile")"
eq "witness: the vendored copy is the pinned blob (a local edit reds here; a bridge change cannot)" \
   "$_pur_vblob" "$(git hash-object "$_pur_vfile")"
eq "witness: the corpus holds vectors of all three kinds (expect null, names_pr true, names_pr false)" "true|true|true" \
   "$(jq -r '[any(.vectors[]; .expect == null), any(.vectors[]; .expect.names_pr == true), any(.vectors[]; .expect.names_pr == false)] | map(tostring) | join("|")' "$_pur_vfile")"
for _impl in lib standalone; do
    if [[ "$_impl" == lib ]]; then _def="$KB_JQ_PR_URL_REF"; else _def="$_pur_prc"; fi
    _out="$(_pur_vec "$_def" "$_pur_vfile")"
    eq "witness ($_impl): every vector was driven" "$_pur_vn" "$(printf '%s\n' "$_out" | command grep -c .)"
    eq "⭐ $_impl pr_url_ref answers every bridge vector (DRIFT lines listed)" "" \
       "$(printf '%s\n' "$_out" | awk -F'\t' '$2 != "ok"')"
done
# CONTROL: the same run over a copy with ONE vector's expected number moved reds for both copies.
jq '(first(.vectors[] | select(.expect.names_pr == true)) | .expect.number) |= . + 1' "$_pur_vfile" > "$TMP/pur-corpus-moved.json"
eq "control: the moved copy differs from the vendored one" "false" \
   "$(cmp -s "$_pur_vfile" "$TMP/pur-corpus-moved.json" && echo true || echo false)"
for _impl in lib standalone; do
    if [[ "$_impl" == lib ]]; then _def="$KB_JQ_PR_URL_REF"; else _def="$_pur_prc"; fi
    eq "control ($_impl): one moved vector is ONE drift line" "1" \
       "$(_pur_vec "$_def" "$TMP/pur-corpus-moved.json" | awk -F'\t' '$2 != "ok"' | command grep -c .)"
done
echo "== pr_url_ref: its match IS repo_from_gh_url's match, plus the digit run =="
# The number belongs to the repo's URL only because the two captures find the SAME first match.
# That holds while pr_url_ref's pattern is repo_from_gh_url's with the segment named and the digit
# run appended — a guard, because repo_from_gh_url is a separate pinned pair (§ 5) that can move
# alone, and a segment added to one pattern and not the other moves the first match.
_pur_re() { printf '%s\n' "$1" | sed -n 's/.*capture("\(github[^"]*\)".*/\1/p'; }
_pur_head() { _pur_re "$1" | sed 's/?<s>//; s/(?<n>\[0-9\]\*)$//'; }
eq "witness: both patterns were extracted" "true|true" \
   "$([[ -n "$(_pur_re "$KB_JQ_REPO_FROM_GH_URL")" ]] && echo true)|$([[ -n "$(_pur_re "$KB_JQ_PR_URL_REF")" ]] && echo true)"
eq "⭐ pr_url_ref's pattern is repo_from_gh_url's, segment named and digits appended" \
   "$(_pur_re "$KB_JQ_REPO_FROM_GH_URL")" "$(_pur_head "$KB_JQ_PR_URL_REF")"
eq "control: repo_from_gh_url losing a segment reds that guard" "false" \
   "$([[ "$(_pur_re "${KB_JQ_REPO_FROM_GH_URL/|tree|blob/|tree}")" == "$(_pur_head "$KB_JQ_PR_URL_REF")" ]] && echo true || echo false)"
eq "control: …and so does pr_url_ref losing one" "false" \
   "$([[ "$(_pur_re "$KB_JQ_REPO_FROM_GH_URL")" == "$(_pur_head "${KB_JQ_PR_URL_REF/|tree|blob/|tree}")" ]] && echo true || echo false)"
echo "== control: a standalone copy read case-insensitively is caught by both comparisons =="
_pur_cs='$m.s != "pull"' _pur_ci='($m.s | ascii_downcase) != "pull"'
_pur_mut="${_pur_prc/"$_pur_cs"/"$_pur_ci"}"
eq "control: the mutation applied" "false" "$([[ "$_pur_mut" == "$_pur_prc" ]] && echo true || echo false)"
eq "control: the line-for-line comparison reds on it" "false" \
   "$([[ "$(printf '%s\n' "$KB_JQ_PR_URL_REF" | _pur_strip)" == "$_pur_mut" ]] && echo true || echo false)"
eq "control: …and so does the corpus, on a /PULL/ URL" "false" \
   "$([[ "$(_pur "$KB_JQ_PR_URL_REF" '"https://github.com/acme/widget/PULL/179"')" == "$(_pur "$_pur_mut" '"https://github.com/acme/widget/PULL/179"')" ]] && echo true || echo false)"
echo "== control: the pre-card#10736 reading (/pull/<N> anywhere) reds the expected-answer rows =="
# The def as it stood: repo from repo_from_gh_url, number from the first `/pull/<N>` anywhere.
_pur_old='def pr_url_ref:
    if type != "string" then null
    else (repo_from_gh_url) as $r
      | ((capture("/pull/(?<n>[0-9]+)") // {n: ""}).n | norm) as $n
      | if $r == null or $n == "" or $n == "0" then null else {repo: $r, n: $n} end
    end;'
_pur_red=0
for _row in "${_pur_rows[@]}"; do
    [[ "$(_pur "$_pur_old" "${_row%|*}")" == "${_row##*|}" ]] || _pur_red=$((_pur_red + 1))
done
eq "control: the old def reads the two-URL value as a/x#179" '{"repo":"a/x","n":"179"}' \
   "$(_pur "$_pur_old" '"https://github.com/a/x/issues/5 https://github.com/b/y/pull/179"')"
eq "control: …and misses at least one expected-answer row" "true" "$( (( _pur_red > 0 )) && echo true || echo false)"
eq "⭐ kb_pr_named_verdict reads the pair through it: …/PULL/179 beside pr_number 179 is refused" "refuse" \
   "$(kb_pr_named_verdict '{}' '{"pr_number":179,"pr_url":"https://github.com/acme/widget/PULL/179"}' | cut -f1)"
eq "⭐ …and so is the two-URL value beside pr_number 179" "refuse" \
   "$(kb_pr_named_verdict '{}' '{"pr_number":179,"pr_url":"https://github.com/a/x/issues/5 https://github.com/b/y/pull/179"}' | cut -f1)"
unset -f _pur _pur_strip _pur_re _pur_head _pur_vec
unset _pur_prc _pur_mut _pur_old _pur_red _pur_cs _pur_ci _pur_rows _row _v _want _pur_vfile _pur_vblob _pur_vn _impl _def _out

# ═══════════ 6 — the WRITE-OUTCOME contract: promote ↔ `bin/kbcard` (card#9938) ═══════════
#
# THE PAIR HERE IS STANDALONE ↔ ANOTHER BIN, not standalone ↔ the lib, and that is the same
# defect class rather than a wider one: `bin/kbcard` owns this fleet's write-outcome ladder
# (card#8556 — APPLIED / NOT APPLIED AND KNOWN / UNVERIFIED, with `KBC_RC_UNVERIFIED` as the
# third outcome's rc), `bin/promote-released-cards` must not source the lib and cannot exec
# kbcard either (it is vendored ALONE), and card#9938 made it adopt that ladder rather than mint
# a second vocabulary for one outcome. So the value and the rule exist twice, and a second
# expression of one rule drifts. Two things are held: the RC, as a value, and the STAGE RULING.
echo "== the UNVERIFIED rc: promote's RC_UNVERIFIED IS kbcard's KBC_RC_UNVERIFIED =="
KBC="$ROOT/bin/kbcard"
_need -r "$KBC"
# Each side is the ASSIGNMENT LINE grepped out of the shipped file, asserted to match exactly
# once: an extraction that found none would compare two empties and pass forever.
_rcu_prc="$(command grep -cE '^RC_UNVERIFIED=' "$PRC")"
_rcu_kbc="$(command grep -cE '^KBC_RC_UNVERIFIED=' "$KBC")"
eq "witness: promote defines RC_UNVERIFIED exactly once"     "1" "$_rcu_prc"
eq "witness: kbcard defines KBC_RC_UNVERIFIED exactly once"  "1" "$_rcu_kbc"
# ⚠ THE TWO SIDES ARE READ DIFFERENTLY, AND THE ASYMMETRY IS THE POINT — it is the same asymmetry
# this whole file exists for. The STANDALONE's value must be a self-contained LITERAL: it may
# source nothing, so a copy whose rc came from a name it cannot resolve would be a broken tool,
# and reading it by text is what can SEE that. The OWNER's value need not be a literal and is
# already moving — card#10029 points `KBC_RC_UNVERIFIED` at the lib's `KB_RC_UNVERIFIED`, which
# is the right direction (one owner for the value, not two literals) — so the owner's side is
# RESOLVED, through the lib this file has already sourced. A `cut -d= -f2` reader would compare
# promote's `3` against the STRING `"$KB_RC_UNVERIFIED"` and red on a pair that AGREES.
# _rcu_value <file> <var> — the shipped assignment's VALUE. An indirection that resolves to
# nothing yields the empty string, so it reds rather than passing: `set +u` is what turns the
# unbound name into an observable empty instead of an abort with no row printed.
_rcu_value() {
    local line
    line="$(command grep -E "^$2=" "$1")" || return 0
    ( set +u; eval "$line"; printf '%s' "${!2-}" ) 2>/dev/null || true
}
_rcu_prc="$(command grep -E '^RC_UNVERIFIED=' "$PRC" | cut -d= -f2)"
_rcu_kbc="$(_rcu_value "$KBC" KBC_RC_UNVERIFIED)"
eq "⭐ the two are the SAME rc (a caller testing for 3 tests one thing)" "$_rcu_kbc" "$_rcu_prc"
eq "…and it is 3, the rc both files' contracts document" "3" "$_rcu_kbc"
eq "⭐ the STANDALONE's rc is a LITERAL — it can resolve no name it does not define" "true" \
   "$([[ "$_rcu_prc" =~ ^[0-9]+$ ]] && echo true || echo false)"
echo "== control: a renumbering on EITHER side is caught — both directions, not one =="
# ON THE REAL FILES, through the SAME extractions the rows above use — not on literals typed
# here. A control that compared two hand-written strings would leave the readers that PRODUCE
# the population untested, which is the half that silently stops finding anything after a rename.
# BOTH sides are mutated: a guard driven from one end only reds when the COPY drifts and passes
# in silence when the OWNER moves — which is the direction this pair is actually moving.
sed 's/^RC_UNVERIFIED=3/RC_UNVERIFIED=4/' "$PRC" > "$TMP/prc-renumbered"
_rcu_mut="$(command grep -E '^RC_UNVERIFIED=' "$TMP/prc-renumbered" | cut -d= -f2)"
eq "control: the COPY-side mutation applied, and the extraction SEES it" "4" "$_rcu_mut"
eq "control: …so the equality above reds on that copy" "false" \
   "$([[ "$_rcu_kbc" == "$_rcu_mut" ]] && echo true || echo false)"
sed 's/^KBC_RC_UNVERIFIED=.*/KBC_RC_UNVERIFIED=4/' "$KBC" > "$TMP/kbc-renumbered"
_rcu_mut="$(_rcu_value "$TMP/kbc-renumbered" KBC_RC_UNVERIFIED)"
eq "control: the OWNER-side mutation applied, and the resolver SEES it" "4" "$_rcu_mut"
eq "control: …so the equality above reds when the OWNER moves and the copy does not" "false" \
   "$([[ "$_rcu_mut" == "$_rcu_prc" ]] && echo true || echo false)"
eq "control: …while the shipped pair still agrees"  "true" \
   "$([[ "$_rcu_kbc" == "$_rcu_prc" ]] && echo true || echo false)"
echo "== control: the resolver FOLLOWS an indirection, and reds when it resolves to nothing =="
# The spelling card#10029 gives the owner's line, driven here against a probe name of this
# file's own rather than against `KB_RC_UNVERIFIED` — that constant is not on this branch yet,
# and a row expecting it would assert which PR landed first instead of what the reader does.
# What is proven is the READER's property, which is what has to hold either way round.
printf 'KBC_RC_UNVERIFIED="$_RCU_PROBE"\n' > "$TMP/kbc-indirect"
eq "control: …=\"\$NAME\" with NAME=3 resolves to 3, so the pair still agrees after card#10029" "3" \
   "$(_RCU_PROBE=3; _rcu_value "$TMP/kbc-indirect" KBC_RC_UNVERIFIED)"
eq "control: …and an indirection pointing at NOTHING resolves EMPTY, which reds" "" \
   "$(_rcu_value "$TMP/kbc-indirect" KBC_RC_UNVERIFIED)"
unset -f _rcu_value

echo "== stage_verdict vs _kbc_confirm_stage: one ruling, two runtimes, one corpus =="
# promote answers a WORD, kbcard answers an EXIT STATUS and a message; the compared property is
# the DECISION, exactly as § 1 compares `require_value`'s verdict across two exit policies.
_adopt_fn "$PRC" card_stage
_adopt_fn "$PRC" stage_verdict
_adopt_fn "$KBC" _kbc_confirm_stage
# _sv <card GET body> <stage asked for> — promote's ruling, driven THROUGH ITS OWN READER. The
# body goes in, not a stage: `card_stage` is the half that decides a JSON string and a JSON
# number are the same stage (`tostring`), and a corpus that handed `stage_verdict` a
# pre-extracted value would be testing a normalisation this file had restated rather than the
# one the tool ships.
_sv() { stage_verdict 0 "$(card_stage "$1")" "$2"; }
# _card <workflow_stage_id as JSON, or the word ABSENT> — a single-card GET body.
_card() {
    if [[ "$1" == ABSENT ]]; then printf '{"data":{"id":1,"name":"c"}}'
    else jq -cn --argjson s "$1" '{data:{id:1,name:"c",workflow_stage_id:$s}}'; fi
}
# _cs <workflow_stage_id as JSON, or the word ABSENT> <stage asked for> — kbcard's ruling on the
# server's write echo. Its own callers hand it `_kbc_write_echo`'s projection, which is an object
# carrying `workflow_stage_id`; ABSENT builds the object without the key.
_cs() {
    local echo_json rc=0
    if [[ "$1" == ABSENT ]]; then echo_json='{"id":1,"name":"c"}'
    else echo_json="$(jq -cn --argjson s "$1" '{id:1,name:"c",workflow_stage_id:$s}')"; fi
    _kbc_confirm_stage move "card 1" "$echo_json" "$2" 2>/dev/null || rc=$?
    [[ "$rc" -eq 0 ]] && printf 'applied' || printf 'not-applied'
}
# THE CORPUS. `85` vs `"85"` is not padding: the board stores the integer this tool sent, and a
# JSON STRING spelling of it is the same stage — both sides normalise with `tostring` / jq -r,
# and a copy that dropped it would report a landed move as a HARD FAILURE.
for _row in '85|85|applied' '84|85|not-applied' '0|85|not-applied' '1085|85|not-applied' '"85"|85|applied' '"84"|85|not-applied'; do
    IFS='|' read -r _got _want _expect <<<"$_row"
    eq "both rule [$_got vs $_want] $_expect (promote)" "$_expect" "$(_sv "$(_card "$_got")" "$_want")"
    eq "…and kbcard agrees"                             "$_expect" "$(_cs "$_got" "$_want")"
done
# THE ONE DECLARED DIVERGENCE, asserted in BOTH directions so neither side can quietly move onto
# the other. A card whose stage CANNOT BE READ is `unverified` in promote and HARD FAILURE in
# kbcard, and neither is wrong because the two are ruling on different subjects: kbcard rules on
# the server's own write ECHO, whose readability `_kbc_write_echo` has already established (an
# unreadable echo is ITS rc 3, one layer up), so a missing stage in a body it has accepted is a
# real disagreement; promote rules on an INDEPENDENT GET that nothing upstream vouched for, so
# "no stage could be read" is nothing measured — and nothing measured may not be reported as a
# measurement. A third divergence would land in the agreement rows above and red there.
eq "declared divergence: promote calls an UNREADABLE stage unverified" "unverified" "$(_sv "$(_card ABSENT)" 85)"
eq "…and the same for a body no card can be read out of at all" "unverified" "$(_sv '<html>502</html>' 85)"
eq "declared divergence: kbcard calls an ABSENT echo stage NOT APPLIED" "not-applied" "$(_cs ABSENT 85)"
eq "…and promote's OTHER unverified arm: the read itself was not a measurement" "unverified" \
   "$(stage_verdict 1 85 85)"
echo "== control: a promote copy that reported from the status class is caught by the corpus =="
# The pre-card#9938 tool, reduced to this rule: it never read anything back, so every write that
# answered 2xx was `applied`. Both divergent rows must invert.
_sv_naive() { printf 'applied'; }
eq "control: the naive rule calls a card that did NOT move applied" "applied" "$(_sv_naive "$(_card 84)" 85)"
eq "control: …where the shipped rule does not"                      "not-applied" "$(_sv "$(_card 84)" 85)"
eq "control: the naive rule calls an UNREADABLE read applied too"   "applied" "$(_sv_naive '<html>502</html>' 85)"
eq "control: …where the shipped rule refuses to rule"               "unverified" "$(_sv '<html>502</html>' 85)"
unset -f card_stage stage_verdict _kbc_confirm_stage _sv _cs _card _sv_naive
unset _rcu_prc _rcu_kbc _rcu_mut _row _got _want _expect KBC

# ═══════════════════ 7 — the two renderers of an UNTRUSTED response body ═════════════════════
#
# THE PAIR: `resp_detail` in promote-released-cards and `resp_excerpt` in next-dl. Each is its
# tool's ONE renderer of bytes a third party chose — next-dl's arm is designed around a gateway's
# SSO or WAF page — onto an operator's terminal, and each carries the SAME ruling in two halves:
# mask this call's bearer token BEFORE the length bound (cutting first splits the credential, so
# the literal match finds nothing and the prefix prints — card#7500), and emit no byte a terminal
# would ACT on.
#
# ⛔ WHY IT IS REGISTERED, and it is not a hypothetical (card#10230, round 7). The mask was ported
# from `resp_detail` into `resp_excerpt` and the SCRUB WAS NOT, under a comment at the new site
# claiming "same ruling, same reasoning and the same instrument as the co-vendored sibling". The
# comment made the divergence invisible: `resp_excerpt` bounded with `tr '\n' ' '`, which converts
# LF and nothing else, so ESC, BEL and CR all reached the terminal — the CR letting a third
# party's page overwrite the refusal line being read, on the one message that says a DL may already
# have been spent. Exactly this file's founding shape: a fix landing in one copy, missing its twin,
# green suite, held by prose.
#
# ⚑ THE LIB NOW OWNS A THIRD COPY, AND next-dl HAS NOT MOVED ONTO IT. Until card#9777 the hoist
# was declined here: promote-released-cards may NOT source the lib (§ Stage D, above), so a lib
# primitive would only have relocated one text, for a single lib-side caller. card#9777 gave the
# chain its lib-sourcing callers — every stage write through `kb_stage_write` renders its refusal
# with the lib's `kb_render_refusal`, a mirror of `resp_detail` pinned in § 8 below — so next-dl's
# `resp_excerpt` is now the one lib-sourcing copy that could call the lib instead of carrying the
# chain. It was NOT migrated in that card: its envelope, its cut and its withheld-on-an-unreadable-
# token-file outcome all differ by design, so the move is a change to what next-dl prints and is
# its own change. Until it lands, this block is what holds that copy to the other two. (Its MASK
# stage does call the lib — kb_mask_token, over kb_token_file_read's token — since card#9777's
# review round; what is mirrored here is the scrub chain alone.)
#
# WHAT IS COMPARED, and what is not: the DECISION about the body — which bytes survive the render
# and in what form. The tools' envelopes differ by design (`resp_detail` prints `HTTP <status>,
# server said: …` and cuts at its own named constant; `resp_excerpt` is interpolated mid-sentence
# and cuts at next-dl's), so the corpus is kept under both bounds and the envelope is stripped.
echo "== the untrusted-body renderers: promote's resp_detail ↔ next-dl's resp_excerpt =="
# `resp_excerpt` is nested INSIDE dl_sequence_call, so `_fn_src` (which anchors at column zero)
# cannot reach it; extracted and de-indented here, the way § 5 de-indents promote's embedded jq
# def. Both halves of the extraction are witnessed before anything is compared.
RX_SRC="$(sed -n '/^    resp_excerpt() {/,/^    }/p' "$NDL" | sed 's/^    //')"
eq "witness: next-dl's resp_excerpt was extracted with a body" "true|true" \
   "$(has 'resp_excerpt() {' "$RX_SRC")|$(has 'head -c' "$RX_SRC")"
eq "witness: the extraction stopped at the function (it did not swallow the caller)" "false" \
   "$(has 'spent_refusal' "$RX_SRC")"
eval "$RX_SRC"
_adopt_fn "$PRC" resp_detail

MP_TOKEN='parity-stub-token'
token_file="$TMP/mp-token"; printf '%s' "$MP_TOKEN" > "$token_file"
API_ERR_FILE="$TMP/mp-detail"
API_ERR_EXCERPT_MAX="$(sed -n 's/^API_ERR_EXCERPT_MAX=\([0-9][0-9]*\)$/\1/p' "$PRC")"
TOKEN="$MP_TOKEN"
eq "witness: promote's bound was read out of the bin" "false" \
   "$([[ -z "$API_ERR_EXCERPT_MAX" ]] && echo true || echo false)"

# THE NORMALISATION ITSELF (card#9777): promote reads $KANBAN_WRITEBACK_TOKEN raw and cannot
# source the lib to get kb_token_file_read's strip, so it carries its own copy of the same
# trailing-whitespace rule — the read-time step BEFORE either renderer below ever runs, and a
# renderer-agreement corpus that only ever fed a clean token (as the one below does) cannot see
# it drift. Extracted by grepping the LITERAL line out of the shipped bin, not retyped here, so
# a hand-edit that changes the character class or the expansion shape is what this pins.
PRC_STRIP_LINE="$(sed -n '/^TOKEN="\${RAW_TOKEN%/p' "$PRC")"
eq "witness: promote's TOKEN-strip line was found in the bin" "false" \
   "$([[ -z "$PRC_STRIP_LINE" ]] && echo true || echo false)"
_prc_strip() { local RAW_TOKEN="$1" TOKEN; eval "$PRC_STRIP_LINE"; printf '%s' "$TOKEN"; }
_lib_strip() { local _v; kb_token_file_read _v <(printf '%s' "$1"); printf '%s' "$_v"; }
STRIP_LABELS=('no trailing whitespace' 'trailing LF'      'trailing CR'
              'trailing CRLF'          'trailing space'   'trailing tab'
              'trailing VT then FF'    'interior whitespace untouched')
STRIP_INPUTS=('sekrit123'              $'sekrit123\n'     $'sekrit123\r'
              $'sekrit123\r\n'         'sekrit123 '       $'sekrit123\t'
              $'sekrit123\v\f'         $'sek rit\t123')
eq "witness: every strip-corpus row has a label" "${#STRIP_LABELS[@]}" "${#STRIP_INPUTS[@]}"
for _i in "${!STRIP_INPUTS[@]}"; do
    eq "strip normalisation parity [${STRIP_LABELS[$_i]}]" \
       "$(_lib_strip "${STRIP_INPUTS[$_i]}")" "$(_prc_strip "${STRIP_INPUTS[$_i]}")"
done
unset _i PRC_STRIP_LINE

# ⛔ CONTROL — a promote copy with the strip line DELETED must diverge from the lib on the
# trailing-CR row, or the loop above is comparing two copies that both dropped it. CR, not LF:
# the `$(…)` this row's own comparison captures through strips a trailing LF on EITHER side
# regardless of what the mutant returned, which would make the row pass vacuously; a trailing
# CR survives a command substitution, so it is CR that actually exercises the mutant's miss.
# Driven on the planted mutant used nowhere else in this run.
_prc_strip_mutant() { local RAW_TOKEN="$1"; printf '%s' "$RAW_TOKEN"; }
eq "CONTROL: a promote copy without the strip line DOES diverge" "false" \
   "$([[ "$(_lib_strip $'sekrit123\r')" == "$(_prc_strip_mutant $'sekrit123\r')" ]] && echo true || echo false)"

# _mp_detail <body> — resp_detail's verdict on the BODY, envelope removed. Its no-body sentence
# and resp_excerpt's empty string are the same decision said two ways; mapping one onto the other
# is the envelope difference being stripped, not a disagreement being hidden.
_mp_detail() {
    local out
    printf '%s\n%s' 200 "$1" > "$API_ERR_FILE"
    out="$(resp_detail)"
    case "$out" in
        'HTTP 200, and the server sent no body') printf '' ;;
        *) printf '%s' "${out#HTTP 200, server said: }" ;;
    esac
}
_mp_ctl() {   # <text> — how many C0-or-DEL bytes are in it, i.e. bytes a terminal ACTS on
    LC_ALL=C printf '%s' "$1" | tr -dc '\000-\037\177' | wc -c | tr -d ' '
}
# ⚠ NUL IS ABSENT FROM THE CORPUS AND CANNOT BE ADDED: a shell variable cannot carry one, so no
# row here can feed it. Both chains delete `\000` and neither tool can receive a NUL through the
# path it actually reads (a `$(…)` capture of curl's output), so this is a bound of the harness
# rather than an untested class of the guard — stated, not claimed away.
MP_LABELS=('plain JSON'                       'an ESC CSI erase-line sequence'
           'a BEL'                            'a CR the far page would overwrite with'
           'an LF'                            'a TAB'
           'VT and FF'                        'SO and US'
           'DEL'                              'a run of spaces'
           'leading and trailing space'       'the wire token echoed back'
           'UTF-8 that must survive intact'   'the empty body'
           'a raw C1 CSI byte')
MP_BODIES=('{"message":"nope"}'               "$(printf '{"m":"blocked\033[2Kfree"}')"
           "$(printf '{"m":"ring\007ing"}')"  "$(printf 'refusing\rnext-dl: minted DL-9999')"
           "$(printf 'line one\nline two')"   "$(printf 'a\tb')"
           "$(printf 'a\013b\014c')"          "$(printf 'a\016b\037c')"
           "$(printf 'a\177b')"               'a     b'
           '  a b  '                          '{"Authorization":"Bearer parity-stub-token"}'
           'café €50'                         ''
           "$(printf 'a\233b')")
eq "witness: every corpus row has a label" "${#MP_LABELS[@]}" "${#MP_BODIES[@]}"
# ⛔ THE CORPUS MUST FIT UNDER BOTH CUTS, or a long row would be truncated at two different
# places and red as a DISAGREEMENT when the two chains actually agree. Both bounds are READ OUT OF
# their bins rather than written here, and the check is the comparison — no figure lives in this
# file to go stale when either tool re-tunes its own.
_mp_ndl_max="$(sed -n 's/.*head -c \([0-9][0-9]*\).*/\1/p' "$NDL" | head -1)"
eq "witness: next-dl's cut was read out of the bin" "false" \
   "$([[ -z "$_mp_ndl_max" ]] && echo true || echo false)"
_mp_longest=0
for _i in "${!MP_BODIES[@]}"; do
    _n="$(LC_ALL=C printf '%s' "${MP_BODIES[$_i]}" | wc -c | tr -d ' ')"
    [[ "$_n" -gt "$_mp_longest" ]] && _mp_longest="$_n"
done
eq "witness: every corpus row fits under BOTH cuts, so no row compares two truncations" "true" \
   "$([[ "$_mp_longest" -lt "$_mp_ndl_max" && "$_mp_longest" -lt "$API_ERR_EXCERPT_MAX" ]] && echo true || echo false)"
# ⭐ VACUITY: the rows below assert that no control byte SURVIVES, which an all-plain corpus would
# satisfy having measured nothing. The corpus itself must carry them going in — and the DERIVED
# count is printed rather than asserted against a written floor, which would stop being re-derived
# the day a row moved. What is ASSERTED is the property: the corpus feeds some, and every row that
# feeds one is a row the render had to CHANGE.
_mp_in=0; _mp_rows=0
for _i in "${!MP_BODIES[@]}"; do
    _n="$(_mp_ctl "${MP_BODIES[$_i]}")"
    _mp_in=$(( _mp_in + _n )); [[ "$_n" -gt 0 ]] && _mp_rows=$(( _mp_rows + 1 ))
done
printf '   corpus: %s rows, %s of them carrying %s control byte(s) in\n' \
    "${#MP_BODIES[@]}" "$_mp_rows" "$_mp_in"
eq "witness: the corpus really feeds control bytes IN" "true" \
   "$([[ "$_mp_in" -gt 0 && "$_mp_rows" -gt 0 ]] && echo true || echo false)"

for _i in "${!MP_BODIES[@]}"; do
    _l="${MP_LABELS[$_i]}"; _b="${MP_BODIES[$_i]}"
    _x="$(resp_excerpt "$_b")"; _d="$(_mp_detail "$_b")"
    eq "the two renderers agree on [$_l]"                  "$_d" "$_x"
    eq "…and NEITHER emits a byte a terminal acts on [$_l]" "0|0" "$(_mp_ctl "$_d")|$(_mp_ctl "$_x")"
    # ⭐ PER-ROW VACUITY, derived from the row itself: a row that carried a control byte in must
    # come out DIFFERENT. Without it a renderer that returned its input unchanged would satisfy the
    # agreement row, and the "0 out" row only for the plain rows.
    if [[ "$(_mp_ctl "$_b")" -gt 0 ]]; then
        eq "…and the render actually CHANGED that body [$_l]" "false" \
           "$([[ "$_x" == "$_b" ]] && echo true || echo false)"
    fi
done
unset _i _l _b _x _d _n _mp_in _mp_rows _mp_longest _mp_ndl_max
# THE DECLARED DIVERGENCE FROM "no control bytes", asserted as a VALUE on BOTH copies rather than
# skipped: the scrub is C0-and-DEL, so C1 (0x80-0x9F, 0x9B CSI included) SURVIVES. `resp_detail`'s
# own comment owns the reason — `\200-\237` overlaps UTF-8's continuation-byte range, so deleting
# it would turn legitimate localised text into mojibake — and it is not restated here. If a copy
# ever starts stripping C1, this reds and that reason gets re-argued instead of silently lost.
_mp_c1() { LC_ALL=C printf '%s' "$1" | tr -dc '\233' | wc -c | tr -d ' '; }
_mp_c1_body="$(printf 'a\233b')"
eq "declared limit: the C1 CSI byte survives promote's copy"   "1" "$(_mp_c1 "$(_mp_detail "$_mp_c1_body")")"
eq "declared limit: …and next-dl's, identically"               "1" "$(_mp_c1 "$(resp_excerpt "$_mp_c1_body")")"
eq "declared limit: …and the UTF-8 row is untouched by both"   "true|true" \
   "$(has 'café €50' "$(_mp_detail 'café €50')")|$(has 'café €50' "$(resp_excerpt 'café €50')")"

# ⭐ THE CONTROL, DRIVEN FROM BOTH ENDS. Every row above would pass just as well for two copies
# that had BOTH lost the scrub — which is the state this branch shipped in round 6 minus one copy.
# So each copy has its `tr -d` stage cut out in turn and must be seen to leak.
echo "== control: cutting the scrub stage out of EITHER copy is caught =="
_mp_esc="$(printf '{"m":"blocked\033[2Kfree"}')"
eq "control: the ESC row does carry control bytes going in" "true" \
   "$([[ "$(_mp_ctl "$_mp_esc")" -gt 0 ]] && echo true || echo false)"
# The needle is the STAGE, not the string `tr -d`: promote's copy quotes a `tr -d` invocation in
# its own comment (the mojibake measurement), so the bare string is present with or without the
# pipeline stage and an assertion on it reports the comment.
_mp_needle='tr -d '\''\000-'
RX_NAIVE="$(printf '%s\n' "$RX_SRC" | sed "s/| tr -d '[^']*' //; s/^resp_excerpt()/rx_naive()/")"
eq "control: the scrub stage really came out of next-dl's copy" "true|false|true" \
   "$(has "$_mp_needle" "$RX_SRC")|$(has "$_mp_needle" "$RX_NAIVE")|$(has 'rx_naive() {' "$RX_NAIVE")"
eval "$RX_NAIVE"
eq "control: unscrubbed, next-dl's copy LEAKS the ESC sequence" "true" \
   "$([[ "$(_mp_ctl "$(rx_naive "$_mp_esc")")" -gt 0 ]] && echo true || echo false)"
eq "control: …while the shipped copy emits none"                "0" "$(_mp_ctl "$(resp_excerpt "$_mp_esc")")"
RD_SRC="$(_fn_src "$PRC" resp_detail)"
RD_NAIVE="$(printf '%s\n' "$RD_SRC" | sed "s/| tr -d '[^']*' //; s/^resp_detail()/rd_naive()/")"
eq "control: the scrub stage really came out of promote's copy" "true|false|true" \
   "$(has "$_mp_needle" "$RD_SRC")|$(has "$_mp_needle" "$RD_NAIVE")|$(has 'rd_naive() {' "$RD_NAIVE")"
eval "$RD_NAIVE"
printf '%s\n%s' 200 "$_mp_esc" > "$API_ERR_FILE"
eq "control: unscrubbed, promote's copy LEAKS it too"           "true" \
   "$([[ "$(_mp_ctl "$(rd_naive)")" -gt 0 ]] && echo true || echo false)"
eq "control: …while the shipped copy emits none"                "0" "$(_mp_ctl "$(_mp_detail "$_mp_esc")")"
unset -f resp_excerpt resp_detail rx_naive rd_naive _mp_detail _mp_ctl _mp_c1
unset RX_SRC RX_NAIVE RD_SRC RD_NAIVE _mp_needle MP_LABELS MP_BODIES MP_TOKEN _mp_esc _mp_c1_body token_file

# ═══════════ 8 — the REFUSAL render: promote's resp_detail ↔ the lib's kb_render_refusal ═══════════
#
# THE PAIR (card#9777). Every stage write in the toolkit renders a board's refusal through ONE of
# these two: every mover that calls `kb_stage_write` (grep bin/ for it) through
# `kb_render_refusal`, and promote-released-cards — which may not source the lib
# — through its own `resp_detail` (card#9301, the original). The product claim is that a refusal
# reaches the operator in the SAME shape whichever mover hit it, so unlike § 7 NOTHING is stripped:
# the envelope (`HTTP <s>, server said: …`, the no-body sentence, the truncation marker), the mask,
# the scrub and the cut are all compared, byte for byte.
#
# WHAT IT DOES NOT COVER: promote's `000` arm (a request that never completed). kb_stage_write
# never renders one — kb_api reports its own `curl failed` there — so the lib copy has no such arm
# and no row here feeds `000`.
echo "== the refusal render: the lib's kb_render_refusal IS promote's resp_detail, envelope and all =="
_adopt_fn "$PRC" resp_detail
API_ERR_FILE="$TMP/rr-detail"
API_ERR_EXCERPT_MAX="$(sed -n 's/^API_ERR_EXCERPT_MAX=\([0-9][0-9]*\)$/\1/p' "$PRC")"
_rr_lib_max="$(sed -n 's/^KB_API_ERR_EXCERPT_MAX=\([0-9][0-9]*\)$/\1/p' "$LIB")"
eq "witness: both bounds were read out of their files" "false|false" \
   "$([[ -z "$API_ERR_EXCERPT_MAX" ]] && echo true || echo false)|$([[ -z "$_rr_lib_max" ]] && echo true || echo false)"
eq "the two bounds are ONE number" "$API_ERR_EXCERPT_MAX" "$_rr_lib_max"
eq "…and the sourced lib carries the value its file declares" "$_rr_lib_max" "$KB_API_ERR_EXCERPT_MAX"

RR_TOKEN='kbwb_RRRRSSSSTTTTUUUU0123456789'
TOKEN="$RR_TOKEN"; KB_TOKEN="$RR_TOKEN"
_rr_promote() { printf '%s\n%s' "$1" "$2" > "$API_ERR_FILE"; resp_detail; }
# A body one byte per position over the bound, and one whose token STRADDLES the cut — the row
# the mask-before-cut ordering exists for. Both are built from the bound read above, so neither
# row goes stale when the bound is re-tuned.
_rr_long="$(printf '%*s' "$(( API_ERR_EXCERPT_MAX + 50 ))" '' | tr ' ' 'x')"
_rr_straddle="$(printf '%*s' "$(( API_ERR_EXCERPT_MAX - 10 ))" '' | tr ' ' 'y')$RR_TOKEN tail"
RR_LABELS=('a leg-refusal JSON body'          'the same body with the wire token echoed back'
           'no body at all'                   'a multi-line HTML error page'
           'an ESC sequence and a CR'         'UTF-8 that must survive intact'
           'a body over the bound'            'a token straddling the cut')
RR_STATUS=(422 422 403 502 409 422 422 422)
RR_BODIES=('{"error":"parent has open legs","open_legs":[123,456]}'
           "{\"error\":\"parent has open legs\",\"open_legs\":[123,456],\"debug\":{\"authorization\":\"Bearer $RR_TOKEN\"}}"
           ''
           "$(printf '<html>\n<body>\n<h1>502 Bad Gateway</h1>\n</body>\n</html>')"
           "$(printf '{"m":"blocked\033[2Kfree\rkbcard: moved"}')"
           '{"message":"Étape refusée — café €50"}'
           "$_rr_long"
           "$_rr_straddle")
eq "witness: every corpus row has a label and a status" "${#RR_LABELS[@]}|${#RR_LABELS[@]}" \
   "${#RR_BODIES[@]}|${#RR_STATUS[@]}"
for _i in "${!RR_BODIES[@]}"; do
    _l="${RR_LABELS[$_i]}"
    _p="$(_rr_promote "${RR_STATUS[$_i]}" "${RR_BODIES[$_i]}")"
    _k="$(kb_render_refusal "${RR_STATUS[$_i]}" "${RR_BODIES[$_i]}")"
    eq "the two renders are byte-identical [$_l]" "$_p" "$_k"
    eq "…and neither carries the token [$_l]" "false|false" "$(has "$RR_TOKEN" "$_p")|$(has "$RR_TOKEN" "$_k")"
done
# ⭐ VACUITY: identical outputs that both dropped the body would pass every row above. So the
# property each row exists for is asserted on the lib copy directly.
eq "the leg refusal is quoted with its status" \
   'HTTP 422, server said: {"error":"parent has open legs","open_legs":[123,456]}' \
   "$(kb_render_refusal 422 "${RR_BODIES[0]}")"
eq "the echoed token is MASKED, not dropped with its field" "true" \
   "$(has '"authorization":"Bearer ***"' "$(kb_render_refusal 422 "${RR_BODIES[1]}")")"
eq "no body is said as such" 'HTTP 403, and the server sent no body' "$(kb_render_refusal 403 '')"
eq "an over-bound body is cut and says so" "true" \
   "$(has "[truncated at $API_ERR_EXCERPT_MAX bytes]" "$(kb_render_refusal 422 "$_rr_long")")"
eq "no prefix of a straddling token survives the cut" "false" \
   "$(has "${RR_TOKEN:0:8}" "$(kb_render_refusal 422 "$_rr_straddle")")"

# ⭐ THE CONTROL, from the lib's end: its mask stage cut out must make a token row DISAGREE with
# promote's and leak — otherwise the rows above are comparing two copies that could both have lost it.
echo "== control: a lib copy without its mask, or with its own bound, is caught =="
RR_SRC="$(_fn_src "$LIB" kb_render_refusal)"
RR_NAIVE="$(printf '%s\n' "$RR_SRC" | sed '/KB_TOKEN/d; s/^kb_render_refusal()/rr_naive()/')"
eq "control: the mask line really came out" "true|false|true" \
   "$(has 'KB_TOKEN' "$RR_SRC")|$(has 'KB_TOKEN' "$RR_NAIVE")|$(has 'rr_naive() {' "$RR_NAIVE")"
eval "$RR_NAIVE"
eq "control: unmasked, the lib copy LEAKS the token" "true" \
   "$(has "$RR_TOKEN" "$(rr_naive 422 "${RR_BODIES[1]}")")"
eq "control: …and the comparison sees the disagreement" "false" \
   "$([[ "$(rr_naive 422 "${RR_BODIES[1]}")" == "$(_rr_promote 422 "${RR_BODIES[1]}")" ]] && echo true || echo false)"
_rr_saved="$KB_API_ERR_EXCERPT_MAX"; KB_API_ERR_EXCERPT_MAX=$(( _rr_saved - 1 ))
eq "control: a lib bound one byte off disagrees on the over-bound row" "false" \
   "$([[ "$(kb_render_refusal 422 "$_rr_long")" == "$(_rr_promote 422 "$_rr_long")" ]] && echo true || echo false)"
KB_API_ERR_EXCERPT_MAX="$_rr_saved"
unset -f resp_detail rr_naive _rr_promote
unset RR_SRC RR_NAIVE RR_LABELS RR_STATUS RR_BODIES RR_TOKEN _rr_long _rr_straddle _rr_saved _rr_lib_max _i _l _p _k
unset TOKEN KB_TOKEN

# ═══════════════════════ 9 — the terminal:partial tag: promote ↔ KB_PARTIAL_TAG (card#10140) ═════
#
# `kbcard move/patch --partial` write the lib's KB_PARTIAL_TAG; `promote-released-cards` holds a
# card carrying its own PARTIAL_TAG, because it may not source the lib. If the two differ, every
# card marked partial is released as verified, and nothing else reds. The standalone side is read
# as TEXT (it must be a self-contained literal); the lib side is the value this file sourced.
echo "== terminal:partial: promote's PARTIAL_TAG IS the lib's KB_PARTIAL_TAG =="
_pt_read() { sed -n "s/^PARTIAL_TAG='\(.*\)'\$/\1/p" "$1"; }
eq "witness: promote assigns PARTIAL_TAG exactly once, as a literal" "1" "$(command grep -cE "^PARTIAL_TAG='[^'\$]+'\$" "$PRC")"
eq "witness: the lib's value is not empty"           "true" "$([[ -n "${KB_PARTIAL_TAG:-}" ]] && echo true || echo false)"
eq "⭐ the two spellings are the SAME tag"            "$KB_PARTIAL_TAG" "$(_pt_read "$PRC")"
echo "== control: a respelling on EITHER side is caught =="
sed "s/^PARTIAL_TAG='terminal:partial'/PARTIAL_TAG='terminal-partial'/" "$PRC" > "$TMP/prc-partial"
eq "control: the COPY-side mutation applied, and the reader SEES it" "terminal-partial" "$(_pt_read "$TMP/prc-partial")"
eq "control: …so the equality reds on that copy"     "false" \
   "$([[ "$KB_PARTIAL_TAG" == "$(_pt_read "$TMP/prc-partial")" ]] && echo true || echo false)"
# The lib is the file this section SOURCED, so the owner-side control re-evaluates the mutated
# lib's own assignment line — the line `source` ran — rather than re-sourcing the whole lib.
sed "s/^KB_PARTIAL_TAG=.*/KB_PARTIAL_TAG='terminal:Partial'/" "$LIB" > "$TMP/lib-partial"
_pt_owner="$( eval "$(command grep -E '^KB_PARTIAL_TAG=' "$TMP/lib-partial")"; printf '%s' "$KB_PARTIAL_TAG" )"
eq "control: the OWNER-side mutation applied"        "terminal:Partial" "$_pt_owner"
eq "control: …so the equality reds when the OWNER moves" "false" \
   "$([[ "$_pt_owner" == "$(_pt_read "$PRC")" ]] && echo true || echo false)"
unset _pt_owner
unset -f _pt_read

_summary "mirror-pair-parity-selftest"
