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

**Weakest property, stated so it is not over-cited:** that leg compares **names**, not behaviour.
It catches a re-declared helper; it cannot catch a selftest that hand-rolls the same logic inline
under a different name, and it says nothing about whether the prelude's argument order is the right
one. It closes the copy channel that actually minted the bug — not every conceivable one.
⚑ **That file has since grown a SECOND leg over a hand-spelled idiom (card#8548), and its exact
reach is stated in its own header — read there rather than here.** This paragraph describes the
name leg only, and is left standing because that leg's bound is what Stage B's argument turns on;
a doc that restates a guard's whole predicate in its own words is how this class went wrong twice.

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

It now carries a **second** sed-extracted mirror on the same terms: `redact_userinfo`, the
standalone copy of the lib's `kb_redact_url_userinfo` (card#7500). The guards *accept* an
api_base carrying userinfo — that is one of the 6 accept rows above — so every message that
renders a base masks it, and the masking primitive is duplicated for exactly the reason
`host_ok` is. Same discipline, same failure mode if it is renamed: the extraction exits 1.
The *class* — that no shipped tool renders a URL a credential can ride in — is held by
`tests/url-userinfo-render-selftest.sh`, which re-derives the population from the tree rather
than enumerating the ten sites the fix touched.

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

**And "guarded" is now the whole set, not the host guard alone (card#8529).** The `require_value`
mirror — which this section names in the same breath as `host_ok` — was held by its comment and by
nothing else, in **four** standalone tools rather than the one this paragraph implies
(`promote-released-cards`, `release-pr-body`, `release-artifacts-check`, `release-tag-check`), as was
the `require_resolvable` pair the two release movers share. `tests/mirror-pair-parity-selftest.sh`
drives each against the lib's original over one corpus and **derives the copy set from the tree**, so
the fifth standalone to grow one is compared on the day it lands rather than on the day somebody
remembers. `tests/mirror-pair-census.sh` beside it re-derives the whole mirror-candidate population
and prints a per-copy verdict — run it rather than quoting a count from this document, which is a
measurement with a date on it. Choosing guarded duplication is only a defensible ruling while the
guard exists for every mirror the ruling covers; that is what this closes.

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

- **The coord-store token rung, MIRRORED into `agent-board-toolkit-runtime-check`** (card#8376) —
  **DUPLICATED ON PURPOSE, GUARDED, on Stage D's terms.** The duplicate-kanban-token leg has to
  resolve a token file exactly as the tools do, and that resolution lives in `_kb-board-lib.sh`
  (`kb_coord_store_token_file` + `_kb_expand_home` + `_kb_looks_like_pasted_secret`, plus
  `kb_resolve_env`'s host-then-board sourced read). `runtime-check` **cannot source the lib** — it
  JUDGES the lib, and a stale or broken lib must not take the judge down with it — so four
  `_rc_*` mirrors ship inside it. That is the same trade this program settled for
  `promote-released-cards`' `host_ok`, and it is pinned the same way:
  `tests/token-duplication-selftest.sh` extracts all four with `sed` and drives them **row-by-row
  against the lib's originals** over a shared case table, and **exits 1 if it cannot extract one**,
  so a rename reds the build rather than retiring the comparison. **The table's size is not
  written here:** the selftest counts the rows as it runs them and prints them on its own
  `== the parity table this run actually drove ==` line, because the figure that stood in this
  spot (`16 store shapes`) was 15 on the day it was typed and had relayed intact ever since. ⚑
  **The board-env row is pinned against `kb_resolve_env`, not `kb_board_env_get`** — the
  single-file read cannot express a board env whose token path interpolates a variable the HOST
  env sets, so a mirror sourcing the board env alone answered a different path than the tools do,
  and the parity block could not see it (found in review of card#8376). ⛔ **Why a drifted mirror is worse here than
  a disagreement:** it would resolve a DIFFERENT file than the tools do, and the leg would then
  report a duplicate credential that is not there, or miss the one that is — a security finding
  invented or lost, either way against a file nobody is looking at. ⚠ **Do not read this as a
  Stage D revival case.** The alternative is not "source the lib" (forbidden here) but "make the
  lib callable out-of-process", which would give the judge a runtime dependency on the artifact
  under judgement. The mirror is the smaller cost, and this entry exists so the next author meets
  the decision instead of re-deriving it — or worse, "fixing" it by adding a `source`.
- **A DEFINITION duplicated into the test that guards it, and a parity block whose population is
  FUNCTIONS rather than USES** (card#8376, found in review at R2 and again at R3) — **the class,
  not the two instances.** The entry above pins the mirrored *functions*; neither instance below
  was a mirrored function, and that is the whole point.
  **Instance 1 — the needle.** `_rc_digest` defines what "the same credential" MEANS: the file's
  content **as its readers see it**, i.e. with trailing newlines stripped, because every reader
  takes a token through `$(cat …)`. `tests/token-duplication-selftest.sh` re-spelled that rule as
  `printf '%s\n' "$FAKE" | sha256sum` to build the needle its canon #20 absence assertions search
  the tool's whole output for. When R2 corrected the definition in the bin, the copy in the test
  stayed on RAW BYTES — so both absence rows searched for a string the tool **cannot emit on any
  input**, and their positive controls proved only that the search function works. Measured: a
  mutant interpolating the compared digest into the `✗` message leaked it with the suite at rc 0
  and 0 FAIL, while a mutant emitting `$(cat …)` reds — the VALUE half live, the sha256 half dead,
  on the one instrument in this repo that resolves two credentials at once. Fixed by **adopting
  `_rc_digest` out of the bin** (`_adopt_fn`, the same `sed`-extract-or-exit-1 the mirror block
  uses, now one spelling shared by both callers) and deriving the needle from it.
  ⚑ **`_adopt_fn` itself now lives in `tests/_selftest-prelude.sh`, and that is not tidying.**
  Minted local to this one selftest it was one more hand-spelling of a `sed` range this suite
  already carried several of — i.e. this entry's own rule re-minted in the act of closing it.
  (The list of files that carried the others was written out here and went stale within one
  release, twice over; it is derived now, see below.) In the prelude it is one
  definition every selftest already sources.
  ⛔ **AND THE GATE THAT SENTENCE PROMISED DID NOT EXIST — corrected here rather than quietly
  rewritten, because the wrong version is the one a future author would have trusted to have
  closed this** (card#8548). This entry, `docs/CHANGELOG.md` and PR #323's body all said
  `prelude-shadow-selftest.sh` *"reds on the seventh copy"*. That guard compared NAMES: it red
  only on a copy called `_adopt_fn`, and a seventh hand-spelling under any other name left it at
  **rc 0** — which is the exact shape of every residual site listed below, so the doc promised
  the guard covered the drift this very paragraph says remains. It was not hypothetical:
  measured on `dev` at `52125a6`, two further copies had already been minted in
  `promote-source-qualify-selftest.sh`, spelled in `awk` instead of `sed`, with the suite green
  — and PR #323's own out-of-scope note had already named a third spelling, a
  `grep -E '^uint_ok\(\)'`, that no name comparison could see either.
  `prelude-shadow-selftest.sh` now carries a **second leg** whose population is the IDIOM —
  every regex literal anchoring a shell function's definition at column zero, whatever tool
  consumes it and whatever DELIMITER it is written in — dispositioned per file with a count, so a
  new spelling reds wherever and however it is written. ⛔ **The delimiter was the same defect one
  level down, and it shipped:** the first cut of this leg took `/`, the second took `/ ' "`, and
  both were inclusion lists a keystroke wide. Measured on this tree, the three-delimiter version
  was blind to two hand-spelled copies that were live at the time — one with a character class
  between the `^` and the name, one with an alternation group — so the delimiter is now taken from
  the line and the name is sought inside the literal that delimiter opened. Both copies are
  dispositioned. The leg's file population is `tests/_shipped-shell-lib.sh`'s, not a fourth
  hand-copy of `ci.yml`'s `find` (card#6911 owns that derivation), and it asserts
  `_ci_shellcheck_drift` so a narrowed workflow cannot leave it scanning a set CI no longer has.
  ⚑ **What that guard covers is stated in its own header and is not restated
  here or in the changelog**: three surfaces describing one predicate in their own words is how
  this got wrong in the first place.
  ⚑ **NO COUNT OF THE RESIDUAL IS WRITTEN HERE EITHER.** "Five hand-spellings" was true when it
  was typed and was two short within one release — a number in prose is a quoted authority that
  outlives the edit that falsifies it. `prelude-shadow-selftest.sh` derives the live population
  every run and prints it as a denominator; its `EXTRACTORS` list is where each remaining site's
  reason lives, one line per file, and a site that leaves the list reds as a stale disposition.
  **What is left is ONE shape, and the shape it is NOT is recorded here rather than quietly
  dropped, because the wrong version is the one a future author would have acted on.** This entry
  filed a second shape as a design call: `kb-host-guard-selftest.sh` (×2) and
  `kb-positional-guard-selftest.sh` eval the extracted source **through a rename**
  (`${src/host_ok() \{/host_ok_prc() \{}`), so — it said — they need an **alias parameter**
  neither `_fn_src` nor `_adopt_fn` has. **That was false the moment `_fn_src` landed.** Those
  sites apply the rename themselves, in their own `${var/…}` expansion, and need only the
  function's TEXT, which is exactly what `_fn_src` returns; all three are migrated, one line each,
  with the suite byte-identical either side. A reason that outlives the change that falsified it
  leaves copies in place waiting on a primitive that is not missing.
  The shape that WAS left: sites that locate a **one-line** function, whose source has no `^}` line
  for `_fn_src`'s range to stop at. ⛔ **It used to run on to the next function's closing brace and
  hand that function's whole body back at rc 0** (`_fn_src bin/next-dl max_int` ⇒ 129 lines,
  two further definitions inside) — a silent wrong answer from a primitive whose docblock promised
  "text, or exit 1". It was made to REFUSE, naming what the range would have swallowed, so the
  bound was loud like the other one — and **card#8529 then gave it the one-line MODE it owed**,
  because pinning the `require_value` mirror across four standalone tools needed it and no
  hand-spelling of that extraction was going to be the right answer. It needed the spacing bound
  relaxed in the same change: `uint_ok()     {` is refused on its SPELLING as well as its shape,
  so freeing either alone freed nothing. `promote-pagination-selftest.sh` migrated onto it; the
  three sites still hand-spelled are held there by a DIFFERENT constraint (two names in one read,
  or a there-is-exactly-one COUNT an extractor answering one function cannot assert), and their
  dispositions say so rather than still naming the one-line mode.
  Other derived sites are anchors but not extractions at all — a definition-line LOCATE that must
  not stop at the first hit, a `sed` `i` mutation planter, and a locate in a NON-SHELL file where
  the definition is not at column zero — and are dispositioned as such.
  **Which files are in each shape, and how many, is in `EXTRACTORS` and not here**;
  writing the file list out is exactly what went stale twice. Each guards its
  own extraction, so none can silently retire a comparison — the residual is duplication, not a
  dead guard. The sites that needed only the **text-returning sibling** are migrated onto it:
  `_fn_src` is that sibling, and `_adopt_fn` is now `_fn_src` plus an `eval`, so there is one
  spelling of "where does this function's text start and stop" for readers and runners alike.
  **Instance 2 — the call graph.** The parity block drives each mirrored function against its
  original, which cannot see a divergence in **which sites call it**: `_kb_expand_home` has ONE
  call site in the lib (inside `kb_coord_store_token_file`), and `_rc_expand_home` had THREE, so a
  board env spelling `KBCARD_TOKEN_FILE="~/tok"` was literal to every tool (`kb_resolve_env` rc 5)
  and expanded here. Fixed by dropping the two extra expansions and driving the shape **through
  `kb_resolve_env`**, not through the mirrored function.
  ⛔ **AND THAT BEHAVIOURAL ROW PINNED ONE OF THE TWO SITES, WHILE THIS ENTRY AND THE PR BOTH
  SAID IT PINNED BOTH — corrected here rather than quietly rewritten, because the wrong version
  is the one a future author would have trusted to have retired this.** Measured, twice each:
  restoring `_rc_add_source`'s expansion reds that row (**2 FAIL**); restoring the precedence
  `eff` expansion — the one-line pre-fix restore, on the arm that tells an operator to DELETE a
  file — left the whole selftest at **rc 0, 0 FAIL**. A scenario row per call site is the wrong
  shape in any case: **the divergence is in the CALL GRAPH**, so the call graph is what is
  asserted now — derived from each file (occurrences outside comment lines and outside the
  definition line) behind a positive control, because an equality between two derivations that
  both broke and answered 0 measures nothing.
  ⛔ **AND THE FIRST CUT OF THAT PIN COUPLED THE GUARD TO AN UNRELATED POPULATION — corrected
  here for the same reason, at card#8548.** It compared `_rc_expand_home` call sites in the bin
  against `_kb_expand_home` call sites **anywhere in the lib**, and this entry recorded *"planting
  a second call in the LIB ⇒ 1 FAIL, `expected '2' got '1'`"* as one of its four seen-to-fail
  arms. That arm was the DEFECT, certified as a feature: the lib is a far larger surface than the
  four functions runtime-check mirrors, so a legitimate new expansion in an unmirrored lib
  function (measured: `kb_resolve_env`) red the guard with **no mirror drift at all** — and
  because the failure named an expected-vs-got count, the remedy it invited was to add a matching
  call to the mirror, which is the opposite of correct. **The population is now the mirrored
  region, in two legs**: (A) every `_rc_expand_home` call in the bin is INSIDE the store-pointer
  mirror — the bin has no business expanding `~` anywhere else, and both dropped sites were
  outside it, as is every future one whatever it is called; (B) inside that mirror it expands as
  often as `kb_coord_store_token_file` does, which is the only leg that reads the lib and it
  reads one function of it. Each failure **names the drift, the direction and the remedy** rather
  than a count, and says outright which side must NOT be changed to match.
  Seen to fail, each on a copy of the tree: restoring `_rc_add_source`'s expansion ⇒ leg A reds,
  naming the line; removing the mirror's one remaining call ⇒ leg B reds *"MISSING an expansion
  its original performs"*, with the behavioural rows and the positive control beside it; a second
  expansion inside the mirror ⇒ leg B reds *"expands MORE often … DROP the extra call in the
  mirror"*. And the **negative** control is shipped in the file rather than only measured: a
  planted `_kb_expand_home` in an unmirrored lib function leaves the derivation unchanged, which
  the old pin red on (re-measured at `52125a6`: old ⇒ 1 FAIL, new ⇒ 0 FAIL). The behavioural row
  stays as the witness — leg B compares HOW MANY, never WHICH.
  **The sibling audit of instance 2, and its disposition.** The other three mirrors were counted
  against the lib's call graph at this change: `_rc_declared_token_file` matches
  (`kb_resolve_env` reads the host env and the board env, and so does this), `_rc_store_pointer`
  matches, and `_rc_looks_like_pasted_secret` DIVERGES — two sites here against the lib's one,
  the extra one in `_rc_add_source`. **Accepted, on the record, not carried as a finding:** the
  lib refuses a credential-shaped *store pointer*, while the extra call here refuses to render a
  credential-shaped *declared value* into a message, which is canon #20 on an instrument that
  resolves two credentials at once. It cannot move a verdict — a value of that shape is not a
  readable file, so the source drops out of the population either way — it only replaces silence
  with an UNJUDGED warn.
  ⛔ **The rule this entry exists to state: a duplicated DEFINITION is not covered by a guard over
  duplicated FUNCTIONS.** Extraction is cheap here — the whole mechanism is one `sed` range — so
  the disposition for a rule the test needs to know is **adopt it from the bin**, never re-spell
  it. A re-spelling in a *test* is the worst place for one: it does not fail loudly when it
  drifts, it disarms the assertion that was supposed to notice.
- **A driver that reads the invoking user's `$HOME` measures the box, not the tool** (card#6911) —
  recorded here because it is a shape, not a one-off: `tests/verdict-through-truncating-reader-selftest.sh`
  drove `bin/kbcard` with no arguments, which prints usage at rc 0 on a configured box and exits **2
  with 0 B of stdout** on a bare one, because `kb_load_config` resolves `$HOME/.kanban-dev-board.env`
  before the no-argument help arm. The gate therefore returned **different verdicts for the same
  commit** depending on who ran it, and only CI could see it. Closed with a planted config plus a
  control that drives both sides — but the control is a **CI-side guard only** (measured: deleting
  the plant reds on a bare box, reds nothing on a configured one), which is the property that makes
  this shape survive review. **The whole 42-selftest CI matrix was re-run under a bare `$HOME`
  looking for siblings and found none**, so this is one instance, not a class — recorded so the next
  gate author knows the axis exists and that `--help`-shaped is not the same as host-independent.
  One residual is named at the gate: `board-session-close`'s direct rc and byte count still vary by
  box, though its classification does not.
- **CI's shell-file population, hand-copied into three class gates** (card#6911) — **EXTRACTED, and
  two adoptions still owed.** `.github/workflows/ci.yml` names the population once
  (`find bin hooks -maxdepth 1 -type f ! -name '*.py'` plus `find tests -maxdepth 1 -type f -name
  '*.sh'`), and by the time this was noticed the expression had been re-typed into
  `read-outcome-collapse-selftest.sh` (card#7210), `piped-match-gate-selftest.sh` (card#7175) and
  `verdict-through-truncating-reader-selftest.sh` (card#6911) — the third caller, one past canon
  #5's threshold. `tests/_shipped-shell-lib.sh` now owns it and the card#6911 gate is its first
  caller. ⛔ **THE THREE POPULATIONS GENUINELY DIFFER AND MUST NOT BE FLATTENED:** two take
  `bin/`+`hooks/`, `piped-match-gate` deliberately ADDS `tests/*.sh` because 44 of the 47 copies its
  class found were inside the harness. So the lib exports **CI's two halves separately** and each
  caller composes its own union — the population is a parameter, never a constant. Adoption is
  behaviour-preserving by construction (byte-identical output to what each already computes), so
  the other two can adopt in their own PRs; they were left untouched here because they were outside
  that PR's file scope. The `ci.yml`↔lib restatement **cannot be deleted** (a workflow `run:` string
  cannot source a bash lib), so it is **GUARDED** instead: `_ci_shellcheck_drift` reds when ci.yml
  stops running either half, with planted positive/negative/no-file controls, all three watched to
  fire. ⚠ **Do not over-cite this:** it dedupes the DERIVATION, not the per-gate ROLL of
  dispositions — a new bin still costs one edit per gate, by design, and the stale-roll blocker that
  prompted the extraction is not something this lib would have caught.
- **The repo-slug predicate, in three bins with THREE spellings** (card#8421) — **EXTRACTED to
  `kb_is_repo_slug` in `bin/_kb-board-lib.sh`; two of the three adopted, the third is a documented
  standalone.** One accept-set — a bare GitHub `<owner>/<name>` — was written three ways:
  `bin/adopt-to-dl`'s `_ata_validate_repo` hand-rolled it as three `case` steps under a local
  `LC_ALL=C`; `bin/run-coverage-check` re-spelled it as a bare regex through `kb_ere_match`;
  `bin/promote-released-cards` spells it as `src_charset_ok` plus a shape `case`. **The divergence
  is the entry, not the count:** the three did not agree. `run-coverage-check --repo` accepted
  `owner/name.git`, which the other two refuse — and the `.git` arm is the one with a stated
  reason (the server's source canonicalizer does not trim a `.git` while `repoFromGitHubUrl` does,
  so the two derivations disagree and a stamped card verifies against a source no card can
  carry). A third copy is where the narrow rule quietly fails to arrive, exactly as the card#7207
  entry above records. **`promote-released-cards` keeps its copy and that is not an oversight** —
  it is vendored standalone into consumer repos and must not source the lib (the same constraint
  that duplicates `host_ok` and `require_value`), so the two are bound by the single accept/reject
  corpus in § 3c of `tests/promote-source-qualify-selftest.sh`, which drives BOTH ends from one row
  set — the lib predicate called directly, `promote-released-cards` run end-to-end — and pins
  the two declared divergences in both directions.
  **Consequence recorded rather than discovered later:** adopting the shared predicate NARROWS
  `run-coverage-check --repo`, which now refuses `owner/name.git` at rc 2 instead of putting it
  into a `repos/<slug>/…` request path GitHub answers 404 for; the narrowing carries its own arm
  in `tests/run-coverage-check-selftest.sh`. The predicate's arms moved WITH it, from
  `tests/adopt-to-dl-selftest.sh` to `tests/kb-board-lib-selftest.sh`, and the caller's selftest
  keeps an end-to-end arm for the WIRING — a lib unit test cannot tell whether its caller still
  calls it.

- **The GitHub Actions file population, in three gates with TWO predicates** (card#7207) —
  **EXTRACTED, all three adopted in the same PR.** `ci-matrix-parity-selftest.sh` and
  `shellcheck-pin-selftest.sh` each globbed `*.yml` **and** `*.yaml` inside their own python
  heredocs; `python-syntax-gate-selftest.sh`, written last, globbed `*.yml` only — and its whole
  purpose is an assertion of ABSENCE over that population. Measured before the fix: a planted
  `.github/workflows/sneak.yaml` running `python3 -m py_compile bin/*.py` passed it at `all checks
  passed`, and the byte-identical file renamed `.yml` red it. The divergence, not the miss, is the
  entry: a third copy of a derivation is where a narrower predicate gets minted unobserved, and the
  copies were near-identical enough that per-file review read the narrow one as covered.
  `tests/_gha-surface-lib.sh` now owns it — `_gha_workflow_files <dir>` (both extensions, one level)
  and `_gha_action_files <root>` (`action.yml`/`action.yaml` at **any** depth, `.git` pruned, since
  `uses: ./x/y` resolves to `x/y/action.yml` and a nested action is as executable as a top-level
  one). **The directory stays a PARAMETER**, exactly as `_shipped-shell-lib.sh` keeps its two halves
  separate: that is what lets each gate point the same derivation at its own planted fixture tree,
  which two of the three already did and none could have kept doing against a hardcoded root.
  Adoption is behaviour-preserving **by measurement**: all nine `ci-matrix-parity` projections and
  both siblings' complete assertion streams are byte-identical before and after. ⚠ **One property
  to know before editing it:** narrowing the shared predicate back to `*.yml` reds
  `python-syntax-gate-selftest.sh` and **leaves both siblings green** — their own fixtures are
  `.yml` files, so nothing there notices. One owner with one guard is the intended shape (three
  copies of the fixture would re-mint what this removed), but it means an edit to the lib is
  answered by that one gate, and it is recorded in the lib's header at the loop it guards.
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

  **✅ CLOSED (card#6630) — THE SAME SHAPE ON LATER PAGES. 3 instances, all 3 fixed.**
  This entry previously said *2 instances* and was CLOSED once already on that count. The count was
  asserted, never derived, and it was wrong: a third paginator in this tree carried the same shape.
  The card was the ONE class item for all three (canon #18 — the audit finds instances, the class
  gets the item), and it is closed only now that the third is fixed. **What the first false close
  cost, recorded so the shape of the mistake survives the fix:** re-closing on a re-derived
  denominator is cheap, and closing on a recalled one hid a live silent-truncation path in a
  shipped tool for the whole interval. The two card paginators are recorded below as members that
  landed first; the changelog window landed second, in its own change, because its failure policy
  was a decision and not a predicate edit.

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
  | `bin/board-stats` `_bs_window_rows` | `before=<cursor>` | **yes — FIXED, see below** |
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

  **The "quietly rendered" half is closed at the RENDERER too, and no longer only for this
  fixture (card#6365) — closed for THE PARTIAL READS THE PAGINATOR CAN DETECT, which is not the
  same sentence as "the renderer cannot quietly render a partial read".** Moving that fixture to
  rc 2 removed *this* route to a quiet render; it left the property itself standing, because rc 3
  (page cap) and rc 4 (a genuine short read on a reachable board) still reach the rendering
  consumers with a partial array by design — that is what those rcs are for. `bin/board-snapshot`
  now marks it **on stdout**, the channel its SessionStart consumer surfaces: every count that
  pass prints carries a `≥` and each of its two sections carries a `card list INCOMPLETE (fetch
  rc=$rc)` note.

  The scoping clause is load-bearing rather than a hedge: three shapes still reach the renderer at
  **rc 0** and are rendered as confident totals — a server that omits `meta.total` (no census to
  run), a page delivered twice and scored as a dedup artifact, and a board the token cannot see
  answering the same well-formed empty envelope as an empty board. All three are named as accepted
  residuals in `fetch_board_cards`' own body — two under the words *"Residual, accepted"* (the
  token-visibility envelope at the parse refusal, the duplicate page at the census) and the third
  stated in the card#6630 paragraph, which names an omitted `meta.total` as the case the census
  cannot speak for. All three are upstream of every renderer, and none is closable by a stricter
  row count — the token-visibility one needs a membership signal the envelope does not carry. A marker
  driven off `$rc` cannot see any of them, so what the renderer now guarantees is *"a read the
  paginator flagged is never rendered as whole"*, not *"a rendered count is whole"*.

  **The marker covers the arms that RENDER and the arms that read NOTHING (card#6365 review).**
  The first cut marked only rc 3 and rc 4 — the two arms that render a partial array. The other
  five arms that reach the untriaged section (env file missing, env sets no `KB_BOARD_ID`, token
  file unreadable, and the read guard's rc 1 / rc 2) reported once on stdout and wrote nothing to
  fd 3, so the untriaged section rendered **empty** under a header that says *"triage is my
  responsibility; none may be silently missed"* — for a board where zero rows were read. That is a
  stronger version of the claim the rc-3/rc-4 note exists to forbid one line above it, and it was
  reachable by a 500 from the API. All five now report through one `board_unread` helper that
  writes the same reason to both channels; the two jq renders each gained a fallback on their own
  channel for the same reason. The old behaviour was documented as a preserved *"fail-soft
  asymmetry"* — it was inherited from the era when the two sections were two independent passes,
  not a ruling, and it is recorded here as ruled-on rather than left implicit.

  **`bin/board-stats` is the class's SECOND MEMBER and it is OPEN, not closed (card#6365 review —
  the RENDERING half has closed since; the disposition paragraph directly below this one owns the
  current state, and this paragraph is the finding as it was written).**
  It already emits an INCOMPLETE note at its `3|4` arm (`every stock count below is a floor, not a
  total`), which is why the first cut of this paragraph recorded the class as *"two members and was
  one instance"*. That was true of the NOTE and silent about the MARKER: every stock number
  `board-stats` prints is bare — measured at NINE per board on all three boards here (eight columns
  plus the total), each quotable out of the one `⚠` line that qualifies them — and `--format json`
  is worse. Its rc-3/rc-4 arm leaves the internal `stock_ok` **true**, so `.stock` is emitted as a
  fully populated object with **no field that distinguishes it from a whole read** (the emitted keys
  are `board`, `board_id`, `failures`, `flow`, `label`, `stock` — there is no completeness field at
  all); the only signal is a prose string inside `failures[]`, which a JSON consumer has to
  string-match to learn the counts are floors. Either the `≥` carrier is load-bearing, in which case `board-stats` needs it (and its
  JSON needs a machine-readable completeness field, not prose), or it is deliberately
  board-snapshot-specific. It is the former: the carrier exists because a number survives being
  quoted out of its line, and a JSON field survives being read by a program that never sees prose
  at all. Recorded as an OPEN member of this entry — it has an owner and a queue position here
  (canon #18) — rather than fixed inside card#6365, whose scope is the SessionStart renderer.
  Changing what `board-stats` prints and what its JSON asserts is an operator-facing report change
  and is ask-gated.

  **DISPOSITION of that second member — the STOCK RENDERING is closed, the CLASS IS NOT
  (card#7228).** The operator approved the rendering half only, and only that half was built:
  `board-stats` now derives the completeness state once at its own `fetch_board_cards` rc guard and
  prefixes `≥` onto every number the stock section prints. The state is **fail-closed**: it is
  initialised false and exactly one arm — rc 0, the whole read — claims otherwise, so an rc added
  to the accepted-partial `3|4` arm floors its numbers whether or not anyone remembers to say so,
  and only an explicit edit to the rc-0 arm can ever claim a read is whole. (A `rc -ne 0`
  derivation over one merged `0|3|4` arm — `board-snapshot`'s shape — was the first cut and is not
  what shipped. **The reason first recorded here for abandoning it was wrong and is corrected:** it
  said that shape pushed the guard's own `*)` arm past the ten-code-line window
  `tests/fetch-board-cards-caller-claims-selftest.sh` derives its arm population inside. Re-measured
  on the shipped bin, a COMPACT spelling of exactly that derivation — the merged arm plus a
  single-line `if [[ "$rc" -ne 0 ]]; then … else … fi` — runs that selftest at **rc 0**, while a
  fully expanded `if … fi` of the SAME derivation reds it on `bin/board-stats: the registered arm is
  INSIDE the derived window [card snapshot unavailable …]`. So `ARM_WINDOW=10` constrains how many
  CODE LINES a spelling spends between the call and its last arm — it constrains LAYOUT, not the
  derivation — and it forbids no shape. The fail-closed default-false spelling stands on its own
  stated ground, which is the only ground it ever needed: it is the stronger invariant, because a
  new rc added to the accepted-partial arm inherits the floor instead of inheriting a claim.) The
  denominator is one count per column, the total, and the oldest-card AGE in each
  pullable column that holds one; the age joins the counts because a card the read never delivered
  can only be OLDER than the oldest one it did, so the printed age is a floor for the same reason
  the counts are. Measured against the pre-change bin, side by side through the shared curl stub:
  the two bins are byte-identical on FOUR of the six format × rc combinations — the text render at
  rc 0, and `--format json` at rc 0, rc 3 and rc 4 — and the two that differ are the text render at
  rc 3 and rc 4, which is exactly this change. (The first cut of this sentence read "a complete read
  is byte-identical … on text AND `--format json`, at rc 0, rc 3 and rc 4", which asserts the
  partial TEXT renders are unchanged. They are not, and could not be.)

  **THE CARD ID beside that age — this paragraph is the single owner of the ruling, and the first
  one was wrong.** The id is the only value in the stock section that is not a number, so the
  marker cannot carry it: `≥` says nothing about an identity. The first cut therefore left it bare
  and justified that by *"the ⚠ line directly above the section already says the named card may not
  be the oldest one on the board"* — **a sentence that does not exist**. The rendered ⚠ line is
  `card snapshot INCOMPLETE (fetch rc=4) — every stock count below is a floor, not a total`; it
  speaks only about the counts, so the age was correctly floored while `(#11)` was left asserting
  *the oldest Backlog card is #11* off a read this tool had just declared incomplete — and by this
  entry's own premise, the card that is actually oldest can be one the read never delivered, under a
  DIFFERENT id. An operator could act on the wrong card. Two routes were on the table and neither
  shipped: **extending the ⚠ text** would put the qualification back onto the line this whole change
  exists because a value survives being quoted out of it, and **dropping the id on a partial read**
  discards a datum that is true and actionable (#11 really is that old and really is pullable — and
  on a page-capped board the report would then name no card at all). What ships is the qualification
  ON the value, for the same reason the marker is: a floored render prints `oldest ≥232.3d (#11
  among the cards read)`, which is true as written and stays true quoted out of every line around
  it. A complete read prints the id bare, asserted with its own control — a qualifier on every
  report would be a worse defect than the one it closes. `bin/board-stats`' `idq` definition and the
  CHANGELOG entry POINT here; the false sentence was minted into three surfaces in one change, which
  is what made re-stating it three times the wrong correction.

  **DISPOSITION of the FLOW half — CLOSED (card#7235), and it is the same fix one section lower
  rather than a second mechanism.** `_bs_one_board` sets `flow_ok=true` on a window it could only
  partly read and appends *"changelog window INCOMPLETE: … — the flow counts below are a floor, not
  a total"*, and then `created`, `moved`, `same-stage moves` and every per-transition,
  per-resolution and per-wash count rendered unqualified under it. Every one of them now carries the
  `≥` the stock section carries, through the SAME `fl($f)` carrier card#7228 built — the marker takes
  a cell of the existing right-padded column, so alignment holds, proven by a strip control that
  compares the floored render to the complete one as a byte equality rather than by eye.

  **The denominator is wider than the card named it, and the two additions are the reason it was
  re-derived instead of copied.** The card listed `created` / `moved` / `same-stage moves` / every
  transition, resolution and wash count. Two more classes of quantity print in that section and both
  are floors for the same reason:

  - **the human/service/unattributed numbers inside every split note** — they count the same rows
    the line they hang off counts, so `split_note` now takes the marker as an argument rather than
    reading none;
  - **`transitions: none in window` / `resolutions: none in window`** — a ZERO is a quantity, and
    `none in window` asserts a TOTAL of zero that survives being quoted out of the ⚠ line exactly as
    a digit does. It is the one claim in the section the marker cannot reach, because there is no
    number to prefix, so a floored render names the population instead — `none in the events read` —
    which is the route `idq` already takes for the oldest-card id, not a new one. A complete window
    still prints `none in window`, with its own control.

  Two things in that section are deliberately NOT marked, and neither is a quantity: the stage
  LABELS, and the `⤷ the changelog reaches back only to …` line, whose instant is the oldest row that
  WAS read and is therefore exact rather than a floor.

  **The two completeness states are SEPARATE, and that is a ruling, not an implementation detail.**
  `flow_complete` is derived at the changelog guard and `stock_complete` at the card guard, from two
  reads with two failure modes: a whole card read under a partly-read window floors the flow half
  ALONE, and the reverse floors the stock half ALONE. One shared flag would floor a section that was
  read whole, and a qualifier on every report is a worse defect than the one this closes — so both
  directions are asserted against the same bin in the same run.

  **The two flags are NOT fail-closed the same way, and the review that found it is why this says
  so.** `flow_complete` is initialised false with exactly ONE arm — an empty `error`, the window
  read to its cutoff — claiming otherwise, and that much reads like `stock_complete`. It is not the
  same dispatch. `stock_complete` switches on an **enumerated rc**, so an rc nobody listed lands in
  `*)` and floors by default. `flow_complete` switches on the **absence of a string** that
  `_bs_window_rows`' own exits have to remember to set: the completeness claim is driven off
  exactly the break sites that set `err`, and a `break` added to that loop which does not set `err`
  reaches the same arm as a window read to its cutoff and claims the window is WHOLE. **That
  direction is FAIL-OPEN**, and a future editor is entitled to know it: adding a break means adding
  its `err=` in the same edit. **Which break sites those are is enumerated ONCE — in
  `bin/board-stats`, in the comment above the `flow_complete` guard in `_bs_one_board` — and this
  document deliberately carries no copy of the list.** The copy it used to carry was one short (it
  named four, omitting the failed changelog READ, which is two messages on one break), which is
  what a hand-synced enumeration in four places produces; the same reason the ask-gated decision
  below is owned here and pointed at from there, in the other direction.

  The nearest EXISTING instance of the shape is the short-page arm's `oldest == none` route, which
  breaks with no `err`. `oldest` is `ep()` of the page's **last row**, so a last row whose
  `created_at` this tool cannot read renders a truncated window as a complete one. **Measured
  against the live board API on 2026-08-22, that read is not exposed there:** the changelog renders
  `created_at` at second precision with a `+00:00` offset — `2026-08-22T18:57:21+00:00` on a fresh
  row, and `2026-06-29T21:12:44+00:00` on the oldest row board 12's log still holds, i.e. at both
  ends of a seven-page window — which `ep()` rewrites to `Z` and parses (1787425041), while the
  fractional-second form (`2026-08-22T18:57:21.123456+00:00`) is the control and returns `null`,
  re-run here rather than carried across. So the shape is real and
  the live trigger is absent on the host measured — a statement about that host on that date, not
  about every host, and not a claim that no host can produce one.

  **The fix that would close the direction is ask-gated and is NOT in this branch.** Making the
  flag affirmative — each stop declaring completeness rather than every stop declaring an error —
  floors strictly more reports than this change does, which is an operator-facing render change and
  therefore takes the same approval the two fixes above took. It was escalated to the operator on
  2026-08-22 separately from this branch, as **card#7298**, which carries the recommendation and
  the measurement; recorded here so the bin's own comment can point at one owner for the decision
  rather than restate it.

  **ONE member of this class stays OPEN on this tool, and it is not a residual of either fix —
  it is the same defect on a surface neither approval covered:**

  - **`--format json` still carries no completeness field for EITHER half.** This was left alone on
    purpose: it is a machine-readable CONTRACT change, and the operator ruled the consumer set has to
    be enumerated before a key consumers must honour is added. The document behind the renderer does
    now carry a `stock_complete` and a `flow_complete` (the text renderer computes nothing of its own
    and needed fields to read), and the `json` arm STRIPS both — so the emitted object is the same six
    keys it always was, asserted in `tests/board-stats-selftest.sh` on a whole read, a partial card
    read and a partly-read window. **The unmeasured bound is unchanged and is the first step of that
    half, not a detail of it:** nothing in this repository consumes `board-stats --format json`
    (grepped), which is a statement about this repository and not about who runs the tool.

  **TWO NEW members were found by the card#7235 sibling audit, on OTHER tools — found, not fixed,
  because each is an operator-facing report change and therefore ask-gated exactly as these two
  were.** **Filed 2026-08-22 as card#7291 and card#7292.**

  - **card#7291 — `bin/board-session-close`'s `_bsc_advisory_leg` prints a KILLED leg's partial output on
    STDOUT and says it is partial on STDERR, below it** (`bin/board-session-close` :797 for the
    output, :804–:806 for the notice). A leg that hits the 60s wall clock is killed at `timeout`'s
    rc 124; its output — which for `_kbc-archive-eligible.py` and `_kbc-stale-blocker.py` is a block
    of counts — is printed first and unqualified, and the *"the … is INCOMPLETE, and what you see
    above is a partial answer"* notice goes to fd 2. That is BOTH halves of card#6365 at once: the
    qualification is on a different CHANNEL from the numbers (the exact half card#6365 closed for
    `board-snapshot`, whose notice moved to stdout because that is the channel its consumer
    surfaces) and it is on a LINE rather than on the values. **This route is why a scripted sweep
    could not have found it:** the partiality does not come from a partial READ at all — this tool
    reads no collection — it comes from a leg killed mid-run, so the "calls a paginator" predicate
    the audit derived its population with does not select this file. The pass that found it MOVED
    the denominator, which is exactly the shape of audit whose clean result means *a pass that moves
    neither the numerator nor the denominator*, not *a grep came back empty*. The drift-check leg
    at :911 splits the same two channels for the same reason — the delegate's output on stdout, the
    degraded-coverage ⚠ on stderr — so a fix here has two sites in this file, not one.
  - **card#7292 — `bin/_kbc-stale-blocker.py`'s summary block prints bare counts under a partial corpus**
    (:627–:638). A declared board that fails to read is warned on stderr and the run continues, and
    the summary then prints `{total_live}` live cards indexed, `{total_open}` open cards scanned,
    `{examined}` citations examined, then `no blocking marker before it: N`, each `excluded, …: N`,
    and `asserted as a blocker: N → M flagged, K out-of-tenant, U unresolved`. The `N of M declared
    board(s) read` clause rides the SAME line as the first three and qualifies nothing below it.
    ⚠ **Not every number there is a floor, and a fix must not assume it is:** `unresolved` moves the
    other way — a citation naming a card on an unread board resolves as unresolved *because* the
    board was unread — so a blanket `≥` would be a wrong claim on that one. It needs the same
    per-value derivation this card did, not a copied prefix.

  **The audit's denominator, so a later pass can re-derive it rather than inherit it.** Population:
  every script in `bin/` + `hooks/` (**28**), narrowed by the property that makes a partial render
  possible — the tool prints a QUANTITY on an operator-facing channel from an input it knows was
  incomplete. **The outer population is scripted; the narrowing to 14 is NOT, and saying otherwise
  was the defect the card#7235 review caught in this paragraph.** Both commands, so a later pass
  re-runs them rather than quoting these figures:

  ```sh
  find bin hooks -maxdepth 1 -type f | wc -l                      # 28 — the population
  command grep -rlE 'fetch_board_cards|fetch_whole_board|fetch_board\b|changelog\.json|search/code|os\.walk|\.rglob|\.iterdir' \
      bin hooks --exclude-dir=__pycache__ | sort                   # 12 — the read-driven sweep
  ```

  Measured 2026-08-22: the sweep returns **12**, not the 14 below. It selects every tool that
  accumulates a COLLECTION through a board read, and the two it cannot select —
  `bin/install-board-hooks` and `bin/release-tag-check` — were added by READING: one iterates the
  hook set it installs, the other polls a remote for a tag, and neither reaches this predicate
  through any token. So the 14 is a hand-enumeration that a token sweep starts and a read finishes,
  and the sweep is shipped here as the reproducible part rather than described as the whole
  derivation. Each of those 14 was then READ at its own read site and classified REFUSE vs
  RENDER-ANYWAY: `promote-released-cards` dies on every truncation path, `kbcard` refuses at three of its four `fetch_board_cards` sites and makes no
  operator-facing claim at the fourth, and `next-dl` / `dl-a0-backfill-triaged` / `board-card-start`
  all refuse, `bin/_kb-board-lib.sh` IS the paginator and renders nothing, and
  `bin/install-board-hooks` / `bin/release-tag-check` print no quantity derived from a partial read
  at all. Two RENDER-ANYWAY tools are non-members on their content rather than on their arm:
  `bin/gh-code-search` puts `incomplete_results` on the SAME LINE as `total_count` in every branch by
  explicit design, and `bin/_dependabot-reconcile.py` prints *"a population that was never measured"*
  rather than a number it cannot stand behind. `bin/_kbc-archive-eligible.py` is ADJACENT and
  deliberately not counted: a board it could not read is warned to stderr with no stdout row, which is
  card#6365's channel half — but every number it prints belongs to a board it DID read, so no printed
  quantity is a floor. **The arithmetic closes on 14:** 6 refuse or render nothing
  (`promote-released-cards`, `kbcard`, `next-dl`, `dl-a0-backfill-triaged`, `board-card-start`,
  `_kb-board-lib.sh`), 2 print no such quantity (`install-board-hooks`, `release-tag-check`), 2 are
  non-members on content (`gh-code-search`, `_dependabot-reconcile.py`), 1 is adjacent
  (`_kbc-archive-eligible.py`), and **3 are members** — `board-stats` (both halves now closed, the
  json field open), `board-snapshot` (closed by card#6365, with the candidate below), and
  `_kbc-stale-blocker.py` (new, above). `board-session-close` is the 15th, and it is the one this
  population did not contain. **One candidate is recorded undecided rather than either way:**
  `bin/board-snapshot`:177 says *"the in-flight count below is a FLOOR"* and an in-flight LIST follows
  it, so the notice speaks about the count and is silent about the list — the same wording gap
  card#7228's review found for `(#11)`. It is weaker than that one, because a list asserts no
  superlative the way "the oldest is #11" does, and it is left as a question for whoever takes the
  `board-snapshot` surface next rather than answered here.

  **So the class is OPEN**, with three members outstanding: the `--format json` field on this tool,
  and the two new ones above. Recording it closed over these would be the same failure this document
  records for the `has()` class — the first cut of that section said it had.

  **The SessionStart delivery bound, filed not fixed (card#6365 review).** `board-snapshot`'s
  in-flight list is UNCAPPED — one line per in-flight card — while the untriaged list caps at six.
  Measured on the rc-3 page-cap fixture: **7,057 characters for ONE board** (212 lines), against a
  SessionStart `additionalContext` cap measured at ~10 KiB PER OUTPUT, in characters, above which
  the payload is spooled and only a ~2 KB preview injects while the hook still exits 0. The first
  casualty of that truncation is the TAIL — the fd-3 note and the entire untriaged section, i.e.
  exactly the lines this change added. Today's live three-board run is 1,400 characters, so the
  bound is conditional and not firing; it is filed because the fix's premise is *"the notice
  reaches the consumer"*, and writing to stdout is necessary, not sufficient. The remedy is to
  **SPLIT the output, not shrink it** (the framework's own finding on this cap), which is a change
  to the hook's delivery contract rather than to this renderer, and therefore not card#6365's.

  **THE THIRD INSTANCE — `bin/board-stats` `_bs_window_rows`, now FIXED, and the reason this entry
  was not closed with the other two.** The changelog window is read by paging BACKWARD on a
  `before=<cursor>` id until the rows precede the cutoff, and the loop's end-of-data signal is a
  **short page**: `_BS_PAGE_JQ` opened with `(.data // []) as $d`, so a `2xx` carrying no `.data`
  yielded `n: 0`, `n < _BS_CL_LIMIT`
  read as *the log is exhausted*, and the loop `break`ed with `truncated=false` and `err=""`. That
  is the same shape as the two fixed above, on the same `KB_API`, the same host, reachable by the
  same proxy/gateway error body. **Measured against the real function** (the shipped
  `_bs_window_rows`, sourced from `bin/board-stats`, page 1 = 200 rows, `_BS_CL_LIMIT` = 200, and
  re-measured on this tree before the predicate was touched — the table below is that re-run, not
  a relayed one):

  | page-2 body | `_bs_window_rows` result |
  | --- | --- |
  | `{"error":"upstream connect error"}` | `pages: 2, truncated: false, error: null` — **silent**, 200 rows |
  | `{"data":null}` | `pages: 2, truncated: false, error: null` — **silent**, 200 rows |
  | `{"data":"str"}` / `{"data":{"id":9}}` / `[{"error":…}]` | `error: "changelog page 2 is not the shape this tool reads"` — caught |
  | `<html>502</html>` | same — caught |

  So the live half was narrower than a `.data`-shape test would suggest, and stating it precisely
  matters: of the shapes measured, the silent set is a JSON **object** whose `.data` is **absent,
  `null` or `false`** — the three `//` substitutes for. The mechanism that catches the rest is
  `$d[-1]`: `// []` yields the substitute only for `null`/`false`, so any other non-array `.data`
  reaches `$d[-1]` as itself and faults the page jq, which the `[[ -n "$page" ]]` guard reports as
  a wrong-shape error. Measured on that boundary: `{"data":false}` was **silent**, `{"data":{}}`
  **caught**. An absent/null `.data` is exactly the shape a
  proxy or gateway error document takes, which is what keeps this reachable rather than academic.
  On the silent path `_bs_one_board` set `flow_ok=true` with no `fails+=` entry, so the report
  rendered flow counts off a truncated window with **no `⚠` line and no `(WINDOW TRUNCATED)`
  marker** — which falsified `bin/board-stats`'s own header claim that *"a number that is a floor
  rather than a total (a capped card read, a truncated changelog window) says so where it is
  printed."*

  **THE POLICY DECISION, TAKEN — and it needed no new mechanism, which is why the fork narrowed
  once the question was asked precisely.** The fork was recorded here as real: `_bs_window_rows` has
  three stop conditions, two of them already set `truncated` while emitting rows, and `board-stats`
  is a fail-soft report whose contract is that one bad board never kills the run — so "refuse" is
  not simply an rc. What resolved it is that the loop **already has** a second, separate channel for
  an aborted read: `err`, which three arms below the stops already use (a curl/HTTP failure, a page
  the parse could not read, a page carrying no cursor id), and which `_bs_one_board` renders on the
  board's own ⚠ line as `changelog window INCOMPLETE … the flow counts below are a floor, not a
  total` whenever `pages > 0`. An unreadable envelope is an aborted read, not a stop, so it belongs
  on that channel and it went there:

  - **The predicate** is the siblings' — `(.data|type) == "array"` — and a body carrying no row
    array makes `_BS_PAGE_JQ` emit **nothing**, which is *already* what a jq fault produces at that
    call site (its `2>/dev/null`). It therefore lands on the pre-existing `[[ -n "$page" ]]` guard
    and reuses its message verbatim. **No new rc, no new field, no new message** — the mirror's
    disposition style, where an operator-facing refusal is not reworded as a side effect of a
    predicate fix.
  - **`truncated` is deliberately NOT set**, and that is the fork's actual answer. It stays a
    property of the three STOPS (cutoff reached, page cap, a log that ends inside the window), which
    is what the function's header already says and what the `(WINDOW TRUNCATED)` marker means. The
    two channels stay distinct: *the log ran out* vs *the body was unreadable*. Collapsing those two
    was the defect; making the second one also set the first would have re-blurred it from the
    other side.
  - **No page split**, unlike the two card paginators. Those split by page because each has two
    documented rcs to select between; this function has one `error` channel and `_bs_one_board`
    already branches identically for any `pages > 0`. Page 1 moves by the same predicate with the
    same message — measured before and after: `{"error":…}`, `{"data":null}` and `{"data":false}`
    as PAGE 1 produced a flow section of zeros reading as a quiet board, and now carry the ⚠.
  - **`{"data":[]}` is untouched at every page number.** A genuinely exhausted log answers with an
    array; it is a short page, it stops the loop, and it stays silent. That is why the predicate is
    a TYPE test and not a truthiness one, and it is a selftest control rather than an argument — a
    truthiness mutant reds it while leaving every refusal leg green.

  **The header claim at `bin/board-stats:61` is repaired by the CODE, not reworded.** It was filed
  here rather than edited precisely because correcting it either way would have pre-judged this
  decision; with the decision taken, the sentence is true — every floor this tool prints now carries
  its own line where it is printed — so the line stands and the selftest asserts it on the
  **rendered text**, not on the JSON field a human never sees. **One imprecision found in the same
  header while making that true, and corrected with it:** `_bs_window_rows`'s own line claimed *"the
  rows never pass through a shell variable or argv"*, which this loop has never satisfied — one
  page's body is `$resp` and one page's filtered rows are `$page`. The guarantee the design actually
  makes, and the one the argv bound is about, is that the **accumulated window** never does: rows
  are appended to the rows-file and reach the aggregation through `--slurpfile`. The line now says
  that instead. No code moved for it.
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
    truncated list through at rc 0 — is closed under card#6630: an unreadable page > 1 is now rc 2,
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
- **The lib-sourcing-bins list, in FOUR prose copies** (card #5981) — **SHIPPED, card#6884, on the
  THIRD attempt AT CLOSING THE CLASS** (`tests/lib-set-derivation-selftest.sh` says *fourth* and is
  not in conflict: it counts attempts at the LIST itself, of which the first two closures here were
  two). *(This line read "on the second attempt" until a third review pass measured that
  the gate the second attempt shipped had the class's own defect inside it — see the second ⛔ below.
  The correction is left visible rather than smoothed, because "shipped on the second attempt" is
  precisely the kind of claim this bullet exists to distrust.)* The lib header, `ADOPTION.md`,
  `INSTALL.md` §6b and `UPGRADE.md` §3 each
  enumerated the bins that `source` `_kb-board-lib.sh`, while `agent-board-toolkit-drift-check`
  **derives** the real set from the files. The prediction this bullet carried is what came true:
  `gh-code-search` joined the set and reached **one** copy, leaving the others telling a vendoring
  consumer to copy a bin set that omitted it — an rc-1 "shared lib not found" refusal on every
  invocation, from following the instructions. Every enumeration is now **deleted**, each replaced
  by the derivation itself — `grep -lE '^[[:space:]]*source "\$KB_LIB"' bin/*` — which is the
  answer this bullet required each audience to be left with (a command they can run against the
  version in their hand), not a bare pointer.

  ⛔ **THE FIRST CLOSURE OF THIS BULLET WAS FALSE, and how it was false is the reason the ruling
  below reversed.** It fixed three copies, wrote *"no fourth copy and no new gate"*, and marked the
  class SHIPPED — against a denominator taken from **this bullet's own prose** rather than
  re-derived from the tree. `UPGRADE.md` §3 was never in that three, and it is the copy a
  re-vendoring consumer actually follows (`INSTALL.md` §6b points at it): it named **six** bins
  where the derivation answers **nine**, omitting `adopt-to-dl`, `board-stats` and `gh-code-search`.
  The re-derivation is the one the fix now publishes, run against the tree in hand rather than
  quoted — `grep -lE '^[[:space:]]*source "\$KB_LIB"' bin/*` (9), controlled against the wider
  `grep -ln _kb-board-lib bin/*` (16), whose seven extra hits are each a documented standalone that
  mirrors a helper rather than sourcing it. A pass that had re-derived instead of quoting would have
  moved its own denominator, which is exactly the signal that a class audit has not converged.

  **The "no new gate" ruling is REVERSED, and the reversal is the finding, not a preference.** The
  argument for it was sound — `drift-check`'s `MISSING-LIB` probe and
  `tests/drift-check-fixture-selftest.sh` do keep the *pattern* honest — but it answers a different
  question: those two prove the derivation still discriminates a sourcer from a standalone; neither
  can see a prose list that has stopped agreeing with it, and a prose list is what the consumer
  reads. A four-copy class that survived a three-copy audit **is** the argument for a gate, and it
  now has one: **`tests/lib-set-derivation-selftest.sh`**, which (1) extracts every published
  spelling of the derivation from the tree, runs each against `bin/`, and reds when one answers a
  different set — or nothing, which is how the release note shipped it, with `$KB_LIB` unescaped
  inside single quotes so the ERE anchor matched **0** files — and (2) reds when a line **anywhere
  in the tree** both names the lib and enumerates two or more members of the derived set, with
  fixture controls so the leg is watched to fire. Its unit is the LINE, which is a
  whole paragraph in the markdown a consumer follows and a wrapped fragment in a shell comment —
  stated in the check, because it means a historical aside wrapped across comment lines is out of
  its reach by construction, not by luck. Version-specific history
  (`UPGRADE.md`'s version-specific section and `docs/CHANGELOG.md`'s RELEASED entries, each split
  at its heading; plus `CLAUDE.md`, carved WHOLE-FILE for a second and independent reason — it is
  agent orientation and reaches no vendoring consumer, so `LEG3_HISTORY=("CLAUDE.md")` skips the
  file, not its release-snapshot table) is deliberately out
  of its population and the check says
  why: a frozen at-that-version list cannot rot, and the v0.8.2 entry now says so in its own words.

  ⛔ **THE SECOND CLOSURE WAS ALSO WEAKER THAN ITS WORDING, and by the same mechanism — which is
  why this bullet now names three attempts.** The gate above shipped with leg 3 stated as *"**No**
  consumer-facing surface enumerates the set in prose again"* while it ran over **four hard-coded
  paths**. A class audit's own instrument had a hand-kept denominator: a fifth surface joined
  silently, measured by appending a re-vendor sentence naming four bins to `README.md` and watching
  `lib-set-derivation-selftest` stay at **rc 0** — the file was outside its four paths entirely —
  with `readme-bin-coverage-selftest` at rc 0 beside it, because that gate owns a *different*
  inventory and compares names only, which it says. That is the same shape as the first closure (an instrument answering about
  its list rather than about the repo) with a check in front of it, which is worse, not better: the
  green now certifies the narrower question.
  **Leg 3's population is now DERIVED on every run** — every readable non-binary file in the tree,
  `.git` excluded, the same population leg 1 uses — minus two carve-outs of deliberately different
  shape: version-specific frozen history, carved out at the HEADING where it begins for two of its
  three members — `CLAUDE.md` stays whole-file, for the independent reason named above (a per-line
  disposition there would need a new entry every release, i.e. the hand-kept list again — it was
  carved **whole-file** until the fourth pass below), and a small set of
  **per-line** dispositions for prose that names the same nouns without instructing anyone to copy
  anything, each keyed `<path>::<substring>` and each **asserted to still match a live line**, so a
  disposition cannot outlive the line it disposed. Line scope is load-bearing on `README.md`
  specifically: it carries one disposed paragraph and is the most consumer-facing file in the repo,
  so a whole-file carve-out would have hidden a regrown list exactly where it does the most damage.
  Three mutations were watched red and restored by copy + `cmp`: the reviewer's `README.md` line
  (1 red), a brand-new `docs/` file nobody named (1 red), and a disposition made stale (2 red).
  **Leg 2 keeps its four-path list, and that is not the same defect**: "this surface OWES the reader
  a derivation" is an editorial obligation no property of the tree can derive, the list is a FLOOR
  rather than a population, and leg 3 no longer reads it.

  ⛔ **A FOURTH PASS THEN MEASURED THE THIRD CLOSURE'S CARVE-OUTS WRONG IN TWO PLACES — same shape
  again: a stated scope wider than the predicate under it.** *(a)* The `UPGRADE.md` split was cut on
  `^## 6\.` while one sentence beside it called it *"derived, not a line number"* (three
  mentions of the split, one making the claim): only the
  OFFSET was derived — the **6** was a hand-kept fact, this bullet's own subject inside this
  bullet's own gate. Measured: a new LIVE `## 6.` section carrying an enumeration line, with the
  history renumbered to `## 7.`, left the run **rc 0 all-green** while the live region silently
  SHRANK, because the only premise beside the cut asserted what the live region LACKS — a direction
  that catches a too-WIDE cut and never a too-narrow one. Both splits are now located by the
  heading's TEXT with the number left free, and each asserts how many headings matched and that the
  matched one lands in the frozen complement. *(b)* `docs/CHANGELOG.md` was carved **whole-file** on
  a reason — *a frozen at-a-version list cannot rot* — that is simply false of `[Unreleased]`, the
  section the release in flight is written INTO: a regrown enumeration line under it passed at rc 0
  (measured). It is now split at its first versioned heading, live head IN. *(c)* Stated rather than
  widened, per the ratified rule: leg 3's per-file predicate is three literal spellings of the lib,
  so a vendoring instruction spelled *"the toolkit library file"* is invisible to it — the leg is
  fail-closed over the FILE population and **not** over the spellings, and that bound now sits
  beside the predicate rather than in a claim about the leg.
  **This is a correction to the gate, not a fourth closure of the class, and the count above is
  deliberately left at three:** the third attempt's finding — derive the population, never list it —
  held; what measured wrong was two of the carve-outs subtracted from that population.

- **The value-taking flag population, in ten hand-typed lists** (card#6645) — **SHIPPED.** Stage C
  gave the flag axis one guard (`kb_require_value`, plus the vendored mirrors that cannot source
  the lib). What it did not give the *tests* was one statement of **which flags the guard covers**:
  ten selftest blocks each typed that population out, six of them under an explicit totality claim
  (*"every value-taking flag … the whole class, not one instance"*). A typed list cannot go red
  when the bin grows a flag, so each claim narrowed with every release that added one — and two had
  already lost members when this was measured: `promote-stage-guard-selftest` named **five** of
  `promote-released-cards`' **six** (`--cards`, shipped in v0.26.0, was never driven) and
  `kbcard-selftest` drove **two** of `bin/kbcard`'s **27**. This is Stage B's card#5740 shape one
  axis over: that one deleted the duplicated *helper*, this one deletes the duplicated
  **population**. Closed the same way — `_value_flags` / `expect_value_flags` in
  `tests/_selftest-prelude.sh` derive the population from each bin's own `require_value` /
  `kb_require_value` call sites (both spellings, because the standalone movers carry their own
  copy) and two-way-compare it against what the block names, so neither direction can drift in
  silence; `tests/value-flag-derivation-selftest.sh` is the control on the derivation itself.
  **Weakest property, stated so it is not over-cited:** the predicate keys on the **guard**, so it
  answers *"is every guarded flag accounted for"*, never *"is every value-taking flag guarded"* —
  `agent-board-toolkit-runtime-check`'s `--reference` guards with `"${2:?…}"` and is invisible to
  it, which is the exclusion Stage C already reasons and keeps by design, not a new gap.
- **The three-outcome read, collapsed to two** (card#7210; the roll is #6572 #6594 #6630 #6631
  #6680 #6884 #7174 #6365) — a read has three outcomes, *present* / *absent* / *unreadable*, and a
  site that discards the read's status and then tests the survivor for emptiness has two. The
  unreadable case is scored as a **measured negative** and the claim built on it is stated with the
  confidence of a real one — `fetch_board_cards` answered an unreadable page-1 `2xx` with
  `RC=0 STDOUT=[[]]`, byte-identical to an empty board. Every instance was found by **reading**,
  never by a failure, which is the property that makes instance-fixing insufficient here: **PR #274
  re-minted the shape one commit after its own parent (`b2071b9`) closed it at
  `install-board-hooks`.** That is Stage B's card#5740 lesson a third time — *fixing N copies
  without the guard that forbids the N+1th leaves the cause in place* — so the guard is
  `tests/read-outcome-collapse-selftest.sh`, and it is deliberately **not** a rewrite of the sites
  it lists. It derives its population from the tree on every run (`find bin hooks -maxdepth 1 -type
  f ! -name '*.py'` — the `bin`/`hooks` half of `ci.yml`'s shellcheck expression; `tests/` is a
  stated exclusion, since the harness discards a read's status on purpose), keys members on
  `<file>:<var>` rather than a line number so a disposition does not rot on the next edit above it,
  prints its **denominator** on every run — clean or not — and reds on a member its
  **disposition list** does not carry, one line each with the reason it is permitted. The split
  between the two halves is the point: (a) *the status is discarded* and (b) *the value is later
  tested for emptiness* are both derivable, but **whether that collapse is a defect is not** — it
  depends on what the branch does next, and `fetch_board_cards`' `-z "$data"` refusal and a
  confident wrong count one file over match identically. So the scanner owns the population and the
  list owns the verdict. **Weakest properties, stated so it is not over-cited:** it cannot see a
  collapse that never touches a variable (`if [ -n "$(cmd 2>/dev/null)" ]`), one carried across a
  function boundary, `bin/*.py`, or the bash embedded in this repo's composite actions — **however
  many there are**, a set `tests/composite-action-wiring-selftest.sh` derives from the tree and
  prints on every run, so this exclusion is not re-counted here (it said "the two" while a third
  was landing) — and a disposition is a recorded judgement, not a proof.

- **`<producer> | grep -q <needle>` under `pipefail`** (card#7175) — `grep -q` exits the instant
  it matches, so its producer fails on the closed pipe, `pipefail` promotes **that** status, and the
  `&& echo true || echo false` tail every call site wore reported a **MATCH as `false`** — a wrong
  answer at rc 0, not an error. **47 copies**, 44 of them in `tests/`; 46 migrated to the prelude's
  new `has_line` (a `case` glob with the newline sentinels made explicit — no pipeline, no
  subprocess, so the window structurally cannot exist), the 47th closed independently on `dev` by
  card#6680. Two facts about it were relayed wrong before anyone re-measured, each costing a red:
  the discriminator is **not** builtin-vs-external (bash forks a subshell for a builtin in a
  pipeline and it takes SIGPIPE like anything else — the "a `printf` builtin survives, rc 0 over a
  5 MB body" measurement is *reproducible*, and reproduces only with the match at the **END** of
  the body, where `grep -q` never leaves early); and the dead producer's status is **not 141** —
  that is the rendering where SIGPIPE is at its **default**, while an inherited `SIG_IGN`, which
  the GitHub Actions runner installs, gives an EPIPE write error at **1**. `pipefail` promotes
  either, so the defect is disposition-independent and only the number moves — **a test asserting
  `rc == 141` passes locally and reds in CI**, which is how the correction cost its own cycle.
  **The gate is `tests/piped-match-gate-selftest.sh`**, and it exists because the first cut of
  `pipeline-free-match-selftest.sh` declined it in writing (*"it is not a gate on new ones"*)
  while **two copies survived the audit** — this document's own § Corrections carried forward had
  already ruled that *a copy that survives an audit of its own class is the argument FOR the gate
  that audit declined*, and Stage B's card#5740 section had ruled it once before that. It derives
  its population from the tree every run (`find bin hooks -maxdepth 1 -type f ! -name '*.py'` plus
  `tests/*.sh` — **`tests/` is IN**, unlike `read-outcome-collapse-selftest.sh`, because this class
  minted its red inside the harness), keys members on `<file>` carrying an **occurrence count** so
  that an N+1th copy inside an already-dispositioned file still reds, prints its denominator on
  every run, and carries exactly one disposition: the `_piped*` / `_stat*` fixtures that ARE the
  construct held still so `pipeline-free-match-selftest.sh` can watch it fail. All three red paths
  were watched to fire. **Weakest properties, stated so it is not over-cited:** it cannot see a
  pipeline built as a string and `eval`'d, one whose `grep -q` sits behind a function boundary,
  `bin/*.py`, or the bash in this repo's composite actions — the set
  `tests/composite-action-wiring-selftest.sh` derives and prints, never a count written here.
- **The wider EARLY-EXIT-READER class — `| head`, `| tail -N` — is NOT closed** (card#7175, filed
  here rather than as its own item because this document owns the reasoning and the gate above is
  where a future closure would land). `grep -q` is one early-exiting reader; `head -N` is another,
  and it does the same thing to its producer under `pipefail`. `bin/release-artifacts-check`'s
  two-stage version extraction (`… | grep -oiE "$VERSION_REGEX" | head -1 | grep -oE … | head -1`)
  is a **live member**, held safe by an explicit `|| true` that is documented at the site as a
  SIGPIPE guard rather than defensive tidying. It is not gated, and the reason is a cost decision
  stated rather than a claim of safety: the population is large, and most of it is legitimate
  (a short producer, or a captured value whose emptiness is then tested), so a disposition list
  over it would be mostly noise on this pass. **The number is not written down here** — a written
  count becomes a quoted authority that relays intact across the passes that falsify it; instead
  `piped-match-gate-selftest.sh` **re-derives it every run and prints it in its denominator as an
  explicitly ADVISORY, un-asserted figure**, so the remainder is a number that moves rather than a
  prose figure that rots.
  - **A SECOND live member, found and fixed** (card#6911, appended here rather than filed anew —
    the class already has this owner). `agent-board-toolkit-runtime-check` carried
    `newest="$(git … tag --list 'v*' --sort=-version:refname | head -1)"`, and it is the member that
    breaks the "most of it is legitimate (a short producer …)" reading above: the producer is short
    *today* and is not bounded to stay so. Measured with a planted tag set — **0/40 runs died at 350
    `v*` tags, 21/40 at 400, 16/20 at 5 900, 40/40 at 12 000** — so it is a **RACE at git's ~4 KiB
    stdio buffer**, not a cliff at the 64 KiB pipe buffer, and it dies at rc 141 *before the
    verdict*. Two corrections this instance forces on the class's own reasoning: **`trap '' PIPE`
    does not cover it** (git restores SIGPIPE to `SIG_DFL` for itself, so the parent's ignore is not
    inherited — the fix ratified for the EXTERNAL reader buys nothing against the INTERNAL one), and
    the reachability is not ours to bound, because `$root` there is `git rev-parse --show-toplevel`
    of the tool's own directory, which for a toolkit **vendored inside a consumer repo** is the
    consumer's repo. Fixed in place by taking the first line with a parameter expansion — byte
    identical output, no second process. **Still not gated**, and that cost decision stands
    unchanged; what this member adds is that the advisory figure's "mostly legitimate" gloss is a
    per-instance judgement nobody has made, not a property of the population.

- **A contract-fixed payload key's DECLARED custom-field type is a board precondition that nothing
  in this repo checks — for every key but one** (card#6517). Every write these tools make to a
  contract-fixed key is validated by kanban against that field's **declared type, per board**
  (`CustomFieldValidator::validateValue` dispatches on `$def->type` alone), so the declaration and
  the JSON type the writer emits are two halves of one contract that live in two different places —
  the board, and `_kbc_build_payload`. They can disagree silently, and when they do the board
  rejects **every** write to that key, forever. Two members are known and derivable from the writers
  themselves: **`dl_number` must be `string`** — `kb_dl_canon` renders `DL-NNNN` and a `number`
  field answers `422 Must be a number.` — and **`pr_number` / `issue_number` must be `number`** —
  `_kbc_build_payload`'s `tonumber? // .` coerces them to JSON numbers and a `string` field answers
  `422 Must be a string.` **Only the first is now checked by a program:**
  `dl-a1-register-field` declares `dl_number` correctly and reads the type back on the
  already-registered arm. The second is **prose only** — stated in `docs/INSTALL.md` §3b and
  `examples/kanban-board.env.example`, enforced by nothing — and prose is what card#6517 already
  proved insufficient once. The gap is recorded rather than closed because closing it well is not a
  second copy of the same read: the natural owner is a per-board **precondition check over the whole
  contract-fixed key set** (one read of the field index, one expected-type table derived from the
  writers rather than hand-listed), which is a new surface and a new decision about what it refuses,
  not an edit to the DL setup tool. **What is NOT claimed here:** that the two members above are the
  whole population. `version_target`, `origin`, `pr_url` and `issue_url` were **not** derived — the
  three working installs inspected declare them `string`, `enum`, `string` and `url` respectively,
  which is an observation of what works and not a statement of what is required, and no run of
  anything has tested the alternatives.

- **The `curl` stub that drives `promote-released-cards` end to end, in three selftests**
  (card#8421) — **EXTRACTED at the second real caller; one adoption still owed, and it is a
  DECISION, not a chore.** `bin/promote-released-cards` runs its whole subject at top level in a
  standalone that must not be sourced, so a fake `curl` on `$PATH` is the only way to exercise the
  correlation, the guards, the reports and the exit policy at all — which is why the fixture that
  decides what "the board said" means had already been hand-rolled twice
  (`promote-stage-guard-selftest.sh`, `promote-ref-canon-selftest.sh`) with a third about to land.
  `tests/_promote-curl-stub.sh` now owns it; the stage-guard file and the new
  `promote-source-qualify-selftest.sh` are its two callers, byte-identical stub content.
  ⛔ **`promote-ref-canon-selftest.sh` was deliberately NOT adopted, and the reason is not
  file scope.** Its own stub logs the PATCH **url alone**, and its `moved()` asserts whole-LINE
  equality against that log via the prelude's `has_line`. The shared stub logs `<url>\t<body>` —
  which the stage-guard file needs, since it asserts on the request BODY — so adopting it there
  means rewriting a deliberately strict assertion into a substring one. That is a change to a
  test's STRENGTH, in the file that pins the card#7587 ref-canon rule, and it belongs to whoever
  is willing to argue it on its own. The alternative that costs nothing — a second log channel in
  the shared stub — is worse: two ways to spell one observation is the shape being consolidated.

- **The source-derivation rule, expressed in a FOURTH runtime as jq** (card#8421) — **NOT
  consolidated onto the server, and the reason is what the server ENDPOINT can answer, not
  effort.** `bin/promote-released-cards` mirrors the kanban `ExternalReferenceNormalizer`
  (`sourceFor` / `repoFromGitHubUrl` / `canonicalizeSource`) in jq, alongside the server PHP, the
  bridge PHP and `kanban_common._derive_card_source`. The obvious consolidation is to stop
  mirroring and let the server answer: `GET /boards/{b}/tasks/by-ref.json?system=dl&ref=N&source=
  <repo>` already applies the qualification server-side, and `bin/adopt-to-dl` step-5-verifies
  with exactly that query. **Read live, it cannot produce this tool's report.** Its filter is
  `->where('source', $source)` — a strict equality — so a card whose source is a *different* repo
  and a card whose source is *null* are both simply **absent** from the answer, indistinguishable
  from "no card carries this ref". Those two rows **are** the report: the `⊘` lines are the only
  evidence the guard fired, and the unsourced one is the only thing that tells an operator to
  **stamp** a card rather than mint one. An endpoint that answers the qualification by *deleting*
  the rows the qualification rejected cannot report on them.
  Two further costs, both measured rather than assumed: `external_references` is
  `whenLoaded`-gated on `TaskResource` and `tasks/search.json` eager-loads only
  `lastStageMoveChangelog`, so the **paged board read this tool already makes carries no
  `source` at all** — adopting by-ref means one request per `(system, ref)` in place of one
  paginated scan, and that scan is also where `workflow_stage_id` (idempotence, the
  `--shipped-stages` guard) comes from; and the `--cards` leg correlates on a card's own **id**,
  which is not an external-reference system, so it has no by-ref query in the first place.
  **Revisit if** the by-ref endpoint grows a way to return the rejected rows (an
  `include_unqualified`, or a per-row `source` on the answer), or `tasks/search.json` gains an
  opt-in `external_references` include — the second alone would remove the mirror, because the
  derivation would no longer need re-expressing to read a value the board already handed over.
  The copy is bound BEHAVIOURALLY meanwhile, by `tests/promote-source-qualify-selftest.sh` § 5.
- **The single-card read and its "was anything actually read?" refusal — SEVEN spellings in
  `bin/kbcard`, and they do not agree on what a card IS** (raised as **m7** and again as **m11** in the review of
  card#8545, the `unlink` verb, and reported-not-minted on that card's instruction; the finding
  was EJECTED from card#8556 on purpose — that card's class is *a
  mutating verb reports success it never read back*, and this is duplication, so it had no owner
  until this entry). `_kbc_link_witness` is the sixth and `_kbc_card_witness` — minted by
  card#8556 itself, after this entry was written — is the seventh. The shape every one of them spells is the
  same three steps: `kb_api GET "/tasks/<id>.json"`, pull the card out of the 2xx body with
  `kb_parse_resp`, then test the result for emptiness and refuse with a "nothing was read"
  diagnostic — because a 2xx whose body carries no card is not an empty card, which is this
  program's own *empty vs absent* trap (§ *Diagnosis*, item 1) at the read boundary. **The population, re-derived rather than quoted:**
  `command grep -n 'kb_api\(_status\)\? GET "/tasks/\$' bin/kbcard` returns 7 — `_kbc_patch_tags`,
  `_kbc_link_witness`, `_kbc_card_witness`, `cmd_show`, `cmd_comments`, `_kbc_archive_decision`
  and `_kbc_field_restamp_dl`'s verify loop — plus two more outside this bin that the count
  deliberately excludes (repo-wide the same grep over `bin/` returns 9): `bin/adopt-to-dl`'s and
  `bin/board-card-start`'s, each a different bin with its own refusal vocabulary, and hoisting
  across that boundary is a separate call. Re-run the grep; do not trust the seven.
  ⛔ **THE `kb_api\(_status\)\?` ALTERNATION IS THE LOAD-BEARING PART OF THAT PATTERN, and it is
  here because the narrower one FAILED.** This entry originally derived on `kb_api GET
  "/tasks/\$` — and `_kbc_card_witness`, the seventh spelling, reads through **`kb_api_status`**,
  so the narrow grep returned 6 both before and after the commit that minted it. The trigger this
  entry exists to arm was therefore standing on a count that could not move. An instrument that
  greps a NAME answers about the NAME, and a population derived BEFORE an edit cannot see what
  the edit ADDS: re-run the derivation AFTER writing, not before. The `\$` at the end is equally
  load-bearing in the other direction — dropping it admits `GET "/tasks/search.json` (line 633),
  which is the board search, not a single-card read, and the count silently becomes 8.
  ⚑ **The cost is not the line count, it is that the seven spellings DISAGREE, and the disagreement
  is invisible at every call site.** Five of them qualify the read — `.data | select(type ==
  "object")`, or a projection that can only come off an object — so a 2xx whose `.data` is a
  scalar is refused. **Two take `.data` bare:** `cmd_show`, which hands the result
  straight to `_kbc_annotate_card`, and `_kbc_archive_decision`, which tests only for
  the literal `null` and empty before deciding whether the archive gate may run. Measured, by
  driving `kb_parse_resp` (it is `jq "$@" <<<"$resp" 2>/dev/null || true`) over four bodies:
  `{"data":"a string"}`, `{"data":5}` and `{"data":true}` all yield a NON-EMPTY result through
  the bare spelling and are refused by the guarded one; `{"data":{"id":1}}` passes both. So the
  same malformed body is a refusal in five verbs and a readable card in two — and in
  `_kbc_archive_decision` the two arms are a fail-closed `noprimitive` verdict versus reaching
  the shim, which is this repo's own "empty vs absent" axis re-minted one layer down.
  ⚠ **Reachability is UNMEASURED and is not claimed.** Whether the board ever answers a task GET
  with a non-object `.data` is a property of the server, not of this repo, and nobody has
  observed it. What is measured is the divergence between the spellings, which is the thing a
  hoist would remove; the entry is filed on the duplication, per this section's own bar, not on
  an incident.
  **What a hoist has to carry, which is why this is filed rather than done in passing:** the seven
  refusals are not interchangeable text. They differ in RETURN POSTURE (`return 1` in four;
  `_kbc_archive_decision` prints a tab-separated `noprimitive` verdict and returns 0 so the gate
  fails closed without aborting its caller; the backfill loop pushes onto `unread` and
  `continue`s so one bad row cannot abort a batch; `_kbc_card_witness` returns 1 only for
  UNMEASURED and answers **rc 0 with `{"state":"absent"}` on a 404** — the one spelling of the
  seven for which *the card is not there* is an ANSWER rather than a failure) and in the NOUN the
  diagnostic names ("its links are UNMEASURED", "refusing to replace this card's tags with a list
  built from nothing", "cannot verify archive safety"). A primitive that returns the card and lets
  each caller own its own refusal keeps all four postures; one that owns the refusal too would
  flatten them, and the flattening is exactly what turns `_kbc_archive_decision`'s deliberate
  fail-closed into an abort. **Do NOT collapse the diagnostics** — Stage A's rule that
  consolidating a guard deletes it silently applies here in full.
  ⛔ **AND `_kbc_card_witness` DIFFERS ON THE WIRE, not just in its posture, which is the part a
  hoist would silently lose.** It is the only one of the seven that reads through
  **`kb_api_status`** rather than `kb_api` — because a 404 and a 403 are two different answers
  there and `kb_api` collapses both to rc 1 with `KB_HTTP` stranded in a subshell — and the only
  one that sends **`?trashed=1`**, without which a merely SOFT-deleted card answers 404 exactly as
  a purged one does and a `--hard` read-back reports a DL ref released that is still pinning the
  allocation floor (`docs/DL-COUNTER-RECOVERY.md` § *Why it strands*). A hoist that unified the
  seven on `kb_api GET "/tasks/$id.json"` would be re-minting card#8556's own defect inside the
  primitive built to prevent it. **The seventh is a member of this class, not a duplicate of it:
  it is here to be counted, and it is here with the reason it cannot simply be folded in.**
- **A window measured from a fixture's stamp — the READER shipped twice in one commit, and it is
  now the prelude's** (card#8533, found in review at R1) — **hoisted, not recorded, because the
  second caller is what this document's own rule waits for.** Re-basing three elapsed-time bounds
  off the tool's startup gave `release-tag-check-selftest` and `board-session-close-selftest` the
  same two-line reader — *now minus the epoch second the fixture wrote*, and *is the stamp
  non-empty* — in near-verbatim copies, in a single commit. The WRITERS legitimately differ (a git
  `ext::` remote helper stamping the read it is about to hang; a `/bin/sh` delegate stamping its
  own launch) and are not consolidated; the reader is one behaviour, and it is the half that can
  drift. `_since_stamp` / `_stamp_taken` therefore live in `tests/_selftest-prelude.sh`, per
  § Stage B's binding rule — *a helper used by more than one selftest lives there and is sourced,
  never re-declared* — and `prelude-shadow-selftest.sh`, which derives its helper set FROM the
  prelude, guards the pair from the next run with no edit of its own.
  ⚑ **The two are shipped as a PAIR, and that is the reason they are one entry rather than one
  helper.** An unwritten stamp reads as epoch 0, so `_since_stamp` answers the seconds since 1970
  — a number no bound passes, which reads exactly like the bound firing while the interval it
  names never happened. `_stamp_taken` is the precondition cell that turns that into "the fixture
  was never reached". A future caller taking the measurement without the precondition re-mints the
  wrong-diagnosis half of the defect, so the pairing rule is stated in the prelude beside them
  rather than left to be re-derived.
  ⚠ **"Unwritten" is THREE states, and the reader was total over only two — found at R2, fixed
  before merge.** `date +%s > stamp` opens its redirect *before* it execs `date`, so a fixture
  killed in that window leaves a zero-byte file that EXISTS: `cat` succeeds, prints nothing, and
  the reader's `|| echo 0` never fires. The arithmetic was then `$(( now -  ))` — a syntax error,
  so the READER failed rather than the subject. Driven rather than read, with the hung-read
  fixture made to open its stamp redirect and not reach `date` before the tool's 1s read bound
  expires — the observed regime, reproduced: `release-tag-check-selftest`
  is `set -e` and evaluates `_since_stamp` one cell AHEAD of the `_stamp_taken` cell written to
  diagnose exactly this, so the file aborted there — **44 of its 142 assertions went unrun, with
  no FAIL line and no `_summary`.** Fixed with `${s:-0}` kept *beside* the existing `|| echo 0`
  rather than replacing it, so the absent/unreadable states stay independent of
  `inherit_errexit`. The docblock's stated states now equal the states the code handles: the
  header had been a completeness claim enumerating two of three — this document's own recurring
  defect shape, sitting in a code comment.
  ⚑ **Disposition — the saturation regime this pair now SURFACES is the design working, not a
  residual flake, and is not tracked further.** At artificial CPU saturation the hung-read arm can
  red as `…the read ran <epoch-sized>s from its own start`: read 1 never began inside the tool's
  1s bound, so no stamp exists and the window is measured from epoch 0. The `5`-vs-`10` bound is
  irrelevant to that number — no bound passes it — and `_stamp_taken` reds one cell earlier with
  "the hung read was actually TAKEN" false, which is the pair converting a wrong number into a
  named cause. Recorded so a later reader does not re-open it as a defect in the bound.
  ⛔ **What this does NOT close, stated so it is not over-cited:** `prelude-shadow-selftest.sh`'s
  name leg compares NAMES, and its idiom leg (card#8548) covers function-EXTRACTION anchors only.
  A third selftest that hand-spells `$(( $(date +%s) - $(cat …) ))` inline under no function name
  at all is invisible to both — the same bound that section already states for `has`. The population is a derivation rather than a figure: `command grep -rn 'date +%s'
  tests/` re-runs it, and at this change it answers THREE — the prelude's one reader, plus the
  two fixture WRITERS, which are the deliberately-unconsolidated half. Those two writers are
  also this derivation's positive control: a run that returns none of them is a broken grep, not
  a clean tree.

---

## Corrections carried forward

Claims the review passes disproved. Kept, because a plan that quietly drops its refuted claims
teaches the next reader nothing.

- **"The drift gate cannot fail"** — true only for the content-drift axis; its `MISSING-LIB` leg is
  live. Revision 1 said *replace*; that would have deleted it. → **add, never replace.**
- **"The lib-sourcing-bins list lives in three prose copies"** and **"no fourth copy and no new
  gate"** — both false, and the second followed from the first. The count came from this document's
  own prose instead of from the tree, so `UPGRADE.md` §3 — the standing re-vendor recipe — was
  never in the population and shipped naming six bins against a derived nine. → **a class audit
  re-derives its denominator every pass; a pass that moves the denominator has not converged, and
  a copy that survives an audit of its own class is the argument FOR the gate that audit declined.**
- **"The class is closed, it now carries a gate"** — false as first written, and false the same way
  twice: the gate's own leg 3 was stated over the repo and ran over four hard-coded paths, so the
  lesson directly above it was discharged by an instrument that fixed *its* denominator at four. →
  **the rule binds the INSTRUMENT too: a check written to close a hand-kept-list class must derive
  its own population, or state the bound it actually runs over where the maintainer reads it.** The
  gate's leg 3 now derives; leg 2's four-path list stays and is stated as a floor, not a population.
- **"A stated scope and a measured predicate can be left to agree by inspection"** — false across
  three findings in one pass (this one, the writer census in `bin/gh-code-search`, and the rc
  contract in `README.md` / `docs/CHANGELOG.md`). Each read broader than what it actually tested or
  described, and each was written by the same hand that had just named the defect. → **the claim and
  the predicate are one artifact: widen the predicate to the claim, or narrow the claim to the
  predicate and say so where it is read — never ship them apart.**
- **"Every surface that said `rc 141` is corrected"** (card#7175's own commit message) — false, and
  false in the direction that costs the most: the CODE sites were all migrated and the claim was
  read off that. **Twelve prose copies survived**, two of them forward-looking *predictions* in the
  shipped `bin/release-artifacts-check`, sitting directly above a live `head -1` pipeline held safe
  by an `|| true`. A maintainer hardening that pipeline reads the line, writes an `rc 141`
  assertion, and gets a green local run and a red CI — the identical propagation path this card
  documents, on its third repetition, with the CHANGELOG shipping the correction and the bin
  shipping the error at the same time. → **a doc-sweep is over the CLAIM, not over the files the
  fix touched; "the file was checked" answers about code and must not be relayed as answering
  about text.** (§ Ground rules → Review discipline already required this: *a corrected code-state
  claim is swept across all docs in the same PR*. It was declared done, not performed.)
- **"~28 sibling `printf | grep -q` sites"** — false; the derived figure is **36**. 19 + 9 is
  exactly the two largest files, so a six-occurrence tail across five more files plus two in
  `bin/board-card-start` were never added in. The counts that GATED the work in the same entry
  (47 / 11 / 46 / 1) were *derived* and re-derive exactly; this one was *typed*, in the same
  paragraph, and read as equally load-bearing. → **a figure a reader cannot tell apart from a
  derived one must be derived, or dropped** — and the derivation, not the number, is what belongs
  in the tree (`piped-match-gate-selftest.sh` re-computes its population every run and prints it).
- **"`pipeline-free-match-selftest.sh` … is not a gate on new ones"** — a declined gate, stated in
  the file, while **two copies of the class survived that same audit** inside that same file. The
  ruling directly above ("a copy that survives an audit of its own class is the argument FOR the
  gate that audit declined") and Stage B's card#5740 section had both already settled it. →
  **a control battery and a census are different artifacts; writing "this is only a battery" is a
  statement of scope, never a disposition of the census.** The gate is
  `tests/piped-match-gate-selftest.sh`.
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
