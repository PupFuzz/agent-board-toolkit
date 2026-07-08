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
| `bin/board-session-close` | session-close board↔git reconcile |
| `bin/next-dl` | next `DL-NNN` number — **atomically claims** server-side when the board exposes the DL-sequence endpoint (race-free; DL-157), else offline `max+1`. `--peek` = non-consuming read |
| `bin/board-card-start` | move a feature branch's correlated card to In Progress (idempotent, fail-soft) |
| `bin/install-board-hooks` | install the `post-checkout` hook into a repo so cards auto-move on branch checkout |
| `bin/agent-board-toolkit-drift-check` | verify a repo's vendored copy of a tool matches this toolkit |
| `bin/dl-a1-register-field` | **DL-board setup:** register the `dl_number` custom field + real-surface-verify the `system=dl` by-ref derivation, then fully remove the throwaway (idempotent) — so the toolkit can *stand up* a DL board, not just operate one |
| `bin/dl-a0-backfill-triaged` | **DL-board setup:** backfill the `triaged` tag onto pre-existing `id:*-pr-*` cards (dry-run default; `--apply` / `--remove`), so untriaged-discovery doesn't read the legacy corpus as untriaged |

## Configuration model (no IDs are hard-coded; nothing secret is stored in this repo)

The tools read all environment-specific values from files **outside** this repo:

- **`~/.kanban-<name>-board.env`** — board/stage/type/custom-field IDs + API base. One per board. Template: [`examples/kanban-board.env.example`](examples/kanban-board.env.example).
- **`~/.kanban-<name>-token`** — a file containing **only** the bearer token (`chmod 600`, never committed).
- **`<repo>/.release-pr.json`** — per-repo release config (only for repos that cut releases). Template: [`examples/release-pr.json.example`](examples/release-pr.json.example). **Security-sensitive:** its `.promote.api_base` is the host the release-CI writeback token (`KANBAN_WRITEBACK_TOKEN`) is sent to — a PR that edits `api_base` to an attacker host would exfiltrate the token on the next promote run. `promote-released-cards` / `board-card-start` therefore reject any `api_base` that is not `https://` on the expected host (`$KANBAN_EXPECTED_HOST`) before sending the token. **`KANBAN_EXPECTED_HOST` is REQUIRED — there is no baked default** (this toolkit is vendored onto operators' own kanban hosts, so it assumes none). **Pin `KANBAN_EXPECTED_HOST` in the promote-CI env** as a repo/org variable (out-of-band from the PR-editable config); if it is unset the guard fails closed and refuses to send the token. Treat any `api_base` change in review as a credential-scope change.

## Reliability posture (fail-loud / fail-closed)

The value-emitting tools never silently truncate a board read or emit a garbage value — a partial read that looks "complete" drives wrong reconciles (cards the tool never saw look absent → spurious creates / missed moves), and a garbage value stamped downstream corrupts state.

- **Loud-on-cap pagination.** A board listing that would exceed a page cap **fails loud** (exits non-zero, no partial output) rather than returning a truncated set. The cap is configurable:
  - `BOARD_PAGE_CAP` (default `50`) — `kbcard list`.
  - `PROMOTE_PAGE_CAP` (default `50`) — `promote-released-cards` (refuses to promote on a truncated board read).
  - `next-dl`'s fallback board-max scan refuses to mint when a >200-card board can't be scanned safely (the atomic claim endpoint is the race-free primary path and is unaffected).
- **Fail-closed.** A non-2xx API response → exit non-zero with **empty stdout** (never a partial/garbage value); a non-positive/garbage id is rejected rather than sent. Empty stdout means "do not act."
- **Fail-soft display/hook tools** (`board-snapshot`, `board-card-start`, hooks) stay non-blocking by design (a hook must not abort a checkout), but surface a **loud notice** on a truncated read rather than presenting it as complete.
- **Token never in argv.** Every API call feeds the bearer token to `curl` out-of-band via `-H @<(...)` process substitution, never as a `-H "Authorization: Bearer …"` argv token — so it can't leak via `ps aux` / world-readable `/proc/<pid>/cmdline` on a multi-user host.
- **Fail-closed host guard.** Before the writeback token is sent, the config-supplied `.release-pr.json` `api_base` is validated to be `https://` on the expected host (`$KANBAN_EXPECTED_HOST`, or a subdomain of it); a mismatch **refuses to send the token** (`promote-released-cards` exits non-zero; `board-card-start` warns loudly and stays fail-soft). `KANBAN_EXPECTED_HOST` is **required with no default** — if it is unset/empty the guard also fails closed, so an operator must set it in their promote-CI env for the token ever to be sent.

## Get started

- **Adopting this for a new project/agent? Start here:** [`ADOPTION.md`](ADOPTION.md) (who it's for + how it fits the cross-project standard)
- **New install:** [`docs/INSTALL.md`](docs/INSTALL.md)
- **Upgrade an existing install:** [`docs/UPGRADE.md`](docs/UPGRADE.md)

## Versioning

`VERSION` holds the toolkit's semver. Upgrades bump it; product repos that vendor a tool record the version they vendored (see UPGRADE.md) so `agent-board-toolkit-drift-check` can flag both *content* drift and *version* skew.
