# Adopting agent-board-toolkit

The front door for an agent (or engineer) adopting this toolkit to drive a kanban board. If you only point a new agent at one file, point it here.

## Where this fits (read first — it's not the shared artifact)

`agent-board-toolkit` is **one project's (kanban-dev's) runtime-specific implementation** of a shared, cross-project task-tracking standard — **not** the shared thing itself. The cross-project sharing lives in two places, neither of which is this code:
- **the standard** (the discipline: one stable intent home, issues-as-source, the correlation convention, the handoff rule), and
- **the kanban v3 API** (shared *behavior* — correlation, by-ref lookup, derived-id — server-side).

Each project implements that standard **in its own runtime**: the Python projects via their own framework/plugin; kanban-dev via this **bash** toolkit. So this repo is the *bash* answer to the shared spec — adopt it if your stack is bash-compatible; otherwise implement the same standard your own way and just share the spec + the API.

> **PM projects may vendor this directly (§8, amended 2026-06-19).** The standard originally scoped this toolkit to kanban-dev only. Because it's portable `bash` + `curl` + `jq`, a PM project (sola/aimla) whose host can run a shell **may vendor these tools** instead of reimplementing them — on the same terms as any consumer: **vendor + drift-check** against this repo, and route any shared-board need (e.g. the atomic DL-claim endpoint) through an **FR to this repo, never a silent fork**. Your *primary* board-ops sharing can still be your own runtime; this is an additional option, not a replacement. **Co-vendored lib:** if you vendor **by copy**, the *lib-sourcing* bins — `kbcard`, `next-dl`, `board-snapshot`, `board-card-start`, `adopt-to-dl`, `dl-a0-backfill-triaged`, `dl-a1-register-field` — **require `bin/_kb-board-lib.sh` copied beside them** (they `source` it as a sibling); `promote-released-cards` / `release-pr-body` are standalone and need no lib. Omitting the lib yields an inscrutable runtime `source: … No such file` — `agent-board-toolkit-drift-check` flags a lib-sourcing bin vendored without the lib.

## Is this for you?

**Adopt it if:** you run on a **bash-capable host** and drive a **kanban board you have API access to** — whether you operate the instance yourself or you're a tenant on someone else's shared instance — and you want one versioned, drift-checked source for the board CLI + release/board helpers instead of loose copies.

**You may not need all of it if:** your project already shares board operations in another runtime (e.g. a Python framework/plugin) — this **bash** tooling doesn't replace that. But you can **vendor the whole toolkit** (§8 amendment above), cherry-pick the runtime-neutral pieces (`promote-released-cards`, `release-pr-body`) — a GitHub-Actions repo can consume the promote step as the SHA-pinned composite action instead of vendoring (INSTALL.md §6a), or just reuse the *patterns* (single-source + drift-check vendoring, the board-independent host-config split). Nothing here depends on a coordination framework.

## Adopt in ~5 minutes (read-only to verify)

```bash
# 1. clone
git clone https://github.com/PupFuzz/agent-board-toolkit.git ~/agent-board-toolkit

# 2. then follow docs/INSTALL.md top to bottom. You supply the three things the
#    toolkit can't know — all live OUTSIDE the repo (no secrets/host in the code):
#    a) your kanban host  -> ~/.kanban-host.env        (KBCARD_API)        [examples/kanban-host.env.example]
#    b) an API token      -> ~/.kanban-<name>-token    (chmod 600)
#    c) your board's IDs  -> ~/.kanban-<name>-board.env (stage/type/cf IDs) [examples/kanban-board.env.example]
#       (the example file documents how to read the IDs from the
#        workflows / card_types / custom_fields endpoints)

# 3. put the tools on PATH (INSTALL.md §2) and verify:
kbcard list --column backlog        # -> your cards (read-only) = install good
```

Full step-by-step, troubleshooting, and the optional "consume a tool from a product repo's CI" paths (composite action §6a / vendor + drift-check §6b): **[`docs/INSTALL.md`](docs/INSTALL.md)**.

## Upgrades

`git pull` (symlink installs) + re-vendor any in-repo copies — **[`docs/UPGRADE.md`](docs/UPGRADE.md)**. `VERSION` is the toolkit's semver.

## What you get (`bin/`)

`kbcard` (board CRUD CLI) · `promote-released-cards` · `release-pr-body` · `board-snapshot` · `board-transition-sync` · `board-session-close` · `next-dl` · `agent-board-toolkit-drift-check`. See [`README.md`](README.md) for the one-line role of each.

## Principles (so you adopt it the way it's meant to work)

- **One source of truth.** Run the tools from this repo (symlink the agent host; drift-check any vendored copy). Don't fork loose copies.
- **Config lives outside the code.** Host/board/token in `~/.kanban-*` files — never committed. The same code runs against any kanban host.
- **The board is the source of truth for state; the tools just drive it.** They read/write the board via its v3 API; they hold no state themselves.
