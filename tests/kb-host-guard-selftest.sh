#!/usr/bin/env bash
# kb-host-guard-selftest.sh — deterministic, network-free unit checks for the anti-exfiltration
# api_base host guard, in BOTH of its copies:
#   1. kb_require_https_host   (bin/_kb-board-lib.sh)      — used by board-card-start
#   2. host_ok                 (bin/promote-released-cards) — the standalone vendored mirror
#
# WHY THIS FILE EXISTS. The guard decides whether the bearer token is sent to a host named by
# a COMMITTED, PR-editable file (.release-pr.json .promote.api_base). It ran on every checkout
# and every promote — and nothing had ever tested whether it decides CORRECTLY. It was wired,
# reached, and wrong: it terminated the URL authority at '/' alone, so
# `https://evil.example#@good.host` parsed as `good.host` and was ACCEPTED, while curl dropped
# the fragment and sent the token to evil.example. A guard that parses a URL differently from
# the client that fetches it is an exfiltration primitive, not a guard.
#
# The two copies are sync-paired by COMMENT ONLY — nothing enforces it, and the same defect was
# present in both. So every case below is asserted against BOTH, and their verdicts must AGREE.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
LIB="$HERE/../bin/_kb-board-lib.sh"
PRC="$HERE/../bin/promote-released-cards"
_need -r "$LIB"
_need -r "$PRC"

# shellcheck source=/dev/null
source "$LIB"
KB_PROG="kb-host-guard-selftest"

# promote-released-cards runs its main at top level (no sourced-guard) and must stay standalone,
# so lift just host_ok out of it — the same extract-and-exercise pattern the promote-action
# selftest uses on the composite action's run block. This keeps the vendored mirror honest
# rather than trusting the "keep the two in sync" comment.
prc_src="$(sed -n '/^host_ok() {/,/^}/p' "$PRC")"
[[ -n "$prc_src" ]] || { echo "selftest: could not extract host_ok from $PRC — did it get renamed?" >&2; exit 1; }
eval "${prc_src/host_ok() \{/host_ok_prc() \{}"

export KANBAN_EXPECTED_HOST="kanban.victim.corp"
EXPECT_HOST="kanban.victim.corp"   # the name the promote copy reads

# check <expected accept|refuse> <url> <label>
check() {
    local want="$1" url="$2" label="$3" g p
    kb_require_https_host "$url" 2>/dev/null && g=accept || g=refuse
    host_ok_prc            "$url" 2>/dev/null && p=accept || p=refuse
    if [[ "$g" != "$want" ]]; then
        bad "$label — kb_require_https_host $g, want $want   [$url]"
    elif [[ "$p" != "$want" ]]; then
        bad "$label — the two copies DISAGREE: lib=$g promote=$p   [$url]"
    else
        ok "$label ($want, both copies)"
    fi
}

echo "== legitimate api_base values must still be ACCEPTED (no over-refusal) =="
check accept "https://kanban.victim.corp/api/v3"          "the expected host"
check accept "https://kanban.victim.corp"                 "expected host, no path"
check accept "https://board.kanban.victim.corp/api/v3"    "a subdomain of the expected host"
check accept "https://kanban.victim.corp:8443/api/v3"     "expected host with a :port"
check accept "https://u:pw@kanban.victim.corp/api/v3"     "real userinfo before the expected host"
check accept "https://kanban.victim.corp/api/v3?x=1"      "a query on the expected host"

echo "== the exfiltration matrix — every one must be REFUSED =="
check refuse "https://evil.example/api/v3"                "a plainly different host"
check refuse "https://kanban.victim.corp.evil.example/"   "expected host as a PREFIX of an evil domain"
check refuse "https://xkanban.victim.corp/"               "expected host as a suffix without a label boundary"
check refuse "https://good.host@evil.example/"            "userinfo trick — host is after the LAST '@'"
check refuse "http://kanban.victim.corp/api/v3"           "scheme downgrade to http"
check refuse "ftp://kanban.victim.corp/"                  "a non-http scheme"
check refuse ""                                           "an empty api_base"
# The #4346 class: a delimiter the authority parser must honor, placed BEFORE an '@' so the
# userinfo strip reaches past it. curl ends the authority here; the guard must agree.
check refuse "https://evil.example#@kanban.victim.corp"       "FRAGMENT split — '#@' (the #4346 bug)"
check refuse "https://evil.example?@kanban.victim.corp"       "QUERY split — '?@' (the #4346 bug)"
check refuse "https://evil.example#@kanban.victim.corp/api/v3" "'#@' with a trailing path"
check refuse "https://evil.example?x=1#@kanban.victim.corp"    "query AND fragment before the '@'"
check refuse "https://evil.example:443#@kanban.victim.corp"    "'#@' after a :port"
check refuse "https://evil.example#kanban.victim.corp"         "fragment naming the expected host, no '@'"
check refuse "https://evil.example?host=kanban.victim.corp"    "query naming the expected host"

echo "== fail-CLOSED when KANBAN_EXPECTED_HOST is unset/empty (no baked default) =="
saved="$KANBAN_EXPECTED_HOST"
unset KANBAN_EXPECTED_HOST; EXPECT_HOST=""
kb_require_https_host "https://kanban.victim.corp/api/v3" 2>/dev/null \
    && bad "unset KANBAN_EXPECTED_HOST must fail closed (lib)" \
    || ok "unset KANBAN_EXPECTED_HOST fails closed (lib)"
host_ok_prc "https://kanban.victim.corp/api/v3" 2>/dev/null \
    && bad "unset expected host must fail closed (promote copy)" \
    || ok "unset expected host fails closed (promote copy)"
export KANBAN_EXPECTED_HOST="" ; EXPECT_HOST=""
kb_require_https_host "https://kanban.victim.corp/api/v3" 2>/dev/null \
    && bad "empty KANBAN_EXPECTED_HOST must fail closed (lib)" \
    || ok "empty KANBAN_EXPECTED_HOST fails closed (lib)"
export KANBAN_EXPECTED_HOST="$saved"; EXPECT_HOST="$saved"

echo "== the refusal must be loud (a silent rc is one an operator never sees) =="
msg="$(kb_require_https_host "https://evil.example#@kanban.victim.corp" 2>&1 >/dev/null || true)"
case "$msg" in
    *"refusing to send token"*) ok "refusal names itself on stderr" ;;
    *) bad "refusal was silent or unhelpful: '$msg'" ;;
esac

_summary "kb-host-guard-selftest"
