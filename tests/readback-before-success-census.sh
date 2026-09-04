#!/usr/bin/env bash
# readback-before-success-census.sh — a CENSUS INSTRUMENT, not a gate. It re-derives the
# population of one defect class across `bin/` and prints it. It asserts nothing about that
# population and is deliberately NOT named `*-selftest.sh`, so `ci-matrix-parity-selftest.sh`'s
# orphan gate (whose population IS `tests/*-selftest.sh`) does not claim it, `suite-home
# -containment`'s `*selftest*` glob does not run it, and it is wired into no workflow. It is the
# same shape, and for the same reason, as `hand-enumerated-population-census.sh` beside it.
#
# THE DEFECT CLASS (card#8556). A mutating verb reports success it never READ BACK: it issues
# its write, the status class says 2xx, and it prints a success built out of what it SENT rather
# than out of a read of what the server now holds. So a mutation the server did not apply
# reaches the caller as applied. `kbcard delete --hard` was the severe member — a false success
# there says the DL ref is released, and that release is an input to the next DL mint
# (docs/DL-COUNTER-RECOVERY.md § Why it strands), so the wrong answer propagates into the
# numbering instead of stopping at one bad print.
#
# WHY IT EXISTS AT ALL, given the fix has landed. The population is not fixed: every new
# mutating write in `bin/` is a new candidate, and a population that is re-derived only when
# somebody remembers to is a population nobody is measuring. This is the method by
# which a later pass RE-COMPUTES it — cheap enough to actually run — rather than a number in a
# document that goes stale the day a bin gains a write.
#
# ⛔ WHY EVERY SWEEP HERE USES `command grep`. In an interactive Claude Code shell `grep` is a
# shell FUNCTION that execs `ugrep --ignore-files`, which silently honours `.gitignore` and
# still exits 0 — a truncated sweep that looks exactly like a clean result. A census that
# under-reports its own population reproduces the defect it is hired to measure.
#
# ─────────────────────────── THE PREDICATE, STATED ───────────────────────────
#
# UNIT — the CALL SITE. A line in `bin/` that names a mutating HTTP method: the shared lib
# invoked with one (`kb_api`/`kb_api_status` with POST, PATCH or DELETE), or a `-X` carrying
# POST, PATCH, DELETE **or a variable** (`-X "$method"`). Comment lines are excluded and NOTHING
# ELSE IS — the denominator has no exemption list, which is what lets it equal the predicate
# exactly. It is re-derived on every run.
#
# ⚠ THE `-X` HALF DELIBERATELY DOES NOT REQUIRE THE COMMAND WORD TO BE `curl`, and it admits a
# VARIABLE method. Both halves of that were once absent and both hid a live member of the class:
#   * `bin/promote-released-cards`'s writes go through a local `api()` wrapper — `api -X PATCH
#     … "$API/tasks/$id.json"` — so a `curl`-anchored pattern reported the whole file, a CARD
#     MOVER, as having no writes in it at all.
#   * `bin/next-dl`'s one transport spells the method as `-X "$method"`, so a pattern requiring
#     a literal verb could not see the DL-sequence claim POST.
# An instrument that greps a NAME answers about the NAME. Both were found by a review of this
# file, not by this file, which is the reason the exemption list is empty.
#
# ⚠ THE SHARED TRANSPORT IS ITSELF IN THE POPULATION, on purpose. `bin/_kb-board-lib.sh`'s two
# `curl` argument builds (`kb_api`, `kb_api_status`) are what every `kb_api` site in the table below resolves
# to, and they report as CANDIDATE forever: a transport does not read back, and a transport that
# did would be reading back for callers that have not asked. They are NOT subtracted, for R3's
# reason — subtracting needs this file to rule on which sites make a success claim, which is the
# judgement it hands the reader rather than makes. Two rows of known noise are cheaper than an
# exemption list, because an exemption list is where the next missed member hides.
#
# SCOPE — the enclosing function, or (for a call at file scope) the rest of the file.
#
# A site is CONFIRMED iff a CONFIRMING READ appears in its scope AFTER it — a `kb_api GET`, or
# one of the file-local read owners in READ_RE below, reached either directly or through a
# helper called after the site whose body contains one. Everything else is a CANDIDATE.
#
# ⚠ WHAT THIS PREDICATE STRUCTURALLY CANNOT SEE — stated because a census that reads as total
# and is not is worse than a narrow one:
#   R1  A read-back that lives one level UP, in the CALLER of a mutating primitive. The
#       conversion POST in `_kbc_field_change_type_call` is exactly that shape: its caller
#       `_kbc_field_retype` owns the confirming read, and this instrument reports the primitive
#       as a candidate. A candidate is not a finding.
#   R2  Whether a confirming read is confirming the RIGHT thing. Presence of a GET after a write
#       is structural; that its predicate matches the intent is per-site work.
#   R3  A site that makes no success claim at all. `delete_throwaway` in dl-a1-register-field
#       is one: two best-effort PATCHes under `|| true` whose rc is discarded by an EXIT trap,
#       printing nothing. The EMITS column below is reported so a reader can see this, but it
#       is NOT subtracted — subtracting it would need this file to decide which emissions are
#       success claims, which is the judgement it exists to hand a reader rather than make.
#   R4  Anything outside `bin/`. The population is `bin/` by choice: that is where this repo's
#       API writes are.
#   R5  A wrapper that BAKES a MUTATING method inside its own body, so no method token appears
#       on the CALLER's line at all. The site reported would then be the wrapper's body and the
#       success claim would be one level up — R1's shape reached by a different road. No such
#       wrapper is in `bin/` today, and the way to see that is to enumerate the `curl`
#       INVOCATIONS rather than the word: run `command grep -rn 'curl ' bin/` and drop the hits
#       that are a `command -v` probe or a diagnostic naming curl in prose (most of them are),
#       which leaves six —
#       `_kb-board-lib.sh`'s `kb_api` and `kb_api_status` (method from the CALLER, and every
#       caller names it, which is MUT_RE's first alternative); `_kb-board-lib.sh`'s
#       `fetch_board_cards` and `bin/_shellcheck-pinned`'s pinned-binary download (no `-X` at
#       all, so plain GETs); `next-dl`'s `dl_sequence_call` and `promote-released-cards`'s
#       `api()` (both take the method from the caller, and both are matched). Not one of them
#       hardcodes POST, PATCH or DELETE. Re-run that enumeration; do not trust this note, which
#       is a measurement with a date on it and not a property of the language.
#
# The CONTROL below is what makes the classifier a measurement rather than a decoration. It runs
# on REAL `bin/` lines, never on a fixture this file wrote: a control that mints its own sample
# proves only the sample, and the sample it minted here was a two-function file fed to `_classify`
# by hand — so `MUT_RE`, the predicate that DEFINES the denominator, was never executed by it at
# all, and neither was the `<file-scope>` branch. Its three legs are stated with the leg they own:
#   * one real site of each VERDICT, so a classifier that stopped discriminating is caught;
#   * one real site that only `MUT_RE` can put in the sweep, so the denominator predicate is
#     executed rather than assumed — and that site is at FILE SCOPE, so the branch `_classify`
#     takes for a call outside any function is executed too.
# Each leg addresses its line by an ANCHOR grepped out of the file, never by a line number: a
# number in this file would rot on the next edit above it and red for the wrong reason. An anchor
# that no longer matches is itself a refusal — the control says which one and exits 2 rather than
# printing a population it can no longer justify.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

MUT_RE='kb_api(_status)?[[:space:]]+(POST|PATCH|DELETE)|-X[[:space:]]+"?(POST|PATCH|DELETE|\$)'
# The file-local read owners, by name. They are named rather than pattern-matched because each
# one IS a read of the mutated subject: the card, the card's links, the board's field index, the
# board's cards, the by-ref index.
READ_RE='kb_api(_status)?[[:space:]]+GET|_kbc_card_witness|_kbc_link_witness|_kbc_confirm_card|_kbc_fetch_fields|_kbc_field_populated|fetch_board_cards|by_ref_has'

# _classify <file> <line> — prints "<scope>\t<verdict>\t<emits>" for one call site.
# <verdict> is CONFIRMED or CANDIDATE; <emits> is stdout / stderr-only / silent, the R3 attribute.
_classify() {
    local file="$1" ln="$2" fstart fl fname fend win extra h hs he
    fstart="$(command grep -nE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$file" \
        | awk -F: -v L="$ln" '$1<=L{s=$1; n=$2} END{if (s) print s":"n}')"
    if [[ -n "$fstart" ]]; then
        fl="${fstart%%:*}"; fname="${fstart#*:}"; fname="${fname%%(*}"
        fend="$(awk -v s="$fl" 'NR>s && /^}/{print NR; exit}' "$file")"
        [[ -n "$fend" ]] || fend="$(wc -l < "$file")"
        # The last `name()` above the line may be a function that already CLOSED — then the
        # call is at file scope, not inside it.
        if [[ "$ln" -gt "$fend" ]]; then fname="<file-scope>"; fend="$(wc -l < "$file")"; fi
    else
        fname="<file-scope>"; fend="$(wc -l < "$file")"
    fi
    # Comments are stripped so a read owner NAMED in prose beside a site cannot confirm it.
    win="$(sed -n "${ln},${fend}p" "$file" | sed 's/[[:space:]]*#.*$//')"
    extra=""
    while read -r h; do
        [[ -n "$h" ]] || continue
        hs="$(command grep -nE "^${h}\(\)" "$file" | head -1 | cut -d: -f1)"
        [[ -n "$hs" ]] || continue
        he="$(awk -v s="$hs" 'NR>s && /^}/{print NR; exit}' "$file")"
        [[ -n "$he" ]] || continue
        extra+="$(sed -n "${hs},${he}p" "$file")"$'\n'
    done < <(printf '%s\n' "$win" | command grep -oE '\b_[a-z][a-z0-9_]*\b' | sort -u)

    local verdict="CANDIDATE" emits="silent"
    printf '%s\n%s\n' "$win" "$extra" | command grep -qE "$READ_RE" && verdict="CONFIRMED"
    if printf '%s\n' "$win" | command grep -qE '^[^#]*\b(echo|printf)\b' ; then
        emits="stderr-only"
        printf '%s\n' "$win" | command grep -E '^[^#]*\b(echo|printf)\b' | command grep -qv '>&2' \
            && emits="stdout"
    fi
    printf '%s\t%s\t%s\n' "$fname" "$verdict" "$emits"
}

# _sweep — THE DENOMINATOR, derived. The control and the population print below both call this,
# so the control exercises the predicate that actually produces the population rather than a
# second copy of it that can drift away from the one under test.
_sweep() {
    command grep -rnE "$MUT_RE" bin/ | command grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
}

# _ctl_line <file> <anchor-ere> — the line number of the ONE line matching <anchor-ere>. Returns
# 1 (printing nothing) unless it matches EXACTLY once: a control that silently addressed the
# first of several matches would be pinning a line nobody chose.
_ctl_line() {
    local file="$1" anchor="$2" hits
    hits="$(command grep -cE "$anchor" "$file")" || return 1
    [[ "$hits" -eq 1 ]] || return 1
    command grep -nE "$anchor" "$file" | cut -d: -f1
}

# --- the control: three legs, all on REAL bin/ lines ---
_control() {
    local rc=0 f ln got want

    # LEG 1 — a real CANDIDATE. `_kbc_field_change_type_call`'s conversion POST is the R1 shape
    # by name: its confirming read lives in its caller, so the classifier must report the
    # primitive as a candidate. Flip the classifier to CONFIRMED-by-default and this reds.
    f="bin/kbcard"
    ln="$(_ctl_line "$f" '^[[:space:]]*kb_api_status POST "/custom_fields/\$1/change-type\.json"')" || {
        echo "control: LEG 1's anchor (the change-type POST in $f) no longer matches exactly one line — the control cannot address the site it exists to classify" >&2
        return 1
    }
    got="$(_classify "$f" "$ln" | cut -f1,2)"; want=$'_kbc_field_change_type_call\tCANDIDATE'
    [[ "$got" == "$want" ]] || { echo "control: LEG 1 ($f:$ln, the change-type POST) classified '$got', expected '$want'" >&2; rc=1; }

    # LEG 2 — a real CONFIRMED, and the opposite verdict on the same classifier. `cmd_delete`'s
    # force-delete is followed in its own scope by the witness re-read this card added. Flip the
    # classifier to CANDIDATE-by-default and this reds.
    ln="$(_ctl_line "$f" '^[[:space:]]*kb_api POST "/tasks/\$task/force-delete\.json"')" || {
        echo "control: LEG 2's anchor (the force-delete POST in $f) no longer matches exactly one line — the control cannot address the site it exists to classify" >&2
        return 1
    }
    got="$(_classify "$f" "$ln" | cut -f1,2)"; want=$'cmd_delete\tCONFIRMED'
    [[ "$got" == "$want" ]] || { echo "control: LEG 2 ($f:$ln, the force-delete POST) classified '$got', expected '$want'" >&2; rc=1; }

    # LEG 3 — THE DENOMINATOR PREDICATE ITSELF, which legs 1 and 2 cannot reach: they are handed
    # a line, so `MUT_RE` never runs. This one asserts that a KNOWN write is in the sweep, and it
    # picks the write that a `curl`-anchored MUT_RE could not see — `promote-released-cards`
    # moving a card's stage through its local `api()` wrapper. It is also at FILE SCOPE, so it is
    # the leg that executes `_classify`'s <file-scope> branch. Narrow MUT_RE back to `curl…-X` and
    # this reds with the file named.
    f="bin/promote-released-cards"
    ln="$(_ctl_line "$f" '^[[:space:]]*if api -X PATCH .*workflow_stage_id')" || {
        echo "control: LEG 3's anchor (the wrapper-shaped stage PATCH in $f) no longer matches exactly one line — the control cannot assert a site it cannot address" >&2
        return 1
    }
    _sweep | cut -d: -f1,2 | command grep -qx "$f:$ln" || {
        echo "control: LEG 3 — $f:$ln is a card-stage PATCH through a local curl wrapper and MUT_RE does not put it in the sweep, so the printed denominator is NOT the population it claims" >&2
        rc=1
    }
    got="$(_classify "$f" "$ln" | cut -f1)"
    [[ "$got" == "<file-scope>" ]] || { echo "control: LEG 3 ($f:$ln) scoped '$got', expected '<file-scope>' — the file-scope branch is no longer exercised" >&2; rc=1; }

    return "$rc"
}

cd "$ROOT" || exit 2
if ! _control; then
    echo "readback-before-success-census: the classifier no longer DISCRIMINATES — refusing to print a population it cannot justify." >&2
    exit 2
fi

printf '%-42s  %-30s  %-9s  %s\n' 'SITE' 'SCOPE' 'VERDICT' 'EMITS'
n_total=0; n_cand=0
while IFS= read -r hit; do
    file="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
    IFS=$'\t' read -r scope verdict emits < <(_classify "$file" "$ln")
    n_total=$((n_total + 1))
    [[ "$verdict" == "CANDIDATE" ]] && n_cand=$((n_cand + 1))
    printf '%-42s  %-30s  %-9s  %s\n' "$file:$ln" "$scope" "$verdict" "$emits"
done < <(_sweep)

echo
echo "denominator — mutating call sites in bin/: $n_total"
echo "candidates  — no confirming read in scope: $n_cand"
echo
echo "A CANDIDATE is not a finding: read R1-R5 in this file's header before ruling on one."
