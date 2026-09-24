#!/usr/bin/env bash
# read-outcome-collapse-selftest.sh — a READ has three outcomes (present / absent /
# unreadable). This gate finds the shell sites that collapse them to two and then test the
# survivor for emptiness, and it reds on any such site this file does not already disposition.
#
# WHY THIS FILE EXISTS. Ten-plus cards on this repo are one class:
#
#     out="$(git ls-remote --tags "$REMOTE" … 2>/dev/null)" || return 1   # rc captured
#     FOUND="$(_remote_tag_sha || true)"                                  #  …and discarded
#     if [ -n "$FOUND" ]; then                                            # emptiness tested
#
# The middle line throws away the only signal that separates "the tag is not there" from "I
# could not look". The third line then scores the unreadable case as a MEASURED NEGATIVE, and
# the caller states the resulting claim with the same confidence it would state a real one.
# Nothing faults, nothing logs, and the answer is byte-identical to a true one — which is why
# every instance was found by reading rather than by a failure: `fetch_board_cards` answered an
# unreadable page-1 2xx with `RC=0 STDOUT=[[]]`, indistinguishable from an empty board
# (card#6594); a later unreadable page ended the scan as a short page and the truncated list
# was then PROMOTED FROM (card#6630); `next-dl` minted a DL from a floor it knew was incomplete
# (card#6631); `kbcard list` answered a board-wide description search with 0 (card#6771).
# Cards #6572 #6594 #6630 #6631 #6680 #6884 #7174 #6365 are the known roll.
#
# FIXING THE INSTANCES IS NOT CLOSING THE CLASS — measured, on this repo, twice. PR #274
# re-minted the shape ONE COMMIT after its own parent `b2071b9` closed it at
# `install-board-hooks`. That is the same lesson `prelude-shadow-selftest.sh` was built on and
# `docs/CONSOLIDATION-PLAN.md` states outright: *"Deleting the copies did not close the class,
# and the first cut of this section said it had… fixing N copies without the guard that forbids
# the N+1th leaves the cause in place."* This file is that guard, for this class. It is
# deliberately NOT a rewrite of the sites it lists — a disposition is a judgement recorded, and
# recording one is what makes the N+1th site cost an explicit edit here instead of nothing.
#
# ─────────────────────────── THE PREDICATE, STATED ───────────────────────────
#
# POPULATION — the SHIPPED shell, in BOTH the places it lives, composed from
# `tests/_shipped-shell-lib.sh` and re-derived on every invocation. No file list is stored
# here, so a new member is scanned the day it lands:
#
#   `_shipped_shell_files`      `bin/` + `hooks/`, one level, minus the python shims — the
#                               `bin`/`hooks` half of `.github/workflows/ci.yml`'s shellcheck
#                               expression, which that lib owns rather than this file copying.
#   `_runbook_invoked_checks`   the `tests/*.sh` files a tracked runbook INVOKES BY NAME in a
#                               fenced code block — shipped behaviour wearing a test's clothes.
#                               ⛔ The members are NOT named here; the denominator below PRINTS
#                               them by name on every run, which is the copy that cannot be
#                               wrong. The day a runbook step tells an operator to run another
#                               check, it is scanned with no edit to this file.
#
# ⛔ WHY THE SECOND HALF EXISTS, AND WHY IT IS NOT "add `tests/`" (card#10311). This gate ran
# GREEN over a live instance of its own class. PR #387 shipped `tests/framework-mirror-check.sh`
# with `_fw_cat "$DIR/$n" > "$tmp/mirror"` under `set -euo pipefail`: an unreadable mirror file
# killed the script at rc 1, which is the code that file's own header documents as STALE or
# DIVERGED — and `VERSIONING.md` release step 12 tells the operator to answer a non-zero rc by
# relaying a re-sync request to ANOTHER REPO'S OWNER. So an unreadable file produced a re-sync
# request for a file nobody ever read. That is shipped behaviour, and the gate built for exactly
# this class could not see it, because the population was `bin`+`hooks` and nothing else.
#
# ⛔ THE HARNESS IS STILL OUT, AND THAT EXCLUSION IS MEASURED RATHER THAN ASSERTED. The harness
# discards a read's status ON PURPOSE (a probe's rc IS the thing under test, and `expect_out`
# captures with `|| true` by design), so unioning `_selftest_shell_files` in would hand this
# file a pile of dispositions that mostly read "this is a test" — plus this file's OWN planted
# collapse fixture matching itself. Exemptions nobody reads are not coverage; they train the
# reader to stamp the next one unread, which is this gate's entire failure mode.
#
# ⛔ THAT PRICE IS NOT WRITTEN DOWN HERE, IT IS RE-MEASURED. A number in this comment would be a
# stale claim with a maintenance schedule (canon #16), and the figure the card was ruled on has
# already moved. So the denominator below prints `harness members this exclusion declines` on
# EVERY run, through the identical scanner, over `_selftest_shell_files` minus what the runbook
# derivation already pulls in. Nothing asserts on it — it is the cost of the ruling, kept live
# so the ruling can be re-argued against a current figure instead of a remembered one.
#
# ⛔ MEMBERSHIP IS DERIVED, NOT NAMED. A list of operator-run checks written into this file
# would be a restatement surface (canon #16) that cannot red when `VERSIONING.md` grows a step —
# card#6645's class, one layer up. The derivation and what it structurally cannot see are stated
# at `_runbook_invoked_checks` in `tests/_shipped-shell-lib.sh`; the control that it still
# matches SOMETHING on the real tree, and that it does not match a mere mention, is below.
#
# MEMBER — `<relpath>:<varname>`, NOT a line number. A line number rots on the next edit above
# it and would turn every disposition into a re-typing chore; the variable is what carries the
# collapsed outcome. Two captures of one variable in one file are therefore ONE member, and a
# disposition covers the variable, not a line. The raw per-capture records are still printed in
# the denominator, so the merge is visible rather than silent.
#
# A member is a CANDIDATE iff  (a) ∧ (b), both derived from the file:
#
#   (a) AN RC-DISCARDING READ CAPTURE. A command-substitution assignment whose failure status
#       the site does not keep. Four spellings, each reported by name in the denominator:
#         ||true          `V="$(cmd || true)"`, `V="$(cmd)" || :` — the status is thrown away.
#         ||print         `V="$(cmd || printf …)"` — replaced by a fabricated value.
#         ||assign-empty  `V="$(cmd)" || V=""` — the status is converted INTO the empty string,
#                         which is the collapse spelled out in one line.
#         rc-unexamined   `V="$(cmd 2>/dev/null)"` with no `||` tail at all — stderr is dropped
#                         and nothing looks at the status.
#       A tail that DOES examine the status — `|| return`, `|| exit`, `|| die`, `|| break`,
#       `|| continue`, `|| { … }` — is NOT a member: those sites kept the third outcome. That
#       exclusion is what makes this predicate discriminate rather than count assignments, and
#       it is asserted below against a fixture, not assumed.
#       Line continuations are joined before the test (`install-board-hooks`' probe puts its
#       `|| { … }` on the next physical line), and the line is truncated at its first TOP-LEVEL
#       `;` so a `||` belonging to a LATER statement on the same line is not attributed to the
#       capture (`release-pr-body`'s `TAG_FORMAT="$(cfg_opt …)"; [ -n … ] || TAG_FORMAT=…`).
#
#   (b) THE CAPTURED VALUE IS LATER TESTED FOR EMPTINESS — `-z`/`-n` on it, or compared against
#       `""` — on a non-comment line of the same file. Comment lines are excluded: a header
#       narrating `[[ -n "$page" ]]` is prose, not a test.
#
# ⛔ WHAT IS NOT SCRIPTABLE, AND IS THEREFORE THE DISPOSITION LIST'S JOB. (a) and (b) together
# derive a CANDIDATE — a site where the three outcomes ARE collapsed. Whether that collapse is
# a DEFECT is a judgement no regex can make, because it depends on what the site does next:
# `fetch_board_cards`' `-z "$data"` branch REFUSES and names what the refusal saved the caller
# from, while the identical shape one file over answers an operator with a confident wrong
# count. Both match. So the scanner owns the population and the list below owns the verdict,
# one line per member with its reason — and a member not in the list is RED, which is the only
# property that makes the pair worth anything.
#
# ⛔ WHAT IT STRUCTURALLY CANNOT SEE — stated so it is not over-cited:
#   * A collapse that never touches a VARIABLE: `if [ -n "$(cmd 2>/dev/null)" ]`, or a bare
#     `cmd 2>/dev/null | wc -l` scored as a count. There is nothing to key a disposition on.
#   * A collapse carried across a FUNCTION BOUNDARY — a helper that returns "" for both
#     outcomes, whose caller tests emptiness with no `2>/dev/null` in sight.
#   * Python. `bin/*.py` is excluded with CI's own shellcheck expression; the class exists there
#     too (`_dependabot-reconcile.py`'s directory reads) and is not covered here.
#   * The bash embedded in this repo's composite actions — the population
#     `tests/composite-action-wiring-selftest.sh` derives every run, not a list written here.
#   * Whether a DISPOSITIONED reason is TRUE. It is a recorded judgement, re-read by whoever
#     next edits that site — not a proof.
#   * Leg (b) matches the name anywhere in the file, so a same-named variable in an unrelated
#     function counts. That over-collects, which errs RED — a spurious member demanding a
#     disposition, never a real one going quiet.
#
# ⛔ `command grep`, never bare `grep`: in an interactive Claude Code shell `grep` is a function
# execing `ugrep --ignore-files`, which honours `.gitignore` and still exits 0 — a truncated
# sweep that reads as a clean one. Every read here goes through awk or `command grep`.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
# shellcheck source=tests/_shipped-shell-lib.sh
source "$HERE/_shipped-shell-lib.sh"
ROOT="$(cd "$HERE/.." && pwd)"

# ── the disposition list ────────────────────────────────────────────────────────────────────
#
# "<relpath>:<var>|<reason it is permitted>". Every currently-known candidate, one line each.
# A candidate NOT listed here reds this test; a line here naming a candidate the scanner no
# longer derives ALSO reds it, so the list cannot outlive what it excuses (the stale-exception
# hole `prelude-shadow-selftest.sh` closes on its own allow-list).
#
# Reasons fall into three shapes, and the shape is legible from the wording:
#   NO READ      — the capture is a pipeline over a string already in memory. `grep` over
#                  "$branch" has no third outcome to lose: rc 1 IS "absent".
#   SAME OUTCOME — absent and unreadable reach the same branch, and that branch REFUSES,
#                  degrades loudly, or makes no claim. The collapse is real and harmless.
#   DISPOSED     — the unreadable outcome is captured EARLIER, on its own branch, so this site
#                  only ever sees a value the caller already accepted.
DISPOSITIONED=(
  "bin/agent-board-toolkit-runtime-check:p|SAME OUTCOME — command -v: a tool this seat cannot resolve cannot be run, so 'missing' is true of absent and unreadable alike."
  "bin/agent-board-toolkit-runtime-check:newest|SAME OUTCOME — empty warns 'cannot judge staleness (UNKNOWN, not ok)' and continues; it never reports current. The offline case is named separately at the fetch above."
  "bin/agent-board-toolkit-runtime-check:rc_store_tok|SAME OUTCOME — the store rung answers rc 1 with nothing on stdout for every state it refuses (absent store, duplicated key, inline token, %-bearing or credential-shaped pointer), mirroring the lib's rung, which the TOOLS also resolve nothing from. 'No usable pointer' and 'no store' must therefore both mean 'not a source here'; the lib is what speaks about a refused store, at each tool's use site."
  "bin/agent-board-toolkit-runtime-check:d|SAME OUTCOME — a digest is empty only when nothing could produce one (no sha256sum, or the file stopped being readable between the two probes), and the emptiness test IS the honest-UNKNOWN branch: it warns 'CANNOT BE VERIFIED (UNKNOWN, not ok)' and classifies nothing. A verdict is never derived from a missing digest."
  "bin/agent-board-toolkit-runtime-check:v|NO READ of the answer — the subshell's rc is the SOURCED env file's last-command status, which says nothing about whether that file DECLARED KBCARD_TOKEN_FILE; the declaration's presence is exactly the emptiness test. Same contract as the lib's kb_board_env_get, which reports an empty line for a var the file does not set."
  "bin/board-card-start:dltok|NO READ — grep over \$branch, already in memory."
  "bin/board-card-start:root|SAME OUTCOME — on the mover both take the same fail-soft bcs_skip: no card moves and no board claim is made. On --lint an empty root leaves the board empty, which no decided verdict record can match (resolved and absent are only ever written with a board), so the board verdict leg speaks — NOT RECORDED, STALE or NOT CHECKED; never a clean verdict."
  "bin/board-card-start:board|SAME OUTCOME — an unresolvable board id from either source takes the same bcs_skip on the mover (no card moves; the verdict record says 'not checked'). On --lint no decided verdict record can match an empty board — resolved and absent are only ever written with one — so the board verdict leg speaks (NOT RECORDED, STALE or NOT CHECKED) — never a clean verdict — and its STALE text says only that the repo 'now maps to no board', claiming neither cause."
  "bin/board-card-start:board_envf|SAME OUTCOME — on the mover no per-board env is the normal case and the token falls back to the host default, which is also what an unreadable env leaves in place. --lint does not read it. Residual: kb_board_env_for skips an unreadable env file, so the mover's stage-id skip says 'no env has KB_BOARD_ID' where one exists but cannot be read."
  "bin/board-card-start:cur|DISPOSED — the unreadable HTTP outcome is refused above ('the card was NOT confirmed missing'); this jq only reads a body already accepted."
  "bin/board-card-start:curdl|DISPOSED — same already-accepted body; an empty dl_number stamps, and the stamp is fail-soft and conflict-guarded."
  "bin/board-card-start:want|SAME OUTCOME — kb_dl_canon over an in-memory \$dl; empty writes nothing at all (fail-closed on the write)."
  "bin/board-session-close:pdir|NO READ — grep over \$PATH, already in memory."
  "bin/board-session-close:root|DISPOSED — git's own refusal is captured and reported one branch above (rc 1); reaching this line means git answered, and the comment says so."
  "bin/board-session-close:p|SAME OUTCOME — readlink -f with an explicit '|| printf' identity fallback; emptiness was already refused at the command -v above."
  "bin/board-session-close:itgt|SAME OUTCOME — empty quotes the installer's OWN refusal instead of inventing a target; unreadable and refusing land on the same correct text."
  "bin/board-session-close:main|SAME OUTCOME — a sibling checkout that cannot be resolved and one that does not exist both mean 'that is not the fix'."
  "bin/board-session-close:pr_key|SAME OUTCOME — the empty branch NAMES the unreadable remote and keeps the repo in the section rather than de-duplicating it away."
  "bin/board-snapshot:untri_buf|SAME OUTCOME — mktemp is a WRITE, not a read; the empty branch interleaves the untriaged lines instead of losing them, and says so."
  "bin/board-stats:page|SAME OUTCOME — empty sets err='changelog page N is not the shape this tool reads' and breaks; the transport failure above is its own captured branch."
  "bin/board-stats:obj|SAME OUTCOME — empty emits a stub object carrying the board identity and an explicit failure string, so no board is ever dropped from the report."
  "bin/card-completeness:IDS|NO READ — grep over \$CARDS_IN, the caller's own --cards value, already in memory; an empty result dies '--cards … contains no card ids' before any request, so no verdict is ever built from it."
  "bin/install-board-hooks:root|SAME OUTCOME — both exit 1 'cannot resolve the work-tree root'; git's own refusal is captured separately just above."
  "bin/install-board-hooks:cdir|SAME OUTCOME — both exit 1 'cannot resolve the git common directory', the fail-closed direction for an installer."
  "bin/install-board-hooks:super|SAME OUTCOME — an unresolvable superproject and no superproject both take the non-submodule wording; the install target is unchanged either way."
  "bin/_kb-board-lib.sh:qextra|SAME OUTCOME — empty returns 5 with 'no request was issued, nothing was read'; refusing the widest wrong answer IS this site's purpose."
  "bin/_kb-board-lib.sh:last_page|SAME OUTCOME — deliberately UNKNOWN on anything but a positive integer (card#4623), so an unreadable meta falls through to the primary short-page break rather than terminating the scan."
  "bin/_kb-board-lib.sh:data|FIXED HERE — this IS the class's fix (card#6594/#6630): empty refuses and names what the refusal saved the caller from. The header records the one accepted residual (a board the token cannot see returns the same well-formed empty envelope)."
  "bin/kbcard:board|SAME OUTCOME — documented at the site: a partial or empty census only removes twins (more conservative), and this site makes no operator-facing claim."
  "bin/kbcard:name|NO READ of a third outcome — _kbc_user_name is a pure scan of this shell's own KB_USER_* variables: it prints a name at rc 0 and prints NOTHING at rc 1, so empty IS 'this board env maps no name for that id', which is the only thing the emptiness test asks. Nothing is fetched, opened or parsed, so there is no unreadable state to lose, and the empty branch renders the RAW id (\`user <n>\`) rather than claiming a name it does not have."
  "bin/kbcard:decision|SAME OUTCOME — the --force escape hatch, documented: an empty decision still writes the audited override line, never a silent forced archive; the non-force branch keeps no '||' and fails closed."
  "bin/next-dl:n|SAME OUTCOME — the local CLAUDE_DECISIONS.md scan is a FLOOR by construction and the code says so; the authoritative leg is the board read, which REFUSES the mint on any non-zero paginator rc (card#6631). Residual: an existing-but-unreadable header file scores as no DLs, lowering only the floor."
  "bin/promote-released-cards:DL_NUMS|NO READ — grep over \$DLS_IN / \$SUBJECTS, already in memory; an all-empty ref set exits 0 'nothing to do' and moves no card."
  "bin/promote-released-cards:BASE|SAME OUTCOME — empty dies 'refusing a full-history sweep'; both outcomes refuse, and a LOCAL-tag baseline is named on stderr."
  "bin/promote-released-cards:last_page|SAME OUTCOME — the co-vendored twin of the lib's rule (card#4623); unknown falls through to the short-page break."
  "bin/release-artifacts-check:EXTRACTED_VERSION|DISPOSED — the git show failure dies one line above; the '|| true' is the documented SIGPIPE guard on a pipeline over \$content, already in memory, and empty dies rather than classifying the PR."
  "bin/release-pr-body:VERSION|SAME OUTCOME — the file's presence gates the if, and empty dies 'could not resolve version'; both outcomes refuse."
  "bin/release-pr-body:LOCAL_TIP|SAME OUTCOME — an absent local ref is the normal case under this release flow; the branch only prints an advisory note and the baseline uses the remote tip either way."
  "bin/release-pr-body:LOCAL_DEV|SAME OUTCOME — the head leg's twin of LOCAL_TIP above (card#7517): an absent local integration ref is the normal case in a fresh release clone, the branch only prints an advisory note, and the range uses the remote tip either way. The fetch that could fail is captured and dies above it."
  "bin/release-pr-body:REMOTE_DEV|SAME OUTCOME — read LOCAL-ONLY on purpose, on the explicit --head path that must not touch the network (card#7517): an origin/dev that is absent and one that cannot be read both mean 'this repo holds nothing fresher to compare the caller's ref against', and both suppress an advisory note only — the ref the caller named is used unchanged in either case."
  "bin/release-pr-body:BASE|SAME OUTCOME — an empty BASE collapses RANGE to HEAD_REF deliberately (the first-ever release); the fetch that could fail is captured and dies above."
  "bin/release-pr-body:ref|NO READ — grep over \$subj, already in memory."
  "bin/release-pr-body:promote|SAME OUTCOME — falls back to the sibling directory, then returns BEFORE any coverage line is printed, so an unresolvable mover yields no coverage report rather than a clean one."
  "bin/release-pr-body:miss|DISPOSED — the mover's rc is captured at the call ('&& rc=0 || rc=\$?') and a non-zero rc prints 'could not run'; this grep only reads output already accepted."
  "bin/release-pr-body:stranded|DISPOSED — line 2 of the mover's no-card report (card#8421), read at the same site and out of the same already-accepted \$out as miss above: the mover's rc is captured at the call ('&& rc=0 || rc=\$?') and a non-zero rc prints 'could not run' and RETURNS before either grep runs."
)

# ── the derivation ──────────────────────────────────────────────────────────────────────────
#
# awk, not grep: joining line continuations and truncating at a top-level `;` are both stateful
# scans a line-oriented match cannot do, and leg (b) needs a second pass over the same file.
_roc_awk='
function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
# stmt(L) — L truncated at its first `;` that is outside quotes and outside every $( ).
function stmt(L,   i, c, n, q, d, out) {
    n = length(L); q = ""; d = 0; out = ""
    for (i = 1; i <= n; i++) {
        c = substr(L, i, 1)
        if (q != "") { out = out c; if (c == q) q = ""; continue }
        if (c == "\"" || c == SQ) { q = c; out = out c; continue }
        if (c == "$" && substr(L, i + 1, 1) == "(") { d++; out = out "$("; i++; continue }
        if (c == "(" && d > 0) { d++; out = out c; continue }
        if (c == ")" && d > 0) { d--; out = out c; continue }
        if (c == ";" && d == 0) break
        out = out c
    }
    return out
}
# tested(v) — is v tested for emptiness on any non-comment line of this file?
function tested(v,   j, L, reA, reB) {
    reA = "-[zn][[:space:]]+\"?\\$\\{?" v "([^A-Za-z0-9_]|$)"
    reB = "\"\\$\\{?" v "\\}?\"[[:space:]]*(=|!=|==)[[:space:]]*\"\""
    for (j = 1; j <= NR; j++) {
        L = lines[j]
        if (L ~ /^[[:space:]]*#/) continue
        if (L ~ reA || L ~ reB) return 1
    }
    return 0
}
BEGIN { SQ = sprintf("%c", 39) }
{ lines[NR] = $0 }
{
    if (cont != "") { L = cont " " $0 } else { L = $0; start = NR }
    if (L ~ /\\[[:space:]]*$/) { sub(/\\[[:space:]]*$/, "", L); cont = L; next }
    cont = ""
    S = stmt(L)
    if (S ~ /^[[:space:]]*#/) next
    if (S !~ /\$\(/) next
    if (!match(S, /^[[:space:]]*((local|declare|export|readonly)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=/)) next
    head = substr(S, RSTART, RLENGTH)
    v = head; sub(/=$/, "", v); sub(/^.*[[:space:]]/, "", v)
    # a tail that EXAMINES the status is not a member — this is the discriminating clause
    if (S ~ /\|\|[[:space:]]*(return|exit|die|break|continue|\{)/) next
    why = ""
    if (S ~ /\|\|[[:space:]]*(true|:)([^A-Za-z0-9_:-]|$)/) why = why "||true,"
    if (S ~ /\|\|[[:space:]]*(echo|printf)/) why = why "||print,"
    if (S ~ ("\\|\\|[[:space:]]*" v "=")) why = why "||assign-empty,"
    if (why == "" && S !~ /\|\|/ && S ~ /2>\/dev\/null/) why = "rc-unexamined,"
    if (why == "") next
    cv[++nc] = v; cl[nc] = start; cw[nc] = why
}
END {
    for (i = 1; i <= nc; i++) {
        v = cv[i]
        if (!(v in memo)) memo[v] = tested(v)
        if (memo[v]) printf "%s\t%s\t%s\t%s\n", REL, v, cl[i], trim(cw[i])
    }
}'

# _roc_population <root> — THE population, composed from `tests/_shipped-shell-lib.sh`: the
# shipped shell, plus the `tests/` files a tracked runbook tells an operator to RUN. Both halves
# are re-derived from the tree on every call; neither is a list in this file. The runbook half's
# status is KEPT (`|| return`) — a tree whose index cannot be read must not arrive here as a
# tree whose runbooks invoke nothing, which is this gate's own class.
_roc_population() {
    local root="$1" runbook
    runbook="$(_runbook_invoked_checks "$root")" || return $?
    { _shipped_shell_files "$root"; printf '%s\n' "$runbook"; } | awk 'NF' | LC_ALL=C sort -u
}

# _roc_records <root> — one TAB record per candidate CAPTURE: relpath, var, line, why.
_roc_records() {
    local root="$1" rel
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        awk -v REL="$rel" "$_roc_awk" "$root/$rel"
    done < <(_roc_population "$root")
}

# _roc_members <root> — the candidate MEMBERS (`relpath:var`), C-collated and deduped.
_roc_members() {
    _roc_records "$1" | awk -F'\t' '{ print $1 ":" $2 }' | LC_ALL=C sort -u
}

# _roc_records_over <root> <relpath>… — the same scanner driven over an EXPLICIT file list, so
# the declined-harness price below is measured by the identical code path rather than by a
# second spelling of it.
_roc_records_over() {
    local root="$1" rel; shift
    for rel in "$@"; do
        [[ -n "$rel" ]] || continue
        awk -v REL="$rel" "$_roc_awk" "$root/$rel"
    done
}

# ── controls: the scanner must be able to find something, and must not find everything ──────
#
# The two assertions this gate actually ships are ABSENCE assertions ("no undispositioned
# member", "no stale disposition"), and a scanner that matches NOTHING satisfies both while
# measuring nothing at all. A planted positive is therefore asserted FIRST, and a planted
# negative beside it — a fixture proving the predicate DISCRIMINATES is what separates it from
# a decoration that happens to be quiet.
_mktmp_scratch
FIX="$TMP/fixture"; mkdir -p "$FIX/bin" "$FIX/tests"
# The fixture is a real (throwaway) git repo because the runbook half of the population reads
# `git ls-files` — the tracked-markdown set is what decides whether a doc is part of this tree.
( cd "$FIX" && git init -q . ) >/dev/null 2>&1

# POSITIVE — the canonical live shape, verbatim from bin/release-tag-check's _remote_tag_sha.
cat > "$FIX/bin/planted-collapse" <<'EOF'
#!/usr/bin/env bash
_remote_tag_sha() {
    local out
    out="$(git ls-remote --tags "$REMOTE" "refs/tags/$1" 2>/dev/null)" || return 1
    printf '%s' "$out"
}
FOUND="$(_remote_tag_sha "$TAG" || true)"
if [ -n "$FOUND" ]; then
    echo "tag exists"
fi
EOF

# NEGATIVE 1 — leg (a) fails: the status is KEPT. Same read, same emptiness test.
cat > "$FIX/bin/planted-rc-kept" <<'EOF'
#!/usr/bin/env bash
kept="$(git ls-remote --tags origin 2>/dev/null)" || die "cannot read the remote"
[ -n "$kept" ] || die "no tags"
EOF

# NEGATIVE 2 — leg (b) fails: the status is discarded but nothing ever tests for emptiness.
cat > "$FIX/bin/planted-no-empty-test" <<'EOF'
#!/usr/bin/env bash
loose="$(git ls-remote --tags origin 2>/dev/null || true)"
printf '%s\n' "$loose"
EOF

# NEGATIVE 3 — the `;` clause: the `||` belongs to a LATER statement, not to the capture.
cat > "$FIX/bin/planted-later-stmt" <<'EOF'
#!/usr/bin/env bash
FMT="$(cfg_opt '.tag_format')"; [ -n "$FMT" ] || FMT='v{{version}}'
EOF

# ── the POPULATION control: two identical collapses under tests/, one reachable, one not ─────
#
# The widening this file carries (card#10311) is a claim about WHICH `tests/` files are in
# scope, and a population claim cannot be proven by the tree it was drawn around — on the real
# tree the one member contributes NO candidate today, so a green run says nothing about
# whether the widening reaches it. These two files carry the SAME planted collapse and differ
# in exactly one thing: the fixture runbook RUNS one of them and merely MENTIONS the other.
cat > "$FIX/tests/planted-runbook-check.sh" <<'EOF'
#!/usr/bin/env bash
MIRROR="$(cat "$DIR/$n" 2>/dev/null || true)"
[ -n "$MIRROR" ] || echo "STALE or DIVERGED"
EOF
cat > "$FIX/tests/planted-harness-only.sh" <<'EOF'
#!/usr/bin/env bash
HARNESS="$(cat "$DIR/$n" 2>/dev/null || true)"
[ -n "$HARNESS" ] || echo "STALE or DIVERGED"
EOF
# The fixture runbook. Three shapes the derivation must tell apart, all naming a `tests/…sh`:
# an INVOCATION inside a fence, a fenced line where the path is an ARGUMENT rather than the
# command word, and a prose/link mention outside any fence.
{ printf 'Prose naming `tests/planted-harness-only.sh`, and a [link](tests/planted-harness-only.sh).\n'
  printf '\n```bash\n'
  printf 'tests/planted-runbook-check.sh --ref origin/dev <somewhere>\n'
  printf 'cat tests/planted-harness-only.sh   # named as an ARGUMENT, not run\n'
  printf '```\n'
  printf '\nMore prose about tests/planted-harness-only.sh, outside every fence.\n'; } > "$FIX/RUNBOOK.md"
( cd "$FIX" && git add bin tests RUNBOOK.md ) >/dev/null 2>&1

echo "== the runbook derivation discriminates (population control) =="
eq "only the check the runbook RUNS is in the population — an argument and a mention are not" \
   "tests/planted-runbook-check.sh" "$(_runbook_invoked_checks "$FIX")"
# A REAL directory that is simply not a git repo — not a missing path, which would be refused
# one step earlier by `cd` and would leave the `git ls-files` status untested.
mkdir -p "$TMP/no-index"
eq "an index that cannot be read is UNMEASURED (rc 3), never a tree whose runbooks invoke nothing" "3" \
   "$(_runbook_invoked_checks "$TMP/no-index" >/dev/null 2>&1; echo $?)"

echo "== the scanner finds a planted collapse (positive control) =="
eq "the canonical shape is derived as a member, in bin/ AND in a runbook-invoked check" \
   "$(printf 'bin/planted-collapse:FOUND\ntests/planted-runbook-check.sh:MIRROR')" \
   "$(_roc_members "$FIX")"

echo "== the scanner discriminates (negative controls) =="
PLANTED_WHY="$(_roc_records "$FIX" | awk -F'\t' '$2 == "FOUND" { print $4 }')"
eq "the planted member is reported as an rc discard" "||true," "$PLANTED_WHY"
has_kept="$(has "planted-rc-kept" "$(_roc_members "$FIX")")"
eq "a capture whose rc is KEPT (|| die) is not a member" "false" "$has_kept"
has_noempty="$(has "planted-no-empty-test" "$(_roc_members "$FIX")")"
eq "a discarded rc never tested for emptiness is not a member" "false" "$has_noempty"
has_later="$(has "planted-later-stmt" "$(_roc_members "$FIX")")"
eq "a '||' in a later statement on the same line is not attributed to the capture" "false" "$has_later"
has_harness="$(has "planted-harness-only" "$(_roc_members "$FIX")")"
eq "an identical collapse in a tests/ file NO runbook runs is not a member (the harness stays out)" \
   "false" "$has_harness"

# ── the denominator ─────────────────────────────────────────────────────────────────────────
#
# Printed on EVERY run, clean or not. A clean result over an unnamed population reports where
# the searcher stopped, not the state of the tree — so this gate states the population it was
# clean over, re-derived from the tree by the same code path that judges it.
mapfile -t POPULATION < <(_roc_population "$ROOT")
mapfile -t RUNBOOK_CHECKS < <(_runbook_invoked_checks "$ROOT")
mapfile -t RECORDS < <(_roc_records "$ROOT")
mapfile -t MEMBERS < <(_roc_members "$ROOT")

# THE PRICE OF THE STATED EXCLUSION, re-measured every run rather than written down (canon #16):
# what unioning the whole harness in would ADD, through the identical scanner. Asserted on by
# nothing — it exists so the ruling "the harness stays out" is re-arguable against a live figure.
mapfile -t DECLINED_HARNESS < <(
    LC_ALL=C comm -23 <(_selftest_shell_files "$ROOT") <(printf '%s\n' "${RUNBOOK_CHECKS[@]}" | awk 'NF') \
    | { mapfile -t h; _roc_records_over "$ROOT" "${h[@]:-}"; } | awk -F'\t' 'NF { print $1 ":" $2 }' | LC_ALL=C sort -u
)

LISTED="$(printf '%s\n' "${DISPOSITIONED[@]}" | awk -F'|' 'NF { print $1 }' | LC_ALL=C sort -u)"
DERIVED="$(printf '%s\n' "${MEMBERS[@]}" | awk 'NF')"
NEW="$(LC_ALL=C comm -23 <(printf '%s\n' "$DERIVED") <(printf '%s\n' "$LISTED"))"
STALE="$(LC_ALL=C comm -13 <(printf '%s\n' "$DERIVED") <(printf '%s\n' "$LISTED"))"

_count() { printf '%s\n' "$1" | awk 'NF' | wc -l | tr -d ' '; }

echo "== denominator [read-outcome-collapse/v2] =="
printf '  shell files scanned (bin/ + hooks/ + runbook-invoked checks) : %s\n' "${#POPULATION[@]}"
printf '  of those, tests/ files a tracked runbook INVOKES by name     : %s\n' "$(_count "$(printf '%s\n' "${RUNBOOK_CHECKS[@]}")")"
printf '%s\n' "${RUNBOOK_CHECKS[@]}" | awk 'NF { printf "    %s\n", $0 }'
printf '  rc-discarding captures ALSO tested for emptiness             : %s\n' "${#RECORDS[@]}"
printf '  candidate MEMBERS (<file>:<var>, captures merged)            : %s\n' "$(_count "$DERIVED")"
printf '  dispositioned below                                          : %s\n' "$(_count "$LISTED")"
printf '  NEW / undispositioned                                        : %s\n' "$(_count "$NEW")"
printf '  stale dispositions (listed, no longer derived)               : %s\n' "$(_count "$STALE")"
printf '  harness members this exclusion DECLINES (not asserted on)    : %s\n' \
    "$(_count "$(printf '%s\n' "${DECLINED_HARNESS[@]}")")"
printf '  by rc-discard spelling:\n'
printf '%s\n' "${RECORDS[@]}" | awk -F'\t' 'NF { n[$4]++ } END { for (k in n) printf "    %-16s %s\n", k, n[k] }' | LC_ALL=C sort

echo "== the derivation carries real data (control on the REAL tree) =="
eq "the scan of $ROOT derived at least one candidate" "false" \
   "$([[ "${#RECORDS[@]}" -eq 0 ]] && echo true || echo false)"
# A derivation that has silently stopped matching is indistinguishable from a repo whose
# runbooks invoke nothing — and the whole point of card#10311 is that this gate once WAS blind
# to an operator-run check and ran green. Zero here means the widening is inert; it reds.
eq "the runbook derivation names at least one operator-run check on the REAL tree" "false" \
   "$([[ "$(_count "$(printf '%s\n' "${RUNBOOK_CHECKS[@]}")")" -eq 0 ]] && echo true || echo false)"
# Every runbook-derived member must be a file that EXISTS and is scannable here; a runbook
# naming a check this tree does not carry is a broken release step, and silently dropping it
# would put the population back where it was.
missing_runbook=""
for rb in "${RUNBOOK_CHECKS[@]}"; do
    [[ -n "$rb" ]] || continue
    [[ -r "$ROOT/$rb" ]] || missing_runbook+="$rb"$'\n'
done
eq "a runbook invokes a check this tree does not carry (fix the runbook, or restore the check)" \
   "" "${missing_runbook%$'\n'}"

echo "== every candidate is dispositioned =="
eq "undispositioned read-outcome collapse (add a line to DISPOSITIONED with its reason, or fix the site)" "" "$NEW"

echo "== no disposition outlives the site it excuses =="
eq "listed member the scanner no longer derives (drop the line)" "" "$STALE"

echo "== every disposition carries a reason =="
noreason=""
for d in "${DISPOSITIONED[@]}"; do
    [[ "$d" == *"|"* ]] && [[ -n "${d#*|}" ]] || noreason+="${d}"$'\n'
done
eq "disposition with no reason" "" "${noreason%$'\n'}"

echo "== no member is dispositioned twice =="
dupes="$(printf '%s\n' "${DISPOSITIONED[@]}" | awk -F'|' 'NF { print $1 }' | LC_ALL=C sort | uniq -d)"
eq "duplicate disposition key" "" "$dupes"

_summary "read-outcome-collapse-selftest"
