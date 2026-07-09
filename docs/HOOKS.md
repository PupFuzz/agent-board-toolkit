# Git hooks — codify "work begun"

A recurring board-drift cause is forgetting to move a card to **In Progress** when work actually starts. This hook removes the manual step: when you check out a feature branch, the correlated card is moved to In Progress automatically.

## What it does

`hooks/post-checkout` → calls `bin/board-card-start`, which:
1. correlates the branch to a card — **try-in-order-with-fallback** (framework contract #112), on the *outcome* of a token not its presence:
   - a **`DL-NNN`** token (e.g. `feature/dl156-foo`) that **resolves** → the card whose `dl_number` is `DL-NNN` (a co-present card-id token is ignored, loudly); or
   - a `DL-NNN` that resolves to **no card** → **falls through** to a **card-id** token in the same branch (never dead-ends — the unstamped-card class). When the card is selected via the card-id path *and* the branch also named a DL, `payload.dl_number` is **stamped if empty** (never overwriting a differing stamp) so the downstream DL-correlated movers (bridge writeback, release promote) stop no-op'ing on the card; or
   - no `DL-NNN` → a **card-id** token → that card (task) id directly. Recognized as an explicit `card#2950` (the bridge's grammar) / `#2950` / `card-2950` / `card/2950` anywhere, or the leading id of a typed branch (`feat/2950-…`, `fix/2950`, `chore/2950/…`). This covers routine FR/bug work branched by card id *before* a DL exists; or
   - a `DL-NNN` present but resolving to nothing with **no card-id fallback** → a loud no-op (a high-value miss), never silent.
2. resolves the card (board id + API base from the repo's `.release-pr.json`; in-progress stage from your `~/.kanban-<name>-board.env`), and verifies it is **on the repo's configured board** (so a stray number can't move an unrelated task; this is also the board-scope guard for the card-id fallback),
3. moves it to In Progress — from **Backlog or Prioritized** on any branch checkout, or from **Held** *only on a genuine branch creation* (`git switch -c`; a re-checkout of an existing branch won't un-park a Held card — the re-fire protection). A card already In Progress / In Review / Shipped / Released / Won't-Do is never touched.

A **pinned** card is never auto-moved regardless of stage: a non-empty `block_reason` **or** a `no-automove` tag makes the move refuse (loudly). Held detection uses the branch's reflog creation entry (`branch: Created from …`, ≤ ~15s old, overridable via `KB_HELD_CREATE_MAX_AGE`); a clone or an unparsable/missing reflog is treated as *not* a creation. This implements the cross-mover contract (agent-board-framework PR #113) shared with the bridge's branch-create `started` mover.

It is **fail-soft** (any missing config / unreachable board / no DL-or-card-id token in the branch → it does nothing and never blocks the checkout) and **idempotent**.

## Install (per repo that you cut feature branches in)

```bash
install-board-hooks /path/to/your-repo     # symlinks the hook into .git/hooks; non-destructive
```
Re-run after `git pull`-ing a new toolkit version only if the hook set changed (it's a symlink, so the content tracks the toolkit automatically).

Requirements: the repo has a `.release-pr.json` with `promote.board_id` (+ `promote.api_base`); you have `~/.kanban-host.env`, a token file, and a `~/.kanban-<name>-board.env` whose `KB_BOARD_ID` matches the repo's board. Same config the rest of the toolkit uses (see [INSTALL.md](INSTALL.md)).

**`~/.kanban-host.env` must export both** (the same setup `kbcard`/`promote-released-cards` use):
- **`KBCARD_API`** — the real kanban api base, e.g. `https://<host>/api/v3`. `board-card-start` reads `promote.api_base` from the committed `.release-pr.json`, but that value is typically a **host-scrubbed RFC-2606 placeholder** (`*.example.com`) because the real host must not live in a repo. When it detects that placeholder (or an empty value) it **falls back to `KBCARD_API`** — so the hook reaches the real board with no per-repo config. A genuinely real committed host (a multi-host install that didn't scrub) is used as-is.
- **`KANBAN_EXPECTED_HOST`** — the expected api host (e.g. `<host>`, the host part of `KBCARD_API`). The anti-exfiltration guard refuses to send the writeback token unless the resolved `api_base` host equals this (or is a subdomain of it). Without it set, `board-card-start` fail-softs (loud on stderr, no move). One host-level setting activates every repo on the machine.

## Manual use

```bash
board-card-start                     # current branch
board-card-start feature/dl156-foo   # a specific branch name
```

## Scope / limits

- Correlates on a `DL-NNN` token (matches the kbcard/writeback convention) **or** a card-id token (`card#2950` / `#2950` / `card-2950` / a typed branch's leading id like `feat/2950-…`), try-in-order-with-fallback: a resolving DL wins; a DL that tracks no card falls through to the card-id token (and stamps `dl_number` on it). A branch with neither token is a no-op. The card-id path only moves a card that lives on the repo's own board.
- This is the **local** half of the codification. The durable, multi-agent half is the bridge moving the card on the branch-create / first-push webhook (derive-from-artifact) — tracked separately.
