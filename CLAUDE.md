# agent-board-toolkit

Repo-specific SME knowledge lives here (add as it accumulates).

## Releasing

Versioning + release process: see [`VERSIONING.md`](VERSIONING.md). Full per-version log: [`docs/CHANGELOG.md`](docs/CHANGELOG.md). Release PRs are cut with the `coord:release-pr` skill; the deterministic body generator + card-promotion tooling read [`.release-pr.json`](.release-pr.json) (board 12).

## Recent releases

Filled in by the release PR that produces each version tag. See [`docs/CHANGELOG.md`](docs/CHANGELOG.md) for the full per-version log.

| Version | Date | Highlights |
| --- | --- | --- |
| v0.9.0 | 2026-07-08 | **`board-transition-sync` RETIRED after the 2026-07-08 rogue-move incident (3 defects, framework-confirmed toolkit-local; bridge writeback supersedes it — operator: remove the PostToolUse hook entry, UPGRADE §6)**; `board-session-close` gains the In-Review-without-open-PR reconcile invariant (#3651 — first run caught 3 stale cards) + the toolkit's own repo in its loops (#55); token-out-of-argv + promote host-guard security fixes (#52), baked host removed / `KANBAN_EXPECTED_HOST` required (#53); UPGRADE.md §6 complete version-by-version actions (#54). |
| v0.8.2 | 2026-07-06 | **Shared board library `bin/_kb-board-lib.sh` (#46)** — the config/API/pagination/DL-canon logic duplicated across 6 `bin` scripts collapsed to one sourced lib (canon #5). **Board reads paginate via `fetch_board_cards` — no silent truncation (#47, DL-A0).** Solo orientation docs (#48). First release under the bridge-parity release infra (`VERSIONING.md` + `docs/CHANGELOG.md` + `.release-pr.json`). |

## Agent Board Framework — solo orientation
@CLAUDE_AGENTBOARD.md
