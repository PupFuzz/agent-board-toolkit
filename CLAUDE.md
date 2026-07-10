# agent-board-toolkit

Repo-specific SME knowledge lives here (add as it accumulates).

## Releasing

Versioning + release process: see [`VERSIONING.md`](VERSIONING.md). Full per-version log: [`docs/CHANGELOG.md`](docs/CHANGELOG.md). Release PRs are cut with the `coord:release-pr` skill; the deterministic body generator + card-promotion tooling read [`.release-pr.json`](.release-pr.json) (board 12).

## Recent releases

Filled in by the release PR that produces each version tag. See [`docs/CHANGELOG.md`](docs/CHANGELOG.md) for the full per-version log.

| Version | Date | Highlights |
| --- | --- | --- |
| v0.11.0 | 2026-07-09 | **Composite GitHub Action for `promote-released-cards` (card #3768).** PR #66. GitHub-Actions consumers now `uses: <owner>/agent-board-toolkit/promote@<sha>  # vX.Y.Z` (INSTALL.md §6a) instead of vendoring a copy — drift impossible, presence guaranteed, dependabot bumps the pin. Thin wrapper (all logic stays in `bin/promote-released-cards`); vendoring + drift-check (§6b) retained for non-Actions consumers. New `promote-action-selftest` CI job guards the wrapper. Corrects #2615 Decision #3 for kanban-dev's two consumers; per-repo cutover next (kanban DL-195 / bridge DL-180 corrections). |
| v0.10.0 | 2026-07-09 | **Card-automation restoration — `board-card-start` revived + hardened.** PRs #58–#63. **Operator: `~/.kanban-host.env` must now export `KANBAN_EXPECTED_HOST` for the hook (INSTALL.md §3); one setting activates every repo.** #3753 (#61): the hook's branch→In-Progress automation was dead on every install — it read `api_base` only from the committed `.release-pr.json`, a host-scrubbed `*.example.com` placeholder, so it hit a dead host and fail-softed; now falls back to the real `$KB_API` from `~/.kanban-host.env` (verified live). #3726 (#60): a DL that resolves to no card falls through to a card-id token + stamps `dl_number`, and the card-id regex recognizes the bridge's `card#<id>` grammar (framework #112). #3743 (#59): Held cards auto-move on genuine branch creation, `no-automove`/`block_reason` opt-out (framework #113). #3755 (#63): the single-token correlation naming convention codified in HOOKS.md. #58: `kbcard` URL-encodes the resolve query + fails loud on a non-numeric `--external-id`. #3700 (#62): `promote-released-cards` retries transient 5xx. Plus `actions/checkout` 6→7. |
| v0.9.0 | 2026-07-08 | **`board-transition-sync` RETIRED after the 2026-07-08 rogue-move incident (3 defects, framework-confirmed toolkit-local; bridge writeback supersedes it — operator: remove the PostToolUse hook entry, UPGRADE §6)**; `board-session-close` gains the In-Review-without-open-PR reconcile invariant (#3651 — first run caught 3 stale cards) + the toolkit's own repo in its loops (#55); token-out-of-argv + promote host-guard security fixes (#52), baked host removed / `KANBAN_EXPECTED_HOST` required (#53); UPGRADE.md §6 complete version-by-version actions (#54). |
| v0.8.2 | 2026-07-06 | **Shared board library `bin/_kb-board-lib.sh` (#46)** — the config/API/pagination/DL-canon logic duplicated across 6 `bin` scripts collapsed to one sourced lib (canon #5). **Board reads paginate via `fetch_board_cards` — no silent truncation (#47, DL-A0).** Solo orientation docs (#48). First release under the bridge-parity release infra (`VERSIONING.md` + `docs/CHANGELOG.md` + `.release-pr.json`). |

## Agent Board Framework — solo orientation
@CLAUDE_AGENTBOARD.md
