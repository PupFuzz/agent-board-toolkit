# agent-board-toolkit

Single source of truth for kanban-dev's **bash** board tooling — the CLI + helpers that drive a kanban board from the agent host and from release CI. One versioned copy, consumed by the agent host (via symlink) and by product repos that run a tool in CI (via a drift-checked vendor).

> **Scope.** This is **kanban-dev's** within-runtime code-share (Task-tracking standard §8): it serves the agent host + the `kanbanboard` and `agent-webhook-bridge` repos. The PM projects' (sola/aimla) *primary* board-ops sharing is Python (`coord.kanban_common`) — but because this is portable `bash` + `curl` + `jq`, a PM project **may also vendor these tools directly** (vendor + drift-check), routing any shared-board need through FRs to this repo, **never a silent fork**. (§8 amended 2026-06-19 at AIMLA PM's request: the original wording *excluded* PM projects, on a cross-runtime-ceiling assumption that doesn't hold for the bash layer.) The canonical three-way shared surface is still the **contract** — the by-ref shape, the `DL-NNN` token, `dl_number`, the writeback outcomes — and the **v3 API substrate**, not this code.

## What's here

| Tool | Role |
|---|---|
| `bin/kbcard` | board CRUD CLI: `create-card` / `move` / `patch` / `list` / `show` / `link` |
| `bin/promote-released-cards` | move a release's shipped cards to the "released" stage (run by release CI) |
| `bin/release-pr-body` | generate the release-PR body/scaffold from repo config |
| `bin/board-snapshot` | session-start board snapshot |
| `bin/board-transition-sync` | reconcile card columns against git/PR state |
| `bin/board-session-close` | session-close board↔git reconcile |
| `bin/next-dl` | next `DL-NNN` number helper |
| `bin/board-card-start` | move a feature branch's correlated card to In Progress (idempotent, fail-soft) |
| `bin/install-board-hooks` | install the `post-checkout` hook into a repo so cards auto-move on branch checkout |
| `bin/agent-board-toolkit-drift-check` | verify a repo's vendored copy of a tool matches this toolkit |

## Configuration model (no IDs are hard-coded; nothing secret is stored in this repo)

The tools read all environment-specific values from files **outside** this repo:

- **`~/.kanban-<name>-board.env`** — board/stage/type/custom-field IDs + API base. One per board. Template: [`examples/kanban-board.env.example`](examples/kanban-board.env.example).
- **`~/.kanban-<name>-token`** — a file containing **only** the bearer token (`chmod 600`, never committed).
- **`<repo>/.release-pr.json`** — per-repo release config (only for repos that cut releases). Template: [`examples/release-pr.json.example`](examples/release-pr.json.example).

## Get started

- **Adopting this for a new project/agent? Start here:** [`ADOPTION.md`](ADOPTION.md) (who it's for + how it fits the cross-project standard)
- **New install:** [`docs/INSTALL.md`](docs/INSTALL.md)
- **Upgrade an existing install:** [`docs/UPGRADE.md`](docs/UPGRADE.md)

## Versioning

`VERSION` holds the toolkit's semver. Upgrades bump it; product repos that vendor a tool record the version they vendored (see UPGRADE.md) so `agent-board-toolkit-drift-check` can flag both *content* drift and *version* skew.
