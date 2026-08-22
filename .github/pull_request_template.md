<!-- agent-board-toolkit PR -->

## What & why

<!-- one or two lines -->

## Checklist
- [ ] The shellcheck gate passes locally — run the `shellcheck` job's own `run:` line from
      `.github/workflows/ci.yml` (it goes through `bin/_shellcheck-pinned`, so your sweep uses the
      analyser version `.shellcheck-version` pins, which is the one CI runs)
- [ ] If a tool changed, vendoring repos re-vendor + `agent-board-toolkit-drift-check` passes (see docs/UPGRADE.md); composite-action consumers pick it up via their next pin bump (no PR-time action)
- [ ] Docs updated if behavior/flags/config changed (README / docs/INSTALL.md / docs/UPGRADE.md)
- [ ] No secrets, hostnames, ids, or emails added to tracked files (config stays in `~/.kanban-*` / `.release-pr.json`)
- [ ] `VERSION` bumped if this is a release-worthy change
