#!/usr/bin/env bash
# decision-log-selftest.sh — network-free checks for `bin/_decision-log.py`: the `## DL-NNN`
# grammar, the `check` predicate's exit contract (0 / 2 / 5 / 6 / 7 / 8), and the import contract
# a consumer repo path-loads (card#12338; ported from agent-webhook-bridge's
# `bin/test_decision_log.py`, card#7157 / card#9936).
#
# EVERY CASE IS A PLANTED DEFECT OR A PINNED NEGATIVE. The predicate is vacuous on a healthy log —
# no duplicate exists — so a case that merely ran it would witness nothing. Each refusal is paired
# with the control that differs from it only in the defect, so a refusal firing on the entry
# rather than on the defect would red the control.
#
# THE GRAMMAR HARDENING (card#12338) is §§ H1–H3, one per hole found in review:
#   H1 a heading after an UNCLOSED code fence used to vanish from the scan at rc 0 — now rc 8;
#   H2 a heading indented by 1–3 spaces (still an ATX heading in CommonMark) was invisible;
#   H3 a suffixed heading (`## DL-0344a`) matched neither the entry nor the placeholder grammar
#      and was counted by nothing at rc 0 — now any `## DL-` heading the entry grammar rejects
#      is a heading with no well-formed number, rc 7.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
TOOL="$HERE/../bin/_decision-log.py"
_need -r "$TOOL"
command -v python3 >/dev/null || { echo "selftest: python3 not found" >&2; exit 1; }
_mktmp_scratch

# log <entry>... — a decision log with one H2 per entry, plus prose citing another DL (noise the
# grammar must not count).
log() {
  printf '# Decision log\n\n> Append-only.\n\n'
  local e
  for e in "$@"; do printf '## DL-%s — an entry\n\nMirrors kanban-board DL-999.\n\n' "$e"; done
}

# chk <args...> — run `check`; sets RC, OUT (stdout), ERR (stderr).
chk() {
  RC=0
  python3 "$TOOL" check "$@" >"$TMP/out" 2>"$TMP/err" || RC=$?
  OUT="$(cat "$TMP/out")"; ERR="$(cat "$TMP/err")"
}

w() { printf '%s' "$2" > "$TMP/$1"; printf '%s' "$TMP/$1"; }

echo "== rc 5: the log at head uses one number twice =="
chk --head "$(w head.md "$(log 293 294 294)")"
eq "a repeated number is rc 5" 5 "$RC"
eq "…naming the number" true "$(has 'DL-294 is used TWICE' "$ERR")"
chk --head "$(w head.md "$(log 288 0288)")"
eq "zero-stripping: DL-288 and DL-0288 collide (rc 5)" 5 "$RC"
eq "…named as DL-288" true "$(has 'DL-288 is used TWICE' "$ERR")"
chk --head "$(w head.md "$(log 293 294)")"
eq "CONTROL: the same log without the repeat is rc 0" 0 "$RC"
eq "…and states its population" true "$(has '2 of 2 `## DL-` header lines counted, 0 skipped' "$OUT")"

echo "== rc 6: an added number is already at the live target tip =="
chk --head "$(w head.md "$(log 293 294)")" --base "$(w base.md "$(log 293)")" --target "$(w target.md "$(log 293 294)")"
eq "an added number already on target is rc 6" 6 "$RC"
eq "…naming it" true "$(has 'DL-294 (added at' "$ERR")"
eq "…as ALREADY IN USE" true "$(has 'ALREADY IN USE' "$ERR")"
chk --head "$(w head.md "$(log 293 294 295)")" --base "$(w base.md "$(log 293)")" --target "$(w target.md "$(log 293 294 295)")"
eq "every colliding number is named, not just the first" true "$(has 'DL-295 (added at' "$ERR")"
chk --head "$(w head.md "$(log 293 295)")" --base "$(w base.md "$(log 293)")" --target "$(w target.md "$(log 293 294)")"
eq "CONTROL: a genuinely new number is rc 0" 0 "$RC"
eq "…and names what it added" true "$(has 'adds 1 DL entries (DL-295)' "$OUT")"
chk --head "$(w head.md "$(log 293)")" --base "$(w base.md "$(log 293)")" --target "$(w target.md "$(log 293 294)")"
eq "CONTROL: a change minting nothing is rc 0" 0 "$RC"
chk --head "$(w head.md "$(log 293 296)")" --base "$(w base.md "$(log 293)")" --target "$(w target.md "$(log 293)")"
eq "CONTROL: an entry carried over from base is not a collision" 0 "$RC"
chk --head "$(w head.md "$(log 293 295)")" --base "$(w base.md "$(log 293)")" --target "$(w target.md "$(log 293 296)")"
eq "CONTROL: a number below the target max is not refused for being low" 0 "$RC"

echo "== rc 7: an added heading carries no number =="
chk --head "$(w head.md "$(log 293; printf '## DL-TBD — a draft\n')")" --base "$(w base.md "$(log 293)")" --target "$(w target.md "$(log 293)")"
eq "an added placeholder is rc 7" 7 "$RC"
eq "…naming the line" true "$(has '## DL-TBD — a draft' "$ERR")"
chk --head "$(w head.md "$(log 293; printf '## DL-TBD — a draft\n')")"
eq "a placeholder is refused on a head-only run too" 7 "$RC"
chk --head "$(w head.md "$(log 293; printf '## DL-414 — a draft\n')")" --base "$(w base.md "$(log 293)")" --target "$(w target.md "$(log 293)")"
eq "CONTROL: the same entry with a number is rc 0" 0 "$RC"
ph=$'## DL-TBD — landed earlier\n\n'
chk --head "$(w head.md "$(log 293 295)"$'\n'"$ph")" --base "$(w base.md "$(log 293)"$'\n'"$ph")" --target "$(w target.md "$(log 293)"$'\n'"$ph")"
eq "an INHERITED placeholder does not red an innocent change" 0 "$RC"
eq "…and is stated in the population" true "$(has '1 carrying no well-formed number' "$OUT")"
chk --head "$(w head.md "$(log 293)"$'\n'"$ph$ph")" --base "$(w base.md "$(log 293)"$'\n'"$ph")" --target "$(w target.md "$(log 293)"$'\n'"$ph")"
eq "a SECOND copy of an inherited placeholder is an addition (counted, not set-tested)" 7 "$RC"

echo "== grammar: what is and is not an entry =="
chk --head "$(w head.md $'# Decision log\n## DL-100 — real\n### DL-100 — an H3 is not an entry\nProse citing DL-100.\n')"
eq "only H2 headings count (an H3 / prose repeat is rc 0)" 0 "$RC"
chk --head "$(w head.md $'## DL-200 — real\n\n```markdown\n## DL-200 — what a header looks like\n```\n')"
eq "a heading inside a CLOSED fence is an example, not an entry" 0 "$RC"
eq "…and the skip is stated" true "$(has 'inside a code fence and were NOT counted' "$ERR")"
eq "…and in the population" true "$(has '1 of 2 `## DL-` header lines counted, 1 skipped' "$OUT")"
chk --head "$(w head.md $'~~~\n## DL-300 — inside\n```\n## DL-300 — still inside\n~~~\n## DL-302 — out\n')"
eq "a tilde fence closes only on tildes" 0 "$RC"
chk --head "$(w head.md $'```\n## DL-TBD — what a draft looks like\n```\n')"
eq "a placeholder inside a closed fence is an example" 0 "$RC"

echo "== H1: an UNCLOSED fence is a finding (rc 8), not a silent truncation =="
unclosed=$'# Decision log\n\n## DL-100 — a\n\n```\nnever closed\n\n## DL-100 — b\n'
chk --head "$(w head.md "$unclosed")"
eq "a head log ending inside a fence is rc 8" 8 "$RC"
eq "…naming the line the fence opened on" true "$(has 'opens a code fence at line 5 that is never closed' "$ERR")"
chk --head "$(w head.md "$(log 293 294)")" --base "$(w base.md $'## DL-293 — a\n\n```\n## DL-294 — hidden\n')" --target "$(w target.md "$(log 293)")"
eq "an unclosed fence in the BASE log is rc 8 (it would invent mints)" 8 "$RC"
eq "…naming the base log" true "$(has 'the base log' "$ERR")"
chk --head "$(w head.md "$(log 293 294)")" --base "$(w base.md "$(log 293)")" --target "$(w target.md $'## DL-293 — a\n\n~~~\n## DL-294 — hidden\n')"
eq "an unclosed fence in the TARGET log is rc 8 (it would hide the collision)" 8 "$RC"
chk --head "$(w head.md $'# Decision log\n\n## DL-100 — a\n\n```\nclosed\n```\n\n## DL-101 — b\n')"
eq "CONTROL: the same log with the fence closed is rc 0" 0 "$RC"

echo "== H2: an ATX heading indented by 1–3 spaces is an entry =="
for ind in ' ' '  ' '   '; do
  chk --head "$(w head.md "$(log 342)"$'\n'"${ind}## DL-342 — indented $(( ${#ind} ))"$'\n')"
  eq "a ${#ind}-space-indented repeat of DL-342 is rc 5" 5 "$RC"
done
chk --head "$(w head.md "$(log 342)"$'\n'"   ## DL-TBD — indented placeholder"$'\n')"
eq "an indented placeholder is rc 7" 7 "$RC"
chk --head "$(w head.md "$(log 342)"$'\n    ## DL-342 — four spaces is an indented code block\n')"
eq "CONTROL: a 4-space-indented line is code, not a heading (rc 0)" 0 "$RC"
chk --head "$(w head.md "$(log 342)"$'\n\t## DL-342 — a tab is four columns\n')"
eq "CONTROL: a tab-indented line is code, not a heading (rc 0)" 0 "$RC"

echo "== H3: a DL heading the entry grammar rejects carries no well-formed number (rc 7) =="
for bad in 'DL-0344a' 'DL-0344_x' 'DL-' 'DL-x344'; do
  chk --head "$(w head.md "$(log 343)"$'\n'"## ${bad} — suffixed"$'\n')" --base "$(w base.md "$(log 343)")" --target "$(w target.md "$(log 343)")"
  eq "\`## ${bad}\` added is rc 7" 7 "$RC"
  eq "…naming it" true "$(has "## ${bad} — suffixed" "$ERR")"
done
chk --head "$(w head.md "$(log 343)"$'\n'"## DL-0344a — suffixed"$'\n')"
eq "\`## DL-0344a\` on a head-only run is rc 7" 7 "$RC"
chk --head "$(w head.md "$(log 343)"$'\n'"## DL-0344 — clean"$'\n')" --base "$(w base.md "$(log 343)")" --target "$(w target.md "$(log 343)")"
eq "CONTROL: \`## DL-0344 — clean\` is a counted entry, rc 0" 0 "$RC"
eq "…counted as DL-344" true "$(has '(DL-344)' "$OUT")"
chk --head "$(w head.md "$(log 343 344)"$'\n'"## DL-0344.1 — dotted"$'\n')"
eq "\`## DL-0344.1\` is DL-344 (a word boundary follows the digits) and collides, rc 5" 5 "$RC"

echo "== usage: half a pairing, and an unreadable log =="
chk --head "$(w head.md "$(log 293 294)")" --base "$(w base.md "$(log 293)")"
eq "--base without --target is rc 2" 2 "$RC"
eq "…saying why" true "$(has 'given together or not at all' "$ERR")"
chk --head "$(w head.md "$(log 293)")" --base "$TMP/absent.md" --target "$TMP/head.md"
eq "an unreadable log is rc 2, not an empty log" 2 "$RC"
eq "…saying it cannot read it" true "$(has 'cannot read' "$ERR")"

echo "== import contract (the names a consumer path-loads) =="
contract="$(python3 - "$TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("decision_log", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
text = "## DL-0100 — a\n```\n## DL-101 — quoted\n```\n## DL-TBD — draft\n  ## DL-0102a — bad\n"
print(m.header_scan(text))
print(m.header_numbers(text))
print(m.header_scan("## DL-1 — a\n```\n## DL-2\n")[3])
PY
)"
eq "header_scan -> (entries, skipped, unnumbered, unclosed_fence)" \
   "([(100, 1)], 1, [('## DL-TBD — draft', 5), ('## DL-0102a — bad', 6)], None)" "$(sed -n 1p <<<"$contract")"
eq "header_numbers -> entries" "[(100, 1)]" "$(sed -n 2p <<<"$contract")"
eq "unclosed_fence -> the line the open fence started on" "2" "$(sed -n 3p <<<"$contract")"

_summary "decision-log-selftest"
