# Git hooks — codify "work begun"

A recurring board-drift cause is forgetting to move a card to **In Progress** when work actually starts. This hook removes the manual step: when you check out a feature branch, the correlated card is moved to In Progress automatically.

## What it does

`hooks/post-checkout` → calls `bin/board-card-start`, which:
1. correlates the branch to a card — **try-in-order-with-fallback** (framework contract #112), on the *outcome* of a token not its presence:
   - a **`DL-NNN`** token (e.g. `feature/dl156-foo`) that **resolves** → the card whose `dl_number` is `DL-NNN` (a co-present card-id token is ignored, loudly); or
   - a `DL-NNN` that resolves to **no card** → **falls through** to a **card-id** token in the same branch (never dead-ends — the unstamped-card class). When the card is selected via the card-id path *and* the branch also named a DL, `payload.dl_number` is **stamped if empty** (never overwriting a differing stamp) so the downstream DL-correlated movers (bridge writeback, release promote) stop no-op'ing on the card; or
   - no `DL-NNN` → a **card-id** token → that card (task) id directly. Recognized as an explicit `card2950` / `card-2950` / `card/2950` / `card#2950` (the separator after `card` is **optional** since card-4621, so the natural glued `card2950` spelling correlates too) or a bare `#2950` anywhere, or the leading id of a typed branch (`feat/2950-…`, `fix/2950`, `chore/2950/…`). This covers routine FR/bug work branched by card id *before* a DL exists; or
   - a `DL-NNN` present but resolving to nothing with **no card-id fallback** → a loud no-op (a high-value miss), never silent.
2. resolves the card (board id from a repo-local `git config kanban.board-id`, else the repo's committed `.release-pr.json` `promote.board_id` — the `git config` value wins if both are set; API base from `.release-pr.json` or `~/.kanban-host.env`; in-progress stage from your `~/.kanban-<name>-board.env`), and verifies it is **on the repo's configured board** (so a stray number can't move an unrelated task; this is also the board-scope guard for the card-id fallback),
3. moves it to In Progress — from **Backlog or Prioritized** on any branch checkout, or from **Held** *only on a genuine branch creation* (`git switch -c`; a re-checkout of an existing branch won't un-park a Held card — the re-fire protection). A card already In Progress / In Review / Shipped / Released / Won't-Do is never touched.

A **pinned** card is never auto-moved regardless of stage: a non-empty `block_reason` **or** a `no-automove` tag makes the move refuse (loudly). Held detection uses the branch's reflog creation entry (`branch: Created from …`, ≤ ~15s old, overridable via `KB_HELD_CREATE_MAX_AGE`); a clone or an unparsable/missing reflog is treated as *not* a creation. This implements the cross-mover contract (agent-board-framework PR #113) shared with the bridge's branch-create `started` mover.

**Un-parking a pinned card is bridge-owned (push-path only), by design.** The bridge's `started` mover can *override* a pin and promote a pinned card from an opt-in stage set on a branch-cut (`unpark_from_stages`), emitting a **durable** compensating "overrode a human hold" alert so the override is never silent. This hook deliberately does **not** mirror that override: a `post-checkout` hook's only surface is `stderr` — which is effectively silent when an agent drives `git switch -c` and is never persisted — so it has no durable place to record the override, the property that makes reversing the pin safe. So a locally-cut branch for a pinned card leaves it parked; the bridge un-parks it (from a configured stage, with the alert) once the branch is **pushed**. The pin-refuse above is the *shared* half of the contract; the un-park override is intentionally bridge-only.

It is **fail-soft** (any missing config / unreachable board / no DL-or-card-id token in the branch → it does nothing and never blocks the checkout) and **idempotent**.

## Branch-name advisory (`pre-push`, card-4621)

`hooks/pre-push` → `board-card-start --lint -- <branch>` for each pushed branch. It is a **fail-soft advisory** (it always exits 0 and **never blocks a push**): it warns, on stderr, only when a branch name **looks like** it references a card but in a spelling the auto-move grammar **won't** recognize — so the card would silently never move to In Progress. It reuses the *exact* card-id matcher `board-card-start` moves on (`_bcs_explicit_card_id` / `_bcs_typed_card_id`), so the lint and the mover can never disagree **about the grammar**.

The `--` is load-bearing, not boilerplate. git **accepts** a branch whose name starts with `-` (`git check-ref-format refs/heads/-foo` is rc 0 and `git update-ref` creates it — only the `git branch` *porcelain* refuses the name), and this hook is fed whatever is being pushed. Passed bare, such a name reads as an unknown option and the lint refuses it, while the mover still moves that branch's card — `post-checkout` passes **no** arguments, so it resolves `HEAD` and never enters the argument parser. The shared matchers are what make the two agree on the *grammar*; the **argument surface** is the one place left where they could still disagree, and the terminator is what closes it.

It is deliberately **narrow / high-precision** — it warns only on the residual after the grammar was widened (card-4621): the literal `card`/`#` at a token boundary followed by ≥2 digits through a separator the grammar does *not* accept, e.g. `card_4524` or `card.4524` (the accepted separators are `-`, `/`, `#`, or none). A branch that already correlates (`card-4524`, glued `card4524`, `feat/4524-…`, a `DL-NNN`) is silent, and a branch with no card-ish signal at all (`docs/adoption-guide`) is silent. The suggested fix names the compliant spelling:

```
board-branch-lint: branch 'fix/card_4524-x' looks like it references card 4524, but the board
auto-move grammar won't recognize this spelling — the card will NOT move to In Progress on
checkout. Rename it e.g. 'fix/card-4524-slug' (or 'fix/4524-slug').
```

The advisory becomes effective once the machine's on-PATH `board-card-start` is the version carrying `--lint` (a toolkit deploy, not merely a tag — see VERSIONING.md).

## Agent-dispatch card-start (`hooks/agent-dispatch-card-start`, card-4945)

`post-checkout` only fires when a **branch** is created — but when work is dispatched to a
subagent, the card should move to In Progress at **dispatch time**, not at the later
branch-creation. `hooks/agent-dispatch-card-start` closes that latency window: it is a **Claude
Code `PreToolUse` hook for the `Agent` (subagent-dispatch) tool** that moves a card the moment a
build is dispatched. It is a peer of `post-checkout`, not a replacement — either can fire first;
`kbcard move` is idempotent, so a second move of an already-In-Progress card is a no-op.

### Marker convention (load-bearing — opt-in per dispatch)

The hook acts **only** on an explicit marker line in the dispatch prompt, anchored at line start:

```
BOARD-CARD: <board-key>#<card-id>
```

e.g. `BOARD-CARD: toolkit#4945`. A **bare card-number scan is deliberately NOT used** — review
and report dispatches routinely mention many card ids in prose (`card#1234`, `#91`), so a number
scan would move the wrong cards. The marker must be added on purpose, which makes the behavior
deterministic. Multiple marker lines are each acted on (exact duplicates deduped); a marker
appearing **mid-line** (any non-whitespace before it) is ignored. Leading indentation is
tolerated (the marker may sit inside an indented block). Any line-start occurrence of the marker
fires, including inside quoted or example text in a prompt (worst case: a benign idempotent
In-Progress move) — so avoid quoting live marker lines at column 0 in dispatch prompts.
`<board-key>` is the same key you pass to `kbcard --board <key>` (it resolves `~/.kanban-<key>-board.env`).

`<board-key>` is **ASCII** letters/digits/`_`/`-`, and `<card-id>` is **ASCII** digits — matched
under `LC_ALL=C` regardless of the shell's own locale, because a bash bracket range is a
*collation* range: under an ordinary `en_US.UTF-8` shell an unpinned `[0-9]` also matches
non-ASCII digits, and `BOARD-CARD: toolkit#٣` parsed, sending a non-number to `kbcard move
--task` (card#5409). A marker whose key or id is not ASCII does not parse, in any locale.

### Mechanics

Claude Code delivers the event as a **JSON object on stdin** (never env vars — the event name is
`hook_event_name` in the stdin JSON). For an `Agent`-tool dispatch the prompt is at
`.tool_input.prompt`. The hook parses stdin, scans the prompt for markers, and for each resolved
marker invokes the existing primitive:

```
kbcard --board <key> move --task <card-id> --column in_progress
```

`kbcard` (on PATH at `~/.local/bin`) owns board-env/token resolution — the hook does not hand-roll
`curl`.

### Fail-soft, always

The hook must never block or materially delay a dispatch. It **exits 0 on every path**
(unparseable stdin, no marker, unknown board key, `kbcard` missing, API error), bounds each move
with `timeout` (~10s; `KBADS_TIMEOUT` overrides), and writes a one-line diagnostic to **stderr** on
failure (visible in hook debug, never fatal) — mirroring `post-checkout`'s posture.

### Registration is a MANUAL operator step (not auto-installed)

`bin/install-board-hooks` symlinks **git** hooks; a Claude Code hook lives in Claude Code
**settings.json**, which the installer deliberately does **not** touch (settings.json is
operator-owned config, not a repo-tracked git hook). Register it by hand — add a `PreToolUse`
matcher `"Agent"` entry that runs the script (adjust the absolute path to your toolkit checkout):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/agent-board-toolkit/hooks/agent-dispatch-card-start"
          }
        ]
      }
    ]
  }
}
```

Place it in your user-level `~/.claude/settings.json` (applies to every project) or a project's
`.claude/settings.json`. No other setup is needed — the hook self-resolves boards from your
existing `~/.kanban-<key>-board.env` files.

## Correlation naming — one token drives the whole lifecycle

Two independent movers advance a card, and **they read different surfaces with different grammars** — so a single naming habit is what makes the *whole* lifecycle auto-move with **zero manual `dl_number` stamping**:

| Mover | Trigger | Reads | Grammar it accepts |
| --- | --- | --- | --- |
| `board-card-start` (this hook) | branch checkout/creation → **In Progress** | the **branch name** | `DL-NNN`, `card<id>`/`card-<id>`/`card/<id>`/`card#<id>` (separator optional since card-4621), `#<id>`, or a typed branch's leading id (`feat/<id>-…`) |
| bridge writeback | PR opened/merged → **In Review / Shipped / Released** | the PR **title + head branch** | **only** `DL-NNN`, `card-<id>`, or `card#<id>` (`\bcard[-#](\d+)`, bridge ≥ v0.57.0; older bridges accept only `card#<id>` with a trailing `\b`) — a bare leading id like `feat/2950-…` does **not** correlate |

The residual asymmetry is deliberate (the bridge never correlates a bare leading id, to avoid mis-correlating version numbers / non-card digits). Since bridge **v0.57.0** the `card-<id>` form correlates on **both** movers, so the fleet-ratified convention (roundtable #48) satisfies both with one token:

- **Branch:** `<type>/card-<id>-<slug>` (e.g. `feat/card-2950-widget`). The hook moves the card to In Progress; the same ref later correlates the PR's head branch on the bridge. (The older `<type>/<card-id>-<slug>` bare-id shape still works for the hook, but only the hook — the bridge ignores it.)
- **PR title:** carries the token automatically via the head branch; adding **`card-<card-id>`** (or the older `card#<card-id>`) to the title is belt-and-braces. Use **`DL-NNN`** in the title when the card carries a decision-log id (the bridge prefers a resolving DL, then falls through to the card token — framework #112).

A bare `#<id>` (e.g. `(#2950)`) in a PR title does **not** match the bridge grammar — write `card-<id>` (or `card#<id>`). With this one habit, a card auto-moves Backlog → In Progress → In Review → Shipped → Released with no `kbcard move` and no manual stamp. (A `board-card-branch` helper that mints the branch and emits the PR-title token is a possible future convenience; the convention above is the load-bearing part.)

## Install (per repo that you cut feature branches in)

```bash
install-board-hooks /path/to/your-repo     # installs the post-checkout + pre-push hooks; non-destructive
```
Re-run after `git pull`-ing a new toolkit version only if the hook set changed (it's a symlink, so the content tracks the toolkit automatically — **but on Windows/MSYS/Git-Bash hosts `ln -s` produces copies**, and a copies install goes stale at every toolkit upgrade; see INSTALL.md §2's copy-topology warning). **On that copy topology the re-run needs one extra step:** the installed hook is a regular file, not a symlink, so the installer's refuse-to-clobber guard stops it (`refusing to overwrite an existing non-symlink hook`) — exactly as it would for a hook you wrote yourself, since it cannot tell the two apart. Delete the stale copies first, then re-run:

```bash
rm -f <repo>/.git/hooks/post-checkout <repo>/.git/hooks/pre-push   # only if they are toolkit copies
install-board-hooks <repo>
```

`install-board-hooks --check <repo>` reports what a run would do, and writes nothing.

**A checkout whose git dir is not `<root>/.git` installs into the hooks directory git really dispatches from — except a linked worktree, which is refused and told where to go instead.** Three topologies put the hooks directory outside the work tree, and they need three *different* answers, so there is no single generic message:

| Topology | Where git dispatches hooks from | What the installer does |
| --- | --- | --- |
| **Linked worktree** (`git worktree`) | the **main** checkout's `.git/hooks`, shared by the main checkout and every worktree | **refuses** — run `install-board-hooks <main-checkout>` instead; that wires this worktree too |
| **`--separate-git-dir`** | the separate git dir's `hooks/` | **installs** there, and says so on stderr |
| **Submodule** | `<superproject>/.git/modules/<name>/hooks` | **installs** there, and names the superproject; the superproject's own hooks are untouched |

The split is by **blast radius**, not by "is the git dir elsewhere". A linked worktree's hooks directory is shared with the main checkout *and every sibling worktree*, so installing from one silently changes hook behaviour for checkouts the operator never named — and it is the only one of the three with another checkout to redirect to, which is why it is the only one that prints a command. The other two have exactly **one** work tree each, so the blast radius is precisely the repo you are standing in; they were previously refused on a rationale that does not apply to them.

On both installing topologies the target directory is reported on **stderr**, never stdout: `--check`'s only stdout is the target directory, and other tools consume it. Detection is by **git common dir** (`git rev-parse --git-common-dir` ≠ `<root>/.git`), never by `.git`-is-a-file: all three share that shape. Note that `--git-common-dir` ≠ `--git-dir` is **not** the discriminator — measured on git 2.43, those two differ **only** for a linked worktree; the other two topologies report them equal. The worktree is discriminated instead by whether another checkout's own `.git` *is* this repo's common dir. One primitive (`_ibh_install_dir_source`) owns that disposition, and `board-session-close` asks it rather than modelling it.

The refusal applies only while `core.hooksPath` is **unset**. A set `core.hooksPath` wins on every topology, so a linked worktree that configures one is perfectly installable and is *not* refused. `install-board-hooks --check <path>` reports all of this without writing anything.

The installer **refuses** a `core.hooksPath` that is **set but empty** rather than reporting a success git will not honor (git then dispatches no hooks at all, so installing into `.git/hooks` would be a silent no-op; fix with `git config --unset core.hooksPath`). It carries a matching refusal for a value git **cannot expand**. Which error you see is **git-version-dependent**: on git 2.43.0 such a value is expanded during the general config read, so *every* git command in the repo fatals and you get git's own message from the installer's first probe; on git 2.54.0 `rev-parse` succeeds and only the explicit path read fatals, so you get the installer's refusal. Both paths are live — this was measured in both environments after it had been called unreachable on the strength of one. Otherwise it **honors `core.hooksPath`**: if the repo sets it (gitleaks, the pre-commit framework, Husky, many Windows setups) git dispatches hooks *only* from there, so the hook is installed into `<core.hooksPath>/post-checkout` — otherwise the install would be a silent no-op. It still refuses to clobber an existing non-symlink hook, and refuses a `core.hooksPath` that resolves **inside the tracked work tree** (a machine-specific absolute symlink there would show as a work-tree change and break on other clones) — guiding you to chain the toolkit hook into your committed hook by hand instead.

Requirements: the repo resolves a **board id** — a repo-local `git config kanban.board-id <id>` (uncommitted; needs no `.release-pr.json`, and so adds no committed `api_base` surface), **or** a `.release-pr.json` with `promote.board_id` (release repos). The `git config` value wins if both are set; in practice they are mutually-exclusive populations. You also have `~/.kanban-host.env`, a token file, and a `~/.kanban-<name>-board.env` whose `KB_BOARD_ID` matches the repo's board. Same config the rest of the toolkit uses (see [INSTALL.md](INSTALL.md)).

**Which token the hook sends.** By default the host-level one: `KBCARD_TOKEN_FILE` from `~/.kanban-host.env`, else `~/.kanban-dev-token`. A board that keeps its token elsewhere sets `KBCARD_TOKEN_FILE` in its **`~/.kanban-<name>-board.env`** — but the hook honors that **only when the repo's board id came from `git config kanban.board-id`**. A board id read from the committed `.release-pr.json` keeps the host/default token, because that file is PR-editable: honoring it would let a pull request re-point the hook at another board's env and send that board's credential. Per-board tokens are therefore a deliberate **host-local opt-in**, invisible to anything committed. (The rest of the toolkit — `kbcard` and friends — has no such restriction; its board comes from a `--board` name you typed, not from a repo file.)

**`~/.kanban-host.env` must export both** (the same setup `kbcard`/`promote-released-cards` use):
- **`KBCARD_API`** — the real kanban api base, e.g. `https://<host>/api/v3`. `board-card-start` reads `promote.api_base` from the committed `.release-pr.json`, but that value is typically a **host-scrubbed reserved placeholder** (`*.example.com`, `.invalid`, `.test`, `.localhost`, or the bare `.example` TLD — RFC-2606/6761) because the real host must not live in a repo — and it is absent entirely for a repo without a `.release-pr.json`. When it detects such a placeholder (or an empty/absent value) it **falls back to `KBCARD_API`** — so the hook reaches the real board with no per-repo config. The detector is anchored to host-label boundaries, so a real host that merely *contains* one of those substrings (e.g. `kanban.latest-corp.com`) is not misread. A genuinely real committed host (a multi-host install that didn't scrub) is used as-is.
- **`KANBAN_EXPECTED_HOST`** — the expected api host (e.g. `<host>`, the host part of `KBCARD_API`). The anti-exfiltration guard refuses to send the writeback token unless the resolved `api_base` host equals this (or is a subdomain of it). Without it set, `board-card-start` fail-softs (loud on stderr **and appended to the diagnostic log**, no move). One host-level setting activates every repo on the machine.

## Is the hook still wired? — the dispatch check

A repo can **lose** its hook wiring and nothing routine notices. The failure is silent by construction, from three directions at once:

- `board-card-start` is **fail-soft** by contract (it must never block a checkout), so from the operator's seat a missing hook and a working hook look identical — no error, no output, just a card that never moves.
- A session-close reconcile sees only the **symptom** (a card still sitting in its backlog column) and corrects it as ordinary drift, **masking the cause** — so the wiring can stay dead for an unbounded time while every session ends "clean".
- `agent-board-toolkit-drift-check` compares a repo's **vendored tool copies** against the toolkit. It says nothing about hook wiring, which is host state, not repo content.

So `board-session-close` reports it. Under `── Git hook dispatch ──` it prints one line per local checkout:

```
• some-repo: ✓ post-checkout pre-push dispatch from /path/some-repo/.git/hooks
• other-repo: dispatch dir /path/other-repo/.git/hooks
    ✗ post-checkout: no hook file in the dispatch dir — the card auto-move is DEAD for this repo
    ⚠ pre-push: no hook file in the dispatch dir — the branch-name advisory is off
      fix: install-board-hooks /path/other-repo
```

What it reports per hook: **missing**, a **dangling symlink**, present but **not executable** (git ignores it, saying so only through a suppressible `advice.ignoredHook` hint at the moment of the checkout), present but **not reaching `board-card-start`** (a foreign hook), and — as a lower-severity wiring drift, reported as ⚠ *"it still fires, but from a checkout other than the on-PATH tools'"* rather than as a dead hook — a hook **symlinked into a different toolkit checkout** than the one whose `board-card-start` is on `PATH` (that clone can be mid-edit, on another branch, or removed). A copied hook is *not* flagged as drift: copies are the supported Windows/MSYS topology.

Per **repo** it also reports `core.hooksPath` states that switch dispatch off wholesale — **set but empty** (git dispatches *no* hooks; it does **not** fall back to `.git/hooks`, so a perfectly-wired `.git/hooks` there is never read) and a value **git cannot expand** (`~unknownuser/…`, which fatals every git command in the repo) — and, per **host**, `board-card-start` being **absent from `PATH`**, which makes every `post-checkout` a no-op however it is wired. All three are findings. A path with no checkout is reported as skipped, not as a finding, and the summary always states **how many checkouts were inspected vs skipped**: zero inspected never prints an all-clear.

It resolves the dispatch directory the way **git** does, not the way it is usually assumed — and the assumptions are where the silent no-ops live. It reuses `install-board-hooks`' own reader and resolver (one implementation, not a second copy), so it inherits both `core.hooksPath` behaviours verified against git: the value is read with `--path`, so a leading **`~` is expanded** (git expands it; reading the raw value makes `~/hooks` look like a *relative* path and plants under the work tree), and its **presence is taken from the exit status**, never from the value, because `--get` returns rc 0 with empty output for a set-but-empty value and rc 1 for unset — and those two mean opposite things. The resolver also *accepts* a git **common dir**, and this check supplies the repo's real one so a linked worktree resolves to the main checkout's hooks dir. Where the installer would target is **asked of the installer**, never modelled here: it answers `<root>/.git/hooks` for an ordinary checkout, the real common dir for a `--separate-git-dir` checkout or a submodule, and a refusal for a linked worktree (see *Install* above). Both tools resolve the common dir and the owning main checkout through the installer's own `_ibh_common_dir` / `_ibh_main_checkout`, so they cannot drift apart on which checkout owns a shared hook dir. A check that read `.git/hooks` alone, or that read the value without its status, would reproduce the exact silent no-op the installer was fixed for — reporting a repo healthy on the strength of a hook git never runs.

The remediation line is never guessed. `install-board-hooks <repo>` is printed only when **two** things are established: that the command would *succeed* — asked of the installer itself through its `--check` dry run, which evaluates every precondition it would evaluate for real and writes nothing — and that the directory it would target is the one git *dispatches* from, which `--check` cannot know (the installer can succeed while installing where git never looks). Where a sibling checkout owns the dispatch directory, that path is named instead, proven the same way. Where the installer **refuses**, the refusal is quoted in the installer's own words and no target is invented. Two refusal shapes get different tails, and the difference is load-bearing. Where it refuses a directory it *would otherwise have targeted* — a repo carrying its own committed hook, an unwritable hooks directory, a `core.hooksPath` naming a regular file — you are told to resolve that and re-run, and **no `ln -s` is offered**, since for the clobber case that would tell you to destroy your own hook. Where it refuses the **topology** (a linked worktree) and no sibling checkout can be confirmed either, there is no directory it would target at all, so the manual `ln -s` into the real dispatch directory is offered instead — naming only the hooks that are actually broken. Saying it "would target" something in that case would state a falsehood about a tool that targets nothing.

This is a deliberate structure, not an implementation detail: the earlier version *modelled* the installer's preconditions and proved two of nine, which put a command that exits 1 in front of the most common finding of all.

### What the reach test can and cannot tell you

It **reads** the hook — symlinks followed, `#` comments stripped — and follows one level of chaining. It never *executes* the hook, so its answer is a textual approximation with bounds in **both** directions. They are stated here and in the code because a check whose limits are undisclosed gets trusted past them:

- **Erring toward a false *finding* (safe).** A hook that only mentions `board-card-start` in a comment is reported as not reaching it; the `#` strip also blanks the tail of a line whose earlier text quotes a `#`; a chain target whose **path contains whitespace** is never followed, so `exec "/opt/tk with space/hooks/post-checkout"` dispatches for real while reading as a finding (the match deliberately excludes whitespace — that is what stops it ingesting a line of prose, and widening it would trade this disclosed false-finding for an undisclosed false-OK); and only **absolute, literal** chain targets are followed — a chain written with a variable (`exec "$TOOLKIT/hooks/post-checkout"`) or relative to the work tree (`exec ../toolkit/hooks/post-checkout`) reads as a finding *even though it works*, because resolving the first needs the hook's runtime environment and the second needs git's dispatch-time working directory. The guidance this chain support exists for prints an absolute literal path, so the population these tools generate is covered; a hand-written variant may not be. A chain through a wrapper that is not itself a `hooks/<name>` path likewise reads as a finding.
- **Erring toward a false *OK* (accepted).** A mention inside a **string literal** — `echo "run board-card-start yourself"` — reads as a reach. So does an invocation that is **unreachable at runtime**, most realistically a call sitting after an early `exit 0`, which is how a hook gets "temporarily" disabled. Both have been reproduced against this implementation.

Whether git could **run** the hook at all is a separate question from whether the hook *calls* the tool, and it has a single owner: one predicate answers it for the dispatched hook and for a chained target alike, covering the executable bit, the file type (a directory is `-x` too), the shebang line — read so that a missing trailing newline does not discard the verdict, split on **space and tab, and only those two** (the kernel's separator set; a POSIX `[[:space:]]` class is a superset that also matches CR/VT/NL/FF, and reading it as "the kernel's whitespace rule" is what let that superset ship), so `#!<TAB>/bin/sh` is not called dead — the interpreter's existence and type, and CR/CRLF. That consolidation is deliberate: the property had been computed in three places, and each fact added to it previously had to be added to each place separately, which is how three of them ended up applied to only some.

The three false-OK bounds — the string literal, the unreachable call, and the unjudged shebang argument — are accepted as **not implemented**, not as impossible. Separating a string literal from code needs real shell parsing; for unreachable code, the simplest form — an unconditional top-level `exit 0` before the call — *is* catchable by a pure read, while the general case (conditionals, functions, traps) is decided only by running the hook. The rationale is deliberately **not** stretched to cover anything a pure *read* can catch — which is why **exec-ability is checked rather than disclosed**. The executable bit is not the ability to be exec'd: a hook with **CRLF line endings** or a **missing shebang interpreter** is `-x`, looks perfect, and still makes git fail with `fatal: cannot exec '<hook>': No such file or directory`. Reading the first line catches both, so the check does, on the direct hook **and** on a chained target, reporting it as `NOT-RUNNABLE` / `CHAIN-BROKEN` with the cause named. CRLF is the native hazard of the Windows/MSYS **copy** install topology documented above, so this is a supported-platform failure rather than a hypothetical.

Treat a `✓` as "a hook is wired, is runnable, and textually calls the tool" — not as proof that a card will move. Two more bounds are disclosed rather than detected, both verified against real dispatch:

- **The shebang *argument* is not judged.** `#!/bin/sh zzz` is twelve bytes, reads as runnable, and is **dead** — `/bin/sh` takes `zzz` as a script path and exits `cannot open zzz`, so the hook never runs. `#!/bin/sh -e` is accepted and fires. Telling those apart needs each interpreter's own CLI rather than a read, and `#!/usr/bin/env bash` is a correct hook whose argument is deliberately not a file — so an "does the argument exist?" heuristic would invent findings.
- **An interpreter name that does not *terminate* within the kernel's shebang buffer** (`BINPRM_BUF_SIZE`, 256 bytes on Linux) is truncated there, while the check reads the whole line. On the kernel this was verified against (6.8, git 2.43) `execve` returns `ENOEXEC` and the shell runs the file, so the *named interpreter* is silently ignored — a wrong-interpreter hazard rather than a dead hook, and the truncated remainder can then land in the argument shape above. The effect may differ on other platforms.

Every bound above is pinned by a fixture, so this disclosure and the behaviour cannot drift apart.

**It is report-only.** It never installs, repairs, or touches a repo, and it does **not** change the ritual's exit code (which stays owned by the inverse-drift check) — remediation is your `install-board-hooks <repo-dir>` call, which the output names per finding.

## Manual use

```bash
board-card-start                     # current branch — move the correlated card to In Progress
board-card-start feature/dl156-foo   # a specific branch name
board-card-start --lint <branch>     # advisory only: print the branch-name warning (if any), no move
board-card-start <branch> --lint     # same — the flag is honoured in ANY position
board-card-start -- -foo             # a branch name starting with '-' — after the -- terminator
```

`--lint` is recognised wherever it appears in the argument list, not only first: accepting it only in position 1 meant `board-card-start <branch> --lint` silently dropped it and performed a **real** card move.

`--` ends option parsing: every argument after it is treated as the branch name, however it is spelled. It is there because git accepts a branch name starting with `-` (see the advisory section above), which would otherwise be refused as an unknown option — so `board-card-start -- -foo` and `board-card-start --lint -- -foo` are the way to name one, and `hooks/pre-push` uses that form.

An argument the tool cannot act on is **refused by name, with no move** — an **empty** branch argument (`board-card-start "$BRANCH"` with `BRANCH` unexpanded, which previously retargeted the move to whatever `HEAD` was on), an **unknown option** (its refusal names `--` as the fix), or a **second** positional. Passing **no** branch argument is unchanged and still means "the current branch" — that is how `hooks/post-checkout` calls it. Every one of these refusals prints to **stderr only** — it is deliberately *not* written to the diagnostic log, whose wording asserts a DL/card token an argument refusal has not established — and still **exits 0**: fail-soft is a contract here (see below), so a refusal is a *no-move*, never a non-zero exit. The exit code matters because an operator who **chains** this hook into a committed one carries no `|| true`, and `post-checkout`'s exit status becomes `git switch`/`git checkout`'s own (`githooks(5)`); the installed wrapper's `|| true` covers only the toolkit's own hook.

## Scope / limits

- Correlates on a `DL-NNN` token (matches the kbcard/writeback convention) **or** a card-id token (`card#2950` / `#2950` / `card-2950` / a typed branch's leading id like `feat/2950-…`), try-in-order-with-fallback: a resolving DL wins; a DL that tracks no card falls through to the card-id token (and stamps `dl_number` on it). A branch with neither token is a no-op. The card-id path only moves a card that lives on the repo's own board.
- **Diagnostics (fail-soft but not silent).** The hook always `exit 0`s (it must never block a checkout), but when a branch carries a DL/card token and the move *didn't* happen for an infrastructure reason — no resolvable board id, an unloadable token/host, an untrusted `api_base`, unresolved stage ids, an unreachable board, a `card#N` that doesn't exist, or a pinned card — it prints a one-line reason to stderr **and appends it to `~/.cache/agent-board-toolkit/board-card-start.log`** (`KB_BCS_LOG` overrides the path). Because the installed hook wrapper discards stderr, that log is the durable record: check it if a card you expected to move didn't. A branch with **no** token, a card already **past** the move stages, or a card-id number that lives on **another** board stays silent — those are genuine no-ops, not failures.
- This is the **local** half of the codification. The durable, multi-agent half is the bridge moving the card on the branch-create / first-push webhook (derive-from-artifact) — tracked separately.
