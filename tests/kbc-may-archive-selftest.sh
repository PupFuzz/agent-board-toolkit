#!/usr/bin/env bash
# kbc-may-archive-selftest.sh — network-free checks for the _kbc-may-archive.py
# archive-gate shim: its tri-state GitHub resolver (OPEN→live, CLOSED/MERGED→
# terminal, gh error→unresolvable/fail-closed), repo derivation from pr_url, twin
# awareness, and the noprimitive fail-loud path. Runs the shim over the REAL
# framework may_archive primitive (canon #9 — validate on the real surface) with a
# FAKE `gh` on PATH, so it is deterministic + offline. When the plugin's
# kanban_common cannot be located (a bare CI runner with no plugin cache) the
# primitive-backed cases SKIP — the noprimitive path is still exercised there.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
SHIM="$HERE/../bin/_kbc-may-archive.py"
_need -r "$SHIM"
command -v python3 >/dev/null || { echo "selftest: python3 not found" >&2; exit 1; }

_mktmp_scratch   # TMP + EXIT-cleanup trap

# ── Locate the real kanban_common the same way the shim does, for the skip gate ──
KC="$(python3 - "$SHIM" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("s", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m._resolve_kanban_common() or "")
PY
)"

# ── Fake gh on PATH: reads a per-run canned state from $FAKE_GH_STATE ───────────
#    FAKE_GH_STATE=OPEN|CLOSED|MERGED|<empty> ; "ERR" makes gh exit non-zero (404/net).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
[[ "${FAKE_GH_STATE:-}" == "ERR" ]] && { echo "gh: not found" >&2; exit 1; }
printf '{"state":"%s"}' "${FAKE_GH_STATE:-OPEN}"
EOF
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"
export FAKE_GH_STATE=OPEN   # must be EXPORTED so the fake gh subprocess reads it

# gate <req-json> — run the shim; prints "<token>\t<reason>".
gate() { printf '%s' "$1" | python3 "$SHIM"; }
tok()  { printf '%s' "$1" | cut -f1; }

# ── noprimitive: kanban_common unresolvable → fail-loud token (CI-safe, always) ──
echo "== _kbc-may-archive.py — noprimitive fail-loud when the primitive is absent =="
out="$(KBCARD_KANBAN_COMMON=/nonexistent/kanban_common.py gate '{"card":{"id":1,"payload":{"pr_number":5,"repo":"o/r"}}}')"
eq "unresolvable primitive → noprimitive token" "noprimitive" "$(tok "$out")"
eq "noprimitive names may_archive"              "true"        "$(case "$out" in *may_archive*) echo true ;; *) echo false ;; esac)"

if [[ -z "$KC" || ! -f "$KC" ]]; then
    echo "  SKIP primitive-backed resolver cases — plugin kanban_common not found on this host"
    _summary "kbc-may-archive-selftest"
    return 0 2>/dev/null || exit 0
fi
export KBCARD_KANBAN_COMMON="$KC"
echo "== resolver tri-state over the REAL may_archive (kanban_common: $KC) =="

# A card whose only backing source is a LIVE PR, no twin → BLOCKED (live).
FAKE_GH_STATE=OPEN
out="$(gate '{"card":{"id":1,"payload":{"pr_number":5,"repo":"o/r"}},"surviving_cards":[]}')"
eq "live PR, no twin → blocked"        "blocked" "$(tok "$out")"
eq "blocked reason says 'live'"        "true"    "$(case "$out" in *"source live"*) echo true ;; *) echo false ;; esac)"

# CLOSED / MERGED PR → terminal → archivable.
FAKE_GH_STATE=CLOSED
eq "closed PR → ok (terminal)"  "ok" "$(tok "$(gate '{"card":{"id":1,"payload":{"pr_number":5,"repo":"o/r"}},"surviving_cards":[]}')")"
FAKE_GH_STATE=MERGED
eq "merged PR → ok (terminal)"  "ok" "$(tok "$(gate '{"card":{"id":1,"payload":{"pr_number":5,"repo":"o/r"}},"surviving_cards":[]}')")"

# gh error (404 / network) → unresolvable → fail-CLOSED → blocked.
FAKE_GH_STATE=ERR
out="$(gate '{"card":{"id":1,"payload":{"pr_number":5,"repo":"o/r"}},"surviving_cards":[]}')"
eq "gh error → blocked (fail-closed)"    "blocked" "$(tok "$out")"
eq "reason says unresolvable/fail-closed" "true"   "$(case "$out" in *unresolvable*|*fail-closed*) echo true ;; *) echo false ;; esac)"

# Live PR WITH a surviving by-ref twin (same pr in another live card) → archivable.
FAKE_GH_STATE=OPEN
out="$(gate '{"card":{"id":1,"payload":{"pr_number":5,"repo":"o/r"}},
             "surviving_cards":[{"id":2,"payload":{"pr_number":5,"repo":"o/r"}}]}')"
eq "live PR WITH surviving twin → ok"  "ok" "$(tok "$out")"

# Source-less card → archivable, and gh is NEVER consulted (ERR would else block).
FAKE_GH_STATE=ERR
eq "source-less card → ok (no gh call)" "ok" "$(tok "$(gate '{"card":{"id":1,"payload":{}},"surviving_cards":[]}')")"

# stable-id (id:<sid>) source with no twin → unresolvable (kbcard can't map it) → blocked.
FAKE_GH_STATE=OPEN
out="$(gate '{"card":{"id":1,"tags":["id:TASK-9"],"payload":{}},"surviving_cards":[]}')"
eq "id:<sid> source, no twin → blocked" "blocked" "$(tok "$out")"

# Repo derivation: no payload.repo, but a pr_url → source derived via the framework
# normalizer; gh returns CLOSED → ok proves the repo was found AND gh was consulted
# (a derivation miss would be unresolvable → blocked).
FAKE_GH_STATE=CLOSED
out="$(gate '{"card":{"id":1,"payload":{"pr_number":7,"pr_url":"https://github.com/PupFuzz/agent-board-toolkit/pull/7"}},"surviving_cards":[]}')"
eq "repo derived from pr_url → ok (terminal)" "ok" "$(tok "$out")"

# Config repo (stdin) supplies the repo when neither descriptor nor url carries one.
FAKE_GH_STATE=CLOSED
out="$(gate '{"card":{"id":1,"payload":{"pr_number":7}},"repo":"PupFuzz/agent-board-toolkit","surviving_cards":[]}')"
eq "config repo used when card has none → ok" "ok" "$(tok "$out")"

# No repo anywhere → unresolvable → blocked (fail-closed), gh never reachable.
FAKE_GH_STATE=OPEN
out="$(gate '{"card":{"id":1,"payload":{"pr_number":7}},"surviving_cards":[]}')"
eq "by-ref with no resolvable repo → blocked (fail-closed)" "blocked" "$(tok "$out")"

_summary "kbc-may-archive-selftest"
