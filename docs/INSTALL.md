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
```

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

> **`.release-pr.json` is security-sensitive.** `.promote.api_base` is the host the release-CI writeback token (`KANBAN_WRITEBACK_TOKEN`) is sent to. A PR that edits `api_base` to an attacker host would exfiltrate the token on the next promote run. `promote-released-cards` (and `board-card-start`) reject any `api_base` that is not `https://` on the **expected host** before sending the token. Set **`KANBAN_EXPECTED_HOST`** in the promote-CI env (a repo/org variable — out-of-band from this PR-editable file) to your kanban host; the guard accepts that host or a subdomain of it. Leaving it unset falls back to a pinned default host. Review any `api_base` change as a credential-scope change.

## 5. Verify (expected output shown)

```bash
kbcard list --column backlog            # -> JSON array of cards (or [] if empty). A non-empty, well-formed
                                        #    result proves token + board IDs + API base are all correct.
kbcard show --task <some-id> | jq .id   # -> the task id echoed back
```
If `kbcard` errors with `HTTP 401` → token wrong/missing. `column '...' is not defined` → a `KB_STAGE_*` id is unset in your env file. A curl/connection error → `KBCARD_API` host wrong.

## 6. (Optional) Vendor a tool into a product repo for CI

A repo whose CI runs a toolkit tool (e.g. `release-promote-cards.yml` runs `bin/promote-released-cards`) needs the script **in the repo** (CI has no `~/.local/bin`). Vendor it and record the version, then let CI guard drift:

```bash
mkdir -p <repo>/bin
cp ~/agent-board-toolkit/bin/promote-released-cards <repo>/bin/promote-released-cards
cat ~/agent-board-toolkit/VERSION > <repo>/.agent-board-toolkit-version    # record what you vendored
# add a CI step (or pre-commit) that fails on drift:
~/agent-board-toolkit/bin/agent-board-toolkit-drift-check ~/agent-board-toolkit <repo>   # -> "drift-check: OK"
```
Set **`KANBAN_EXPECTED_HOST`** in that CI job's env (alongside `KANBAN_WRITEBACK_TOKEN`) to your kanban host — it pins the host `promote-released-cards` will send the token to, out-of-band from the PR-editable `.release-pr.json` (see §4). See [`UPGRADE.md`](UPGRADE.md) for keeping the vendored copy current.

## Worked example (host install, primary board named `dev`)

```bash
git clone <agent-board-toolkit-remote-url> ~/agent-board-toolkit
for t in ~/agent-board-toolkit/bin/*; do ln -sf "$t" ~/.local/bin/"$(basename "$t")"; done; hash -r
cp ~/agent-board-toolkit/examples/kanban-board.env.example ~/.kanban-dev-board.env && chmod 600 ~/.kanban-dev-board.env
# ...fill in IDs in ~/.kanban-dev-board.env...
printf '%s' 'TOKEN_HERE' > ~/.kanban-dev-token && chmod 600 ~/.kanban-dev-token
kbcard list --column backlog        # -> [ {...}, ... ]   ✓ install verified
```
