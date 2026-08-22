#!/usr/bin/env bash
# locale-range-guard-selftest.sh — every guard whose accept-set is spelled as a bash
# bracket RANGE must mean the SAME thing under a UTF-8 locale as under LC_ALL=C
# (card#5409).
#
# THE DEFECT. A bracket range in a bash pattern — `[[ $x =~ ^[0-9]+$ ]]`, and a glob
# `case "$x" in *[!0-9]*)` alike — is a COLLATION range, not an ASCII range: it means
# "every character that sorts between these two in the CURRENT locale". Measured on the
# reference host: under LC_ALL=en_US.UTF-8, `^[0-9]+$` matches U+0663 ARABIC-INDIC DIGIT
# THREE and `^[A-Za-z0-9_-]+$` matches U+00E9 / U+2163 / U+FB01; all four are rejected
# under LC_ALL=C. GNU `grep -E` does NOT widen `[0-9]` in either locale, which is what
# identifies bash's engine rather than the pattern as the cause.
#
# WHAT WAS AND WAS NOT WRONG — the claim this file makes is deliberately narrow. The
# widened guards still rejected the characters they were written to reject (a comma and a
# space were measured rejected under en_US.UTF-8 too), so this was NOT a CSV-corruption
# or injection vector. What was wrong is that a guard admitted input its own error
# message declares invalid ("--type '<x>' must be alphanumeric / '-' / '_'" while
# accepting a Roman numeral), and that one PARSE site captured a non-ASCII "digit" as a
# card id and passed it on to `kbcard move --task`.
#
# WHAT THIS TEST ASSERTS. Per fixed site: the same verdict under BOTH LC_ALL=C and
# LC_ALL=en_US.UTF-8, each paired with a plain-ASCII POSITIVE CONTROL that must still be
# ACCEPTED — so a guard that stops being exercised (or is narrowed into rejecting
# everything) is detectable rather than silently green. The locale itself is
# positive-controlled first: if the runner's en_US.UTF-8 does not actually widen
# `[0-9]`, the UTF-8 half proves nothing and says so loudly instead of passing vacuously.
#
# NOT COVERED HERE, and named rather than implied: bin/next-dl's three adopters
# (the atomic-claim value, the claimed DL, and the board DL max) reach their guard only
# through a live board read, so they are covered by the kb_is_uint primitive cases plus
# the static backstop at the end of this file, not by a behavior case of their own.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
ROOT="$(cd "$HERE/.." && pwd)"
BIN="$ROOT/bin"
_need -r "$BIN/_kb-board-lib.sh"
_need -r "$BIN/kbcard"
_need -x "$ROOT/hooks/agent-dispatch-card-start"
# ⛔ SCRATCH HOME, AND BEFORE THE PROBES BELOW (card#7245). The guard probes drive their
# subject by `source "$BIN/kbcard"` in a child shell, and kbcard resolves
# `KB_LOG_FILE="${KBCARD_LOG_FILE:-$HOME/.kbcard-failures.log}"` at source time — so with the
# operator's HOME inherited, every probe whose guard REJECTS (which is most of this file, by
# design) appended a fabricated record to their live triage log. Same defect as
# tests/kbcard-field-selftest.sh; the population is "the suite writes nothing outside its
# scratch", and tests/suite-home-containment-selftest.sh now measures it rather than trusting
# this comment. Hoisted here rather than left at the positive control below, which is the only
# other $TMP user and now reads the dir this call makes.
_mktmp_scratch --home
export BIN ROOT

# Fixtures as explicit UTF-8 BYTE escapes, not \u escapes or literals: the bytes are what
# reach a guard, and a byte escape cannot be re-encoded by the shell's own locale or
# mangled by an editor.
AI3=$'\xd9\xa3'          # U+0663 ARABIC-INDIC DIGIT THREE
EACUTE=$'\xc3\xa9'       # U+00E9 LATIN SMALL LETTER E WITH ACUTE
ROMAN4=$'\xe2\x85\xa3'   # U+2163 ROMAN NUMERAL FOUR
FILIG=$'\xef\xac\x81'    # U+FB01 LATIN SMALL LIGATURE FI

# ---------------------------------------------------------------------------
# Locale positive control: the UTF-8 half of every assertion below is only evidence if
# this box's en_US.UTF-8 really is collation-wide. Probed with a bare bracket range in a
# subprocess — deliberately NOT through the primitive under test.
echo "== precondition: the runner has a locale that actually exercises the defect =="
LOCALES=(C)
UTF8_LOCALE=""
# The probe IS the availability test: an uninstalled locale falls back to C behaviour, so
# it fails the widening check and is skipped — no separate `locale` existence check needed
# (and none is written, because its failure mode was not measured).
for cand in en_US.UTF-8 en_US.utf8; do
    if LC_ALL="$cand" IN="$AI3" bash -c '[[ "$IN" =~ ^[0-9]+$ ]]' 2>/dev/null; then
        UTF8_LOCALE="$cand"; break
    fi
done
if [[ -n "$UTF8_LOCALE" ]]; then
    LOCALES+=("$UTF8_LOCALE")
    ok "en_US.UTF-8 present AND collation-wide ($UTF8_LOCALE widens [0-9] to U+0663)"
else
    printf '  SKIP  no collation-wide UTF-8 locale on this box — the UTF-8 half of every\n' >&2
    printf '        case below is NOT RUN. `locale -a` offers: %s\n' \
        "$(locale -a 2>/dev/null | tr '\n' ' ' | head -c 200)" >&2
    printf '        Install en_US.UTF-8 (or run under one) to exercise the regression.\n' >&2
fi
# The C half must be a real measurement too: prove C REJECTS what UTF-8 widens.
if LC_ALL=C IN="$AI3" bash -c '[[ "$IN" =~ ^[0-9]+$ ]]' 2>/dev/null; then
    bad "LC_ALL=C matched U+0663 against [0-9] — the C-locale baseline is not what it claims"
else
    ok "LC_ALL=C rejects U+0663 against a bare [0-9] range (baseline honest)"
fi

# verdict <locale> <input> <body> — run <body> as a subprocess under <locale> with IN set;
# the body prints a one-word verdict, and its LAST stdout line is the answer. A body that
# needs to rule on stderr redirects it into stdout itself (see the native_type_id case),
# so this stays one runner rather than two near-identical ones.
verdict() { LC_ALL="$1" IN="$2" bash -c "$3" 2>/dev/null | tail -1 || true; }
# both <label> <expected> <input> <body> — assert the verdict under EVERY live locale.
both() {
    local label="$1" exp="$2" in="$3" body="$4" loc
    for loc in "${LOCALES[@]}"; do eq "$label [$loc]" "$exp" "$(verdict "$loc" "$in" "$body")"; done
}

# ---------------------------------------------------------------------------
echo "== kb_is_uint / kb_ere_match — the primitives (bin/_kb-board-lib.sh) =="
UINT='source "$BIN/_kb-board-lib.sh"; kb_is_uint "$IN" && echo ACCEPT || echo REJECT'
both "kb_is_uint rejects U+0663"        "REJECT" "$AI3"    "$UINT"
both "kb_is_uint rejects a mixed run"   "REJECT" "4$AI3"   "$UINT"
both "kb_is_uint rejects empty"         "REJECT" ""        "$UINT"
both "kb_is_uint accepts 42 (posctl)"   "ACCEPT" "42"      "$UINT"
both "kb_is_uint accepts 0 (posctl)"    "ACCEPT" "0"       "$UINT"

TAGSAFE='source "$BIN/_kb-board-lib.sh"; kb_ere_match "$IN" '"'"'^[A-Za-z0-9_-]+$'"'"' && echo ACCEPT || echo REJECT'
both "kb_ere_match [A-Za-z0-9_-] rejects U+00E9" "REJECT" "$EACUTE" "$TAGSAFE"
both "kb_ere_match [A-Za-z0-9_-] rejects U+2163" "REJECT" "$ROMAN4" "$TAGSAFE"
both "kb_ere_match [A-Za-z0-9_-] rejects U+FB01" "REJECT" "$FILIG"  "$TAGSAFE"
both "kb_ere_match keeps rejecting a comma"      "REJECT" "a,b"     "$TAGSAFE"
both "kb_ere_match keeps rejecting a space"      "REJECT" "a b"     "$TAGSAFE"
both "kb_ere_match accepts v1_2-x (posctl)"      "ACCEPT" "v1_2-x"  "$TAGSAFE"

# Captures must survive the helper: kb_dl_num and the dispatch hook both read BASH_REMATCH
# after the match, so a `local BASH_REMATCH` would break them silently.
both "kb_ere_match leaves BASH_REMATCH to the caller" "93" "DL-093" \
     'source "$BIN/_kb-board-lib.sh"; kb_ere_match "$IN" "^([Dd][Ll]-?)?0*([0-9]{1,6})$" && echo "${BASH_REMATCH[2]}"'
# And the C locale must not escape the helper — it is scoped, not ambient.
both "kb_ere_match does not leak LC_ALL to its caller" "restored" "x" \
     'source "$BIN/_kb-board-lib.sh"; before="${LC_ALL-unset}"; kb_is_uint 1
      [[ "${LC_ALL-unset}" == "$before" ]] && echo restored || echo LEAKED'

# ---------------------------------------------------------------------------
echo "== kb_dl_num — the DL token parser (bin/_kb-board-lib.sh) =="
# The verdict distinguishes a CLEAN refusal from the widened path's failure mode: with the
# range widened, the token got PAST the pattern and died in `$((10#…))` instead — also a
# non-zero rc, so an rc-only assertion could not tell the two apart.
DLNUM='source "$BIN/_kb-board-lib.sh"; out="$(kb_dl_num "$IN" 2>&1 || true)"
       case "$out" in *"is not a DL number"*) echo REJECT ;;
                      *"invalid integer"*|*"error"*) echo ARITH-ERR ;; *) echo "$out" ;; esac'
both "kb_dl_num rejects a bare U+0663"     "REJECT" "$AI3"      "$DLNUM"
both "kb_dl_num rejects DL-<U+0663>"       "REJECT" "DL-$AI3"   "$DLNUM"
both "kb_dl_num accepts DL-093 → 93 (posctl)" "93"  "DL-093"    "$DLNUM"
both "kb_dl_num accepts a bare 93 (posctl)"   "93"  "93"        "$DLNUM"

# ---------------------------------------------------------------------------
echo "== kbcard --type — the tag-safety guard (bin/kbcard; card#5409 SITE 1) =="
# kb_api is stubbed, so a card that gets past the guard is "created" without a network call.
TYPE='source "$BIN/kbcard" 2>/dev/null || true
      kb_api() { printf "%s" "{\"data\":{\"id\":1,\"name\":\"x\",\"workflow_stage_id\":48}}"; }
      export KB_BOARD_ID=1 KB_STAGE_BACKLOG=48
      out="$(cmd_create_card --name n --type "$IN" --column backlog 2>&1 || true)"
      case "$out" in *"must be alphanumeric"*) echo REJECT ;; *) echo ACCEPT ;; esac'
both "--type rejects U+00E9"            "REJECT" "$EACUTE" "$TYPE"
both "--type rejects U+2163"            "REJECT" "$ROMAN4" "$TYPE"
both "--type rejects U+FB01"            "REJECT" "$FILIG"  "$TYPE"
both "--type still rejects a comma"     "REJECT" "a,b"     "$TYPE"
both "--type accepts widget (posctl)"   "ACCEPT" "widget"  "$TYPE"
both "--type accepts tech_debt-2 (posctl)" "ACCEPT" "tech_debt-2" "$TYPE"

echo "== kbcard --external-id / task-ref / swimlane / native type / field =="
EXTID='source "$BIN/kbcard" 2>/dev/null || true
       kb_api() { printf "%s" "{\"data\":{\"id\":1,\"name\":\"x\",\"workflow_stage_id\":48}}"; }
       export KB_BOARD_ID=1 KB_STAGE_BACKLOG=48
       out="$(cmd_create_card --name n --type t --column backlog --external-id "$IN" 2>&1 || true)"
       case "$out" in *"--external-id must be numeric"*) echo REJECT ;; *) echo ACCEPT ;; esac'
both "--external-id rejects U+0663"      "REJECT" "$AI3" "$EXTID"
both "--external-id accepts 99 (posctl)" "ACCEPT" "99"   "$EXTID"

# resolve_task: a non-numeric ref is an external_id LOOKUP, not a task id. Under the
# widened range it took the id branch and died in the arithmetic that follows it.
REFPATH='source "$BIN/kbcard" 2>/dev/null || true
         kb_api() { printf "%s" "{\"data\":[]}"; }
         export KB_BOARD_ID=1
         out="$( (resolve_task "$IN") 2>&1 || true)"   # sub-subshell: the failure path exits
         case "$out" in *"no task found with external_id"*) echo LOOKUP ;;
                        *"invalid task id"*) echo INVALID ;; *) echo "$out" ;; esac'
both "resolve_task treats U+0663 as an external_id" "LOOKUP" "$AI3" "$REFPATH"
both "resolve_task takes 4945 as an id (posctl)"    "4945"   "4945" "$REFPATH"

SWIM='source "$BIN/kbcard" 2>/dev/null || true
      out="$(swimlane_id "$IN" 2>/dev/null || true)"; [ -n "$out" ] && echo "$out" || echo REJECT'
both "swimlane_id rejects U+0663 as an id"   "REJECT" "$AI3" "$SWIM"
both "swimlane_id passes 7 through (posctl)" "7"      "7"    "$SWIM"

# native_type_id: the widened range let a non-ASCII KB_TYPE_* value reach bash arithmetic,
# which printed `[[: <x>: syntax error` on stderr while still falling back. The verdict is
# built from BOTH streams, so the noise is what this case is watching for.
NATIVE='source "$BIN/kbcard" 2>/dev/null || true
        export KB_TYPE_WIDGET="$IN"
        err="$(native_type_id widget 2>&1 >/dev/null || true)"
        out="$(native_type_id widget 2>/dev/null || true)"
        [ -n "$err" ] && { echo "NOISE:$err"; exit 0; }
        [ -n "$out" ] && echo "$out" || echo TAG-FALLBACK-CLEAN'
both "native_type_id falls back silently on U+0663" "TAG-FALLBACK-CLEAN" "$AI3" "$NATIVE"
both "native_type_id resolves 23 (posctl)"          "23"                 "23"   "$NATIVE"

# field --field: the widened range sent a non-ASCII value to `jq --argjson`, which errored and
# left `fld` empty — so the "not defined, here are the fields" message was still printed, just
# with a jq parse error stapled in front of it. The jq arm is therefore tested FIRST: an
# assertion that only looked for the named refusal passes on BOTH, and proves nothing.
FIELD='source "$BIN/kbcard" 2>/dev/null || true
       _kbc_fetch_fields() { printf "%s" "[{\"id\":10,\"key\":\"sev\",\"type\":\"enum\",\"options\":[]}]"; }
       export KB_BOARD_ID=1
       out="$(_kbc_field_set_options --field "$IN" --options a 2>&1 || true)"
       case "$out" in *rgjson*) echo JQ-ERROR ;;
                      *"is not defined on board"*) echo NAMED-REJECT ;; *) echo OTHER ;; esac'
both "field --field U+0663 → the named refusal" "NAMED-REJECT" "$AI3" "$FIELD"
both "field --field 10 resolves (posctl)"       "OTHER"        "10"   "$FIELD"

# ---------------------------------------------------------------------------
echo "== hooks/agent-dispatch-card-start — the BOARD-CARD marker parse (card#5409 SITE 2) =="
# kbcard is a PATH shim that records its argv; HOME is scratch, so only the board env the
# case creates exists. A parsed marker is observable as a recorded `move` call.
MARKER='T="$(mktemp -d)"; export HOME="$T"; mkdir -p "$T/bin"; : > "$T/.kanban-toolkit-board.env"
        export KBADS_REC="$T/calls"; : > "$KBADS_REC"
        { echo "#!/usr/bin/env bash"; echo "printf %s\\\\n \"\$*\" >> \"\$KBADS_REC\""; } > "$T/bin/kbcard"
        chmod +x "$T/bin/kbcard"; export PATH="$T/bin:$PATH"
        jq -n --arg p "BOARD-CARD: toolkit#$IN" "{tool_input:{prompt:\$p}}" \
          | bash "$ROOT/hooks/agent-dispatch-card-start" >/dev/null 2>&1
        if [ -s "$KBADS_REC" ]; then sed -n "1p" "$KBADS_REC"; else echo NO-PARSE; fi
        rm -rf "$T"'
both "marker does not parse a U+0663 card id" "NO-PARSE" "$AI3" "$MARKER"
both "marker parses 4945 (posctl)" "--board toolkit move --task 4945 --column in_progress" "4945" "$MARKER"

MARKER_KEY='T="$(mktemp -d)"; export HOME="$T"; mkdir -p "$T/bin"
            : > "$T/.kanban-$IN-board.env"; : > "$T/.kanban-toolkit-board.env"
            export KBADS_REC="$T/calls"; : > "$KBADS_REC"
            { echo "#!/usr/bin/env bash"; echo "printf %s\\\\n \"\$*\" >> \"\$KBADS_REC\""; } > "$T/bin/kbcard"
            chmod +x "$T/bin/kbcard"; export PATH="$T/bin:$PATH"
            jq -n --arg p "BOARD-CARD: $IN#4945" "{tool_input:{prompt:\$p}}" \
              | bash "$ROOT/hooks/agent-dispatch-card-start" >/dev/null 2>&1
            if [ -s "$KBADS_REC" ]; then echo PARSED; else echo NO-PARSE; fi
            rm -rf "$T"'
both "marker does not parse a U+2163 board key" "NO-PARSE" "$ROMAN4"  "$MARKER_KEY"
both "marker parses the toolkit key (posctl)"   "PARSED"   "toolkit"  "$MARKER_KEY"

# ---------------------------------------------------------------------------
echo "== promote-released-cards — the standalone's glob guards (uint_ok / uint_csv_ok) =="
# Network-free by ordering: both numeric guards run BEFORE the token check, and the
# --shipped-stages guard runs before the config file is even read. The ASCII positive
# control is the NEXT refusal in each sequence, which is what proves the guard passed.
PBOARD='D="$(mktemp -d)"; cd "$D"
        jq -n --arg b "$IN" "{version_file:\"VERSION\",
          promote:{board_id:\$b,released_stage_id:1,api_base:\"https://h/api/v3\"}}" > .release-pr.json
        unset KANBAN_WRITEBACK_TOKEN
        out="$(bash "$ROOT/bin/promote-released-cards" --dry-run 2>&1 || true)"
        case "$out" in *"board_id must be numeric"*) echo REJECT ;;
                       *"KANBAN_WRITEBACK_TOKEN is not set"*) echo PAST-GUARD ;; *) echo OTHER ;; esac
        rm -rf "$D"'
both "promote board_id rejects U+0663"        "REJECT"     "$AI3" "$PBOARD"
both "promote board_id accepts 12 (posctl)"   "PAST-GUARD" "12"   "$PBOARD"

PSTAGES='D="$(mktemp -d)"; cd "$D"
         out="$(bash "$ROOT/bin/promote-released-cards" --dry-run --shipped-stages "$IN" 2>&1 || true)"
         case "$out" in *"comma-separated list of numeric stage ids"*) echo REJECT ;;
                        *"no .release-pr.json in this repo"*) echo PAST-GUARD ;; *) echo OTHER ;; esac
         rm -rf "$D"'
both "promote --shipped-stages rejects U+0663"      "REJECT"     "$AI3"   "$PSTAGES"
both "promote --shipped-stages rejects 84,U+0663"   "REJECT"     "84,$AI3" "$PSTAGES"
both "promote --shipped-stages accepts 84,85 (posctl)" "PAST-GUARD" "84,85" "$PSTAGES"

# ---------------------------------------------------------------------------
echo "== dl-a1-register-field --sentinel + adopt-to-dl <card-id>/--issue =="
# A scratch HOME with a stub board env; the sentinel guard runs after config load and
# before any request, and the ASCII control's next stop is the (stubbed) create.
SENT='T="$(mktemp -d)"; export HOME="$T"
      printf "export KBCARD_API=\"https://kanban.test/api/v3\"\nexport KANBAN_EXPECTED_HOST=\"kanban.test\"\nexport KBCARD_TOKEN_FILE=\"$T/token\"\n" > "$T/.kanban-host.env"
      printf "export KB_BOARD_ID=1\nexport KB_STAGE_BACKLOG=48\n" > "$T/.kanban-t-board.env"
      printf "stub-token\n" > "$T/token"
      mkdir -p "$T/bin"; printf "#!/usr/bin/env bash\nexit 7\n" > "$T/bin/curl"; chmod +x "$T/bin/curl"
      export PATH="$T/bin:$PATH"
      out="$(bash "$ROOT/bin/dl-a1-register-field" --board t --sentinel "$IN" 2>&1 || true)"
      case "$out" in *"--sentinel must be a positive integer"*) echo REJECT ;; *) echo PAST-GUARD ;; esac
      rm -rf "$T"'
both "dl-a1 --sentinel rejects U+0663"              "REJECT"     "$AI3"       "$SENT"
both "dl-a1 --sentinel accepts 999000001 (posctl)"  "PAST-GUARD" "999000001"  "$SENT"

ADOPT='T="$(mktemp -d)"; export HOME="$T"
       out="$(bash "$ROOT/bin/adopt-to-dl" "$IN" --repo o/n 2>&1 || true)"
       case "$out" in *"<card-id> must be numeric"*) echo REJECT ;;
                      *"--board <name> is required"*) echo PAST-GUARD ;; *) echo OTHER ;; esac
       rm -rf "$T"'
both "adopt-to-dl <card-id> rejects U+0663"     "REJECT"     "$AI3"  "$ADOPT"
both "adopt-to-dl <card-id> accepts 4945 (posctl)" "PAST-GUARD" "4945" "$ADOPT"

ISSUE='T="$(mktemp -d)"; export HOME="$T"
       out="$(bash "$ROOT/bin/adopt-to-dl" 4945 --repo o/n --board t --issue "$IN" 2>&1 || true)"
       case "$out" in *"--issue must be a positive integer"*) echo REJECT ;;
                      *"not configured"*|*"no board env"*|*"board env"*) echo PAST-GUARD ;; *) echo OTHER ;; esac
       rm -rf "$T"'
both "adopt-to-dl --issue rejects U+0663"      "REJECT"     "$AI3" "$ISSUE"
both "adopt-to-dl --issue accepts 77 (posctl)" "PAST-GUARD" "77"   "$ISSUE"

# ---------------------------------------------------------------------------
echo "== .github/workflows/auto-tag-version.yml — the merge-time VERSION gate =="
# The definition is EXTRACTED from the shipped workflow rather than restated here, so a
# revert of that line is what this case sees. An empty extraction is a failure, not a skip.
WF="$ROOT/.github/workflows/auto-tag-version.yml"
_need -r "$WF"
VOK_DEF="$(grep -E '^[[:space:]]*version_ok\(\)' "$WF" | head -1 | sed 's/^[[:space:]]*//')"
if [[ -z "$VOK_DEF" ]]; then
    bad "auto-tag-version.yml no longer defines version_ok() — the VERSION gate's ASCII pin is gone"
else
    ok "extracted version_ok() from the shipped workflow"
    VREGEX="$(jq -r '.version_regex // empty' "$ROOT/.release-pr.json")"
    eq "the workflow's regex source is non-empty" "true" "$([[ -n "$VREGEX" ]] && echo true || echo false)"
    VER='eval "$VOK_DEF"; version_ok "0.23.$IN" "$VREGEX" && echo ACCEPT || echo REJECT'
    export VOK_DEF VREGEX
    both "VERSION gate rejects 0.23.<U+0663>" "REJECT" "$AI3" "$VER"
    both "VERSION gate accepts 0.23.1 (posctl)" "ACCEPT" "1"  "$VER"
fi

# ---------------------------------------------------------------------------
echo "== static backstop: no bare bash bracket-RANGE regex left in bin/ or hooks/ =="
# Behavior cases cannot reach every adopter (next-dl's three need a live board), and a NEW
# site would be born defective with no case watching it. This scan is the backstop: a
# `[[ =~ ]]` whose pattern carries a bracket range, on a non-comment line, with no
# `LC_ALL=C` on that line or the two above it.
#
# The exemption is that STRUCTURAL PROPERTY, not a list of blessed lines: "this range is
# matched under the C locale" is exactly what makes a range legitimate, and a hardcoded
# allow-list would have silently exempted any line that happened to look like one of them
# (an earlier draft's `[[ "$1" =~` exemption did precisely that, and let a re-minted
# kb_dl_num through). Both halves of the window rule are positive-controlled below.
#
# The matcher is an awk REGEX LITERAL, not a -v string: awk processes backslash escapes in
# a -v assignment, so `\[` would arrive as a bare `[` and the pattern would silently match
# nothing — the failure mode the positive control below exists to catch (it did).
scan_ranges() {
    local dir="$1"
    local files=()
    while IFS= read -r f; do files+=("$f"); done < <(find "$dir" -maxdepth 1 -type f | sort)
    [[ ${#files[@]} -gt 0 ]] || return 0
    awk '
        FNR == 1 { p1 = ""; p2 = "" }
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line ~ /^#/) { p2 = p1; p1 = $0; next }        # comments describe the defect
            if ($0 ~ /=~[^#]*\[\^?[A-Za-z0-9]-[A-Za-z0-9]/ && ($0 p1 p2) !~ /LC_ALL=C/)
                printf "%s:%d:%s\n", FILENAME, FNR, $0
            p2 = p1; p1 = $0
        }
    ' "${files[@]}" 2>/dev/null || true
    return 0
}
n_hits() { [[ -z "$1" ]] && { printf '0'; return 0; }; printf '%s\n' "$1" | wc -l | tr -d ' '; }

for d in "$BIN" "$ROOT/hooks"; do
    hits="$(scan_ranges "$d")"
    eq "no unscoped bracket-range regex in ${d##*/}/" "0" "$(n_hits "$hits")"
    [[ -n "$hits" ]] && printf '  offending lines:\n%s\n' "$hits" >&2
done

echo "== positive control: the scanner FLAGS a re-introduced bare range =="
pos="$TMP/pos"; mkdir -p "$pos"
printf '%s\n' '    [[ "$id" =~ ^[0-9]+$ ]] || die "not numeric"' > "$pos/reminted-digit"
printf '%s\n' 'if [[ "$k" =~ ^[A-Za-z0-9_-]+$ ]]; then :; fi'   > "$pos/reminted-alnum"
# The shape an exact-line allow-list would have exempted: a re-minted range spelled the same
# way as a legitimate one, but with no LC_ALL=C anywhere near it.
printf '%s\n' 'kb_dl_num() {' '    [[ "$1" =~ ^([Dd][Ll]-?)?0*([0-9]{1,6})$ ]] || return 2' '}' \
    > "$pos/reminted-lookalike"
printf '%s\n' '# [[ "$x" =~ ^[0-9]+$ ]] — described in a comment, not code' > "$pos/benign-comment"
printf '%s\n' 'kb_is_uint "$x" || die "not numeric"'             > "$pos/benign-adopter"
# The window rule's other half: scoped by an LC_ALL=C two lines above ⇒ NOT flagged.
printf '%s\n' 'marker() {' '    local LC_ALL=C' '    [[ "$1" =~ ^[A-Za-z0-9_-]+#([0-9]+) ]]' '}' \
    > "$pos/benign-scoped"
pos_hits="$(scan_ranges "$pos")"
eq "scanner flags exactly the three re-minted files" "3" "$(n_hits "$pos_hits")"
case "$pos_hits" in *reminted-digit:*)     ok "digit range flagged";;      *) bad "digit range NOT flagged";; esac
case "$pos_hits" in *reminted-alnum:*)     ok "alnum range flagged";;      *) bad "alnum range NOT flagged";; esac
case "$pos_hits" in *reminted-lookalike:*) ok "unscoped look-alike flagged";; *) bad "unscoped look-alike NOT flagged (an allow-list would have missed it)";; esac
case "$pos_hits" in *benign-comment:*) bad "a comment was flagged (filter too broad)";;   *) ok "comment not flagged";; esac
case "$pos_hits" in *benign-adopter:*) bad "an adopter was flagged (filter too broad)";;  *) ok "adopter not flagged";; esac
case "$pos_hits" in *benign-scoped:*)  bad "an LC_ALL=C-scoped range was flagged";;       *) ok "LC_ALL=C-scoped range not flagged";; esac

# Re-emit the degraded-coverage banner IMMEDIATELY before the verdict: a green summary is
# what a reader takes away, and half these cases did not run.
[[ -n "$UTF8_LOCALE" ]] || printf '  SKIP  (repeated) the UTF-8 half of every case above was NOT RUN — a pass here\n        certifies the C-locale behaviour only.\n' >&2
_summary "locale-range-guard-selftest"
