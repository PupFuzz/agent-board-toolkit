# Git hooks — codify "work begun"

A recurring board-drift cause is forgetting to move a card to **In Progress** when work actually starts. This hook removes the manual step: when you check out a feature branch, the correlated card is moved to In Progress automatically.

## What it does

`hooks/post-checkout` → calls `bin/board-card-start`, which:
1. correlates the branch to a card — **try-in-order-with-fallback** (framework contract #112), on the *outcome* of a token not its presence:
   - a **`DL-NNN`** token (e.g. `feature/dl156-foo`) that **resolves** → the card whose `dl_number` is `DL-NNN` (a co-present card-id token is ignored, loudly); or
   - a `DL-NNN` that resolves to **no card** → **falls through** to a **card-id** token in the same branch (never dead-ends — the unstamped-card class). When the card is selected via the card-id path *and* the branch also named a DL, `payload.dl_number` is **stamped if empty** (never overwriting a differing stamp) so the downstream DL-correlated movers (bridge writeback, release promote) stop no-op'ing on the card; or
   - no `DL-NNN` → a **card-id** token → that card (task) id directly. Recognized as an explicit `card2950` / `card-2950` / `card/2950` / `card#2950` (the separator after `card` is **optional** since card-4621, so the natural glued `card2950` spelling correlates too) or a bare `#2950` anywhere, or the leading id of a typed branch (`feat/2950-…`, `fix/2950`, `chore/2950/…`). This covers routine FR/bug work branched by card id *before* a DL exists; or
   - a `DL-NNN` present but resolving to nothing with **no card-id fallback** → a loud no-op (a high-value miss), never silent.
2. resolves the card (board id from a repo-local `git config kanban.board-id`, else the repo's committed `.release-pr.json` `promote.board_id` — the `git config` value wins if both are set; API base from `.release-pr.json` or `~/.kanban-host.env`; in-progress stage from your `~/.kanban-<name>-board.env`), and verifies it is **on the repo's configured board** (so a stray number can't move an unrelated task; this is also the board-scope guard for the card-id fallback),
3. moves it to In Progress — from **Backlog or Prioritized** on any branch checkout, or from **Held** *only on a genuine branch creation* (`git switch -c`; a re-checkout of an existing branch won't un-park a Held card — the re-fire protection). A card already In Progress / In Review / Shipped / Released / Won't-Do is never touched.

A **pinned** card is never auto-moved regardless of stage: a non-empty `block_reason` **or** a `no-automove` tag makes the move refuse (loudly). Held detection uses the branch's reflog creation entry (`branch: Created from …`, ≤ ~15s old, overridable via `KB_HELD_CREATE_MAX_AGE`); a clone or an unparsable/missing reflog is treated as *not* a creation. This implements the cross-mover contract (agent-board-framework PR #113) shared with the bridge's branch-create `started` mover.

**Un-parking a pinned card is bridge-owned (push-path only), by design.** The bridge's `started` mover can *override* a pin and promote a pinned card from an opt-in stage set on a branch-cut (`unpark_from_stages`), emitting a **durable** compensating "overrode a human hold" alert so the override is never silent. This hook deliberately does **not** mirror that override: a `post-checkout` hook's only surface is `stderr` — which is effectively silent when an agent drives `git switch -c` and is never persisted — so it has no durable place to record the override, the property that makes reversing the pin safe. So a locally-cut branch for a pinned card leaves it parked; the bridge un-parks it (from a configured stage, with the alert) once the branch is **pushed**. The pin-refuse above is the *shared* half of the contract; the un-park override is intentionally bridge-only.

It is **fail-soft** (any missing config / unreachable board / no DL-or-card-id token in the branch → it does nothing and never blocks the checkout) and **idempotent**.

## Branch-name advisory (`pre-push`, card-4621)

`hooks/pre-push` → `board-card-start --lint <branch>` for each pushed branch. It is a **fail-soft advisory** (it always exits 0 and **never blocks a push**): it warns, on stderr, only when a branch name **looks like** it references a card but in a spelling the auto-move grammar **won't** recognize — so the card would silently never move to In Progress. It reuses the *exact* card-id matcher `board-card-start` moves on (`_bcs_explicit_card_id` / `_bcs_typed_card_id`), so the lint and the mover can never disagree.

It is deliberately **narrow / high-precision** — it warns only on the residual after the grammar was widened (card-4621): the literal `card`/`#` at a token boundary followed by ≥2 digits through a separator the grammar does *not* accept, e.g. `card_4524` or `card.4524` (the accepted separators are `-`, `/`, `#`, or none). A branch that already correlates (`card-4524`, glued `card4524`, `feat/4524-…`, a `DL-NNN`) is silent, and a branch with no card-ish signal at all (`docs/adoption-guide`) is silent. The suggested fix names the compliant spelling:

```
board-branch-lint: branch 'fix/card_4524-x' looks like it references card 4524, but the board
auto-move grammar won't recognize this spelling — the card will NOT move to In Progress on
checkout. Rename it e.g. 'fix/card-4524-slug' (or 'fix/4524-slug').
```

The advisory becomes effective once the machine's on-PATH `board-card-start` is the version carrying `--lint` (a toolkit deploy, not merely a tag — see VERSIONING.md).

## Agent-dispatch card-start (`hooks/agent-dispatch-card-start`, card-4945)

`post-checkout` only fires when a **branch** is created — but when work is dispatched to a
subagent, the card should move to In Progress at **dispatch time**, not at the later
branch-creation. `hooks/agent-dispatch-card-start` closes that latency window: it is a **Claude
Code `PreToolUse` hook for the `Agent` (subagent-dispatch) tool** that moves a card the moment a
build is dispatched. It is a peer of `post-checkout`, not a replacement — either can fire first;
`kbcard move` is idempotent, so a second move of an already-In-Progress card is a no-op.

### Marker convention (load-bearing — opt-in per dispatch)

The hook acts **only** on an explicit marker line in the dispatch prompt, anchored at line start:

```
BOARD-CARD: <board-key>#<card-id>
```

e.g. `BOARD-CARD: toolkit#4945`. A **bare card-number scan is deliberately NOT used** — review
and report dispatches routinely mention many card ids in prose (`card#1234`, `#91`), so a number
scan would move the wrong cards. The marker must be added on purpose, which makes the behavior
deterministic. Multiple marker lines are each acted on (exact duplicates deduped); a marker
appearing **mid-line** (any non-whitespace before it) is ignored. Leading indentation is
tolerated (the marker may sit inside an indented block). Any line-start occurrence of the marker
fires, including inside quoted or example text in a prompt (worst case: a benign idempotent
In-Progress move) — so avoid quoting live marker lines at column 0 in dispatch prompts.
`<board-key>` is the same key you pass to `kbcard --board <key>` (it resolves `~/.kanban-<key>-board.env`).

### Mechanics

Claude Code delivers the event as a **JSON object on stdin** (never env vars — the event name is
`hook_event_name` in the stdin JSON). For an `Agent`-tool dispatch the prompt is at
`.tool_input.prompt`. The hook parses stdin, scans the prompt for markers, and for each resolved
marker invokes the existing primitive:

```
kbcard --board <key> move --task <card-id> --column in_progress
```

`kbcard` (on PATH at `~/.local/bin`) owns board-env/token resolution — the hook does not hand-roll
`curl`.

### Fail-soft, always

The hook must never block or materially delay a dispatch. It **exits 0 on every path**
(unparseable stdin, no marker, unknown board key, `kbcard` missing, API error), bounds each move
with `timeout` (~10s; `KBADS_TIMEOUT` overrides), and writes a one-line diagnostic to **stderr** on
failure (visible in hook debug, never fatal) — mirroring `post-checkout`'s posture.

### Registration is a MANUAL operator step (not auto-installed)

`bin/install-board-hooks` symlinks **git** hooks; a Claude Code hook lives in Claude Code
**settings.json**, which the installer deliberately does **not** touch (settings.json is
operator-owned config, not a repo-tracked git hook). Register it by hand — add a `PreToolUse`
matcher `"Agent"` entry that runs the script (adjust the absolute path to your toolkit checkout):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/agent-board-toolkit/hooks/agent-dispatch-card-start"
          }
        ]
      }
    ]
  }
}
```

Place it in your user-level `~/.claude/settings.json` (applies to every project) or a project's
`.claude/settings.json`. No other setup is needed — the hook self-resolves boards from your
existing `~/.kanban-<key>-board.env` files.

## Correlation naming — one token drives the whole lifecycle

Two independent movers advance a card, and **they read different surfaces with different grammars** — so a single naming habit is what makes the *whole* lifecycle auto-move with **zero manual `dl_number` stamping**:

| Mover | Trigger | Reads | Grammar it accepts |
| --- | --- | --- | --- |
| `board-card-start` (this hook) | branch checkout/creation → **In Progress** | the **branch name** | `DL-NNN`, `card<id>`/`card-<id>`/`card/<id>`/`card#<id>` (separator optional since card-4621), `#<id>`, or a typed branch's leading id (`feat/<id>-…`) |
| bridge writeback | PR opened/merged → **In Review / Shipped / Released** | the PR **title + head branch** | **only** `DL-NNN`, `card-<id>`, or `card#<id>` (`\bcard[-#](\d+)`, bridge ≥ v0.57.0; older bridges accept only `card#<id>` with a trailing `\b`) — a bare leading id like `feat/2950-…` does **not** correlate |

The residual asymmetry is deliberate (the bridge never correlates a bare leading id, to avoid mis-correlating version numbers / non-card digits). Since bridge **v0.57.0** the `card-<id>` form correlates on **both** movers, so the fleet-ratified convention (roundtable #48) satisfies both with one token:

- **Branch:** `<type>/card-<id>-<slug>` (e.g. `feat/card-2950-widget`). The hook moves the card to In Progress; the same ref later correlates the PR's head branch on the bridge. (The older `<type>/<card-id>-<slug>` bare-id shape still works for the hook, but only the hook — the bridge ignores it.)
- **PR title:** carries the token automatically via the head branch; adding **`card-<card-id>`** (or the older `card#<card-id>`) to the title is belt-and-braces. Use **`DL-NNN`** in the title when the card carries a decision-log id (the bridge prefers a resolving DL, then falls through to the card token — framework #112).

A bare `#<id>` (e.g. `(#2950)`) in a PR title does **not** match the bridge grammar — write `card-<id>` (or `card#<id>`). With this one habit, a card auto-moves Backlog → In Progress → In Review → Shipped → Released with no `kbcard move` and no manual stamp. (A `board-card-branch` helper that mints the branch and emits the PR-title token is a possible future convenience; the convention above is the load-bearing part.)

## Install (per repo that you cut feature branches in)

```bash
install-board-hooks /path/to/your-repo     # installs the post-checkout + pre-push hooks; non-destructive
```
Re-run after `git pull`-ing a new toolkit version only if the hook set changed (it's a symlink, so the content tracks the toolkit automatically — **but on Windows/MSYS/Git-Bash hosts `ln -s` produces copies**, and a copies install must re-run `install-board-hooks` after every toolkit upgrade; see INSTALL.md §2's copy-topology warning).

The installer **honors `core.hooksPath`**: if the repo sets it (gitleaks, the pre-commit framework, Husky, many Windows setups) git dispatches hooks *only* from there, so the hook is installed into `<core.hooksPath>/post-checkout` — otherwise the install would be a silent no-op. It still refuses to clobber an existing non-symlink hook, and refuses a `core.hooksPath` that resolves **inside the tracked work tree** (a machine-specific absolute symlink there would show as a work-tree change and break on other clones) — guiding you to chain the toolkit hook into your committed hook by hand instead.

Requirements: the repo resolves a **board id** — a repo-local `git config kanban.board-id <id>` (uncommitted; needs no `.release-pr.json`, and so adds no committed `api_base` surface), **or** a `.release-pr.json` with `promote.board_id` (release repos). The `git config` value wins if both are set; in practice they are mutually-exclusive populations. You also have `~/.kanban-host.env`, a token file, and a `~/.kanban-<name>-board.env` whose `KB_BOARD_ID` matches the repo's board. Same config the rest of the toolkit uses (see [INSTALL.md](INSTALL.md)).

**Which token the hook sends.** By default the host-level one: `KBCARD_TOKEN_FILE` from `~/.kanban-host.env`, else `~/.kanban-dev-token`. A board that keeps its token elsewhere sets `KBCARD_TOKEN_FILE` in its **`~/.kanban-<name>-board.env`** — but the hook honors that **only when the repo's board id came from `git config kanban.board-id`**. A board id read from the committed `.release-pr.json` keeps the host/default token, because that file is PR-editable: honoring it would let a pull request re-point the hook at another board's env and send that board's credential. Per-board tokens are therefore a deliberate **host-local opt-in**, invisible to anything committed. (The rest of the toolkit — `kbcard` and friends — has no such restriction; its board comes from a `--board` name you typed, not from a repo file.)

**`~/.kanban-host.env` must export both** (the same setup `kbcard`/`promote-released-cards` use):
- **`KBCARD_API`** — the real kanban api base, e.g. `https://<host>/api/v3`. `board-card-start` reads `promote.api_base` from the committed `.release-pr.json`, but that value is typically a **host-scrubbed reserved placeholder** (`*.example.com`, `.invalid`, `.test`, `.localhost`, or the bare `.example` TLD — RFC-2606/6761) because the real host must not live in a repo — and it is absent entirely for a repo without a `.release-pr.json`. When it detects such a placeholder (or an empty/absent value) it **falls back to `KBCARD_API`** — so the hook reaches the real board with no per-repo config. The detector is anchored to host-label boundaries, so a real host that merely *contains* one of those substrings (e.g. `kanban.latest-corp.com`) is not misread. A genuinely real committed host (a multi-host install that didn't scrub) is used as-is.
- **`KANBAN_EXPECTED_HOST`** — the expected api host (e.g. `<host>`, the host part of `KBCARD_API`). The anti-exfiltration guard refuses to send the writeback token unless the resolved `api_base` host equals this (or is a subdomain of it). Without it set, `board-card-start` fail-softs (loud on stderr **and appended to the diagnostic log**, no move). One host-level setting activates every repo on the machine.

## Manual use

```bash
board-card-start                     # current branch — move the correlated card to In Progress
board-card-start feature/dl156-foo   # a specific branch name
board-card-start --lint <branch>     # advisory only: print the branch-name warning (if any), no move
```

## Scope / limits

- Correlates on a `DL-NNN` token (matches the kbcard/writeback convention) **or** a card-id token (`card#2950` / `#2950` / `card-2950` / a typed branch's leading id like `feat/2950-…`), try-in-order-with-fallback: a resolving DL wins; a DL that tracks no card falls through to the card-id token (and stamps `dl_number` on it). A branch with neither token is a no-op. The card-id path only moves a card that lives on the repo's own board.
- **Diagnostics (fail-soft but not silent).** The hook always `exit 0`s (it must never block a checkout), but when a branch carries a DL/card token and the move *didn't* happen for an infrastructure reason — no resolvable board id, an unloadable token/host, an untrusted `api_base`, unresolved stage ids, an unreachable board, a `card#N` that doesn't exist, or a pinned card — it prints a one-line reason to stderr **and appends it to `~/.cache/agent-board-toolkit/board-card-start.log`** (`KB_BCS_LOG` overrides the path). Because the installed hook wrapper discards stderr, that log is the durable record: check it if a card you expected to move didn't. A branch with **no** token, a card already **past** the move stages, or a card-id number that lives on **another** board stays silent — those are genuine no-ops, not failures.
- This is the **local** half of the codification. The durable, multi-agent half is the bridge moving the card on the branch-create / first-push webhook (derive-from-artifact) — tracked separately.
