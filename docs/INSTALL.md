# agent-board-toolkit — new install

Follow top to bottom. Every command is copy-pasteable; placeholders are in `<angle brackets>` or `ALL_CAPS`. Expected output is shown after each verify step.

## 0. Prerequisites

```bash
for c in bash curl jq git gh; do command -v "$c" >/dev/null && echo "ok: $c" || echo "MISSING: $c"; done
```
All must print `ok:`. (`gh` is only needed for tools that touch GitHub, e.g. `board-session-close`. `release-pr-body` needs no `gh`, but it does need `git fetch` access to `origin` — it resolves the release baseline from the remote's release branch, since the local one is stale by design under the branch-off-dev flow.)

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

> **⚠ Windows / MSYS / Git-Bash: `ln -s` silently produces COPIES, not symlinks** (native
> mingw64 has no default symlink capability), and any manual `cp` install has the same
> effect. A copies install **works, but changes the upgrade contract**: `git pull` no longer
> refreshes the installed tools — you MUST re-run the loop above after **every** toolkit
> upgrade, or your on-PATH tools silently keep running the old version (a peer's Windows
> adopter hit exactly this verifying v0.13.0; it has re-occurred on every bump since).
> The same applies to a **pinned second checkout/worktree** topology (symlinks pointing at a
> checkout detached at a release tag): the pin does not advance with the dev clone. In both
> topologies, when verifying a fix or a security advisory, **inspect what `~/.local/bin`
> resolves to — never the checkout you edited**: `readlink -f ~/.local/bin/kbcard`. The
> `agent-board-toolkit-drift-check` tool catches stale vendored copies in repos; the
> `agent-board-toolkit-runtime-check` tool is that guard for the PATH install itself —
> run it after any upgrade (`board-snapshot` runs it quietly at SessionStart), and it FAILS
> LOUD on a stale pin, stale copies, or a mixed-runtime split (cards #4351/#4361).

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

> `KBCARD_API` is **board-independent** — set it **once** in `~/.kanban-host.env` (§3), not here. A board env that sets it is **refused** (as of v0.14.0) rather than silently honored, with a message naming the file. What "refused" means per tool: `kbcard`, `dl-a0-backfill-triaged`, `dl-a1-register-field`, and `adopt-to-dl` **exit 2 and do nothing**; `next-dl` **warns and skips the board check**, then still mints from its offline scan (fail-soft by design — but that scan is non-atomic, so fix the board env rather than rely on it). `board-snapshot` and `board-card-start` never read a board env's `KBCARD_API` at all, so they ignore one.

> **Token-file precedence**, uniform across every tool: **this board env's `KBCARD_TOKEN_FILE` > `~/.kanban-host.env`'s > an ambient one > `~/.kanban-dev-token`.** So a per-board token set here wins over a host-level default — that is the point of setting it here. (One exception: `board-card-start` consults a board env's token only for a repo whose board id comes from a repo-local `git config kanban.board-id` — see [HOOKS.md](HOOKS.md).)

> **The default board (no `--board` flag)** reads `~/.kanban-dev-board.env` + `~/.kanban-dev-token`. On a box whose primary board is **not** named `dev`, you have three ways to work flag-free — pick one:
> - name that board `dev` (env at `~/.kanban-dev-board.env`), **or**
> - **set `KBCARD_BOARD_ENV`** to your primary board's env file — e.g. `echo 'export KBCARD_BOARD_ENV="$HOME/.kanban-<name>-board.env"' >> ~/.profile` (recommended on a single-board box), **or**
> - always pass `--board <name>`.
>
> Without one of these, a bare `kbcard` on a non-`dev` box exits `2` with `board env file not readable: …/.kanban-dev-board.env` — the error names these fixes and lists the `~/.kanban-*-board.env` files it did find, so a fresh box on a non-`dev` board isn't left reverse-engineering the default.

## 4. Per-repo release config (only for repos that cut releases)

`promote-released-cards`, `release-pr-body` and `release-artifacts-check` read `<repo>/.release-pr.json`:

```bash
cp ~/agent-board-toolkit/examples/release-pr.json.example <your-repo>/.release-pr.json
# edit: set promote.{board_id, released_stage_id, api_base}, ref_token_regex (e.g. "DL-[0-9]+"),
# card_token_regex (e.g. "card#[0-9]+"), version_file/version_regex, dev/main branch names,
# and the artifacts set.
# tag_format (optional, default "v{{version}}"): how a version maps to its git tag —
# set "{{version}}" for unprefixed tags, or e.g. "release-{{version}}". Version extraction
# accepts 2-4 numeric segments (SemVer and .NET Major.Minor.Build.Revision alike).
jq . <your-repo>/.release-pr.json   # must parse (no trailing commas); remove the "_comment" line if you like
```

> **`ref_token_regex` and `card_token_regex` are TWO ID SPACES, not two spellings of one.** Both are optional and independent; set whichever your commit subjects actually use (set both if they use both).
> - **`ref_token_regex`** (e.g. `"DL-[0-9]+"`) — the token's numeric part is a **decision-log number**, correlated against a card's `payload.dl_number`.
> - **`card_token_regex`** (e.g. `"card#[0-9]+"`) — the token's numeric part is a **card id**, correlated against the card's own `id`.
>
> **Do not migrate by re-spelling `ref_token_regex`.** If your subjects moved from `DL-NNN` to `card#NNNN`, add the second key — do not change the first. `promote-released-cards` reads `ref_token_regex` too and matches on `dl_number`, so a `card#` spelling there makes a range naming `card#42` correlate with whichever card carries `DL-42`: it **moves that card and reports `0 no-card`**. Leaving `ref_token_regex` unset (or on its old spelling) with no matching tokens in range is harmless — the manifest footer is simply omitted.
>
> **What each key buys.** `release-pr-body` renders a `## Card coverage` section that dry-runs `promote-released-cards` over the range's refs and names any that have **no tracking card** — so a typo'd id, or a card belonging to a different board, is caught at release-prep rather than by a red post-merge promote run. It needs `.promote.board_id` + `$KANBAN_WRITEBACK_TOKEN` + the promote tool on `PATH`; without them the section says so instead of reporting clean. Each key also adds a machine-readable footer: `<!-- release-manifest:shipped-refs=DL-1,DL-2 -->` and `<!-- release-manifest:shipped-cards=5877,5874 -->` (bare ids — there is no token spelling for a consumer to parse).
>
> **Card ids are never derived from commit subjects by the mover.** `promote-released-cards` accepts them only via the explicit `--cards "5877,5874"` flag, because a descriptive `card#NNNN` mention in a subject ("supersedes card#1234") would otherwise relocate an unrelated card — with a DL token that misfire needs a matching `dl_number` stamp as well, but an id *is* the match. `release-pr-body` does derive them from subjects, and passes them with `--dry-run`.

> **`artifacts` is a must-move-together SET, not a memo.** Each entry is `<path> <prose>` — the path is the **leading whitespace-delimited token**, so **a member path may not contain whitespace**; everything after the first space is prose. `{{version}}` is expanded, and a single-level `{a,b}` brace set is allowed in the path (`sboms/v{{version}}.{spdx,cdx}.json` ⇒ two members). `release-pr-body` renders the set as the release PR's `- [ ]` checklist; `release-artifacts-check` (§6c) **asserts** it. Three member shapes, distinguished by the prose you write — and the shape a member was judged by is **printed on its OK line**, so check it says what you intended:
> - `docs/CHANGELOG.md → [{{version}}] section` — the literal text `[{{version}}] section` (matched case-insensitively) requires a **line beginning `## [<version>]`** in the file at head. This is the only **strong** shape. The trigger is that exact wording: `[{{version}}] entry` or `… heading` is **not** recognized and silently falls through to the weak shape below — which is why the OK line names the shape it used (`via '## [X.Y.Z]' heading line` vs `via content mention`).
> - a path whose **filename carries the version** (`sboms/v{{version}}.json`) — existence at head is the whole assertion.
> - anything else (`CLAUDE.md § Recent releases row`) — the file's content at head must **contain the version string. This test is UNANCHORED**: with version `0.25.0`, a file containing only `10.25.0` (or `0.25.01`) satisfies it. It is the catch-all for members whose agreement has no structure to key on, so it is deliberately weak — a member that needs a real assertion should use the `[{{version}}] section` shape.
>
> Every member must additionally appear in the PR's own changes and still exist at head (a deletion appears in a diff, so the existence leg is what catches it). Declare only what a release genuinely must move: an over-declared entry fails every release PR, and an under-declared one is invisible — no tool can assert a member you never named.

> **`.release-pr.json` is security-sensitive.** `.promote.api_base` is the host the release-CI writeback token (`KANBAN_WRITEBACK_TOKEN`) is sent to. A PR that edits `api_base` to an attacker host would exfiltrate the token on the next promote run. `promote-released-cards` (and `board-card-start`) reject any `api_base` that is not `https://` on the **expected host** before sending the token. **`KANBAN_EXPECTED_HOST` is REQUIRED — there is no baked default** (the toolkit ships onto your own kanban host, so it assumes none). Set **`KANBAN_EXPECTED_HOST`** in the promote-CI env (a repo/org variable — out-of-band from this PR-editable file) to your kanban host; the guard accepts that host or a subdomain of it. Leaving it unset makes the guard **fail closed** — the token is never sent. Review any `api_base` change as a credential-scope change.

## 5. Verify (expected output shown)

```bash
kbcard list --column backlog            # -> JSON array of cards (or [] if empty). A non-empty, well-formed
                                        #    result proves token + board IDs + API base are all correct.
kbcard show --task <some-id> | jq .id   # -> the task id echoed back
```
If `kbcard` errors with `HTTP 401` → token wrong/missing. `column '...' is not defined` → a `KB_STAGE_*` id is unset in your env file. A curl/connection error → `KBCARD_API` host wrong. `board env file not readable: …/.kanban-dev-board.env` → this box has no default (`dev`) board — set `KBCARD_BOARD_ENV` or pass `--board <name>` (see §3b); the error lists the boards that do exist.

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
    shipped-stage-ids: '52'                    # optional, EXAMPLE id — use YOUR board's Shipped-class stage id(s), comma-separated. A matched card NOT in one is skipped, so a stale/recycled DL stamp on a declined card is never promoted. Blank = no guard (prior behavior). Prefer a LITERAL — see below
    dry-run: ${{ github.event.inputs.dry_run }} # optional workflow_dispatch passthrough
```

Pin by **full 40-char SHA with the `# vX.Y.Z` comment** (the comment is what dependabot parses). The consumer repo still needs its own `.release-pr.json` (§4) and unset-guards for the two repo variables if it wants friendlier errors than the script's own fail-closed ones.

> **Give `shipped-stage-ids` a literal, not a bare `${{ vars.… }}`.** The stage ids are per-board
> constants that change only when the board's columns are reconfigured, so a repo variable buys
> nothing — and it fails **silently** in the one direction that matters. An unset variable renders
> as a blank input, the action correctly omits the flag, and the source-stage guard is simply
> **off**: no error, no warning, and a promote summary identical to a run that never asked for the
> guard. The workflow file still *reads* as guard-enabled, so the next person to audit it sees a
> protection that isn't running. That is the same "looks enabled, isn't" shape the guard exists to
> prevent, one layer up.
>
> If you do source it from a variable, **preflight it** exactly like `KANBAN_API_BASE` and
> `KANBAN_EXPECTED_HOST` above — an explicit `::error::` on empty, so an unset variable fails the
> job instead of quietly downgrading it:
>
> ```yaml
> - name: Preflight the source-stage guard
>   env:
>     KANBAN_SHIPPED_STAGE_IDS: ${{ vars.KANBAN_SHIPPED_STAGE_IDS }}
>   run: |
>     if [ -z "$KANBAN_SHIPPED_STAGE_IDS" ]; then
>       echo "::error::vars.KANBAN_SHIPPED_STAGE_IDS is unset — this workflow reads as guard-enabled but the source-stage guard would run OFF. Set it, or pass a literal." >&2
>       exit 1
>     fi
> ```
>
> Note this is a *consumer-side* choice: the action cannot tell "the operator omitted the input" from
> "the operator wired a variable that is unset", so it cannot warn on blank without crying wolf at
> every consumer who has deliberately not adopted the guard. Only the consumer knows its own intent.

### 6b. Non-Actions consumer — vendor + drift-check

For CI that can't `uses:` a GitHub action (or a project that prefers one literal copy — e.g. PM-project vendors per the Task-tracking standard §8 amendment — see [`ADOPTION.md`](../ADOPTION.md)), vendor the script **into the repo** and record the version, then let CI guard drift:

```bash
mkdir -p <repo>/bin
cp ~/agent-board-toolkit/bin/promote-released-cards <repo>/bin/promote-released-cards
cat ~/agent-board-toolkit/VERSION > <repo>/.agent-board-toolkit-version    # record what you vendored
# add a CI step (or pre-commit) that fails on drift:
~/agent-board-toolkit/bin/agent-board-toolkit-drift-check ~/agent-board-toolkit <repo>   # -> "drift-check: OK"
```

> **Vendoring a *lib-sourcing* bin (not `promote-released-cards`)?** The interactive/hook bins — `kbcard`, `next-dl`, `board-snapshot`, `board-card-start`, `adopt-to-dl`, `dl-a0-backfill-triaged`, `dl-a1-register-field` — `source` `bin/_kb-board-lib.sh` as a sibling, so you must copy **the lib too** into the same `bin/` (`cp ~/agent-board-toolkit/bin/_kb-board-lib.sh <repo>/bin/`). Without it the tool refuses at startup — since v0.11.2 that is a self-naming message pointing back at this section, **not** the bare `source: …/_kb-board-lib.sh: No such file` it used to be — and it refuses on **every** invocation, `--help` included, because the lib is loaded before any argument is read. `board-card-start` is the one deliberate variant: it runs from a git hook that must never block a checkout, so it reports that board automation was skipped and still exits 0. `agent-board-toolkit-drift-check` also flags a lib-sourcing bin vendored without the co-located lib. `promote-released-cards`, `release-pr-body` and `release-artifacts-check` are standalone and need no lib.

**Both paths** require **`KANBAN_EXPECTED_HOST`** — §6a supplies it via the `expected-host` **input** (step-level env overrides job env, so setting it only as job env does NOT reach the action's script; pin it as a repo variable and pass it through), §6b sets it in the CI job's env (alongside `KANBAN_WRITEBACK_TOKEN`). It pins the host `promote-released-cards` will send the token to, out-of-band from the PR-editable `.release-pr.json` (see §4). **This is required, not optional:** with no baked default, an unset `KANBAN_EXPECTED_HOST` makes the promote step fail closed (exit non-zero, token never sent). See [`UPGRADE.md`](UPGRADE.md) for keeping a vendored copy (§6b) current; action consumers (§6a) upgrade via the pin.

### 6c. GitHub Actions consumer — the release-artifact gate

Consume `release-artifacts-check` via the [`release-artifacts/`](../release-artifacts/action.yml) composite action, SHA-pinned on the same terms as §6a. It asserts every member of your `.release-pr.json` `artifacts` set (§4) actually moved in a release PR:

```yaml
name: Release artifacts
on:
  pull_request:
    # `edited` fires on a base RETARGET, and the verdict is a function of the base
    types: [opened, edited, reopened, synchronize]
permissions:
  contents: read
jobs:
  release-artifacts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<full-40-char-SHA>  # vX.Y.Z
        with:
          fetch-depth: 0     # REQUIRED — resolves the fork point; the version file is read at both ends
      - uses: <owner>/agent-board-toolkit/release-artifacts@<full-40-char-SHA>  # vX.Y.Z
        with:
          base-sha: ${{ github.event.pull_request.base.sha }}
          head-sha: ${{ github.event.pull_request.head.sha }}
          # config: .release-pr.json   # optional; the default
```

**The asserted range is `merge-base(base-sha, head-sha)..head-sha` — the PR's own changes — never base's tip.** That is a correctness requirement, not a refinement, because base-branch drift after the fork point corrupts both halves of the check:

- **the MOVED leg:** a hotfix landing on the base branch after the fork makes that file differ between base's tip and head, so it appears in a base-tip diff and *spuriously satisfies* "this artifact moved" for a member the PR never touched. Measured on a fixture: base-tip exits **0** with `all 5 declared artifact member(s) moved and agree`, merge-base exits **1** naming the member.
- **the CLASSIFICATION:** a version bump arriving on the base branch makes base's tip read the *same* version as head, so a real release PR is classified "version unchanged" and the entire gate silently does not run. Base-tip exits **0** with `not a release PR; nothing to assert` on a PR that is genuinely missing a member.

You still pass `base-sha` — it is what the fork point is resolved *from*.

**No `paths:` filter, deliberately.** The gate must observe every PR in order to *classify* it: a PR whose version **value** is unchanged between the fork point and head is not a release PR and exits 0 after two `git show`s. Classifying by value rather than by "the version file appears in the diff" is what makes this correct for a repo whose `version_file` is a whole config file (kanban's is `config/app.php`), where the file-moved test would misfire on any unrelated edit.

**It fails closed** (rc 2) on an unresolvable merge base or an unreadable version file, naming which end of the range it is and the path, rather than reading either as "not a release PR" — that misclassification would be a silent non-run of the entire gate. A shallow checkout is the usual cause, hence `fetch-depth: 0`.

## Worked example (host install, primary board named `dev`)

```bash
git clone <agent-board-toolkit-remote-url> ~/agent-board-toolkit
for t in ~/agent-board-toolkit/bin/*; do ln -sf "$t" ~/.local/bin/"$(basename "$t")"; done; hash -r
cp ~/agent-board-toolkit/examples/kanban-board.env.example ~/.kanban-dev-board.env && chmod 600 ~/.kanban-dev-board.env
# ...fill in IDs in ~/.kanban-dev-board.env...
printf '%s' 'TOKEN_HERE' > ~/.kanban-dev-token && chmod 600 ~/.kanban-dev-token
kbcard list --column backlog        # -> [ {...}, ... ]   ✓ install verified
```
