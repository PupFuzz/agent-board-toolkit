#!/usr/bin/env bash
# tests/shellcheck-pin-selftest.sh — the analyser the shellcheck gate runs is DECLARED, is the one
# that actually runs, and is never silently substituted.
#
# (The `tests/` prefix on that line is load-bearing, not a stray: a comment whose first word is
# `shellcheck…` is read as a shellcheck DIRECTIVE, so this file following the repo's bare-basename
# header convention is SC1073 — an unparseable directive, at ERROR severity, on both 0.9.0 and
# 0.11.0. Caught by the gate itself while this file was being written.)
#
# WHY THIS FILE EXISTS (card#6619). The gate ran `ubuntu-latest`'s preinstalled shellcheck and
# printed no version, so the verdict came from a program the log did not name and the repo did not
# choose. The two ends of that drift disagree at ERROR severity — measured, and recorded with the
# reproduction in `.shellcheck-version`. `bin/_shellcheck-pinned` closes it, and this file is what
# keeps it closed, on the two axes a green gate cannot see for itself:
#
#   1. THE CALL SITES. A pin held by one job is not a pin: ci.yml has three shellcheck call sites in
#      three jobs, and the two that analyse a GENERATED file drift exactly as silently as the one
#      that analyses the tree. Leg 2 derives every shellcheck invocation in every workflow's `run:`
#      bodies and requires each to go through the wrapper, so the N+1th job cannot re-mint the bare
#      call — the sibling audit, as a gate rather than as a memory.
#   2. THE SUBSTITUTION. The wrapper's whole value is that it REFUSES a shellcheck reporting some
#      other version rather than falling back to it. A fallback would restore the original defect
#      wearing the fix's name — a local "shellcheck clean" about a different program — and would do
#      it while every gate stayed green. Leg 3 drives each resolution arm with stub binaries and
#      asserts the refusals by rc AND by the absence of any evidence the wrong binary ran.
#
# NETWORK-FREE, INCLUDING THE DOWNLOAD ARM. CI takes the PATH arm today (the image ships the pinned
# version), so the download arm is the one nobody exercises until the day the image moves and it is
# the only thing standing between the gate and an unpinned analyser. It is driven here through a
# `curl` stub on PATH — the repo's own idiom (`_kb-api-stub-curl.sh`) — over a real .tar.xz built in
# the fixture, so the unpack, the sha256 verification and the post-unpack version check all run for
# real against bytes this file controls.
#
# WHAT A GREEN RUN HERE DOES NOT PROVE: that 0.9.0 is the RIGHT pin. That is a decision recorded in
# `.shellcheck-version` with its measurement; this file holds the mechanism, not the choice. It also
# says nothing about the gate's severity or file population, which stay in ci.yml where the call
# sites own them.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$HERE/_gha-surface-lib.sh"

ROOT="$HERE/.."
WRAP="$ROOT/bin/_shellcheck-pinned"
PINFILE="$ROOT/.shellcheck-version"
WORKFLOWS="$ROOT/.github/workflows"
_need -x "$WRAP"
_need -r "$PINFILE"
_need -r "$WORKFLOWS" ".github/workflows"   # _need knows -r and -x only; a dir answers -r
command -v xz >/dev/null 2>&1 || { echo "selftest: xz not found (needed to build the .tar.xz fixture)" >&2; exit 1; }
_mktmp_scratch

# The asset key the wrapper derives from uname. Spelled here too because the FIXTURE has to name the
# platform it is pretending to publish for; the live pin file's own key is read from disk, not from
# this line.
ASSET="$(uname -s | tr '[:upper:]' '[:lower:]').$(uname -m)"

# ---------------------------------------------------------------------------
# Leg 1 — the pin is a declared, parseable fact, and it is declared exactly once.
# ---------------------------------------------------------------------------
echo "== leg 1: .shellcheck-version declares the version, and nothing else does =="
PINNED="$(awk '$1 == "version" { print $2; exit }' "$PINFILE")"
# A bash match rather than a pipe into `grep -q`: that idiom returns 141 under `pipefail` whenever
# the reader exits before the writer's last write, which is a random red (measured: 6 in 20000).
eq "the pin file names a version" "true" \
   "$([[ "$PINNED" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] && echo true || echo false)"
eq "the pin file carries a 64-hex sha256 for at least one asset" "true" \
   "$(awk '$1 == "asset" && $3 ~ /^[0-9a-f]{64}$/ { f = 1 } END { print (f ? "true" : "false") }' "$PINFILE")"

# The version must live in ONE place. A workflow that also spells it out is a second copy that goes
# stale in silence — the shape this whole card is about, re-minted in YAML.
eq "no workflow spells the pinned version out" "" \
   "$(command grep -rn -- "$PINNED" "$WORKFLOWS" || true)"

# ---------------------------------------------------------------------------
# Leg 2 — every shellcheck invocation in every workflow goes through the wrapper.
# ---------------------------------------------------------------------------
echo "== leg 2: no workflow runs a bare shellcheck =="

# _bare_shellcheck <workflows-dir> — `<file>:<job>: <line>` for every line of every step's `run:`
# body that invokes shellcheck as a COMMAND without going through the wrapper. Scoped to `run:`
# bodies on purpose: a step NAME or a job KEY saying "shellcheck" invokes nothing, and an inline
# `disable=` directive is a comment. The token match rejects any neighbour that makes it
# part of a longer word, which is what excludes `_shellcheck-pinned` itself — so the check reads the
# wrapper's NAME, and renaming the wrapper without updating a call site reds here rather than
# passing on a substring.
#
# The FILE population comes from `_gha_workflow_files` (tests/_gha-surface-lib.sh), which owns
# both accepted extensions for all three gates that ask this question — this one globbed them
# inline until card#7207's review found a third copy of the derivation with a narrower predicate.
# The directory stays a parameter, so the fixture tree below runs through the same derivation.
_bare_shellcheck() {
    local -a files=()
    mapfile -t files < <(_gha_workflow_files "$1")
    python3 - "${files[@]}" <<'PY'
import os, re, sys, yaml

TOKEN = re.compile(r'(?<![\w./-])shellcheck(?![\w-])')
out = []
for path in sys.argv[1:]:
    doc = yaml.safe_load(open(path)) or {}
    for job_name, job in (doc.get('jobs') or {}).items():
        for step in (job.get('steps') or []):
            run = step.get('run')
            if not run:
                continue
            for line in run.splitlines():
                if line.strip().startswith('#'):
                    continue
                if TOKEN.search(line):
                    out.append(f'{os.path.basename(path)}:{job_name}: {line.strip()}')
print('\n'.join(out))
PY
}

# Positive control FIRST — the live assertion is an assertion of ABSENCE, and a yaml parse that
# quietly yielded {} would satisfy it while reading nothing at all. Prove the walk reaches real
# `run:` bodies before trusting an empty answer from it.
mkdir -p "$TMP/wf-ctl"
cat > "$TMP/wf-ctl/bare.yml" <<'YML'
name: fixture
on: [pull_request]
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - name: shellcheck the tree
        run: |
          # shellcheck disable=SC1000 -- a directive is a comment, not an invocation
          shellcheck -S error bin/*
YML
cat > "$TMP/wf-ctl/pinned.yml" <<'YML'
name: fixture
on: [pull_request]
jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - name: shellcheck the tree
        run: ./bin/_shellcheck-pinned -S error bin/*
YML
ctl="$(_bare_shellcheck "$TMP/wf-ctl")"
eq "prove-it-can-fail: a bare shellcheck in a run: body is REPORTED" "true" \
   "$(has "bare.yml:gate: shellcheck -S error bin/*" "$ctl")"
eq "the WRAPPED sibling is not reported (witness: the walk read both files)" "false" \
   "$(has "pinned.yml" "$ctl")"
eq "a '# shellcheck' directive line is not read as an invocation" "false" \
   "$(has "disable=SC1000" "$ctl")"

eq "no workflow invokes shellcheck outside bin/_shellcheck-pinned" "" "$(_bare_shellcheck "$WORKFLOWS")"

# ---------------------------------------------------------------------------
# Leg 3 — resolution and refusal, driven end to end with stubs.
# ---------------------------------------------------------------------------
echo "== leg 3: the wrapper runs the pinned version, or refuses and says why =="

FAKEV=9.9.9   # deliberately a version no real shellcheck reports, so a stub can never be confused
              # with the box's own analyser and the PATH arm cannot pass by accident.

# _fake_sc <path> <version> — a stand-in analyser: it answers --version like shellcheck and, for any
# other argv, prints a marker that proves THIS binary is what ran and what it was handed.
_fake_sc() {
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then
    printf 'ShellCheck - shell script analysis tool\nversion: %s\n' "$2"
    exit 0
fi
printf 'RAN %s ARGS %s\n' "$2" "\$*"
EOF
    chmod +x "$1"
}

# _wrap <pin-file> <cache> <path-prefix-dir> [args...] — run the wrapper in a controlled
# environment; leaves rc in WRC, stdout in $TMP/o, stderr in $TMP/e. SHELLCHECK_PIN_BIN and
# STUB_SERVE ride in from the caller when a case needs them.
WRC=0
_wrap() {
    local pin="$1" cache="$2" pathdir="$3"; shift 3
    WRC=0
    env SHELLCHECK_PIN_FILE="$pin" SHELLCHECK_PIN_CACHE="$cache" PATH="$pathdir:$PATH" \
        "$WRAP" "$@" >"$TMP/o" 2>"$TMP/e" || WRC=$?
}

printf 'version %s\nasset   %s  %s\n' "$FAKEV" "$ASSET" "0000000000000000000000000000000000000000000000000000000000000000" \
    > "$TMP/pin-badsha"
printf 'version %s\n' "$FAKEV" > "$TMP/pin-noasset"
printf '# no version line here\n' > "$TMP/pin-noversion"

mkdir -p "$TMP/empty"

echo "-- 3a: an explicitly supplied binary of the pinned version is used, and the args reach it --"
_fake_sc "$TMP/bins/good" "$FAKEV"
SHELLCHECK_PIN_BIN="$TMP/bins/good" _wrap "$TMP/pin-noasset" "$TMP/cache-a" "$TMP/empty" -S error x.sh
eq "rc 0" "0" "$WRC"
eq "the pinned binary ran with the forwarded args" "true" "$(has "RAN $FAKEV ARGS -S error x.sh" "$(cat "$TMP/o")")"
eq "the banner names the version" "true" "$(has "shellcheck $FAKEV" "$(cat "$TMP/e")")"
eq "the banner names the binary that ran" "true" "$(has "$TMP/bins/good" "$(cat "$TMP/e")")"
eq "the banner is on stderr, not stdout" "false" "$(has "_shellcheck-pinned:" "$(cat "$TMP/o")")"

echo "-- 3b: a PATH shellcheck of the pinned version is used --"
_fake_sc "$TMP/path-good/shellcheck" "$FAKEV"
_wrap "$TMP/pin-noasset" "$TMP/cache-b" "$TMP/path-good" -S error x.sh
eq "rc 0" "0" "$WRC"
eq "the PATH binary ran" "true" "$(has "RAN $FAKEV ARGS -S error x.sh" "$(cat "$TMP/o")")"

echo "-- 3c: a WRONG-version binary is refused and NAMED, never fallen back to --"
_fake_sc "$TMP/path-bad/shellcheck" 1.2.3
_wrap "$TMP/pin-noasset" "$TMP/cache-c" "$TMP/path-bad" -S error x.sh
eq "rc 9 (the wrapper's own refusal, distinct from every shellcheck verdict)" "9" "$WRC"
eq "the refusal names what it found and what is pinned" "true" \
   "$(has "reports 1.2.3, pinned is $FAKEV" "$(cat "$TMP/e")")"
eq "the wrong-version binary did NOT run" "false" "$(has "RAN 1.2.3" "$(cat "$TMP/o")")"
eq "an unpinned platform asset is named as the way out" "true" "$(has "$ASSET" "$(cat "$TMP/e")")"

echo "-- 3c2: a candidate that is not shellcheck at all is rejected, not a crash --"
# The wrapper runs under `pipefail`, so a candidate that EXITS NON-ZERO on --version is the arm that
# takes it down rather than moving past it: it would die on the version probe, at some rc that is
# not the wrapper's own refusal code, with nothing said. What is asserted is therefore the rc AND
# that a diagnostic was produced — "it failed" is true of the defect too.
mkdir -p "$TMP/junk"
printf '#!/usr/bin/env bash\necho "not shellcheck" >&2\nexit 1\n' > "$TMP/junk/shellcheck"
chmod +x "$TMP/junk/shellcheck"
_wrap "$TMP/pin-noasset" "$TMP/cache-c2" "$TMP/junk" -S error x.sh
eq "rc 9, the wrapper's own refusal" "9" "$WRC"
eq "it says why, naming the pinned version" "true" "$(has "$FAKEV" "$(cat "$TMP/e")")"

echo "-- 3d/3e/3f/3g: the download arm, over a real tarball, through a curl stub --"
# The fixture the stub serves: upstream's layout, `shellcheck-v<ver>/shellcheck`, xz-compressed.
mkdir -p "$TMP/pkg/shellcheck-v$FAKEV"
_fake_sc "$TMP/pkg/shellcheck-v$FAKEV/shellcheck" "$FAKEV"
tar -cJf "$TMP/served.tar.xz" -C "$TMP/pkg" "shellcheck-v$FAKEV"
GOODSHA="$(sha256sum "$TMP/served.tar.xz" | awk '{print $1}')"
# A second tarball with the same layout and different bytes — the substituted download.
printf 'padding that changes the digest\n' > "$TMP/pkg/shellcheck-v$FAKEV/README"
tar -cJf "$TMP/other.tar.xz" -C "$TMP/pkg" "shellcheck-v$FAKEV"
eq "the two fixture tarballs really do differ (control for the sha leg)" "false" \
   "$(test "$GOODSHA" = "$(sha256sum "$TMP/other.tar.xz" | awk '{print $1}')" && echo true || echo false)"
printf 'version %s\nasset   %s  %s\n' "$FAKEV" "$ASSET" "$GOODSHA" > "$TMP/pin-good"

mkdir -p "$TMP/stub"
cat > "$TMP/stub/curl" <<'EOF'
#!/usr/bin/env bash
# stub curl: serves $STUB_SERVE to the path given by -o; with nothing to serve it fails like curl
# does on a transport error, which is the "no network" case.
out=""; prev=""
for a in "$@"; do
    [ "$prev" = "-o" ] && out="$a"
    prev="$a"
done
[ -n "$out" ] || { echo "stub curl: no -o given" >&2; exit 2; }
[ -n "${STUB_SERVE:-}" ] || exit 22
cp "$STUB_SERVE" "$out"
EOF
chmod +x "$TMP/stub/curl"

echo "   3d: the download cannot be made"
_wrap "$TMP/pin-good" "$TMP/cache-d" "$TMP/stub" -S error x.sh
eq "rc 9" "9" "$WRC"
eq "the refusal names the download it could not make" "true" "$(has "could not download" "$(cat "$TMP/e")")"

echo "   3g: the download is served with the WRONG bytes"
STUB_SERVE="$TMP/other.tar.xz" _wrap "$TMP/pin-good" "$TMP/cache-g" "$TMP/stub" -S error x.sh
eq "rc 9" "9" "$WRC"
eq "the refusal says the sha256 did not match" "true" "$(has "sha256 MISMATCH" "$(cat "$TMP/e")")"
eq "nothing from the substituted tarball ran" "false" "$(has "RAN " "$(cat "$TMP/o")")"
eq "the substituted binary was not left in the cache" "false" \
   "$(test -e "$TMP/cache-g/$FAKEV/shellcheck" && echo true || echo false)"

echo "   3e: the download is served with the pinned bytes"
STUB_SERVE="$TMP/served.tar.xz" _wrap "$TMP/pin-good" "$TMP/cache-e" "$TMP/stub" -S error x.sh
eq "rc 0" "0" "$WRC"
eq "the downloaded binary ran with the forwarded args" "true" "$(has "RAN $FAKEV ARGS -S error x.sh" "$(cat "$TMP/o")")"
eq "it landed in the cache" "true" "$(test -x "$TMP/cache-e/$FAKEV/shellcheck" && echo true || echo false)"

echo "   3f: the cache is used on the next run, with no downloader at all"
_wrap "$TMP/pin-good" "$TMP/cache-e" "$TMP/empty" -S error x.sh
eq "rc 0 with curl gone from PATH" "0" "$WRC"
eq "the cached binary ran" "true" "$(has "RAN $FAKEV ARGS -S error x.sh" "$(cat "$TMP/o")")"

echo "-- 3h: an undeclared pin is refused rather than guessed --"
_wrap "$TMP/no-such-pin-file" "$TMP/cache-h" "$TMP/path-good" -S error x.sh
eq "rc 9 when the pin file is missing" "9" "$WRC"
eq "the refusal names the missing pin file" "true" "$(has "no pin file at" "$(cat "$TMP/e")")"
# The PATH here holds a binary the wrapper WOULD have accepted under a readable pin file — so this
# proves the refusal comes from the missing declaration, not from an empty PATH.
eq "the acceptable PATH binary did NOT run" "false" "$(has "RAN $FAKEV" "$(cat "$TMP/o")")"

_wrap "$TMP/pin-noversion" "$TMP/cache-i" "$TMP/path-good" -S error x.sh
eq "rc 9 when the pin file declares no version" "9" "$WRC"
eq "the refusal names the missing version line" "true" "$(has "declares no 'version" "$(cat "$TMP/e")")"

_summary shellcheck-pin-selftest
