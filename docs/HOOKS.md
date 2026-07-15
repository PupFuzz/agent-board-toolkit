# Git hooks — codify "work begun"

A recurring board-drift cause is forgetting to move a card to **In Progress** when work actually starts. This hook removes the manual step: when you check out a feature branch, the correlated card is moved to In Progress automatically.

## What it does

`hooks/post-checkout` → calls `bin/board-card-start`, which:
1. correlates the branch to a card — **try-in-order-with-fallback** (framework contract #112), on the *outcome* of a token not its presence:
   - a **`DL-NNN`** token (e.g. `feature/dl156-foo`) that **resolves** → the card whose `dl_number` is `DL-NNN` (a co-present card-id token is ignored, loudly); or
   - a `DL-NNN` that resolves to **no card** → **falls through** to a **card-id** token in the same branch (never dead-ends — the unstamped-card class). When the card is selected via the card-id path *and* the branch also named a DL, `payload.dl_number` is **stamped if empty** (never overwriting a differing stamp) so the downstream DL-correlated movers (bridge writeback, release promote) stop no-op'ing on the card; or
   - no `DL-NNN` → a **card-id** token → that card (task) id directly. Recognized as an explicit `card#2950` (the bridge's grammar) / `#2950` / `card-2950` / `card/2950` anywhere, or the leading id of a typed branch (`feat/2950-…`, `fix/2950`, `chore/2950/…`). This covers routine FR/bug work branched by card id *before* a DL exists; or
   - a `DL-NNN` present but resolving to nothing with **no card-id fallback** → a loud no-op (a high-value miss), never silent.
2. resolves the card (board id from a repo-local `git config kanban.board-id`, else the repo's committed `.release-pr.json` `promote.board_id` — the `git config` value wins if both are set; API base from `.release-pr.json` or `~/.kanban-host.env`; in-progress stage from your `~/.kanban-<name>-board.env`), and verifies it is **on the repo's configured board** (so a stray number can't move an unrelated task; this is also the board-scope guard for the card-id fallback),
3. moves it to In Progress — from **Backlog or Prioritized** on any branch checkout, or from **Held** *only on a genuine branch creation* (`git switch -c`; a re-checkout of an existing branch won't un-park a Held card — the re-fire protection). A card already In Progress / In Review / Shipped / Released / Won't-Do is never touched.

A **pinned** card is never auto-moved regardless of stage: a non-empty `block_reason` **or** a `no-automove` tag makes the move refuse (loudly). Held detection uses the branch's reflog creation entry (`branch: Created from …`, ≤ ~15s old, overridable via `KB_HELD_CREATE_MAX_AGE`); a clone or an unparsable/missing reflog is treated as *not* a creation. This implements the cross-mover contract (agent-board-framework PR #113) shared with the bridge's branch-create `started` mover.

**Un-parking a pinned card is bridge-owned (push-path only), by design.** The bridge's `started` mover can *override* a pin and promote a pinned card from an opt-in stage set on a branch-cut (`unpark_from_stages`), emitting a **durable** compensating "overrode a human hold" alert so the override is never silent. This hook deliberately does **not** mirror that override: a `post-checkout` hook's only surface is `stderr` — which is effectively silent when an agent drives `git switch -c` and is never persisted — so it has no durable place to record the override, the property that makes reversing the pin safe. So a locally-cut branch for a pinned card leaves it parked; the bridge un-parks it (from a configured stage, with the alert) once the branch is **pushed**. The pin-refuse above is the *shared* half of the contract; the un-park override is intentionally bridge-only.

It is **fail-soft** (any missing config / unreachable board / no DL-or-card-id token in the branch → it does nothing and never blocks the checkout) and **idempotent**.

## Correlation naming — one token drives the whole lifecycle

Two independent movers advance a card, and **they read different surfaces with different grammars** — so a single naming habit is what makes the *whole* lifecycle auto-move with **zero manual `dl_number` stamping**:

| Mover | Trigger | Reads | Grammar it accepts |
| --- | --- | --- | --- |
| `board-card-start` (this hook) | branch checkout/creation → **In Progress** | the **branch name** | `DL-NNN`, `card#<id>`, `#<id>`, `card-<id>`, or a typed branch's leading id (`feat/<id>-…`) |
| bridge writeback | PR opened/merged → **In Review / Shipped / Released** | the PR **title + head branch** | **only** `DL-NNN` or `card#<id>` (`\bcard#(\d+)\b`) — a bare leading id like `feat/2950-…` does **not** correlate |

The asymmetry is deliberate (the bridge stays strict to avoid mis-correlating version numbers / non-card digits). So the convention that satisfies **both**:

- **Branch:** `<type>/<card-id>-<slug>` (e.g. `feat/2950-widget`). The hook moves the card to In Progress off the leading id; no `#` needed in the ref.
- **PR title:** include **`card#<card-id>`** (e.g. `Add the widget (card#2950)`) — this is the token the bridge matches. Use **`DL-NNN`** in the title instead when the card carries a decision-log id (the bridge prefers a resolving DL, then falls through to `card#` — framework #112).

A bare `#<id>` (e.g. `(#2950)`) in a PR title does **not** match the bridge grammar — write `card#<id>`. With this one habit, a card auto-moves Backlog → In Progress → In Review → Shipped → Released with no `kbcard move` and no manual stamp. (A `board-card-branch` helper that mints the branch and emits the PR-title token is a possible future convenience; the convention above is the load-bearing part.)

## Install (per repo that you cut feature branches in)

```bash
install-board-hooks /path/to/your-repo     # installs the post-checkout hook; non-destructive
```
Re-run after `git pull`-ing a new toolkit version only if the hook set changed (it's a symlink, so the content tracks the toolkit automatically).

The installer **honors `core.hooksPath`**: if the repo sets it (gitleaks, the pre-commit framework, Husky, many Windows setups) git dispatches hooks *only* from there, so the hook is installed into `<core.hooksPath>/post-checkout` — otherwise the install would be a silent no-op. It still refuses to clobber an existing non-symlink hook, and refuses a `core.hooksPath` that resolves **inside the tracked work tree** (a machine-specific absolute symlink there would show as a work-tree change and break on other clones) — guiding you to chain the toolkit hook into your committed hook by hand instead.

Requirements: the repo resolves a **board id** — a repo-local `git config kanban.board-id <id>` (uncommitted; needs no `.release-pr.json`, and so adds no committed `api_base` surface), **or** a `.release-pr.json` with `promote.board_id` (release repos). The `git config` value wins if both are set; in practice they are mutually-exclusive populations. You also have `~/.kanban-host.env`, a token file, and a `~/.kanban-<name>-board.env` whose `KB_BOARD_ID` matches the repo's board. Same config the rest of the toolkit uses (see [INSTALL.md](INSTALL.md)).

**Which token the hook sends.** By default the host-level one: `KBCARD_TOKEN_FILE` from `~/.kanban-host.env`, else `~/.kanban-dev-token`. A board that keeps its token elsewhere sets `KBCARD_TOKEN_FILE` in its **`~/.kanban-<name>-board.env`** — but the hook honors that **only when the repo's board id came from `git config kanban.board-id`**. A board id read from the committed `.release-pr.json` keeps the host/default token, because that file is PR-editable: honoring it would let a pull request re-point the hook at another board's env and send that board's credential. Per-board tokens are therefore a deliberate **host-local opt-in**, invisible to anything committed. (The rest of the toolkit — `kbcard` and friends — has no such restriction; its board comes from a `--board` name you typed, not from a repo file.)

**`~/.kanban-host.env` must export both** (the same setup `kbcard`/`promote-released-cards` use):
- **`KBCARD_API`** — the real kanban api base, e.g. `https://<host>/api/v3`. `board-card-start` reads `promote.api_base` from the committed `.release-pr.json`, but that value is typically a **host-scrubbed reserved placeholder** (`*.example.com`, `.invalid`, `.test`, `.localhost`, or the bare `.example` TLD — RFC-2606/6761) because the real host must not live in a repo — and it is absent entirely for a repo without a `.release-pr.json`. When it detects such a placeholder (or an empty/absent value) it **falls back to `KBCARD_API`** — so the hook reaches the real board with no per-repo config. The detector is anchored to host-label boundaries, so a real host that merely *contains* one of those substrings (e.g. `kanban.latest-corp.com`) is not misread. A genuinely real committed host (a multi-host install that didn't scrub) is used as-is.
- **`KANBAN_EXPECTED_HOST`** — the expected api host (e.g. `<host>`, the host part of `KBCARD_API`). The anti-exfiltration guard refuses to send the writeback token unless the resolved `api_base` host equals this (or is a subdomain of it). Without it set, `board-card-start` fail-softs (loud on stderr **and appended to the diagnostic log**, no move). One host-level setting activates every repo on the machine.

## Manual use

```bash
board-card-start                     # current branch
board-card-start feature/dl156-foo   # a specific branch name
```

## Scope / limits

- Correlates on a `DL-NNN` token (matches the kbcard/writeback convention) **or** a card-id token (`card#2950` / `#2950` / `card-2950` / a typed branch's leading id like `feat/2950-…`), try-in-order-with-fallback: a resolving DL wins; a DL that tracks no card falls through to the card-id token (and stamps `dl_number` on it). A branch with neither token is a no-op. The card-id path only moves a card that lives on the repo's own board.
- **Diagnostics (fail-soft but not silent).** The hook always `exit 0`s (it must never block a checkout), but when a branch carries a DL/card token and the move *didn't* happen for an infrastructure reason — no resolvable board id, an unloadable token/host, an untrusted `api_base`, unresolved stage ids, an unreachable board, a `card#N` that doesn't exist, or a pinned card — it prints a one-line reason to stderr **and appends it to `~/.cache/agent-board-toolkit/board-card-start.log`** (`KB_BCS_LOG` overrides the path). Because the installed hook wrapper discards stderr, that log is the durable record: check it if a card you expected to move didn't. A branch with **no** token, a card already **past** the move stages, or a card-id number that lives on **another** board stays silent — those are genuine no-ops, not failures.
- This is the **local** half of the codification. The durable, multi-agent half is the bridge moving the card on the branch-create / first-push webhook (derive-from-artifact) — tracked separately.
