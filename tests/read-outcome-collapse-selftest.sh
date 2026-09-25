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
#   `_shipped_shell_files`   `bin/` + `hooks/`, one level, minus the python shims — the
#                            `bin`/`hooks` half of `.github/workflows/ci.yml`'s shellcheck
#                            expression, which that lib owns rather than this file copying.
#   `_operator_run_checks`   `tests/*-check.sh` — the operator-run checks that live in the
#                            harness directory without being harness. ⛔ The members are NOT
#                            named here; the denominator below PRINTS them on every run, which
#                            is the copy that cannot be wrong.
#
# ⛔ WHY THE SECOND HALF EXISTS (card#10311). This gate ran GREEN over a live instance of its
# own class. PR #387 shipped `tests/framework-mirror-check.sh` with `_fw_cat "$DIR/$n" >
# "$tmp/mirror"` under `set -euo pipefail`: an unreadable mirror file killed the script at rc 1,
# which is the code that file's own header documents as STALE or DIVERGED — and `VERSIONING.md`
# release step 12 tells the operator to answer a non-zero rc by relaying a re-sync request to
# ANOTHER REPO'S OWNER. So an unreadable file produced a re-sync request for a file nobody ever
# read. That is shipped behaviour, and the gate built for exactly this class could not see it.
#
# ⛔ WHY THE HALF IS A FILENAME GLOB AND NOT "WHAT A RUNBOOK INVOKES", which is what this gate's
# first cut used and got wrong. That predicate parses markdown, and its miss is SILENT. This
# tree holds TWO operator-run checks; `docs/HOOKS.md` invokes the second
# (`install-board-hooks-capability-windows-check.sh`, which a Windows seat runs and sends the
# whole output of) in an inline-code span spelled `<toolkit>/tests/…`, which no fence-and-
# command-word predicate reaches — so the first cut covered one of two while asserting there
# was one. A predicate whose failure mode is a silent under-count must not BE the population of
# the gate whose entire subject is silent under-counting. The filename kind is a property of
# the file, needs no parser, and cannot be shrunk by a doc's formatting. The lib states how the
# four kinds partition `tests/*.sh`; the two guards that keep that partition honest are below.
#
# ⛔ THE HARNESS IS STILL OUT, AND THAT EXCLUSION IS MEASURED RATHER THAN ASSERTED. The harness
# discards a read's status ON PURPOSE (a probe's rc IS the thing under test, and `expect_out`
# captures with `|| true` by design), so unioning `_selftest_shell_files` in would hand this
# file a pile of dispositions that mostly read "this is a test" — plus this file's OWN planted
# collapse fixtures matching themselves. Exemptions nobody reads are not coverage; they train
# the reader to stamp the next one unread, which is this gate's entire failure mode.
#
# ⛔ THAT PRICE IS NOT WRITTEN DOWN HERE, IT IS RE-MEASURED. A number in this comment would be a
# stale claim with a maintenance schedule (canon #16), and the figure the card was ruled on has
# already moved. So the denominator below prints `harness members this exclusion declines` on
# EVERY run, through the identical scanner. Nothing asserts on it — it is the cost of the
# ruling, kept live so the ruling can be re-argued against a current figure.
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
#       `|| continue`, `|| { … }` — is NOT a member: those sites kept the third outcome AT THE SITE
#       (whether the rc they hand one call up still does is `rc1-merge`'s question, below). That
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
# ─────────────────────── THE FUNCTION-BOUNDARY LEGS (card#10361) ───────────────────────
#
# (a)+(b) read ONE site. The shape that kept re-minting is split across TWO, and neither half is
# wrong alone: a function answers ONE value or rc for "read, and absent" and "nothing was read",
# and its caller acts on that answer. card#6594, #6630, #6631, #10230 and #10241 were all that
# seam, every one found by hand after shipping — and the last two shipped PAST this gate, green,
# because its (a) exclusion says a `|| return` tail "kept the third outcome", which is true at
# the site and false one call up. Four more spellings are therefore derived, over the SAME
# population, by one scan that sees every file at once (a function is defined in one file and
# tested in another):
#
#   READERS and COLLAPSERS are derived first, never listed. A function READS when a line of its
#   body runs, in COMMAND position, a transport or decoder — `kb_api`, `kb_api_status`, `curl`,
#   `gh`, `jq`, `git ls-remote`, `git fetch` — or a function that reads (to a fixed point). It
#   COLLAPSES when its own OUTPUT statement is such a read with the status thrown away
#   (`jq … 2>/dev/null || true`) — `kb_parse_resp` is the lib's by-design one — or passes a
#   collapser's output through. Both sets are printed in the denominator.
#
#   envelope-default  A jq filter defaulting the response ENVELOPE — `.data // …`, `.data[]?`,
#                     or a path through it defaulted to a VALUE (`.data.comments // []`; a
#                     `// empty` there makes nothing, which an emptiness arm can still refuse).
#                     On jq 1.7 `{"message":"session expired"}` through `.data // []` is
#                     byte-identical to `{"data":[]}` (card#10241, measured), so the decoder
#                     itself scores an unreadable body as a measured empty. The closed form is
#                     a CLASSIFIER — `.data` present AND an array — never a default.
#                     Member `<file>:<fn>():envelope`. [#6594, #6630, #10241]
#   fn-collapse       `V="$(G …)"` where G is a COLLAPSER and V is tested for emptiness (leg b):
#                     the discard is inside G, so no `2>/dev/null` is in sight at the capture.
#                     Joins leg (a)'s `<file>:<var>` key space — one variable, one verdict.
#   rc1-merge         Inside a function, a read whose failure tail answers a LITERAL rc 1
#                     (`|| return 1`, `|| exit 1`, or either anywhere in an `|| { … }` block) —
#                     the rc a predicate uses for "absent" — and that function's rc is USED as
#                     an answer somewhere: tested as a condition, or captured with `$?`, directly
#                     or through a wrapper that passes it straight through. A function whose rc
#                     only propagates a failure outward is not a member; one whose rc is read as
#                     a verdict is. Member `<file>:<fn>()`. [#6631, #10230, #10241]
#   truthiness        A READING function called as a condition — `if`/`elif`/`while`/`until`,
#                     `!`, `&&`, or `||` with a tail that is neither a refusal (`return`/`exit`/
#                     `die`, which is rc1-merge's or the process's) nor an rc capture (`x=$?`).
#                     A three-outcome function tested for truth IS the collapse, however well
#                     the function keeps its outcomes apart. Member `<file>:if <fn>`. [#10241]
#
#   The CORRECT shape these must stay green on is card#10241's fix, planted verbatim below: the
#   predicate classifies the envelope and returns 0 / 1 / a NAMED third rc, the wrapper keeps
#   each rc (`|| arc=$?`) and returns a named constant, and the caller branches on the rc.
#   A WRITE (a literal PATCH/POST/PUT/DELETE in the call) is excluded from rc1-merge and
#   truthiness: a write's outcome is `tests/readback-before-success-census.sh`'s class.
#
# ⛔ WHAT IT STRUCTURALLY CANNOT SEE — stated so it is not over-cited:
#   * A collapse that never touches a VARIABLE: `if [ -n "$(cmd 2>/dev/null)" ]`, or a bare
#     `cmd 2>/dev/null | wc -l` scored as a count. There is nothing to key a disposition on.
#   * A seam carried across a PROCESS boundary: a tool whose `exit 1` means both "not found" and
#     "could not read", read by another tool's `if tool …`. `exit` at a script's top level is
#     that script's published contract, and a caller in another repo is outside every scan here.
#   * The function-boundary legs resolve a call by NAME across the whole population, so a
#     same-named function in another bin counts (over-collects — errs RED); a function called
#     through a variable (`"$fn" …`) or `eval` is invisible; a value tested for VALIDITY rather
#     than emptiness (`kb_is_uint "$v"`, card#10230's 2xx arm) is not leg (b); an rc merged under
#     a literal other than 1 is not rc1-merge, and a USE of a function's rc is recognised only as
#     a condition or as an `x=$?` taken on the call's own line, the next line, or in its `if`'s
#     own `else` — an rc read any later is not seen, which UNDER-collects, the silent direction;
#     and a jq default on an envelope key other than `.data` (a `gh api` body's own shape) is not
#     envelope-default.
#   * card#6771 — the sixth recorded instance — is not a shell shape in THIS tree: `kbcard list`
#     projected no `description`, and a peer's `grep` over that projection answered 0 for a card
#     the board held. No function here collapsed a read; the consumer read a surface that never
#     carried the field. What covers it is `kbcard search` printing the field it matched on and
#     the README's statement that `list`'s projection is the filterable surface.
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
#   DISTINCT     — (function-boundary members) the rc or value the scan flagged carries ONE
#                  outcome only: "absent" is answered on a different channel (rc 0 with `[]`, a
#                  `null`, rc 3 UNVERIFIED), so nothing measured-absent can arrive looking like it.
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
  "bin/_kb-board-lib.sh:fetch_board_cards()|DISTINCT — rc 1 is only 'page 1 was not read' (no response, a non-2xx, or a 2xx with no card array); an empty board answers rc 0 with [] (card#6594), so no read-and-absent outcome shares it. Where its rc is used it is branched on (the DL minter refuses on every non-zero one, card#6631); the one discard is the archive census above, where a partial read is the conservative direction."
  "bin/_kb-board-lib.sh:if kb_owner_resolve|SAME OUTCOME — the only reads are of the LOCAL coord config, and every false answer (unreadable, not an object, no project, no seat, not on the roster) stamps nothing and prints KB_OWNER_WHY, naming which; nothing is guessed and no absence is claimed."
  "bin/_kb-board-lib.sh:new|DISPOSED — \$tags is kb_card_tags' output, refused above when empty (the unreadable arm names HTTP and sends nothing), so kb_owner_strip reads a list already accepted: empty here means only 'no owner tag to remove', and the branch sends no write."
  "bin/adopt-to-dl:cur_board|SAME OUTCOME — empty REFUSES the adoption, naming that nothing was read and the board is UNCONFIRMED; a readable card always carries a board_id, so there is no absent case to lose."
  "bin/card-completeness:if load_open_prs|DISTINCT — rc 1 is only UNMEASURED (the cause in \$UNMEASURED); a repo with no open PRs is rc 0 with no rows. The false branch reports every card UNMEASURED at exit 6 and never 'complete'."
  "bin/card-completeness:if load_unreleased_prs|DISTINCT — rc 1 is only UNMEASURED (a failed page, a missing ahead_by, a truncated or over-cap window); an empty window is rc 0. The false branch reports every card UNMEASURED at exit 6."
  "bin/card-completeness:load_open_prs()|DISTINCT — its one rc-1 tail is fetch_pages failing, which sets \$UNMEASURED; 'no open PRs' is rc 0 with no rows, never rc 1."
  "bin/card-completeness:load_unreleased_prs()|DISTINCT — every rc-1 tail sets \$UNMEASURED; an empty unreleased window is rc 0, never rc 1."
  "bin/dl-a1-register-field:(top)():envelope|SAME OUTCOME, WITH A WRONG MESSAGE — '.data[]?' scores an unreadable 2xx field index as 'no dl_number definition', and both reach the FATAL exit 1, so no board is certified. Residual, not fixed here (an error-message change is ask-first): that FATAL line asserts 'the board's custom-field index carries NO dl_number definition' about a body it could not read."
  "bin/kbcard:_kbc_field_create_call()|DISTINCT — its rc 1 is the re-read's 'does not define it' (a HARD FAILURE, the fail-closed direction for a create's read-back): \$after is _kbc_fetch_fields' output, which refuses a body with no .data, and a re-read that cannot be made returns _kbc_unverified's rc 3 on its own branch. Residual: a .data that is an object, not an array, would read as 'does not define it'. The POST's own failure is a write, outside this leg."
  "bin/kbcard:base|SAME OUTCOME — empty REFUSES the tag replace ('a list built from nothing'); kb_card_tags answers [] for a card with no tags, so empty is only the unreadable case."
  "bin/kbcard:card|SAME OUTCOME — empty or null is the 'noprimitive' verdict, which the archive gate fails LOUD on and never archives."
  "bin/kbcard:cid|DISTINCT — empty takes _kbc_unverified: rc 3 UNVERIFIED WRITE, never a success and never 'not posted'."
  "bin/kbcard:cmd_comments():envelope|OPEN, RECORDED AT THE SITE — '.data.comments // []' answers [] for a 2xx JSON body with no .data (an API or gateway error envelope), so 'kbcard comments' prints no comments at rc 0 for a card it never read. Left open there as card#6426 §b: refusing it moves a READ verb from rc 0 to rc 1, an acceptance change not granted. The 'false' half of the same default is docs/CONSOLIDATION-PLAN.md's 'shape test downstream of //' class."
  "bin/kbcard:comments|SAME OUTCOME for every body jq cannot parse or whose comments are not a list of objects — empty REFUSES, saying nothing was read and that this is NOT an empty list, while a real empty list decodes to [], which is non-empty. The JSON-envelope residual is the cmd_comments():envelope line above."
  "bin/kbcard:cur|SAME OUTCOME — empty REFUSES the --card-start move at rc 2 before any write, saying the stage could not be read."
  "bin/kbcard:data|SAME OUTCOME — at every capture empty means no card object was read: show and the link witness REFUSE naming it; the patch preflights REFUSE before the write, except under --unassign and --steal, which proceed LOUDLY and by design (the flag already overrides the holder the read would have named)."
  "bin/kbcard:echo_out|DISTINCT — empty takes _kbc_unverified: rc 3 UNVERIFIED, never a confirmed move."
  "bin/kbcard:fid|DISTINCT — empty takes _kbc_unverified: rc 3 UNVERIFIED, never a created field."
  "bin/kbcard:fields|SAME OUTCOME — empty REFUSES, saying nothing was read and that this is NOT a board with no custom fields; a board with none decodes to [], which is non-empty."
  "bin/kbcard:got|SAME OUTCOME — empty (a body jq cannot parse) joins the restamp's UNREAD list; a card with no such key decodes to null and joins MISMATCH; neither is counted done. Residual: a 2xx JSON error envelope with no .data also decodes to null and is reported as a MISMATCH rather than UNREAD — the wrong name on a not-done card, the direction that claims nothing."
  "bin/kbcard:id|DISPOSED — \$rows is already refused when empty, and a well-formed [] reaches 'no task found' correctly. Residual recorded at the site: a .data that is an object reads as the not-found arm (refusing it would change what this read verb accepts). The other emptiness test of an 'id' in this file is a different function's local."
  "bin/kbcard:link|DISTINCT — empty takes _kbc_unverified: rc 3 UNVERIFIED, never a created link."
  "bin/kbcard:meta|DISTINCT — empty takes _kbc_unverified: rc 3 UNVERIFIED placement, never a confirmed reorder."
  "bin/kbcard:out|SAME OUTCOME — the link witness REFUSES an unreadable linked_tasks list as UNMEASURED; the write echo takes _kbc_unverified (rc 3). Neither answers 'no links' or 'written'."
  "bin/kbcard:ranked|DISTINCT — empty takes _kbc_unverified: rc 3 UNVERIFIED, never a confirmed reorder."
  "bin/kbcard:ref_ids|SAME OUTCOME — empty sends NO acknowledgement, so an unread set and a set the server did not name both leave the refusal standing; only the advisory wording branches on it, and nothing is written either way."
  "bin/kbcard:resolve_task():envelope|SAME OUTCOME — '.data // empty' routes a missing, null or false .data to the REFUSAL that says nothing was read and that it is NOT 'no such card'; a well-formed empty result [] is truthy in jq and survives to the not-found arm."
  "bin/kbcard:row|DISTINCT — empty takes _kbc_unverified (rc 3) at the set-options read-back; at the retype it takes the arm that refuses the ECHO of a conversion the 2xx says landed and does not restamp. Neither reports an option set or a type it did not read."
  "bin/kbcard:rows|SAME OUTCOME — empty REFUSES the external-id lookup, saying nothing was read and that it is NOT 'no such card'. The other emptiness test of a 'rows' in this file is a different function's local (the KB_STAGE_* table)."
  "bin/kbcard:to_t|DISTINCT — empty takes the same refuse-the-echo arm as \$row at the retype, with no restamp; the converted type is reported only when it was read."
  "bin/next-dl:dl_sequence_call()|SAME OUTCOME — rc 1 is only 'nothing was spent': the config did not resolve (no request), the route answered 404 (it does not exist here), or — on the NON-consuming peek alone — the request did not complete or its 2xx could not be read. Every rc 1 takes the announced offline fallback that --require-counter refuses; where a number MAY have been spent (the claim, transport or undecodable) it exits 3 and refuses to mint (card#10230)."
  "bin/promote-released-cards:back|SAME OUTCOME — owner_card_tags answers [] for a card with no tags, so empty is only 'no tag list could be read', and that branch says the clear is UNVERIFIED rather than done."
  "bin/promote-released-cards:kept|DISPOSED — \$tags already passed owner_card_tags' refusal above, so owner_strip reads an accepted list: empty means only 'no owner tag to remove', and no write is sent."
  "bin/promote-released-cards:left|DISPOSED — \$back already passed owner_card_tags' UNVERIFIED branch above, so owner_list reads an accepted array: empty means the card really carries no owner tag, which is the read-back the success line quotes."
  "bin/promote-released-cards:tags|SAME OUTCOME — owner_card_tags answers [] for a card with no tags, so empty is only the unreadable case, and that branch sends NO tag list and says so."
  "bin/release-artifacts-check:_json_parses()|NO READ — a parse of a config blob already in memory; its two answers are 'parses' and 'does not', and the READ (git show) failed on its own branch before the blob got here."
  "bin/release-artifacts-check:if _json_parses|NO READ — the same in-memory parse; the false branch dies or scores the config 'unreadable'/'not valid JSON' by name, which is what an unparseable blob is."
)

# ── the derivation ──────────────────────────────────────────────────────────────────────────
#
# awk, not grep: joining line continuations and truncating at a top-level `;` are both stateful
# scans a line-oriented match cannot do, and leg (b) needs a second pass over the same file.
_roc_awk_lib='
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
# tested(v, lines, nl) — is v tested for emptiness on any non-comment line of lines[1..nl]?
function tested(v, lines, nl,   j, L, reA, reB) {
    reA = "-[zn][[:space:]]+\"?\\$\\{?" v "([^A-Za-z0-9_]|$)"
    reB = "\"\\$\\{?" v "\\}?\"[[:space:]]*(=|!=|==)[[:space:]]*\"\""
    for (j = 1; j <= nl; j++) {
        L = lines[j]
        if (L ~ /^[[:space:]]*#/) continue
        if (L ~ reA || L ~ reB) return 1
    }
    return 0
}
BEGIN { SQ = sprintf("%c", 39) }
'
_roc_awk="$_roc_awk_lib"'
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
        if (!(v in memo)) memo[v] = tested(v, lines, NR)
        if (memo[v]) printf "%s\t%s\t%s\t%s\n", REL, v, cl[i], trim(cw[i])
    }
}'

# The function-boundary scan (card#10361). ONE awk over EVERY population file at once, run from
# the root so FILENAME is the relpath: a function is defined in one file and called in another
# (every lib-sourcing bin), so a per-file pass cannot see the seam. ONLY, when set, is a
# newline-separated relpath list that limits which files REPORT — definitions are still read
# from every file given, which is how the declined-harness price below is measured through
# this same code. MODE=sets prints the derived READ / COLLAPSE sets instead of records.
_roc_fn_awk="$_roc_awk_lib"'
function isdef(L) { return L ~ /^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*[{(]/ }
function defname(L,   s) { s = L; sub(/^[[:space:]]*(function[[:space:]]+)?/, "", s); sub(/[[:space:]]*\(\).*/, "", s); return s }
function iscomment(L) { return L ~ /^[[:space:]]*#/ }
function isassign(L) { return L ~ /^[[:space:]]*((local|declare|export|readonly)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=/ }
function isprim(t) { return t == "kb_api" || t == "kb_api_status" || t == "curl" || t == "gh" || t == "jq" || t == "git-ls-remote" || t == "git-fetch" }
# cmds(s) — " w1 w2 … ", the words of s in COMMAND position: line start, or after ; & | ( { !
# then do else if elif while until time — and never a `$var`, `${var` or an `x=` assignment.
# A git word keeps its verb (`git-ls-remote`) so a LOCAL git read is not taken for a remote one.
function cmds(s,   out, t, pre, acc, pw) {
    out = " "; acc = ""; pw = ""
    while (match(s, /[A-Za-z_][A-Za-z0-9_-]*/)) {
        t = substr(s, RSTART, RLENGTH); pre = acc substr(s, 1, RSTART - 1); acc = pre t; s = substr(s, RSTART + RLENGTH)
        if (pw == "git" && (t == "ls-remote" || t == "fetch")) out = out "git-" t " "
        else if (pre ~ /(^|[;&|({!]|(^|[[:space:]])(then|do|else|if|elif|while|until|time))[[:space:]]*$/ && pre !~ /[$][{]?$/ && s !~ /^=/) out = out t " "
        pw = t
    }
    return out
}
# nosubst(s) — s with every $( … ) removed: what is left is the commands of THIS statement.
function nosubst(s,   i, c, n, d, q, out) {
    n = length(s); d = 0; q = ""; out = ""
    for (i = 1; i <= n; i++) { c = substr(s, i, 1)
        if (d == 0 && q == "" && c == SQ) { q = c; out = out c; continue }
        if (q != "") { out = out c; if (c == q) q = ""; continue }
        if (c == "$" && substr(s, i + 1, 1) == "(") { d++; i++; continue }
        if (d > 0 && c == "(") { d++; continue }
        if (d > 0 && c == ")") { d--; continue }
        if (d == 0) out = out c
    }
    return out
}
# orpos(s) — index of the first `||` outside quotes and outside every $( ), or 0.
function orpos(s,   i, c, n, q, d) {
    n = length(s); q = ""; d = 0
    for (i = 1; i < n; i++) { c = substr(s, i, 1)
        if (q != "") { if (c == q) q = ""; continue }
        if (d == 0 && (c == "\"" || c == SQ)) { q = c; continue }
        if (c == "$" && substr(s, i + 1, 1) == "(") { d++; i++; continue }
        if (d > 0 && c == "(") { d++; continue }
        if (d > 0 && c == ")") { d--; continue }
        if (d == 0 && c == "|" && substr(s, i + 1, 1) == "|") return i
    }
    return 0
}
function rec(f, k, l, w) { printf "%s\t%s\t%d\t%s\n", f, k, l, w }
BEGIN { nl = split(ONLY, o, "\n"); for (k = 1; k <= nl; k++) if (o[k] != "") only[o[k]] = 1 }
{ F = FILENAME; n[F]++; line[F, n[F]] = $0; if (!(F in seen)) { seen[F] = 1; files[++nf] = F } }
END {
    # ── pass 1: which functions READ, and which COLLAPSE a read into their own output ──
    for (fi = 1; fi <= nf; fi++) { F = files[fi]; depth = 0; pend = ""
        for (i = 1; i <= n[F]; i++) { L = line[F, i]; def = isdef(L)
            if (def) { nm = defname(L); ind = L; sub(/[^[:space:]].*/, "", ind); defd[nm] = 1
                stack[++depth] = nm; sind[depth] = ind; B = substr(L, index(L, "()") + 2)
                one = (B ~ /[})][[:space:]]*(#.*)?$/ && B !~ /[{(][[:space:]]*(#.*)?$/)
            } else { B = iscomment(L) ? "" : L; one = 0 }
            fnat[F, i] = (depth > 0) ? stack[depth] : ""
            # A continued line is judged as the WHOLE statement: a pass-through spelled over two
            # lines with its `|| return 1` on the second is not a pass-through.
            if (B ~ /\\[[:space:]]*$/) { sub(/\\[[:space:]]*$/, "", B); pend = pend B " "; B = "" }
            else if (pend != "" && B != "") { B = pend B; pend = "" }
            if (depth > 0 && B != "") { c = cmds(B); m = split(c, w, " ")
                for (k = 1; k <= m; k++) { t = w[k]; if (t == "") continue
                    if (isprim(t)) { for (d = 1; d <= depth; d++) direct[stack[d]] = 1 }
                    else for (d = 1; d <= depth; d++) if (t != stack[d]) edge[stack[d], t] = 1 }
                if (!isassign(B)) {
                    if (B ~ /\|\|[[:space:]]*(true|:|printf|echo)([^A-Za-z0-9_]|$)/ && c ~ / (kb_api|kb_api_status|curl|gh|jq|git-ls-remote|git-fetch) /) coll[stack[depth]] = 1
                    if (B !~ /\|\||&&/) for (k = 1; k <= m; k++) if (w[k] != "") passes[stack[depth], w[k]] = 1
                }
            }
            if (one) depth--
            else if (!def && depth > 0 && L ~ ("^" sind[depth] "[})][[:space:]]*(#.*)?$")) depth--
        }
    }
    for (f in direct) reader[f] = 1
    do { ch = 0; for (k in edge) { split(k, p, SUBSEP); if (!(p[1] in reader) && (p[2] in reader)) { reader[p[1]] = 1; ch = 1 } } } while (ch)
    do { ch = 0; for (k in passes) { split(k, p, SUBSEP); if (!(p[1] in coll) && (p[2] in coll) && (p[1] in defd)) { coll[p[1]] = 1; ch = 1 } } } while (ch)
    if (MODE == "sets") { for (f in defd) print "D\t" f; for (f in reader) if (f in defd) print "R\t" f; for (f in coll) print "C\t" f; exit }
    # ── pass 2: the four seam spellings ──
    for (fi = 1; fi <= nf; fi++) { F = files[fi]; rep = (ONLY == "" || (F in only))
        delete cur; for (j = 1; j <= n[F]; j++) cur[j] = line[F, j]
        cont = ""
        for (i = 1; i <= n[F]; i++) { R = line[F, i]
            if (cont != "") J = cont " " R; else { J = R; st = i }
            if (J ~ /\\[[:space:]]*$/) { sub(/\\[[:space:]]*$/, "", J); cont = J; continue }
            cont = ""
            if (iscomment(J)) continue
            fn = fnat[F, st]
            write = (J ~ /(^|[^A-Za-z])(PATCH|POST|PUT|DELETE)([^A-Za-z]|$)/)
            if (rep && (J ~ /\.data[[:space:]]*\/\/|\.data\[\]\?/ || J ~ /\.data(\.[A-Za-z_][A-Za-z0-9_]*|\[[^]]*\])+\??[[:space:]]*\/\/[[:space:]]*(\[|\{|"|[0-9]|false|true|null|\$)/)) rec(F, (fn == "" ? "(top)" : fn) "():envelope", st, "envelope-default")
            # a capture whose rc is KEPT marks its function as ANSWERING (for rc1-merge below)
            if (match(J, /(^|[;&|[:space:]])(if[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*="?\$\([[:space:]]*[A-Za-z_][A-Za-z0-9_]*/)) {
                g = substr(J, RSTART, RLENGTH); sub(/^.*\$\([[:space:]]*/, "", g)
                if (J ~ /(else|;|\|\|)[[:space:]]*(\{[[:space:]]*)?[A-Za-z_][A-Za-z0-9_]*=\$\?/ || line[F, i + 1] ~ /^[[:space:]]*(else[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=\$\?/) used[g] = 1
                # `if V="$(F)"; then` … `else` / `rc=$?` on later lines: follow the if to its own
                # else or fi, at the indentation of that if.
                else if (J ~ /^[[:space:]]*if[[:space:]]/) { ind = J; sub(/[^[:space:]].*/, "", ind)
                    for (e = i + 1; e <= n[F]; e++) { X = line[F, e]
                        if (X ~ ("^" ind "fi([^A-Za-z0-9_]|$)")) break
                        if (X ~ ("^" ind "else([^A-Za-z0-9_]|$)")) {
                            if (X ~ /=\$\?/ || line[F, e + 1] ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\?/) used[g] = 1
                            break } } }
            }
            # a bare call whose status is taken on the NEXT line (`F …` then `rc=$?`)
            if (J !~ /\|\||&&|\|/ && line[F, i + 1] ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\?/) {
                m = split(cmds(nosubst(J)), w, " "); for (k = 1; k <= m; k++) if (w[k] != "") { used[w[k]] = 1; break } }
            if (rep && match(J, /^[[:space:]]*((local|declare|export|readonly)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*="?\$\([[:space:]]*[A-Za-z_][A-Za-z0-9_]*/)) {
                h = substr(J, RSTART, RLENGTH); v = h; sub(/=.*/, "", v); sub(/^.*[[:space:]]/, "", v)
                g = h; sub(/^.*\$\([[:space:]]*/, "", g)
                if ((g in coll) && tested(v, cur, n[F])) rec(F, v, st, "fn-collapse(" g "),")
            }
            op = orpos(J)
            if (rep && fn != "" && op > 0 && !write) { pre = substr(J, 1, op - 1); tl = substr(J, op + 2); hit = 0
                m = split(cmds(pre), w, " ")
                for (k = 1; k <= m; k++) if (w[k] != "" && w[k] != fn && (isprim(w[k]) || (w[k] in reader))) hit = 1
                if (hit) { blk = tl
                    if (tl ~ /^[[:space:]]*\{/) { bd = gsub(/\{/, "{", tl) - gsub(/\}/, "}", tl); e = i
                        while (bd > 0 && e < n[F]) { e++; X = line[F, e]; if (iscomment(X)) continue; blk = blk "\n" X; bd += gsub(/\{/, "{", X) - gsub(/\}/, "}", X) } }
                    else sub(/[;&|].*/, "", blk)
                    if (blk ~ /(^|[^A-Za-z0-9_])(return|exit)[[:space:]]+1([^0-9]|$)/ || blk ~ /^[[:space:]]*false([^A-Za-z0-9_]|$)/) { nm2++; m2f[nm2] = F; m2n[nm2] = fn; m2l[nm2] = st }
                }
            }
            S = nosubst(J); m = split(cmds(S), w, " ")
            for (k = 1; k <= m; k++) { t = w[k]; if (t == "" || !(t in reader) || !(t in defd)) continue
                if (!match(S, "(^|[^A-Za-z0-9_])" t "([^A-Za-z0-9_-]|$)")) continue
                before = substr(S, 1, RSTART); after = substr(S, RSTART + RLENGTH)
                seg = after; sub(/(;|&&|\|\||\||[[:space:]]then|[[:space:]]do)([^\n]|\n)*$/, "", seg)
                if (seg ~ /(^|[^A-Za-z])(PATCH|POST|PUT|DELETE)([^A-Za-z]|$)/) continue
                rest = substr(after, length(seg) + 1)
                cond = (before ~ /(^|[^A-Za-z0-9_])(if|elif|while|until)[[:space:]]+(![[:space:]]+)?[^;]*$/ && before !~ /(^|[^A-Za-z0-9_])(then|do|else)[[:space:]][^;]*$/) || before ~ /![[:space:]]*\{?[[:space:]]*$/
                lst = (rest ~ /^[[:space:]]*(&&|\|\|)/) || before ~ /(&&|\|\|)[[:space:]]*$/
                if (rest ~ /^[[:space:]]*\|\|[[:space:]]*(\{[[:space:]]*)?[A-Za-z_][A-Za-z0-9_]*=\$\?/) { used[t] = 1; lst = 0 }
                if (rest ~ /^[[:space:]]*;[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\?/) used[t] = 1
                if (rest ~ /^[[:space:]]*\|\|[[:space:]]*(return|exit|die)([^A-Za-z0-9_]|$)/ && !cond) lst = 0
                if (cond || lst) { used[t] = 1; if (rep) rec(F, "if " t, st, "truthiness") }
            }
        }
    }
    do { ch = 0; for (k in passes) { split(k, p, SUBSEP); if ((p[1] in used) && !(p[2] in used)) { used[p[2]] = 1; ch = 1 } } } while (ch)
    for (k = 1; k <= nm2; k++) if (m2n[k] in used) rec(m2f[k], m2n[k] "()", m2l[k], "rc1-merge")
}'

# _roc_population <root> — THE population, composed from `tests/_shipped-shell-lib.sh`: the
# shipped shell, plus the operator-run checks that live under `tests/`. Both halves are globs
# over the tree, re-derived on every call; neither reads a doc and neither is a list here.
_roc_population() {
    { _shipped_shell_files "$1"; _operator_run_checks "$1"; } | awk 'NF' | LC_ALL=C sort -u
}

# _roc_fn_records <root> <only> <relpath>… — the function-boundary records over the given files
# (read from <root>, so FILENAME is the relpath). <only>, when non-empty, is a newline-separated
# relpath list that alone REPORTS; every file given still contributes its definitions. The rc is
# awk's own: a scanner that failed to run must not read as a tree with no seam in it.
_roc_fn_records() {
    local root="$1" only="$2"; shift 2
    [[ $# -gt 0 ]] || return 0
    ( cd "$root" && awk -v ONLY="$only" "$_roc_fn_awk" "$@" )
}

# _roc_fn_sets <root> — `D|R|C<TAB>name`: every function DEFINED in the population, the ones that
# READ, and the ones that COLLAPSE a read into their own output.
_roc_fn_sets() {
    local -a pop; mapfile -t pop < <(_roc_population "$1")
    ( cd "$1" && awk -v MODE=sets "$_roc_fn_awk" "${pop[@]}" )
}

# _roc_records <root> — one TAB record per candidate: relpath, key, line, why. Leg (a)+(b) per
# file, then the function-boundary legs over the whole population in ONE pass.
_roc_records() {
    local -a pop; mapfile -t pop < <(_roc_population "$1")
    _roc_capture_records "$1"
    _roc_fn_records "$1" "" "${pop[@]}"
}

# _roc_capture_records <root> — leg (a)+(b) ALONE, per file: the gate as it stood before the
# function-boundary legs. Kept callable so the reach those legs add is MEASURED below, on every
# run, rather than asserted in a comment.
_roc_capture_records() {
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
    local -a pop given=(); mapfile -t pop < <(_roc_population "$root")
    for rel in "$@"; do
        [[ -n "$rel" ]] || continue
        given+=("$rel")
        awk -v REL="$rel" "$_roc_awk" "$root/$rel"
    done
    # The function-boundary legs over the same files, with the shipped population's
    # DEFINITIONS in view (a harness file calls the lib's functions) but reporting only these.
    [[ ${#given[@]} -gt 0 ]] || return 0
    _roc_fn_records "$root" "$(printf '%s\n' "${given[@]}")" "${pop[@]}" "${given[@]}"
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

# ── the POPULATION control: two identical collapses under tests/, one in scope, one not ─────
#
# The widening this file carries (card#10311) is a claim about WHICH `tests/` files are in
# scope, and a population claim cannot be proven by the tree it was drawn around — on the real
# tree NEITHER operator-run check contributes a candidate today, so a green run says nothing
# about whether the widening reaches them. These two files carry the SAME planted collapse and
# differ in exactly one thing: the KIND their filename declares.
cat > "$FIX/tests/planted-mirror-check.sh" <<'EOF'
#!/usr/bin/env bash
MIRROR="$(cat "$DIR/$n" 2>/dev/null || true)"
[ -n "$MIRROR" ] || echo "STALE or DIVERGED"
EOF
cat > "$FIX/tests/planted-harness-selftest.sh" <<'EOF'
#!/usr/bin/env bash
HARNESS="$(cat "$DIR/$n" 2>/dev/null || true)"
[ -n "$HARNESS" ] || echo "STALE or DIVERGED"
EOF
# A fixture runbook, for the GUARD rather than for the population. Four shapes it must tell
# apart, all naming a `tests/…sh`: an invocation in a PLAIN fence; one in a BLOCKQUOTED fence
# (a real code block a reader pastes from — this tree uses that shape in two operator recipes,
# and both consumers of `_md_fenced_lines` were blind to it until card#10311 round 2); a fenced
# line where the path is an ARGUMENT, not the command word; and a prose/link mention.
{ printf 'Prose naming `tests/planted-harness-selftest.sh`, and a [link](tests/planted-harness-selftest.sh).\n'
  printf '\n```bash\n'
  printf 'cd "$TK" && bash -x <toolkit>/tests/planted-mirror-check.sh --ref origin/dev\n'
  printf 'cat tests/planted-harness-selftest.sh   # named as an ARGUMENT, not run\n'
  printf '```\n'
  printf '\n> ```bash\n'
  printf '> env FOO=1 tests/planted-mirror-check.sh|tee out\n'
  printf '> ```\n'
  printf '\nMore prose about tests/planted-harness-selftest.sh, outside every fence.\n'; } > "$FIX/RUNBOOK.md"
( cd "$FIX" && git add bin tests RUNBOOK.md ) >/dev/null 2>&1

echo "== the population is the FILENAME KIND, and it discriminates =="
eq "a tests/ file named *-check.sh is in the population; an identically-shaped selftest is not" \
   "$(printf 'tests/planted-mirror-check.sh')" "$(_operator_run_checks "$FIX")"
eq "every tests/*.sh in the fixture declares one of the four kinds" "" "$(_tests_shell_unclassified "$FIX")"

echo "== the runbook GUARD reaches the spellings a runbook actually uses =="
# One equality carries the whole matrix: a `cd … &&` chain, an interpreter WITH FLAGS, a
# `<placeholder>/` path prefix, an `env VAR=` prefix, a BLOCKQUOTED fence, and a `|` with no
# space — all invocations of the same file, which must dedupe to one line; against an ARGUMENT
# position and two prose mentions of the other file, which must not appear at all.
eq "every invocation spelling resolves to the file RUN; an argument and a mention do not" \
   "tests/planted-mirror-check.sh" "$(_runbook_invoked_checks "$FIX")"
# A REAL directory that is simply not a git repo — not a missing path, which would be refused
# one step earlier by `cd` and would leave the `git ls-files` status untested.
mkdir -p "$TMP/no-index"
eq "an index that cannot be read is UNMEASURED (rc 3), never a runbook that invokes nothing" "3" \
   "$(_runbook_invoked_checks "$TMP/no-index" >/dev/null 2>&1; echo $?)"

echo "== the scanner finds a planted collapse (positive control) =="
eq "the canonical shape is derived as a member, in bin/ AND in an operator-run check" \
   "$(printf 'bin/planted-collapse:FOUND\ntests/planted-mirror-check.sh:MIRROR')" \
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
has_harness="$(has "planted-harness-selftest" "$(_roc_members "$FIX")")"
eq "an identical collapse in a tests/ SELFTEST is not a member (the harness stays out)" \
   "false" "$has_harness"

# ── the FUNCTION-BOUNDARY controls: the recorded instances, reconstructed (card#10361) ───────
#
# Each recorded instance of the seam is planted in its OWN tree, reduced from the pre-fix source
# at the commit named — the seam lines kept as they shipped, everything the seam does not touch
# cut, and a one-line stand-in only where the seam needs a callee the reduction dropped. Its own tree, because the legs resolve calls by NAME across the whole population: two
# fixtures both defining `fetch_board_cards` would each answer for the other. Each tree must
# derive EXACTLY the members named — no fewer (the leg is blind to a recorded instance), and no
# more (the leg is not discriminating). Every one of these trees derives NOTHING under the
# pre-card#10361 gate, which is the reach this change adds.
_seam() { local r="$TMP/seam-$1"; mkdir -p "$r/bin"; cat > "$r/bin/$2"; printf '%s' "$r"; }

# card#6594 — `da5d0d2^:bin/_kb-board-lib.sh`. The decoder defaulted the envelope, so an HTML
# 200 read as `[]` and `fetch_board_cards` answered an empty board at rc 0.
S6594="$(_seam 6594 _kb-board-lib.sh <<'EOF'
fetch_board_cards() {
    local api="$1" token="$2" board="$3" page=1 pages="" resp data n
    while :; do
        resp="$(curl -sS -H @- -H "Accept: application/json" \
                "$api/tasks/search.json?q=board_id=${board}&limit=200&page=${page}" <<<"$(kb_auth_header "$token")")" || {
            [[ "$page" -eq 1 ]] && return 1
            return 2
        }
        data="$(printf '%s' "$resp" | jq -c '.data // []' 2>/dev/null)"
        n="$(printf '%s' "$data" | jq 'length' 2>/dev/null)"
        pages+="$data"$'\n'
        [[ "${n:-0}" -lt 200 ]] && break
        page=$((page + 1))
    done
    printf '%s\n' "$pages" | jq -c -s 'add' 2>/dev/null
}
EOF
)"

# card#6630 — `88d9a4e^:bin/promote-released-cards`. The page-1 zero-cards die caught page 1;
# a later unreadable page decoded to `[]`, ended the scan as a short page, and the mover
# PROMOTED from the truncated list.
S6630="$(_seam 6630 promote-released-cards <<'EOF'
fetch_whole_board() {
  local page=1 resp data n cards='[]'
  while :; do
    resp="$(api "$API/tasks/search.json?q=board_id=$BOARD&limit=200&page=$page")" || die "board read failed"
    data="$(printf '%s' "$resp" | jq -c '.data // []')"
    n="$(printf '%s' "$data" | jq 'length')"
    if [ "$page" -eq 1 ] && [ "${n:-0}" -eq 0 ]; then
      die "board $BOARD returned 0 visible cards — Refusing."
    fi
    cards="$(printf '%s\n%s\n' "$cards" "$data" | jq -c -s 'add')"
    [ "${n:-0}" -lt 200 ] && break
    page=$((page + 1))
  done
  printf '%s' "$cards"
}
EOF
)"

# card#6631 — `200f190^:bin/next-dl`. The paginator KEPT its rc and board_dl_max branched on it,
# then answered "page 1 unreadable" with exit 1 — the same rc it answered "this board carries no
# DL floor" with — and the caller fail-softed on rc 1 and minted without the board's floor.
S6631="$(_seam 6631 next-dl <<'EOF'
fetch_board_cards() { curl -sS "$1/tasks/search.json" | jq -c '.data'; }
board_dl_max() (
    cfg="$(resolve_board_cfg)" || exit 1
    IFS=$'\t' read -r api tok board <<<"$cfg"
    cards="$(fetch_board_cards "$api" "$tok" "$board" "${NEXT_DL_PAGE_CAP:-50}")" || {
        rc=$?
        [[ "$rc" -eq 1 ]] && { echo "next-dl: board $board could not be read (no response, a non-2xx status, or a 2xx carrying no card array) — skipping board check" >&2; exit 1; }
        echo "next-dl: board $board did not return a complete card list (fetch rc=$rc) — refusing to mint from a partial scan (could re-mint a used DL)" >&2
        exit 2
    }
    printf '%s' "$cards" | jq -r '.[]?.payload.dl_number // empty' | max_int
)
if bmax="$(board_dl_max)"; then dlrc=0; else dlrc=$?; fi
[[ "$dlrc" -eq 2 ]] && exit 1
EOF
)"

# card#10230 — `ca9ac25^:bin/next-dl`. dl_sequence_call answered a transport failure and an
# undecodable 2xx with exit 1, the rc it answers a 404 (route not deployed) with, so a CONSUMING
# claim whose answer was never read fell back to the offline scan and minted a duplicate. The rc
# crosses TWO boundaries: board_claim passes it straight through to the caller that branches.
S10230="$(_seam 10230 next-dl <<'EOF'
dl_sequence_call() (
    method="$1"; path="$2"; field="$3"; label="$4"; risk="$5"
    unusable() { echo "next-dl: NO AUTHORITATIVE NUMBER — the $label $1." >&2; }
    resp="$(curl -sS -w $'\n%{http_code}' -X "$method" \
        -H @- -H "Accept: application/json" \
        "$api/boards/$board/$path" 2>/dev/null <<<"$(kb_auth_header "$(cat "$token_file")")")" || {
        unusable "could not be REACHED (curl transport failure — no HTTP status came back, so whether the route exists here is unknown)"
        exit 1
    }
    http="${resp##*$'\n'}"; body="${resp%$'\n'*}"
    case "$http" in
        2[0-9][0-9])
            val="$(kb_parse_resp "$body" -r "$field // empty")"
            kb_is_uint "$val" && [[ "$val" -ge 1 ]] || {
                unusable "answered HTTP $http but carried no usable number at $field (an older response shape, or a body that could not be read)"
                exit 1
            }
            printf '%s' "$val" ;;
        404)
            unusable "is NOT DEPLOYED on this board's kanban (HTTP 404) — this kanban predates the DL-sequence route"
            exit 1 ;;
        *)
            echo "next-dl: the $label is PRESENT but FAILED (HTTP $http) — NOT silently falling back to the offline scan, $risk." >&2
            exit 3 ;;
    esac
)
board_claim() {
    dl_sequence_call POST dl-sequence/claim.json .data.value \
        "atomic claim endpoint" \
        "which is not atomic and could re-mint on a shared board"
}
if claimed="$(board_claim)"; then crc=0; else crc=$?; fi
[[ $crc -eq 3 ]] && exit 1
EOF
)"

# card#10241 — `239c409^:bin/_kb-board-lib.sh` + `bin/dl-a1-register-field`. All three legs at
# once: the predicate defaulted the envelope, the wrapper folded a failed read into rc 1, and two
# callers whose PASS condition is a miss tested it for truth ("after clear … empty", "zero
# residue", exit 0, over a board nobody read).
S10241="$(_seam 10241 dl-a1-register-field <<'EOF'
kb_by_ref_hit() {
    printf '%s' "${1:-}" | jq -e --argjson id "${2:-0}" \
        '(if type=="object" then (.data // []) else . end) | any(.[]?; .id == $id)' >/dev/null 2>&1
}
by_ref_has() {
    local resp
    resp="$(kb_api GET "/boards/$BOARD/tasks/by-ref.json?system=dl&ref=$SENTINEL")" || return 1
    kb_by_ref_hit "$resp" "$1"
}
if by_ref_has "$TID"; then
    echo "  by-ref system=dl ref=$SENTINEL: FOUND (card $TID)"
fi
if by_ref_has "$TID"; then
    echo "dl-a1-register-field: FATAL: by-ref still resolves after clear" >&2; exit 1
fi
echo "  acceptance: by-ref ref=$SENTINEL empty after delete — zero residue"
EOF
)"

# THE CORRECT SHAPE — `239c409:bin/_kb-board-lib.sh` + `bin/dl-a1-register-field`, card#10241's
# fix, as shipped: the predicate CLASSIFIES the envelope and returns 0 / 1 / a NAMED third rc;
# the wrapper keeps each rc apart and answers a named constant; the caller branches on the rc.
# Every leg must be silent on it — this is what "the seam is closed" looks like to the scan.
SFIXED="$(_seam fixed dl-a1-register-field <<'EOF'
kb_jq_one() {
    local input="$1"; shift
    local one
    one="$(jq -s "${@:1:$#-1}" "if length == 1 then .[0] | (${*: -1}) else error(\"x\") end" <<<"$input" 2>/dev/null)" || return 1
    [[ -z "$one" ]] || printf '%s\n' "$one"
}
kb_by_ref_hit() {
    local verdict
    verdict="$(kb_jq_one "${1:-}" -r --argjson id "${2:-0}" '
        (if type == "object" then .data else . end) as $rows
        | if ($rows | type) != "array" then "unreadable"
          elif any($rows[]; .id == $id) then "hit"
          else "absent" end')"
    case "$verdict" in
        hit)    return 0 ;;
        absent) return 1 ;;
        *)      return "$KB_RC_BYREF_UNREADABLE" ;;
    esac
}
by_ref_state() {
    local resp arc=0 rc=0
    resp="$(kb_api GET "/boards/$BOARD/tasks/by-ref.json?system=dl&ref=$SENTINEL")" || arc=$?
    if [[ "$arc" != 0 ]]; then
        return "$A1_RC_UNMEASURED"
    fi
    kb_by_ref_hit "$resp" "$1" || rc=$?
    case "$rc" in
        0|1) return "$rc" ;;
        *)   return "$A1_RC_UNMEASURED" ;;
    esac
}
brs=0; by_ref_state "$TID" || brs=$?
case "$brs" in
    0) echo "FOUND" ;;
    1) echo "NOT FOUND" >&2 ;;
    *) echo "UNMEASURED" >&2 ;;
esac
EOF
)"

echo "== the function-boundary legs see every recorded instance of the seam =="
eq "card#6594: the paginator's envelope default" \
   "bin/_kb-board-lib.sh:fetch_board_cards():envelope" "$(_roc_members "$S6594")"
eq "card#6630: the mirror's later-page envelope default" \
   "bin/promote-released-cards:fetch_whole_board():envelope" "$(_roc_members "$S6630")"
eq "card#6631: an unreadable board answered with the no-floor rc, and branched on" \
   "bin/next-dl:board_dl_max()" "$(_roc_members "$S6631")"
eq "card#10230: a failed CONSUMING read answered with the not-deployed rc, through a wrapper" \
   "bin/next-dl:dl_sequence_call()" "$(_roc_members "$S10230")"
eq "card#10241: envelope default + rc-1 wrapper + a miss-is-pass caller testing it for truth" \
   "$(printf '%s\n' 'bin/dl-a1-register-field:by_ref_has()' 'bin/dl-a1-register-field:if by_ref_has' 'bin/dl-a1-register-field:kb_by_ref_hit():envelope')" \
   "$(_roc_members "$S10241")"
eq "the reason each was derived is the leg it names" \
   "$(printf '%s\n' envelope-default envelope-default rc1-merge rc1-merge rc1-merge truthiness envelope-default)" \
   "$(for r in "$S6594" "$S6630" "$S6631" "$S10230" "$S10241"; do _roc_records "$r" | awk -F'\t' '{ print $2 "\t" $4 }' | LC_ALL=C sort -u | cut -f2; done)"
eq "card#10241's FIX, as shipped, derives nothing (the correct shape stays green)" \
   "" "$(_roc_members "$SFIXED")"
eq "leg (a)+(b) ALONE derives none of the five — this is the reach the function-boundary legs add" \
   "" "$(for r in "$S6594" "$S6630" "$S6631" "$S10230" "$S10241"; do _roc_capture_records "$r"; done)"

# ── the function-boundary legs DISCRIMINATE: each positive beside the negative one edit away ──
SDISC="$TMP/seam-disc"; mkdir -p "$SDISC/bin"
cat > "$SDISC/bin/disc-lib" <<'EOF'
kb_parse_resp() { local resp="$1"; shift; jq "$@" <<<"$resp" 2>/dev/null || true; }
kb_api() { curl -sS -X "$1" "$API$2"; }
read_card() { kb_api GET "/tasks/$1.json"; }
answers_one() {
    resp="$(kb_api GET "/x")" || return 1
    printf '%s' "$resp" | jq -e '.data.ok' >/dev/null
}
answers_named() {
    resp="$(kb_api GET "/x")" || return "$RC_UNREADABLE"
    printf '%s' "$resp" | jq -e '.data.ok' >/dev/null
}
id_of() { printf '%s' "$1" | jq -r '.data.id // empty'; }
spread_one() {
    resp="$(kb_api GET "/y")" || return 1
    printf '%s' "$resp"
}
bare_one() {
    kb_api GET "/z" >/dev/null || return 1
}
only_propagates() {
    resp="$(kb_api GET "/x")" || return 1
    printf '%s' "$resp"
}
EOF
cat > "$SDISC/bin/disc-callers" <<'EOF'
collapsed="$(kb_parse_resp "$resp" -r '.data.id // empty')"
[ -n "$collapsed" ] || die "nothing read"
kept="$(read_card 5)"
[ -n "$kept" ] || die "no card"
if answers_one; then echo yes; fi
rc=0; answers_named || rc=$?
if answers_named; then echo yes; fi
x="$(only_propagates)" || die "could not read"
answers_one || rc=$?
if x="$(spread_one)"; then
    :
else
    rc=$?
fi
bare_one "$x"
rc=$?
if ! kb_is_uint "$n"; then die "not a number"; fi
if ! kb_api PATCH "/tasks/1.json" "{}" >/dev/null; then die "write refused"; fi
ok="$(printf '%s' "$resp" | jq -c 'if (.data|type) == "array" then .data else empty end')"
items="$(printf '%s' "$resp" | jq -c '.data.items // []')"
EOF
echo "== the function-boundary legs discriminate =="
eq "exactly the positives: a path defaulted to a VALUE (not to empty), a collapser's capture, rc-1 answered AND used (however the rc is taken), a reader tested for truth (not a write)" \
   "$(printf '%s\n' '(top)():envelope' 'collapsed' 'if answers_named' 'if answers_one' | sed 's|^|bin/disc-callers:|'; printf '%s\n' 'answers_one()' 'bare_one()' 'spread_one()' | sed 's|^|bin/disc-lib:|')" \
   "$(_roc_members "$SDISC")"
eq "the derived sets: kb_parse_resp COLLAPSES; every function here READS" \
   "$(printf '%s\n' 'C kb_parse_resp' 'R answers_named' 'R answers_one' 'R bare_one' 'R id_of' 'R kb_api' 'R kb_parse_resp' 'R only_propagates' 'R read_card' 'R spread_one')" \
   "$(_roc_fn_sets "$SDISC" | awk -F'\t' '$1 != "D" { print $1 " " $2 }' | LC_ALL=C sort)"

# ── the denominator ─────────────────────────────────────────────────────────────────────────
#
# Printed on EVERY run, clean or not. A clean result over an unnamed population reports where
# the searcher stopped, not the state of the tree — so this gate states the population it was
# clean over, re-derived from the tree by the same code path that judges it.
mapfile -t POPULATION < <(_roc_population "$ROOT")
mapfile -t OPCHECKS   < <(_operator_run_checks "$ROOT")
# The scan's rc is READ: `_roc_records` ends in the function-boundary awk, and a scanner that
# did not run must not reach the absence assertions below as a tree with no seam in it.
RECORDS_TXT="$(_roc_records "$ROOT")" \
    || { echo "read-outcome-collapse-selftest: UNMEASURED — the function-boundary scan did not run (rc $?)" >&2; exit 3; }
mapfile -t RECORDS < <(printf '%s\n' "$RECORDS_TXT" | awk 'NF')
mapfile -t MEMBERS < <(printf '%s\n' "$RECORDS_TXT" | awk -F'\t' 'NF { print $1 ":" $2 }' | LC_ALL=C sort -u)
FNSETS="$(_roc_fn_sets "$ROOT")" \
    || { echo "read-outcome-collapse-selftest: UNMEASURED — the READ/COLLAPSE derivation did not run (rc $?)" >&2; exit 3; }

# The runbook GUARD's input. ⛔ Its rc is READ, not merely kept: an index this process cannot
# read must not reach the guard below as "no runbook invokes anything", which would satisfy it
# silently. `_md_fenced_lines` answers 3 for that, and this is where the gate dies on it.
RUNBOOK_INVOKED="$(_runbook_invoked_checks "$ROOT")" \
    || { echo "read-outcome-collapse-selftest: UNMEASURED — the tracked-markdown set could not be read (rc $?); the runbook guard did not run" >&2; exit 3; }

# THE PRICE OF THE STATED EXCLUSION, re-measured every run rather than written down (canon #16):
# what unioning the whole harness in would ADD, through the identical scanner. Asserted on by
# nothing — it exists so the ruling "the harness stays out" is re-arguable against a live figure.
mapfile -t DECLINED_HARNESS < <(
    LC_ALL=C comm -23 <(_selftest_shell_files "$ROOT") <(printf '%s\n' "${OPCHECKS[@]}" | awk 'NF') \
    | { mapfile -t h; _roc_records_over "$ROOT" "${h[@]:-}"; } | awk -F'\t' 'NF { print $1 ":" $2 }' | LC_ALL=C sort -u
)

LISTED="$(printf '%s\n' "${DISPOSITIONED[@]}" | awk -F'|' 'NF { print $1 }' | LC_ALL=C sort -u)"
DERIVED="$(printf '%s\n' "${MEMBERS[@]}" | awk 'NF')"
NEW="$(LC_ALL=C comm -23 <(printf '%s\n' "$DERIVED") <(printf '%s\n' "$LISTED"))"
STALE="$(LC_ALL=C comm -13 <(printf '%s\n' "$DERIVED") <(printf '%s\n' "$LISTED"))"

_count() { printf '%s\n' "$1" | awk 'NF' | wc -l | tr -d ' '; }

echo "== denominator [read-outcome-collapse/v3] =="
printf '  shell files scanned (bin/ + hooks/ + operator-run checks)     : %s\n' "${#POPULATION[@]}"
printf '  of those, tests/ operator-run checks (tests/*-check.sh)       : %s\n' "$(_count "$(printf '%s\n' "${OPCHECKS[@]}")")"
printf '%s\n' "${OPCHECKS[@]}" | awk 'NF { printf "    %s\n", $0 }'
printf '  functions defined in them (names, deduped across files)       : %s\n' "$(_count "$(printf '%s\n' "$FNSETS" | awk -F'\t' '$1 == "D"')")"
printf '  of those, READ (a transport/decoder, or a function that reads): %s\n' "$(_count "$(printf '%s\n' "$FNSETS" | awk -F'\t' '$1 == "R"')")"
printf '  of those, COLLAPSE a read into their own output               : %s\n' "$(_count "$(printf '%s\n' "$FNSETS" | awk -F'\t' '$1 == "C"')")"
printf '%s\n' "$FNSETS" | awk -F'\t' '$1 == "C" { print $2 }' | LC_ALL=C sort | awk 'NF { printf "    %s\n", $0 }'
printf '  candidate records (captures, envelopes, rc merges, conditions): %s\n' "${#RECORDS[@]}"
printf '  candidate MEMBERS (records merged per <file>:<key>)           : %s\n' "$(_count "$DERIVED")"
printf '  dispositioned below                                           : %s\n' "$(_count "$LISTED")"
printf '  NEW / undispositioned                                         : %s\n' "$(_count "$NEW")"
printf '  stale dispositions (listed, no longer derived)                : %s\n' "$(_count "$STALE")"
printf '  harness members this exclusion DECLINES (not asserted on)     : %s\n' \
    "$(_count "$(printf '%s\n' "${DECLINED_HARNESS[@]}")")"
printf '  by spelling (a capture may carry more than one):\n'
printf '%s\n' "${RECORDS[@]}" | awk -F'\t' 'NF { k = $4; gsub(/\([^)]*\)/, "", k); n[k]++ } END { for (k in n) printf "    %-16s %s\n", k, n[k] }' | LC_ALL=C sort

echo "== the derivation carries real data (control on the REAL tree) =="
eq "the scan of $ROOT derived at least one candidate" "false" \
   "$([[ "${#RECORDS[@]}" -eq 0 ]] && echo true || echo false)"
# A glob that has silently stopped matching is indistinguishable from a tree with no operator-run
# checks — and the whole point of card#10311 is that this gate once WAS blind to one and ran
# green. Zero here means the widening is inert; it reds.
eq "the population names at least one operator-run check on the REAL tree" "false" \
   "$([[ "$(_count "$(printf '%s\n' "${OPCHECKS[@]}")")" -eq 0 ]] && echo true || echo false)"

echo "== the naming partition that makes the glob a COMPLETE population =="
# `tests/*-check.sh` is only the right population while every OTHER tests/*.sh declares which
# kind it is. A file named neither `_*`, `*-selftest.sh`, `*-census.sh` nor `*-check.sh` is
# unclassifiable, which means nothing can say whether it belongs in this gate — so it reds here
# rather than defaulting to "out", which is how the blind spot this card closes was created.
eq "a tests/*.sh whose name declares no kind (name it *-check.sh if an operator runs it)" "" \
   "$(printf '%s\n' "$(_tests_shell_unclassified "$ROOT")")"

echo "== the runbook guard: a check a runbook RUNS must be a kind this gate can place =="
# The second guard on the glob, and the weaker one by construction — its markdown reach is
# bounded and the lib states the bounds. What it catches is the shape that would otherwise
# re-open the blind spot: an operator-run check landing under an unrecognised name AND being
# wired into a runbook step. It cannot catch one that is never wired into a fenced block, which
# is precisely why the POPULATION is the glob above and not this.
unplaceable=""
while IFS= read -r rb; do
    [[ -n "$rb" ]] || continue
    [[ -r "$ROOT/$rb" ]] || { unplaceable+="$rb (a runbook invokes it; this tree does not carry it)"$'\n'; continue; }
    case "${rb#tests/}" in
        _*|*-selftest.sh|*-census.sh|*-check.sh) ;;
        *) unplaceable+="$rb (a runbook invokes it; its name declares no kind)"$'\n' ;;
    esac
done <<< "$RUNBOOK_INVOKED"
eq "a runbook invokes a tests/ file this gate cannot place" "" "${unplaceable%$'\n'}"

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
