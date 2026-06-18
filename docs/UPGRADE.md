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

> **Why a re-vendor + check instead of a submodule?** It keeps each repo self-contained for CI (no submodule checkout) while `agent-board-toolkit-drift-check` makes silent divergence impossible — the check fails CI if `bin/<tool>` no longer matches the toolkit at the recorded version. If you prefer one literal copy, a git submodule of `agent-board-toolkit` is the supported alternative; then "upgrade" is `git submodule update --remote` and the drift-check is unnecessary.

## 4. Verify after upgrade

```bash
agent-board-toolkit-drift-check ~/agent-board-toolkit <repo>   # each vendored repo -> "drift-check: OK"
kbcard show --task <some-id> | jq .id              # host -> the id, no error
```

## 5. Compatibility

- **Patch/minor** (`x.y.Z` / `x.Y.z`): backward-compatible — config files unchanged; host pull + re-vendor is all that's needed.
- **Major** (`X.y.z`): may change a config key or a tool's flags. The version's release notes list any required config migration **before** you bump. Read them, migrate `~/.kanban-*-board.env` / `.release-pr.json` as directed, then upgrade.
- Rollback is `git -C ~/agent-board-toolkit checkout <previous-tag>` (host) and reverting the vendor-bump PR (repos). No state is stored in the toolkit, so rollback is always safe.
