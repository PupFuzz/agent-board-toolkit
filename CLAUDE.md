# agent-board-toolkit

Repo-specific SME knowledge lives here (add as it accumulates).

## Releasing

Versioning + release process: see [`VERSIONING.md`](VERSIONING.md). Full per-version log: [`docs/CHANGELOG.md`](docs/CHANGELOG.md). Release PRs are cut with the `coord:release-pr` skill; the deterministic body generator + card-promotion tooling read [`.release-pr.json`](.release-pr.json) (board 12).

Recent releases at a glance (last 10, with upgrade actions): [`docs/recent-changes.md`](docs/recent-changes.md) — read it when you need what a recent version changed or what upgrading to it requires.

<!-- `CLAUDE_AGENTBOARD.md` is LOCAL-ONLY and untracked (`.gitignore`): the coord plugin's `coord:init-solo` places it in each agent machine's checkout and its orientation sync keeps it current. A fresh clone has no such file, so this import resolves to nothing there. -->
@CLAUDE_AGENTBOARD.md
