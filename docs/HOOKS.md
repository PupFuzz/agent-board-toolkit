# Git hooks — codify "work begun"

A recurring board-drift cause is forgetting to move a card to **In Progress** when work actually starts. This hook removes the manual step: in a repo you have **armed**, checking out a feature branch moves the correlated card to In Progress.

## Arm it per repo — unset means OFF (card#9845)

```bash
git config kanban.automove-on-checkout true     # in each repo whose cards you want moved at checkout
```

`hooks/post-checkout` calls the mover **only** where this is set to a git boolean true (`true`, `yes`, `on`, `1`); with it unset, `false`, empty or unreadable the hook exits without calling anything, silently. **The default is OFF because a checkout is not a work-start signal** — reading a colleague's branch, bisecting, or hopping back to `main` fires this hook too, and the mover is invoked with **no arguments**, byte-identically to a deliberate hand-run, so no layer below the hook can tell those apart (card#9845's measurement: three such moves inside five seconds, 2026-09-19). Arming is what supplies the missing signal, and it is the whole of it: an armed repo behaves exactly as every repo did before.

`git config` writes repo-locally, which is the intended grain — the reader is git's ordinary cascade, so `--global` is available to a seat that deliberately wants every repo armed. It sits beside `kanban.board-id` (§ What it does, step 2), which the mover already reads.

⚠ **Arming is also what writes the [board-verdict record](#the-board-verdict-leg-dl-225) — and what runs the `payload.dl_number` stamp (framework contract #112 step 2).** Both are the mover's writes, so an unarmed repo gets neither: no checkout records a verdict, and a branch that names both a card and a DL leaves `payload.dl_number` unstamped — so the DL-correlated movers (bridge writeback, release promote) silently no-op on that card at release, nothing failing. **This is the SAME release-grade cost [README § ⚠ Setting a reason pins the card](../README.md#-setting-a-reason-pins-the-card-against-the-whole-post-checkout-hook--not-just-its-stage-move) already documents for a pinned card** — an unarmed repo reaches it by a different route (the mover is never called at all, instead of being called and exiting at the pin).

**What `pre-push` says about a card-id branch in an unarmed repo** — this paragraph owns it; every other surface points here. A branch with **no record** reads `NOT RECORDED`. A branch whose record was written **before** the repo was unarmed — by a checkout while it was armed, or before card#9845, when every checkout called the mover — has that record still: nothing but a run of the mover rewrites or removes it, and the lint reads it whether or not the repo is armed. So it keeps repeating that record's verdict (for `resolved` that is **silence**, not `NOT RECORDED`), or reports it `STALE` where [§ The board-verdict leg](#the-board-verdict-leg-dl-225) *How staleness shows* detects that. While the repo stays unarmed no checkout refreshes it; only a deliberate hand-run of `board-card-start` for that branch does, and that run can also move the card.

⚠ **Cross-repo seam, not fixed here: a wired-but-unarmed repo still satisfies a purely TEXTUAL "is the auto-move installed" check.** The Agent Board Framework's `board-mover-check.py` (`/coord:update` area 8) reads whether the dispatched `post-checkout` mentions `board-card-start` — a predicate this hook still satisfies whether or not `kanban.automove-on-checkout` is set, so such a check can report the mover live while an unarmed repo moves nothing. `board-mover-check.py` lives in the framework repo, a different seat's, so it isn't changed here.

## What it does

In an armed repo, `hooks/post-checkout` → calls `bin/board-card-start`, which:
1. correlates the branch to a card — **try-in-order-with-fallback** (framework contract #112), on the *outcome* of a token not its presence:
   - a **`DL-NNN`** token (e.g. `feature/dl156-foo`) that **resolves** → the card whose `dl_number` is `DL-NNN` (a co-present card-id token is ignored, loudly); or
   - a `DL-NNN` that resolves to **no card** → **falls through** to a **card-id** token in the same branch (never dead-ends — the unstamped-card class). When the card is selected via the card-id path *and* the branch also named a DL, `payload.dl_number` is **stamped if empty** (never overwriting a differing stamp) so the downstream DL-correlated movers (bridge writeback, release promote) stop no-op'ing on the card; or
   - no `DL-NNN` → a **card-id** token → that card (task) id directly. Recognized as an explicit `card2950` / `card-2950` / `card/2950` / `card#2950` (the separator after `card` is **optional** since card-4621, so the natural glued `card2950` spelling correlates too) or a bare `#2950` anywhere, or the leading id of a typed branch (`feat/2950-…`, `fix/2950`, `chore/2950/…`). This covers routine FR/bug work branched by card id *before* a DL exists; or
   - a `DL-NNN` present but resolving to nothing with **no card-id fallback** → a loud no-op (a high-value miss), never silent.
2. resolves the card (board id from a repo-local `git config kanban.board-id`, else the repo's committed `.release-pr.json` `promote.board_id` — the `git config` value wins if both are set; API base from `.release-pr.json` or `~/.kanban-host.env`; in-progress stage from your `~/.kanban-<name>-board.env`), and verifies it is **on the repo's configured board** (so a stray number can't move an unrelated task; this is also the board-scope guard for the card-id fallback),
3. moves it to In Progress — from **Backlog or Prioritized** on any branch checkout, or from **Held** *only on a genuine branch creation* (`git switch -c`; a re-checkout of an existing branch won't un-park a Held card — the re-fire protection). A card already In Progress / In Review / Shipped / Released / Won't-Do is never touched.
4. once that move has succeeded, stamps the seat owner tag `owner:<project>/<seat>` in a separate write. When it is stamped, when it is not, and what is logged are [README § The seat owner tag](../README.md#the-seat-owner-tag--ownerprojectseat); a tag that is not stamped never undoes or fails the move.

A **pinned** card is never auto-moved regardless of stage: a non-empty `block_reason` **or** a `no-automove` tag makes the move refuse (loudly). Held detection uses the branch's reflog creation entry (`branch: Created from …`, ≤ ~15s old, overridable via `KB_HELD_CREATE_MAX_AGE`); a clone or an unparsable/missing reflog is treated as *not* a creation. This implements the cross-mover contract (agent-board-framework PR #113) shared with the bridge's branch-create `started` mover.

**Un-parking a pinned card is bridge-owned (push-path only), by design.** The bridge's `started` mover can *override* a pin and promote a pinned card from an opt-in stage set on a branch-cut (`unpark_from_stages`), emitting a **durable** compensating "overrode a human hold" alert so the override is never silent. This hook deliberately does **not** mirror that override: a `post-checkout` hook's only surface is `stderr` — which is effectively silent when an agent drives `git switch -c` and is never persisted — so it has no durable place to record the override, the property that makes reversing the pin safe. So a locally-cut branch for a pinned card leaves it parked; the bridge un-parks it (from a configured stage, with the alert) once the branch is **pushed**. The pin-refuse above is the *shared* half of the contract; the un-park override is intentionally bridge-only.

It is **fail-soft** (any missing config / unreachable board / no DL-or-card-id token in the branch → it moves nothing and never blocks the checkout) and **idempotent**.

**It records what the board said, for the `pre-push` lint (DL-225).** Every run on a named branch leaves that branch's board verdict in a local record — `resolved`, `absent` (not a card on this repo's board: a 404, or a card on another board) or `not_checked` with its reason — on the arms that stay silent on stderr and in the log as well as on the loud ones, and whether or not a card moved. [§ The board verdict leg](#the-board-verdict-leg-dl-225) owns the record and what the lint makes of it.

## Branch-name advisory (`pre-push`, card-4621)

`hooks/pre-push` → `board-card-start --lint -- <branch>` for each pushed branch. It is a **fail-soft advisory** (it always exits 0 and **never blocks a push**) and prints each finding as one `board-branch-lint:` line on stderr. Its **malformed-spelling** leg catches a branch name that **looks like** it references a card but in a spelling the auto-move grammar **won't** recognize, so the card would silently never move to In Progress. For a spelling the grammar **accepts**, the **id-space** question — is that number a card on this repo's board at all? — is answered by the [board verdict](#the-board-verdict-leg-dl-225) the mover recorded at checkout. Both legs reuse the *exact* card-id matchers `board-card-start` moves on (`_bcs_explicit_card_id` / `_bcs_typed_card_id`), so the lint and the mover can never disagree **about the grammar**.

The `--` is load-bearing, not boilerplate. git **accepts** a branch whose name starts with `-` (`git check-ref-format refs/heads/-foo` is rc 0 and `git update-ref` creates it — only the `git branch` *porcelain* refuses the name), and this hook is fed whatever is being pushed. Passed bare, such a name reads as an unknown option and the lint refuses it, while the mover still moves that branch's card — `post-checkout` passes **no** arguments, so it resolves `HEAD` and never enters the argument parser. The shared matchers are what make the two agree on the *grammar*; the **argument surface** is the one place left where they could still disagree, and the terminator is what closes it.

The malformed-spelling leg is deliberately **narrow / high-precision** — it warns only on the residual after the grammar was widened (card-4621): the literal `card`/`#` at a token boundary followed by ≥2 digits through a separator the grammar does *not* accept, e.g. `card_4524` or `card.4524` (the accepted separators are `-`, `/`, `#`, or none). A branch that already correlates (`card-4524`, glued `card4524`, `feat/4524-…`, a `DL-NNN`) is silent, and a branch with no card-ish signal at all (`docs/adoption-guide`) is silent. The suggested fix names the compliant spelling — **and, since card#9845, also names arming as a separate precondition**: renaming fixes the *grammar*, but a rename alone still moves nothing in a repo that has not run `git config kanban.automove-on-checkout true` (§ [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845)), because there is nothing hook-side left to fire on a compliant rename in an unarmed repo either:

```
board-branch-lint: branch 'fix/card_4524-x' looks like it references card 4524, but the board
auto-move grammar won't recognize this spelling — the card will NOT move to In Progress on
checkout. Rename it e.g. 'fix/card-4524-slug' (or 'fix/4524-slug') to fix the grammar; that
alone still moves nothing unless this repo is ARMED for checkout auto-move ('git config
kanban.automove-on-checkout true' — docs/HOOKS.md § Arm it per repo, card#9845).
```

### The board verdict leg (DL-225)

The malformed-spelling leg cannot see the opposite mistake: a **well-formed** token carrying a GitHub issue or PR number instead of a card id. `fix/card-712-foo`, where 712 is the PR that was in front of whoever cut the branch, lints clean under that leg; on checkout the mover finds no card of this board's at 712 and moves nothing — noting it in its durable log at most, and silently when 712 is another board's card; and at merge the **branch beats the PR title** for card correlation, so the card's terminal move is refused as well.

On every checkout **in an armed repo** (§ [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845) — an unarmed one never calls the mover, so it records nothing) the mover asks the board about the branch's card id — the explicit token, else a typed leading id (`_bcs_card_id`, which the lint shares) — and records the answer. `board-card-start --lint` repeats that answer at push: it reads the branch's record and nothing else, and issues no request. A branch the board said is not a card here:

```
board-branch-lint: branch 'fix/card-712-foo' names card 712, which is NOT a card on board 42 — the board said so when the
branch was checked out (card #712: HTTP 404; recorded 2026-09-14T12:00:00Z); card ids and GitHub issue/PR numbers are
separate id spaces — cut the branch from the CARD id …
```

What the lint says for a branch carrying a card id (a branch with none is silent and reads no record):

| The branch's record | At push |
| --- | --- |
| `resolved` — the card is on this repo's board, whether or not it moved (a pinned card, or one past the move stages, is still resolved) | silent |
| `absent` — the card read answered HTTP 404, or the card's body names another board by a plain-integer id | the line above, with the id-space rule |
| `not_checked` — the checkout got no answer about the id: no board mapped, no board env, no token, the read refused or unreachable, a body with no stage or no plain-integer board id, the DL search failed, a DL-matched card whose read then failed, a DL that resolved a card other than the branch's explicit card token (see *A DL and an explicit card token* below), … | `board verdict NOT CHECKED … — <the recorded reason>` |
| none | `board verdict NOT RECORDED …` — **the repo is not armed** (§ [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845)), so no checkout of the branch has called the mover; or the branch was created without a checkout (`git branch`, `git update-ref`, a fetch) and no earlier branch of that name left a record; or it was last checked out before this version or without the hook; or its record could not be written (the mover's durable log says so) |
| stale — see below | `board verdict … is STALE — <why>` |
| a file that is not a record for this branch | `board verdict record … is UNREADABLE` |

**Every row but `resolved` and `absent` names its fix** — check the branch out again; `git checkout <branch>` re-fires `post-checkout` even when that branch is already checked out (measured on git 2.43), except where a re-checkout would only record the same verdict (a DL beside a card token, below), which names its own fix. ⚠ **In a repo that is not armed, re-checking-out is not the fix and the line will repeat** — no checkout there calls the mover, so whatever this leg says about a card-id branch there it keeps saying until the repo is armed; which line that is — `NOT RECORDED`, or an older record's verdict — is owned by § [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845). The lint does not read the setting and cannot say which of the row's causes it is looking at; a repo you deliberately leave unarmed is one where these lines are noise you should expect (card#9845). A push prints at most one id-space line per branch: `hooks/pre-push` lints each pushed local branch once, even when one push sends it to several remote refs (`git push r b:refs/heads/x b:refs/heads/y` feeds the hook one line per refspec).

- **A DL and an explicit card token — where the mover and the bridge split.** The mover lets a DL that resolves win the MOVE: on `feature/dl-89-card-712-x`, with DL-89 stamped on card 4242, it moves 4242 and logs `DL wins; #712 ignored`. agent-webhook-bridge decides the MERGE the other way (DL-218, `GitHubPrCardMoveClassifier::cardTokenVerdict`): a card token its `CardTokenGrammar` parses out of the PR's head branch that is not one of the DL's cards is authoritative, so at merge that branch's subject is card 712, not 4242. Neither behaviour is changed by this leg; the lint reports the difference. The mover never reads 712, so it records the branch `not_checked` — `DL-89 resolved card #4242; the branch's own card #712 was not judged — …` — and the push line speaks. Checking the branch out again would record the same verdict, so the line names the fixes that do change it: rename the branch so its DL and its card token name the same card, or accept that the bridge acts on card #712 at merge. The record is `resolved` when the explicit token names the DL's own card, and when the other id is a typed leading id (`fix/712-dl-89`), which the bridge grammar does not parse.

  **The two card-token grammars differ in both directions** (the bridge's side read from its `CardTokenGrammar::PATTERN` on `dev`):
  - *A card id here, no token to the bridge — an over-report.* The toolkit takes a bare `#712`, `card/712`, and a `card` token after `_` (`x_card-712`); the bridge parses none of them. A DL beside one is recorded `not_checked` as well: a line the merge does not need.
  - *A token to the bridge, no card id here — a silence.* The bridge takes `card` after any character that is not an ASCII letter, digit or `_`, where the toolkit takes it only at the start of the name or after `/`, `-` or `_`: `feature/dl-89.card-712-x`, `feature/dl-89+card-712-x` and `feature/dl-89@card-712-x` name card 712 to the bridge. The bridge also takes a one-digit id after `card-` or `card#`, where the toolkit needs two: `feature/dl-89-card-5-x`. On those the toolkit reads no card id at all — the mover judges only the DL (one that resolves is moved and recorded `resolved`), and the lint, with no card id to judge, is **silent** — while at merge the bridge acts on the token. That case is left to the bridge's merge-time check; the toolkit's grammar is not widened to close it, because the mover moves on that grammar.

- **Location.** `$(git rev-parse --git-common-dir)/agent-board-toolkit/board-verdict/<key>`, where `<key>` is `printf '%s' <branch> | git hash-object --stdin`. The common git dir is the one every linked worktree of a repository shares — branches belong to the repository, not to a worktree — git tracks nothing inside it, and the records go when the repository does. Hashing the name keeps a long name, or `fix` beside `fix/x`, from colliding as a path; the record's own `branch=` line is checked when it is read.
- **Format.** Line 1 is `abtk-board-verdict 1`; then one `key=value` per line — `branch`, `card` (the id the name yields), `dl`, `board`, `verdict` (`resolved`, `absent` or `not_checked`), `subject` (the resolved card), `reason`, `remedy` (the fix the lint names for a `not_checked` verdict that checking the branch out again would only re-record; empty otherwise), `recorded_at` (unix seconds) and `recorded_utc`. No value carries a line break or any other control character: the writer turns a line break into a space and removes the rest — C0, DEL and C1 — from every value it is given, and the lint removes them again from each record value it prints, so an older or hand-edited record cannot write to the terminal.
- **The latest checkout wins.** Every run of the mover — a checkout in an armed repo (§ [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845)), or a hand-run — rewrites the branch's record atomically — a temp file in the record's directory, renamed over the old one — so a reader sees the previous record or the new one, never a torn one. A write that fails is logged to the mover's durable log and never fails the checkout, and it removes the previous record wherever the directory still allows, so the lint says `NOT RECORDED` rather than repeating an older checkout's answer.
- **How staleness shows.** The lint reports a record `STALE`, and does not repeat its verdict, when the record names a board and the repo now maps to another board, or to none — a record that names no board, from a checkout that stopped before resolving one (`curl` or `jq` not on `PATH`), is not stale against the board the repo maps to, and repeats its own `NOT CHECKED` reason; when the id this version reads from the name is not the recorded `card`; or when the branch's reflog ends in a `branch: Created from` entry newer than `recorded_at` — it was deleted and re-created with `git branch`, without a checkout, since. **A re-creation that leaves no such entry is NOT detected, and the older verdict is repeated as current:** `git update-ref` (its reflog entry has an empty message) and `git fetch . <src>:refs/heads/<branch>` (`fetch …: storing ref`), both measured on git 2.43 — any re-creation logged under another message reads the same way; a branch whose reflog is off (`core.logAllRefUpdates=false`) or expired; and a re-creation in the same second as the record. **Not detectable without reading the board:** a card created, moved to another board or deleted after the checkout, or a DL stamped onto a different card — the next run of the mover re-records.
- **Not pruned.** A deleted branch's record stays until the repository goes; the reflog rule above keeps a re-created name from inheriting it.
- **Never a block.** A finding is a line; the exit status is 0 whatever either leg finds.
- **Independent of the malformed-spelling leg.** A malformed spelling carries no accepted id, so this leg has nothing to judge on it, and an accepted spelling is silent to the other leg. Neither predicate was widened into the other.

The advisory becomes effective once the machine's on-PATH `board-card-start` is the version carrying `--lint` (a toolkit deploy, not merely a tag — see VERSIONING.md). The board verdict leg speaks for a branch carrying a card id once that version carries it, and repeats the board's answer once the branch has been checked out through a `post-checkout` that called the mover with that version on `PATH` — since card#9845, only in an **armed** repo or by a hand-run of the mover; what a branch reads before that, and what an unarmed repo's branches read, is owned by § [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845).

## Agent-dispatch card-start (`hooks/agent-dispatch-card-start`, card-4945)

`post-checkout` only fires when a **branch** is created, and since card#9845 only in an **armed**
repo (§ [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845)) — but when work is
dispatched to a subagent, the card should move to In Progress at **dispatch time**, not at the
later branch-creation. In a repo left unarmed, this hook is the only starter at all. `hooks/agent-dispatch-card-start` closes that latency window: it is a **Claude
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

`<board-key>` is **ASCII** letters/digits/`_`/`-`, and `<card-id>` is **ASCII** digits — matched
under `LC_ALL=C` regardless of the shell's own locale, because a bash bracket range is a
*collation* range: under an ordinary `en_US.UTF-8` shell an unpinned `[0-9]` also matches
non-ASCII digits, and `BOARD-CARD: toolkit#٣` parsed, sending a non-number to `kbcard move
--task` (card#5409). A marker whose key or id is not ASCII does not parse, in any locale.

### Mechanics

Claude Code delivers the event as a **JSON object on stdin** (never env vars — the event name is
`hook_event_name` in the stdin JSON). For an `Agent`-tool dispatch the prompt is at
`.tool_input.prompt`. The hook parses stdin, scans the prompt for markers, and for each resolved
marker invokes the existing primitive:

```
kbcard --board <key> move --task <card-id> --column in_progress --stamp-owner --card-start
```

`kbcard` (on PATH at `~/.local/bin`) owns board-env/token resolution — the hook does not hand-roll
`curl`. `--stamp-owner` has kbcard stamp the seat owner tag after the move, under the rules in
[README § The seat owner tag](../README.md#the-seat-owner-tag--ownerprojectseat). The hook relays
kbcard's `owner tag` lines to its own stderr and keeps the rest of kbcard's output suppressed.
**Upgrade `kbcard` with this hook:** a `kbcard` older than `--stamp-owner` refuses the flag as an
unknown arg. The hook retries the move once without it — **still carrying `--card-start`** — and
says what happened once that retry has answered, never before. ⛔ **On every `kbcard` that can
actually exist the retry is refused too, and the card does NOT move:** `--stamp-owner` shipped
first, so a `kbcard` old enough to refuse it is older than the guard flag as well, and the
paragraph below is the outcome. The card moves unstamped only on a `kbcard` that knows
`--card-start` but not `--stamp-owner`, which no release is. Either way the fix is the same:
update `kbcard` together with this hook.

**The work-start guard (`--card-start`, card#9556).** kbcard **reads the card** and **refuses the move** rather than making it when the card is **pinned** (a non-empty `block_reason` or a `no-automove` tag) or is **not in Backlog / Prioritized** — so a dispatch naming a card that has already shipped no longer pulls it back to In Progress, and a human's pin is not overridden. A **Held** card is refused too: it is promoted only by a genuine branch creation, which a dispatch is not. A refusal is **rc 0 with nothing written** (no move, no owner tag), and its reason is relayed to the hook's stderr, so a card that did not move says why — a card **already In Progress** (a follow-up dispatch, or `post-checkout` got there first) is told exactly that, and left where it is. **A guard the lib cannot answer is not a refusal by policy** (card#9756): when `kb_card_pinned` or `kb_card_start_stage_verdict` returns an rc outside its declared set — rc 127 when the lib beside `kbcard` predates them — nothing is written, `kbcard` exits **rc 2**, and its line naming the function and the rc is relayed beside the hook's `kbcard move failed` line. The fix is to copy the lib beside `kbcard` as `docs/INSTALL.md` §6b derives. The predicate is the toolkit lib's, shared with [`bin/board-card-start`](../bin/board-card-start): the hook is installed standalone and cannot source that lib, so `kbcard` is how it reaches the same invariants instead of a third copy of them. ⛔ **Unlike `--stamp-owner`, the flag is never dropped to get the move through** — a `kbcard` that refuses it as an unknown arg leaves the card where it is, loudly, because dropping the guard would move the card anyway, which is the defect itself.

### Fail-soft, always

The hook must never block or materially delay a dispatch. It **exits 0 on every path**
(unparseable stdin, no marker, unknown board key, `kbcard` missing, API error), bounds each move
with `timeout` (~10s; `KBADS_TIMEOUT` overrides — since `--card-start` that one bound covers
**three** requests per move where it covered two: the guard's read of the card, then the move and
owner-tag writes, so a slow board may need it raised; a kill reports as the generic
`kbcard move failed` line), and writes a one-line diagnostic to **stderr** on
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
| `board-card-start` (this hook) | branch checkout/creation → **In Progress**, in an **armed** repo only (§ [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845)) | the **branch name** | `DL-NNN`, `card<id>`/`card-<id>`/`card/<id>`/`card#<id>` (separator optional since card-4621), `#<id>`, or a typed branch's leading id (`feat/<id>-…`) |
| bridge writeback | PR opened/merged → **In Review / Shipped / Released** | the PR **title + head branch** | **only** `DL-NNN`, `card-<id>`, or `card#<id>` (`\bcard[-#](\d+)`, bridge ≥ v0.57.0; older bridges accept only `card#<id>` with a trailing `\b`) — a bare leading id like `feat/2950-…` does **not** correlate |

The residual asymmetry is deliberate (the bridge never correlates a bare leading id, to avoid mis-correlating version numbers / non-card digits). Since bridge **v0.57.0** the `card-<id>` form correlates on **both** movers, so the fleet-ratified convention (roundtable #48) satisfies both with one token:

- **Branch:** `<type>/card-<id>-<slug>` (e.g. `feat/card-2950-widget`). The hook moves the card to In Progress; the same ref later correlates the PR's head branch on the bridge. (The older `<type>/<card-id>-<slug>` bare-id shape still works for the hook, but only the hook — the bridge ignores it.)
- **PR title:** carries the token automatically via the head branch; adding **`card-<card-id>`** (or the older `card#<card-id>`) to the title is belt-and-braces. Use **`DL-NNN`** in the title when the card carries a decision-log id (the bridge prefers a resolving DL, then falls through to the card token — framework #112).

A bare `#<id>` (e.g. `(#2950)`) in a PR title does **not** match the bridge grammar — write `card-<id>` (or `card#<id>`). With this one habit, a card auto-moves Backlog → In Progress → In Review → Shipped → Released with no `kbcard move` and no manual stamp — the **In Progress** step in an armed repo (§ [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845)); unarmed, the branch name still drives every later step, which the bridge owns. (A `board-card-branch` helper that mints the branch and emits the PR-title token is a possible future convenience; the convention above is the load-bearing part.)

## Install (per repo that you cut feature branches in)

```bash
install-board-hooks /path/to/your-repo                        # installs the post-checkout + pre-push hooks; non-destructive
git -C /path/to/your-repo config kanban.automove-on-checkout true   # ARM the auto-move — installing does not
```
Re-run after `git pull`-ing a new toolkit version only if the hook set changed: the hook entries are symlinks, so their content tracks the toolkit automatically.

**Installing and arming are two steps on purpose (card#9845), and the installer says so on every successful run** — it ends by printing that the command does NOT arm the auto-move, with the `git config` line that arms the repo it just wired and the one that reads its current state, on both the symlink and the `--allow-copies` terminus. It never arms the key itself: doing so as a side effect of `install-board-hooks` would restore the always-on behaviour this card removed, on every repo it touched, under a command whose name says nothing about it. The installer wires the hooks; the `git config` above is what lets `post-checkout` move a card, and an install without it leaves the auto-move OFF — see § [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845) for why that is the default, and for the `payload.dl_number` stamp an unarmed repo also loses (release-grade, not just advisory noise). `pre-push`'s advisory needs no arming and is unaffected, except that in an unarmed repo its board-verdict leg has no record to repeat.

**That symlink IS the upgrade contract, so the installer measures whether this seat can make one — before it writes anything.** On a symlink-incapable seat (the measured case: Windows/MSYS/Git-Bash with Developer Mode off and no elevation) the emulation layer does **not** fail `ln -s` — it returns success having substituted a **copy**. An install that accepted that would report exactly what a healthy install reports while leaving the seat running hooks no `git pull` will ever reach again. So a capability probe runs first, and there are three outcomes:

| Verdict | Exit | What happens |
| --- | --- | --- |
| **CAPABLE** | 0 | symlinks are installed — the unchanged path |
| **NOT_CAPABLE** | 1 | **refused**, nothing installed, with the reason and the opt-in named |
| **INDETERMINATE** | 4 | **refused**, nothing installed — reported *separately* from NOT_CAPABLE, because "we could not determine" is not "we know you cannot". The reason names a local fault to fix (an unwritable or unreadable directory, a probe-name collision, an unlink that did not take, a reader — `git` or the shell — that cannot read the probe's own entries); `--allow-copies` deliberately does **not** apply, since it opts into a *known* degradation, not an unknown one |

**Any other probe status is refused the same way, at the same exit 4.** Only `0` selects the install and only `1` selects the not-capable refusal; anything else is a status the installer cannot read as a measurement, so it takes the INDETERMINATE arm above rather than falling through to the install. That is not hypothetical — the probe's own signal handling exits `130`/`143`, and a signal it does not catch reads back as `129`/`137` — and a fall-through there would install symlinks on the strength of a probe that never said CAPABLE.

**The probe reads the entry twice, with two different readers, because on the seat that matters they disagree.** Its test is that the installed entry still delivers the source's content after the source is *replaced* — and the obvious way to check that, reading the entry from the shell, is exactly what the emulation layer defeats. Under `MSYS=winsymlinks:lnk` the layer creates a Windows `.lnk` shortcut that its own `cat` and `test -L` both resolve, while `git.exe` — the binary that actually dispatches hooks — opens the file and reads shortcut bytes. A shell-only probe would answer **CAPABLE** there: the silent degrade, reproduced inside the detector. So the replaced content is read again by git's own binary (`git hash-object`, which is why `git` is a requirement of this tool — it already was), and both answers are kept:

| git tracks | shell tracks | Verdict | `REASON` |
| --- | --- | --- | --- |
| yes | yes | CAPABLE | `ok` |
| no | no | NOT_CAPABLE | `link-does-not-track-source-across-replacement` |
| no | yes | NOT_CAPABLE | `readers-disagree-native-git-does-not-track` — the `winsymlinks:lnk` signature |
| yes | no | NOT_CAPABLE | `readers-disagree-shell-does-not-track` (hooks execute under that shell) |
| unmeasured | yes / no | INDETERMINATE | `git-read-failed` |
| yes / no | unmeasured | INDETERMINATE | `shell-read-failed` |
| unmeasured | unmeasured | INDETERMINATE | `both-reads-failed` |

Both disagreements fail closed, and the token records *which* reader failed: a refusal nobody can attribute is not much better than no refusal. **A failed *read* is never scored as "does not track", and that is one rule over both readers, not the native one's rule** — either reader is `unmeasured` until its own read succeeds, and `unmeasured` is INDETERMINATE. Scoring it otherwise would report a fact about the seat that was never established and route you to `--allow-copies` — a degradation — over a local fault that has nothing to do with symlinks. The distinction is the read's *status*, not its output: a read that succeeds and finds **nothing** is the seat answering, and stays a measured absence (`readers-disagree-shell-does-not-track`, NOT_CAPABLE) exactly as any other non-matching content. Where **both** readers fail — an entry neither can open — the token says so rather than naming one of them, so fixing the named one does not just earn you a second refusal.

**If your seat genuinely cannot symlink, `--allow-copies` installs copies deliberately:**

```bash
install-board-hooks --allow-copies <repo>    # installs COPIES; prints COPY per hook; exits 3, never 0
```

It is a permit, not a force: on a capable seat it changes nothing and symlinks are still installed. Exit status **3** is the point — a copies install is legible to a script rather than indistinguishable from a symlink install. **A copies install must be re-run after every toolkit upgrade**, and that re-run needs one extra step: the installed hook is a regular file, so the refuse-to-clobber guard stops it (`refusing to overwrite an existing non-symlink hook`) — exactly as it would for a hook you wrote yourself, since it cannot tell the two apart. Delete the stale copies first — the copies install itself prints these exact lines in its exit-3 summary, which is where they are stated (the refusing re-run prints only the clobber refusal):

```bash
rm -f <repo>/.git/hooks/post-checkout <repo>/.git/hooks/pre-push   # only if they are toolkit copies
install-board-hooks --allow-copies <repo>
```

`install-board-hooks --check <repo>` reports what a run would do, answers the **same** verdict and exit status a real run would, and installs nothing. It is not write-free: the capability probe is measurable only by creating a symlink, so the dry run creates and removes the probe's two `.ibhp*` entries. That is deliberate — a `--check` that skipped the measurement would answer "this would succeed" on precisely the seat where the real run refuses, and the session-close remedy line that consumes it would print that refusal as the fix.

**Validating this on a real Windows seat:** run `bash <toolkit>/tests/install-board-hooks-capability-windows-check.sh`. It needs only the checkout, `bash`, `git` and coreutils — no network, no board config — touches nothing but its own temp directory, and prints a seat report plus one `ok`/`FAIL` line per assertion. The behaviour above was developed on Linux, where an incapable seat can only be simulated; that script is how the real one is measured.

It also carries the one thing the probe cannot do: an **end-to-end dispatch** leg that stops inferring. The probe decides by *reading* the entry; that leg makes an entry with the seat's own `ln -s`, replaces the hook source the way an upgrade does, runs a real `git checkout`, and reports which content actually **executed** — with its own control (the hook is fired once *before* the replacement), so "nothing happened" can never read as a pass. Its two trailing lines, `SEAT VERDICT:` and `SEAT DISPATCH:`, are the result: a seat the probe **refuses** whose dispatch nonetheless delivers the replacement means the refusal is **wrong** on that seat, and the script says so at length rather than just failing. Send the whole output; do not adjust anything to make it green.

**A checkout whose git dir is not `<root>/.git` installs into the hooks directory git really dispatches from — except a linked worktree, which is refused and told where to go instead.** Three topologies put the hooks directory outside the work tree, and they need three *different* answers, so there is no single generic message:

| Topology | Where git dispatches hooks from | What the installer does |
| --- | --- | --- |
| **Linked worktree** (`git worktree`) | the **main** checkout's `.git/hooks`, shared by the main checkout and every worktree | **refuses** — run `install-board-hooks <main-checkout>` instead; that wires this worktree too |
| **`--separate-git-dir`** | the separate git dir's `hooks/` | **installs** there, and says so on stderr |
| **Submodule** | `<superproject>/.git/modules/<name>/hooks` | **installs** there, and names the superproject; the superproject's own hooks are untouched |

The split is by **blast radius**, not by "is the git dir elsewhere". A linked worktree's hooks directory is shared with the main checkout *and every sibling worktree*, so installing from one silently changes hook behaviour for checkouts the operator never named — and it is the only one of the three with another checkout to redirect to, which is why it is the only one that prints a command. The other two have exactly **one** work tree each, so the blast radius is precisely the repo you are standing in; they were previously refused on a rationale that does not apply to them.

On both installing topologies the target directory is reported on **stderr**, never stdout: `--check`'s only stdout is the target directory, and other tools consume it. Detection is by **git common dir** (`git rev-parse --git-common-dir` ≠ `<root>/.git`), never by `.git`-is-a-file: all three share that shape. Note that `--git-common-dir` ≠ `--git-dir` is **not** the discriminator — measured on git 2.43, those two differ **only** for a linked worktree; the other two topologies report them equal. The worktree is discriminated instead by whether another checkout's own `.git` *is* this repo's common dir. One primitive (`_ibh_install_dir_source`) owns that disposition, and `board-session-close` asks it rather than modelling it.

The refusal applies only while `core.hooksPath` is **unset**. A set `core.hooksPath` wins on every topology, so a linked worktree that configures one is perfectly installable and is *not* refused. `install-board-hooks --check <path>` reports all of this and installs nothing — it is not write-free, and the `--check` paragraph above says what its one write is.

The installer **refuses** a `core.hooksPath` that is **set but empty** rather than reporting a success git will not honor (git then dispatches no hooks at all, so installing into `.git/hooks` would be a silent no-op; fix with `git config --unset core.hooksPath`). It carries a matching refusal for a value git **cannot expand**. Which error you see is **git-version-dependent**: on git 2.43.0 such a value is expanded during the general config read, so *every* git command in the repo fatals and you get git's own message from the installer's first probe; on git 2.54.0 `rev-parse` succeeds and only the explicit path read fatals, so you get the installer's refusal. Both paths are live — this was measured in both environments after it had been called unreachable on the strength of one. Otherwise it **honors `core.hooksPath`**: if the repo sets it (gitleaks, the pre-commit framework, Husky, many Windows setups) git dispatches hooks *only* from there, so the hook is installed into `<core.hooksPath>/post-checkout` — otherwise the install would be a silent no-op. It still refuses to clobber an existing non-symlink hook — decided over the **whole** hook set before the first write, so a refusal installs nothing at all rather than leaving whichever hooks it had already reached — and refuses a `core.hooksPath` that resolves **inside the tracked work tree** (a machine-specific absolute symlink there would show as a work-tree change and break on other clones) — guiding you to chain the toolkit hook into your committed hook by hand instead.

Requirements (beyond arming the repo, above): the repo resolves a **board id** — a repo-local `git config kanban.board-id <id>` (uncommitted; needs no `.release-pr.json`, and so adds no committed `api_base` surface), **or** a `.release-pr.json` with `promote.board_id` (release repos). The `git config` value wins if both are set; in practice they are mutually-exclusive populations. You also have `~/.kanban-host.env`, a token file, and a `~/.kanban-<name>-board.env` whose `KB_BOARD_ID` matches the repo's board. Same config the rest of the toolkit uses (see [INSTALL.md](INSTALL.md)).

**Which token the hook sends.** By default the host-level one: `KBCARD_TOKEN_FILE` from `~/.kanban-host.env`. **There is no baked default below that** — if neither the host env nor (per the rule below) the board env declares a token file, the hook falls to the coord credential store's `[kanban] api_token_file` pointer (card#7316) and, failing that too, skips the move and says so (card#7245). **The store rung does not widen what a repository can influence:** it is board-independent and lives outside the repo, so the PR-editable-file rule below is unaffected by it. A board that keeps its token elsewhere sets `KBCARD_TOKEN_FILE` in its **`~/.kanban-<name>-board.env`** — but the hook honors that **only when the repo's board id came from `git config kanban.board-id`**. A board id read from the committed `.release-pr.json` keeps the host/default token, because that file is PR-editable: honoring it would let a pull request re-point the hook at another board's env and send that board's credential. Per-board tokens are therefore a deliberate **host-local opt-in**, invisible to anything committed. (The rest of the toolkit — `kbcard` and friends — has no such restriction; its board comes from a `--board` name you typed, not from a repo file.)

**`~/.kanban-host.env` must export both** (the same setup `kbcard`/`promote-released-cards` use):
- **`KBCARD_API`** — the real kanban api base, e.g. `https://<host>/api/v3`. `board-card-start` reads `promote.api_base` from the committed `.release-pr.json`, but that value is typically a **host-scrubbed reserved placeholder** (`*.example.com`, `.invalid`, `.test`, `.localhost`, or the bare `.example` TLD — RFC-2606/6761) because the real host must not live in a repo — and it is absent entirely for a repo without a `.release-pr.json`. When it detects such a placeholder (or an empty/absent value) it **falls back to `KBCARD_API`** — so the hook reaches the real board with no per-repo config. The detector is anchored to host-label boundaries, so a real host that merely *contains* one of those substrings (e.g. `kanban.latest-corp.com`) is not misread. A genuinely real committed host (a multi-host install that didn't scrub) is used as-is.
- **`KANBAN_EXPECTED_HOST`** — the expected api host (e.g. `<host>`, the host part of `KBCARD_API`). The anti-exfiltration guard refuses to send the writeback token unless the resolved `api_base` host equals this (or is a subdomain of it). Without it set, `board-card-start` fail-softs (loud on stderr **and appended to the diagnostic log**, no move). One host-level setting serves every repo on the machine — it lets the hook reach the board, while whether the hook calls the mover at all is each repo's arming (§ [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845)) — and since card#7245 the same variable also gates every *other* tool in the toolkit, which preflight the api base they resolve from `~/.kanban-host.env` against it.

## Is the hook still wired? — the dispatch check

A repo can **lose** its hook wiring and nothing routine notices. The failure is silent by construction, from three directions at once:

- `board-card-start` is **fail-soft** by contract (it must never block a checkout), so from the operator's seat a missing hook and a working hook look identical — no error, no output, just a card that never moves.
- A session-close reconcile sees only the **symptom** (a card still sitting in its backlog column) and corrects it as ordinary drift, **masking the cause** — so the wiring can stay dead for an unbounded time while every session ends "clean".
- `agent-board-toolkit-drift-check` compares a repo's **vendored tool copies** against the toolkit. It says nothing about hook wiring, which is host state, not repo content.

So `board-session-close` reports it. Under `── Git hook dispatch ──` it prints one line per local checkout, between a header and a summary that both carry the leg's scope:

```
── Git hook dispatch — does each checkout's post-checkout still reach board-card-start? ──
   (report-only; remediation is yours: install-board-hooks <repo-dir> — wiring is half: a card
   also needs that repo ARMED — 'git config kanban.automove-on-checkout true' — which no fix
   line here sets (docs/HOOKS.md § Arm it per repo))
• some-repo: ✓ post-checkout pre-push dispatch from /path/some-repo/.git/hooks
• other-repo: dispatch dir /path/other-repo/.git/hooks
    ✗ post-checkout: no hook file in the dispatch dir — the card auto-move is DEAD for this repo
    ⚠ pre-push: no hook file in the dispatch dir — the branch-name advisory is off
      fix: install-board-hooks /path/other-repo
  (2 inspected / 0 skipped — 2 finding(s) — REPORT-ONLY: nothing was installed, repaired or
  changed here; wiring is half: a card also needs that repo ARMED — …)
```

⚠ **`fix: install-board-hooks …` is a WIRING fix, and running it to completion still leaves an unarmed repo moving no card (card#9845).** So is every other remedy this leg prints — the `then: install-board-hooks` repairs under a broken `core.hooksPath`, the hand-chain line, the manual `ln -s` tail and the host-`PATH` fix — which is why the arming note rides the leg's header and every summary that measured something, once for the leg, rather than being appended to each remedy. `install-board-hooks` itself ends every successful run by saying it did not arm the repo (§ [Install](#install-per-repo-that-you-cut-feature-branches-in)).

What it reports per hook: **missing**, a **dangling symlink**, present but **not executable** (git ignores it, saying so only through a suppressible `advice.ignoredHook` hint at the moment of the checkout), present but **not reaching `board-card-start`** (a foreign hook), and — as a lower-severity wiring drift, reported as ⚠ *"it still fires, but from a checkout other than the on-PATH tools'"* rather than as a dead hook — a hook **symlinked into a different toolkit checkout** than the one whose `board-card-start` is on `PATH` (that clone can be mid-edit, on another branch, or removed). A copied hook is *not* flagged as drift: copies remain a supported topology on a symlink-incapable seat — now as the installer's explicit `--allow-copies` opt-in (see *Install* above) rather than as something `ln -s` did silently. This check cannot tell a deliberate copy from a stale one, and does not try; the re-install obligation belongs to the seat that opted in.

Per **repo** it also reports `core.hooksPath` states that switch dispatch off wholesale — **set but empty** (git dispatches *no* hooks; it does **not** fall back to `.git/hooks`, so a perfectly-wired `.git/hooks` there is never read) and a value **git cannot expand** (`~unknownuser/…`, which fatals every git command in the repo) — and, per **host**, `board-card-start` being **absent from `PATH`**, which makes every `post-checkout` a no-op however it is wired. All three are findings. A path with no checkout is reported as skipped, not as a finding, and the summary always states **how many checkouts were inspected vs skipped**: zero inspected never prints an all-clear.

⚠ **A `✓` is a WIRING verdict, and since card#9845 wiring is no longer sufficient for a move.** The check asks whether the hook git dispatches still reaches `board-card-start`; it does not read `kanban.automove-on-checkout`, so a repo that is wired and **not armed** reports `✓` and moves nothing — by design, that being the point of the opt-in. The summary line says as much (`that is what ✓ asserts, not that a card will move`). If a card did not move in a repo this check calls healthy, read the arming (§ [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845)) before looking anywhere else: `git -C <repo> config --bool --get kanban.automove-on-checkout`.

It resolves the dispatch directory the way **git** does, not the way it is usually assumed — and the assumptions are where the silent no-ops live. It reuses `install-board-hooks`' own reader and resolver (one implementation, not a second copy), so it inherits both `core.hooksPath` behaviours verified against git: the value is read with `--path`, so a leading **`~` is expanded** (git expands it; reading the raw value makes `~/hooks` look like a *relative* path and plants under the work tree), and its **presence is taken from the exit status**, never from the value, because `--get` returns rc 0 with empty output for a set-but-empty value and rc 1 for unset — and those two mean opposite things. The resolver also *accepts* a git **common dir**, and this check supplies the repo's real one so a linked worktree resolves to the main checkout's hooks dir. Where the installer would target is **asked of the installer**, never modelled here: it answers `<root>/.git/hooks` for an ordinary checkout, the real common dir for a `--separate-git-dir` checkout or a submodule, and a refusal for a linked worktree (see *Install* above). Both tools resolve the common dir and the owning main checkout through the installer's own `_ibh_common_dir` / `_ibh_main_checkout`, so they cannot drift apart on which checkout owns a shared hook dir. A check that read `.git/hooks` alone, or that read the value without its status, would reproduce the exact silent no-op the installer was fixed for — reporting a repo healthy on the strength of a hook git never runs.

The remediation line is never guessed. `install-board-hooks <repo>` is printed only when **two** things are established: that the command would *succeed* — asked of the installer itself through its `--check` dry run, which evaluates every precondition it would evaluate for real and installs nothing (its one write is the symlink-capability probe's create-and-remove pair — see *Install* above; a `--check` that skipped it would call the install a fix on the one seat where it refuses) — and that the directory it would target is the one git *dispatches* from, which `--check` cannot know (the installer can succeed while installing where git never looks). Where a sibling checkout owns the dispatch directory, that path is named instead, proven the same way. Where the installer **refuses**, the refusal is quoted in the installer's own words and no target is invented. Two refusal shapes get different tails, and the difference is load-bearing. Where it refuses a directory it *would otherwise have targeted* — a repo carrying its own committed hook, an unwritable hooks directory, a `core.hooksPath` naming a regular file — you are told to resolve that and re-run, and **no `ln -s` is offered**, since for the clobber case that would tell you to destroy your own hook. Where it refuses the **topology** (a linked worktree) and no sibling checkout can be confirmed either, there is no directory it would target at all, so the manual `ln -s` into the real dispatch directory is offered instead — naming only the hooks that are actually broken. Saying it "would target" something in that case would state a falsehood about a tool that targets nothing.

This is a deliberate structure, not an implementation detail: the earlier version *modelled* the installer's preconditions and proved two of nine, which put a command that exits 1 in front of the most common finding of all.

### What the reach test can and cannot tell you

It **reads** the hook — symlinks followed, `#` comments stripped — and follows one level of chaining. It never *executes* the hook, so its answer is a textual approximation with bounds in **both** directions. They are stated here and in the code because a check whose limits are undisclosed gets trusted past them:

- **Erring toward a false *finding* (safe).** A hook that only mentions `board-card-start` in a comment is reported as not reaching it; the `#` strip also blanks the tail of a line whose earlier text quotes a `#`; a chain target whose **path contains whitespace** is never followed, so `exec "/opt/tk with space/hooks/post-checkout"` dispatches for real while reading as a finding (the match deliberately excludes whitespace — that is what stops it ingesting a line of prose, and widening it would trade this disclosed false-finding for an undisclosed false-OK); and only **absolute, literal** chain targets are followed — a chain written with a variable (`exec "$TOOLKIT/hooks/post-checkout"`) or relative to the work tree (`exec ../toolkit/hooks/post-checkout`) reads as a finding *even though it works*, because resolving the first needs the hook's runtime environment and the second needs git's dispatch-time working directory. The guidance this chain support exists for prints an absolute literal path, so the population these tools generate is covered; a hand-written variant may not be. A chain through a wrapper that is not itself a `hooks/<name>` path likewise reads as a finding.
- **Erring toward a false *OK* (accepted).** A mention inside a **string literal** — `echo "run board-card-start yourself"` — reads as a reach. So does an invocation that is **unreachable at runtime**, most realistically a call sitting after an early `exit 0`, which is how a hook gets "temporarily" disabled. Both have been reproduced against this implementation.

Whether git could **run** the hook at all is a separate question from whether the hook *calls* the tool, and it has a single owner: one predicate answers it for the dispatched hook and for a chained target alike, covering the executable bit, the file type (a directory is `-x` too), the shebang line — read so that a missing trailing newline does not discard the verdict, split on **space and tab, and only those two** (the kernel's separator set; a POSIX `[[:space:]]` class is a superset that also matches CR/VT/NL/FF, and reading it as "the kernel's whitespace rule" is what let that superset ship), so `#!<TAB>/bin/sh` is not called dead — the interpreter's existence and type, and CR/CRLF. That consolidation is deliberate: the property had been computed in three places, and each fact added to it previously had to be added to each place separately, which is how three of them ended up applied to only some.

The three false-OK bounds — the string literal, the unreachable call, and the unjudged shebang argument — are accepted as **not implemented**, not as impossible. Separating a string literal from code needs real shell parsing; for unreachable code, the simplest form — an unconditional top-level `exit 0` before the call — *is* catchable by a pure read, while the general case (conditionals, functions, traps) is decided only by running the hook. The rationale is deliberately **not** stretched to cover anything a pure *read* can catch — which is why **exec-ability is checked rather than disclosed**. The executable bit is not the ability to be exec'd: a hook with **CRLF line endings** or a **missing shebang interpreter** is `-x`, looks perfect, and still makes git fail with `fatal: cannot exec '<hook>': No such file or directory`. Reading the first line catches both, so the check does, on the direct hook **and** on a chained target, reporting it as `NOT-RUNNABLE` / `CHAIN-BROKEN` with the cause named. CRLF is the native hazard of the Windows/MSYS **copy** install topology documented above, so this is a supported-platform failure rather than a hypothetical.

Treat a `✓` as "a hook is wired, is runnable, and textually calls the tool" — not as proof that a card will move. Two more bounds are disclosed rather than detected, both verified against real dispatch:

- **The shebang *argument* is not judged.** `#!/bin/sh zzz` is twelve bytes, reads as runnable, and is **dead** — `/bin/sh` takes `zzz` as a script path and exits `cannot open zzz`, so the hook never runs. `#!/bin/sh -e` is accepted and fires. Telling those apart needs each interpreter's own CLI rather than a read, and `#!/usr/bin/env bash` is a correct hook whose argument is deliberately not a file — so an "does the argument exist?" heuristic would invent findings.
- **An interpreter name that does not *terminate* within the kernel's shebang buffer** (`BINPRM_BUF_SIZE`, 256 bytes on Linux) is truncated there, while the check reads the whole line. On the kernel this was verified against (6.8, git 2.43) `execve` returns `ENOEXEC` and the shell runs the file, so the *named interpreter* is silently ignored — a wrong-interpreter hazard rather than a dead hook, and the truncated remainder can then land in the argument shape above. The effect may differ on other platforms.

Every bound above is pinned by a fixture, so this disclosure and the behaviour cannot drift apart.

**It is report-only.** It never installs or repairs anything, and it does **not** change the ritual's exit code (which stays owned by the inverse-drift check) — remediation is your `install-board-hooks <repo-dir>` call, which the output names per finding — plus the repo's arming (§ [Arm it per repo](#arm-it-per-repo--unset-means-off-card9845)), which no line of this check sets.

## Manual use

```bash
board-card-start                     # current branch — move the correlated card to In Progress
board-card-start feature/dl156-foo   # a specific branch name
board-card-start --lint <branch>     # advisory only: print the branch-name findings (if any), no move
board-card-start <branch> --lint     # same — the flag is honoured in ANY position
board-card-start -- -foo             # a branch name starting with '-' — after the -- terminator
```

`--lint` is recognised wherever it appears in the argument list, not only first: accepting it only in position 1 meant `board-card-start <branch> --lint` silently dropped it and performed a **real** card move.

`--` ends option parsing: every argument after it is treated as the branch name, however it is spelled. It is there because git accepts a branch name starting with `-` (see the advisory section above), which would otherwise be refused as an unknown option — so `board-card-start -- -foo` and `board-card-start --lint -- -foo` are the way to name one, and `hooks/pre-push` uses that form.

An argument the tool cannot act on is **refused by name, with no move** — an **empty** branch argument (`board-card-start "$BRANCH"` with `BRANCH` unexpanded, which previously retargeted the move to whatever `HEAD` was on), an **unknown option** (its refusal names `--` as the fix), or a **second** positional. Passing **no** branch argument is unchanged and still means "the current branch" — that is how `hooks/post-checkout` calls it. Every one of these refusals prints to **stderr only** — it is deliberately *not* written to the diagnostic log, whose wording asserts a DL/card token an argument refusal has not established — and still **exits 0**: fail-soft is a contract here (see below), so a refusal is a *no-move*, never a non-zero exit. The exit code matters because an operator who **chains** this hook into a committed one carries no `|| true`, and `post-checkout`'s exit status becomes `git switch`/`git checkout`'s own (`githooks(5)`); the installed wrapper's `|| true` covers only the toolkit's own hook.

## Scope / limits

- Correlates on a `DL-NNN` token (matches the kbcard/writeback convention) **or** a card-id token (`card#2950` / `#2950` / `card-2950` / a typed branch's leading id like `feat/2950-…`), try-in-order-with-fallback: a resolving DL wins; a DL that tracks no card falls through to the card-id token (and stamps `dl_number` on it). A branch with neither token is a no-op. The card-id path only moves a card that lives on the repo's own board.
- **Diagnostics (fail-soft but not silent).** The hook always `exit 0`s (it must never block a checkout), but when a branch carries a DL/card token and the move *didn't* happen for an infrastructure reason — no resolvable board id, an unloadable token/host, an untrusted `api_base`, unresolved stage ids, an unreachable board, a `card#N` that doesn't exist, a pinned card, or a card-start invariant that returned an rc outside its declared set (rc 127: a `_kb-board-lib.sh` older than this hook; nothing is written, not even the `dl_number` stamp — card#9756) — it prints a one-line reason to stderr **and appends it to `~/.cache/agent-board-toolkit/board-card-start.log`** (`KB_BCS_LOG` overrides the path). Because the installed hook wrapper discards stderr, that log is the durable record: check it if a card you expected to move didn't — **after** confirming the repo is armed (`git config --bool --get kanban.automove-on-checkout`), because an unarmed repo never calls the mover and so leaves nothing in this log to find. Where a line names the api base, any **userinfo is masked to `***`** — an api_base may legitimately carry `user:password@`, and this log outlives the run on disk — so `https://***@board.example.com/api/v3` in the log means the base carried a credential, not that it is malformed. A branch with **no** token, a card already **past** the move stages, or a card-id number that lives on **another** board stays silent — those are genuine no-ops, not failures.
- **The owner tag's lines are logged the same way, but they are not failed moves.** When the card moves and the owner tag is not stamped, for any reason in [README § The seat owner tag](../README.md#the-seat-owner-tag--ownerprojectseat), that line goes to stderr and the same log. A checkout from a shell that does not carry `COORD_AGENT` (for example, a human terminal) logs the unresolved-owner line on every move it makes.
- This is the **local** half of the codification. The durable, multi-agent half is the bridge moving the card on the branch-create / first-push webhook (derive-from-artifact) — tracked separately.
