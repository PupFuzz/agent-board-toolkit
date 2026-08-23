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
check accept "https://kanban.victim.corp./api/v3"         "the expected host, FQDN-spelled with a trailing dot"
check refuse "https://kanban.victim.corp../api/v3"        "a DOUBLE trailing dot is not that name"

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

# ---------------------------------------------------------------------------------------
echo "== kb_url_host — ONE authority parser, asserted directly (card#7245) =="
# Both guards now read the host from kb_url_host, so the exfiltration matrix above is a
# statement about THIS function. Asserting it directly as well is not duplication: the guards
# can only report accept/refuse, which cannot distinguish "parsed evil.example and refused it"
# from "parsed nothing and refused everything" — and a parser that returns "" for every input
# passes every refuse row above while being useless.
uh() { eq "kb_url_host $1" "$2" "$(kb_url_host "$1")"; }
uh "https://kanban.victim.corp/api/v3"           "kanban.victim.corp"
uh "https://kanban.victim.corp:8443/api/v3"      "kanban.victim.corp"
uh "https://u:pw@kanban.victim.corp/api/v3"      "kanban.victim.corp"
uh "https://good.host@evil.example/"             "evil.example"
uh "https://evil.example#@kanban.victim.corp"    "evil.example"
uh "https://evil.example?@kanban.victim.corp"    "evil.example"
uh "https://evil.example:443#@kanban.victim.corp" "evil.example"
uh "http://127.0.0.1:1/api"                      "127.0.0.1"
uh ""                                            ""
# A SCHEMELESS string whose path carries a '://' must not be re-read as a scheme — the reason
# the strip is gated on an anchored scheme match instead of a bare `${u#*://}`.
uh "kanban.victim.corp/p?x://y"                  "kanban.victim.corp"

# ── BRACKETED IPv6 LITERALS: the authority ends at ']', never at the first ':' ──────────
# `${u%%:*}` strips from the FIRST colon, and an IP-literal is nothing but colons, so
# `https://[::1]:8080/api` parsed as `[` and `https://[fe80::1]/api` as `[fe80`. Neither was
# fail-OPEN by itself — both refuse — but the refusal then printed
# `if '[' IS your board host, set KANBAN_EXPECTED_HOST="["`, and `[` matches EVERY bracketed
# authority, so the guard's own remediation text was what minted the bypass. The install
# shape is legitimate by this repo's own docs (docs/INSTALL.md §3 blesses a 127.0.0.1
# board; `[::1]` is the same box). curl ends the authority at ']' — measured:
# `https://[::1]:8080/api` connects to `::1` port 8080 — so the parser must too.
uh "https://[::1]:8080/api/v3"           "[::1]"
uh "https://[::1]/api/v3"                "[::1]"
uh "https://[fe80::1]/api"               "[fe80::1]"
uh "https://[::ffff:169.254.169.254]/"   "[::ffff:169.254.169.254]"
uh "https://u:pw@[::1]:8080/api"         "[::1]"
uh "https://[::1]"                       "[::1]"
# The bracket must not become a way to smuggle one: a '[' in the PATH is already gone by
# then, and an '@' after the literal still puts the host after the LAST '@'.
uh "https://evil.example/[::1]"          "evil.example"
uh "https://[::1]@evil.example/"         "evil.example"
# An UNCLOSED bracket has no ']' to end at, so it keeps the old first-colon strip and lands
# on '['. That is not a hole: curl rejects the URL outright — measured,
# `curl 'https://[::1/api'` exits 3, `bad range specification in URL position 10` — so no
# request is ever made with it, and '[' matches no declared host after this change.
uh "https://[::1/api"                    "["

# ── A TRAILING DOT is the same DNS name ────────────────────────────────────────────────
# `kanban.victim.corp.` is the absolute (FQDN) spelling; curl resolves it to the same name.
# Refusing it produced `'kanban.victim.corp.' is not 'kanban.victim.corp'`, which reads as a
# tool malfunction. ONE dot is stripped, not a run: `..` is not a valid name and must stay
# refused rather than be normalised into one.
uh "https://kanban.victim.corp./api/v3"  "kanban.victim.corp"
uh "https://kanban.victim.corp.:8443/"   "kanban.victim.corp"
uh "https://kanban.victim.corp../api/v3" "kanban.victim.corp."
uh "https://."                           ""

# ---------------------------------------------------------------------------------------
echo "== kb_require_known_api_host — the same hosts, a host-ONLY predicate (card#7245) =="
# THE STATED SCOPE IS THE HOST AND NOTHING ELSE, so this block is the two-sided proof of that:
# every host-based refusal above must still refuse here, and the two rows that differ from
# kb_require_https_host — http:// and ftp:// on the DECLARED host — must ACCEPT, because this
# guard judges the operator's own ~/.kanban-host.env, where an http://127.0.0.1 board is a
# legitimate install. A copy of the https guard would silently refuse those with a message
# about a host.
kcheck() {
    local want="$1" url="$2" label="$3" g
    kb_require_known_api_host "$url" 2>/dev/null && g=accept || g=refuse
    [[ "$g" == "$want" ]] && ok "$label ($want)" || bad "$label — $g, want $want   [$url]"
}
kcheck accept "https://kanban.victim.corp/api/v3"        "the declared host"
kcheck accept "https://board.kanban.victim.corp/api/v3"  "a subdomain of the declared host"
kcheck accept "https://kanban.victim.corp:8443/api/v3"   "declared host with a :port"
kcheck accept "http://kanban.victim.corp/api/v3"         "http on the declared host — NOT this guard's call"
kcheck accept "ftp://kanban.victim.corp/"                "a non-http scheme on the declared host — same"
kcheck refuse "https://evil.example/api/v3"              "a plainly different host"
kcheck refuse "https://kanban.victim.corp.evil.example/" "declared host as a PREFIX of an evil domain"
kcheck refuse "https://xkanban.victim.corp/"             "declared host as a suffix without a label boundary"
kcheck refuse "https://good.host@evil.example/"          "userinfo trick — host is after the LAST '@'"
kcheck refuse "https://evil.example#@kanban.victim.corp" "FRAGMENT split — '#@'"
kcheck refuse "https://evil.example?@kanban.victim.corp" "QUERY split — '?@'"
kcheck refuse ""                                         "an empty api base"

echo "== …and it fails CLOSED when nothing is declared — the arm that catches the 00:42 write =="
ksaved="$KANBAN_EXPECTED_HOST"
unset KANBAN_EXPECTED_HOST
kb_require_known_api_host "https://kanban.victim.corp/api/v3" 2>/dev/null \
    && bad "unset KANBAN_EXPECTED_HOST must refuse (no host is recognised)" \
    || ok "unset KANBAN_EXPECTED_HOST refuses"
kmsg="$(kb_require_known_api_host "https://kanban.victim.corp/api/v3" 2>&1 >/dev/null || true)"
eq "  and the refusal names the variable to set" "true" "$(has 'export KANBAN_EXPECTED_HOST=' "$kmsg")"
eq "  and names the file to set it in"           "true" "$(has '~/.kanban-host.env' "$kmsg")"
export KANBAN_EXPECTED_HOST=""
kb_require_known_api_host "https://kanban.victim.corp/api/v3" 2>/dev/null \
    && bad "empty KANBAN_EXPECTED_HOST must refuse" \
    || ok "empty KANBAN_EXPECTED_HOST refuses"
export KANBAN_EXPECTED_HOST="$ksaved"
kmsg="$(kb_require_known_api_host "https://evil.example/api/v3" 2>&1 >/dev/null || true)"
eq "a MISMATCH names the host it refused"        "true" "$(has "evil.example" "$kmsg")"
eq "  and tells the operator both ways out"      "true" "$(has 'KBCARD_API' "$kmsg")"

echo "== an IPv6-literal board host: BOTH copies, and the tool's own remediation (card#7245) =="
# The install shape is legitimate, so the guard must be usable on it: a declared `[::1]`
# accepts that board and NOTHING else. The rows are run against both copies, because the
# vendored mirror splits the authority with the same two parameter expansions.
ipsaved="$KANBAN_EXPECTED_HOST"
export KANBAN_EXPECTED_HOST="[::1]"; EXPECT_HOST="[::1]"
check accept "https://[::1]:8080/api/v3"            "the declared IPv6 literal with a :port"
check accept "https://[::1]/api/v3"                 "the declared IPv6 literal, no port"
check refuse "https://[::ffff:169.254.169.254]/api" "a DIFFERENT IPv6 literal (link-local metadata)"
check refuse "https://[fe80::1]/api"                "another different IPv6 literal"
check refuse "https://evil.example/api/v3"          "a name, against a declared IP-literal"

# ⛔ THE DEFECT THIS BLOCK EXISTS FOR, asserted through the tool's OWN words rather than a
# literal: the remediation line tells the operator what to set, so whatever it names must
# admit the board it was printed for and nothing else. It used to name `[`, which admits
# every bracketed authority — the guard's text producing the config that breaks the guard.
export KANBAN_EXPECTED_HOST="kanban.victim.corp"
ipmsg="$(kb_require_known_api_host "https://[::1]:8080/api/v3" 2>&1 >/dev/null || true)"
suggested="$(printf '%s\n' "$ipmsg" | sed -n 's/.*set KANBAN_EXPECTED_HOST="\([^"]*\)".*/\1/p' | head -1)"
eq "the refusal suggests a host to declare (control)" "false" \
   "$([[ -z "$suggested" ]] && echo true || echo false)"
export KANBAN_EXPECTED_HOST="$suggested"; EXPECT_HOST="$suggested"
kcheck accept "https://[::1]:8080/api/v3"            "taking the tool's suggestion accepts the board it named"
kcheck refuse "https://[::ffff:169.254.169.254]/api" "  …and STILL refuses every other IPv6 literal"
kcheck refuse "https://[fe80::1]/api"                "  …and this one too"
export KANBAN_EXPECTED_HOST="$ipsaved"; EXPECT_HOST="$ipsaved"

# A trailing dot on the DECLARED side is the same name too — otherwise an operator who
# copied the FQDN spelling out of their own KBCARD_API is refused with
# `'kanban.victim.corp' is not 'kanban.victim.corp.'`, the mirror image of the case above.
export KANBAN_EXPECTED_HOST="kanban.victim.corp."; EXPECT_HOST="kanban.victim.corp."
check  accept "https://kanban.victim.corp/api/v3"       "a declared host spelled with a trailing dot"
check  accept "https://board.kanban.victim.corp/api/v3" "  …and its subdomains still match"
check  refuse "https://evil.example/api/v3"             "  …while a different host still refuses"
kcheck accept "https://kanban.victim.corp/api/v3"       "same, through the host-only preflight"
# A declared host that is NOTHING BUT a dot normalises to empty, which must fail CLOSED —
# the strip must not turn a junk declaration into a wildcard.
export KANBAN_EXPECTED_HOST="."; EXPECT_HOST="."
check  refuse "https://kanban.victim.corp/api/v3"       "a declared host of '.' alone recognises nothing"
kcheck refuse "https://kanban.victim.corp/api/v3"       "  …through the host-only preflight too"
# ⛔ THE ROW THAT CAUGHT THE COPIES DIVERGING. A declared "." normalises to empty, and the
# mirror's subdomain arm is built as *".$EXPECT_HOST" — with the declared side empty that
# becomes *"." , which matches any host STILL ending in a dot after its own single-dot strip.
# `kanban.victim.corp..` is exactly such a host, so the vendored copy ACCEPTED it while the
# lib refused. Unreachable through promote-released-cards (its caller dies on an empty
# EXPECT_HOST) but the extracted unit has no caller, and agreement is what this file asserts.
check  refuse "https://kanban.victim.corp../api/v3"     "  …and a DOUBLE dot cannot ride the empty declaration"
export KANBAN_EXPECTED_HOST="$ipsaved"; EXPECT_HOST="$ipsaved"

echo "== the refusal must be loud (a silent rc is one an operator never sees) =="
msg="$(kb_require_https_host "https://evil.example#@kanban.victim.corp" 2>&1 >/dev/null || true)"
case "$msg" in
    *"refusing to send token"*) ok "refusal names itself on stderr" ;;
    *) bad "refusal was silent or unhelpful: '$msg'" ;;
esac

# ---------------------------------------------------------------------------------------
echo "== kb_redact_url_userinfo — the SECOND sync-paired copy, same two-copy discipline (card#7500) =="
# WHY IT IS ASSERTED HERE. The guards ACCEPT an api_base carrying userinfo — the pinned
# `https://u:pw@kanban.victim.corp/api/v3` row at the top of this file — so every message that
# renders the base must mask it, and the masking primitive is duplicated for exactly the reason
# host_ok is: bin/promote-released-cards is vendored standalone and must not source the lib.
# Two copies sync-paired by comment is the shape that was already wrong once in this very file,
# so the mirror is lifted out and the two are asserted to AGREE on every row, byte for byte.
#
# ⛔ IT READS THE SAME AUTHORITY BOUNDARY AS kb_url_host, AND THE MATRIX BELOW IS WHY. The
# `#@` / `?@` rows have NO userinfo — the '@' sits in a fragment/query that curl discards —
# and a redactor cutting at the last '@' anywhere would rewrite those refusals to name
# `kanban.victim.corp` as the base being contacted, i.e. print the protected host as the
# destination in the exact message that exists to say it is not.
prc_red_src="$(sed -n '/^redact_userinfo() {/,/^}/p' "$PRC")"
[[ -n "$prc_red_src" ]] || { echo "selftest: could not extract redact_userinfo from $PRC — did it get renamed?" >&2; exit 1; }
eval "${prc_red_src/redact_userinfo() \{/redact_userinfo_prc() \{}"

# red <url> <expected> <label> — assert BOTH copies produce <expected>, spelled as a literal.
# The expectation is never computed by calling either copy: that would assert only self-equality.
red() {
    local url="$1" want="$2" label="$3" g p
    g="$(kb_redact_url_userinfo "$url")"
    p="$(redact_userinfo_prc  "$url")"
    if [[ "$g" != "$want" ]]; then
        bad "$label — lib gave '$g', want '$want'   [$url]"
    elif [[ "$p" != "$want" ]]; then
        bad "$label — the two copies DISAGREE: lib='$g' promote='$p'   [$url]"
    else
        ok "$label (both copies)"
    fi
}

echo "-- a base carrying userinfo loses it and KEEPS the host --"
red "https://u:pw@kanban.victim.corp/api/v3"  "https://***@kanban.victim.corp/api/v3"  "the pinned accepted-userinfo row"
red "https://u:pw@kanban.victim.corp:8443/x"  "https://***@kanban.victim.corp:8443/x"  "userinfo with a :port"
red "http://u:pw@127.0.0.1:8080/a?x=1#f"      "http://***@127.0.0.1:8080/a?x=1#f"      "scheme, port, query and fragment all survive"
red "https://u:pw@[::1]:8443/api"             "https://***@[::1]:8443/api"             "an IPv6 IP-literal host survives"
red "https://user-only@kanban.victim.corp/"   "https://***@kanban.victim.corp/"        "a username with no password is still userinfo"
red "https://a@b@c.victim.corp/x"             "https://***@c.victim.corp/x"            "the mask spans to the LAST '@' in the authority"
red "u:pw@kanban.victim.corp/api"             "***@kanban.victim.corp/api"             "a schemeless authority is still redacted"

echo "-- a base with NO userinfo comes back BYTE-IDENTICAL (no message churn) --"
red "https://kanban.victim.corp/api/v3"       "https://kanban.victim.corp/api/v3"      "the ordinary base"
red "https://kanban.victim.corp./api/v3"      "https://kanban.victim.corp./api/v3"     "the FQDN trailing-dot spelling"
red ""                                        ""                                        "an empty api_base"
red "https://"                                "https://"                                "a scheme and nothing else"
red "host/p?x://y"                            "host/p?x://y"                            "a schemeless string whose PATH contains '://'"

echo "-- ⛔ the #4346 hostile rows have NO userinfo and must come back UNTOUCHED --"
red "https://evil.example#@kanban.victim.corp"        "https://evil.example#@kanban.victim.corp"        "FRAGMENT split — the '@' is not in the authority"
red "https://evil.example?@kanban.victim.corp"        "https://evil.example?@kanban.victim.corp"        "QUERY split — likewise"
red "https://evil.example#@kanban.victim.corp/api/v3" "https://evil.example#@kanban.victim.corp/api/v3" "'#@' with a trailing path"
red "https://evil.example:443#@kanban.victim.corp"    "https://evil.example:443#@kanban.victim.corp"    "'#@' after a :port"
# The userinfo TRICK is the mirror image: here the '@' IS in the authority, the host is
# evil.example, and `good.host` is a decoy the mask must remove — it is indistinguishable from
# a real credential and reads as the trusted host to a human scanning the refusal.
red "https://good.host@evil.example/"                 "https://***@evil.example/"                       "the userinfo TRICK — the decoy is masked, evil.example survives"

echo "== …and the guards' REFUSAL MESSAGES carry the mask, not the credential (card#7500) =="
# The primitive above is only half the fix; the other half is that every message rendering a base
# actually goes through it. These three are the guards' own stderr — driven for real, asserted on
# the credential VALUE (a message printing `***` AND the password would satisfy a mask check),
# and paired with a HOST leg so a later edit that redacted everything cannot pass.
_UI_PW='not-a-real-password-card7500'
_UI_USER='fakeuser'
_UI_BASE="https://$_UI_USER:$_UI_PW@kanban.victim.corp/api/v3"

_guard_msg() { # <label> <captured-stderr>
    local label="$1" text="$2"
    # POSITIVE CONTROL FIRST: every leg below is an absence, and empty stderr satisfies them all.
    eq "$label — the guard actually spoke (positive control)" "false" \
       "$([[ -z "$text" ]] && echo true || echo false)"
    eq "$label — the password is absent"  "false" "$(has "$_UI_PW"   "$text")"
    eq "$label — the username is absent"  "false" "$(has "$_UI_USER" "$text")"
    eq "$label — the HOST is still named" "true"  "$(has 'kanban.victim.corp' "$text")"
}

_ui_saved="$KANBAN_EXPECTED_HOST"
unset KANBAN_EXPECTED_HOST
_guard_msg "kb_require_known_api_host, nothing declared" \
    "$(kb_require_known_api_host "$_UI_BASE" 2>&1 >/dev/null || true)"
export KANBAN_EXPECTED_HOST="other.example"
_guard_msg "kb_require_known_api_host, host mismatch" \
    "$(kb_require_known_api_host "$_UI_BASE" 2>&1 >/dev/null || true)"
export KANBAN_EXPECTED_HOST="$_ui_saved"; EXPECT_HOST="$_ui_saved"
_guard_msg "kb_require_https_host, scheme downgrade" \
    "$(kb_require_https_host "http://$_UI_USER:$_UI_PW@kanban.victim.corp/api/v3" 2>&1 >/dev/null || true)"

# CONTROL — a userinfo-free base is still printed verbatim, so the mask is not a rewrite of every
# message. `refusing to use '<base>'` is the historic spelling and must be byte-identical.
_ctl="$(KANBAN_EXPECTED_HOST="other.example" kb_require_known_api_host "https://kanban.victim.corp/api/v3" 2>&1 >/dev/null || true)"
eq "CONTROL: a userinfo-free base is quoted verbatim" "true" \
   "$(has "refusing to use 'https://kanban.victim.corp/api/v3'" "$_ctl")"
eq "CONTROL: …and no mask is inserted into it"        "false" "$(has '***' "$_ctl")"
unset -f _guard_msg
unset _UI_PW _UI_USER _UI_BASE _ui_saved _ctl

echo "-- the mask agrees with kb_url_host on WHICH host survives, on every row above --"
# The property that makes the mask safe: redacting must never change the parsed host. Asserted
# over the same hostile matrix the guards are asserted over, so a future edit to either the
# parser or the redactor that splits them reds here rather than in production.
for _u in \
    "https://u:pw@kanban.victim.corp/api/v3" "https://good.host@evil.example/" \
    "https://evil.example#@kanban.victim.corp" "https://evil.example?@kanban.victim.corp" \
    "https://u:pw@[::1]:8443/api" "https://a@b@c.victim.corp/x" \
    "u:pw@kanban.victim.corp/api" "https://kanban.victim.corp./api/v3" "" ; do
    eq "host is preserved through the mask [$_u]" \
       "$(kb_url_host "$_u")" "$(kb_url_host "$(kb_redact_url_userinfo "$_u")")"
done

_summary "kb-host-guard-selftest"
