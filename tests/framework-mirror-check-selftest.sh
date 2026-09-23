#!/usr/bin/env bash
# framework-mirror-check-selftest.sh — drive `tests/framework-mirror-check.sh` over FIXTURES, so
# each verdict is observed firing on the input that earns it and staying silent on the one that
# does not (card#9939).
#
# WHY FIXTURES. The check's real subject — the agent-board-framework's `templates/release/` —
# lives in a PRIVATE repo this CI holds no credential for, so CI cannot run the check itself.
# What it can run is this: a toolkit fixture with two tags, and framework fixtures in both
# layouts the check accepts, each built to be exactly one verdict.
#
# WHAT A GREEN RUN PROVES — the weakest property the assertions support: on these fixtures the
# check names IN-STEP / STALE / DIVERGED / UNMEASURED for the inputs built to be each, exits with
# the rc its header documents, derives its population from names shared with `bin/`, holds that
# derived population to the DECLARED floor so a mirror that dropped a file is not scored clean,
# keeps a read's third outcome (unreadable) apart from drift, reads the git ref it was given
# rather than the working tree, holds a stamped copy to the tag its stamp claims, and says which
# artifact it read. It proves nothing about the real framework mirror — run the check itself for
# that (VERSIONING.md's release flow).
#
# ⛔ EVERY rc-0 ASSERTION IS PAIRED WITH THE SAME FIXTURE, ONE CONDITION APART, OBSERVED RED —
# because an IN-STEP answer from a check that compared nothing would pass the rc-0 half alone.
# The pairing runs in BOTH directions and the label says which: where the rc 0 is the CLAIM, the
# red beside it is a one-line mutation of that fixture (an appended byte, a stale working tree, a
# removed file); where the rc 0 is labelled `control:`, it is the green half of an adjacent RED
# arm, differing from it by exactly the one condition that arm is about — which is what makes
# that red discrimination and not something the check prints over any input.
#
# That is a universal, so it carries the derivation of its own population rather than a count:
#
#     command grep -n 'eq "[^"]*" "0" "\$RC"' tests/framework-mirror-check-selftest.sh
#
# — every assertion that the subject exited 0. Re-run it after any edit here and read the pairing
# off the file; a number written in this comment would be a quoted authority the next edit
# falsifies. The pairing was MISSING on the plugin-layout arm when the universal was first
# written (it asserted rc 0 and the `READ:` line and nothing else, in the only coverage of the
# layout a seat actually runs), which is why the derivation is spelled out here.
#
# ⛔ AND EVERY rc-3 ARM IS DRIVEN. `UNMEASURED` is the verdict that must never be reachable only
# in theory: an arm with no control is a branch nobody has seen taken, and this check's whole
# contract is that it refuses rather than passes when it could not measure.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
TOOLKIT="$(cd "$HERE/.." && pwd)"
CHECK="$HERE/framework-mirror-check.sh"
_need -x "$CHECK"
_need -x "$TOOLKIT/bin/release-pr-body"
_need -r "$TOOLKIT/.release-pr.json"
_mktmp_scratch

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# _run <args...> — run the check as a process; sets RC/OUT (stdout+stderr: the verdict rows are
# on stdout and the summary on stderr, and every assertion below reads one or the other).
_run() { RC=0; OUT="$("$CHECK" "$@" 2>&1)" || RC=$?; }

# ── toolkit fixture: v0.1.0 then v0.2.0, each carrying a distinct promote and a stamped
# release-pr-body. The stamped file is the REAL bin with only its stamp rewritten, because the
# check maps a stamp to a tag by calling the toolkit's own `release-pr-body --tag`.
TK="$TMP/tk"
mkdir -p "$TK/bin"
git -C "$TK" init -q
cp "$TOOLKIT/.release-pr.json" "$TK/.release-pr.json"
_stamp() { sed "s/^ABTK_TOOL_VERSION=.*/ABTK_TOOL_VERSION='$1'/" "$TOOLKIT/bin/release-pr-body" > "$TK/bin/release-pr-body"; chmod +x "$TK/bin/release-pr-body"; }
printf 'promote v1\nline two\n' > "$TK/bin/promote-released-cards"
printf 'not mirrored\n' > "$TK/bin/kbcard"
_stamp 0.1.0
git -C "$TK" add -A && GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git -C "$TK" commit -qm one && git -C "$TK" tag v0.1.0
printf 'promote v2\nline two\n' > "$TK/bin/promote-released-cards"
_stamp 0.2.0
git -C "$TK" add -A && GIT_COMMITTER_DATE='2026-02-01T00:00:00Z' git -C "$TK" commit -qm two && git -C "$TK" tag v0.2.0

eq "premise: the stamp maps to its tag through the toolkit's own release-pr-body" "v0.2.0" \
   "$("$TK/bin/release-pr-body" --config "$TK/.release-pr.json" --version 0.2.0 --tag)"

# _mirror <dir> <tag> — a framework-repo-layout fixture whose release dir holds <tag>'s copies,
# plus a file that is NOT a toolkit bin (must not join the population).
_mirror() {
  local d="$1/plugins/coord/templates/release"
  mkdir -p "$d"
  git -C "$TK" show "$2:bin/promote-released-cards" > "$d/promote-released-cards"
  git -C "$TK" show "$2:bin/release-pr-body" > "$d/release-pr-body"
  printf 'framework-only\n' > "$d/release-pr.json.template"
}

echo "== bad invocation exits 2, naming the fault =="
_bad() { local label="$1" want="$2"; shift 2; _run "$@"; eq "$label: rc 2" "2" "$RC"; eq "$label: says '$want'" "true" "$(has "$want" "$OUT")"; }
_bad "no arguments" "usage: framework-mirror-check"
_bad "empty path" "<framework-path> is empty" --toolkit "$TK" ""
_bad "unknown flag" "unknown flag: --nope" --nope "$TMP"
_bad "--ref without a value" "--ref needs a non-empty value" "$TMP" --ref
_bad "extra positional" "unexpected extra argument: b" --toolkit "$TK" "$TMP" b
_bad "missing dir" "no such directory" --toolkit "$TK" "$TMP/absent"
mkdir -p "$TMP/neither"
_bad "neither layout" "not a framework repo or coord plugin root" --toolkit "$TK" "$TMP/neither"

echo "== IN-STEP: both copies equal the newest tag's =="
FW="$TMP/fw-instep"; _mirror "$FW" v0.2.0
_run --toolkit "$TK" "$FW"
eq "in-step: rc 0" "0" "$RC"
eq "in-step: promote row" "true" "$(has "IN-STEP   promote-released-cards — byte-identical to v0.2.0" "$OUT")"
eq "in-step: release-pr-body row" "true" "$(has "IN-STEP   release-pr-body — byte-identical to v0.2.0" "$OUT")"
eq "population: the two shared names, and only those" "true" "$(has_line "MIRRORED: promote-released-cards release-pr-body" "$OUT")"
eq "names the artifact and layout it read" "true" "$(has "READ:     framework repo at $FW" "$OUT")"
eq "names what it cannot see" "true" "$(has "NOT SEEN: any other framework artifact" "$OUT")"
eq "names the newest tag it read" "true" "$(has "newest read: v0.2.0" "$OUT")"
# the mutation witness for the rc-0 above: one changed byte in the SAME fixture reds
printf 'x' >> "$FW/plugins/coord/templates/release/promote-released-cards"
_run --toolkit "$TK" "$FW"
eq "in-step witness: one appended byte → rc 1" "1" "$RC"

echo "== STALE: a copy equal to an OLDER tag =="
FW="$TMP/fw-stale"; _mirror "$FW" v0.2.0
git -C "$TK" show v0.1.0:bin/promote-released-cards > "$FW/plugins/coord/templates/release/promote-released-cards"
_run --toolkit "$TK" "$FW"
eq "stale: rc 1" "1" "$RC"
eq "stale: names the tag it equals and the newest" "true" \
   "$(has "STALE     promote-released-cards — byte-identical to v0.1.0's bin/promote-released-cards; the newest tag carrying it, v0.2.0, differs" "$OUT")"
eq "stale: the other file is still judged on its own" "true" "$(has "IN-STEP   release-pr-body" "$OUT")"
eq "stale: summary names the remedy" "true" "$(has "re-sync FROM a toolkit tag, never a hand edit" "$OUT")"

echo "== DIVERGED: a copy equal to no tag, with the nearest named =="
FW="$TMP/fw-div"; _mirror "$FW" v0.2.0
printf 'promote v2\nFRAMEWORK EDIT\n' > "$FW/plugins/coord/templates/release/promote-released-cards"
_run --toolkit "$TK" "$FW"
eq "diverged: rc 1" "1" "$RC"
eq "diverged: nearest tag and distance" "true" "$(has "nearest is v0.2.0 at 2 differing lines, newest is v0.2.0" "$OUT")"

echo "== a stamp is a CLAIM, held to its tag =="
FW="$TMP/fw-claim"; _mirror "$FW" v0.2.0
printf '# a framework-local line\n' >> "$FW/plugins/coord/templates/release/release-pr-body"
_run --toolkit "$TK" "$FW"
eq "false claim: rc 1" "1" "$RC"
eq "false claim: names the claimed tag" "true" "$(has "DIVERGED  release-pr-body — its stamp claims v0.2.0 but its bytes are not v0.2.0's" "$OUT")"
FW="$TMP/fw-claim-old"; _mirror "$FW" v0.2.0
git -C "$TK" show v0.1.0:bin/release-pr-body > "$FW/plugins/coord/templates/release/release-pr-body"
_run --toolkit "$TK" "$FW"
eq "true claim of an older tag: STALE, not DIVERGED" "true" "$(has "STALE     release-pr-body — byte-identical to v0.1.0" "$OUT")"
FW="$TMP/fw-claim-none"; _mirror "$FW" v0.2.0
sed -i "s/^ABTK_TOOL_VERSION=.*/ABTK_TOOL_VERSION='9.9.9'/" "$FW/plugins/coord/templates/release/release-pr-body"
_run --toolkit "$TK" "$FW"
eq "claim of a tag this checkout lacks: rc 3" "3" "$RC"
eq "claim of a tag this checkout lacks: says so" "true" "$(has "UNMEASURED release-pr-body — stamp claims v9.9.9, which this checkout does not have" "$OUT")"

echo "== the plugin-install layout, and its provenance =="
PL="$TMP/plugin"; mkdir -p "$PL/templates/release" "$PL/.claude-plugin"
cp "$TMP/fw-instep/plugins/coord/templates/release/release-pr-body" "$PL/templates/release/"
git -C "$TK" show v0.2.0:bin/promote-released-cards > "$PL/templates/release/promote-released-cards"
printf '{"name":"coord","version":"7.7.7"}\n' > "$PL/.claude-plugin/plugin.json"
_run --toolkit "$TK" "$PL"
eq "plugin layout: rc 0" "0" "$RC"
eq "plugin layout: named, with its plugin.json version" "true" "$(has "READ:     coord plugin install at $PL — templates/release/ (plugin.json version 7.7.7)" "$OUT")"
# ⛔ THIS ARM IS THE ONLY COVERAGE OF THE PLUGIN LAYOUT, AND THE PLUGIN IS THE ARTIFACT A SEAT
# ACTUALLY RUNS. Asserting rc 0 and the `READ:` line alone would pass over a run that derived an
# empty population, judged nothing, and said so nowhere — so the population and both per-file
# verdicts are asserted here, exactly as they are in the framework-repo layout above.
eq "plugin layout: the population is derived here too" "true" "$(has_line "MIRRORED: promote-released-cards release-pr-body" "$OUT")"
eq "plugin layout: promote is judged, not merely counted" "true" "$(has "IN-STEP   promote-released-cards — byte-identical to v0.2.0" "$OUT")"
eq "plugin layout: release-pr-body is judged too" "true" "$(has "IN-STEP   release-pr-body — byte-identical to v0.2.0" "$OUT")"
# the mutation witness for the rc-0 above: one changed byte in the SAME fixture reds
printf 'x' >> "$PL/templates/release/promote-released-cards"
_run --toolkit "$TK" "$PL"
eq "plugin layout witness: one appended byte → rc 1" "1" "$RC"

echo "== --ref reads the committed tree, not the working tree =="
FR="$TMP/fw-git"; _mirror "$FR" v0.2.0
git -C "$FR" init -q && git -C "$FR" add -A && git -C "$FR" commit -qm mirror
git -C "$TK" show v0.1.0:bin/promote-released-cards > "$FR/plugins/coord/templates/release/promote-released-cards"
_run --toolkit "$TK" "$FR"
eq "working tree (stale edit): rc 1" "1" "$RC"
eq "working tree: provenance flags the uncommitted change" "true" "$(has "WITH UNCOMMITTED CHANGES under plugins/coord/templates/release" "$OUT")"
_run --toolkit "$TK" --ref HEAD "$FR"
eq "--ref HEAD (in-step commit): rc 0" "0" "$RC"
eq "--ref HEAD: provenance names the ref and its commit" "true" "$(has "(git ref HEAD = $(git -C "$FR" rev-parse HEAD))" "$OUT")"
_bad "--ref that does not resolve" "--ref 'nope' does not resolve" --toolkit "$TK" --ref nope "$FR"

echo "== a mirror that DROPPED a declared file is not OK =="
# The population is derived from the AUDITED end, so the audited end can SHRINK it. N→0 is the
# `nothing to compare` arm below; N→N−1 is this one, and until the FLOOR anchor landed it read
# `MIRRORED: release-pr-body` / `IN-STEP` / `OK` / rc 0 in BOTH read modes — a mirror holding one
# of the two files satisfying a check whose whole subject is that both travel.
OKF="$TMP/fw-floor-ok"; _mirror "$OKF" v0.2.0
DROP="$TMP/fw-drop"; _mirror "$DROP" v0.2.0
rm "$DROP/plugins/coord/templates/release/promote-released-cards"
_run --toolkit "$TK" "$DROP"
eq "a dropped declared file: rc 3, not 0" "3" "$RC"
eq "a dropped declared file: its own row, naming the declaration" "true" \
   "$(has "NOT MIRRORED promote-released-cards — the toolkit declares bin/promote-released-cards travels to plugins/coord/templates/release/, and this artifact does not carry it" "$OUT")"
eq "a dropped declared file: the survivor is still judged" "true" "$(has "IN-STEP   release-pr-body" "$OUT")"
eq "a dropped declared file: never reports OK" "false" "$(has "framework-mirror-check: OK" "$OUT")"
eq "the floor is printed on every run, beside the derived population" "true" \
   "$(has_line "MUST CARRY: promote-released-cards release-pr-body — the set README declares travels; one this artifact does not carry is UNMEASURED, never OK" "$OUT")"
# the same drop read through a REF, because the anchor must not be a working-tree-only property
git -C "$DROP" init -q && git -C "$DROP" add -A && git -C "$DROP" commit -qm dropped
_run --toolkit "$TK" --ref HEAD "$DROP"
eq "a dropped declared file via --ref HEAD: rc 3" "3" "$RC"
# CONTROL — the SAME fixture with the one file put back is rc 0 and prints no such row, so the
# rows above are the drop and not something this check says about every mirror.
git -C "$TK" show v0.2.0:bin/promote-released-cards > "$DROP/plugins/coord/templates/release/promote-released-cards"
_run --toolkit "$TK" "$DROP"
eq "control: the same fixture carrying both files is rc 0" "0" "$RC"
eq "control: no NOT MIRRORED row on a complete mirror" "false" "$(has "NOT MIRRORED" "$OUT")"

echo "== the declared floor is held level with bin/, in both directions =="
# The floor is WRITTEN (it is a declaration, not a measurement), so the two guards that stop it
# rotting are what make it trustworthy — and each is driven here rather than assumed.
TKG="$TMP/tk-renamed"; cp -a "$TK" "$TKG"
mv "$TKG/bin/promote-released-cards" "$TKG/bin/promote-cards"
_run --toolkit "$TKG" "$OKF"
eq "a declared member bin/ no longer carries: rc 3" "3" "$RC"
eq "…and it is named, not silently dropped from the floor" "true" \
   "$(has "the declared mirrored set names promote-released-cards, which $TKG/bin/ does not carry" "$OUT")"
# the SELF-WIDENING leg: a third bin carrying the toolkit's own `this file travels` stamp reds
# until the floor declares it, so the written declaration cannot lag the tree in silence.
TKS="$TMP/tk-newstamp"; cp -a "$TK" "$TKS"
printf "#!/usr/bin/env bash\nABTK_TOOL_VERSION='0.2.0'\n" > "$TKS/bin/some-new-mover"
_run --toolkit "$TKS" "$OKF"
eq "a newly stamped bin the floor does not declare: rc 3" "3" "$RC"
eq "…and it is named" "true" "$(has "stamps some-new-mover as a travelling release bin" "$OUT")"

echo "== the FLOOR is a restatement of README, and is held against it =="
# The check loads the declared set INLINE — a running program cannot follow a pointer — so the
# copy is GUARDED here rather than deleted. Derived FROM THE CHECK and compared against the README
# row that carries the declaration; never against a list typed in this file, which would be a
# third copy.
# ⚑ BOUND, stated so the guard is not over-cited: this is one-way. It reds when the check declares
# a file README's declaration does not name. README naming a THIRD travelling bin that the floor
# omits is prose with no machine-readable shape, and is covered instead by the stamp guard above
# the moment that bin is stamped.
mapfile -t FLOOR_DECLARED < <(awk '/^FLOOR=\(/ { s = $0; sub(/^FLOOR=\(/, "", s); sub(/\).*$/, "", s); n = split(s, a, " "); for (i = 1; i <= n; i++) print a[i]; exit }' "$CHECK")
eq "the FLOOR extraction carries real data (positive control)" "false" \
   "$([[ "${#FLOOR_DECLARED[@]}" -eq 0 ]] && echo true || echo false)"
DECL_ROW="$(awk '/mirrors synced at toolkit tags/ { print; exit }' "$TOOLKIT/README.md")"
eq "README still carries the mirror declaration (positive control)" "false" \
   "$([[ -z "$DECL_ROW" ]] && echo true || echo false)"
for n in "${FLOOR_DECLARED[@]}"; do
  eq "README's mirror declaration names $n" "true" "$(has "$n" "$DECL_ROW")"
done

echo "== a read has THREE outcomes, and the third is never DRIFT =="
# Under `set -euo pipefail` an unreadable mirror file used to kill the run with cat's status 1 —
# the code this check's header documents as STALE-or-DIVERGED. The loop aborted, no summary
# printed, every remaining file went unjudged, and VERSIONING step 12 would have relayed that
# rc 1 to another repo's owner as a re-sync request for a file nobody read.
UR="$TMP/fw-unreadable"; _mirror "$UR" v0.2.0
UF="$UR/plugins/coord/templates/release/promote-released-cards"
chmod 000 "$UF"
# ⛔ THE PRECONDITION IS ITS OWN CELL. A mode-000 file is readable to root, so without this the
# whole arm below would pass as an ordinary IN-STEP run and report a defect class as covered.
eq "precondition: the fixture really is unreadable to this user (not running as root?)" "false" \
   "$(cat "$UF" >/dev/null 2>&1 && echo true || echo false)"
_run --toolkit "$TK" "$UR"
eq "an unreadable mirror file: rc 3, not cat's 1" "3" "$RC"
eq "an unreadable mirror file: its own row, naming the read failure" "true" \
   "$(has "UNMEASURED promote-released-cards — its bytes could not be read from this artifact" "$OUT")"
eq "an unreadable mirror file: the loop CONTINUES and the next file is judged" "true" \
   "$(has "IN-STEP   release-pr-body" "$OUT")"
eq "an unreadable mirror file: the summary still prints" "true" \
   "$(has "framework-mirror-check: UNMEASURED — see the rows above" "$OUT")"
eq "an unreadable mirror file: never scored as drift" "false" "$(has "framework-mirror-check: FAILED" "$OUT")"
# CONTROL — the same fixture, readable, is rc 0: the rows above are the chmod and nothing else.
chmod 644 "$UF"
_run --toolkit "$TK" "$UR"
eq "control: the same fixture readable is rc 0" "0" "$RC"

echo "== a failure of the check's OWN machinery is UNMEASURED, never DRIFT =="
RC=0; OUT="$(TMPDIR="$TMP/no-such-tmpdir" "$CHECK" --toolkit "$TK" "$OKF" 2>&1)" || RC=$?
eq "an unusable TMPDIR: rc 3, not mktemp's 1" "3" "$RC"
eq "an unusable TMPDIR: says nothing was compared" "true" "$(has "could not create a scratch directory" "$OUT")"

echo "== UNMEASURED is never a pass =="
FW="$TMP/fw-nothing"; mkdir -p "$FW/plugins/coord/templates/release"
printf 'x\n' > "$FW/plugins/coord/templates/release/unrelated"
_run --toolkit "$TK" "$FW"
eq "no shared name: rc 3" "3" "$RC"
eq "no shared name: says nothing to compare" "true" "$(has "shares a name with the toolkit's bin/ — nothing to compare" "$OUT")"
NT="$TMP/tk-notags"; mkdir -p "$NT/bin"; git -C "$NT" init -q
_run --toolkit "$NT" "$TMP/fw-instep"
eq "toolkit with no tags: rc 3" "3" "$RC"
eq "toolkit with no tags: says so" "true" "$(has "has no tags" "$OUT")"
# a mirrored bin that NO TAG carries — the toolkit grew a bin after its last tag and the mirror
# already has it, so there is no tagged copy to compare against. A measurement that did not
# happen, not a clean one.
TKN="$TMP/tk-untagged"; cp -a "$TK" "$TKN"
printf 'brand new\n' > "$TKN/bin/newly-added"
git -C "$TKN" add -A && GIT_COMMITTER_DATE='2026-03-01T00:00:00Z' git -C "$TKN" commit -qm three
UN="$TMP/fw-untagged"; _mirror "$UN" v0.2.0
printf 'brand new\n' > "$UN/plugins/coord/templates/release/newly-added"
_run --toolkit "$TKN" "$UN"
eq "a mirrored bin no tag carries: rc 3" "3" "$RC"
eq "a mirrored bin no tag carries: says which and why" "true" \
   "$(has "UNMEASURED newly-added — no toolkit tag carries bin/newly-added" "$OUT")"
eq "a mirrored bin no tag carries: the declared files are still judged" "true" "$(has "IN-STEP   promote-released-cards" "$OUT")"
# CONTROL — the SAME toolkit against the SAME mirror with that one file removed is rc 0, so the
# row is discrimination rather than something this fixture prints either way.
rm "$UN/plugins/coord/templates/release/newly-added"
_run --toolkit "$TKN" "$UN"
eq "control: the same toolkit against a mirror lacking it is rc 0" "0" "$RC"
# a stamp the toolkit's OWN mapper cannot turn into a tag. `release-pr-body --tag` reads
# `.release-pr.json`; a toolkit checkout whose config is gone answers non-zero for EVERY version,
# so the copy's claim is unjudged rather than judged false — and the row must say where the
# mapping failed, not blame the stamp.
TKC="$TMP/tk-noconfig"; cp -a "$TK" "$TKC"; rm "$TKC/.release-pr.json"
_run --toolkit "$TKC" "$OKF"
eq "a stamp the toolkit cannot map to a tag: rc 3" "3" "$RC"
eq "a stamp the toolkit cannot map to a tag: names the claim and the mapper" "true" \
   "$(has "UNMEASURED release-pr-body — stamp claims 0.2.0 and the toolkit's own release-pr-body --tag could not map it to a tag" "$OUT")"

_summary "framework-mirror-check-selftest"
