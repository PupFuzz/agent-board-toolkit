#!/usr/bin/env bash
# mirror-pair-parity-selftest.sh — the extract-and-exercise pin for the `bin/` mirror pairs that
# were held by a `keep the two in sync` COMMENT and by nothing else (card#8529).
#
# WHAT A MIRROR PAIR IS HERE. `bin/` ships four tools that are vendored STANDALONE into consumer
# repos and must not source `bin/_kb-board-lib.sh` — `promote-released-cards`,
# `release-artifacts-check`, `release-pr-body`, `release-tag-check`. Each therefore carries its
# own inline copy of a guard the lib also owns. That duplication is not an oversight to remove:
# `docs/CONSOLIDATION-PLAN.md` § Stage D DECIDED (2026-08-01) against making them source the lib,
# and chose GUARDED duplication instead. This file is some of that guard.
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
_need -r "$LIB"
_need -x "$PRC"
_need -x "$RPB"

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

# ═══════════════════════ 4 — the owner-tag clear: promote ↔ the lib's tag rules ═══════════════
#
# promote-released-cards removes the seat owner tags from a card it releases, and may not source
# the lib, so it carries its own copies of the tag rules the lib's `kb_owner_tag_write clear`
# goes through: which tag list a card read carries (`kb_card_tags`), the list without its owner
# tags (`kb_owner_strip`), and the owner tags named (`kb_owner_list`). A disagreement is a tag wipe
# (a read one copy calls unreadable and the other calls `[]`) or a tag the two clear differently.
echo "== owner tags: promote's owner_card_tags / owner_strip / owner_list agree with the lib, row by row =="
_adopt_fn "$PRC" owner_card_tags
_adopt_fn "$PRC" owner_strip
_adopt_fn "$PRC" owner_list
for _b in '{"data":{"tags":["a","owner:p/s"]}}' '{"data":{"id":1}}' '{"data":{"tags":null}}' '{"data":{"tags":[]}}' \
          '{"ok":true}' '{"data":null}' '{"data":[]}' '{"data":{"tags":false}}' '{"data":{"tags":{"0":"owner:p/s"}}}' \
          '{"data":{"tags":"owner:p/s"}}' '<html>' ''; do
    eq "card tags agree on [$_b]" "$(kb_card_tags "$_b")" "$(owner_card_tags "$_b")"
done
for _t in '["a","owner:p/s","b","owner:q/t"]' '["a","b"]' '["ownership","owner:p/s"]' '["owner:p/s"]' '[]' '["x-owner:p/s","owner:p/s"]' \
          '["Owner:p/s"]' '["owner:"]' '[1,"owner:p/s",null]'; do
    eq "strip agrees on [$_t]" "$(kb_owner_strip "$_t")" "$(owner_strip "$_t")"
    eq "list agrees on [$_t]"  "$(kb_owner_list "$_t")"  "$(owner_list "$_t")"
done
# A witness that the corpus exercises both arms of each rule — rows that were all empty on both
# sides would agree about nothing.
eq "witness: a readable list and an unreadable read are both in the corpus" "true|true" \
   "$([[ -n "$(owner_card_tags '{"data":{"tags":[]}}')" ]] && echo true)|$([[ -z "$(owner_card_tags '{"ok":true}')" ]] && echo true)"
eq "witness: a strip that writes and one that does not are both in the corpus" "true|true" \
   "$([[ -n "$(owner_strip '["owner:p/s"]')" ]] && echo true)|$([[ -z "$(owner_strip '["a"]')" ]] && echo true)"
echo "== control: a promote copy that reads a card with the naive default is caught =="
_naive="$(_fn_src "$PRC" owner_card_tags | sed 's/(if has("tags") and .tags != null then .tags else \[\] end) | select(type == "array")/(.tags \/\/ [])/')"
eq "control: the mutation applied" "false" "$(has 'has("tags")' "$_naive")"
eval "$_naive"
eq "control: the naive copy now DISAGREES with the lib on a non-list tags value" "false" \
   "$([[ "$(kb_card_tags '{"data":{"tags":false}}')" == "$(owner_card_tags '{"data":{"tags":false}}')" ]] && echo true || echo false)"
_adopt_fn "$PRC" owner_card_tags
unset -f owner_card_tags owner_strip owner_list
unset _b _t _naive

# ═══════════════════════ 5 — `repo_from_gh_url`: promote ↔ KB_JQ_REPO_FROM_GH_URL ══════════════
#
# The board attributes a card (by-ref `source`) from a GitHub URL through one rule, which
# promote-released-cards mirrors in jq as `def repo_from_gh_url:`. `kbcard patch` and `adopt-to-dl`
# ask the SAME question — does a URL written without its number still attribute the card to a
# repo? (card#9846) — through the lib's `KB_JQ_REPO_FROM_GH_URL`, which is that def's text. The
# standalone must not source the lib, so the def exists twice; what holds them together is THIS:
# the two texts are identical line for line (indentation aside — the standalone's copy sits
# indented inside a larger program), and both are driven over one corpus so an extraction that
# found the wrong lines cannot pass by comparing two empties.
echo "== repo_from_gh_url: the lib constant IS the standalone's def, line for line =="
_rfg_strip() { sed 's/^[[:space:]]*//'; }
# _prc_jq_def <file> <name> — the TEXT of one `def <name>: … end;` jq definition in a standalone,
# indentation stripped (the standalone's defs sit indented inside a larger program). Extracted at
# top level, like `_fn_src` above and for the same reason: a rename must end the run at a witness
# rather than compare two empties. § 6 below is the second caller.
_prc_jq_def() {
    awk -v n="$2" '$0 ~ "^[[:space:]]*def " n ":" {on=1} on {print} on && /^[[:space:]]*end;[[:space:]]*$/ {exit}' "$1" \
        | _rfg_strip
}
_rfg_prc="$(_prc_jq_def "$PRC" repo_from_gh_url)"
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
unset -f _rfg
unset _rfg_prc _rfg_mut _rfg_corpus _v

# ═══════════════════ 6 — `payload.repo` as the source: promote ↔ KB_JQ_PAYLOAD_REPO_IS_SOURCE ══
#
# The OTHER half of "how a card gets its by-ref source", and the half that outranks § 5: a
# `payload.repo` that is a string containing `/` IS the source, and no URL is consulted at all.
# `promote-released-cards` spells that predicate inline as the first arm of `def derive_source:`;
# `kbcard patch` asks the same question of the card it is about to refuse a write on, so its
# refusal cannot tell an operator the board takes the source from a URL when it does not
# (card#9918), and reaches it through the lib's KB_JQ_PAYLOAD_REPO_IS_SOURCE. Two copies again.
#
# ⚠ WHY THIS BLOCK IS BEHAVIOURAL WHERE § 5 IS LINE-FOR-LINE. The standalone's copy is an ARM of a
# larger def, not a def of its own — there is no text to hold identical. So the two are driven
# instead: each corpus row is a card whose URLs attribute it to acme/widget and whose payload.repo
# is the row, and the question asked of both copies is the one the predicate decides — DID
# payload.repo win? promote answers by running `derive_source` (a source that is not acme/widget
# is payload.repo's), the lib by evaluating its fragment. A row where the two disagree is the
# drift this block exists to red on.
echo "== payload_repo_is_source: promote's derive_source and the lib fragment agree, row by row =="
_ds_canon="$(_prc_jq_def "$PRC" canon_source)"
_ds_rfg="$(_prc_jq_def "$PRC" repo_from_gh_url)"
_ds_derive="$(_prc_jq_def "$PRC" derive_source)"
_ds_prog="$_ds_canon$_ds_rfg$_ds_derive"
eq "witness: all three defs extracted with a body" "true|true|true" \
   "$(has 'ascii_downcase' "$_ds_canon")|$(has 'capture(' "$_ds_rfg")|$(has 'test(' "$_ds_derive")"
eq "witness: the lib defines KB_JQ_PAYLOAD_REPO_IS_SOURCE" "false" \
   "$([[ -z "${KB_JQ_PAYLOAD_REPO_IS_SOURCE:-}" ]] && echo true || echo false)"
# _ds_card <repo-json-value|-> — a card whose pr_url attributes it to acme/widget, carrying that
# payload.repo (or no repo key at all for `-`). The URL half is held constant so the ONLY thing
# that can move derive_source's answer is the predicate under test.
_ds_card() {
    if [[ "$1" == - ]]; then jq -cn '{payload:{pr_url:"https://github.com/acme/widget/pull/1"}}'
    else jq -cn --argjson r "$1" '{payload:{repo:$r, pr_url:"https://github.com/acme/widget/pull/1"}}'; fi
}
# promote's verdict: derive_source answering anything but the URL's repo means payload.repo won.
_ds_promote() { # <card-json>
    local src; src="$(jq -r "$_ds_prog"'derive_source // "«null»"' <<<"$1" 2>/dev/null)" || src='«error»'
    [[ "$src" == "acme/widget" ]] && printf 'url' || printf 'payload'
}
# the lib's verdict, through the fragment exactly as kbcard calls it.
_ds_lib() { # <frag> <card-json>
    jq -e "$1"'payload_repo_is_source' >/dev/null 2>&1 <<<"$2" && printf 'payload' || printf 'url'
}
# The CONTROL BEFORE THE ROWS: with no payload.repo key the URL must win, or every row below would
# read `url` for a reason that has nothing to do with the predicate.
eq "control: no payload.repo at all → promote derives the URL's repo" "url" "$(_ds_promote "$(_ds_card -)")"
eq "control: …and the lib agrees there is no payload.repo source"     "url" "$(_ds_lib "$KB_JQ_PAYLOAD_REPO_IS_SOURCE" "$(_ds_card -)")"
# ⛔ NO ROW MAY CANONICALISE TO acme/widget — the oracle reads such a row as `url` whatever the
# predicate said. Asserted below rather than left to care.
_ds_corpus=('null' '""' '", "' '"norepo"' '"a/b"' '" a/b "' '"A/B"' '"/"' '"a/b/c"'
    '"https://github.com/x/y/pull/1"' '5' 'true' '["a/b"]' '{"r":"a/b"}')
_ds_collide=0
for _v in "${_ds_corpus[@]}"; do
    [[ "$(jq -rn --argjson v "$_v" "$_ds_canon"'($v | canon_source) // "«null»"')" == "acme/widget" ]] \
        && _ds_collide=$((_ds_collide + 1))
done
eq "witness: no corpus row canonicalises to the URL's own repo" "0" "$_ds_collide"
_ds_payload=0 _ds_url=0
for _v in "${_ds_corpus[@]}"; do
    _c="$(_ds_card "$_v")"
    _want="$(_ds_promote "$_c")"
    [[ "$_want" == payload ]] && _ds_payload=$((_ds_payload + 1)) || _ds_url=$((_ds_url + 1))
    eq "payload.repo [$_v]: the lib fragment agrees with derive_source ($_want)" \
       "$_want" "$(_ds_lib "$KB_JQ_PAYLOAD_REPO_IS_SOURCE" "$_c")"
done
# A corpus that only ever answered one way would agree with a fragment stuck on that answer.
eq "witness: the corpus drives BOTH answers" "true|true" \
   "$([[ "$_ds_payload" -gt 0 ]] && echo true)|$([[ "$_ds_url" -gt 0 ]] && echo true)"
echo "== control: a lib fragment that tightens the predicate is caught by the same comparison =="
# `[^/]*/[^/]*` requires EXACTLY one slash — the same tightening that would silently stop
# `kbcard patch` naming payload.repo on a card promote attributes to it.
_ds_mut="${KB_JQ_PAYLOAD_REPO_IS_SOURCE/test(\"\/\")/test(\"\\\\A[^\/]*\/[^\/]*\\\\z\")}"
eq "control: the mutation changed the fragment" "false" \
   "$([[ "$_ds_mut" == "$KB_JQ_PAYLOAD_REPO_IS_SOURCE" ]] && echo true || echo false)"
_ds_dis=0
for _v in "${_ds_corpus[@]}"; do
    _c="$(_ds_card "$_v")"
    [[ "$(_ds_lib "$_ds_mut" "$_c")" == "$(_ds_promote "$_c")" ]] || _ds_dis=$((_ds_dis + 1))
done
eq "control: the tightened fragment DISAGREES with derive_source (a/b/c and the URL row)" "2" "$_ds_dis"
unset -f _ds_card _ds_promote _ds_lib _prc_jq_def _rfg_strip
unset _ds_canon _ds_rfg _ds_derive _ds_prog _ds_corpus _ds_mut _ds_dis _ds_collide _ds_payload _ds_url _c _want _v

_summary "mirror-pair-parity-selftest"
