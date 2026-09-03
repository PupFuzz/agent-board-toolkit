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
# `kb_api POST|PATCH|DELETE` in `bin/` is a new candidate, and a population that is re-derived
# only when somebody remembers to is a population nobody is measuring. This is the method by
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
# UNIT — the CALL SITE. A line in `bin/` invoking the shared lib with a mutating method
# (`kb_api`/`kb_api_status` with POST, PATCH or DELETE) or a raw `curl -X` with one. Comment
# lines are excluded. That set IS the denominator and it is re-derived on every run.
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
#
# The CONTROL below is what makes the classifier a measurement rather than a decoration: two
# synthetic functions, one of each verdict, run through the same classifier. If it stops
# discriminating, this file exits 2 and says so — it does not print a population it can no
# longer justify.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

MUT_RE='kb_api(_status)?[[:space:]]+(POST|PATCH|DELETE)|curl[^|]*-X[[:space:]]+"?(POST|PATCH|DELETE)'
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

# --- the control: the classifier must answer differently for the two shapes ---
_control() {
    local fx; fx="$(mktemp)" || return 1
    cat > "$fx" <<'FIXTURE'
_ctl_unconfirmed() {
    kb_api PATCH "/tasks/$1.json" '{"x":1}' >/dev/null || return 1
    echo "done"
}
_ctl_confirmed() {
    kb_api PATCH "/tasks/$1.json" '{"x":1}' >/dev/null || return 1
    kb_api GET "/tasks/$1.json" >/dev/null || return 1
    echo "done"
}
FIXTURE
    local a b rc=0
    a="$(_classify "$fx" 2 | cut -f2)"
    b="$(_classify "$fx" 6 | cut -f2)"
    rm -f "$fx"
    [[ "$a" == "CANDIDATE" ]] || { echo "control: the unconfirmed fixture classified '$a', expected CANDIDATE" >&2; rc=1; }
    [[ "$b" == "CONFIRMED" ]] || { echo "control: the confirmed fixture classified '$b', expected CONFIRMED" >&2; rc=1; }
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
done < <(command grep -rnE "$MUT_RE" bin/ | command grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')

echo
echo "denominator — mutating call sites in bin/: $n_total"
echo "candidates  — no confirming read in scope: $n_cand"
echo
echo "A CANDIDATE is not a finding: read R1-R3 in this file's header before ruling on one."
