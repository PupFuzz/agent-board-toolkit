# Git hooks — codify "work begun"

A recurring board-drift cause is forgetting to move a card to **In Progress** when work actually starts. This hook removes the manual step: when you check out a feature branch, the correlated card is moved to In Progress automatically.

## What it does

`hooks/post-checkout` → calls `bin/board-card-start`, which:
1. extracts a `DL-NNN` token from the branch name (e.g. `feature/dl156-foo`),
2. finds the board card whose `dl_number` is `DL-NNN` (board id + API base from the repo's `.release-pr.json`; in-progress stage from your `~/.kanban-<name>-board.env`),
3. moves it to In Progress — **only if it's currently in Backlog or Prioritized** (never drags a further-along card backward).

It is **fail-soft** (any missing config / unreachable board / no DL in the branch → it does nothing and never blocks the checkout) and **idempotent**.

## Install (per repo that you cut feature branches in)

```bash
install-board-hooks /path/to/your-repo     # symlinks the hook into .git/hooks; non-destructive
```
Re-run after `git pull`-ing a new toolkit version only if the hook set changed (it's a symlink, so the content tracks the toolkit automatically).

Requirements: the repo has a `.release-pr.json` with `promote.board_id` + `promote.api_base`; you have `~/.kanban-host.env` (or `KBCARD_API`), a token file, and a `~/.kanban-<name>-board.env` whose `KB_BOARD_ID` matches the repo's board. Same config the rest of the toolkit uses (see [INSTALL.md](INSTALL.md)).

## Manual use

```bash
board-card-start                     # current branch
board-card-start feature/dl156-foo   # a specific branch name
```

## Scope / limits

- Correlates on `DL-NNN` only (matches the existing kbcard/writeback convention). A branch with no DL token is a no-op.
- This is the **local** half of the codification. The durable, multi-agent half is the bridge moving the card on the branch-create / first-push webhook (derive-from-artifact) — tracked separately.
