#!/usr/bin/env bash
# runtime-check-selftest.sh — decision-matrix checks for bin/agent-board-toolkit-runtime-check
# (card #4361). The guard judges WHAT EXECUTES; these drive it against synthetic topologies
# under a scratch HOME + PATH: pinned-current, pinned-STALE, dev-ahead, copies-current,
# copies-STALE, copies-unverifiable, mixed-runtimes. Network-free: the tag fetch inside the
# guard fails against the file-path-less origin and is tolerated as a named warn.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CHECK="$HERE/../bin/agent-board-toolkit-runtime-check"
[[ -x "$CHECK" ]] || { echo "selftest: $CHECK not executable" >&2; exit 1; }

fails=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1" >&2; fails=$((fails + 1)); }
eq()  { [[ "$2" == "$3" ]] && ok "$1" || bad "$1 — expected '$2' got '$3'"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

# A minimal toolkit-shaped repo with two release tags.
mk_repo() { # <dir>
    git init -q "$1"
    mkdir -p "$1/bin"
    printf '#!/bin/sh\necho v1\n' > "$1/bin/kbcard"; chmod +x "$1/bin/kbcard"
    printf '0.1.0\n' > "$1/VERSION"
    git -C "$1" -c user.email=t@t -c user.name=t add -A
    git -C "$1" -c user.email=t@t -c user.name=t commit -qm one
    git -C "$1" tag v0.1.0
    printf '#!/bin/sh\necho v2\n' > "$1/bin/kbcard"
    printf '0.2.0\n' > "$1/VERSION"
    git -C "$1" -c user.email=t@t -c user.name=t add -A
    git -C "$1" -c user.email=t@t -c user.name=t commit -qm two
    git -C "$1" tag v0.2.0
}

run_check() { # <bindir> [extra args...] -> sets RC, ERR
    local bindir="$1"; shift
    RC=0
    ERR="$(PATH="$bindir:/usr/bin:/bin" "$CHECK" "$@" 2>&1 >/dev/null)" || RC=$?
}

echo "== pinned runtime at the newest tag → ok =="
mk_repo "$TMP/repo1"
git -C "$TMP/repo1" checkout -q v0.2.0
mkdir -p "$TMP/bin1"; ln -s "$TMP/repo1/bin/kbcard" "$TMP/bin1/kbcard"
run_check "$TMP/bin1"
eq "current pin → rc 0" "0" "$RC"

echo "== pinned runtime BEHIND the newest tag → loud rc 1 =="
mk_repo "$TMP/repo2"
git -C "$TMP/repo2" checkout -q v0.1.0
mkdir -p "$TMP/bin2"; ln -s "$TMP/repo2/bin/kbcard" "$TMP/bin2/kbcard"
run_check "$TMP/bin2"
eq "stale pin → rc 1" "1" "$RC"
grep -q "STALE runtime" <<<"$ERR" && ok "names the staleness" || bad "missing STALE runtime message"
grep -q "v0.1.0.*v0.2.0" <<<"$ERR" && ok "names both versions" || bad "missing version pair"

echo "== dev checkout AHEAD of the newest tag → ok (maintainer topology) =="
mk_repo "$TMP/repo3"
printf 'x\n' > "$TMP/repo3/extra"; git -C "$TMP/repo3" -c user.email=t@t -c user.name=t add -A
git -C "$TMP/repo3" -c user.email=t@t -c user.name=t commit -qm three   # v0.2.0-1-g…
mkdir -p "$TMP/bin3"; ln -s "$TMP/repo3/bin/kbcard" "$TMP/bin3/kbcard"
run_check "$TMP/bin3"
eq "dev-ahead → rc 0" "0" "$RC"

echo "== copies topology: byte-match vs stale vs unverifiable =="
mk_repo "$HOME/agent-board-toolkit"     # auto-derived reference
mkdir -p "$TMP/bin4"; cp "$HOME/agent-board-toolkit/bin/kbcard" "$TMP/bin4/kbcard"; chmod +x "$TMP/bin4/kbcard"
run_check "$TMP/bin4"
eq "matching copy → rc 0" "0" "$RC"

printf '#!/bin/sh\necho OLD\n' > "$TMP/bin4/kbcard"   # stale copy
run_check "$TMP/bin4"
eq "stale copy → rc 1" "1" "$RC"
grep -q "STALE COPIES" <<<"$ERR" && ok "names the stale copy" || bad "missing STALE COPIES message"

rm -rf "$HOME/agent-board-toolkit"
run_check "$TMP/bin4"
eq "unverifiable copy → rc 0 (warn, honest UNKNOWN)" "0" "$RC"
grep -q "CANNOT BE VERIFIED" <<<"$ERR" && ok "says UNKNOWN, not ok" || bad "missing cannot-verify warn"

echo "== mixed runtimes → loud rc 1 =="
mkdir -p "$TMP/bin5"
ln -s "$TMP/repo1/bin/kbcard" "$TMP/bin5/kbcard"
printf '#!/bin/sh\necho x\n' > "$TMP/repo2/bin/next-dl"; chmod +x "$TMP/repo2/bin/next-dl"
git -C "$TMP/repo2" -c user.email=t@t -c user.name=t add -A
git -C "$TMP/repo2" -c user.email=t@t -c user.name=t commit -qm nd
ln -s "$TMP/repo2/bin/next-dl" "$TMP/bin5/next-dl"
run_check "$TMP/bin5"
eq "mixed runtimes → rc 1" "1" "$RC"
grep -q "MIXED runtimes" <<<"$ERR" && ok "names the split" || bad "missing MIXED runtimes message"

echo "== ships-but-missing symlink → warn, rc stays 0 =="
run_check "$TMP/bin1"   # repo1 also ships only kbcard; simulate by adding a tool to the repo
printf '#!/bin/sh\n' > "$TMP/repo1/bin/adopt-to-dl"; chmod +x "$TMP/repo1/bin/adopt-to-dl"
run_check "$TMP/bin1"
eq "install gap → rc 0 (warn-only)" "0" "$RC"
grep -q "ships adopt-to-dl but PATH lacks" <<<"$ERR" && ok "names the install gap" || bad "missing install-gap warn"

if [[ "$fails" -gt 0 ]]; then
    echo "runtime-check-selftest: $fails check(s) FAILED" >&2
    exit 1
fi
echo "runtime-check-selftest: all checks passed"
