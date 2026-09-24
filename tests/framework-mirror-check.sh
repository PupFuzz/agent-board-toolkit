#!/usr/bin/env bash
# framework-mirror-check.sh — measure whether the agent-board-framework's `templates/release/`
# mirrors of this repo's release bins are what README declares them to be: byte copies of the
# toolkit's own file AT A TOOLKIT TAG, synced at every tag (README § the `bin/release-pr-body`
# row: "This copy is authoritative … the agent-board-framework's `templates/release/` copies are
# mirrors synced at toolkit tags"). This repo DECLARES that lockstep; this file is its CHECK
# (card#9939). Before it, nothing on either end compared the copies, and the mirror matched no
# toolkit tag at all while both repos audited themselves clean.
#
# Usage:  tests/framework-mirror-check.sh [--toolkit <dir>] [--ref <git-ref>] <framework-path>
#   <framework-path>  EITHER a clone of the framework repo (the mirror is read from
#                     `plugins/coord/templates/release/`) OR an installed coord plugin root, e.g.
#                     `~/.claude/plugins/cache/agent-board-framework/coord/<version>` (read from
#                     `templates/release/`). These are DIFFERENT ARTIFACTS — the plugin a seat
#                     runs is not the repo's branch — so run once per artifact you care about.
#   --ref <git-ref>   read the mirror from this ref of <framework-path> (which must then be a git
#                     repo) instead of its working tree — e.g. `origin/dev` in a clone whose
#                     checkout lags or was cloned `--no-checkout`.
#   --toolkit <dir>   the toolkit checkout whose TAGS are the reference (default: the checkout
#                     this file lives in). Only LOCAL tags are read: `git fetch --tags` first.
#
# Exit:   0 = every mirrored file is IN-STEP (byte-identical to the newest toolkit tag's copy)
#         1 = at least one file is STALE (equals an older tag) or DIVERGED (equals no tag, or not
#             the tag its own ABTK_TOOL_VERSION stamp claims)
#         2 = bad invocation
#         3 = UNMEASURED — something needed for a verdict could not be read, or a file the toolkit
#             DECLARES travels is not in the mirror at all; never a pass
#         (a run that is both STALE/DIVERGED and UNMEASURED exits 1: both are failures, and the
#          re-sync rc 1 asks for is the actionable one. The UNMEASURED rows still print.)
#
# THE POPULATION IS DERIVED, NOT LISTED: every file of the toolkit's `bin/` that also exists by
# name in the mirror directory. A mirror directory sharing NO name with `bin/` is UNMEASURED,
# not clean. Each run prints the population it derived; read it rather than quoting a count.
#
# ⛔ …AND A DERIVED POPULATION IS DERIVED FROM THE AUDITED END, SO THE AUDITED END CAN SHRINK IT.
# A mirror that has DROPPED one of the two release bins shares ONE name with `bin/`, that one
# name compares clean, and the run reads `OK` — the check cannot tell IN STEP from NO LONGER
# MIRRORED, which is the exact shape that let the live drift live (*a sweep predicate built from
# the FOUND copies cannot find the DRIFTED one*). The N→0 case is caught by the `MIRRORED:` guard
# below; N→N−1 needs an anchor that does NOT come from the mirror. `FLOOR` is that anchor: the
# set README declares travels. It is WRITTEN, because it is a DECLARATION and not a measurement —
# and it is held level with the tree in both directions by two derived guards beside it, so it
# cannot rot in silence. The population still decides WHAT IS COMPARED; the floor decides WHAT
# MUST BE PRESENT.
#
# A READ HAS THREE OUTCOMES — present, absent, UNREADABLE. Every read of the mirror below keeps
# the third: a file whose bytes cannot be read is its own row at rc 3 and the loop CONTINUES, so
# the remaining files are still judged. It is never scored as drift.
#   ⚑ THAT IS NOW GUARDED, NOT MERELY STATED (card#10311). This file's first cut collapsed those
#     three outcomes, and `tests/read-outcome-collapse-selftest.sh` ran GREEN over it, because
#     its population was `bin/`+`hooks/` and this file lives in `tests/`. It is in that gate's
#     population now — derived, because `VERSIONING.md` INVOKES it by name in a fenced release
#     step — so an rc-discarding capture added here reds that gate until it is fixed or
#     dispositioned there. Nothing about that derivation is written down in this file; moving
#     this check out of the runbook's reach would move it back out of the gate.
#
# WHAT A RUN READS AND WHAT IT CANNOT SEE — printed on every run, because a green verdict about
# the wrong artifact is the failure this check exists to prevent:
#   * It reads exactly ONE framework artifact, named in its first lines (path, layout, and the
#     git commit or plugin version it carries). A plugin install and the framework repo can hold
#     different bytes; a verdict about one is not a verdict about the other.
#   * It compares BYTES. It proves nothing about behaviour, and a framework-side divergence the
#     framework has documented as deliberate is still reported as DIVERGED — "byte-identical" is
#     the declared rule, and whether an exception is justified is not something bytes can say.
#   * It cannot run in this repo's CI: the framework repo is private and CI holds no credential
#     for it. VERSIONING.md's release flow is where it is run; `framework-mirror-check-selftest.sh`
#     is what CI runs, against fixtures.
set -euo pipefail

prog="framework-mirror-check"
die() { echo "$prog: $*" >&2; exit 2; }
unmeasured() { echo "$prog: UNMEASURED — $*" >&2; exit 3; }

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TK="$(cd "$HERE/.." && pwd)"; REF=""; FW=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --toolkit|--ref)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then die "$1 needs a non-empty value"; fi
      if [ "$1" = "--toolkit" ]; then TK="$2"; else REF="$2"; fi
      shift 2 ;;
    -h|--help) awk 'NR>1 { if (substr($0,1,1) == "#") print; else exit }' "$0"; exit 0 ;;
    -*) die "unknown flag: $1" ;;
    *)
      [ -z "$FW" ] || die "unexpected extra argument: $1"
      [ -n "$1" ] || die "<framework-path> is empty (an unexpanded variable?)"
      FW="$1"; shift ;;
  esac
done
[ -n "$FW" ] || die "usage: $prog [--toolkit <dir>] [--ref <git-ref>] <framework-path>"
[ -d "$FW" ] || die "no such directory: $FW"
[ -d "$TK/bin" ] || die "no bin/ under toolkit dir: $TK"
git -C "$TK" rev-parse --git-dir >/dev/null 2>&1 || die "toolkit dir is not a git checkout: $TK"

# ── where the mirror is read from ───────────────────────────────────────────────────────────
# _fw_has <dir>: does the artifact carry it. _fw_ls <dir>: its regular files. _fw_cat <path>: bytes.
if [ -n "$REF" ]; then
  git -C "$FW" rev-parse --verify -q "$REF^{commit}" >/dev/null \
    || die "--ref '$REF' does not resolve to a commit in $FW"
  _fw_has() { [ "$(git -C "$FW" cat-file -t "$REF:$1" 2>/dev/null)" = "tree" ]; }
  _fw_ls()  { git -C "$FW" ls-tree "$REF:$1" | awk -F'\t' '$1 ~ / blob / { print $2 }'; }
  _fw_cat() { git -C "$FW" cat-file blob "$REF:$1"; }
else
  _fw_has() { [ -d "$FW/$1" ]; }
  _fw_ls()  { local f; for f in "$FW/$1"/* "$FW/$1"/.[!.]*; do [ -f "$f" ] && printf '%s\n' "${f##*/}"; done; return 0; }
  _fw_cat() { cat "$FW/$1"; }
fi

if _fw_has plugins/coord/templates/release; then
  DIR=plugins/coord/templates/release; LAYOUT="framework repo"
elif _fw_has templates/release; then
  DIR=templates/release; LAYOUT="coord plugin install"
else
  die "no plugins/coord/templates/release/ or templates/release/ under $FW${REF:+ at $REF} — not a framework repo or coord plugin root"
fi

prov=""
if [ -n "$REF" ]; then
  prov="git ref $REF = $(git -C "$FW" rev-parse "$REF^{commit}")"
elif git -C "$FW" rev-parse --git-dir >/dev/null 2>&1; then
  prov="working tree at HEAD $(git -C "$FW" rev-parse HEAD)"
  [ -z "$(git -C "$FW" status --porcelain -- "$DIR" 2>/dev/null)" ] \
    || prov="$prov, WITH UNCOMMITTED CHANGES under $DIR"
fi
if [ -z "$REF" ] && [ -r "$FW/.claude-plugin/plugin.json" ]; then
  v="$(jq -r '.version // empty' "$FW/.claude-plugin/plugin.json" 2>/dev/null || true)"
  prov="${prov:+$prov; }plugin.json version ${v:-(unreadable)}"
fi
echo "READ:     $LAYOUT at $FW — $DIR/ (${prov:-no git commit or plugin version found})"

# ── the reference: toolkit tags, newest first ───────────────────────────────────────────────
mapfile -t TAGS < <(git -C "$TK" for-each-ref --sort=-creatordate --format='%(refname:short)' refs/tags)
[ "${#TAGS[@]}" -gt 0 ] || unmeasured "the toolkit checkout $TK has no tags — git fetch --tags"
echo "AGAINST:  toolkit tags in $TK (local refs only; newest read: ${TAGS[0]} — git fetch --tags if that is not the latest release)"
echo "NOT SEEN: any other framework artifact (repo branch vs plugin install are different bytes), and behaviour — this compares bytes only"

# ── what MUST be present: the DECLARED travelling set ───────────────────────────────────────
#
# README's `bin/release-pr-body` row is the declaration: "the toolkit owns both release bins
# (tests + release discipline live here); the agent-board-framework's `templates/release/` copies
# are mirrors synced at toolkit tags". This array is that sentence, machine-readable. It is a
# RESTATEMENT of README and is therefore GUARDED, not left to agree by inspection:
# `framework-mirror-check-selftest.sh` holds every member against the README row that carries the
# declaration (and would red if README stopped naming one).
FLOOR=(promote-released-cards release-pr-body)

# GUARD 1 — a declared member `bin/` no longer carries. Errs RED on a rename or a removal, so the
# declaration cannot outlive the file it names.
floor_missing=""
for n in "${FLOOR[@]}"; do
  [ -f "$TK/bin/$n" ] || floor_missing="$floor_missing $n"
done
[ -z "$floor_missing" ] || unmeasured "the declared mirrored set names$floor_missing, which $TK/bin/ does not carry — this file's FLOOR (and README's declaration) is stale"

# GUARD 2 — THE SELF-WIDENING LEG. `ABTK_TOOL_VERSION=` is the toolkit's own machine-readable
# "this file travels" marker (VERSIONING rule 1): it exists so a copy living in another repo, with
# no `VERSION` beside it, can still name the release it IS. Today exactly ONE of the two declared
# bins carries it — which is precisely why the stamp is used as a CONTROL ON the declaration and
# NOT as the anchor itself: as the anchor it would cover `release-pr-body` and say nothing at all
# about `promote-released-cards`, i.e. it would miss the very drop this whole section exists to
# catch. As a control it errs the safe way — the day a THIRD bin is stamped, this reds until the
# FLOOR above is widened, so the written declaration cannot silently lag the tree.
stamped_extra=""
for f in "$TK"/bin/*; do
  [ -f "$f" ] || continue
  grc=0; command grep -q '^ABTK_TOOL_VERSION=' "$f" || grc=$?
  case "$grc" in
    0) case " ${FLOOR[*]} " in *" ${f##*/} "*) ;; *) stamped_extra="$stamped_extra ${f##*/}" ;; esac ;;
    1) ;;
    *) unmeasured "could not scan $f for an ABTK_TOOL_VERSION stamp (grep rc $grc) — the floor's control did not run" ;;
  esac
done
[ -z "$stamped_extra" ] || unmeasured "$TK/bin/ stamps$stamped_extra as a travelling release bin, and this file's FLOOR does not declare it — widen the FLOOR (and README) or drop the stamp"

# Printed BEFORE the derived population, and before the guard that can exit on it: the
# declaration is what the measurement below is judged against, and a run that ends at
# `nothing to compare` should still have said what it was looking for.
echo "MUST CARRY: ${FLOOR[*]} — the set README declares travels; one this artifact does not carry is UNMEASURED, never OK"

mapfile -t NAMES < <(_fw_ls "$DIR" | while IFS= read -r n; do [ -f "$TK/bin/$n" ] && printf '%s\n' "$n"; done)
[ "${#NAMES[@]}" -gt 0 ] || unmeasured "no file under $DIR shares a name with the toolkit's bin/ — nothing to compare"
echo "MIRRORED: ${NAMES[*]}"

# `|| unmeasured`, not a bare capture: under `set -e` a scratch dir this run could not create
# would kill the script with mktemp's status 1 — the code this header documents as
# STALE-or-DIVERGED — and VERSIONING step 12 would relay a re-sync request to another repo's
# owner for a mirror nothing had read. A failure of this file's own machinery is never drift.
tmp="$(mktemp -d)" || unmeasured "could not create a scratch directory (TMPDIR unwritable?) — nothing was compared"
trap 'rm -rf "$tmp"' EXIT
drift=0; unm=0

# THE ANCHOR ITSELF. A declared file the mirror does not carry is not a file that is in step.
for n in "${FLOOR[@]}"; do
  case " ${NAMES[*]} " in
    *" $n "*) ;;
    *) echo "NOT MIRRORED $n — the toolkit declares bin/$n travels to $DIR/, and this artifact does not carry it"; unm=1 ;;
  esac
done

for n in "${NAMES[@]}"; do
  if ! _fw_cat "$DIR/$n" > "$tmp/mirror" 2>"$tmp/err"; then
    echo "UNMEASURED $n — its bytes could not be read from this artifact: $(head -n1 "$tmp/err" 2>/dev/null || true)"; unm=1; continue
  fi
  # ⚑ NO LOCAL CONTROL, AND SAID SO RATHER THAN IMPLIED. Unlike the read above and the scratch
  # dir before it, `git hash-object` over a regular file this process just wrote has no failure this
  # file can stage: it was driven against a broken `clean` filter and an out-of-worktree path and
  # answered rc 0 both times. It is kept because it is the one remaining substitution inside the
  # loop, and a bare capture here re-mints exactly the shape the arm above exists to close — a
  # non-zero status killing the run under `set -e` and being reported as rc 1 DRIFT. Read it as
  # a closed hole, never as a checked one; `framework-mirror-check-selftest.sh` drives the other
  # two legs of this class and does not claim this one.
  if ! blob="$(git -C "$TK" hash-object "$tmp/mirror" 2>"$tmp/err")"; then
    echo "UNMEASURED $n — the toolkit could not hash the bytes read for it: $(head -n1 "$tmp/err" 2>/dev/null || true)"; unm=1; continue
  fi

  newest=""; newest_blob=""; match=""
  for t in "${TAGS[@]}"; do
    b="$(git -C "$TK" rev-parse -q --verify "$t:bin/$n" 2>/dev/null)" || continue
    [ -n "$newest" ] || { newest="$t"; newest_blob="$b"; }
    [ "$b" = "$blob" ] && { match="$t"; break; }
  done
  [ -n "$newest" ] || { echo "UNMEASURED $n — no toolkit tag carries bin/$n"; unm=1; continue; }

  # A copy that carries the toolkit's own version stamp CLAIMS a tag; hold it to that claim.
  claim="$(sed -n "s/^ABTK_TOOL_VERSION='\\(.*\\)'\$/\\1/p" "$tmp/mirror" | head -n1)"
  if [ -n "$claim" ]; then
    ctag="$("$TK/bin/release-pr-body" --config "$TK/.release-pr.json" --version "$claim" --tag 2>/dev/null)" \
      || { echo "UNMEASURED $n — stamp claims $claim and the toolkit's own release-pr-body --tag could not map it to a tag (is $TK/.release-pr.json readable, and $TK/bin/release-pr-body runnable?)"; unm=1; continue; }
    cblob="$(git -C "$TK" rev-parse -q --verify "$ctag:bin/$n" 2>/dev/null)" \
      || { echo "UNMEASURED $n — stamp claims $ctag, which this checkout does not have (git fetch --tags)"; unm=1; continue; }
    if [ "$cblob" != "$blob" ]; then
      echo "DIVERGED  $n — its stamp claims $ctag but its bytes are not $ctag's bin/$n (blob $blob)"; drift=1; continue
    fi
  fi

  if [ "$blob" = "$newest_blob" ]; then
    echo "IN-STEP   $n — byte-identical to $newest's bin/$n"
  elif [ -n "$match" ]; then
    echo "STALE     $n — byte-identical to $match's bin/$n; the newest tag carrying it, $newest, differs"; drift=1
  else
    best=""; bestn=""
    for t in "${TAGS[@]}"; do
      git -C "$TK" show "$t:bin/$n" > "$tmp/tag" 2>/dev/null || continue
      d="$(diff "$tmp/tag" "$tmp/mirror" | grep -c '^[<>]' || true)"
      if [ -z "$bestn" ] || [ "$d" -lt "$bestn" ]; then best="$t"; bestn="$d"; fi
    done
    echo "DIVERGED  $n — byte-identical to NO toolkit tag (blob $blob); nearest is $best at $bestn differing lines, newest is $newest"; drift=1
  fi
done

if [ "$drift" -ne 0 ]; then
  echo "$prog: FAILED — the mirror is not a copy of a toolkit tag. The fix is a framework-side re-sync FROM a toolkit tag, never a hand edit of the mirror (README)." >&2
  exit 1
fi
[ "$unm" -eq 0 ] || { echo "$prog: UNMEASURED — see the rows above" >&2; exit 3; }
echo "$prog: OK — every mirrored file is byte-identical to the newest toolkit tag's copy"
