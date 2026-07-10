# Changelog

All notable changes to the agent-board-toolkit are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) (pre-1.0: features minor-bump, fixes/refactors/docs patch-bump). See [`../VERSIONING.md`](../VERSIONING.md) for the full policy.

> **This changelog begins at [0.8.2].** Earlier releases (v0.4.x–v0.8.1) predate the changelog and are recorded only as git tags — run `git tag -l 'v*' --sort=-version:refname` and inspect each tag's release commit for their contents. They were not retro-documented here to avoid reconstructing summaries after the fact.

## [Unreleased]

_(empty after each tagged release; accumulates as feature PRs land on dev)_

## [0.11.1] - 2026-07-10

**Patch — `kbcard` + `board-card-start` payload writes rely on the kanban per-key merge; drop the stale wholesale-replace read-merge-write (card #3867).** 2 PRs since v0.11.0 (#70 fix + #69 docs).

### Fixed
- **#70** — `kbcard` (`patch`) and `board-card-start` (the DL-stamp write-site) assumed `PATCH /tasks/{id}.json` replaces `task.payload` **wholesale** and did a read-merge-write of the full payload. That premise is stale: the kanban v3 API **merges `task.payload` per-key** (kanban #2180). Both now PATCH **only the changed keys** — dropping an unnecessary GET (kbcard) and, more importantly, the **lost-update race** #2180 was designed to prevent (a concurrent edit to another custom field between the read and the PATCH was clobbered by the stale full-payload write). `tags` read-merge-write is intentionally **retained** (`tags` is a top-level array with no per-key merge — only `payload` got #2180; same label, opposite correctness). Verified on the prod API: a delta `dl_number` PATCH preserved sibling `pr_number`/`origin`. Card #3867.

### Changed
- **#69** — synced the solo-agent orientation doc (`CLAUDE_AGENTBOARD.md`) to coord v0.2.253 (finish-to-next self-drive guidance). Docs only.

## [0.11.0] - 2026-07-09

**Composite GitHub Action for `promote-released-cards` — GitHub-Actions consumers pin a SHA instead of vendoring a copy.** PR #66 (card #3768).

### Added
- **#66** — `promote/action.yml`: `promote-released-cards` is consumable as a SHA-pinned **composite GitHub Action** (`uses: <owner>/agent-board-toolkit/promote@<sha>  # vX.Y.Z`) — the preferred path for GitHub-Actions consumers (INSTALL.md §6a). Thin wrapper: all logic stays in the script; inputs `writeback-token` / `expected-host` / `api-base` (runtime injection into the checked-out `.release-pr.json`) / `dls` / `dry-run`. Drift becomes impossible rather than detected, presence is guaranteed, and dependabot's `github-actions` ecosystem bumps the pin — replacing the manual re-vendor ritual for these consumers. Vendoring + drift-check (§6b) remains the documented path for non-Actions consumers (PM-project vendors per the §8 amendment). New `promote-action-selftest` CI job guards the wrapper's wiring (embedded shellcheck + fail-closed `uses: ./promote` smoke). Corrects the #2615 Decision #3 consumption model for kanban-dev's own two consumers; consumer-side cutover tracked per repo (kanban DL-195 / bridge DL-180 corrections).

## [0.10.0] - 2026-07-09

**Card-automation restoration — `board-card-start` is revived and hardened.** PRs #58–#63. The post-checkout hook's branch→In-Progress automation was dead on every install; this release fixes the root cause and completes the framework #112/#113 contracts for the local mover. **Operator: `~/.kanban-host.env` must now export `KANBAN_EXPECTED_HOST` for `board-card-start` (see INSTALL.md §3) — one host-level setting activates every repo.**

### Fixed
- **#61** — `board-card-start` falls back to `$KB_API` when the committed `.release-pr.json` `api_base` is a host-scrubbed placeholder (card #3753). The hook read the api base **only** from `.release-pr.json`, which is a scrubbed `*.example.com` placeholder post host-scrub — so it hit a dead host and fail-softed silently, and no card ever auto-moved to In Progress. It now detects the RFC-2606 placeholder and uses the real host it already resolves from `~/.kanban-host.env` (`KBCARD_API`); a genuinely-real committed host is used as-is. Verified live.

### Added / Changed
- **#60** — `board-card-start`: a `DL-NNN` that resolves to no card **falls through** to a card-id token, and **stamps `payload.dl_number`** when selected via card-id with a DL named in the branch (card #3726, framework #112). Closes the dead-end where a decision-logged-but-unstamped card never moved; the card-id regex now also recognizes the bridge's `card#<id>` grammar.
- **#59** — `board-card-start` auto-moves a **Held** card to In Progress on a genuine branch **creation** (reflog-detected, ≤15s), with a `no-automove`/`block_reason` opt-out (framework #113 Held-automove contract, toolkit half).
- **#63** — `docs/HOOKS.md` codifies the **single-token correlation naming convention** (card #3755): branch `<type>/<card-id>-slug` + `card#<id>` (or `DL-NNN`) in the PR title drives both movers with zero manual stamping; flags the bare-`#<id>`-doesn't-match-the-bridge gotcha.
- **#58** — `kbcard`: URL-encode the `resolve_task` query + fail loud on a non-numeric `--external-id` (was silently mis-resolving).

### Fixed (release tooling)
- **#62** — `promote-released-cards` retries transient 5xx (`curl --retry`) to ride the deploy maintenance window (card #3700). Byte-identical to the kanban + bridge vendored copies.

### Changed (dependencies)
- **#23** — `actions/checkout` 6.0.2 → 7.0.0.

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
