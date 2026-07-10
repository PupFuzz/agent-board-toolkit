# agent-board-toolkit — new install

Follow top to bottom. Every command is copy-pasteable; placeholders are in `<angle brackets>` or `ALL_CAPS`. Expected output is shown after each verify step.

## 0. Prerequisites

```bash
for c in bash curl jq git gh; do command -v "$c" >/dev/null && echo "ok: $c" || echo "MISSING: $c"; done
```
All must print `ok:`. (`gh` is only needed for tools that touch GitHub, e.g. `release-pr-body`.)

## 1. Get the toolkit

```bash
# Option A — clone (recommended; makes upgrades a `git pull`):
git clone <agent-board-toolkit-remote-url> ~/agent-board-toolkit
# Option B — if you were handed a copy, just place it at ~/agent-board-toolkit
cat ~/agent-board-toolkit/VERSION    # confirm you have it, e.g. -> 0.1.0
```

## 2. Put the tools on your PATH (agent host)

Symlink each tool into a directory already on your `PATH` (e.g. `~/.local/bin`). Symlinks (not copies) keep the host on the single source — upgrades are then just step §1's `git pull`.

```bash
mkdir -p ~/.local/bin
for t in ~/agent-board-toolkit/bin/*; do ln -sf "$t" ~/.local/bin/"$(basename "$t")"; done
hash -r
command -v kbcard    # -> /home/<you>/.local/bin/kbcard  (a symlink into ~/agent-board-toolkit/bin)
```

## 3. Host config (once per host) — REQUIRED

The tools read the API base from `~/.kanban-host.env` (board-independent — one per host, shared by every board on it). `kbcard` **fails fast** if it's missing, so set it first:

```bash
cp ~/agent-board-toolkit/examples/kanban-host.env.example ~/.kanban-host.env
chmod 600 ~/.kanban-host.env
# edit KBCARD_API to point at your kanban host, e.g. https://kanban.example.com/api/v3
# and set KANBAN_EXPECTED_HOST to that host (see below)
```

**Also export `KANBAN_EXPECTED_HOST`** here (the host part of `KBCARD_API`, e.g. `kanban.example.com`). It is the anti-exfiltration guard's expected host — the local `board-card-start` post-checkout hook (and any locally-run `promote-released-cards`) **refuses to send the writeback token** unless the resolved `api_base` host matches it, and there is **no baked default**. Without it, `board-card-start` fail-softs (no card move). This is the local counterpart to the CI-side `KANBAN_EXPECTED_HOST` in §4/§5; one setting here activates card automation for every repo on the host. (CI jobs set it in their own env, not from this file.)

## 3b. Per-board config + token

Each board you manage needs one env file and one token file. The `--board <name>` flag selects `~/.kanban-<name>-board.env`.

```bash
# a) board IDs — copy the template and fill in YOUR board's numeric IDs:
cp ~/agent-board-toolkit/examples/kanban-board.env.example ~/.kanban-<name>-board.env
chmod 600 ~/.kanban-<name>-board.env
# how to find the IDs is documented inline in that file (workflows/card_types/custom_fields endpoints).

# b) token — a file containing ONLY the bearer token (no quotes, no export):
printf '%s' '<YOUR_API_TOKEN>' > ~/.kanban-<name>-token
chmod 600 ~/.kanban-<name>-token

# c) point KBCARD_TOKEN_FILE at this board's token file:
echo 'export KBCARD_TOKEN_FILE="$HOME/.kanban-<name>-token"' >> ~/.kanban-<name>-board.env
```

> `KBCARD_API` is **board-independent** — set it **once** in `~/.kanban-host.env` (§3), not here. The tools resolve it before the board env is sourced, so a `KBCARD_API` placed in a board env file is ignored.

> The default board (no `--board` flag) reads `~/.kanban-dev-board.env` + `~/.kanban-dev-token`. Name your primary board `dev` to use the tools flag-free, or always pass `--board <name>`.

## 4. Per-repo release config (only for repos that cut releases)

`promote-released-cards` and `release-pr-body` read `<repo>/.release-pr.json`:

```bash
cp ~/agent-board-toolkit/examples/release-pr.json.example <your-repo>/.release-pr.json
# edit: set promote.{board_id, released_stage_id, api_base}, ref_token_regex (e.g. "DL-[0-9]+"),
# version_file/version_regex, dev/main branch names, and the artifacts checklist.
jq . <your-repo>/.release-pr.json   # must parse (no trailing commas); remove the "_comment" line if you like
```

> **`.release-pr.json` is security-sensitive.** `.promote.api_base` is the host the release-CI writeback token (`KANBAN_WRITEBACK_TOKEN`) is sent to. A PR that edits `api_base` to an attacker host would exfiltrate the token on the next promote run. `promote-released-cards` (and `board-card-start`) reject any `api_base` that is not `https://` on the **expected host** before sending the token. **`KANBAN_EXPECTED_HOST` is REQUIRED — there is no baked default** (the toolkit ships onto your own kanban host, so it assumes none). Set **`KANBAN_EXPECTED_HOST`** in the promote-CI env (a repo/org variable — out-of-band from this PR-editable file) to your kanban host; the guard accepts that host or a subdomain of it. Leaving it unset makes the guard **fail closed** — the token is never sent. Review any `api_base` change as a credential-scope change.

## 5. Verify (expected output shown)

```bash
kbcard list --column backlog            # -> JSON array of cards (or [] if empty). A non-empty, well-formed
                                        #    result proves token + board IDs + API base are all correct.
kbcard show --task <some-id> | jq .id   # -> the task id echoed back
```
If `kbcard` errors with `HTTP 401` → token wrong/missing. `column '...' is not defined` → a `KB_STAGE_*` id is unset in your env file. A curl/connection error → `KBCARD_API` host wrong.

## 6. (Optional) Consume a tool from a product repo's CI

A repo whose CI runs a toolkit tool (e.g. `release-promote-cards.yml` runs `bin/promote-released-cards`) can't use `~/.local/bin`. Two consumption paths:

### 6a. GitHub Actions consumer — the composite action (preferred)

Consume `promote-released-cards` via the [`promote/`](../promote/action.yml) composite action, SHA-pinned. Drift is impossible (nothing is copied), presence is guaranteed, and dependabot's `github-actions` ecosystem tracks the pin and PRs version bumps — no manual re-vendor ritual.

```yaml
# in the promote job, after checking out the CONSUMER repo with
# fetch-depth: 0 + fetch-tags: true (the script derives the shipped-ref
# range from the consumer's git history; it fail-closes on a shallow clone):
- uses: <owner>/agent-board-toolkit/promote@<full-40-char-SHA>  # vX.Y.Z
  with:
    writeback-token: ${{ secrets.KANBAN_WRITEBACK_TOKEN }}
    expected-host: ${{ vars.KANBAN_EXPECTED_HOST }}
    api-base: ${{ vars.KANBAN_API_BASE }}   # injected into the checked-out .release-pr.json when the committed value is a placeholder
    dls: ${{ github.event.inputs.dls }}         # optional workflow_dispatch passthrough
    dry-run: ${{ github.event.inputs.dry_run }} # optional workflow_dispatch passthrough
```

Pin by **full 40-char SHA with the `# vX.Y.Z` comment** (the comment is what dependabot parses). The consumer repo still needs its own `.release-pr.json` (§4) and unset-guards for the two repo variables if it wants friendlier errors than the script's own fail-closed ones.

### 6b. Non-Actions consumer — vendor + drift-check

For CI that can't `uses:` a GitHub action (or a project that prefers one literal copy — e.g. PM-project vendors per the Task-tracking standard §8 amendment — see [`ADOPTION.md`](../ADOPTION.md)), vendor the script **into the repo** and record the version, then let CI guard drift:

```bash
mkdir -p <repo>/bin
cp ~/agent-board-toolkit/bin/promote-released-cards <repo>/bin/promote-released-cards
cat ~/agent-board-toolkit/VERSION > <repo>/.agent-board-toolkit-version    # record what you vendored
# add a CI step (or pre-commit) that fails on drift:
~/agent-board-toolkit/bin/agent-board-toolkit-drift-check ~/agent-board-toolkit <repo>   # -> "drift-check: OK"
```

**Both paths** require **`KANBAN_EXPECTED_HOST`** — §6a supplies it via the `expected-host` **input** (step-level env overrides job env, so setting it only as job env does NOT reach the action's script; pin it as a repo variable and pass it through), §6b sets it in the CI job's env (alongside `KANBAN_WRITEBACK_TOKEN`). It pins the host `promote-released-cards` will send the token to, out-of-band from the PR-editable `.release-pr.json` (see §4). **This is required, not optional:** with no baked default, an unset `KANBAN_EXPECTED_HOST` makes the promote step fail closed (exit non-zero, token never sent). See [`UPGRADE.md`](UPGRADE.md) for keeping a vendored copy (§6b) current; action consumers (§6a) upgrade via the pin.

## Worked example (host install, primary board named `dev`)

```bash
git clone <agent-board-toolkit-remote-url> ~/agent-board-toolkit
for t in ~/agent-board-toolkit/bin/*; do ln -sf "$t" ~/.local/bin/"$(basename "$t")"; done; hash -r
cp ~/agent-board-toolkit/examples/kanban-board.env.example ~/.kanban-dev-board.env && chmod 600 ~/.kanban-dev-board.env
# ...fill in IDs in ~/.kanban-dev-board.env...
printf '%s' 'TOKEN_HERE' > ~/.kanban-dev-token && chmod 600 ~/.kanban-dev-token
kbcard list --column backlog        # -> [ {...}, ... ]   ✓ install verified
```
