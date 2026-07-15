# agent-board-toolkit — upgrade an existing install

Use this when a new toolkit version is available. Three surfaces upgrade differently: the **agent host** (symlinks — trivial), **product repos that vendored a tool** (need a re-vendor + drift-check), and **composite-action consumers** (a SHA-pin bump, dependabot-automated — see the §3 callout).

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

## 3. Upgrade a product repo that vendored a tool (INSTALL §6b)

> **Composite-action consumers (INSTALL §6a) skip this section entirely** — their upgrade is the SHA-pin bump (`uses: …/agent-board-toolkit/promote@<sha>  # vX.Y.Z`), which dependabot PRs automatically. Nothing is vendored, so there is nothing to re-vendor or drift-check.

A vendored copy does **not** update with the host pull — re-vendor it deliberately, in a branch, and let the drift-check confirm:

```bash
cd <repo> && git checkout -b chore/bump-agent-board-toolkit
cp ~/agent-board-toolkit/bin/promote-released-cards bin/promote-released-cards   # re-copy each vendored tool
cp ~/agent-board-toolkit/bin/_kb-board-lib.sh bin/                              # + the shared lib IF you vendored a lib-sourcing bin (kbcard/next-dl/board-snapshot/board-card-start/dl-a0/dl-a1)
cat ~/agent-board-toolkit/VERSION > .agent-board-toolkit-version                       # record the new version
~/agent-board-toolkit/bin/agent-board-toolkit-drift-check ~/agent-board-toolkit .            # -> "drift-check: OK"
git add bin/promote-released-cards .agent-board-toolkit-version
git commit -m "chore: bump vendored agent-board-toolkit to $(cat ~/agent-board-toolkit/VERSION)"
# open a PR per the repo's normal flow; CI re-runs the drift-check as a guard.
```

> **⚠ Re-vendoring `promote-released-cards` from a host-guarded version? You must also add `KANBAN_EXPECTED_HOST`.** The guarded script — the version that validates `.release-pr.json`'s `api_base` against `$KANBAN_EXPECTED_HOST` before sending the writeback token (see [`INSTALL.md`](INSTALL.md) §6b + [`README.md`](../README.md)) — **requires** `KANBAN_EXPECTED_HOST` in the promote-CI env and has **no baked default**. A re-vendor that copies the new script but does **not** add the variable makes the **next promote run fail closed**: the token is never sent and tracking-card promotion is skipped (with a loud CI error). The **`drift-check` will NOT catch this** — it verifies the script matches the toolkit, not that your consuming workflow supplies the env. So in the SAME re-vendor PR, add it to the promote step's env, alongside `KANBAN_WRITEBACK_TOKEN`:
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

## 6. Version-specific upgrade actions

§1–§5 are the mechanics (pull, re-vendor, drift-check). This section is the **content**: the changes across `v0.4.1 → dev` that require an upgrader to **do** something (set a var, add a file, re-run a loop, or knowingly accept a changed behavior). Feature additions that need no action are omitted. **Find your installed version (`cat ~/agent-board-toolkit/VERSION`) and walk forward from the next entry — each entry is cumulative.**

**Audience tags** (an entry may carry more than one):

- **[host]** — an agent host with symlink installs (INSTALL §2).
- **[vendor]** — a product repo that copied a `bin/` tool into its own tree (INSTALL §6b / §3 above).
- **[release-CI]** — a repo whose CI runs the promote workflow (via a vendored copy or the §6a composite action; the tool is usually `promote-released-cards`).

> Coverage floor is **v0.4.1**. **v0.4.0** was the first tag and has no earlier release to upgrade from, so it has no entry. Releases **v0.4.x–v0.8.1** predate `docs/CHANGELOG.md` (which starts at [0.8.2]); the actions below were reconstructed from the git history (release commits + PR titles/bodies) and verified against the actual script source at each tag. Where the history did not record an operator action for a change, that is stated rather than invented.

### v0.4.1

- **[host] board-snapshot board roster became config-driven.** The set of boards `board-snapshot` scans is now read from `~/.kanban-snapshot-boards` (or the `KANBAN_SNAPSHOT_BOARDS` env override) as `<name>:<label>` lines, instead of hardcoded literals. It **defaults to the `dev`+`bridge` pair**, so a stock kanban-dev host needs no action. **If your host snapshots a different set of boards, create `~/.kanban-snapshot-boards`** with your `<name>:<label>` lines, or the snapshot will only cover the default pair.
- **[host] optional `KB_STAGE_WONT_DO` board-env key.** A "Won't Do" terminal column is now supported by `kbcard` (`--column wont_do`) and by `board-snapshot`'s terminal/untriaged detection. Both read `KB_STAGE_WONT_DO` from `~/.kanban-<name>-board.env`. **Only needed if your board has such a column** — set `KB_STAGE_WONT_DO=<stage_id>` in that board's env to use it; leaving it unset simply means that column isn't recognized as terminal.
- **[host] `kbcard --version` no longer 422s on a board without the version field.** It now writes `version_target` only when `KB_CF_VERSION_TARGET` is a real custom-field id (not `000`/unset), and warns instead of failing. Transparent — no action.
- `next-dl` gained `--board <name>` + `KB_DL_CHECKOUT_GLOBS`, and `board-card-start` now correlates by card-id as well as `DL-NNN`. Both are transparent improvements — no action.

### v0.4.2

- **[host] token-resolution order fixed — verify after upgrade.** `kbcard` / `board-snapshot` now honor a board-env `KBCARD_TOKEN_FILE` in the correct precedence. If you had worked around the old order (e.g. an ambient `KBCARD_TOKEN` in your shell), **run the §2 smoke test** after upgrading to confirm your token still resolves.
- **[host] doc correction: `KBCARD_API` is host-env only.** It is resolved **before** the per-board env is sourced, so a `KBCARD_API` placed in a `~/.kanban-<name>-board.env` file is **ignored**. If you had put it there, **move it to `~/.kanban-host.env`** (INSTALL §3). No code change forces this, but a board-file `KBCARD_API` silently does nothing.

### v0.4.3 — v0.4.4

- **[host] `kbcard list --column` undercount fixed (v0.4.3), then an argv-overflow + truncation regression fixed (v0.4.4).** Before v0.4.3, `kbcard list --column X` silently stopped at the first page; the fix paginates it, and v0.4.4 repairs a follow-on regression on large boards. **Awareness only, no action** — but any automation that keyed off the old (undercounted) numbers will now see the true, larger counts. There is no config change.

### v0.5.0

- **[host] two new tools — re-run the symlink loop.** `dl-a1-register-field` and `dl-a0-backfill-triaged` were added to `bin/`. A symlink install won't pick up a *new* tool automatically, so **re-run the INSTALL §2 link loop** (also shown in §2 above) after pulling.
- **[host] `dl-a1-register-field` needs a one-time board setup.** It registers the `dl_number` custom field on a DL board and real-surface-verifies the server's `system=dl` by-ref index. **Run it once per board that mints DLs** (`dl-a1-register-field --board <name>`); it is idempotent (a re-run is a clean no-op). `next-dl`'s atomic-claim path depends on that field existing. `dl-a0-backfill-triaged` is a one-shot sweep that backfills the `triaged` tag onto pre-existing adapter-owned cards — run it once per board if you rely on the untriaged-discovery check over a legacy card corpus.
- **[host] loud-on-cap / fail-closed posture (FR-2/FR-3).** A board read that hits the pagination cap now **errors loudly** instead of silently returning a truncated set, and ambiguous states fail closed. This is the intended hardening, **but** any wrapper that previously consumed a silently-capped partial result will now see a **non-zero exit** — update wrappers that swallowed the old (wrong) success.

### v0.6.0 — v0.6.1

- **[release-CI] cause-aware promote exit + shift-left card-coverage check (v0.6.0).** The promote step now distinguishes failure causes on its exit code and checks card coverage earlier in the release. **[vendor] re-vendor `promote-released-cards`** (§3) to pick it up; a release whose cards aren't covered may now be flagged earlier. No config change.
- **[vendor] `promote-released-cards` jq argv-overflow fixed on large boards (v0.6.1).** The paged board is now accumulated via stdin rather than argv (fixes `jq: Argument list too long`). If your board is large, **re-vendor `promote-released-cards`** (§3). No config change.

### v0.7.0

- **[host] `kbcard --type` behavior change — undeclared aliases now TAG instead of ERRORING.** Before v0.7.0, `--type` accepted a fixed set of six aliases (`dl|release|request|fr|bug|idea`) and **errored** on any other alias or on an alias not defined for the board. Now `--type` is config-driven: it resolves **any** `KB_TYPE_<ALIAS>` key from the board env to that native `card_type_id`, and for an alias with **no** native id (or when `KB_TYPING_MODE=tags` is set) it applies a `type:<alias>` **tag** instead — it no longer errors. **Action:**
  - To type cards **natively** on your board, add `KB_TYPE_<ALIAS>=<card_type_id>` keys (uppercased, `-`→`_`, e.g. `KB_TYPE_TECH_DEBT`) to `~/.kanban-<name>-board.env`.
  - To force **tag** mode board-wide, set `KB_TYPING_MODE=tags` in that env.
  - Be aware: because an unknown alias no longer errors, a **typo'd `--type` now silently produces a `type:<typo>` tag** rather than a hard failure. Don't rely on the old error to catch mistyped types.
- **[host] `board-snapshot` pagination fix.** In-flight and untriaged counts were short past the default page; they now paginate. Awareness only — snapshot counts may rise. No action.

### v0.8.0

- **[host] `next-dl` stops masking a failed atomic claim.** It now surfaces a present-but-failed server-side DL claim (non-zero exit) instead of silently falling through, and paginates its offline header-scan fallback. Intended hardening — **update any wrapper that assumed `next-dl` always succeeded**; it may now exit non-zero where it previously masked the failure.
- **[host] `kbcard --pr-url`** was added to `patch` + `create-card` (sets `payload.pr_url`). Opt-in new capability — no action.

### v0.8.1

- **[host/vendor] DL number pad width changed 3 → 4 (`DL-NNN` → `DL-NNNN`).** Newly minted or normalized DLs render zero-padded to four digits (`DL-0001`). **No migration required:** the width is purely cosmetic — every reader extracts the digits and compares **numerically**, so pre-existing 3-padded cards and `## DL-NNN` decision-log headers stay valid and mixed widths coexist. Awareness only.
- **[host] `kbcard --dl` is normalized at the write-site** (#3400): a `--dl` value is canonicalized to `DL-NNNN` and a non-DL shape (a `pr_url`, a version string, an out-of-range overflow) is now **rejected** at write time. Awareness — a malformed `--dl` errors where it may previously have been stored as-is.

### v0.8.2

- **[vendor] NEW file dependency: `bin/_kb-board-lib.sh`.** The shared config/API/pagination/DL-canon library was extracted, and these six tools now `source` it: **`kbcard`, `board-snapshot`, `next-dl`, `dl-a0-backfill-triaged`, `dl-a1-register-field`, `board-card-start`**. Consequences:
  - **[vendor] critical:** a product repo that vendored **any of those six** must now **also vendor `bin/_kb-board-lib.sh` alongside it**. A vendored tool is a plain file copy; it resolves the lib next to itself, so a re-vendor that copies only the single old tool file will **break at runtime** (`_kb-board-lib.sh: No such file or directory`). In the same re-vendor PR (§3), `cp ~/agent-board-toolkit/bin/_kb-board-lib.sh bin/_kb-board-lib.sh`, add it to the commit, and record it — the drift-check verifies each file against the toolkit but will **not** add the missing lib for you.
  - **Exception — `promote-released-cards` is deliberately standalone** and does **not** source the lib (it intentionally duplicates the host-guard so it can be vendored as one self-contained file). If the only tool you vendor is `promote-released-cards`, you do **not** need `_kb-board-lib.sh`.
  - **[host] symlink installs are unaffected.** Each tool resolves the lib via `readlink -f` back to the toolkit's real `bin/`, so a symlinked tool finds `_kb-board-lib.sh` in the source checkout automatically — no separate action (re-running the §2 loop is harmless but not required for the lib).
- **[host] board reads now paginate via `fetch_board_cards` — no silent truncation** (#47, DL-A0). Awareness only — a full large board is returned where a page could previously be dropped.
- The bridge-parity release infrastructure (`VERSIONING.md`, `docs/CHANGELOG.md`, `.release-pr.json`) landed here. These are **toolkit-repo-internal** — a consumer needs no action. (`.release-pr.json` is per-consumer-repo config you already maintain per §4; nothing about its schema changed.)

### Unreleased (on `dev`, after v0.8.2) — security hardening

- **[release-CI/vendor] fail-closed `KANBAN_EXPECTED_HOST` host guard — REQUIRED new promote-CI variable, no default.** `promote-released-cards` (and `board-card-start`) now validate `.release-pr.json`'s `api_base` against `$KANBAN_EXPECTED_HOST` **before** sending the writeback token, and there is **no baked default** — an unset var makes the guard **fail closed** (token never sent, promotion skipped with a loud CI error). **This is the one action an upgrader must not miss when re-vendoring the guarded `promote-released-cards`.** The exact steps — adding `KANBAN_EXPECTED_HOST` (and, if your workflow injects `api_base` from a variable, `KANBAN_API_BASE`) to the promote step's env and setting the repo/org variable — are in the **§3 warning box** above and summarized in **§5**. The drift-check will **not** catch a missing var (it checks the script, not your workflow env). **[host]** symlink installs that don't run the promote workflow are unaffected.
- **[host] `bin/board-transition-sync` RETIRED — remove its `PostToolUse` hook entry from `~/.claude/settings.json`** (#3649). The hand-rolled single-card mover had three defects (2026-07-08 incident, reported upstream): it grepped the first `DL-NNN` from the whole `gh pr create` command (PR *bodies* citing historical DLs moved unrelated Released cards), matched the card `dl_number` by exact string (silently inert against the zero-padded `DL-%04d` canonical form), and scanned boards in a fixed order on a false cross-board-uniqueness assumption. The bridge writeback supersedes it (correct title/branch-only extraction, numeric compare, repo-routing; bridge DL-174 fixed the 1:1-board correlation) — put the PR's own `DL-NNN` in the PR **title** and the bridge moves the card on opened/merged. **Action:** delete the hook block referencing `board-transition-sync` from `~/.claude/settings.json` `hooks.PostToolUse`, and remove any stale `~/.local/bin/board-transition-sync` symlink/copy.
- **[host/vendor] token kept out of argv** (#52) and **baked infra host scrubbed from the toolkit** (#53). The writeback bearer token is no longer passed on the command line (it stays out of the process table), and the previously-baked host literal was removed — which is *why* `KANBAN_EXPECTED_HOST` now has no default. Both are transparent to operators beyond the required-var action above; **no separate action.**

### v0.14.0

- **[vendor/release-CI/host] SECURITY — re-vendor `promote-released-cards`; the `api_base` host guard could be bypassed.** The guard that validates `.release-pr.json`'s `api_base` before the bearer token is sent terminated the URL authority at `/` alone, where RFC 3986 ends it at the first of `/`, `?` or `#`. An `api_base` of `https://evil.example#@your.real.host` therefore parsed as `your.real.host` and was **accepted**, while curl discarded the fragment and sent the token to `evil.example`. Since `api_base` lives in a **committed, PR-editable** file, a pull request alone was sufficient — no access to the victim's `$HOME` or git config. Both copies of the guard (`bin/_kb-board-lib.sh`'s `kb_require_https_host` and `bin/promote-released-cards`' standalone `host_ok`) are fixed.
  - **[vendor] Action:** a repo that **vendored `promote-released-cards`** must **re-vendor it** (§3) — the vendored copy carries its own guard and does not track the toolkit. Until you do, that repo's promote workflow keeps the bypassable guard, and its exposure is the `KANBAN_WRITEBACK_TOKEN` CI secret. Exposure requires your promote workflow to run against untrusted config (e.g. `pull_request_target`); a workflow triggered only on `push` to a protected branch is not exposed, but should still re-vendor.
  - **[release-CI] Action:** if you consume the **SHA-pinned composite action** (§6a), bump the pin — `promote/action.yml` is unchanged, so you get the fix in `bin/promote-released-cards` with the bump alone.
  - **[host] No action** — a symlink install picks it up on `git pull`.
  - Legitimate `api_base` values are unaffected: subdomains, `:port`, real `user:pw@` userinfo, and queries all still pass. If a *valid* `api_base` of yours now refuses, that is a bug — report it.
