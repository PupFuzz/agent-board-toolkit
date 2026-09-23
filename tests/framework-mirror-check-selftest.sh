#!/usr/bin/env bash
# framework-mirror-check-selftest.sh — drive `tests/framework-mirror-check.sh` over fixtures.
#
# WHY A FIXTURE AND NOT THE REAL ARTIFACT. The subject reads an artifact that lives OUTSIDE this
# repo — a framework clone or an installed coord plugin — and neither exists on a CI runner. So the
# subject itself is not a CI check (its own header says so, and it is deliberately not named
# `*-selftest.sh`). What CI CAN hold is the subject's JUDGEMENT, and that is what this drives: a
# scratch toolkit repo with real tags, and scratch mirror directories built to each verdict.
#
# ⛔ BOTH ARMS, AND THE REVERSE ONE IS THE POINT. A DECLARE+CHECK fix is routinely verified in one
# direction only — "what is declared exists" — which passes just as happily when the check has gone
# blind. Every red arm below is reached by MUTATING THE MIRRORED SIDE (the far end of the seam)
# away from the declaration and watching the subject go red, never by removing the declaration. The
# IN-STEP arm is the PRESENCE WITNESS that makes those reds mean something: it proves the subject
# can still say yes over this same fixture, so a red is discrimination and not a stuck verdict.
#
# WHAT A GREEN RUN PROVES, and no more: that the subject reaches each verdict over a fixture built
# to it, and that an unmeasurable run is rc 2 rather than rc 0. Nothing here is a claim about the
# real framework mirror — only running the subject against a real artifact says anything about that.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

ROOT="$(cd "$HERE/.." && pwd)"
SUBJECT="$ROOT/tests/framework-mirror-check.sh"
_need -r "$SUBJECT"
_mktmp_scratch

# ── a scratch TOOLKIT: a real git repo, two bins, two tags, VERSION at the newer one ──
# v1.0.0 ships both bins stamped '1.0.0'; v1.1.0 re-stamps them and changes promote's body, so the
# two tags differ in content AND stamp — which is what lets STALE and DIVERGED be told apart.
TK="$TMP/toolkit"
mkdir -p "$TK/bin" "$TK/tests"
cp "$SUBJECT" "$TK/tests/framework-mirror-check.sh"

_write_bins() {  # _write_bins <version> <body-marker>
  local v="$1" body="$2" n
  for n in promote-released-cards release-pr-body; do
    printf '#!/usr/bin/env bash\n# %s\nABTK_TOOL_VERSION=%s\necho %s\n' "$n" "'$v'" "$body" > "$TK/bin/$n"
    chmod +x "$TK/bin/$n"
  done
}

git -C "$TK" init -q
git -C "$TK" config user.email t@e.i
git -C "$TK" config user.name t
printf '1.0.0\n' > "$TK/VERSION"
_write_bins 1.0.0 old
git -C "$TK" add -A && git -C "$TK" commit -qm v1
git -C "$TK" tag v1.0.0
printf '1.1.0\n' > "$TK/VERSION"
_write_bins 1.1.0 new
git -C "$TK" add -A && git -C "$TK" commit -qm v2
git -C "$TK" tag v1.1.0

CHECK="$TK/tests/framework-mirror-check.sh"

# _mirror <name> — a scratch INSTALLED-PLUGIN-shaped artifact holding the v1.1.0 bins (in step).
# Every red arm starts from this and mutates the MIRRORED copy.
_mirror() {
  local d="$TMP/$1" n
  mkdir -p "$d/templates/release"
  for n in promote-released-cards release-pr-body; do
    git -C "$TK" show "v1.1.0:bin/$n" > "$d/templates/release/$n"
  done
  printf '%s' "$d"
}
_run() { bash "$CHECK" "$1" 2>&1 || true; }
_rc()  { local rc=0; bash "$CHECK" "$1" >/dev/null 2>&1 || rc=$?; echo "$rc"; }

echo "== PRESENCE WITNESS: an in-step mirror is IN-STEP at rc 0 =="
# Without this the reds below prove nothing — a check that always reds would pass every one.
fx="$(_mirror in-step)"
out="$(_run "$fx")"
eq "promote-released-cards IN-STEP" "true" "$(has 'IN-STEP       promote-released-cards' "$out")"
eq "release-pr-body IN-STEP"        "true" "$(has 'IN-STEP       release-pr-body' "$out")"
eq "…and the run is rc 0"           "0"    "$(_rc "$fx")"
eq "…and it says so"                "true" "$(has 'OK — every mirrored file this repo authors is in step' "$out")"

echo "== REVERSE ARM: the MIRRORED copy is edited while its stamp still claims v1.1.0 =="
# The hand-edit-in-the-mirror case README.md forbids. The declaration is untouched; the far end
# moved. A check verifying only 'declared ⇒ real' sees nothing wrong here.
fx="$(_mirror diverged)"
printf 'echo hand-edited-in-the-mirror\n' >> "$fx/templates/release/promote-released-cards"
out="$(_run "$fx")"
eq "reds as DIVERGED"                "true" "$(has 'DIVERGED      promote-released-cards' "$out")"
eq "…naming the tag it claims"       "true" "$(has 'claims v1.1.0 but is NOT v1.1.0:bin/promote-released-cards' "$out")"
eq "…and counting the differing lines" "true" "$(has '(1 differing line(s))' "$out")"
eq "…the untouched sibling stays IN-STEP" "true" "$(has 'IN-STEP       release-pr-body' "$out")"
eq "…and the run is rc 1"            "1"    "$(_rc "$fx")"

echo "== REVERSE ARM: the MIRRORED copy is a real older tag, honestly stamped =="
# Byte-perfect and truthful — and still not in step. STALE is the verdict a byte-diff alone cannot
# reach, because this copy IS byte-identical to the tag it names.
fx="$(_mirror stale)"
git -C "$TK" show "v1.0.0:bin/promote-released-cards" > "$fx/templates/release/promote-released-cards"
out="$(_run "$fx")"
eq "reds as STALE"                   "true" "$(has 'STALE         promote-released-cards' "$out")"
eq "…naming the tag it matches"      "true" "$(has 'byte-identical to the v1.0.0 it claims' "$out")"
eq "…and this checkout's VERSION"    "true" "$(has 'but VERSION is 1.1.0' "$out")"
eq "…and how far behind"             "true" "$(has '1 tag(s) landed after it' "$out")"
eq "…and the run is rc 1"            "1"    "$(_rc "$fx")"

echo "== REVERSE ARM: the MIRRORED copy carries NO stamp — the live state of the real mirror =="
# The condition the check cannot establish. Its correct output is to SAY SO BY NAME, at non-zero —
# never to guess a tag and never to pass.
fx="$(_mirror unstamped)"
sed -i '/^ABTK_TOOL_VERSION=/d' "$fx/templates/release/promote-released-cards"
out="$(_run "$fx")"
eq "reds as UNSTAMPED"               "true" "$(has 'UNSTAMPED     promote-released-cards' "$out")"
eq "…naming the missing line"        "true" "$(has 'carries no ABTK_TOOL_VERSION line' "$out")"
eq "…and refusing to guess"          "true" "$(has 'is not guessed at' "$out")"
eq "…and the run is rc 1"            "1"    "$(_rc "$fx")"

echo "== REVERSE ARM: the stamp names a tag this checkout does not have =="
fx="$(_mirror unknown-tag)"
sed -i "s/^ABTK_TOOL_VERSION=.*/ABTK_TOOL_VERSION='9.9.9'/" "$fx/templates/release/promote-released-cards"
out="$(_run "$fx")"
eq "reds as UNKNOWN-TAG"             "true" "$(has 'UNKNOWN-TAG   promote-released-cards' "$out")"
eq "…naming the tag"                 "true" "$(has 'claims v9.9.9, which this checkout does not have' "$out")"
eq "…and the run is rc 1"            "1"    "$(_rc "$fx")"

echo "== REVERSE ARM: a malformed stamp is not read as a version =="
fx="$(_mirror malformed)"
sed -i "s/^ABTK_TOOL_VERSION=.*/ABTK_TOOL_VERSION=\"1.1.0\"/" "$fx/templates/release/promote-released-cards"
out="$(_run "$fx")"
eq "double-quoted spelling reds"     "true" "$(has "stamp line is not spelled ABTK_TOOL_VERSION='<version>'" "$out")"
fx="$(_mirror twice)"
sed -i "0,/^ABTK_TOOL_VERSION=.*/s//&\n&/" "$fx/templates/release/promote-released-cards"
eq "a second stamp line reds"        "true" "$(has 'carries 2 ABTK_TOOL_VERSION lines' "$(_run "$fx")")"

echo "== DIRECTION: a shared file this repo does not AUTHOR is reported, never judged =="
# card#10176 adds bin/card-completeness, which is adopted FROM the framework — the mirror runs
# the other way — so every remedy this check prints would be backwards for it. The toolkit's own
# ABTK_TOOL_VERSION stamp is the authorship claim, so an UNSTAMPED toolkit-side file is one this
# repo does not claim. ⛔ Driven from the TOOLKIT side (removing the stamp), which is the side
# that makes the claim; the mirrored copy is left in step so a wrong verdict here could only be
# a FALSE one, not a true one arrived at by luck.
printf '#!/usr/bin/env bash\n# adopted-from-elsewhere\necho x\n' > "$TK/bin/adopted-tool"
chmod +x "$TK/bin/adopted-tool"
git -C "$TK" add -A && git -C "$TK" commit -qm adopted
fx="$(_mirror not-ours)"
cp "$TK/bin/adopted-tool" "$fx/templates/release/adopted-tool"
out="$(_run "$fx")"
eq "reported as NOT-OURS"            "true" "$(has 'NOT-OURS      adopted-tool' "$out")"
eq "…saying this repo does not stamp it" "true" "$(has 'this repo does not stamp it' "$out")"
eq "…and that it is not judged"      "true" "$(has 'NOT judged here' "$out")"
eq "…it is NOT called in-step"       "false" "$(has 'IN-STEP       adopted-tool' "$out")"
eq "…and does not make the run red"  "0"    "$(_rc "$fx")"
eq "…the authored siblings still judged" "true" "$(has 'IN-STEP       promote-released-cards' "$out")"
# CONTROL — stamp it on the TOOLKIT side and the very same pair is judged. Without this the arm
# above would pass for a check that had simply stopped looking at the file.
sed -i "2a ABTK_TOOL_VERSION='1.1.0'" "$TK/bin/adopted-tool"
git -C "$TK" add -A && git -C "$TK" commit -qm stamped && git -C "$TK" tag -f v1.1.0 -m r >/dev/null 2>&1
fx2="$(_mirror now-ours)"
cp "$TK/bin/adopted-tool" "$fx2/templates/release/adopted-tool"
out2="$(_run "$fx2")"
eq "(control) stamped ⇒ it IS judged" "false" "$(has 'NOT-OURS      adopted-tool' "$out2")"
eq "(control) …and reads IN-STEP"     "true"  "$(has 'IN-STEP       adopted-tool' "$out2")"

echo "== an intersection of ONLY unauthored files is rc 2, not a pass =="
# The empty measurement reached one step later than the no-intersection case below.
git -C "$TK" tag -d v1.1.0 >/dev/null 2>&1; git -C "$TK" tag v1.1.0
only="$TMP/only-theirs"; mkdir -p "$only/templates/release"
sed -i '/^ABTK_TOOL_VERSION=/d' "$TK/bin/adopted-tool"
git -C "$TK" add -A && git -C "$TK" commit -qm unstamped
cp "$TK/bin/adopted-tool" "$only/templates/release/adopted-tool"
out="$(_run "$only")"
eq "rc 2"                            "2"    "$(_rc "$only")"
eq "…naming why nothing was judged"  "true" "$(has 'one this repo does not author' "$out")"
eq "…and calling the pass out"       "true" "$(has 'deliberately NOT a pass' "$out")"
# Put the fixture back to the two authored bins for anything after this point.
git -C "$TK" rm -q -f bin/adopted-tool && git -C "$TK" commit -qm drop

echo "== THE SILENT-GREEN ARM: nothing to compare is rc 2, NOT rc 0 =="
# The defect this whole card exists to end: a check that read nothing reporting a pass.
fx="$TMP/empty"; mkdir -p "$fx/templates/release"
out="$(_run "$fx")"
eq "reds at rc 2"                    "2"    "$(_rc "$fx")"
eq "…saying nothing was compared"    "true" "$(has 'nothing was compared, so nothing is in step' "$out")"
eq "…and calling the pass out"       "true" "$(has 'deliberately NOT a pass' "$out")"
# A mirror holding only files the toolkit does not ship is the same measurement.
printf 'x\n' > "$fx/templates/release/not-a-toolkit-bin"
eq "an unrelated-file-only mirror is rc 2 too" "2" "$(_rc "$fx")"

echo "== the artifact it read is NAMED, and classified by kind =="
fx="$(_mirror kinds)"
eq "an installed plugin says so"     "true" "$(has 'read installed coord plugin' "$(_run "$fx")")"
eq "…and prints the resolved path"   "true" "$(has "$fx/templates/release" "$(_run "$fx")")"
# A framework repo CLONE is a different reader with a different scope, so it reports differently.
clone="$TMP/clone"; mkdir -p "$clone/plugins/coord/templates/release" "$clone/.git"
for n in promote-released-cards release-pr-body; do
  git -C "$TK" show "v1.1.0:bin/$n" > "$clone/plugins/coord/templates/release/$n"
done
eq "a clone says clone"              "true" "$(has 'read framework repo clone' "$(_run "$clone")")"
eq "…and is still IN-STEP at rc 0"   "0"    "$(_rc "$clone")"
# The clone LAYOUT without .git is not a clone — provenance is unknown and the report says so
# rather than crediting it with a history it does not have.
rmdir "$clone/.git"
eq "clone layout with no .git is named" "true" "$(has 'NO .git — not a clone' "$(_run "$clone")")"

echo "== invocation refusals =="
eq "no argument is rc 2"             "2" "$(xrc=0; bash "$CHECK" >/dev/null 2>&1 || xrc=$?; echo $xrc)"
eq "an empty argument is rc 2"       "2" "$(xrc=0; bash "$CHECK" "" >/dev/null 2>&1 || xrc=$?; echo $xrc)"
eq "…naming the unexpanded variable" "true" "$(has 'an unexpanded variable?' "$(bash "$CHECK" "" 2>&1 || true)")"
eq "an extra argument is rc 2"       "2" "$(xrc=0; bash "$CHECK" "$fx" extra >/dev/null 2>&1 || xrc=$?; echo $xrc)"
eq "a non-directory is rc 2"         "2" "$(xrc=0; bash "$CHECK" "$TMP/nope" >/dev/null 2>&1 || xrc=$?; echo $xrc)"
eq "a directory of no known shape is rc 2" "2" "$(xrc=0; bash "$CHECK" "$TMP" >/dev/null 2>&1 || xrc=$?; echo $xrc)"

echo "== the toolkit side must be able to answer, or the run is rc 2 =="
# A checkout with no tags cannot hold a stamp to anything. Saying so beats a confident verdict.
NT="$TMP/no-tags"; mkdir -p "$NT/bin" "$NT/tests"
cp "$SUBJECT" "$NT/tests/framework-mirror-check.sh"; printf '1.1.0\n' > "$NT/VERSION"
cp "$TK/bin/promote-released-cards" "$NT/bin/"
git -C "$NT" init -q && git -C "$NT" config user.email t@e.i && git -C "$NT" config user.name t
git -C "$NT" add -A && git -C "$NT" commit -qm only
fx="$(_mirror no-tags-mirror)"
rc=0; bash "$NT/tests/framework-mirror-check.sh" "$fx" >/dev/null 2>&1 || rc=$?
eq "a tagless checkout is rc 2"      "2" "$rc"
eq "…and names why"                  "true" "$(has 'has no v* tags' "$(bash "$NT/tests/framework-mirror-check.sh" "$fx" 2>&1 || true)")"

_summary "framework-mirror-check-selftest"
