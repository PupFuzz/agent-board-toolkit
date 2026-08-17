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
| **B** | make the gates able to fail | **shipped** (5/5), plus a later addition on the same axis — the harness's own shared helper (card #5740); see *Stage B* |
| **C** | one value-guard on every axis | **shipped, narrower than its own title** (card #5566) — the *flag* axis only: its positional half was superseded by a *different, better* fix, and its exit-code half is **unreachable by construction** (both below) |
| **D** | one library (`promote-released-cards` sources the lib) | **DROPPED — decided 2026-08-01**, not merely recommended (see *Stage D*). It is the program's strongest argument *against* consolidating. |
| **E** | de-duplicate the PR-query set | **shipped** (card #5227); its other half stays dropped |

**C was design-only by direction** — plannable and reviewable, not buildable, without a fresh
decision, which **this document never granted**. It received that decision on 2026-08-01, once the
build prerequisite below was discharged, and shipped. E had run the same course (card #5227).

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
| **positional** — an empty positional ≠ an absent one | **ZERO-arg SUCCEEDS** (bare `kbcard` → usage; `board-card-start` with no args → the current branch) while a **1-arg EMPTY call FAILS** — the two answers this axis must keep apart, and `$#` is the only thing that can | `hooks/post-checkout` calls `board-card-start` with **zero args** — the primary production path |
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

### Later addition on this axis — the harness's own helper (card #5740)

Stage B made the gates *runnable*. It did not ask whether the assertions **inside** them could
fail, and one of them could not.

`has()` — a literal-substring assertion helper — was defined locally in **ten** selftests, and one
copy took its arguments in the opposite order. That divergence is invisible to every gate this
stage built, and the mechanism is the durable part: reversing the arguments of a substring test is
neither a syntax nor a type error. Under a needle-first definition, `has <haystack> <needle>`
compares two unrelated strings and answers `false` — so **every assertion expecting `false` keeps
passing while testing nothing**. Per-file review cannot see it either: the inverted file had
carried its spelling since it was written and was internally consistent across its own eight call
sites, so neither that file nor the prelude could reveal the inversion in isolation. Only comparing
the two definitions could.

**The rule this leaves, binding on every future selftest:** a helper used by more than one selftest
lives in `_selftest-prelude.sh` and is *sourced*, never re-declared. A deliberate **variant** is
still fine and is not what this forbids — `kb-board-lib-selftest` defines `expect_rc`/`expect_out`
that route failures through the shared `eq`, which the prelude's docblock sanctions. The test is
whether a second definition can silently **disagree** with the shared one, not whether it exists.

**Deleting the copies did not close the class, and the first cut of this section said it had.**
Card #5740 left `has()` with one definition and a prelude comment asserting it "lives here and
nowhere else" — enforced by nothing executable. That is the shape *Stage B itself* was built to
remove (`ci-matrix-parity-selftest`'s `# KEEP THIS LIST IN SYNC` comment), re-minted one layer
down: fixing N copies without the guard that forbids the N+1th leaves the cause in place.
`prelude-shadow-selftest.sh` is that guard — it derives the helper set **from the prelude** rather
than restating it (a hardcoded list would be this program's own defect again), allow-lists the
sanctioned variants by name so adding a shadow costs an explicit edit, and fails if an allow-list
entry outlives the shadow it excuses.

**Weakest property, stated so it is not over-cited:** that guard compares **names**, not behaviour.
It catches a re-declared helper; it cannot catch a selftest that hand-rolls the same logic inline
under a different name, and it says nothing about whether the prelude's argument order is the right
one. It closes the copy channel that actually minted the bug — not every conceivable one.

---

## Stage C — one value-guard on every axis · flag half shipped; positional half superseded; exit-code half unreachable

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

**That fourth site is closed (card #5429), and deliberately NOT as a fourth adoption.** The bin
now refuses an extra positional and names which slot is empty, but it does so **hand-rolled**, on
the grounds this section already states two paragraphs down for `agent-board-toolkit-runtime-check`:
`agent-board-toolkit-drift-check` is a **detector of `_kb-board-lib.sh`** — the content-drift loop
diffs it and the MISSING-LIB leg reads it — so sourcing the lib would make the detector depend on
the artifact under test, and a drifted or broken lib would take out the very tool that exists to
report it. (An earlier draft of this paragraph justified the exclusion by co-vendoring cost
instead; that was wrong and is corrected here — **no consumer vendors this tool at all.** Per
`INSTALL.md` §6b consumers run it *from* the toolkit checkout against their repo, and both
consumer drift-gates were retired for the SHA-pinned composite action.) `kb_require_positional` is
also single-slot by construction (`<slot>` *is* the destination variable, which is what makes
"have I seen one?" a one-variable test). Generalising the primitive to N slots was the other
option and was rejected under canon #5: it costs the property that makes the current one simple,
to serve the repo's **only** two-positional bin — extraction belongs at the second real caller,
and there is no second.
So the rule now has **three implementations** (the lib primitive, `install-board-hooks`' standalone
mirror, and this two-slot hand-roll) — but three *argument shapes*, not three copies of one shape:
a single-slot loop, its vendored mirror, and a fixed-arity pair where `$#` answers both halves
directly. What IS shared and must stay shared is the **diagnostic wording**; the drift-check copy
carries a header comment saying so. `tests/drift-check-fixture-selftest.sh` pins all nine input
classes (arity 0/1/2/3+ x which slot is empty), each observed red under a mutation that removes
the guard it covers, including the empty-before-extra ordering that nothing else can witness.

**What remained of Stage C was the flag axis alone**, and it shipped on 2026-08-01 (card #5566).
The four spellings this section carried, measured on `origin/dev` before the build:

| spelling | where | rc | names the offending flag? |
|---|---|---|---|
| `kb_require_value` | `kbcard`, `adopt-to-dl` | 2 | yes |
| `shift; [[ -n … ]] \|\| { echo "$USAGE" >&2; exit 2; }` | `next-dl`, `dl-a0-backfill-triaged`, `dl-a1-register-field` | 2 | **no** — prints usage only |
| `"${2:?…}"` | `agent-board-toolkit-runtime-check` | **1** | partially — see the correction below |
| a local `require_value` mirror | `promote-released-cards`, `release-pr-body` | 2 (via `die`) | yes |

**Scope.** Only the bins that source the lib can adopt the primitive; the two standalone tools are
vendored into consumer repos and cannot. `agent-board-toolkit-runtime-check` is **excluded on
purpose** — it validates `_kb-board-lib.sh`, so it must not source it; making the mixed-runtime
*detector* depend on the artifact under test is backwards, and its rc is fixed in place by that.

### What the delta table found, and what it cost this section's own framing

The build prerequisite (a complete per-call-site behaviour-delta table) was discharged first, by
grepping the call-site set out of `bin/` rather than hand-listing it and then **running** every
site in both its missing and its explicitly-empty form. Four findings changed the stage:

1. **The four rows above are 57 individual call sites across 8 files** — the grouping is by
   spelling-and-bin, and per-flag granularity was hidden inside it (`dl-a1-register-field` alone is
   4 sites, not 1). Of those 57, **6** were caller-visibly adoptable; the rest were already at the
   target state, already at message parity, or out of scope. The stage's real size is 6 call sites
   across 3 files, not the "~5 bins" this section implied.
2. **The exit-code half of the headline is UNREACHABLE, and the stage did not retire it.** Every
   adoptable site already exited 2. The only rc 1 in the corpus is `agent-board-toolkit-runtime-
   check`'s `"${2:?…}"`, which is excluded by design and stays rc 1. So *"one invariant, two exit
   codes → one"* was never available: what shipped retires the **message-quality** divergence on
   the adoptable set, and **the exit-code divergence remains, by design**. Say it that way; the
   stronger claim is an overclaim in the exact program that exists to stop them.
3. **`next-dl`'s `--board` guard was COMPOUND**, and a drop-in swap would have shipped green while
   deleting a Preserve item. One condition — `[[ -n "${1:-}" && -z "$project" ]]` — did the
   value-presence test *and* the "project named twice" mutual exclusion. It was **split** into two
   sequential checks (presence via the primitive, exclusion kept as its own guard with its own
   message), presence first, which is the order the `&&` already short-circuited in. That order is
   now a choice rather than an accident, so it is asserted.
4. **`bin/kbcard`'s `cmd_field` sub-verb check is a false-positive lookalike.** It matches the
   diagnostic vocabulary and sits in the file most of this axis lives in, but it reads a positional
   sub-verb, not a flag's value. Not converted — see Preserve.

**One correction to this section's own starting table.** It called `runtime-check`'s row *"no — a
raw bash diagnostic"*. Run, it emits `…: line 40: 2: --reference needs a dir`: bash's own
positional slot (`2`) stands where the flag should be, but the custom text after it **does** carry
the literal `--reference`. Inconsistent and un-prefixed, not absent. The row's disposition is
unchanged.

### What shipped (card #5566)

`kb_require_value` adopted at all 6 caller-visible sites — `dl-a0-backfill-triaged --board`,
`dl-a1-register-field --board/--stage/--swimlane/--sentinel`, and `next-dl --board` — every one an
**rc-2-stays-rc-2 message-text upgrade** from a bare usage line to one naming the offending flag,
in both the missing and the explicitly-empty form. **No exit code changed on any healthy install.**

**One structural consequence the delta table did not predict, and it is caller-visible.**
`dl-a0-backfill-triaged` and `dl-a1-register-field` parsed their arguments **before** sourcing the
lib, so the primitive did not exist at the point of the check; the source block moved above the arg
loop (the ordering `next-dl`, `kbcard`, `adopt-to-dl` and `board-card-start` already had). On a
**broken install only** — a bin vendored without `_kb-board-lib.sh` beside it — those two now
answer *every* invocation with the missing-lib refusal at rc 1, including `--help`, which
previously answered rc 0 before the lib was ever consulted. `--help` is the widest-known case but
not the only rc that moves: with the check below the loop the missing lib was reported only for an
invocation the loop let through, so the loop's own refusals (`--bogus`, a trailing value-taking
flag, a stray positional) went **2 → 1** too — measured lib-less on both binaries, pre and post.
The two alternatives were both worse:
an inline mirror of the primitive is the defect this program exists to remove, and sourcing
conditionally (`[ -r "$KB_LIB" ] && source "$KB_LIB"`) evades `agent-board-toolkit-drift-check`'s
anchored `^[[:space:]]*source "\$KB_LIB"` probe, deleting a live guard to preserve a refusal path.
Both bins' selftests now pin the lib-less behaviour.

**Preserve — each asserted by a test rather than by inspection, each bullet naming what that
test actually covers (an rc-only assertion is not coverage of a message, and was not here):**

- `install-board-hooks`/`adopt-to-dl` **empty-positional rejection** — untouched by this stage;
  `tests/kb-positional-guard-selftest.sh` continues to own it.
- `next-dl`'s **"project named twice" mutual exclusion** — asserted in
  `tests/next-dl-selftest.sh` across all four spellings of the collision (`kanban --board dev`,
  `--board dev kanban`, `kanban bridge`, `--board dev --board alt`), each pinned to rc 2, to the
  **generic usage line** (a mutual-exclusion violation is not a value-guard failure), and to
  minting nothing and issuing no request. Both halves of the split were driven red independently.
- **`kbcard field`'s sub-verb dispatch** — deliberately **not** converted (finding 4 above);
  `tests/kbcard-field-selftest.sh` owns it, pinning the missing-sub-verb refusal by **message**
  and the unknown-sub-verb one by rc. The message half was added when review measured this
  bullet's own claim false: the file asserted rc **only**, and rc cannot separate the two arms —
  with the guard deleted an absent sub-verb falls through to the `*)` catch-all, which answers rc
  2 as well, so the whole 25-file suite stayed green over a deleted Preserve item (measured, then
  driven red by the added assertion). Driven as a process the delta is wider still and remains
  unasserted: `kbcard field` goes from a named rc 2 to a **silent rc 1** (the arm's own `shift` on
  an exhausted stack under `set -e`), which no function-level case can reach.

**Honest scope:** this retired the *argv* axis. It does **not** retire the class. Card #5276
records the axis as four positions found in order — flag values, a `core.hooksPath` **config read**,
the positionals in `install-board-hooks`/`adopt-to-dl`, and `kbcard`'s own positional (**closed
2026-08-04** — the verb dispatch now splits `$# -eq 0` from `$1 == ""` and refuses the second
through this stage's own `kb_require_positional`; it needed no new primitive, which is the
strongest evidence the shared shape was the right one).
The config read is the one **no argument primitive can reach**; it needed, and got, its own fix
under card #5200. Retiring the argv axis retires three of the four positions and leaves the class
intact.

> The lesson card #5276 states in its own body is the one to carry: **a sibling audit's axis must be
> the *shape*** — a value that can be present-but-empty where *presence* is the real question —
> **never the category of source it was last found in.** An earlier sweep passed `kbcard` clean, and
> that verdict was correct *for the axis it examined*; it simply examined a different one.

**Build prerequisite — discharged, and it earned its cost.** The rule was: enumerate **every**
behaviour delta per call-site before dispatching, because a partial table buys consent for a
smaller change than would ship. The first attempt's table had four rows; the discharged one derived
57 call sites and produced the four findings above — including the compound `next-dl` guard, whose
naive swap would have deleted a Preserve item **and still gone green**, since `next-dl` had no
argument-surface coverage at all until this stage added it. The prerequisite is what made the
difference between building the stage and building a regression that looked like it.

**Related cards:** #5276 (the empty-positional case — **closed 2026-08-04**), #5427 and #5351 (whether a `--`
terminator belongs in the shared shape — currently `install-board-hooks` refuses a bare `--`, and
`adopt-to-dl`'s `--) ;;` arm is decorative), #5429 (**closed 2026-08-04** — see the fourth-site
paragraph above), #5409.

### Ruling 2026-07-29 — DEFERRED, not declined · **superseded 2026-08-01, kept as the record**

Put to the user with the trade stated and deferred **by decision, not by neglect**. Three reasons,
recorded so this is not re-litigated from the defect list alone — and reason 1 turned out to be
measurably smaller than it assumed, which is why the reasons are kept rather than deleted:

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

### Ruling 2026-08-01 — **BUILT**, on the discharged prerequisite

The user directed the consolidation program to completion; that is the fresh decision this document
requires, and the delta table was produced **first**, as the deferral demanded. Two of its
measurements bear directly on the reasoning above and are recorded here rather than left to be
re-derived:

- **Reason 1 was narrower than it read.** *"A caller scripting `rc == 2 ⇒ usage error` is relying
  on the current shape, including the `runtime-check` outlier"* — measured, no rc changed anywhere
  in the 57-site corpus on a healthy install, and `runtime-check` was never reachable from this
  build at all. The blast radius that justified deferring was **message text on 6 call sites**. The
  deferral was still not wrong: nothing in the section *established* that before the table existed,
  which is precisely what reason 2 said.
- **Reason 2 was load-bearing, and it paid.** The table is what surfaced the compound `next-dl`
  guard. A build off the four-row section would have swapped it wholesale, deleted the mutual
  exclusion, and passed every test in the repo.

What the stage did **not** buy is stated in the status table and above: the exit-code divergence
survives by design. A future reader tempted to write "Stage C unified the exit codes" should read
finding 2 first.

---

## Stage D — one library · DROPPED (decided 2026-08-01)

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
  has **no equivalent ROW-COUNT refusal**: since card#6594 it refuses an unreadable page-1
  *envelope* at rc 1, but zero rows in a well-formed envelope is still rc 0 and `[]`, and that
  divergence is deliberate — the *"two implementations … disagreed on the safety branch — CLOSED"*
  entry below states why a read verb must not adopt the mover's predicate. Dropping the mover's
  refusal would turn a lost-membership token into `0 moved` and **exit 0**.

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

### Ruling 2026-08-01 — **DROPPED.** The recommendation is now a decision.

The program was directed to completion, which required D to be *decided* rather than left standing as
a recommendation — a recommendation is a thing a later session re-opens from the defect list.

**Dropped on the reasoning already recorded above, unchanged.** Nothing new was measured to reach this;
the four arguments were already sufficient and are restated here only as the decision's basis:
the trade buys **one deduplicated line** and sells a hard lib dependency plus a co-vendoring obligation
onto a network-free, git-only tool; the retry is a **restructure, not a knob**; a knob honored only by
`kb_api` leaves two other fetchers unprotected; and dropping promote's 0-visible-cards refusal would
turn a lost-membership token into `0 moved` and **exit 0** — trading a live guard for tidiness.

**What this closes and what it does not.** It closes D as a *stage*. It does **not** claim the
duplication is gone: `promote-released-cards` still carries its `require_value` and `host_ok` mirrors
by design, and `tests/kb-host-guard-selftest.sh` still pins the host-guard mirror row-by-row against
the lib and **exits 1 if it cannot extract `host_ok`** — so a rename or removal of that mirror fails
the build rather than silently reducing coverage. The mirror is *guarded duplication*, which is the
outcome this stage chose over consolidation.

**If it is ever revived,** the § Stage D revival checklist above still applies in full (the literal
`source "$KB_LIB"`, the INSTALL.md §6b / ADOPTION.md group split, the UPGRADE.md entry, and the
framework's `templates/release/` mirror).

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
  repo, which drives three live boards. Stage C got the win without the rewrite.
- **A "keep in sync" comment sweep** — the premise evaporated. The genuine instances nearly all
  describe the standalone mirrors Stage D would remove at the source, and the proposed
  guard was a decoration by construction: it would have matched the dispatch sites Stage C changed
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

## Post-program dispositions

Duplications found *after* the program closed, in the shapes it named. Parked here rather than on a
tracker: this document already owns the reasoning for every consolidation in this repo, and a
finding with no owner is abandoned, not filed.

- **`board-snapshot`'s inline roster parser vs `kb_board_roster`** (card #5981) — the lib now owns the
  parser and `board-stats` is its second caller, but `board-snapshot` still carries the original
  inline copy, so a parser fix must be carried across by hand. Migrating it is **decision-gated, not
  a cleanup**: the fallbacks differ (two hardcoded board names for back-compat vs discovery of every
  `~/.kanban-*-board.env`), so adopting the primitive changes what a roster-less box renders at
  SessionStart — and the two emit different first fields (`<name>` vs `<envfile>`), so the call site
  changes too. Recorded at the function; this is the owning record.
- **The custom-field CREATE call, in two implementations** (card #6525) — `kbcard`'s
  `_kbc_field_create_call` is the `field create` verb's one POST site (it was shared with `field
  retype` until that verb became a thin call on the server's atomic conversion route, which creates
  nothing), and `dl-a1-register-field` carries a second, inline
  `kb_api_status POST /boards/<id>/custom_fields.json` with its own body literal. Recorded at the
  moment the second copy was *created*, per the ground rules — but migrating it is **decision-gated,
  not a cleanup**, and the reason is the shape rule this document already states (*mechanism belongs
  in the primitive; policy belongs at the caller*): the two disagree on **what a non-2xx means**.
  `dl-a1-register-field` is idempotent by contract — its headline re-run guarantee is that a
  **409/422 is success** (already registered) — and it reads the exact status through `kb_api_status`
  to get that; `_kbc_field_create_call` reports rc only, treats an id-less 2xx as an **unverified
  write**, and its caller `_kbc_field_create` refuses a duplicate key at rc 2 *before* the POST, off
  a board field-index read the one-shot bin does not perform. Adopting the primitive would therefore
  either change the bin's idempotency contract or push a status-exposing variant into the primitive
  for its single second caller — extraction belongs at the second *real* caller, and this is a second
  caller with a different invariant. What must not happen is the **wire contract** drifting between
  them (the flat `{key,label,type[,options]}` body and the server's `[{value,label}]` option shape,
  both read out of `CustomFieldsController` / `CustomField::TYPES` rather than recalled): that is the
  part a fix has to land in both, and this bullet is the record that there are two.
- **The tolerant response parse, in the fail-soft bins** (card#6426) — `kb_parse_resp` now owns
  "apply a filter to a response body, yielding nothing rather than dying when the body is not
  JSON", and the bins that run under `set -e` were migrated onto it (that migration is what the
  card shipped). The three fail-soft bins were **deliberately left carrying their own inline
  guards** — `board-card-start`'s `2>/dev/null` card reads, `board-snapshot`'s `fromjson? // null`
  stage-name map, and `board-stats`'s `_bs_stage_map` and changelog-page parse — and the reason is
  ground rule 5, not oversight: none of them runs under `set -e`, so a jq fault there is already
  non-fatal, and each one's POLICY on an unreadable body is a **different non-empty default**
  (`board-snapshot` degrades to `stage <id>` labels, `board-stats` to `_BS_EMPTY_MAP` or a named
  `err` on the board's own ⚠ line, `board-card-start` to a silent `exit 0`). Adopting the
  primitive there is mechanical, but it does not by itself remove a copy: each call site would
  still need its own `[[ -n … ]] || default`, so what looks like one owner replacing four is one
  owner plus four unchanged policies. **What makes it worth doing anyway, when someone decides
  to:** those inline guards have already drifted once in the way that matters —
  `dl-a1-register-field`'s copy suppressed jq's *message* with `2>/dev/null` while leaving its
  *status* live, so under `set -e` it still killed the run, silently, which is the exact failure
  the suppression was written to prevent. A guard that is four near-copies agreeing by habit is
  one edit away from that again. Decision-gated on the same axis as the roster parser above: it
  changes nothing a caller can see **only if** each default is preserved exactly, and that is a
  per-site judgement rather than a sweep.
- **`fetch_board_cards`'s internal body parses — and its co-vendored MIRROR's** (card#6426) — the
  lib's own paginator reads `meta.last_page`, `meta.total`, `.data`, and the page/dedup lengths
  straight off each response with `jq … 2>/dev/null`, i.e. the primitive's shape written inline in
  the file that now defines the primitive. Derived rather than recalled — **seven** `jq` invocations
  inside `fetch_board_cards`, **all seven** carrying `2>/dev/null`. Re-derive rather than trust that
  figure — the non-comment `jq ` lines of the function body, anchored on the function name so the
  recipe survives every edit around it:

      awk '/^fetch_board_cards\(\)/{f=1} f&&/jq /&&$0!~/^ *#/{print} f&&/^}/{exit}' bin/_kb-board-lib.sh

  This entry said "five" when it was first written, and that number had never been derived from the
  file. Left alone for a reason worth recording: `2>/dev/null` there suppresses the message but not
  the status, and whether that status is fatal depends on **how the caller invoked the function**.

  **The mechanism this entry first recorded was measurably wrong, and the correction matters more
  than the conclusion it leaves standing.** It said bash suppresses `errexit` inside a command
  substitution *that is part of an `||` or `if` list*, "which is how every caller in this repo calls
  it". Both halves fail. Re-measured on **bash 5.2.21**, driving the real function against a stub
  answering `200` with `<html>502</html>`, five shapes:

  | caller shape | outcome |
  | --- | --- |
  | `set -e`, substitution in **no** `\|\|`/`if` list | survives — rc 0, `[]` |
  | `set -e`, substitution in an `\|\|` list | survives — rc 0, `[]` |
  | `set -e`, **direct** call (no substitution) | **dies at rc 5** |
  | `set -e` **+ `shopt -s inherit_errexit`**, substitution | **dies at rc 5** |
  | **no `-e`**, direct call | survives — rc 0, `[]` |

  So the `||`/`if` conjunct does no work here: **no command-substitution subshell inherits `errexit`
  without `inherit_errexit`** (which no file in this repo sets — grep-verifiable), and that, not the
  list shape, is what keeps jq's rc out of the caller's `set -e`. The `||`/`if` shape governs
  something else entirely — the function's OWN explicit `return 1..4`, which every caller reads
  deliberately and which is not what this entry is about.

  **And "every caller in this repo" was false.** Derived, not recalled — **seven call sites across
  six bins**: `cmd_list` and `_kbc_archive_decision` (`bin/kbcard`), `board_dl_max` (`bin/next-dl`),
  `bin/dl-a0-backfill-triaged`, `board_report` (`bin/board-snapshot`), `_bs_one_board`
  (`bin/board-stats`) and `bin/board-card-start`. Two are not in an `||`/`if` list at all:
  `board-snapshot`'s is a bare `data="$(…)"; rc=$?`, and **`board-stats`' is not a substitution
  either** — a direct call redirected to a file.

  **Both are nonetheless safe, by a THIRD route the entry never named:** `board-snapshot`,
  `board-stats` and `board-card-start` each run `set -uo pipefail` with **no `-e` at all** (one
  `set` line per file, verified). For `board-stats` that is the *only* route available, because the
  substitution boundary is not there to protect it.

  **The conclusion survives — the rc reaches no caller's `set -e` today — but by the substitution
  and the absent `-e`, never by the list shape.** Migrating the parses is therefore still a
  hardening rather than a cleanup, against a future caller that invokes this function directly (or
  a file that sets `inherit_errexit`) — and the test to write is **NOT** one that "pins the caller
  shape": that would assert a property which is neither true today nor protective. Pin the
  BOUNDARY instead — a direct `fetch_board_cards` call under `set -euo pipefail`, against a 2xx
  body that is not JSON, must not exit 5. That test is **red today** (it exits 5), which is exactly
  what makes it a test of the migration rather than of the callers' habits.

  **The population predicate that found this one — "bins that source the lib" — structurally
  excludes the mirror, and the mirror is the bigger half.** `bin/promote-released-cards` is the
  standalone that must never source the lib (the lib header says so, and `fetch_whole_board`'s own
  comment names itself the deliberate co-vendored port of `fetch_board_cards`). It carries the
  **same shape again, seven more times** — the same recipe with `fetch_whole_board` as the anchor —
  of which only the `meta.last_page` and `meta.total` reads
  carry `2>/dev/null`, so **five parse a response body raw**, under `set -euo pipefail`, in a tool
  that PATCHes cards. (The review that surfaced this said "6 sites, two without `2>/dev/null`"; the
  derived figures are seven and five — the accumulator `jq -c -s 'add'` was not in the reviewer's
  list.) Any future audit of this shape whose predicate is lib-sourcing will miss all seven; the
  predicate has to be "reads a kanban response body", which is a grep of the files, not of the
  source graph.

  **The two implementations of this one behaviour disagreed on the safety branch — CLOSED.** The
  mirror refuses a page-1 read that returns zero cards — `fetch_whole_board` `die`s with *"board N
  returned 0 visible cards — the token's user is likely not a member of board N … Refusing."* — and
  the lib had no such branch at all. Closed by **card#6594**, which landed second and therefore
  deleted the divergence rather than re-syncing a second copy of it: both implementations now fail
  closed on an unreadable page 1. The predicates are deliberately NOT identical — a mover can treat
  zero cards as never a working state, a read verb cannot, because `kbcard list` on a genuinely
  empty board must still succeed — and the reason lives with the code that has to honour it, in
  `fetch_board_cards`' own parse-site comment. Do not converge them by copying the mirror's
  predicate into the lib; that reintroduces a refusal on a legitimate board.

  **Per-consumer exposure on page 1 is now settled by the rc-1 arm rather than predicted per
  consumer.** Measured on the shipped bins against a `200` carrying `<html>502</html>`: `kbcard list`
  and `dl-a0-backfill-triaged` abort, `board-snapshot` prints `(board read failed — fetch rc=1)`,
  `board-stats` marks the stock section unavailable, `board-card-start` skips the move, `next-dl`
  warned and kept its documented rc-1 fail-soft, so it announced the dropped DL floor rather than
  refusing — **that residual was card#6631** (board 12), and it is now CLOSED at the caller: on the
  operator's ruling (*"I don't want next-dl to offer offline allocation as a contract"*) `next-dl`
  refuses on rc 1 as it already did on rc 2/3/4, so no non-zero paginator rc fail-softs there any
  more. It was closed WITHOUT separating rc 1's three causes — the expensive option,
  since a new paginator rc reaches the six consumer bins and eight invocations this registry test
  derives, plus the test itself: the ruling removed the requirement that separation existed to
  serve, because refusing all three causes is no longer a cost to avoid. What survives
  is a stated bound, not a residual with a card, and the line it draws is **resolve-failure vs
  fetch-failure, not configured vs unconfigured**: a `resolve_board_cfg` failure (no request issued
  at all) and a complete, successful read of a board carrying no `dl_number` stamp both still mint
  from the local header scan, and a named, reachable board reaches either. `bin/next-dl`'s header
  and its `board_dl_max` exit-code note own that enumeration; this doc does not restate it.
  **One measured path recorded here rather than fixed, because fixing it changes what the tool
  accepts:** a token file that is a DIRECTORY passes `kb_resolve_env`'s `-r` test, so the config
  resolves, `cat` fails, and the board is read with an EMPTY bearer. The `cat` status is not fatal
  for the reason this document already measures above — `board_dl_max` is called inside a command
  substitution, and no such subshell inherits `errexit` without `inherit_errexit`. The outcome is then the server's: measured against the test stub, a `401` reaches
  the rc-1 refusal and a readable `2xx` mints. It sits behind the same acceptance-change gate as
  `cmd_comments`' `false` instance recorded further down this document, not behind card#6631's
  ruling.
  `kbcard archive` substitutes `[]` for the twin census. That last one was recorded here as safe *by contract rather than by
  measurement*; it has since been measured — the same card with `surviving_cards: []` returns
  `blocked … no surviving twin — archive withheld (fail-closed)` where the populated census returns
  `ok`, so an empty census can only withhold more archives, never permit one. Two sources and now a
  run.

  **⏳ OPEN (card#6630) — THE SAME SHAPE ON LATER PAGES. 3 instances, 2 fixed here, 1 LIVE.**
  This entry previously said *2 instances* and was CLOSED on that count. The count was asserted,
  never derived, and it was wrong: there is a third paginator in this tree carrying the same shape,
  and it is still live. The card stays OPEN as the ONE class item for all three (canon #18 — the
  audit finds instances, the class gets the item); the two fixed instances are recorded below as
  members that are done, not as the whole class.

  **The denominator, derived rather than recalled** (canon #19 — the method, so a later pass can
  re-run it): the population is *every loop in this tree that issues repeated API requests to
  accumulate one result set*. Derived by taking every HTTP-issuing call site (`curl`, `kb_api`,
  `promote-released-cards`'s `api`, `gh api`, and the Python subprocess calls) and keeping those
  lexically inside a `while`/`for` whose request URL carries a page/cursor parameter the loop
  itself advances. That yields **4**, and the discriminating control is that it independently
  re-finds the two instances this change fixes:

  | paging loop | key | instance of this shape? |
  | --- | --- | --- |
  | `bin/_kb-board-lib.sh` `fetch_board_cards` | `page=N` | **yes — FIXED here** |
  | `bin/promote-released-cards` `fetch_whole_board` | `page=N` | **yes — FIXED here** |
  | `bin/board-stats` `_bs_window_rows` | `before=<cursor>` | **yes — OPEN, see below** |
  | `bin/_dependabot-reconcile.py` `gh_alerts` | `gh api --paginate` | **no** — paging is delegated to `gh`, and a body that is not a JSON array raises `InstrumentError` rather than reading as an exhausted population. Disposed by checking, not by absence of symptoms. |

  `bin/install-board-hooks`'s `_ibh_symlink_probe` uses a `while :`/`break` block and issues no
  request at all; it is not in this population.

  Until this change `fetch_board_cards` and `fetch_whole_board`
  read a page > 1 through `.data // []`, so an unreadable later body was taken for a short page and
  ended the scan. The `meta.total` census is what covers it, and only
  where the server declares `meta.total` — which is the whole exposure, because both copies default
  an absent `meta.total` to UNKNOWN and then skip the census. Measured at page 1 = 200 rows with
  page 2 answering `200` + `<html>502</html>`:

  | copy | `meta.total` declared | outcome |
  | --- | --- | --- |
  | `fetch_board_cards` | yes | **rc 4** + `INCOMPLETE` on stderr — ~~covered~~ **NOT covered; see the correction below** — rc 4 EMITS its partial array and the rendering consumers rendered it |
  | `fetch_board_cards` | **no** | **rc 0, 200 cards, EMPTY STDERR** — a silent truncated read |
  | `fetch_whole_board` | yes | **rc 2** (`die`, refuses to promote) — covered |
  | `fetch_whole_board` | **no** | **rc 0, 200 cards, promotes** — the only tell is a raw `jq: parse error` on stderr, i.e. jq's voice, not the tool's |

  The mirror's is the worse half: it is a tool that PATCHes cards, and it proceeds. Neither looks
  reachable against this repo's kanban, whose `LengthAwarePaginator` carried `meta.total` on every
  probe made for this entry — a populated page, an empty result, and a past-the-end page — which is
  what makes these latent rather than live, and is the same reasoning (and the same unproven
  "always") that card #4623 recorded for the `last_page` default. A vendoring consumer pointed at
  a different server is where the assumption is not even that strong. **The fix was one predicate in
  each of the two CARD paginators** — the envelope test applied to every page, returning the
  already-documented **rc 2**
  in the lib and `die`ing in the mirror — taken under card#6630 (ONE class item carrying
  every instance, canon #18) on the operator's ruling, which is the gate card#6594's
  page-1 scoping had left in the way. **The two page-1 predicates were NOT converged**, and must
  not be: the mirror still dies on zero CARDS and the lib still admits an empty board (see the
  page-1 divergence above).

  **⚠ THE MIRROR'S PAGE-1 ACCEPTANCE MOVED. That is a behaviour change, not a change of voice, and
  this entry previously said the opposite.** The retracted claim was that for the two shapes
  `.data // []` passed through as a non-array (`{"data":{"id":9}}`, `{"data":"str"}`) the tool
  already died *"in jq's voice at jq's status"*, so *"the verdict was refuse either way"*. Measured
  against `git show HEAD:bin/promote-released-cards`, lifting the real `fetch_whole_board` onto the
  selftest's page-serving stub: **it returned rc 0 with EMPTY stdout on both shapes.** The
  accumulator's `jq -s 'add'` did fault (status **5**, `array ([]) and object ({"id":9}) cannot be
  added`) — and that fault is **non-fatal**, because `errexit` is not inherited by a
  command-substitution subshell and no file in this repo sets `inherit_errexit`; the same mechanism
  this document already records for `board_dl_max` above. The caller `CARDS="$(fetch_whole_board)"`
  therefore took an empty card list at rc 0 and continued: `PLAN`, `MATCHED_DLS` and `MATCHED_CARDS`
  all evaluated cleanly over the empty input, and the run aborted at the **fourth** assignment,
  `MISSING="$(jq -n --argjson md "$MATCHED_DLS" …)"`, with `jq: invalid JSON text passed to
  --argjson` — a different jq, at a different site, at status **2**, and a message about an internal
  argument rather than about the board.
  **So the page-1 disposition for those two shapes moved from *rc 0 out of the fetch, proceed with
  an empty list* to *die at the fetch*.** What is true of the *process* exit — 2 either way, and no
  card PATCHed either way, because both aborts land before the move loop — is what made the wrong
  claim comfortable; it is not what the tool accepted. The page-1 PREDICATE (zero CARDS) did not
  move, and no other page-1 shape changed disposition. That is a measurement, not an inference —
  the same lift run against `HEAD` and against the worktree over six page-1 bodies:

  | page-1 body | pre-fix | post-fix |
  | --- | --- | --- |
  | `{"error":"upstream connect error"}` | rc 2, zero-cards die | rc 2, zero-cards die |
  | `{"data":null}` | rc 2, zero-cards die | rc 2, zero-cards die |
  | `<html>502</html>` | rc 2, zero-cards die (behind a raw `jq: parse error`) | unchanged, same raw `jq: parse error` |
  | `{"data":[]}` | rc 2, zero-cards die | rc 2, zero-cards die |
  | `{"data":{"id":9}}` | **rc 0, EMPTY stdout** | **rc 2, zero-cards die** |
  | `{"data":"str"}` | **rc 0, EMPTY stdout** | **rc 2, zero-cards die** |

  Two rows moved; four did not. (The `<html>` row also records a pre-existing wart neither this
  change nor its predecessor touched: the mirror's extraction carries no `2>/dev/null`, so an
  unparseable page 1 still puts jq's parse error on stderr ahead of the tool's own refusal, where
  the lib's identical parse suppresses it. Not fixed here — it is a stderr-content change on a
  refusal path — and filed on this entry so it is not re-found as new.)

  **The acceptance the page-1 message now carries, recorded rather than fixed (MINOR 6).** With the
  new extraction, `data=''` means *unreadable envelope* and `data='[]'` means *genuinely zero rows*
  — two states the code can now tell apart and then deliberately collapses again at
  `bin/promote-released-cards`'s `data='[]'` page-1 arm, so both land on the die that names board
  membership as the likely cause. That message pre-dates this change and is already wrong for
  `{"error":…}` and `{"data":null}`; **this change adds exactly two more shapes to it**
  (`{"data":{"id":9}}`, `{"data":"str"}`) — the two rows that moved in the table above, which is
  where that count comes from. Not fixed here on purpose: rewording an operator-facing refusal is
  a change to how errors are reported, which is ask-gated, and distinguishing the two causes is a
  message decision the operator should make rather than one this fix should smuggle in. It is
  recorded as an open member of this entry so it has an owner and a queue position (canon #18).

  **One row of the table above was wrong about the consequence, and the correction is the reason
  the "latent" framing did not hold:** `meta.total`-declared was recorded as *covered*, but rc 4
  EMITS its partial array, and the two consumers that render on 3|4 rendered it. Re-measured
  through the shipped bins on that same fixture, `board-snapshot` printed a board line derived from
  the truncated read (`• Board 5 (kanban-board): in-flight 0`) with `INCOMPLETE` on a stderr its
  SessionStart display does not show. *Covered* was true of the refuse-policy callers only; for the
  rendering ones the census turned a silent truncation into a **quietly rendered** one. Both are
  now rc 2, refused before the census.

  **THE THIRD INSTANCE — `bin/board-stats` `_bs_window_rows`, LIVE, and the reason this entry is
  not closed.** The changelog window is read by paging BACKWARD on a `before=<cursor>` id until the
  rows precede the cutoff, and the loop's end-of-data signal is a **short page**: `_BS_PAGE_JQ`
  opens with `(.data // []) as $d`, so a `2xx` carrying no `.data` yields `n: 0`, `n < _BS_CL_LIMIT`
  reads as *the log is exhausted*, and the loop `break`s with `truncated=false` and `err=""`. That
  is the same shape as the two fixed above, on the same `KB_API`, the same host, reachable by the
  same proxy/gateway error body. **Measured against the real function** (the shipped
  `_bs_window_rows`, sourced from `bin/board-stats`, page 1 = 200 rows, `_BS_CL_LIMIT` = 200):

  | page-2 body | `_bs_window_rows` result |
  | --- | --- |
  | `{"error":"upstream connect error"}` | `pages: 2, truncated: false, error: null` — **silent**, 200 rows |
  | `{"data":null}` | `pages: 2, truncated: false, error: null` — **silent**, 200 rows |
  | `{"data":"str"}` / `{"data":{"id":9}}` / `[{"error":…}]` | `error: "changelog page 2 is not the shape this tool reads"` — caught |
  | `<html>502</html>` | same — caught |

  So the live half is narrower than a `.data`-shape test would suggest, and stating it precisely
  matters: of the shapes measured, the silent set is a JSON **object** whose `.data` is **absent,
  `null` or `false`** — the three `//` substitutes for. The mechanism that catches the rest is
  `$d[-1]`: `// []` yields the substitute only for `null`/`false`, so any other non-array `.data`
  reaches `$d[-1]` as itself and faults the page jq, which the `[[ -n "$page" ]]` guard reports as
  a wrong-shape error. Measured on that boundary: `{"data":false}` is **silent**, `{"data":{}}` is
  **caught**. An absent/null `.data` is exactly the shape a
  proxy or gateway error document takes, which is what keeps this reachable rather than academic.
  On the silent path `_bs_one_board` sets `flow_ok=true` with no `fails+=` entry, so the report
  renders flow counts off a truncated window with **no `⚠` line and no `(WINDOW TRUNCATED)`
  marker** — which falsifies `bin/board-stats`'s own header claim that *"a number that is a floor
  rather than a total (a capped card read, a truncated changelog window) says so where it is
  printed."* **That header line is a live false claim and is filed here rather than edited**, because
  correcting it either way pre-judges the `err`/`truncated` policy decision this instance needs.
  **Deliberately NOT fixed under card#6630's current scope:** unlike the two card paginators, this
  loop's failure policy is a real fork — `_bs_window_rows` has three stop conditions and two of them
  already set `truncated` while emitting rows, so "refuse" is not simply the existing rc, and
  `board-stats` is a fail-soft report whose contract is that one bad board never kills the run.
  That is a policy decision, not a predicate edit, and it is the open work on this card.
- **The eight rows the card#6426 derivation left undisposed** (card#6426) — the instrument that
  enumerated "a raw `jq` over a value derived from a kanban response" ended its run printing `?
  (unresolved — dispose in prose, never silently): 8`, and the change shipped without disposing one
  of them. A clean result over a population with a silent remainder reports where the searcher
  stopped, so the remainder is disposed here. Each row was re-decided by reading the parse's own
  **input expression**, not by trusting the instrument's classifier. Two verdicts are used: **`R` —
  response-derived, but downstream of a parse that already owns the risk** (the raw `jq` cannot meet
  a body this tool has not already refused or made safe), and **`L` — locally built input, never a
  response body at all**.

  **Six are `R`:**
  - `bin/dl-a0-backfill-triaged`, four rows — the two `$t` reads in the dry-run preview loop and the
    two in the apply loop. All four read `$t`, an element of `targets_json[]`, and every member of
    that array is a `#TARGET\t<@json>` row emitted by the single `$targets_jq` filter. That filter
    **constructs** the object it emits (`{id, newtags, idtags}`), so `$t` is jq's own `@json` output
    rather than anything the server sent. The response risk sits upstream, in that one filter over
    `$cards_json`, and the `fetch_board_cards` call already guards it on rc.
  - `kb_by_ref_hit` (`bin/_kb-board-lib.sh`) — its input genuinely *is* a raw response body, but the
    `jq -e … >/dev/null 2>&1` **is the predicate**: its status is the function's return value,
    consumed as a boolean, message suppressed, and any jq fault reads as a non-hit (fail-closed).
    There is no status to leak into `set -e` and no value to misread.
  - `_kbc_field_enumerate` (`bin/kbcard`) — reads `$fields`, which comes only from
    `_kbc_fetch_fields`, and that read now refuses a body no custom-field set can be read out of.
    Stronger than that: it is reached only from `_kbc_field_set_options`' "field not defined" arm,
    i.e. only after that function already `map`ped the same value successfully, so by construction it
    is an array.

  **Two are `L`:**
  - `bin/board-stats`' `failures_json` build — parses `printf '%s\n' "${fails[@]}"`, the shell array
    the enclosing function appends its own diagnostics to.
  - `swimlane_id`'s "defined swimlanes" enumeration (`bin/kbcard`) — parses `_kbc_swimlane_map`'s
    output, which that function builds with `jq -c` from this board's `KB_SWIMLANE_*` env variables.

  **The sibling audit that closed the write-path shape test, recorded so it is not re-derived**
  (card#6426) — the harm the tag-read shape test exists to prevent is *a read whose own result
  becomes the body of a write that REPLACES what it read*. Every write in the toolkit was checked
  against that predicate, not just the greppable ones. Exactly one site matches: `_kbc_patch_tags`.
  Disposed explicitly, so none of these is silence: `field set-options` PATCHes a
  replace-wholesale `options` array but builds it from the caller's `--options`, so an unreadable
  read there cannot yield a write built from nothing; `archive` / `delete` send constant bodies and
  the read feeds only a fail-closed gate; `move` / `patch`'s other fields come from flags;
  `dl-a0-backfill-triaged` *is* a tag read-modify-write, but a card whose tag list cannot be read
  fails its `id:*-pr-*` selector and never becomes a target, so its write only ever fires on a tag
  list it demonstrably read; `dl-a1-register-field` and `board-card-start` send constants. **One
  instance, not a class** — so no class item, per the filing rule.

  **A second mechanism inside that one instance, found by A/B-ing the accepted set rather than by
  reading** (card#6426, fix round 2). Testing `.data` for an object closed the WRAPPER; the value
  actually re-sent is `.data.tags`, and a **`tags` that is a JSON object** passed that test and then
  did **not** fault, because **jq's `map` iterates an object's VALUES**. Measured on the bin before
  the container test: `{"data":{"id":5,"tags":{"0":"keep-me"}}}` with `--type fr` issued
  `PATCH {"tags":["keep-me","type:fr"]}` at **rc 0** — the object degraded into a plausible list,
  the merge succeeded, and every tag the card actually carried was replaced. It takes a `map`-first
  flag (`--type`); `--triaged` alone always faulted (`object + array`), which is why the first round
  read as diagnostic-only. Closed by testing the CONTAINER type of `tags` in the same filter, at the
  same refusal and the same rc. **This narrowed the accepted set by 8 rows**, re-derived in round 3
  on a 184-row A/B matrix (23 body shapes x 8 flag combinations; see the `[Unreleased]` CHANGELOG
  entry for the denominator), every one of them the object-valued-`tags` class. **The earlier
  decomposition of those 8 — "6 rows (3 bodies x 2 flag combinations) … and 2 where an empty object
  …" — was wrong and is corrected here:** the 8 are **2 bodies x 4 `--type` combinations**
  (`--type` in its tag-alias and native-id forms, each with and without `--triaged`) — 4 rows where
  `{"0":"keep-me"}`'s values were silently re-published as the card's whole tag list, and 4 where
  `{}` produced a list built from a container the tool could not read as one (the native-id form
  PATCHing `{"tags":[]}`, i.e. every tag gone with nothing put back). A third body,
  `{"a":1}`, is NOT in the set: `startswith` faults on a number, so it refused at rc 2 both before
  and after. `dl-a0-backfill-triaged` — the other tag read-modify-write this
  entry's write enumeration above already names — was re-checked against this specific mechanism: `any(…)` also iterates an
  object's values, so such a card can become a target, but `$tags + ["triaged"]` / `- ["triaged"]`
  then faults on an object and no write is issued. Fail-safe there; still one instance, still no
  class item.

  **A NINTH row the instrument could not print, and the reason is a defect in the PREDICATE'S FORM**
  (card#6426) — `_kbc_field_list` (`bin/kbcard`) pipes `_kbc_fetch_fields` straight into a bare
  `jq "map(…)"`. That is a genuine unguarded response parse — measured: `field list` against a `200`
  carrying `{"data":null}` exits **5** (*Cannot iterate over null*) — but the derivation's `R`
  predicate matches on the PRODUCING TOKEN (`kb_api|fetch_board_cards|curl`) and the producer here
  is a **local reader function**, so no pass could see it. The lesson is not "add
  `_kbc_fetch_fields` to the list": a predicate that enumerates producers by NAME is blind to every
  producer it does not happen to name, and the next reader wrapper re-mints the blind spot. The
  criterion was amended instead — guardedness, not depth, and *a local reader function is
  transparent, not a boundary*.

  **The sibling audit that amendment demands, run and disposed.** Derivation, runnable rather than
  recalled — over the lib-sourcing bins plus the lib, take every function whose body names
  `kb_api` / `kb_api_status` / `fetch_board_cards` / `curl` (**26** at the time of writing — re-derive,
  never quote), then keep only those
  whose **stdout is a response-derived value that some OTHER site then parses**:

      for f in $(grep -l '_kb-board-lib.sh' bin/*) bin/_kb-board-lib.sh; do
        awk -v F="$f" '/^[_a-zA-Z][_a-zA-Z0-9]*\(\) *\{/ {n=$1; sub(/\(\).*/,"",n); i=1; b=""; next}
                       i && /^\}/ {if (b ~ /kb_api|fetch_board_cards|curl /) print F"\t"n; i=0; next}
                       i {b=b"\n"$0}' "$f"; done | sort -u

  **Control that proves the derivation discriminates** (canon #9): renaming the `kb_api` token
  inside exactly one function (`cmd_link`) drops **exactly** that row, 26 -> 25; the file was
  restored by byte snapshot + `cmp`, never `git checkout --`. Note the candidate scan reaches
  `bin/promote-released-cards` even though it must never `source` the lib — `grep -l` matches the
  lib's name in its own header comment — which is the one thing the lib-sourcing predicate above
  gets wrong, closed here by accident rather than by design. Do not rely on that.

  **Exactly one member: `_kbc_fetch_fields`.** The other 25 are disposed, not silent — the `cmd_*`
  verbs' stdout IS the tool's output and reaches no further jq; `kb_api` / `kb_api_status` /
  `fetch_board_cards` / `fetch_whole_board` are the named producers the predicate already sees;
  `_kbc_patch_tags` and `_bs_window_rows` emit a `jq -n`-BUILT value (`L`); `_kbc_archive_decision`
  emits the python shim's tab-separated verdict, read by `IFS=$'\t' read`, never by jq;
  `resolve_task` emits a `kb_is_uint`-validated scalar; `by_ref_has` is a boolean-by-rc predicate;
  `_bcs_patch` and `delete_throwaway` are writers that discard the body; `adopt-to-dl`'s `main`,
  `board_report` and `_bs_one_board` are top-level. The two functions pass 2 expected to be out
  ARE out, for the reason it gave: `_kbc_swimlane_map` and `_kbc_board_repo` read local env/config
  and never touch a response.

  **Disposition of `_kbc_field_list` — REPORTED, deliberately NOT migrated.** The fix would have to
  tighten `_kbc_fetch_fields` to require `.data` to be an ARRAY, which moves `field list` on
  `{"data":null}` from jq's rc **5** to this tool's rc **1** refusal. It needs no new exit code, but
  it is a change to what a READ verb accepts and to the status it reports — the ask-first axis
  card#6426 §(b) is already fenced on, and the same axis `show`'s residual wording sits behind. It
  is recorded here as an in-population, unmigrated site with a named blocker, not left as silence.

  **What these dispositions do NOT cover, said plainly:** `R` means the raw `jq` at that row is
  safe, not that its verb is. The read-verb residue is separate and stays filed — a `2xx` whose
  `.data` is valid JSON of the wrong shape still exits at jq's rc 5 in the projections that index it
  (measured: `field list` on `{"data":null}`; `field set-options --field <k>` on `{"data":null}` and
  on `{"data":{"id":9}}`; `show --task 7` on `{"data":"str"}` and `{"data":5}`; `list` on
  `{"data":{"id":9}}`), which is a change to what those verbs **accept** and therefore not this
  card's to make.

  **In-population members no pass of the derivation named, recorded rather than migrated.** The
  first two below are card#6426 fix round 3's; the third arrived with card#6525 and dates itself.
  Round 3's two are raw `jq` reads of a value that IS a response body, and both
  are labelled **`L`** ("locally built input") by the instrument — wrongly, and for the same
  mechanical reason in each: the resolver picks up the wrong variable. It reads the jq invocation's
  *named* arguments rather than the value the filter is actually applied to, so a function whose
  response body arrives as **stdin or a positional** while its `--arg*` bindings are locally built
  resolves as local. That is the same failure mode as the producer-by-NAME predicate above, one
  level down: an instrument that resolves by the wrong term answers about the wrong term.
  - **`bin/board-stats` `_bs_stage_map`** — `printf '%s' "${1:-}" | jq -c -R -s "$_BS_STAGEMAP_JQ"`,
    where `$1` is the raw body of `kb_api GET /boards/<id>/preload.json`. The resolver sees
    `$_BS_STAGEMAP_JQ` (a filter constant) and the `|| printf '%s' "$_BS_EMPTY_MAP"` fallback, both
    local. **NOT migrated, and the blocker is that it is already correct:** the read is fail-soft
    by design — `2>/dev/null || <empty map>` — and its caller compares the result against
    `$_BS_EMPTY_MAP` and appends a named `fails+=(…)` line, so an unusable preload is *reported*,
    not silently rendered. `kb_parse_resp` would buy nothing here; the fallback IS the refusal.
  - **`bin/kbcard` `_kbc_list_project`** — the filter opens on `(. // [])` over **stdin**, and
    stdin is `$cards` from `fetch_board_cards`. The resolver sees `--argjson swmap "$swmap"`
    (`_kbc_swimlane_map`'s locally built board-env map) and resolves the whole call as local.
    **NOT migrated, and deliberately so:** the unguarded read is not here but one level up, in the
    paginator's own inline per-page `jq … 2>/dev/null`. Guarding this site could never have seen
    that — by the time the value reaches it the information is already gone — which is why
    **`card#6594` fixed it at the paginator, at page 1, at the existing rc 1**, and `list` now
    aborts instead of printing a `[]` it could not read. Fixing it here would have been #2's
    symptom patch. This site stays unmigrated: `cmd_list` aborts on every non-zero paginator
    rc, so what reaches it is real cards or a genuinely empty board. The one exception this
    bullet used to name — the later-page hole, where a server that omitted `meta.total` let a
    truncated list through at rc 0 — is closed under card#6630 (the card itself stays open for
    its third instance, `bin/board-stats`): an unreadable page > 1 is now rc 2,
    which `cmd_list` already aborts on.
  - **`bin/kbcard` `_kbc_field_populated`** (card#6525, re-derived on every pass that touches
    that branch) — the populated-card census behind `field delete` and `field retype
    --restamp-dl` (the conversion itself needs no census: the server scans the board).
    **Re-running the producer derivation above on this tree returns 31 functions, not the 26
    of the pass that wrote it** — and not the 30 or the 32 two earlier passes of this same
    branch recorded. The count is a **re-derivation, never a quote**; that is what this bullet
    is, and the movement is the point:
    - **Five members the 26-function pass did not have:** `_kbc_field_create_call`,
      `_kbc_field_delete_call`, `_kbc_field_populated`, `_kbc_field_change_type_call` and
      `_kbc_field_restamp_dl`.
    - **`_kbc_field_retype` is NOT one of them, though a pass of this branch disposed of it as
      one.** It was a member while it made the delete/create calls itself; it now calls the two
      field primitives and `kb_parse_resp` and names no producer at all, so the derivation
      stopped returning it — a disposition written against a membership that no longer holds is
      the thing re-derivation exists to catch.
    - **`_kbc_field_change_type_report` was a member for exactly one commit, on a PROSE match.**
      Its body calls no producer; it matched because the predicate is textual and its `000`
      message contained the words *"curl transport failure"*. Rewording that message dropped it
      out. Recorded rather than smoothed over: this is the same instrument artefact the control
      above already names in the other direction (`grep -l` reaching `promote-released-cards`
      through a header comment) — **a predicate that greps a token answers about the token**,
      so a count that moves without a structural change is expected and must be explained, not
      reconciled away.
    Four of the five fall out at the filter — the create call's stdout is a field **id** nothing
    re-parses (its own first projection off the response goes through `kb_parse_resp`), the
    delete call emits no stdout at all and carries its state in its rc, `_kbc_field_restamp_dl`
    likewise emits no stdout and reports through its rc and stderr, and
    `_kbc_field_change_type_call`'s stdout **is** a response-derived value that two other sites
    read — but the status line is split off with shell parameter expansion and **every** read of
    the body, at both sites, goes through `kb_parse_resp`, so it is in-population and guarded,
    with nothing to migrate. The fifth is `_kbc_field_populated`, and it takes
    `_kbc_list_project`'s disposition directly above for `_kbc_list_project`'s reason: its jq
    reads `$cards` from `fetch_board_cards`, not a `kb_api` body, so guarding it here could
    never have seen the information — card#6594 closed that one level up at page 1, and
    card#6630's fix closed the later pages at the same site. It is STRICTER than `cmd_list` where it
    counts: it refuses on **every** non-zero paginator rc (1, 2, 3 and 4, measured in
    `tests/kbcard-field-selftest.sh` against a complete-read positive control), so a partial
    board never reaches its filter — and with the later-page exception closed, the rc it refuses
    on now covers an unreadable page 2 as well.

  **CLASS — a shape test applied downstream of `//` does not see `false`** (card#6426, fix round 3;
  **2 instances, 1 fixed, 1 open**). jq's `//` yields its right-hand side for `false` exactly as it
  does for `null`, so any filter shaped `(.x // <default>) | select(type == …)` hands the container
  test **the default** whenever `.x` is `false` — the test sits on the far side of the very
  substitution it was written to police, and can never fail for that input. The remedy is the same
  at both instances and is named here so whoever rules on the second does not re-derive it: **decide
  absent-or-null explicitly and put the shape test on the near side** —
  `(if has("x") and .x != null then .x else <default> end) | select(type == …)`. It adds no exit
  code and no message class.
  - **Instance 1 — `_kbc_patch_tags` (`bin/kbcard`), FIXED in round 3.** `(.data.tags // []) |
    select(type == "array")` accepted `{"data":{"id":505,"tags":false}}` and, with `--triaged`,
    issued `PATCH {"tags":["triaged"]}` at **rc 0** — measured — destroying every tag on the card.
    It is the third distinct route to one harm — the `.data`-object test (round 1) and the
    `tags`-container test (round 2) each closed one — which is why this is filed as a class and
    not as a third one-off. Now **rc 2 with no PATCH**, in the refusal this verb already had.
    Covered by
    `tests/kbcard-selftest.sh` (`patch --triaged (tags is false)`, `patch --type (tags is false)`),
    watched red.
  - **Instance 2 — `cmd_comments` (`bin/kbcard`), OPEN and ask-gated.** `(.data.comments // []) |
    select(type == "array")` accepts `{"data":{"id":505,"comments":false}}` and prints
    **"card 505 has no comments" at rc 0** — measured — which is exactly the claim the comment two
    lines above it forbids ("printing it here would answer a question this read never reached").
    **NOT fixed: the round-3 grant was the write path only.** Applying the remedy moves a **READ**
    verb from rc 0 to rc 1, i.e. a change to what it accepts — the same ask-first axis as
    `_kbc_field_list` and `show`'s residual wording, and it needs the same ruling. The hazard is
    strictly worse than those, though, and that is why it is recorded as a live wrong-answer rather
    than a diagnostic residue: the other two *fail*, loudly, at a status nobody documented; this one
    **succeeds with a false claim about the board**. Recorded at the site as well as here.

  **Owner and queue position for the open half** — this document, as the preamble states, and
  **blocked on one operator ruling**: the read-verb acceptance axis. That single ruling disposes
  instance 2, `_kbc_field_list` and `show`'s residual wording together; they are three symptoms of
  one gate, not three questions. **A NEW instance of this class arriving before that ruling lands
  is the signal to stop patching instances and take the ruling** — the `//`-shaped filter is a
  two-token idiom any new projection can reproduce, so the count moving is the thing to watch.
  Re-derive it — do not quote the number — with a scan of the SHAPE rather than of the known
  sites, over the whole file text so a filter spanning several lines is still one string:

      for f in bin/*; do [ -f "$f" ] || continue; case "$f" in *.py) continue;; esac
        tr '\n' ' ' < "$f" | grep -oE '//[^|]{0,12}\| *[^|]{0,40}(select\(type|\| *type *\))' \
          | sed "s|^|$f: |"
      done

  **1 hit at the time of writing** — `cmd_comments`, i.e. exactly the open instance; the fixed one
  no longer matches, which is the point. **Control that proves it discriminates** (canon #9):
  reinstating round 2's pre-fix filter in `_kbc_patch_tags` takes the count to **2** and back to
  **1** on restore — restored by byte snapshot + `cmp`, never `git checkout --`.
- **The lib-sourcing-bins list, in three prose copies** (card #5981) — the lib header, `ADOPTION.md`
  and `INSTALL.md` §6b each enumerate the bins that `source` `_kb-board-lib.sh`, while
  `agent-board-toolkit-drift-check` **derives** the real set from the files. That is the restatement
  shape Stage B closed elsewhere by deleting the copy and pointing at the owner; the same fix applies
  here, and the same caution does — the three copies are consumer-facing prose with different
  audiences, so the replacement has to leave each audience an answer, not just a pointer.

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
bin/next-dl kanban --board dev                               # Stage C: still rc 2 + the usage line
bin/next-dl --board ''                                       # Stage C: rc 2, now naming --board
bin/promote-released-cards --dry-run                         # Stage D, if revived: plan unchanged
bin/board-session-close                                      # Stage E: same findings, byte-identical
```

**A pass is evidence only if failure was possible.** Every check added by this program was made to
fail once before it was trusted — and three traps are worth naming, because each produced a green run
that meant nothing: a mutated copy of a bin extracted for testing can die on an unrelated
`$0`-anchored sibling *before* reaching the mutation; an inequality assertion passes trivially
against a mutant that crashed; and an **rc-only** assertion over an arm whose neighbour answers the
**same rc** pins nothing at all — Stage C's `kbcard field` Preserve item was rc-pinned only, and
deleting its guard left the entire suite green, because the `*)` catch-all it then fell through to
also returns 2 (measured; the message assertion that fixes it is in § Stage C). Assert on the
outcome, not on an exit code — and where the rc is shared, the message *is* the outcome.
