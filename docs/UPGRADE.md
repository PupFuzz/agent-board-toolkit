# agent-board-toolkit — upgrade an existing install

Use this when a new toolkit version is available. Two surfaces upgrade differently: the **agent host** (symlinks — trivial) and **product repos that vendored a tool** (need a re-vendor + drift-check).

## 1. See what you have vs what's available

```bash
cat ~/agent-board-toolkit/VERSION                 # installed
git -C ~/agent-board-toolkit fetch --quiet && git -C ~/agent-board-toolkit show origin/HEAD:VERSION   # available
```

## 2. Upgrade the agent host (symlink installs — nothing else to do)

If you installed per INSTALL §2 (symlinks into `~/.local/bin`), the host tracks the source automatically:

```bash
git -C ~/agent-board-toolkit pull --ff-only
hash -r
cat ~/agent-board-toolkit/VERSION                 # confirm the new version
kbcard list --column backlog | jq 'length'  # smoke test -> a number, no error
```
If any **new** tool was added, re-run the symlink loop from INSTALL §2 to pick it up:
```bash
for t in ~/agent-board-toolkit/bin/*; do ln -sf "$t" ~/.local/bin/"$(basename "$t")"; done; hash -r
```

## 3. Upgrade a product repo that vendored a tool (INSTALL §6)

A vendored copy does **not** update with the host pull — re-vendor it deliberately, in a branch, and let the drift-check confirm:

```bash
cd <repo> && git checkout -b chore/bump-agent-board-toolkit
cp ~/agent-board-toolkit/bin/promote-released-cards bin/promote-released-cards   # re-copy each vendored tool
cat ~/agent-board-toolkit/VERSION > .agent-board-toolkit-version                       # record the new version
~/agent-board-toolkit/bin/agent-board-toolkit-drift-check ~/agent-board-toolkit .            # -> "drift-check: OK"
git add bin/promote-released-cards .agent-board-toolkit-version
git commit -m "chore: bump vendored agent-board-toolkit to $(cat ~/agent-board-toolkit/VERSION)"
# open a PR per the repo's normal flow; CI re-runs the drift-check as a guard.
```

> **⚠ Re-vendoring `promote-released-cards` from a host-guarded version? You must also add `KANBAN_EXPECTED_HOST`.** The guarded script — the version that validates `.release-pr.json`'s `api_base` against `$KANBAN_EXPECTED_HOST` before sending the writeback token (see [`INSTALL.md`](INSTALL.md) §6 + [`README.md`](../README.md)) — **requires** `KANBAN_EXPECTED_HOST` in the promote-CI env and has **no baked default**. A re-vendor that copies the new script but does **not** add the variable makes the **next promote run fail closed**: the token is never sent and tracking-card promotion is skipped (with a loud CI error). The **`drift-check` will NOT catch this** — it verifies the script matches the toolkit, not that your consuming workflow supplies the env. So in the SAME re-vendor PR, add it to the promote step's env, alongside `KANBAN_WRITEBACK_TOKEN`:
> ```yaml
> KANBAN_EXPECTED_HOST: ${{ vars.KANBAN_EXPECTED_HOST }}   # your kanban host, e.g. kanban.example.com
> ```
> and set the variable once (out-of-band from the PR-editable `.release-pr.json`):
> ```bash
> gh variable set KANBAN_EXPECTED_HOST --repo <owner>/<repo> --body "<your-kanban-host>"
> ```
> If your promote workflow also injects `api_base` from a variable, set `KANBAN_API_BASE` the same way. The guard accepts that host or a subdomain of it.

> **Why a re-vendor + check instead of a submodule?** It keeps each repo self-contained for CI (no submodule checkout) while `agent-board-toolkit-drift-check` makes silent divergence impossible — the check fails CI if `bin/<tool>` no longer matches the toolkit at the recorded version. If you prefer one literal copy, a git submodule of `agent-board-toolkit` is the supported alternative; then "upgrade" is `git submodule update --remote` and the drift-check is unnecessary.

## 4. Verify after upgrade

```bash
agent-board-toolkit-drift-check ~/agent-board-toolkit <repo>   # each vendored repo -> "drift-check: OK"
kbcard show --task <some-id> | jq .id              # host -> the id, no error
```

## 5. Compatibility

- **Patch/minor** (`x.y.Z` / `x.Y.z`): backward-compatible — config files unchanged; host pull + re-vendor is all that's needed.
- **Major** (`X.y.z`): may change a config key or a tool's flags. The version's release notes list any required config migration **before** you bump. Read them, migrate `~/.kanban-*-board.env` / `.release-pr.json` as directed, then upgrade.
- **Required config added with the promote host-guard.** The version that introduces the fail-closed `api_base` host validation adds **one required** promote-CI variable — `KANBAN_EXPECTED_HOST`, with **no default**. Any repo that vendors `promote-released-cards` must add it to its promote-workflow env on the re-vendor that pulls the guarded script (see §3), or the promote step fails closed on the next release. This affects **only** repos that run the promote workflow; the agent-host symlink install (§2) is unaffected. `.release-pr.json` and `~/.kanban-*-board.env` are otherwise unchanged.
- Rollback is `git -C ~/agent-board-toolkit checkout <previous-tag>` (host) and reverting the vendor-bump PR (repos). No state is stored in the toolkit, so rollback is always safe.
