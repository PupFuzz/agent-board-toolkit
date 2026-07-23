# agent-board-toolkit

Single source of truth for kanban-dev's **bash** board tooling — the CLI + helpers that drive a kanban board from the agent host and from release CI. One versioned copy, consumed by the agent host (via symlink) and by product repos that run a tool in CI — GitHub-Actions repos via the SHA-pinned [`promote/`](promote/action.yml) composite action, others via a drift-checked vendor.

> **Scope.** This is **kanban-dev's** within-runtime code-share (Task-tracking standard §8): it serves the agent host + the `kanbanboard` and `agent-webhook-bridge` repos. The PM projects' (sola/aimla) *primary* board-ops sharing is Python (`coord.kanban_common`) — but because this is portable `bash` + `curl` + `jq`, a PM project **may also vendor these tools directly** (vendor + drift-check), routing any shared-board need through FRs to this repo, **never a silent fork**. (§8 amended 2026-06-19 at AIMLA PM's request: the original wording *excluded* PM projects, on a cross-runtime-ceiling assumption that doesn't hold for the bash layer.) The canonical three-way shared surface is still the **contract** — the by-ref shape, the `DL-NNN` token, `dl_number`, the writeback outcomes — and the **v3 API substrate**, not this code.

## What's here

| Tool | Role |
|---|---|
| `bin/kbcard` | board CRUD CLI: `create-card` / `move` / `patch` / `list` / `show` / `link` / `archive` (gated: refuses to archive a card whose backing PR/issue is still live-and-untwinned unless `--force`) / `delete` (`--hard` releases the DL ref) / `field list` (read a board's custom fields + enum option sets) / `field set-options` (idempotent converge-to-set on an enum/multi_select field's options — see [§ `kbcard field`](#kbcard-field--custom-field-schema)) |
| `bin/promote-released-cards` | move a release's shipped cards to the "released" stage (run by release CI) |
| `promote/action.yml` | SHA-pinned composite-action wrapper around `bin/promote-released-cards` for GitHub-Actions consumers (INSTALL.md §6a) |
| `bin/release-pr-body` | generate the release-PR body/scaffold from repo config. **This copy is authoritative** — same as `promote-released-cards`: the toolkit owns both release bins (tests + release discipline live here); the agent-board-framework's `templates/release/` copies are mirrors synced at toolkit tags. Framework-side needs land as toolkit PRs first, never as a fork of the mirror |
| `bin/board-snapshot` | session-start board snapshot |
| `bin/board-session-close` | session-close board↔git reconcile |
| `bin/next-dl` | next `DL-NNN` number — **atomically claims** server-side when the board exposes the DL-sequence endpoint (race-free; DL-157), else offline `max+1`. `--peek` = non-consuming read |
| `bin/board-card-start` | move a feature branch's correlated card to In Progress (idempotent, fail-soft) |
| `bin/adopt-to-dl` | **pull-into-build adoption seam:** stamp an existing plain card with `dl_number` + a source-qualified placeholder `pr_url` in one atomic write (via `next-dl` + `kbcard patch`), then fail-loud-verify by `by-ref?system=dl&ref=N&source=<repo>`. Refuses to re-mint over an already-adopted card (`--dl N` re-stamps idempotently for a crash-retry) |
| `bin/install-board-hooks` | install the `post-checkout` (card auto-move on branch checkout) + `pre-push` (fail-soft branch-name advisory) hooks into a repo |
| `bin/agent-board-toolkit-drift-check` | verify a repo's vendored copy of a tool matches this toolkit |
| `bin/dl-a1-register-field` | **DL-board setup:** register the `dl_number` custom field + real-surface-verify the `system=dl` by-ref derivation, then fully remove the throwaway (idempotent) — so the toolkit can *stand up* a DL board, not just operate one |
| `bin/dl-a0-backfill-triaged` | **DL-board setup:** backfill the `triaged` tag onto pre-existing `id:*-pr-*` cards (dry-run default; `--apply` / `--remove`), so untriaged-discovery doesn't read the legacy corpus as untriaged |

## Configuration model (no IDs are hard-coded; nothing secret is stored in this repo)

The tools read all environment-specific values from files **outside** this repo:

- **`~/.kanban-host.env`** — the **host-level, board-independent** settings every tool reads: `KBCARD_API` (the api base) and `KANBAN_EXPECTED_HOST` (the anti-exfiltration guard's expected host; **required, no default**). Optionally a host-wide `KBCARD_TOKEN_FILE` default. Template: [`examples/kanban-host.env.example`](examples/kanban-host.env.example).
- **`~/.kanban-<name>-board.env`** — board/stage/type/custom-field IDs, and optionally this board's own `KBCARD_TOKEN_FILE`. One per board. **Not the API base** — `KBCARD_API` is host-level, and a board env that sets it is refused (see [`docs/INSTALL.md`](docs/INSTALL.md) §3). Template: [`examples/kanban-board.env.example`](examples/kanban-board.env.example).
- **`~/.kanban-<name>-token`** — a file containing **only** the bearer token (`chmod 600`, never committed). Token precedence: a board env's `KBCARD_TOKEN_FILE` > the host env's > an ambient one > `~/.kanban-dev-token`.
- **`<repo>/.release-pr.json`** — per-repo release config (only for repos that cut releases). Template: [`examples/release-pr.json.example`](examples/release-pr.json.example). **Security-sensitive:** its `.promote.api_base` is the host the release-CI writeback token (`KANBAN_WRITEBACK_TOKEN`) is sent to — a PR that edits `api_base` to an attacker host would exfiltrate the token on the next promote run. `promote-released-cards` / `board-card-start` therefore reject any `api_base` that is not `https://` on the expected host (`$KANBAN_EXPECTED_HOST`) before sending the token. **`KANBAN_EXPECTED_HOST` is REQUIRED — there is no baked default** (this toolkit is vendored onto operators' own kanban hosts, so it assumes none). **Pin `KANBAN_EXPECTED_HOST` in the promote-CI env** as a repo/org variable (out-of-band from the PR-editable config); if it is unset the guard fails closed and refuses to send the token. Treat any `api_base` change in review as a credential-scope change.

## Reliability posture (fail-loud / fail-closed)

The value-emitting tools never silently truncate a board read or emit a garbage value — a partial read that looks "complete" drives wrong reconciles (cards the tool never saw look absent → spurious creates / missed moves), and a garbage value stamped downstream corrupts state.

- **Loud-on-cap pagination.** A board listing that would exceed a page cap **fails loud** (exits non-zero, no partial output) rather than returning a truncated set. The cap is configurable:
  - `BOARD_PAGE_CAP` (default `50`) — `kbcard list`.
  - `PROMOTE_PAGE_CAP` (default `50`) — `promote-released-cards` (refuses to promote on a truncated board read).
  - `next-dl`'s fallback board-max scan refuses to mint when a >200-card board can't be scanned safely (the atomic claim endpoint is the race-free primary path and is unaffected).
- **Fail-closed.** A non-2xx API response → exit non-zero with **empty stdout** (never a partial/garbage value); a non-positive/garbage id is rejected rather than sent. Empty stdout means "do not act."
- **Fail-soft display/hook tools** (`board-snapshot`, `board-card-start`, hooks) stay non-blocking by design (a hook must not abort a checkout), but surface a **loud notice** on a truncated read rather than presenting it as complete.
- **Token never in argv.** Every API call feeds the bearer token to `curl` out-of-band via a stdin herestring (`-H @- <<<…`), never as a `-H "Authorization: Bearer …"` argv token — so it can't leak via `ps aux` / world-readable `/proc/<pid>/cmdline` on a multi-user host. The herestring also redirects a regular temp file onto fd 0 rather than a `/dev/fd` named pipe, so it works on native mingw64/Git-Bash curl (where `-H @<(…)` process substitution fails to open its fd).
- **Fail-closed host guard.** Before the writeback token is sent, the config-supplied `.release-pr.json` `api_base` is validated to be `https://` on the expected host (`$KANBAN_EXPECTED_HOST`, or a subdomain of it); a mismatch **refuses to send the token** (`promote-released-cards` exits non-zero; `board-card-start` warns loudly and stays fail-soft). `KANBAN_EXPECTED_HOST` is **required with no default** — if it is unset/empty the guard also fails closed, so an operator must set it in their promote-CI env for the token ever to be sent.

## `kbcard field` — custom-field schema

Per-board custom fields define which keys a card's `tasks.payload` may carry (an unregistered key 422s on a task write). The `field` verb reads that schema and reconciles enum option sets. Board selection uses the global `--board` flag, like every other `kbcard` verb.

- **`kbcard --board <key> field list`** — list the board's custom fields (`id` / `key` / `label` / `type`); `enum` and `multi_select` fields include their full `{value,label}` option set. Reads the board index (`GET /boards/<id>/custom_fields.json`) — the only field read surface (there is no per-field GET).
- **`kbcard --board <key> field set-options --field <name|id> --options a,b,c`** — an **idempotent converge-to-set** on an `enum`/`multi_select` field's options: after the call the option set equals **exactly** the given comma list, in that order. It reconciles by value (a second call with the same list detects no drift and **skips the PATCH** — a no-op it reports on stderr). Values only; each label defaults to its value (labels for retained values are not preserved across a rewrite). Refuses a non-`enum`/`multi_select` field, empty/duplicate values, and an unresolved `--field` (which then enumerates the board's defined fields). The consumer is a provisioning preflight that calls it with a full derived set and expects any drift to heal in one call.

> **Observed option-removal semantic** (empirically pinned against the sandbox instance, board 1162; stated here and in `--help` because the server behavior is load-bearing for consumers): **removing an option is a definition-only change.** A card still holding a removed value **keeps it verbatim** in `tasks.payload` — the value is orphaned (no longer a defined option) but preserved, **not cleared and not cascaded** — and the removal PATCH is **not rejected** (HTTP 200) even while a card references the dropped value. So `set-options` never mutates card data; converging a field's option set away from a value in use leaves that card's stored value intact (and now undefined). `add-option` / `rename-option` are intentionally not provided (deferred to v2).

## Get started

- **Adopting this for a new project/agent? Start here:** [`ADOPTION.md`](ADOPTION.md) (who it's for + how it fits the cross-project standard)
- **New install:** [`docs/INSTALL.md`](docs/INSTALL.md)
- **Consume from GitHub Actions CI:** the [`promote/`](promote/action.yml) composite action, SHA-pinned — INSTALL.md §6a (preferred over vendoring for Actions consumers; dependabot bumps the pin)
- **Upgrade an existing install:** [`docs/UPGRADE.md`](docs/UPGRADE.md)
- **`next-dl` minting wrong-range numbers?** [`docs/DL-COUNTER-RECOVERY.md`](docs/DL-COUNTER-RECOVERY.md) — recover a stranded per-board DL allocation counter over the API (no server shell)

## Versioning

`VERSION` holds the toolkit's semver. Upgrades bump it; product repos that vendor a tool record the version they vendored (see UPGRADE.md) so `agent-board-toolkit-drift-check` can flag both *content* drift and *version* skew. Composite-action consumers (INSTALL.md §6a) don't vendor — their version is the SHA pin, bumped by dependabot.
