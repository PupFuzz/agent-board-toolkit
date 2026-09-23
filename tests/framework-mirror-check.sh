#!/usr/bin/env bash
# framework-mirror-check.sh — hold the agent-board-framework's `templates/release/` copies of this
# repo's release bins to the toolkit TAG each copy's own stamp claims.
#
# ⛔ NOT a gate and NOT a `*-selftest.sh`. It reads an artifact that lives OUTSIDE this repo and
# cannot exist on a CI runner (the framework repo is private, and a plugin install is a property of
# a developer's box), so it is deliberately not named `*-selftest.sh`: `ci-matrix-parity-selftest`'s
# orphan gate (population `tests/*-selftest.sh`) does not claim it, `suite-home-containment`'s
# `*selftest*` glob does not run it, and it is wired into no workflow. Same shape, same reason, as
# `mirror-pair-census.sh` beside it. `VERSIONING.md` release step 12 is what runs it.
# `tests/framework-mirror-check-selftest.sh` drives THIS file over fixtures, and that one IS in CI.
#
# ─────────────────────────── WHY THIS EXISTS (card#9939) ───────────────────────────
#
# `README.md` DECLARES a lockstep: the toolkit owns the release bins, and the framework's
# `templates/release/` copies are "mirrors synced at toolkit tags". That declaration is a
# CROSS-REPO guarantee — its population is the HOP, which neither repo contains. Each end can audit
# itself completely clean while the seam is audited by neither, and that is exactly what happened:
# the mirror drifted with a green suite on both sides, because nothing anywhere compared them.
#
# Canon #7 puts three obligations on the DECLARING end, which for this pair is the toolkit:
#
#   DECLARE — state the guarantee's conditions on a surface the consuming end can REACH. For a
#     mirrored FILE the reachable surface is THE FILE ITSELF: a copy sitting in another repo has no
#     `VERSION` beside it, so the toolkit release it is has to travel INSIDE it. That is the
#     `ABTK_TOOL_VERSION` stamp (`VERSIONING.md` rule 1), which `bin/promote-released-cards` and
#     `bin/release-pr-body` both carry. The stamp is the declaration; this check reads THAT, not a
#     restatement of it kept here, which is why a sync can never leave the two disagreeing.
#   CHECK — the declaring end owns a check that its declaration is true of its own code. This file.
#   NAME WHAT YOU CANNOT VERIFY — where a condition cannot be established from inside this repo,
#     saying so BY NAME is the correct OUTPUT, not a failure of the mechanism. Three such
#     conditions are named rather than assumed, and each is a NON-ZERO verdict here:
#       * an UNSTAMPED copy — older than the stamp, so it names no release and can be held to no
#         tag. It is NOT "probably the oldest tag" and is never guessed at;
#       * a copy whose stamp names a tag THIS CHECKOUT DOES NOT HAVE (`UNKNOWN-TAG`);
#       * the artifact-identity question this check structurally cannot answer — see below.
#
# ⚠ WHAT THIS CHECK CANNOT SEE, STATED SO A GREEN IS NOT OVER-READ. It compares the toolkit against
# ONE artifact that the caller NAMES, and it prints which one it read, resolved to an absolute path
# and classified. It CANNOT tell you whether that artifact agrees with the framework repo's own
# `templates/release/`: an installed plugin is a PUBLISHED copy of that directory, so a plugin that
# is in step proves nothing about the framework repo's working tree, and if those two disagree that
# is a THIRD copy and a worse finding than anything this file reports. Point it at a clone of the
# framework repo to answer that question; pointed at a plugin it answers the published-copy question
# only, and SAYS which of the two it did.
#
# ⚠ AND A BYTE-EQUAL COPY IS NOT A CLAIM ABOUT BEHAVIOUR EITHER WAY. The mirror legitimately carries
# framework-local divergences, marked `MIRROR NOTE` in its own source (a fix ahead of the toolkit
# awaiting adoption, a comment block that applies only there). Those make a copy DIVERGED here, and
# DIVERGED is a report, not a verdict that someone erred — read the notes before acting on it.
#
# ─────────────────────────── THE POPULATION, DERIVED ───────────────────────────
#
# The mirrored set is NOT listed here and NOT read from any manifest that could go stale. It is the
# INTERSECTION, by basename, of this repo's `bin/` and the artifact's `templates/release/` — the
# same way `bin/agent-board-toolkit-drift-check` derives an adopter's vendored set, and for the same
# reason: a file that starts being mirrored is measured on the day it lands, not on the day somebody
# remembers to add it. ⛔ An EMPTY intersection is rc 2, never rc 0 — a check that read nothing has
# not established that anything is in step, and reporting that as a pass is the exact silent-green
# this card exists to end.
#
# Usage:  framework-mirror-check.sh <framework-artifact-dir>
# Exit:   0 = every mirrored file IN-STEP at this checkout's VERSION
#         1 = at least one STALE / DIVERGED / UNSTAMPED / UNKNOWN-TAG
#         2 = bad invocation, or nothing could be measured
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

die() { echo "framework-mirror-check: $*" >&2; exit 2; }

[ "$#" -ge 1 ] || die "usage: framework-mirror-check.sh <framework-artifact-dir>"
ART="$1"
[ -n "$ART" ] || die "<framework-artifact-dir> is empty (an unexpanded variable?)"
[ "$#" -le 1 ] || die "unexpected extra argument: ${2:-(empty — an unexpanded variable?)}"
[ -d "$ART" ] || die "no such directory: $ART"

# ── resolve the artifact, and CLASSIFY it: the answer's scope depends on which kind it is. ──
# Accepted spellings, in order. Each names a different reader, so the resolved KIND is reported
# rather than collapsed into "found it".
ART="$(cd "$ART" && pwd)"
if   [ -d "$ART/plugins/coord/templates/release" ]; then
  MIRROR="$ART/plugins/coord/templates/release"; KIND="framework repo clone"
elif [ -d "$ART/templates/release" ]; then
  MIRROR="$ART/templates/release";               KIND="installed coord plugin"
elif [ "$(basename "$ART")" = release ] && [ "$(basename "$(dirname "$ART")")" = templates ]; then
  MIRROR="$ART";                                 KIND="templates/release directory"
else
  die "$ART is none of: a framework repo clone (plugins/coord/templates/release/), an installed coord plugin (templates/release/), or a templates/release directory itself"
fi

# A clone carries its own history; a published plugin copy does not. This is the one signal that
# separates "the repo's working tree" from "a copy of it someone shipped", and the scope caveat in
# the header turns on it, so it is reported, not inferred by the reader.
if [ "$KIND" = "framework repo clone" ] && [ ! -e "$ART/.git" ]; then
  KIND="framework repo layout (NO .git — not a clone; provenance unknown)"
fi

# ── the toolkit side has to be able to answer at all ──
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || die "$ROOT is not a git work tree — the tags a stamp is held against cannot be read"
[ -n "$(git -C "$ROOT" tag --list 'v*')" ] \
  || die "this checkout has no v* tags — a stamped copy cannot be held to the tag it claims (fetch tags first)"
WANT="$(tr -d '\n' < "$ROOT/VERSION")"

echo "framework-mirror-check: read $KIND"
echo "framework-mirror-check:      $MIRROR"
echo "framework-mirror-check: toolkit $ROOT at VERSION $WANT"

# ── the derived population ──
members=""
for f in "$ROOT"/bin/*; do
  [ -f "$f" ] || continue
  name="${f##*/}"
  [ -f "$MIRROR/$name" ] || continue
  members="$members$name"$'\n'
done
members="$(printf '%s' "$members" | sed '/^$/d')"

[ -n "$members" ] || die "no file under $MIRROR shares a basename with anything in $ROOT/bin — nothing was compared, so nothing is in step (rc 2, deliberately NOT a pass)"

rc=0
judged=0
while IFS= read -r name; do
  copy="$MIRROR/$name"

  # ── DOES THIS REPO CLAIM TO BE THIS FILE'S UPSTREAM? Asked FIRST, because every verdict below
  # assumes the answer is yes, and for one shipped file it is NO.
  # The toolkit's own stamp IS that claim: `VERSIONING.md` rule 1 puts `ABTK_TOOL_VERSION` in a
  # bin so a COPY of it can name the toolkit release it is — a statement only the file's upstream
  # is in a position to make, and one this repo re-stamps at every release. A file present in
  # BOTH trees that this repo does NOT stamp is therefore one this repo did not author.
  # `bin/card-completeness` is the live case (card#10176): it is adopted FROM the framework, so
  # the mirror runs the other way and every remedy below — "re-sync it from a toolkit tag" — is
  # backwards for it. Reported so it is never silently dropped, and NOT judged, because a verdict
  # this check is not entitled to reach is worse than no verdict (canon #7: name what you cannot
  # verify). ⛔ It is also not counted as in-step: see the `judged` guard after the loop.
  if ! command grep -qE "^ABTK_TOOL_VERSION=" "$ROOT/bin/$name"; then
    echo "  NOT-OURS      $name — in both trees, but this repo does not stamp it, so the toolkit does not claim to be its upstream; it is adopted FROM the framework, not mirrored INTO it. NOT judged here: this check only holds copies of files the toolkit authors, and its remedy would be backwards for this one. Nothing here says whether that copy is in step."
    continue
  fi
  judged=$((judged + 1))

  # Read the stamp TEXTUALLY. This never executes the far end's file: running foreign code to ask
  # it its version would make the answer the file's to choose, and this is a check ON that file.
  stamps="$(command grep -cE "^ABTK_TOOL_VERSION=" "$copy" || true)"
  if [ "$stamps" = 0 ]; then
    echo "  UNSTAMPED     $name — carries no ABTK_TOOL_VERSION line, so it names no toolkit release and CANNOT be held to any tag. It is older than the stamp; that is not a version and is not guessed at. Re-sync it from a toolkit tag that carries one."
    rc=1; continue
  fi
  if [ "$stamps" != 1 ]; then
    echo "  UNSTAMPED     $name — carries $stamps ABTK_TOOL_VERSION lines, not exactly one; no single release is named."
    rc=1; continue
  fi
  line="$(command grep -E "^ABTK_TOOL_VERSION=" "$copy")"
  if [[ "$line" =~ ^ABTK_TOOL_VERSION=\'([^\']*)\'$ ]]; then
    claim="${BASH_REMATCH[1]}"
  else
    echo "  UNSTAMPED     $name — stamp line is not spelled ABTK_TOOL_VERSION='<version>': $line"
    rc=1; continue
  fi

  tag="v$claim"
  if ! git -C "$ROOT" rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
    echo "  UNKNOWN-TAG   $name — claims $tag, which this checkout does not have. Fetch tags, or the copy names a release this repo never cut."
    rc=1; continue
  fi

  if git -C "$ROOT" show "$tag:bin/$name" 2>/dev/null | diff -q - "$copy" >/dev/null 2>&1; then
    if [ "$claim" = "$WANT" ]; then
      echo "  IN-STEP       $name — byte-identical to $tag:bin/$name, and $tag is this checkout's VERSION."
    else
      behind="$(git -C "$ROOT" tag --list 'v*' --sort=v:refname | sed -n "/^$tag\$/,\$p" | sed '1d' | wc -l | tr -d ' ')"
      echo "  STALE         $name — byte-identical to the $tag it claims, but VERSION is $WANT; $behind tag(s) landed after it. Re-sync from v$WANT."
      rc=1
    fi
  else
    n="$(git -C "$ROOT" show "$tag:bin/$name" 2>/dev/null | diff - "$copy" | command grep -c '^[<>]' || true)"
    echo "  DIVERGED      $name — claims $tag but is NOT $tag:bin/$name ($n differing line(s)). Either it was hand-edited in the mirror (which README.md forbids: framework-side needs land as toolkit PRs first) or it carries declared MIRROR NOTE divergences — read them before acting."
    rc=1
  fi
done <<< "$members"

# An intersection that is entirely files this repo does not author is NOT a clean bill of health
# — it is the same empty measurement the population guard above refuses, reached one step later.
[ "$judged" -gt 0 ] \
  || die "every file shared with $MIRROR is one this repo does not author, so NOTHING this check is entitled to judge was compared (rc 2, deliberately NOT a pass)"

if [ "$rc" = 0 ]; then
  echo "framework-mirror-check: OK — every mirrored file this repo authors is in step at v$WANT"
else
  echo "framework-mirror-check: NOT IN STEP — see the per-file verdicts above" >&2
fi
exit "$rc"
