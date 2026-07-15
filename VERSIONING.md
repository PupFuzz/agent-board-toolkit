# Versioning policy

How the agent-board-toolkit is versioned, released, and tagged. Mirrors the agent-webhook-bridge and kanban-board projects' process; see [`feedback-git-workflow`](../.claude/projects/-home-kanban/memory/feedback-git-workflow.md) for the operating rule.

## The core rules

1. **Single source of truth for the version:** the [`VERSION`](VERSION) file at the repo root, containing one semver string and a trailing newline. Consumers read it with `tr -d '\n' < VERSION` (or the release tooling's `version_file`/`version_regex` in [`.release-pr.json`](.release-pr.json)).
2. **Version bumps happen on `dev` in a dedicated release PR**, NOT on each feature PR. The bump + CHANGELOG entry is the release act.
3. **Every release tag `v<version>` corresponds to a [`docs/CHANGELOG.md`](docs/CHANGELOG.md) entry** describing the bundle of merged PRs in the release.
4. **Tags are created on `main`, not `dev`, by CI.** After the user merges the release PR (`dev` → `main`), the [`auto-tag-version.yml`](.github/workflows/auto-tag-version.yml) workflow fires on the push to `main`, reads `VERSION`, and tags the merge commit `v<VERSION>` (the tag SHA equals the merge commit's SHA). It is **tag-only** — unlike agent-webhook-bridge's, it does not yet publish a GitHub Release from the CHANGELOG. **Claude does not hand-tag** — the workflow owns it (idempotent; a tag already at a *different* SHA fails loud, meaning the release PR forgot to bump `VERSION`).
5. **Back-merge `main` → `dev` after every release** (`sync/main-to-dev-post-v<version>`) so the branches don't diverge. The user's confirmation that the release PR merged to `main` IS the authorization for the back-merge sync PR — it is opened autonomously and auto-merged on green with a **merge commit** (never squashed — squashing a back-merge breaks the next release PR's diff).

## Branching model

Two long-lived branches: **`main`** (releases only) and **`dev`** (integration). All feature work branches off `dev` and PRs back to `dev`. Only the user merges to `main` (release PRs). Same shape as agent-webhook-bridge and kanban-board, adopted wholesale.

## Bump sizing

The toolkit is pre-1.0. The effective cadence — matching the actual tag history (e.g. v0.8.0 feature → v0.8.1 fix) — is:

- **Patch** (`x.y.Z+1`) — bug fixes, refactors, docs, internal-only changes, no new user-visible surface.
- **Minor** (`x.Y+1.0`) — new user-visible additions (a new `bin/` tool, a new flag, a new capability).
- **Major** (`X+1.0.0`) — reserved for post-1.0 breaking changes to the public CLI/flag surface.

When a release mixes a feature with fixes, lean toward minor; a release that is only fixes/refactors/docs is a patch. When in doubt, state the reasoning in the release PR.

## Release flow

Hybrid policy: ask before opening every PR; auto-merge dev-targeted PRs on green; only the user merges to `main`.

1. **Pick the next version** per the bump-sizing rule above (`tr -d '\n' < VERSION` for the current one).
2. **Feature branch off `dev`:** `release/v<version>`.
3. **Bump `VERSION`** to the new semver.
4. **Update [`docs/CHANGELOG.md`](docs/CHANGELOG.md):** add a `## [X.Y.Z] - YYYY-MM-DD` section (one bullet per bundled PR, Keep-a-Changelog headers) directly under `## [Unreleased]`, keeping `[Unreleased]` empty.
5. **Add a `CLAUDE.md § Recent releases` row** at the top of the table, and **trim the oldest row back to 10**. The table is the ergonomic snapshot and is always truncated to its stated cap; `docs/CHANGELOG.md` (step 4) is the canonical record and is never truncated, so a trimmed row is still fully documented there.
6. **ASK the user** before opening the release PR.
7. Open the release PR `release/v<version>` → **`main`** with full release notes. **CRITICAL: the PR head must be the `release/v<version>` branch, NOT `dev` directly** — a `dev`-headed PR merged with auto-delete-head-branches enabled deletes `dev`.
8. Wait for ALL CI checks (if the repo has CI) to complete + pass. **Claude does NOT `gh pr merge` a `main`-targeted PR** regardless of CI state.
9. **After the user merges to `main` and confirms:** that confirmation authorizes the back-merge sync PR — no separate ask. (On the main-push, `auto-tag-version.yml` mints the `v<VERSION>` tag AND `release-promote-cards.yml` moves board-12 tracking cards to Released — both automatic; Claude does not hand-tag or hand-promote.)
10. Open the back-merge sync PR `sync/main-to-dev-post-v<version>` → `dev`; auto-merge on green with a **merge commit**.

The [`.release-pr.json`](.release-pr.json) config drives the toolkit's own `bin/release-pr-body` generator (deterministic bundled-work list + artifact checklist from git truth; the baseline tag is resolved by **fetching `origin/main`** — the local `main` ref is a release behind by design under this flow (it is never checked out, steps 2–10) and would misreport already-shipped PRs as new; no network → the tool fails loud, with `--base <tag>` as the explicit override) and `bin/promote-released-cards` — invoked by [`release-promote-cards.yml`](.github/workflows/release-promote-cards.yml) on the main-push (via the local `./promote` composite action) to move board-12 tracking cards (matched by their `dl_number`/`pr_number` against the shipped git range) to the released stage.

## Anti-patterns

- **Don't tag a release before doc-sync.** The CHANGELOG entry lands in the same release PR as the version bump.
- **Don't bump the version on a regular feature PR.** Version bumps belong to release events.
- **Don't reuse a tag.** Tags are immutable; if a release is broken, ship `vX.Y.Z+1`.
- **Don't tag `dev`.** Only `main` gets tags.
- **Don't PR `dev` directly to `main`.** Use a disposable `release/v<version>` branch as the PR head (see rule 7).
- **Don't squash a back-merge sync PR** — it breaks the next release PR's diff. Use a merge commit.
