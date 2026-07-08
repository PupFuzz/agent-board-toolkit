# Changelog

All notable changes to the agent-board-toolkit are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) (pre-1.0: features minor-bump, fixes/refactors/docs patch-bump). See [`../VERSIONING.md`](../VERSIONING.md) for the full policy.

> **This changelog begins at [0.8.2].** Earlier releases (v0.4.x–v0.8.1) predate the changelog and are recorded only as git tags — run `git tag -l 'v*' --sort=-version:refname` and inspect each tag's release commit for their contents. They were not retro-documented here to avoid reconstructing summaries after the fact.

## [Unreleased]

_(empty after each tagged release; accumulates as feature PRs land on dev)_

## [0.9.0] - 2026-07-08

### Removed
- **#55** — `bin/board-transition-sync` retired (#3649). Three defects (whole-command DL grep moving unrelated Released cards on PR-body citations; exact-string match silently inert vs the zero-padded `DL-%04d` canonical form; cross-board first-match on a false uniqueness assumption) — reported upstream, framework-confirmed never-shipped-there. Superseded by the bridge writeback (bridge DL-174 fixed 1:1-board correlation; put the PR's own `DL-NNN` in the title). **Operator action: remove the PostToolUse hook entry** — see UPGRADE §6.

### Added
- **#55** — `board-session-close`: In-Review-without-open-PR reconcile invariant (#3651) — flags any In-Review card whose `pr_number` matches no open PR; first live run caught three cards stale for 2–4 weeks. The toolkit's own repo joined the branch/PR loops.
- **#54** — UPGRADE.md §6: complete version-by-version upgrade actions (v0.4.1 → dev), source-verified per tag.

### Security
- **#52** — writeback bearer token kept out of argv (process-table exposure) + promote `api_base` host validation (#3569/#3570).
- **#53** — baked infra host removed from the shared toolkit; `KANBAN_EXPECTED_HOST` is REQUIRED (fail-closed) for the guarded promote path. **Operator action:** set the repo/org variable — see UPGRADE §3/§6.

### Changed
- **#51** — VERSIONING.md names the auto-tag workflow; stale changelog comment fixed.

## [0.8.2] - 2026-07-06

**Shared board library extraction (`bin/_kb-board-lib.sh`): the config/API/pagination/DL-canon logic duplicated across the toolkit's `bin` scripts is collapsed to one sourced source, plus a silent board-read truncation fix.** PRs #46, #47, #48. **First release under the bridge-parity release infrastructure** (`VERSIONING.md`, `docs/CHANGELOG.md`, `.release-pr.json`, `CLAUDE.md § Recent releases`).

### Changed

- **Extracted `bin/_kb-board-lib.sh` as the single shared board library (#46).** The per-board config load, kanban API client, paginated board read, and DL canonicalization were each reimplemented across `kbcard`, `board-snapshot`, `next-dl`, `dl-a0-backfill-triaged`, `dl-a1-register-field`, and `board-card-start`; the second real caller exists, so per canon #5 the primitive is extracted to one sourced lib. Behavior-preserving.

### Fixed

- **Board reads now paginate via `fetch_board_cards` — no silent truncation (#47, DL-A0).** A single-page board GET silently dropped cards past the first page on a large board; the shared read now follows pagination so a full board is returned, failing loud on a partial read rather than reporting a truncated set as complete.

### Docs

- Agent Board Framework solo orientation (#48).
