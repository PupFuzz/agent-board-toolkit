#!/usr/bin/env bash
# e2e-harness-containment-selftest.sh — deterministic, network-free checks that the E2E API
# harness (tests/_kb-api-stub.sh) writes its board config INSIDE the scratch dir it was given
# and nowhere else.
#
# ⛔ WHY THIS FILE EXISTS (card#7245). At 00:42 on 2026-08-22 a run of that harness wrote the
# operator's LIVE host config: `~/.kanban-host.env` was replaced wholesale with a single
# `export KBCARD_API="https://kanban.test/api/v3"` line, `~/.kanban-dev-token` — which held a
# prod-capable bearer — was overwritten with the literal `stub-token`, and a stray
# `~/.kanban-e2e-board.env` was left behind. Every board tool on the box failed from then until
# the operator restored the credential by hand: first `Could not resolve host: kanban.test`,
# then `HTTP 401 Unauthenticated`. The harness's only guard was `: "${HOME:?…}"`, which fires
# when HOME is UNSET — i.e. it was satisfied by precisely the value that did the damage.
#
# THE POPULATION IS THE HARNESS'S WRITE SET, and it is derived from the harness rather than
# recalled: every path kb_stub_board_config opens. Three properties are asserted over it —
# a refusal when HOME is not the scratch dir, a write set that stays inside the scratch dir,
# and a host env that DECLARES what the lib's preflight and token resolution now require.
#
# EVERY ABSENCE ASSERTION HERE IS PAIRED WITH A PRESENCE WITNESS. "the decoy is unchanged" is
# also true of a harness that has stopped writing anything at all, and of a driver that never
# ran; each block therefore also asserts the file the harness IS supposed to have written.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
STUB="$HERE/_kb-api-stub.sh"
_need -r "$STUB"

_mktmp_scratch   # TMP + EXIT-cleanup trap. NOT --home: this file sets HOME per driver run.

# The driver: source the prelude + the harness in a FRESH shell whose HOME and TMP are whatever
# the case supplies, then call the harness exactly as a selftest would. It prints its config
# state on stdout so a case can assert on it, and REACHED-END last — a line that only exists if
# kb_stub_board_config returned rather than refusing.
cat > "$TMP/drive.sh" <<'DRIVER'
# shellcheck source=/dev/null
source "$1/_selftest-prelude.sh"
# shellcheck source=/dev/null
source "$1/_kb-api-stub.sh"
kb_stub_scrub_env
kb_stub_board_config demo 42 'export KB_STAGE_BACKLOG=48'
printf 'HOST_ENV=%s\n'  "${KANBAN_HOST_ENV:-}"
printf 'TOKEN=%s\n'     "${KB_STUB_TOKEN_FILE:-}"
printf 'REACHED-END\n'
DRIVER

# drive <home> <tmp-or-UNSET> — run it; stdout captured, stderr merged into DRV_ERR, rc in DRV_RC.
DRV_OUT=""; DRV_ERR=""; DRV_RC=0
drive() {
    local home="$1" tmp="$2"
    DRV_RC=0
    if [[ "$tmp" == "UNSET" ]]; then
        DRV_OUT="$(env -u TMP HOME="$home" bash "$TMP/drive.sh" "$HERE" 2>"$TMP/err")" || DRV_RC=$?
    else
        DRV_OUT="$(env HOME="$home" TMP="$tmp" bash "$TMP/drive.sh" "$HERE" 2>"$TMP/err")" || DRV_RC=$?
    fi
    DRV_ERR="$(cat "$TMP/err")"
}

# plant_decoys <dir> — the three files the 00:42 write destroyed, with contents nothing else
# in this file writes, so "unchanged" is a claim about THESE bytes.
plant_decoys() {
    mkdir -p "$1"
    printf 'export KBCARD_API="https://real.kanban.example/api/v3"\nexport KANBAN_EXPECTED_HOST="real.kanban.example"\n' > "$1/.kanban-host.env"
    printf 'DECOY-LIVE-BEARER-DO-NOT-OVERWRITE\n' > "$1/.kanban-dev-token"
}
same_bytes() { cmp -s "$1" "$2" && echo true || echo false; }

# ---------------------------------------------------------------------------
echo "== the documented setup still works (positive control, first) =="
# Every refusal asserted below is worthless if the harness refuses everything, so the
# contained case is measured BEFORE them.
OKH="$TMP/ok"; mkdir -p "$OKH"
drive "$OKH" "$OKH"
eq "a scratch HOME == TMP is accepted (rc)"        "0"    "$DRV_RC"
eq "  and the driver reached the end"              "true" "$(has 'REACHED-END' "$DRV_OUT")"
eq "  the board env was written"                   "true" "$([[ -r "$OKH/.kanban-demo-board.env" ]] && echo true || echo false)"
eq "  and it carries the extra line it was given"  "true" "$(has 'KB_STAGE_BACKLOG=48' "$(cat "$OKH/.kanban-demo-board.env")")"

# ---------------------------------------------------------------------------
echo "== the harness writes its OWN host env, via \$KANBAN_HOST_ENV — never the shared one =="
host_env="$(printf '%s\n' "$DRV_OUT" | sed -n 's/^HOST_ENV=//p')"
tok_file="$(printf '%s\n' "$DRV_OUT" | sed -n 's/^TOKEN=//p')"
eq "KANBAN_HOST_ENV is exported and points inside the scratch dir" "true" \
   "$([[ -n "$host_env" && "$host_env" == "$OKH/"* ]] && echo true || echo false)"
eq "  and that file exists (witness)"              "true" "$([[ -r "$host_env" ]] && echo true || echo false)"
eq "  ~/.kanban-host.env was NOT written"          "false" "$([[ -e "$OKH/.kanban-host.env" ]] && echo true || echo false)"
eq "the token file is declared, inside the scratch dir" "true" \
   "$([[ -n "$tok_file" && "$tok_file" == "$OKH/"* ]] && echo true || echo false)"
eq "  and it exists (witness)"                     "true" "$([[ -r "$tok_file" ]] && echo true || echo false)"
eq "  ~/.kanban-dev-token was NOT written"         "false" "$([[ -e "$OKH/.kanban-dev-token" ]] && echo true || echo false)"

echo "== …and that host env DECLARES what the lib now requires of it =="
hcontent="$(cat "$host_env")"
eq "declares KBCARD_API"          "true" "$(has 'export KBCARD_API='          "$hcontent")"
eq "declares KANBAN_EXPECTED_HOST — the api-host preflight has no default" "true" \
   "$(has 'export KANBAN_EXPECTED_HOST=' "$hcontent")"
eq "declares KBCARD_TOKEN_FILE — the token ladder has no default"          "true" \
   "$(has 'export KBCARD_TOKEN_FILE=' "$hcontent")"
eq "the declared host matches the declared api base" "true" \
   "$(has "https://$(printf '%s\n' "$hcontent" | sed -n 's/^export KANBAN_EXPECTED_HOST="\(.*\)"$/\1/p')/" "$hcontent")"

# ---------------------------------------------------------------------------
echo "== a HOME that is not the scratch dir is REFUSED, and left byte-identical =="
# This is the 00:42 shape exactly: a real home, fully populated, with TMP pointing somewhere
# else entirely (or nowhere) because nobody called _mktmp_scratch --home.
REALH="$TMP/realhome"; plant_decoys "$REALH"
cp "$REALH/.kanban-host.env" "$TMP/ref-host.env"
cp "$REALH/.kanban-dev-token" "$TMP/ref.token"
drive "$REALH" "$TMP/elsewhere"
eq "a real HOME beside a different TMP is refused (rc)" "1"     "$DRV_RC"
eq "  and the driver never reached the end"             "false" "$(has 'REACHED-END' "$DRV_OUT")"
eq "  the refusal names the setup call to make"         "true"  "$(has '_mktmp_scratch --home' "$DRV_ERR")"
eq "  and names the card"                               "true"  "$(has 'card#7245' "$DRV_ERR")"
eq "  ~/.kanban-host.env is byte-identical"             "true"  "$(same_bytes "$REALH/.kanban-host.env" "$TMP/ref-host.env")"
eq "  ~/.kanban-dev-token is byte-identical"            "true"  "$(same_bytes "$REALH/.kanban-dev-token" "$TMP/ref.token")"
eq "  and no board env was minted beside them"          "false" "$([[ -e "$REALH/.kanban-demo-board.env" ]] && echo true || echo false)"

echo "== …and so is a HOME with NO TMP at all (the un-set-up shell) =="
REALH2="$TMP/realhome2"; plant_decoys "$REALH2"
drive "$REALH2" UNSET
eq "an unset TMP is refused (rc)"                       "1"     "$DRV_RC"
eq "  and no board env was minted"                      "false" "$([[ -e "$REALH2/.kanban-demo-board.env" ]] && echo true || echo false)"

echo "== …EVEN when the real home is otherwise a perfectly good scratch target =="
# The discriminator is "did the caller run the documented setup", not "does this directory
# look writable" — a HOME that merely EXISTS is the state that took the box down.
REALH3="$TMP/realhome3"; plant_decoys "$REALH3"
drive "$REALH3" "$TMP"
eq "HOME under TMP but not EQUAL to it is still refused" "1" "$DRV_RC"

_summary "e2e-harness-containment-selftest"
