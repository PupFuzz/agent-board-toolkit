<!-- agent-board-toolkit PR -->

## What & why

<!-- one or two lines -->

## Checklist
- [ ] `shellcheck -S error bin/*` passes (CI gates this)
- [ ] If a tool changed, vendoring repos re-vendor + `agent-board-toolkit-drift-check` passes (see docs/UPGRADE.md); composite-action consumers pick it up via their next pin bump (no PR-time action)
- [ ] Docs updated if behavior/flags/config changed (README / docs/INSTALL.md / docs/UPGRADE.md)
- [ ] No secrets, hostnames, ids, or emails added to tracked files (config stays in `~/.kanban-*` / `.release-pr.json`)
- [ ] `VERSION` bumped if this is a release-worthy change
