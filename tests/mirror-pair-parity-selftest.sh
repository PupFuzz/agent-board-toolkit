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

_summary "mirror-pair-parity-selftest"
