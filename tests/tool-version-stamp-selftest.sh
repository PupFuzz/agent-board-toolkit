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
# UNION the VENDORED-BY-COPY set (card#10367): the action-named bins, closed over the siblings
# each launches literally from its own directory. That set is read in two steps, never from a list
# and never from the stamps (a population built from the stamped files cannot find the unstamped
# one):
#   1. every `bin/<name>` NAMED anywhere in a `*/action.yml` that is a file in bin/ — a superset
#      of what the actions run (a description naming a tool counts too);
#   2. closed over `_launched`: for a file with a line holding `dirname` and, after it, `$0`,
#      `BASH_SOURCE` or `__file__`, every other bin/ file written as a `/<name>` segment on a
#      non-comment line.
# THE REACH OF STEP 2 — the one statement of it; other docs point here rather than restate it.
# Claimed only as far as a control below pins it:
#   MEMBERS: a literal `/<sibling>` launch under `dirname "$0"`, `dirname "${BASH_SOURCE[0]}"`,
#     and python `os.path.dirname(...__file__...)`;
#   KNOWN NON-MEMBERS: a sibling only mentioned (no `/` segment); a literal launch from a file
#     with no `dirname` self-dir; a sibling name held in a variable; a self-dir resolved by
#     `${BASH_SOURCE[0]%/*}`, `realpath "$0"` or `readlink -f "$0"` without `dirname`.
# A known non-member is not held to the flag, and nothing reds or prints for it.
# The presence witnesses are `release-pr-body` (stamp leg) and a non-empty action leg: an empty
# derivation cannot pass.
#
# PER MEMBER, each a separate violation:
#   * exactly one stamp line, spelled `ABTK_TOOL_VERSION='<value>'`;
#   * <value> equal to VERSION (trailing newline stripped, as VERSIONING.md tells consumers to);
#   * the file names `--tool-version` (a stamp nothing prints is not a surface);
#   * `--tool-version`, run on a COPY of the member file alone — in a scratch box outside every git
#     work tree, with a decoy VERSION beside the copy's bin/ and in the directory it runs from, and
#     with `jq`, `curl` and `git` absent from PATH (the question must not need the tool's runtime
#     dependencies: a host that lacks one still gets its answer) — exits 0 with stdout exactly
#     `<VERSION>\n` and stderr empty. The decoy is VERSION with a suffix, so it can never equal
#     VERSION. Run in place instead, a stamped bin that reads `$(dirname "$0")/../VERSION`
#     before its stamp prints the right answer from the checkout and the wrong one from every
#     copy; from the box, that read reds.
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

# NODEPS — a PATH holding every command on this PATH EXCEPT jq, curl and git, so a member that
# checks for its runtime dependencies before answering `--tool-version` reds. Links, first match
# per name wins, which is the lookup PATH itself does.
NODEPS="$TMP/nodeps"; mkdir -p "$NODEPS"
IFS=: read -ra _pdirs <<< "$PATH"
for _d in "${_pdirs[@]}"; do
  [ -d "$_d" ] || continue
  for _e in "$_d"/*; do
    _n="${_e##*/}"
    case "$_n" in jq|curl|git) continue ;; esac
    [ -x "$_e" ] && [ ! -d "$_e" ] && [ ! -e "$NODEPS/$_n" ] && ln -s "$_e" "$NODEPS/$_n"
  done
done

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

# _launched <root> <name> — the bin/ siblings <root>/bin/<name> launches from its own directory:
# only for a file matching `dirname` of `$0`/`BASH_SOURCE`/`__file__`, and only a name written
# literally as any `/<name>` segment on a non-comment line that is a regular file in <root>/bin/
# other than itself. Reach: header, THE REACH OF STEP 2.
_launched() {
  local f="$1/bin/$2"
  command grep -qE 'dirname.*(\$0|BASH_SOURCE|__file__)' "$f" || return 0
  command grep -vE '^[[:space:]]*#' "$f" | command grep -oE '/[A-Za-z0-9_][A-Za-z0-9._-]*' \
    | sed 's#^/##' | sort -u | while IFS= read -r n; do
      [ "$n" != "$2" ] && [ -f "$1/bin/$n" ] && printf '%s\n' "$n"
    done
  return 0
}

# _vendored <root> — _action_bins, closed over _launched. A worklist, so a sibling's own
# siblings join too; each name is expanded once, so a launch cycle terminates.
_vendored() {
  local -A seen=(); local -a work; local n s
  mapfile -t work < <(_action_bins "$1")
  while [ "${#work[@]}" -gt 0 ]; do
    n="${work[0]}"; work=("${work[@]:1}")
    [ -z "${seen[$n]:-}" ] || continue
    seen[$n]=1; printf '%s\n' "$n"
    while IFS= read -r s; do work+=("$s"); done < <(_launched "$1" "$n")
  done
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
    _vendored "$1"
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
    rc=0; (cd "$box/cwd" && PATH="$NODEPS" "$box/bin/$name" --tool-version) >"$TMP/out" 2>"$TMP/err" || rc=$?
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

echo "== CONTROL: an unstamped sibling an action-run tool LAUNCHES from its own directory is a member and reds =="
# Named by no action, carrying no stamp and no flag: only the launch leg can see it. The launcher
# is itself clean (stamped, answers from its copy), so every violation below is the sibling's.
fx="$(_fixture launched-sibling)"
V="$(tr -d '\n' < "$ROOT/VERSION")"
cat > "$fx/bin/launcher-tool" <<SH
#!/usr/bin/env bash
ABTK_TOOL_VERSION='$V'
case "\${1:-}" in --tool-version) printf '%s\\n' "\$ABTK_TOOL_VERSION"; exit 0;; esac
echo "see helper-tool --help for the options"
SH
cat > "$fx/bin/helper-tool" <<'SH'
#!/usr/bin/env bash
echo "unknown arg '$1'" >&2; exit 2
SH
chmod +x "$fx/bin/launcher-tool" "$fx/bin/helper-tool"
mkdir -p "$fx/launch-action"
printf 'runs:\n  using: composite\n  steps:\n    - run: "$GITHUB_ACTION_PATH/../bin/launcher-tool"\n' > "$fx/launch-action/action.yml"
eq "premise: the launcher is a member" "true" "$(has_line launcher-tool "$(_members "$fx")")"
eq "control: a sibling only MENTIONED in a message (no path segment) is NOT a member" "false" \
   "$(has_line helper-tool "$(_members "$fx")")"
eq "control: and the fixture is clean" "" "$(_violations "$fx")"
printf 'HERE="$(cd "$(dirname "$0")" && pwd)"\nexec "$HERE/helper-tool" "$@"\n' >> "$fx/bin/launcher-tool"
eq "a sibling the launcher execs from its own dir is a member" "true" "$(has_line helper-tool "$(_members "$fx")")"
v="$(_violations "$fx")"
eq "reds for carrying no stamp"     "true" "$(has 'helper-tool: carries 0 ABTK_TOOL_VERSION= lines' "$v")"
eq "…and for the copy not answering" "true" "$(has 'helper-tool: --tool-version exited 2' "$v")"
eq "…and only the sibling reds"      "false" "$(has 'launcher-tool:' "$v")"
eq "control: the same launch from a file that never resolves its own dir mints no member" "false" \
   "$(sed -i '/dirname/d' "$fx/bin/launcher-tool"; has_line helper-tool "$(_members "$fx")")"

echo "== KNOWN NON-MEMBERS: launches the launch leg cannot see (its stated blind spots) =="
# Each launcher below really does run helper-tool from its own directory, and helper-tool is NOT
# made a member. If the predicate widens to see one, it reds and the header's THE REACH OF STEP 2
# is owed an edit in the same change.
fx="$(_fixture blind-spots)"
cat > "$fx/bin/helper-tool" <<'SH'
#!/usr/bin/env bash
echo "unknown arg '$1'" >&2; exit 2
SH
cat > "$fx/bin/launcher-tool" <<SH
#!/usr/bin/env bash
ABTK_TOOL_VERSION='$V'
case "\${1:-}" in --tool-version) printf '%s\\n' "\$ABTK_TOOL_VERSION"; exit 0;; esac
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
tool=helper-tool
exec "\$HERE/\$tool" "\$@"
SH
chmod +x "$fx/bin/launcher-tool" "$fx/bin/helper-tool"
mkdir -p "$fx/launch-action"
printf 'runs:\n  using: composite\n  steps:\n    - run: "$GITHUB_ACTION_PATH/../bin/launcher-tool"\n' \
  > "$fx/launch-action/action.yml"
eq "premise: the launcher is a member" "true" "$(has_line launcher-tool "$(_members "$fx")")"
eq "premise: run, the launcher really reaches helper-tool" "true" \
   "$(has "unknown arg 'x'" "$("$fx/bin/launcher-tool" x 2>&1 || true)")"
eq "blind spot: a sibling name held in a variable is NOT a member" "false" \
   "$(has_line helper-tool "$(_members "$fx")")"
sed -i 's#^HERE=.*#HERE="${BASH_SOURCE[0]%/*}"#; s#^tool=.*##; s#"\$HERE/\$tool"#"$HERE/helper-tool"#' \
  "$fx/bin/launcher-tool"
eq "premise: the \${BASH_SOURCE[0]%/*} launcher really reaches helper-tool" "true" \
   "$(has "unknown arg 'x'" "$("$fx/bin/launcher-tool" x 2>&1 || true)")"
eq "blind spot: a literal sibling under a \${BASH_SOURCE[0]%/*} self-dir is NOT a member" "false" \
   "$(has_line helper-tool "$(_members "$fx")")"
for _res in realpath 'readlink -f'; do
  sed -i -e '/^SELF=/d' -e "s#^HERE=.*#SELF=\"\$($_res \"\$0\")\"\nHERE=\"\${SELF%/*}\"#" "$fx/bin/launcher-tool"
  eq "premise: the $_res self-dir launcher really reaches helper-tool" "true" \
     "$(has "unknown arg 'x'" "$("$fx/bin/launcher-tool" x 2>&1 || true)")"
  eq "blind spot: a literal sibling under a $_res self-dir (no dirname) is NOT a member" "false" \
     "$(has_line helper-tool "$(_members "$fx")")"
done
sed -i -e '/^SELF=/d' -e 's#^HERE=.*#HERE="$(dirname "${BASH_SOURCE[0]}")"#' "$fx/bin/launcher-tool"
eq "control: the same literal launch under a dirname self-dir IS a member" "true" \
   "$(has_line helper-tool "$(_members "$fx")")"

echo "== CONTROL: a python launcher resolving its dir via dirname of __file__ makes its sibling a member =="
fx="$(_fixture py-launcher)"
cat > "$fx/bin/helper-tool" <<'SH'
#!/usr/bin/env bash
echo "unknown arg '$1'" >&2; exit 2
SH
cat > "$fx/bin/py-launcher" <<'PY'
#!/usr/bin/env python3
import os, sys
here = os.path.dirname(os.path.abspath(__file__))
os.execv(here + "/helper-tool", [here + "/helper-tool"] + sys.argv[1:])
PY
chmod +x "$fx/bin/py-launcher" "$fx/bin/helper-tool"
mkdir -p "$fx/py-action"
printf 'runs:\n  using: composite\n  steps:\n    - run: "$GITHUB_ACTION_PATH/../bin/py-launcher"\n' > "$fx/py-action/action.yml"
eq "premise: run, the python launcher really reaches helper-tool" "true" \
   "$(has "unknown arg 'x'" "$("$fx/bin/py-launcher" x 2>&1 || true)")"
eq "a sibling the python launcher execs from its __file__ dir is a member" "true" \
   "$(has_line helper-tool "$(_members "$fx")")"

echo "== CONTROL: a stamped member that checks for jq BEFORE answering --tool-version reds =="
fx="$(_fixture deps-first)"
cat > "$fx/bin/deps-first" <<SH
#!/usr/bin/env bash
ABTK_TOOL_VERSION='$V'
command -v jq >/dev/null || exit 2
case "\${1:-}" in --tool-version) printf '%s\\n' "\$ABTK_TOOL_VERSION"; exit 0;; esac
SH
chmod +x "$fx/bin/deps-first"
eq "premise: NODEPS carries no jq" "false" "$(PATH="$NODEPS" command -v jq >/dev/null && echo true || echo false)"
eq "premise: with jq on PATH it answers VERSION" "$V" "$("$fx/bin/deps-first" --tool-version)"
eq "reds: the copy exits 2 with jq absent" "true" \
   "$(has 'deps-first: --tool-version exited 2' "$(_violations "$fx")")"

echo "== the launch leg on the real tree =="
eq "presence witness: promote-released-cards launches card-completeness" "true" \
   "$(has_line card-completeness "$(_launched "$ROOT" promote-released-cards)")"

_summary "tool-version-stamp-selftest"
