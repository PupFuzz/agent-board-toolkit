<!-- agent-board-toolkit PR -->

## What & why

<!-- one or two lines -->

## Scope

**Built:** dispatched (coder ×N / mechanic ×M) | inline (trivial-tier: <one-line reason>) | inline (dispatch-prohibited: <one-line reason>) | in-session (docs/coordination)
<!-- REQUIRED on every PR body — keep exactly ONE value, delete the others, and leave the line
     UNBULLETED at column 0 with the value UNQUOTED: the plane-1 audit is line-anchored and
     matches the value against the canonical set, so a leading `- ` reads as ABSENT and a
     wrapping backtick reads as out-of-set. The value set, and when each value is legitimate,
     is owned by the coord plugin's `docs/built-line.md` § "The `Built:` line"; read it there —
     deliberately not restated here, because a second copy drifts. The values above are the four
     a seat declares for its own work; the fifth, `unattestable — <reason>`, is restricted to two
     conditions that doc owns and is not offered here. -->

<!-- The card this work is coordinated on. Same line-anchored, unquoted, unbulleted shape as
     `Built:` above; the value is `card#NNNN`. Left EMPTY on purpose — a placeholder after the
     colon would be read as the answer and PASS an unfilled row. -->
**Coordinated in:**

## Checklist
- [ ] The shellcheck gate passes locally — run the `shellcheck` job's own `run:` line from
      `.github/workflows/ci.yml` (it goes through `bin/_shellcheck-pinned`, so your sweep uses the
      analyser version `.shellcheck-version` pins, which is the one CI runs)
- [ ] If a tool changed, vendoring repos re-vendor + `agent-board-toolkit-drift-check` passes (see docs/UPGRADE.md); composite-action consumers pick it up via their next pin bump (no PR-time action)
- [ ] Docs updated if behavior/flags/config changed (README / docs/INSTALL.md / docs/UPGRADE.md)
- [ ] No secrets, hostnames, ids, or emails added to tracked files (config stays in `~/.kanban-*` / `.release-pr.json`)
- [ ] `VERSION` bumped if this is a release-worthy change
