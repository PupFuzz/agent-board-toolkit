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

## The `[Unreleased]` entry rule — every card-carrying PR, not the release

**A PR whose title carries a `card#<id>` token adds a line-initial `- **card#<id>** — …` bullet to `[Unreleased]` in [`docs/CHANGELOG.md`](docs/CHANGELOG.md), in the same PR.** The release (step 4 below) *collects* those bullets; it does not author them. A PR with no `card#` token (a `chore(deps)` bump, a `docs(orientation)` sync) owes nothing.

**Line-initial is the rule, not "the file mentions the card"** — a mention can be prose that misinforms. `docs/CHANGELOG.md` once carried *"card#5374 proposes the selftest…"* inside a different card's entry, written before card#5374 shipped it, so a release cut from that file told the reader the gate was proposed rather than delivered. A PR that folds two cards owes **two** bullets; one bullet naming both discharges only the card it leads with.

This is gated, not conventional: [`tests/changelog-card-entry-selftest.sh`](tests/changelog-card-entry-selftest.sh) (its own [`changelog-card-entry.yml`](.github/workflows/changelog-card-entry.yml) workflow, which subscribes `edited` so a **title edit** re-runs it) derives obligations from the commit subjects since the last release tag **plus the PR title** — under squash-merge the title *is* the coming subject, so the check fires before the merge rather than reddening `dev` after it. Until card#5767 the rule was enforced by nothing and written down nowhere, and 3 of the 24 cards merged since v0.23.1 had no entry.

## Release flow

Hybrid policy: ask before opening every PR; auto-merge dev-targeted PRs on green; only the user merges to `main`.

1. **Pick the next version** per the bump-sizing rule above (`tr -d '\n' < VERSION` for the current one).
2. **Feature branch off `dev`:** `release/v<version>`.
3. **Bump `VERSION`** to the new semver.
4. **Update [`docs/CHANGELOG.md`](docs/CHANGELOG.md):** retitle the accumulated `## [Unreleased]` block as `## [X.Y.Z] - YYYY-MM-DD` and open a fresh, empty `## [Unreleased]` above it. The bullets are already there — each landed with its own PR (see § The `[Unreleased]` entry rule above); this step collects them, and authoring one here means a PR shipped without its entry. Keep the Keep-a-Changelog headers; add only what is genuinely release-level (an upgrade note, a bundling summary).
5. **Add a `CLAUDE.md § Recent releases` row** at the top of the table, and **trim the oldest row back to 10**. The table is the ergonomic snapshot and is always truncated to its stated cap; `docs/CHANGELOG.md` (step 4) is the canonical record and is never truncated, so a trimmed row is still fully documented there.
6. **ASK the user** before opening the release PR.
7. Open the release PR `release/v<version>` → **`main`** with full release notes. **CRITICAL: the PR head must be the `release/v<version>` branch, NOT `dev` directly** — a `dev`-headed PR merged with auto-delete-head-branches enabled deletes `dev`.
8. Wait for ALL CI checks (if the repo has CI) to complete + pass. **Claude does NOT `gh pr merge` a `main`-targeted PR** regardless of CI state.
9. **After the user merges to `main` and confirms:** that confirmation authorizes the back-merge sync PR — no separate ask. (On the main-push, `auto-tag-version.yml` mints the `v<VERSION>` tag AND `release-promote-cards.yml` moves board-12 tracking cards to Released — both automatic; Claude does not hand-tag or hand-promote.)
10. Open the back-merge sync PR `sync/main-to-dev-post-v<version>` → `dev`; auto-merge on green with a **merge commit**.
11. **DEPLOY the release to the host that actually runs the tools. A tag is not a deploy** (the sibling of agent-webhook-bridge's release≠deploy rule — this repo lacked the step entirely until v0.15.0 shipped and the on-PATH runtime silently stayed at v0.14.0):
    ```bash
    # <pinned-runtime> is a SECOND checkout kept deliberately DETACHED at a release tag.
    # Do not run this against a clone that tracks main (docs/INSTALL.md §1 Option A) — and do
    # not relay this line as an upgrade recipe to anyone who has one: `checkout` would convert
    # their self-advancing install into a pin. That topology upgrades with `git pull --ff-only`
    # (docs/UPGRADE.md §2), which lands the identical bits.
    git -C <pinned-runtime> fetch --tags && git -C <pinned-runtime> checkout "v<version>"
    for t in <pinned-runtime>/bin/*; do ln -sf "$t" ~/.local/bin/"$(basename "$t")"; done   # REQUIRED
    hash -r && agent-board-toolkit-runtime-check                                            # must print `ok — … @ v<version>`
    ```
    **Re-running the symlink loop is not optional even on a symlink install:** a symlink tracks its target's *content*, not the *set* of tools — a release that ADDS a bin (v0.12.0 `adopt-to-dl`, v0.15.0 `agent-board-toolkit-runtime-check`) never appears on `PATH` without it. Then **exercise one real command** (`kbcard show --task <id>`), because a green tag is not a working install.
    > **⚠ A release that adds a CHECK must force that check's first run by hand, here.** A guard shipped *in* the artifact it guards cannot bootstrap: v0.15.0's `agent-board-toolkit-runtime-check` exists to catch a stale pin, and a stale pin is exactly what stops it from existing on `PATH` — it was `command not found` on the maintainer's own host while the condition it detects was live. From the next release on, `board-snapshot` surfaces it at every SessionStart (folded to **stdout** — a stderr-only warning is discarded by the hook and the guard would be silently unread).

The [`.release-pr.json`](.release-pr.json) config drives the toolkit's own `bin/release-pr-body` generator (deterministic bundled-work list + artifact checklist from git truth; the baseline tag is resolved by **fetching `origin/main`** — the local `main` ref is a release behind by design under this flow (it is never checked out, steps 2–10) and would misreport already-shipped PRs as new; no network → the tool fails loud, with `--base <tag>` as the explicit override) and `bin/promote-released-cards` — invoked by [`release-promote-cards.yml`](.github/workflows/release-promote-cards.yml) on the main-push (via the local `./promote` composite action) to move board-12 tracking cards (matched by their `dl_number`/`pr_number` against the shipped git range) to the released stage.

Its **`artifacts` array is the must-move-together release set** — steps 3, 4 and 5 above, one entry each — and it is **asserted**, not merely printed: [`release-artifacts-gate.yml`](.github/workflows/release-artifacts-gate.yml) runs `bin/release-artifacts-check` on every PR, and on a release PR (one whose `VERSION` **value** differs from the one at its **fork point**) the check **goes red** if any declared member is absent from the PR's own changes, no longer exists at head, or does not carry the version being shipped. A red check does not by itself prevent a merge — step 8 below ("wait for ALL CI checks to complete + pass") is what makes it binding, and adding the `release-artifacts` job to `main`'s required status checks is what makes it binding mechanically. The range is `merge-base(base, head)..head` rather than base's tip, which is load-bearing on both halves: a commit landing on `main` after the release branch was cut would otherwise make an untouched member look moved, and a version bump arriving on the base branch would make a real release PR read as "version unchanged" and skip the gate entirely. Before this the array was a `- [ ]` checklist in the generated body and nothing else, so a forgotten CHANGELOG heading or `CLAUDE.md` row shipped in silence. A **non**-release PR exits 0 without asserting anything, so the gate costs nothing on ordinary work; the post-merge `auto-tag-version.yml` stays fail-soft by design, because at that point the fix is a retag rather than a commit.

## Anti-patterns

- **Don't tag a release before doc-sync.** The CHANGELOG entry lands in the same release PR as the version bump.
- **Don't bump the version on a regular feature PR.** Version bumps belong to release events.
- **Don't reuse a tag.** Tags are immutable; if a release is broken, ship `vX.Y.Z+1`.
- **Don't tag `dev`.** Only `main` gets tags.
- **Don't PR `dev` directly to `main`.** Use a disposable `release/v<version>` branch as the PR head (see rule 7).
- **Don't squash a back-merge sync PR** — it breaks the next release PR's diff. Use a merge commit.
