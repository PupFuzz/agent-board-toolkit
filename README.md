# agent-board-toolkit

Single source of truth for kanban-dev's **bash** board tooling — the CLI + helpers that drive a kanban board from the agent host and from release CI. One versioned copy, consumed by the agent host (via symlink) and by product repos that run a tool in CI (via a drift-checked vendor).

> **Scope.** This is **kanban-dev's** within-runtime code-share (Task-tracking standard §8, move #2): it serves the agent host + the `kanbanboard` and `agent-webhook-bridge` repos. The PM projects (sola/aimla) do **not** consume it — they share board-ops in Python via `coord.kanban_common`. Three-way sharing lives in the **spec** (the standard) and the **v3 API substrate**, not in this code.

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
