# Changelog

All notable changes to the agent-board-toolkit are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) (pre-1.0: features minor-bump, fixes/refactors/docs patch-bump). See [`../VERSIONING.md`](../VERSIONING.md) for the full policy.

> **This changelog begins at [0.8.2].** Earlier releases (v0.4.x–v0.8.1) predate the changelog and are recorded only as git tags — run `git tag -l 'v*' --sort=-version:refname` and inspect each tag's release commit for their contents. They were not retro-documented here to avoid reconstructing summaries after the fact.

## [Unreleased]

_(empty after each tagged release; accumulates as feature PRs land on dev)_

## [0.14.0] - 2026-07-15

**Minor — a security fix in the `api_base` host guard, plus the restoration of the board-env token precedence that v0.8.2 silently broke.** 2 PRs since v0.13.0 (#98, #97). Cards #4346/#4325.

**Read before upgrading — two consumer-visible changes.** (1) **[vendor]** a repo that vendored `promote-released-cards` **must re-vendor** to get the security fix; the vendored copy carries its own guard and does not track the toolkit. **[release-CI]** SHA-pinned action consumers get it with the pin bump (`promote/action.yml` is unchanged). (2) **[host]** if you set `KBCARD_TOKEN_FILE` in **both** a board env and `~/.kanban-host.env`, the **board's** token now wins where the host's silently did since v0.8.2 — a live change in *which credential is sent*. Full actions: `docs/UPGRADE.md` § v0.14.0.

### Security
- **SECURITY — the `api_base` host guard accepted a URL that sends the bearer token to an attacker-controlled host.** `kb_require_https_host` (`_kb-board-lib.sh`) and its standalone mirror `host_ok` (`promote-released-cards`) terminated the URL authority at **`/` alone**. RFC 3986 ends it at the first of **`/`, `?`, or `#`** — so with a delimiter placed before an `@`, the userinfo strip (`${h##*@}`) reached past it and lifted a fake host out of the query/fragment:

  ```
  api_base: https://evil.example#@kanban.your-host.tld
  guard parses host -> kanban.your-host.tld  -> ACCEPTED
  curl connects to  -> evil.example          -> bearer token sent to the attacker
  ```

  Because `api_base` is read from the **committed, PR-editable** `.release-pr.json`, a pull request alone was enough: for `board-card-start` a maintainer merely checking out the branch leaked their kanban token, and for `promote-released-cards` a repo running promote on untrusted config would leak the `KANBAN_WRITEBACK_TOKEN` CI secret. Neither required any access to `$HOME` or `git config`. Both copies now terminate the authority at `[/?#]`. Verified end-to-end against a listener standing in for the attacker: the pre-fix hook delivered the bearer token, the fixed hook sends nothing and names the real host in its refusal. Legitimate values — subdomains, `:port`, real `user:pw@` userinfo, queries — are unaffected.

  It survived because the guard had **no decision coverage**: it was wired and ran on every checkout, but nothing had ever asked it to judge a hostile URL. New `tests/kb-host-guard-selftest.sh` (+ CI job) pins the matrix and additionally asserts the two copies agree — they are sync-paired by comment only, and both carried the identical defect.

  **[vendor] Action required:** `promote-released-cards` changed, so a repo that **vendored** it must re-vendor (UPGRADE §3) to get the fix. **[release-CI]** consumers of the SHA-pinned composite action get it with the pin bump — `promote/action.yml` itself is unchanged.
### Fixed
- **A board env's `KBCARD_TOKEN_FILE` is honored again — the documented precedence is restored.** `kbcard` honored it from v0.4.2 through v0.8.1 (`v0.8.1:bin/kbcard:440`, *"after host + board env are sourced, so a config-file `KBCARD_TOKEN_FILE` is honored"*). The **v0.8.2 shared-library extraction** consolidated six divergent copies of the config resolution onto the two that had the source order backwards (`next-dl`, `dl-a1-register-field`) and **silently regressed** it: from v0.8.2 through v0.13.0 a board-env `KBCARD_TOKEN_FILE` was ignored and the host/default token was sent to every board. The docs were right; the code drifted. One ladder now serves every tool — **board > host > ambient > `~/.kanban-dev-token`** — as a property of source order (host sourced first, board second) rather than six hand-rolled precedence tests. **Operator-visible where a board env *and* the host env both set `KBCARD_TOKEN_FILE`:** the board's token now wins, changing which credential is sent — see the `docs/UPGRADE.md` v0.14.0 entry.
- **A board env that sets the board-independent `KBCARD_API` is refused, loudly.** Same inverted order, same silence: v0.4.2–v0.8.1 ignored one (as INSTALL.md documented, because `API` was frozen before the board env was sourced), while v0.8.2–v0.13.0 sourced the board env *first* and so silently **honored** it — quietly re-pointing the tool at another host. `kb_resolve_env` now returns rc 4 and names the offending file; `next-dl` no longer swallows that message (it muted stderr, leaving a bare "config incomplete" while losing both the atomic DL claim and the board's `dl_number` seed — the DL-154 re-mint collision class).
- **`board-snapshot` no longer goes dark on a host with no `~/.kanban-dev-token`.** It read one token up-front and `exit 0`'d when that file was missing, so a host using only per-board tokens rendered **nothing**. It now reads each board's token as it renders that board, honoring that board's `KBCARD_TOKEN_FILE`; a board whose token is unreadable reports itself instead of blanking the entire snapshot.
- **`board-card-start` attributes a failed card read to its actual cause.** `get()` used `curl -f`, so an unreachable API, a rejected token (401/403), and a server error were all an empty body — every one reported as **"card … does not exist"**, sending an agent to hunt a missing card instead of a broken token. Each cause is now distinct in the durable diagnostic log. (The status is returned on stdout: `$(get …)` is a subshell, so a global set inside it cannot reach the caller.)

### Changed
- **`board-card-start`: per-board tokens are a host-local opt-in, and `git config kanban.board-id` outranks `.release-pr.json`.** The hook consults a board env's `KBCARD_TOKEN_FILE` **only** when the repo's board id came from the repo-local `git config`; a board id from the committed, PR-editable `.release-pr.json` keeps the host/default token (identical to prior behavior). Reordering the two sources alone would not have closed this — they are documented mutually-exclusive populations, so the inversion only helps the population that never had the exposure; gating the *capability* on the trusted source is the actual fix. The committed value is now digits-validated (`^[0-9]+$`) before it keys a board-env lookup.
- **Reading a board env is now clean-slate** (`kb_board_env_get`): every key is unset before the file is sourced, so a key the file does not set reads as **empty** instead of inheriting whatever is in the environment. Board envs `export` their keys, so in an operator shell that sourced one board's env, that board's values are live for every later tool. Scope, precisely: stage ids are unique to one board, so an inherited id never matches another board's cards — the reachable cases are `board-snapshot` (a board env with no `KB_BOARD_ID` would render a *different* board's cards under this board's label, or abort the subshell under `set -u`) and a board env missing a required stage id (the guard would pass on an inherited value and PATCH a stage that isn't on that board). `board-snapshot` now also says so (`• <label>: (env … sets no KB_BOARD_ID)`) rather than silently rendering nothing.
- **`board-card-start` resolves its board env once**, using it for both the stage ids and the token — the two lookups were separate matchers, free to disagree about which file wins when two board envs claim the same `KB_BOARD_ID`. A duplicate `KB_BOARD_ID` now warns (which file wins is arbitrary either way; being silent about it was the defect), and the stage ids are read newline-delimited so an unset optional `KB_STAGE_HELD` cannot shift another id into its place.
- **`kb_load_host_token`'s `gated`/`unconditional` mode flag is gone**, replaced by `kb_load_host_env`. The two modes differed only because the gate conflated "source the host env" with "let the host's `KBCARD_API` win"; separating those makes one behavior serve both callers. It also fixes the gated bug where a stray ambient `KBCARD_API` skipped the host env entirely, dropping the host's `KBCARD_TOKEN_FILE` — `board-snapshot` was the only `gated` caller, so it was the only tool affected.

### Added
- **`tests/kb-board-lib-selftest.sh` + a CI job** — network-free unit checks for the shared config resolution under a scratch `HOME`: the full token ladder in all four cases, the `KBCARD_API` refusal and its message, the failure return codes, the board-env matcher (no-match, a leaked `KB_BOARD_ID` false-match, duplicates, an unparsable env), and token paths containing spaces. The ladder is a property of source *order*, which is precisely how it regressed unnoticed for five minor versions — nothing exercised it.

## [0.13.0] - 2026-07-14

**Minor — `board-card-start` adoption hardening + Windows/Git-Bash curl portability.** 1 PR since v0.12.2 (#94). No config migration; back-compat (absent-config behavior is identical). Consumer-visible: the token auth mechanism, a new board-id resolution fallback, `core.hooksPath` support, and a durable diagnostic log. Cards #4281/#4289/#4290; correlation roundtable #30/#32/#34.

### Fixed
- **#94** — **Windows/Git-Bash portability: every kanban API call now works on native mingw64 curl.** The bearer token was fed to `curl` via `-H @<(…)` process substitution, which needs a `/dev/fd` named pipe that native mingw64/Git-Bash curl cannot open (rc=26) — so every API call fail-softed. All **8 call-sites** — the shared `_kb-board-lib.sh` (`kb_api`/`kb_api_status`/`fetch_board_cards`), `board-card-start`, `next-dl`, and the standalone `promote-released-cards` — now feed the token via a stdin herestring (`-H @- <<<`), which redirects a regular temp file onto fd 0. This keeps the token out of `argv` (unchanged security property) **and** off persistent disk (bash writes the herestring temp `0600` and unlinks it before exec), and additionally fixes a latent `promote-released-cards --retry` bug (the old process-sub pipe was non-seekable, so a retried request could not re-read the header). Vendored surface: `promote-released-cards` changes an internal auth-feed line, but `promote/action.yml` is unchanged — a SHA-pinned action consumer sees only the internal fix.
- **#94** — **`install-board-hooks` honors `core.hooksPath`.** It hardcoded `<repo>/.git/hooks/post-checkout`; when a repo sets `core.hooksPath` (gitleaks, the pre-commit framework, Husky, many Windows setups) git dispatches hooks only from there, so the install was a silent no-op (symlink created, install reports success, hook never fires). It now installs into `<core.hooksPath>/post-checkout`, and refuses — with operator guidance — a `core.hooksPath` that resolves inside the tracked work tree, where a machine-specific absolute symlink would show as a work-tree change and break on other clones.

### Added
- **#94** — **`board-card-start` resolves its board id without a `.release-pr.json`.** A repo that does not cut releases can bind itself to a board with a repo-local, uncommitted `git config kanban.board-id <id>` — so it adopts the hook without adding a committed, token-adjacent `api_base` surface (the board id is not a secret; `api_base` still resolves from `~/.kanban-host.env`). `.release-pr.json` `promote.board_id` still wins when present (back-compat).
- **#94** — **`board-card-start` durable diagnostic log.** When a branch carries a DL/card token but the move does not happen for an infrastructure reason (no resolvable board id, an unloadable token/host, an untrusted `api_base`, unresolved stage ids, an unreachable board, a named `card#N` that does not exist, or a pinned card), the hook prints the reason and appends it to `~/.cache/agent-board-toolkit/board-card-start.log` (`KB_BCS_LOG` overrides the path) — the installed hook wrapper discards stderr, so the log is the durable record. Still always `exit 0`. Genuine no-ops (no token), already-advanced cards, and the card-id board-scope guard stay silent (no cry-wolf).

### Changed
- **#94** — the host-scrub placeholder detector recognizes the RFC-2606/6761 reserved forms (`.invalid`, `.test`, `.localhost`, the bare `.example` TLD) in addition to `example.{com,net,org}`, each anchored to a host-label boundary so a real host that merely *contains* the substring (e.g. `kanban.latest-corp.com`) is not misread as a placeholder.

## [0.12.2] - 2026-07-14

**Patch — `docs/HOOKS.md` clarifies that un-parking a pinned card is intentionally NOT mirrored by the local hook (docs only; no bin/CI/vendored-surface change).** 1 PR since v0.12.1 (#91).

### Changed
- **#91** — `docs/HOOKS.md`: document that un-parking a pinned card is **owned by the real-time push-path mover, not the local `board-card-start` post-checkout hook**, by design. A push-path mover can override a deliberate pin and promote a pinned card from an opt-in unpark stage set on branch-cut *because it has a durable compensating override-alert surface*; a post-checkout hook's only surface is stderr — effectively silent when an agent drives git, never persisted — so it lacks the durable alert that would make reversing a deliberate pin safe. The local hook therefore keeps refusing pinned cards. Documentation only: `bin/*`, `promote/action.yml`, `examples/*`, and CI are byte-identical to v0.12.1, so a consumer that pins the action or vendors the scripts sees no functional change.

## [0.12.1] - 2026-07-13

**Patch — new agent-facing DL-counter recovery runbook (docs; one comment-only `bin/next-dl` change).** 1 PR since v0.12.0 (#88).

### Added
- **#88** — `docs/DL-COUNTER-RECOVERY.md`: an agent-facing, **API-driven** runbook for recovering a stranded per-board DL counter — the scenario where `next-dl` mints numbers in a far-too-high range because the board's monotonic DL high-water mark was pushed above the real sequence (e.g. by a hard-deleted or trashed high-DL card). Written for an operator/agent who drives a board **over its API token with no server shell**: diagnose (inspect the sequence + list refs), exhaustively sweep every trashed/junk pinner (not just the top one), force-delete each, then reset the counter — mirroring the board's own console recovery path via the board API's DL-sequence inspect/reset endpoints. `README.md` gains an index pointer to the runbook.

### Changed
- **#88** — `bin/next-dl` gains a **comment-only** pointer to the recovery runbook for the "minting far-too-high numbers" symptom. No behavior change — the executable path is byte-identical. `promote/action.yml`, all other `bin/*`, and `examples/*` are byte-identical to v0.12.0, so a consumer that pins the action or vendors the scripts sees no functional change.

## [0.12.0] - 2026-07-12

**Minor — new `bin/adopt-to-dl`: the pull-into-build adoption seam for card-first boards.** 1 PR since v0.11.4 (#85).

### Added
- **#85** — `bin/adopt-to-dl <card-id> --repo <owner/name> --board <name> [--dl N]`: stamps an existing *plain* board card with `payload.dl_number` + a source-qualified placeholder `pr_url` in **one atomic write**, then **fail-loud-verifies** the card resolves via the kanban `by-ref?system=dl&ref=N&source=<repo>` correlation — so a card crosses from manual ownership into the bridge writeback's PR-lifecycle authority with its `source` resolving **at adoption time**, not silently at the next `bridge:check`. Thin orchestration over existing primitives (no write-path reimplementation): `next-dl` mints the DL (atomic server-side claim, echoed to the caller **before** the write so a crash mid-seam is retried with `--dl N`), and `kbcard patch --dl … --pr-url …` performs the single-request `dl_number`+`pr_url` PATCH (kanban per-key payload merge). An **already-adopted guard** refuses to re-mint over a card that already carries a `dl_number` (which would orphan the old DL and strand any branch/PR named for it); `--dl N` re-stamps idempotently for a crash-retry. The by-ref verify **lowercases the source** (the kanban server stores and looks up `source` lowercased), so a mixed-case `--repo` verifies correctly. Sibling bins (`next-dl`, `kbcard`) resolve from the script's own directory, not `$PATH`. Ships with a network-free pure-logic selftest (`tests/adopt-to-dl-selftest.sh`) wired into CI as the `adopt-to-dl-selftest` job; `shellcheck -S error` now also covers `tests/`. `adopt-to-dl` is the write-site adoption seam **for CLI-adopted (card-first) boards** — a board whose `dl_number` is server-derived by a bridge writeback does not need it. It `source`s `bin/_kb-board-lib.sh` (a co-vendored dependency for vendor-by-copy consumers). All other `bin/*`, `promote/action.yml`, and `examples/*` are byte-identical to v0.11.4, so a consumer that pins the action or vendors existing scripts sees only the new bin. Card #4020.

## [0.11.4] - 2026-07-11

**Patch — release-notes reframe to be board/setup-agnostic (docs only; no change to any vendored/shared or CI surface).** 1 PR since v0.11.3 (#82).

### Changed
- **#82** — reframed the v0.11.3 release notes (CHANGELOG entry + recent-releases row) to describe the change and its consumer impact in board/setup-agnostic terms, rather than referencing the maintainer's own board/card specifics. Documentation only — `bin/*`, `promote/action.yml`, `examples/*`, and all CI workflows are byte-identical to v0.11.3, so a consumer that pins the action or vendors the scripts sees nothing new. Card #3895.

## [0.11.3] - 2026-07-11

**Patch — the toolkit dogfoods its own release-promote automation (internal CI only; no change to the vendored/shared surface).** 1 PR since v0.11.2 (#78).

### Added
- **#78** — a `release-promote-cards.yml` workflow in the toolkit's own CI that, on a release main-push, moves the release's shipped tracking cards to the released stage — using the existing (unchanged) `promote-released-cards` script via the local `./promote` composite action, with board/stage/api read from the repo's own `.release-pr.json`. **No change to any vendored/shared file** (`bin/*`, `promote/action.yml`, `examples/*` are byte-identical to v0.11.2), so a consumer that pins the action or vendors the script sees nothing new. Reusable pattern: any consumer can run `promote-released-cards` (or `uses: <owner>/agent-board-toolkit/promote@<sha>`) on their own release, pointed at their own board via their own `.release-pr.json` — the script derives the shipped ref set (DL tokens + PR numbers) from `git log <prev-tag>..HEAD` and moves cards matched by `payload.dl_number`/`pr_number`.

## [0.11.2] - 2026-07-10

**Patch — fail-loud + document `_kb-board-lib.sh` as a required co-vendored dependency of the lib-sourcing bins (card #3894, from a peer integrator).** 1 PR since v0.11.1 (#74).

### Fixed
- **#74** — the 6 bins that `source` the shared `bin/_kb-board-lib.sh` had **no existence guard**, so a vendor-by-copy that omitted the lib died with a raw `source: …/_kb-board-lib.sh: No such file` instead of a message naming the fix. Now: the **5 interactive bins** (`kbcard`, `next-dl`, `board-snapshot`, `dl-a0-backfill-triaged`, `dl-a1-register-field`) fail **loud** (`exit 1` + a self-naming message pointing at INSTALL.md §3 / co-vendoring); **`board-card-start`** (a git post-checkout hook — must never block a checkout) keeps its **soft** `exit 0` but the silent skip now prints a diagnostic to stderr; and **`agent-board-toolkit-drift-check`** grows a **MISSING-LIB probe** (anchored `source "$KB_LIB"` match, so standalone tools — `promote-released-cards`, `release-pr-body`, drift-check itself — are correctly excluded) that fails a lib-sourcing bin vendored without the co-located lib. Docs (ADOPTION.md / INSTALL.md / UPGRADE.md) now state the lib is a required co-vendored dependency of those bins. `promote-released-cards` is deliberately standalone and needs no lib.

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
