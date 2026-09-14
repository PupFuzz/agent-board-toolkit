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
# `ABTK_TOOL_VERSION=`, UNION every file in bin/ naming `--tool-version` on a line before any `#`.
# The second half is what stops a bin answering the flag some other way — most likely by reading
# a VERSION file relative to itself, which is right in a checkout and wrong in every copy. The
# PRESENCE witness is `release-pr-body`: an empty derivation cannot pass.
#
# PER MEMBER, each a separate violation:
#   * exactly one stamp line, spelled `ABTK_TOOL_VERSION='<value>'`;
#   * <value> equal to VERSION (trailing newline stripped, as VERSIONING.md tells consumers to);
#   * the file names `--tool-version` (a stamp nothing prints is not a surface);
#   * `<bin> --tool-version`, run from a directory that is not a repo, exits 0 with stdout
#     exactly `<VERSION>\n` and stderr empty.
#
# WHAT A GREEN RUN PROVES — and no more: that every member's stamp and answer equal VERSION on
# THIS tree. Nothing about copies already in the field, which carry whatever they were stamped
# with (or, older than the flag, nothing at all).
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"

ROOT="$(cd "$HERE/.." && pwd)"
_mktmp_scratch
mkdir -p "$TMP/nowhere"

# _members <root> — the derived population, one bin/ basename per line.
_members() {
  local f
  for f in "$1"/bin/*; do
    [ -f "$f" ] || continue
    if command grep -qE '^ABTK_TOOL_VERSION=' "$f" \
       || command grep -qE -- '^[^#]*--tool-version' "$f"; then
      printf '%s\n' "${f##*/}"
    fi
  done
}

# _violations <root> — one line per violation, naming the file. Prints nothing when clean.
_violations() {
  local root="$1" want name f stamps val rc
  want="$(tr -d '\n' < "$root/VERSION")"
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
    rc=0; (cd "$TMP/nowhere" && "$f" --tool-version) >"$TMP/out" 2>"$TMP/err" || rc=$?
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

echo "== precondition: the probe directory is not inside a git work tree =="
if git -C "$TMP/nowhere" rev-parse --git-dir >/dev/null 2>&1; then
  bad "scratch dir resolves to a git repo — the 'no checkout' leg would not measure a copy"
else
  ok "scratch dir is outside every git work tree"
fi

echo "== the real tree: every stamp and every --tool-version answer equals VERSION =="
members="$(_members "$ROOT")"
eq "presence witness: release-pr-body is a member" "true" "$(has_line release-pr-body "$members")"
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
eq "reds for carrying no stamp"       "true" "$(has 'reads-a-path: carries 0 ABTK_TOOL_VERSION= lines' "$(_violations "$fx")")"

echo "== CONTROL: a stamp nothing prints, and an answer that is not the stamp =="
fx="$(_fixture stamp-only)"
printf "#!/usr/bin/env bash\nABTK_TOOL_VERSION='%s'\n" "$(tr -d '\n' < "$ROOT/VERSION")" > "$fx/bin/stamp-only"
chmod +x "$fx/bin/stamp-only"
eq "stamp without the flag reds"      "true" "$(has 'stamp-only: stamped, but names no --tool-version flag' "$(_violations "$fx")")"
printf "#!/usr/bin/env bash\nABTK_TOOL_VERSION='%s'\ncase \"\${1:-}\" in --tool-version) echo other;; esac\n" "$(tr -d '\n' < "$ROOT/VERSION")" > "$fx/bin/stamp-only"
eq "an answer other than the stamp reds" "true" "$(has "stamp-only: --tool-version printed 'other" "$(_violations "$fx")")"

_summary "tool-version-stamp-selftest"
