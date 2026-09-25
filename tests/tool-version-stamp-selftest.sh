#!/usr/bin/env bash
# tool-version-stamp-selftest.sh — the drift guard for the `ABTK_TOOL_VERSION` stamp a bin/ file
# embeds so that `<bin> --tool-version` can answer from a copy with no checkout beside it.
#
# WHY A STAMP NEEDS A GUARD. VERSION stays the single source of the toolkit's version
# (VERSIONING.md rule 1). A copied file cannot read it, so a bin answering `--tool-version`
# carries the value inline — a restatement, and a restatement with no check drifts. The failure
# it would produce is the one the flag exists to end: a copy reporting a version it is not. The
# release PR is where VERSION moves, and CI runs this on every pull_request, so a release that
# bumps VERSION without re-stamping reds here instead of shipping a stale stamp.
#
# THE POPULATION IS DERIVED, never listed: every file in bin/ with a line-initial
# `ABTK_TOOL_VERSION=`, UNION every file in bin/ naming `--tool-version` on a line before any `#`,
# UNION every `bin/<name>` a composite action (`*/action.yml`) runs. The second leg makes a bin
# that answers the flag WITHOUT a stamp a member, so it reds for carrying none. The third is the
# VENDORED-BY-COPY set (card#10367): what an action runs is what INSTALL.md §6b tells a
# non-Actions consumer to copy, and a copy that cannot say what it is cannot be told from a stale
# one — so a tool joining an action is a member on that day, stamped or not, and reds until it is.
# That leg is read from the action files, never from a list, and never from the stamps (a
# population built from the stamped files cannot find the unstamped one). The PRESENCE witnesses
# are `release-pr-body` (stamp leg) and a non-empty action leg: an empty derivation cannot pass.
#
# PER MEMBER, each a separate violation:
#   * exactly one stamp line, spelled `ABTK_TOOL_VERSION='<value>'`;
#   * <value> equal to VERSION (trailing newline stripped, as VERSIONING.md tells consumers to);
#   * the file names `--tool-version` (a stamp nothing prints is not a surface);
#   * `--tool-version`, run on a COPY of the member file alone — in a scratch box outside every git
#     work tree, with a decoy VERSION beside the copy's bin/ and in the directory it runs from —
#     exits 0 with stdout exactly `<VERSION>\n` and stderr empty. The decoy is VERSION with a
#     suffix, so it can never equal VERSION. Run in place instead, a stamped bin that reads
#     `$(dirname "$0")/../VERSION` before its stamp prints the right answer from the checkout and
#     the wrong one from every copy; from the box, that read reds.
#
# WHAT A GREEN RUN PROVES — and no more: that every member's stamp and answer equal VERSION on
# THIS tree, and that the answer does not come from a VERSION file beside the file or in its cwd.
# The copy carries only the member, so a member must answer before loading anything beside it.
# A read from an absolute path (a toolkit checkout under $HOME, say) is NOT ruled out. Nothing
# about copies already in the field, which carry whatever they were stamped with (or, older than
# the flag, nothing at all).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

ROOT="$(cd "$HERE/.." && pwd)"
_mktmp_scratch

# _action_bins <root> — every bin/ basename a composite action at <root>/*/action.yml names.
# Only names that exist in <root>/bin/ are kept, so a match inside a comment or a description that
# names no real file cannot mint a member that then reds as unrunnable.
_action_bins() {
  local a
  for a in "$1"/*/action.yml; do
    [ -f "$a" ] || continue
    command grep -oE 'bin/[A-Za-z0-9_.-]+' "$a" || true
  done | sed 's#^bin/##' | sort -u | while IFS= read -r n; do
    [ -f "$1/bin/$n" ] && printf '%s\n' "$n"
  done
  return 0
}

# _members <root> — the derived population, one bin/ basename per line.
_members() {
  local f
  {
    for f in "$1"/bin/*; do
      [ -f "$f" ] || continue
      if command grep -qE '^ABTK_TOOL_VERSION=' "$f" \
         || command grep -qE -- '^[^#]*--tool-version' "$f"; then
        printf '%s\n' "${f##*/}"
      fi
    done
    _action_bins "$1"
  } | sort -u
}

# _violations <root> — one line per violation, naming the file. Prints nothing when clean.
# Every answer is taken from a copy in a fresh box under $TMP whose VERSION files hold a decoy.
_violations() {
  local root="$1" want decoy box name f stamps val rc
  want="$(tr -d '\n' < "$root/VERSION")"
  decoy="$want-decoy"
  box="$(mktemp -d "$TMP/box.XXXXXX")"
  mkdir -p "$box/bin" "$box/cwd"
  printf '%s\n' "$decoy" > "$box/VERSION"
  printf '%s\n' "$decoy" > "$box/cwd/VERSION"
  while IFS= read -r name; do
    f="$root/bin/$name"
    stamps="$(command grep -cE '^ABTK_TOOL_VERSION=' "$f" || true)"
    if [ "$stamps" != 1 ]; then
      printf "%s: carries %s ABTK_TOOL_VERSION= lines, not exactly one\n" "$name" "$stamps"
    else
      val="$(command grep -E '^ABTK_TOOL_VERSION=' "$f")"
      if [[ "$val" =~ ^ABTK_TOOL_VERSION=\'([^\']*)\'$ ]]; then
        [ "${BASH_REMATCH[1]}" = "$want" ] \
          || printf "%s: stamp is '%s' but VERSION is '%s' — re-stamp it in the release PR (VERSIONING.md § Release flow)\n" "$name" "${BASH_REMATCH[1]}" "$want"
      else
        printf "%s: stamp line is not spelled ABTK_TOOL_VERSION='<version>': %s\n" "$name" "$val"
      fi
    fi
    command grep -qE -- '^[^#]*--tool-version' "$f" \
      || printf '%s: stamped, but names no --tool-version flag\n' "$name"
    cp "$f" "$box/bin/$name"
    rc=0; (cd "$box/cwd" && "$box/bin/$name" --tool-version) >"$TMP/out" 2>"$TMP/err" || rc=$?
    [ "$rc" = 0 ] || printf '%s: --tool-version exited %s\n' "$name" "$rc"
    printf '%s\n' "$want" > "$TMP/want"
    cmp -s "$TMP/out" "$TMP/want" \
      || printf "%s: --tool-version printed '%s', not exactly '%s' and a newline\n" "$name" "$(head -c 200 "$TMP/out")" "$want"
    [ ! -s "$TMP/err" ] || printf "%s: --tool-version wrote to stderr: %s\n" "$name" "$(head -c 200 "$TMP/err")"
  done < <(_members "$root")
}

# _fixture <name> — a scratch toolkit root holding this tree's VERSION and release-pr-body.
_fixture() {
  local fx="$TMP/$1"
  mkdir -p "$fx/bin"
  cp "$ROOT/VERSION" "$fx/VERSION"
  cp "$ROOT/bin/release-pr-body" "$fx/bin/release-pr-body"
  printf '%s' "$fx"
}

echo "== precondition: the scratch dir holding every copy is not inside a git work tree =="
if git -C "$TMP" rev-parse --git-dir >/dev/null 2>&1; then
  bad "scratch dir resolves to a git repo — the 'no checkout' leg would not measure a copy"
else
  ok "scratch dir is outside every git work tree"
fi

echo "== the real tree: every stamp and every --tool-version answer equals VERSION =="
members="$(_members "$ROOT")"
eq "presence witness: release-pr-body is a member" "true" "$(has_line release-pr-body "$members")"
abins="$(_action_bins "$ROOT")"
eq "presence witness: the composite actions name at least one bin/ file" "false" "$([ -z "$abins" ] && echo true || echo false)"
echo "population: $(printf '%s' "$members" | tr '\n' ' ')"
v="$(_violations "$ROOT")"
eq "no violations on this tree" "" "$v"

echo "== CONTROL: VERSION moves and the stamp does not — the release-PR shape =="
fx="$(_fixture version-bumped)"
printf '9.9.9\n' > "$fx/VERSION"
v="$(_violations "$fx")"
eq "reds naming the stale stamp"      "true" "$(has "release-pr-body: stamp is '$(tr -d '\n' < "$ROOT/VERSION")' but VERSION is '9.9.9'" "$v")"
eq "…and the answer that disagrees"   "true" "$(has 'release-pr-body: --tool-version printed' "$v")"

echo "== CONTROL: the stamp moves and VERSION does not =="
fx="$(_fixture stamp-edited)"
sed -i "s/^ABTK_TOOL_VERSION=.*/ABTK_TOOL_VERSION='0.0.1'/" "$fx/bin/release-pr-body"
v="$(_violations "$fx")"
eq "reds naming the edited stamp"     "true" "$(has "stamp is '0.0.1'" "$v")"

echo "== CONTROL: a malformed or duplicated stamp line =="
fx="$(_fixture stamp-dq)"
sed -i "s/^ABTK_TOOL_VERSION=.*/ABTK_TOOL_VERSION=\"$(tr -d '\n' < "$ROOT/VERSION")\"/" "$fx/bin/release-pr-body"
eq "double-quoted spelling reds"      "true" "$(has 'stamp line is not spelled' "$(_violations "$fx")")"
fx="$(_fixture stamp-twice)"
sed -i "0,/^ABTK_TOOL_VERSION=.*/s//&\n&/" "$fx/bin/release-pr-body"
eq "a second stamp line reds"         "true" "$(has 'carries 2 ABTK_TOOL_VERSION= lines' "$(_violations "$fx")")"

echo "== CONTROL: a bin answering --tool-version WITHOUT a stamp is a member, and reds =="
fx="$(_fixture unstamped-flag)"
cat > "$fx/bin/reads-a-path" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in --tool-version) tr -d '\n' < "$(dirname "$0")/../VERSION"; echo;; esac
SH
chmod +x "$fx/bin/reads-a-path"
eq "derived as a member"              "true" "$(has_line reads-a-path "$(_members "$fx")")"
v="$(_violations "$fx")"
eq "reds for carrying no stamp"       "true" "$(has 'reads-a-path: carries 0 ABTK_TOOL_VERSION= lines' "$v")"
eq "…and for answering from the decoy" "true" "$(has "reads-a-path: --tool-version printed '$(tr -d '\n' < "$ROOT/VERSION")-decoy'" "$v")"

echo "== CONTROL: a STAMPED bin that answers from a VERSION beside itself before its stamp =="
# Right in a checkout, wrong in every copy: the shape only a run from a copy can see.
fx="$(_fixture path-first)"
INJ='  [ -f "$(dirname "$0")/../VERSION" ] && { tr -d '"'\\n'"' < "$(dirname "$0")/../VERSION"; echo; exit 0; }' \
  awk '{ print } /^if \[ "\$TOOL_VERSION_ONLY" = 1 \]; then$/ { print ENVIRON["INJ"]; n++ } END { exit n != 1 }' \
  "$ROOT/bin/release-pr-body" > "$fx/bin/release-pr-body" && rc=0 || rc=$?
eq "premise: the relative read was injected exactly once" "0" "$rc"
eq "premise: in place, the mutant prints VERSION"  "$(tr -d '\n' < "$ROOT/VERSION")" "$( (cd "$TMP" && "$fx/bin/release-pr-body" --tool-version) 2>&1 )"
eq "from a copy, reds naming the member and the decoy" "true" "$(has "release-pr-body: --tool-version printed '$(tr -d '\n' < "$ROOT/VERSION")-decoy'" "$(_violations "$fx")")"

echo "== CONTROL: a stamp nothing prints, and an answer that is not the stamp =="
fx="$(_fixture stamp-only)"
printf "#!/usr/bin/env bash\nABTK_TOOL_VERSION='%s'\n" "$(tr -d '\n' < "$ROOT/VERSION")" > "$fx/bin/stamp-only"
chmod +x "$fx/bin/stamp-only"
eq "stamp without the flag reds"      "true" "$(has 'stamp-only: stamped, but names no --tool-version flag' "$(_violations "$fx")")"
printf "#!/usr/bin/env bash\nABTK_TOOL_VERSION='%s'\ncase \"\${1:-}\" in --tool-version) echo other;; esac\n" "$(tr -d '\n' < "$ROOT/VERSION")" > "$fx/bin/stamp-only"
eq "an answer other than the stamp reds" "true" "$(has "stamp-only: --tool-version printed 'other" "$(_violations "$fx")")"

echo "== CONTROL: a tool a composite action runs, carrying NO stamp and NO flag, is a member and reds =="
# The card#10367 shape: a tool vendored by copy that cannot say what it is. The first two legs
# cannot see it (it names neither the stamp nor the flag); only the action leg can.
fx="$(_fixture unstamped-action-tool)"
cat > "$fx/bin/new-release-tool" <<'SH'
#!/usr/bin/env bash
echo "unknown arg '$1'" >&2; exit 2
SH
chmod +x "$fx/bin/new-release-tool"
eq "premise: invisible to the stamp and flag legs" "false" \
   "$(command grep -qE -e '^ABTK_TOOL_VERSION=' -e '^[^#]*--tool-version' "$fx/bin/new-release-tool" && echo true || echo false)"
eq "control: NOT a member while no action names it" "false" "$(has_line new-release-tool "$(_members "$fx")")"
eq "control: and the fixture is clean without it" "" "$(_violations "$fx")"
mkdir -p "$fx/new-action"
printf 'runs:\n  using: composite\n  steps:\n    - run: "$GITHUB_ACTION_PATH/../bin/new-release-tool"\n' > "$fx/new-action/action.yml"
eq "an action naming it makes it a member" "true" "$(has_line new-release-tool "$(_members "$fx")")"
v="$(_violations "$fx")"
eq "reds for carrying no stamp"          "true" "$(has 'new-release-tool: carries 0 ABTK_TOOL_VERSION= lines' "$v")"
eq "…for naming no flag"                  "true" "$(has 'new-release-tool: stamped, but names no --tool-version flag' "$v")"
eq "…and for the copy not answering"      "true" "$(has 'new-release-tool: --tool-version exited 2' "$v")"
eq "control: an action naming a bin/ path that is not a file mints no member" "false" \
   "$(printf '# see bin/no-such-tool\n' >> "$fx/new-action/action.yml"; has_line no-such-tool "$(_members "$fx")")"

_summary "tool-version-stamp-selftest"
