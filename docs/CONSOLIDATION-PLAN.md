# Consolidation program

The durable record of the toolkit's 2026-07 consolidation program: what it diagnosed, what it
shipped, what it deliberately did **not** ship, and the claims it disproved along the way.

**Goal:** make the toolkit extensible — so that fixing a bug lands in one place and does not mint
its sibling. Every stage was judged on one question: *after this lands, does the next fix in this
area land once?* A stage that didn't improve that didn't belong.

**How to read this.** Per-version bookkeeping lives in [`CHANGELOG.md`](CHANGELOG.md) and is not
repeated here; this document owns the *reasoning* — the measurements, the refuted claims, and the
rules a future stage is still bound by. Where the two disagree, the CHANGELOG is authoritative on
what shipped and this file is authoritative on why.

**Citation discipline.** Everything here cites a **symbol, function, or file** — never
`file:line`. The program's own source plan pinned line numbers, and by the time this document was
written essentially none of them still pointed at what they named. Line numbers do not survive;
names mostly do, and a renamed symbol fails loudly where a shifted line number fails silently.

---

## Status

Measured against `origin/dev` at the time of writing; the CHANGELOG is the running record.

| stage | what it was | status |
|---|---|---|
| **A** | three live defects found *by* the plan's own review passes | **shipped** |
| **B** | make the gates able to fail | **shipped** (5/5) |
| **C** | one value-guard on every axis | **not started**; its positional half was superseded by a *different, better* fix (below) |
| **D** | one library (`promote-released-cards` sources the lib) | **recommended dropped** — see *Stage D* |
| **E** | de-duplicate the PR-query set | **shipped** (card #5227); its other half stays dropped |

**C remains design-only by direction:** it may be planned and reviewed, not built, without a fresh
decision — and **this document does not authorize it**. E was design-only under the same rule until
it received that fresh decision and was built (card #5227); C has not.

---

## Diagnosis — why fixes here kept minting siblings

Four structural properties made a fix in this codebase *likely to create the next bug*. Each was
measured, not asserted. The first is the program's central finding, and the two earlier revisions
of the plan both got it wrong.

### 1. "Empty vs absent" is three invariants wearing one label

They present the same surface question — *"was there a value?"* — and require **opposite** answers
on the same input shape:

| axis | what a 1-arg / zero-arg call must mean | where the contract lives |
|---|---|---|
| **flag-value** — a flag consuming a value must get a non-empty one | **FAIL** | `kb_require_value`, asserted in `tests/kb-board-lib-selftest.sh` |
| **positional** — an empty positional ≠ an absent one | **SUCCEED** (bare `kbcard` → usage; `board-card-start` with no args → the current branch) | `hooks/post-checkout` calls `board-card-start` with **zero args** — the primary production path |
| **config-read** — an empty `core.hooksPath` ≠ an unset one | distinguished by **exit status**, not by value | `_ibh_read_hooks_path` in `install-board-hooks` |

So `kb_require_value` **cannot** absorb the positional axis: inside a function `$#` is the
*function's* arity, and its 1-arg shape is already contracted with the inverse answer.

This is why adopting `kb_require_value` at every value-taking arm of `kbcard` (card #5146) did not
prevent card #5276 two days later — **not** because "one home for an invariant doesn't work", but
because these were never one invariant. Any plan promising "one value-guard on every axis" is
promising something the shapes forbid.

The real duplication is narrower and still worth fixing; it is scoped under *Stage C* below.

### 2. Guards live at call-sites, so consolidating deletes them silently

Revision 1 of the source plan would have deleted two live guards while "removing duplication" —
the drift-check `MISSING-LIB` assertion, and (via a mis-specified retry) promote's
0-visible-cards refusal. That is the failure mode reproducing *inside the fix for it*.

### 3. Several gates could not fail, so a broken fix would ship green

`agent-board-toolkit-drift-check . .` compares every file to itself, so it cannot detect content
drift. Three bins had **zero** selftest coverage. `board-session-close`'s Open-PRs leg had none.
The CI matrix and the selftest files were kept in step **by hand**, so a new test could be silently
skipped forever. Stage B closed all four — note *how* it closed the first: the self-run still cannot
detect content drift and was deliberately **kept anyway**, because its `MISSING-LIB` leg is a live
assertion; a fixture job was **added** beside it. Compensating for a gate that cannot fail is not
the same as removing it.

### 4. A bin with no test coverage cannot be refactored

Which is why the duplication persisted, rather than why it started.

**Explicitly not claimed:** that any of this changes how many cards get filed. Card volume tracks
audit intensity and commit volume. The program was justified by three live defects, four unguarded
gates, and one invariant with five spellings — not by a metric.

---

## Ground rules

Binding on any future stage of this program.

1. One stage = one PR = one CHANGELOG entry. Doc-sync inside the stage, never after.
2. **Prove-it-can-fail** on every new check — red before green, no exceptions.
3. **Add, don't replace**, wherever an existing check has any live assertion.
4. **Every stage carries a `Preserve:` list** — what must still be true afterwards. A consolidation
   that drops a guard is a regression wearing a refactor's clothes, and revision 1 did it twice.
5. **Mechanism belongs in the primitive; policy belongs at the caller.** When a call-site guard has
   no equivalent in the primitive, do not reflexively hoist it — ask which it is. The repo settled
   this and wrote it down twice (in `promote-released-cards` and
   `tests/promote-pagination-selftest.sh`): *the lib returns an rc for its caller to interpret,
   whereas this tool IS the caller and its policy is to die.* A blanket "hoist everything" would
   break the fail-soft callers of `fetch_board_cards` — rule 4 violated in the act of obeying
   rule 5.
6. The program's durable copy lands as this file.

**Review discipline.** Per stage: design review before code → build → implementation review on the
diff → a **fresh-adversarial** pass with no prior context → iterate to **zero must-fix**, with the
gradient recorded in the PR body. Reviewers primed with **reachability** (can this branch fire?),
**doc-sweep** (a corrected code-state claim is swept across all docs in the same PR), and the
*"correct defense-in-depth"* mis-clear smell. Use **two reviewers with different lenses**, not two
with the same one — that is how the drift-gate error surfaced.

---

## Stage A — three live defects · shipped

Found *by* the plan's review passes. Two were in a tool that **writes to the board**.

- **`board-card-start` honored `--lint` only in position 1**, and the file had no `$#` check
  anywhere, so `board-card-start <branch> --lint` performed a **real card move**. Byte-for-byte the
  defect `install-board-hooks` documents already fixing for its own `--check`. It was one argument
  order away from firing in production: `hooks/pre-push` already invoked the tool with `--lint`
  *and* a positional branch, so only the order stood between the advisory path and a real move.
- **`board-card-start` used `branch="${1:-…}"`** — `:-` fires on **empty**, so
  `board-card-start "$BRANCH"` with `BRANCH` unset silently retargeted the move to whatever HEAD
  was on.
- **`agent-board-toolkit-runtime-check` printed a fixed line range for `--help`**, leaking past the
  header into `set -euo pipefail` — the same defect card #5145 had already fixed elsewhere.

Both `board-card-start` defects shipped in one PR (card #5333); the runtime-check header shipped
separately (card #5334), replacing the fixed range with the contiguous-comment `awk` form the other
movers use.

**The third item's prescription was replaced on measurement, and this is the correction that
matters.** Stage A said to *"widen `tests/help-output-selftest.sh`'s `CLIS=()` to every bin with a
`--help` arm"*. That was not built, because deriving the **required** side of a set comparison
fails **open**: a CLI regressing away from the header form drops *out* of a derived required set,
and the suite goes green on the exact defect it exists to catch. What shipped instead (card #5339)
keeps the required set hand-written — `CLIS` ∪ `EXCLUDED`, each exclusion stating its reason — and
derives only the **scan**: every bin whose source mentions `--help` at all, which can only ever
*add* a name to answer for.

> **Generalize this.** A derivation feeding the **required** side of a set comparison fails open; one
> feeding the **found** side, or challenging an exemption, fails closed. Ask which side before
> proposing "just derive it". The two look identical in a diff.

**Preserve (still true):** `board-card-start` is fail-soft by contract — it must exit 0 on every
path and never block a checkout. Its argument refusals return rc 0 for exactly this reason; that
divergence from its siblings is deliberate and must not be "fixed".

**Residue:** the three one-liner bins (`adopt-to-dl`, `dl-a0-backfill-triaged`,
`dl-a1-register-field`) sit in `EXCLUDED` because a one-line usage string cannot satisfy a
line-count equality against a multi-line header. Moving them into `CLIS` would mean *growing their
help output* — a user-facing change on three tools, so it is a decision, not a cleanup. Open as
card #5412.

---

## Stage B — make the gates able to fail · shipped 5/5

Each item landed as its own PR; see the CHANGELOG for what each changed.

- **A fixture-driven drift job** (card #5356) — a divergent vendored copy in a temp dir, asserting
  `DRIFT` **and** `MISSING-LIB` both fire, and that a clean co-vendored copy passes. The
  `drift-check . .` self-run was **kept**: its `MISSING-LIB` leg asserts the shipped tree carries
  the lib for its sourcers. *Add, never replace* — revision 1 of the plan proposed replacing it,
  which would have deleted a live assertion.
- **Selftests for the uncovered bins** (cards #5356, #5357) — `dl-a0-backfill-triaged` and
  `dl-a1-register-field` exercised **as processes** (neither is main-guarded), and
  `agent-board-toolkit-drift-check` covered by the fixture job above.
- **The Open-PRs leg of `board-session-close`** (card #5358) — previously unasserted, and named on
  card #5227 as the reason that code could not be touched safely. Stage E was built on it.
- **CI-matrix ↔ selftest-file parity** (card #5355) — the matrix list was hand-aligned behind a
  *"keep this list in sync"* comment; a test absent from it never ran and nothing said so. The
  guard is deliberately its **own** CI job rather than a matrix entry: a matrix entry would be
  subject to the very list it validates.
- **A stale tool list in `ADOPTION.md`** (card #5359) — it named a tool retired in v0.9.0 *and*
  omitted six that exist. Removed rather than corrected: it was a second copy of README's table, so
  the section now names the categories and points at the one list. This is the shape to prefer —
  **delete the restatement and point at the owner**, rather than re-syncing N copies.

**Extensibility gained:** a change to any of these bins is now verifiable, and a new test cannot be
silently skipped.

---

## Stage C — one value-guard on every axis · not started; positional half superseded

**The positional half is settled, and not the way this stage proposed.** Stage C said to *extend
`kb_require_value` to the positional axis*. That directly contradicts the diagnosis above, which
proves it cannot be done — the contradiction survived two review passes inside the plan itself.
What shipped (card #5343) is a **separate primitive**, `kb_require_positional`, living beside
`kb_require_value` in `bin/_kb-board-lib.sh`. Two primitives, because there are two invariants.

That consolidation covered three hand-rolled copies of the positional rule
(`install-board-hooks`, `adopt-to-dl`, `board-card-start`). Its **weakest property** is worth
stating plainly, because it is easy to over-cite: the both-copies matrix proves only that the lib
primitive and `install-board-hooks`' standalone mirror **agree on the inputs it feeds**. It is
blind by construction to a call site left hand-rolled — and a fourth such site was found
afterwards (`agent-board-toolkit-drift-check` silently discards a third positional; card #5429).

**What remains of Stage C is the flag axis alone**, and it is still open. Measured on `origin/dev`:

| spelling | where | rc | names the offending flag? |
|---|---|---|---|
| `kb_require_value` | `kbcard`, `adopt-to-dl` | 2 | yes |
| `shift; [[ -n … ]] \|\| { echo "$USAGE" >&2; exit 2; }` | `next-dl`, `dl-a0-backfill-triaged`, `dl-a1-register-field` | 2 | **no** — prints usage only |
| `"${2:?…}"` | `agent-board-toolkit-runtime-check` | **1** | no — a raw bash diagnostic |
| a local `require_value` mirror | `promote-released-cards`, `release-pr-body` | 2 (via `die`) | yes |

So one invariant still yields **two exit codes** and three message qualities.

**Scope, if it is ever built.** Only the bins that source the lib can adopt the primitive; the two
standalone tools are vendored into consumer repos and cannot. `agent-board-toolkit-runtime-check`
is **excluded on purpose** — it validates `_kb-board-lib.sh`, so it must not source it; making the
mixed-runtime *detector* depend on the artifact under test is backwards, and its rc is fixed in
place by that.

**Honest scope:** this would retire the *argv* axis. It does **not** retire the class. Card #5276
records the axis as four positions found in order — flag values, a `core.hooksPath` **config read**,
the positionals in `install-board-hooks`/`adopt-to-dl`, and `kbcard`'s own positional (still open).
The config read is the one **no argument primitive can reach**; it needed, and got, its own fix
under card #5200. Retiring the argv axis retires three of the four positions and leaves the class
intact.

> The lesson card #5276 states in its own body is the one to carry: **a sibling audit's axis must be
> the *shape*** — a value that can be present-but-empty where *presence* is the real question —
> **never the category of source it was last found in.** An earlier sweep passed `kbcard` clean, and
> that verdict was correct *for the axis it examined*; it simply examined a different one.

**Build prerequisite:** enumerate **every** behavior delta per call-site before dispatching. The
first attempt's table had four rows and review found at least four more. A partial table buys
consent for a smaller change than would ship — which is why this is ask-first.

**Preserve:** `install-board-hooks`/`adopt-to-dl` empty-positional rejection; `next-dl`'s
"project named twice" mutual exclusion; `kbcard field`'s sub-verb dispatch.

**Related open cards:** #5276 (the empty-positional case), #5427 and #5351 (whether a `--`
terminator belongs in the shared shape — currently `install-board-hooks` refuses a bare `--`, and
`adopt-to-dl`'s `--) ;;` arm is decorative), #5429, #5409.

### Ruling 2026-07-29 — **DEFERRED, not declined. Do not build it off this section alone.**

Put to the user with the trade stated and deferred **by decision, not by neglect**. Three reasons,
recorded so this is not re-litigated from the defect list alone:

1. **The benefit is real but small, and its blast radius is not.** What the stage buys is one exit
   code and one message quality across ~5 bins. What it touches is the **error contract every
   consumer of those bins sees** — a caller scripting `rc == 2 ⇒ usage error` is relying on the
   current shape, including the `runtime-check` outlier. Changing what a tool rejects, and how, is
   ask-first in its own right; the size of the diff is not the size of the change.
2. **The build prerequisite above is unmet, and it is the load-bearing one.** A complete
   per-call-site behavior-delta table must exist BEFORE any dispatch. The first attempt's table had
   four rows and review found at least four more — so the table is not a formality, it is the thing
   that establishes what would actually ship. Building without it buys consent for a smaller change
   than lands.
3. **A dry queue is not a reason to build.** This stage came up precisely because nothing else in
   the toolkit queue was runnable, which is the worst reason to touch a shared error contract.

**What would change the ruling:** a reason to be in these bins anyway (a defect fix in `next-dl`,
`dl-a0-backfill-triaged`, `dl-a1-register-field`, or `runtime-check`), at which point the delta
table is cheap to produce and the axis rides along with work that justifies itself. Absent that,
the current state is accepted **with its cost named**: one invariant, two exit codes, three message
qualities — and `agent-board-toolkit-runtime-check`'s `rc 1` is fixed in place by its deliberate
exclusion (it validates `_kb-board-lib.sh`, so it must not source it).

---

## Stage D — one library · recommended dropped

The stage would have made `promote-released-cards` source `_kb-board-lib.sh` and drop its mirrors.
It is recommended **dropped**, and the reasoning is worth keeping because it is the strongest
argument in the program *against* consolidation:

- **`release-pr-body` was already dropped from it.** Zero HTTP calls; only `require_value` overlaps
  the lib. Giving a self-contained, network-free, git-only tool a hard dependency on a large lib —
  plus a co-vendoring obligation — to dedup **one line** is the wrong trade.
- **The retry is a restructure, not a knob.** Measured against a 503→503→200 server: `kb_api`'s
  shape (`-sS`, deliberately **no `-f`**, to preserve error bodies) plus `--retry` concatenates
  every attempt's body, the status read sees `200`, and `kb_api` returns success on a garbage
  document. Promote's own `api()` is safe only because it uses `-f`. A working shape needs
  `-o <tmpfile> -w '%{http_code}'`.
- **Retry parity across all three fetchers.** Promote's board *read* also retries. A knob honored
  only by `kb_api` leaves `fetch_board_cards` and `kb_api_status` unprotected — the identical
  mistake the lib documents making once with `KB_CURL_MAX_TIME`.
- **Hoist, don't delete, the 0-visible-cards refusal.** `promote-released-cards` dies when page 1
  returns zero cards (*"the token's user is likely not a member of board N"*). `fetch_board_cards`
  has **no equivalent** — rc 0 and `[]`. Dropping it would turn a lost-membership token into
  `0 moved` and **exit 0**.

**Correcting the stage's own supporting claim.** It asserted the two host guards are *"behaviorally
identical — verified over 21 hostile URLs × 4 expected-hosts"*. The live assertion is
`tests/kb-host-guard-selftest.sh`, and its measured shape is: `kb_require_https_host` (the lib) and
`host_ok` (the standalone mirror in `promote-released-cards`, sed-extracted by the test) compared
row-by-row over **20 URLs at one expected host** — 6 that must be accepted, 14 that must be refused,
including the userinfo, fragment and query authority-split cases — plus **unset** and **empty**
`KANBAN_EXPECTED_HOST` fail-closed regimes and a loud-refusal check. The identity claim is
supported; the numbers quoted for it were not. Cite the test, not the sentence.

That test is the **security** test in the CI matrix, and it **exits 1** if it cannot extract
`host_ok` — so any rename or removal of that mirror fails the build by design rather than
silently reducing coverage.

**If it is ever revived:** use the literal `source "$KB_LIB"` — `agent-board-toolkit-drift-check`
matches that exact string (anchored, with leading whitespace allowed), and `. "$KB_LIB"` evades it.
Both [`INSTALL.md`](INSTALL.md) §6b and [`ADOPTION.md`](../ADOPTION.md) already split the tools into
*lib-sourcing, must be co-vendored with `bin/_kb-board-lib.sh`* and *standalone, needs no lib* — and
both name `promote-released-cards` in the second group, alongside a §6b recipe that copies it as a
single file. This stage moves it into the first group, so both statements and that recipe need
amending, plus an entry in [`UPGRADE.md`](UPGRADE.md). The framework's `templates/release/` mirror
would need the lib too — that mirror is currently healthy, and this stage would make its job harder.

---

## Stage E — de-duplicate the PR-query set · shipped

`board-session-close` held a hardcoded repo list for its Open-PRs leg while `BSC_WORKTREES`
hardcoded the local checkouts, and the code itself admitted *"keeping the two in step is manual
today"*. It was left out of card #5200's hoist **deliberately**, and card #5227 records why: it is a
*different semantic* — unique GitHub remotes, not local checkouts, and two worktrees of one repo are
two entries in `BSC_WORKTREES` but must be one entry in a PR query. So the consolidation was not
"reuse the array"; it is to derive the PR set from `BSC_WORKTREES` by de-duplicating on
`git remote get-url`. That is a behavior change to a leg that had no coverage — which is why Stage B
had to come first.

**What shipped, and the two decisions that shaped it.** The derivation keeps the first *present*
checkout of each distinct remote, in `BSC_WORKTREES` order — which reproduces the retired literal
list exactly, verified byte-identical against the live host before merge.

- **The dedupe key is the raw `git remote get-url origin` string, with no normalizer.** An
  ssh-vs-https re-clone under-dedupes and lists one repo twice under two labels — visible, labelled,
  harmless. A normalizer would be a new primitive with its own defect surface bought for no measured
  benefit. The weakest property, stated at the call site: the dedupe holds for byte-identical URLs
  only, and it assumes each checkout's `gh` target *is* its `origin` (a fork remote or
  `gh repo set-default` could disagree).
- **An entry whose remote cannot be read keeps its own slot and is named — it is never deduped
  away.** This inverts the naive derivation and is the reason the change is worth making at all.
  The query set is the *required* side, so dropping an unreadable entry would fail **open**: a
  clean-looking section that silently covered fewer repos, with no diff anywhere to record it —
  strictly worse than the literal list it replaced, which at least needed a human edit to lose a
  repo. An extra query is the harmless direction. The warning rides the leg's own stdout section
  rather than stderr, because the failure direction is safe by construction and stderr is shared by
  every leg.

Since the `-e .git` filter necessarily runs before the remote read, the rule is first *present*
checkout: if a repo's primary checkout lost its `.git` while a `-prod` clone kept one, the repo is
now covered via the clone where it previously went unqueried. That is a real behavior change, and a
strict improvement in coverage.

**Its other half is impossible and was dropped.** The coord config has **zero** path-like keys;
`BSC_WORKTREES` spans more checkouts than there are repos, and the board-name → directory-name
mapping is not a mechanical transform. Deriving worktrees from the config would silently drop the
`-prod` checkouts — the exact failure mode the stage claimed to prevent. Calling these "three
copies of one list" was a category error: the config maps *boards → repos*, `BSC_WORKTREES` maps
*local checkouts*, and the PR loop maps *unique remotes*. Three different sets.

**Depended on Stage B** — its Open-PRs coverage is what made this leg safe to touch, and that
coverage is what caught the two traps this change had to clear: the fixture's `git` stub had to
learn `remote get-url` (a silent stub hands every entry an empty key, collapsing all five into one
group), and the fail-closed path needed its own case, directly paired with the readable-remote
assertion so it cannot pass on a leg that simply queries everything.

Partially closes card #5227 — note the split on the card; the operator-specific absolute paths stay
out of scope. Filed separately as roundtable **#187**:
a coord-config schema FR for a `worktrees[]` surface, which is the prerequisite for ever removing
the operator-specific absolute paths. That FR asks for an explicitly declared array and records why
deriving the list from the config's repo list is the wrong fix — the same reasons this stage's other
half was dropped, above.

---

## Dropped, with reasons

- **A new `kb_parse` option parser** — a sibling implementation beside the `kb_require_value` that
  already owns the flag invariant. Building it would *be* the defect this program exists to remove.
  Its value-return mechanism would also rewrite option plumbing across the largest tool in the
  repo, which drives three live boards. Stage C gets the win without the rewrite.
- **A "keep in sync" comment sweep** — the premise evaporated. The genuine instances nearly all
  describe the standalone mirrors Stage D would remove at the source, and the proposed
  guard was a decoration by construction: it would have matched the dispatch sites Stage C changes
  and greened permanently without ever firing on the ones that remain. Deleting the prose would
  also have destroyed **measured** knowledge — `_ibh_read_hooks_path`'s header records the git-2.43
  measurements that are the whole reason it returns a status, and `kb_require_positional`'s header
  records a **negative result**: a separate seen-flag was tried in `install-board-hooks` and
  removed, because with empty positionals refused nothing could reach it and a mutation of it could
  not be made to fail. That second one is worth noticing twice — it originally lived at the
  `install-board-hooks` call site and **moved with the rule** when card #5343 hoisted it. A
  consolidation must carry the measured prose to the new owner, not leave it behind with the code
  it explained. Its one useful piece, CI-matrix parity, moved to Stage B and shipped there.
- **Card-rate metrics** — never the goal; see the diagnosis.

---

## Corrections carried forward

Claims the review passes disproved. Kept, because a plan that quietly drops its refuted claims
teaches the next reader nothing.

- **"The drift gate cannot fail"** — true only for the content-drift axis; its `MISSING-LIB` leg is
  live. Revision 1 said *replace*; that would have deleted it. → **add, never replace.**
- **"`INSTALL.md` §6b is unaffected"** — false. Both it and `ADOPTION.md` state these bins need no
  lib, and §6b's recipe is a single-file `cp`. → *affected, with an upgrade step.*
- **"The framework mirror proves hand-sync failed"** — false when checked. The mirror measured
  self-consistent, carried self-documenting `MIRROR NOTE` blocks, and was hours behind a patch
  release — healthy, not evidence of drift. (A measurement, not a standing guarantee: it lives in
  another repo and is not covered by anything here. Re-measure before citing it.)
- **Stage ordering** — revision 1 migrated two bins in an early stage that a later stage was what
  let them see the lib.
- **Renaming to resolve a collision can be a protected-settings change.** Stage B needed a name
  distinct from an existing CI job. Rename the **file**, not the job: a job name can be a required
  status check on a protected branch, where a rename is an admin operation and not a refactor.

---

## Verification

Per stage: the full `tests/*.sh` matrix green locally and in CI; every new check demonstrated **red
before green**; `shellcheck -S error` clean; the review loop converged to **zero must-fix** with the
gradient in the PR body; every `Preserve:` item asserted by a test, not by inspection.

```bash
bash tests/<each>.sh
bin/board-card-start "$(git branch --show-current)" --lint   # Stage A: must NOT move a card
bin/agent-board-toolkit-runtime-check --help | tail -3       # Stage A: must not leak `set -euo`
bin/promote-released-cards --dry-run                         # Stage D, if revived: plan unchanged
bin/board-session-close                                      # Stage E: same findings, byte-identical
```

**A pass is evidence only if failure was possible.** Every check added by this program was made to
fail once before it was trusted — and two traps are worth naming, because both produced a green run
that meant nothing: a mutated copy of a bin extracted for testing can die on an unrelated
`$0`-anchored sibling *before* reaching the mutation, and an inequality assertion passes trivially
against a mutant that crashed. Assert on the outcome, not on an exit code.
