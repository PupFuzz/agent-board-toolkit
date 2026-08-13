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
kbcard list --column backlog | jq 'length'  # smoke test -> a number on stdout, plus one stderr line
                                            # `… <M> of <N> board cards matched` (the filter's denominator,
                                            # printed on every filtered read — not an error)
```
If any **new** tool was added, re-run the symlink loop from INSTALL §2 to pick it up:
```bash
for t in ~/agent-board-toolkit/bin/*; do ln -sf "$t" ~/.local/bin/"$(basename "$t")"; done; hash -r
```

> **`pull --ff-only` upgrades this checkout only while its HEAD is on a branch.** That is the INSTALL §1 **Option A** clone topology — the recommended one, and the one this section assumes. If the checkout has been **detached at a tag** — by a §5 rollback, by a deliberately pinned second checkout, or by a `checkout v<version>` line copied out of a release note — the command above answers `You are not currently on a branch.` and exits **1** instead of upgrading. Return it to the tracking branch first (`git -C ~/agent-board-toolkit checkout main`), then pull. The pin's real cost is quieter than that error, though: an install nobody pulls simply never sees the next release. `agent-board-toolkit-runtime-check` is the guard for exactly that (`board-snapshot` runs it at SessionStart), and its remediation line **branches on your topology** — it names `pull --ff-only` for a checkout on a branch and the pin-advancing `checkout <tag>` only for one that is already detached.

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
- **Rollback on the host is a deliberate, temporary pin — not the mirror image of the upgrade.** `git -C ~/agent-board-toolkit checkout <previous-tag>` **detaches HEAD**: the install stops advancing, and §2's `git pull --ff-only` exits 1 until you return it with `git -C ~/agent-board-toolkit checkout main`. That is the pinned topology INSTALL §2's warning box tells you to stay out of, so undo the pin once the reason for it is gone. While it stands, `agent-board-toolkit-runtime-check` fails loud every session — intended, not noise: you are knowingly behind. (Do not substitute `git reset --hard <previous-tag>` to keep HEAD attached; that diverges the branch from its upstream and breaks `--ff-only` too.) Repos roll back by reverting the vendor-bump PR. No *state* is stored in the toolkit, so no data is ever at risk — the topology change is the part that persists.

## 6. Version-specific upgrade actions

§1–§5 are the mechanics (pull, re-vendor, drift-check). This section is the **content**: the changes across `v0.4.1 → v0.27.0` that require an upgrader to **do** something (set a var, add a file, re-run a loop, deploy in a particular order, or knowingly accept a changed behavior). Feature additions that need no action are omitted from an entry's bullets. **Find your installed version (`cat ~/agent-board-toolkit/VERSION`) and walk forward from the next entry — each entry is cumulative.**

> **Every release has an entry; a release that asks nothing of you says so.** A release requiring no action carries a **No upgrade action** line rather than being left out, so a gap in this walk can only ever mean a doc defect — never "nothing was required". *No upgrade action* means nothing **beyond** the routine mechanics above: §2's `git pull` on the host, and §3's re-vendor + drift-check in any repo that vendored a tool which changed in that release. Keeping this section complete is a release-time obligation, not a courtesy — `VERSIONING.md` § The §6 upgrade-action rule owns it, and the release-artifact gate asserts it.

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

- **[host] token-resolution order fixed — verify after upgrade.** `kbcard` now honors a board-env `KBCARD_TOKEN_FILE` in the correct precedence. If you had worked around the old order (e.g. an ambient `KBCARD_TOKEN` in your shell), **run the §2 smoke test** after upgrading to confirm your token still resolves. *(Scope correction, made in v0.14.0: this entry originally also named `board-snapshot`, which was never true — `board-snapshot` resolved its token before sourcing any board env at every version up to v0.13.0, so a board-env `KBCARD_TOKEN_FILE` never reached it. It honors one as of **v0.14.0**. The `kbcard` half was accurate here, then silently regressed in v0.8.2 — see the **v0.14.0** entry.)*
- **[host] doc correction: `KBCARD_API` is host-env only.** It is resolved **before** the per-board env is sourced, so a `KBCARD_API` placed in a `~/.kanban-<name>-board.env` file is **ignored**. If you had put it there, **move it to `~/.kanban-host.env`** (INSTALL §3). No code change forces this, but a board-file `KBCARD_API` silently does nothing. *(Accurate as written for v0.4.2–v0.8.1. v0.8.2 inverted the source order and began silently **honoring** a board-env `KBCARD_API`; as of **v0.14.0** it is **refused loudly** rather than either ignored or honored — see the v0.14.0 entry for the current rule.)*

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

### v0.9.0 — security hardening

- **[release-CI/vendor] fail-closed `KANBAN_EXPECTED_HOST` host guard — REQUIRED new promote-CI variable, no default** (#52/#53). `promote-released-cards` (and `board-card-start`) now validate `.release-pr.json`'s `api_base` against `$KANBAN_EXPECTED_HOST` **before** sending the writeback token, and there is **no baked default** — an unset var makes the guard **fail closed** (token never sent, promotion skipped with a loud CI error). **This is the one action an upgrader must not miss when re-vendoring the guarded `promote-released-cards`.** The exact steps — adding `KANBAN_EXPECTED_HOST` (and, if your workflow injects `api_base` from a variable, `KANBAN_API_BASE`) to the promote step's env and setting the repo/org variable — are in the **§3 warning box** above and summarized in **§5**. The drift-check will **not** catch a missing var (it checks the script, not your workflow env). **[host]** symlink installs that don't run the promote workflow have no CI action here — but note `board-card-start` gained the same guard at this version, so the **host-level** `KANBAN_EXPECTED_HOST` (in `~/.kanban-host.env`) becomes load-bearing at **v0.10.0**, which revives that hook — see the next entry.
- **[host] `bin/board-transition-sync` RETIRED — remove its `PostToolUse` hook entry from `~/.claude/settings.json`** (#55, #3649). The hand-rolled single-card mover had three defects (2026-07-08 incident, reported upstream): it grepped the first `DL-NNN` from the whole `gh pr create` command (PR *bodies* citing historical DLs moved unrelated Released cards), matched the card `dl_number` by exact string (silently inert against the zero-padded `DL-%04d` canonical form), and scanned boards in a fixed order on a false cross-board-uniqueness assumption. The bridge writeback supersedes it (correct title/branch-only extraction, numeric compare, repo-routing; bridge DL-174 fixed the 1:1-board correlation) — put the PR's own `DL-NNN` in the PR **title** and the bridge moves the card on opened/merged. **Action:** delete the hook block referencing `board-transition-sync` from `~/.claude/settings.json` `hooks.PostToolUse`, and remove any stale `~/.local/bin/board-transition-sync` symlink/copy.
- **[host/vendor] token kept out of argv** (#52) and **baked infra host scrubbed from the toolkit** (#53). The writeback bearer token is no longer passed on the command line (it stays out of the process table), and the previously-baked host literal was removed — which is *why* `KANBAN_EXPECTED_HOST` now has no default. Both are transparent to operators beyond the required-var action above; **no separate action.**

### v0.10.0

- **[host] REQUIRED for local card automation: export `KANBAN_EXPECTED_HOST` from `~/.kanban-host.env`** (INSTALL §3). This release revives `board-card-start` — the post-checkout branch→In-Progress automation was **dead on every install** before v0.10.0 (the hook read `api_base` only from the committed `.release-pr.json`, which is a host-scrubbed placeholder; #61 falls back to the real host from `~/.kanban-host.env`). The revived hook runs the v0.9.0 host guard, which has **no baked default** — and because a checkout hook must never block a checkout, the failure mode is **fail-soft**: without the var the hook exits 0, warns only on stderr, and **no card ever moves**. One host-level export activates card automation for every repo on the host. Symlink hosts that never installed the hook, and repos that only run promote in CI, are unaffected.
- **[host] the revived hook's behavior — accept or opt out per card.** A genuine branch **creation** now auto-moves a **Held** card to In Progress (#59; opt out per-card with a `no-automove` tag or a `block_reason`). A branch `DL-NNN` that resolves to no card **falls through** to a card-id token and **stamps `payload.dl_number`** on the selected card (#60); the bridge's `card#<id>` grammar is now recognized alongside bare card ids. No config change — but if you had parked cards in Held relying on the hook staying dead, review them.
- **[vendor] re-vendor `promote-released-cards`** (§3) to pick up transient-5xx retry (#62) — promote runs no longer fail on a deploy maintenance window. No config change.

### v0.11.0

- **[release-CI] optional migration: `promote-released-cards` as a SHA-pinned composite action** (#66, INSTALL §6a). GitHub-Actions consumers can replace the vendored copy with `uses: <owner>/agent-board-toolkit/promote@<sha>  # vX.Y.Z` — drift becomes impossible and dependabot bumps the pin. **No required action** — vendoring + drift-check (§6b) remains fully supported; migrate at your convenience.

### v0.11.1 — v0.11.4

- **No action.** v0.11.1 switches `kbcard`/`board-card-start` payload writes to per-key delta PATCHes (the kanban server already merges `task.payload` per-key, so this is transparent); v0.11.3 (toolkit-internal CI) and v0.11.4 (release-notes reframe) change nothing a consumer touches.
- **[vendor] v0.11.2 awareness — a missing `_kb-board-lib.sh` is now loud.** The five interactive lib-sourcing bins fail with a self-naming message (and `agent-board-toolkit-drift-check` grows a MISSING-LIB probe that fails CI) when vendored without the co-located lib. The lib has been a required co-vendored dependency **since v0.8.2** — if this newly fails for you, the vendored tool was already broken at runtime; fix it by co-vendoring the lib (§3), not by pinning back.

### v0.12.0

- **[host] new tool `bin/adopt-to-dl` — re-run the symlink loop** (INSTALL §2, shown in §2 above) to pick it up; a symlink install never picks up a *new* tool automatically. The tool itself is opt-in (the pull-into-build adoption seam for card-first boards — stamps an existing plain card with a freshly minted `payload.dl_number`); a board whose `dl_number` is bridge-derived doesn't need it. **[vendor]** it sources `_kb-board-lib.sh` — co-vendor the lib if you vendor it (v0.8.2 rule).

### v0.12.1 — v0.12.2

- **No action.** Docs releases (the DL-counter recovery runbook; the HOOKS.md pinned-card clarification). The one `bin/next-dl` change is comment-only — every executable path, `promote/action.yml`, and `examples/*` are byte-identical to v0.12.0.

### v0.13.0

- **[host] if any repo sets `core.hooksPath`, re-run `install-board-hooks` there.** Before v0.13.0 the installer hardcoded `.git/hooks/post-checkout`; on a repo with `core.hooksPath` (gitleaks, pre-commit, Husky, many Windows setups) git dispatches hooks only from that path, so the install **reported success but the hook never fired**. The installer now targets `core.hooksPath` (and refuses, with guidance, a hooksPath inside the tracked work tree). If your hook has silently never moved a card on such a repo, this is why — re-run the installer after upgrading.
- **[vendor] re-vendor `promote-released-cards`** (§3): the bearer token is now fed to curl via a stdin herestring instead of `-H @<(…)` process substitution. **Required if any promote run executes on native mingw64/Git-Bash curl** (the old form fail-softed every API call there, rc=26); recommended regardless — it also fixes a latent `--retry` bug (the old non-seekable pipe meant a retried request couldn't re-read the auth header). **[release-CI]** SHA-pinned action consumers get it with the pin bump; `promote/action.yml` itself is unchanged.
- **[host] optional: `git config kanban.board-id <id>`** (repo-local, uncommitted) binds a repo with no `.release-pr.json` to a board for `board-card-start` — adopt the hook without adding a committed `api_base` surface. Opt-in; existing installs unchanged. Failed-but-attempted moves are now durably logged to `~/.cache/agent-board-toolkit/board-card-start.log` (`KB_BCS_LOG` overrides) — check there first when a card didn't move. Awareness only.

### v0.14.0

- **[vendor/release-CI/host] SECURITY — re-vendor `promote-released-cards`; the `api_base` host guard could be bypassed.** The guard that validates `.release-pr.json`'s `api_base` before the bearer token is sent terminated the URL authority at `/` alone, where RFC 3986 ends it at the first of `/`, `?` or `#`. An `api_base` of `https://evil.example#@your.real.host` therefore parsed as `your.real.host` and was **accepted**, while curl discarded the fragment and sent the token to `evil.example`. Since `api_base` lives in a **committed, PR-editable** file, a pull request alone was sufficient — no access to the victim's `$HOME` or git config. Both copies of the guard (`bin/_kb-board-lib.sh`'s `kb_require_https_host` and `bin/promote-released-cards`' standalone `host_ok`) are fixed.
  - **[vendor] Action:** a repo that **vendored `promote-released-cards`** must **re-vendor it** (§3) — the vendored copy carries its own guard and does not track the toolkit. Until you do, that repo's promote workflow keeps the bypassable guard, and its exposure is the `KANBAN_WRITEBACK_TOKEN` CI secret. Exposure requires your promote workflow to run against untrusted config (e.g. `pull_request_target`); a workflow triggered only on `push` to a protected branch is not exposed, but should still re-vendor.
  - **[release-CI] Action:** if you consume the **SHA-pinned composite action** (§6a), bump the pin — `promote/action.yml` is unchanged, so you get the fix in `bin/promote-released-cards` with the bump alone.
  - **[host] No action** — a symlink install picks it up on `git pull`.
  - Legitimate `api_base` values are unaffected: subdomains, `:port`, real `user:pw@` userinfo, and queries all still pass. If a *valid* `api_base` of yours now refuses, that is a bug — report it.
- **[host] a board env's `KBCARD_TOKEN_FILE` is honored again — verify your per-board tokens.** For `kbcard`, `next-dl`, `dl-a0-backfill-triaged`, `dl-a1-register-field` and `adopt-to-dl` this is a **restoration, not a new rule**: `kbcard` honored a board-env `KBCARD_TOKEN_FILE` from v0.4.2 through v0.8.1, and the v0.8.2 shared-library extraction silently inverted the source order, so from **v0.8.2 through v0.13.0** it was **ignored** and the host-level (or default `~/.kanban-dev-token`) token was sent instead — to *every* board. For **`board-snapshot` this is genuinely new** (it never honored a board-env token at any version), and **`board-card-start` is the one exception to the ladder** — it honors a board's token only for a repo whose board id is host-local (see its own entry below). The precedence:
  > **a board env's `KBCARD_TOKEN_FILE` > the host env's > an ambient one > `~/.kanban-dev-token`**

  **Action — only if you set `KBCARD_TOKEN_FILE` in BOTH a board env and `~/.kanban-host.env`.** For those boards the **board's** token now wins where the host's silently did since v0.8.2. That is the documented intent, but it is a live change in *which credential is sent*: confirm each board's token file is the one you want that board to use (`kbcard --board <name> list` per board is the quickest check). If you only ever set one of the two, nothing changes.
- **[host] `board-snapshot` renders per-board tokens — and no longer goes dark without `~/.kanban-dev-token`.** It read **one** token up-front and exited silently when that file was missing, so a host that uses only per-board token files displayed **nothing** at all. It now reads each board's token as it renders that board, and a board whose token is unreadable reports itself (`• <label>: (token file unreadable: …)`) instead of blanking the whole snapshot.
- **[host] a board env that sets `KBCARD_API` is now REFUSED, loudly.** The API base is board-independent. v0.4.2–v0.8.1 ignored a board-env `KBCARD_API`; v0.8.2–v0.13.0 silently **honored** it (the same inverted order as above), so a stray value in a board env quietly re-pointed the tool at another host. `kbcard` / `next-dl` / `dl-a0-backfill-triaged` / `dl-a1-register-field` / `adopt-to-dl` now **refuse** it with a message naming the file, instead of guessing which behavior you meant. **Action:** if any `~/.kanban-<name>-board.env` sets `KBCARD_API`, move it to `~/.kanban-host.env` (INSTALL §3). Refusal is **not uniform** — know what you are looking at: `kbcard` / `dl-a0-backfill-triaged` / `dl-a1-register-field` / `adopt-to-dl` **exit 2 and will not run** until you move it, while `next-dl` **warns, skips the board check, and still mints from its offline scan** (it is fail-soft by contract). For `next-dl` the message is therefore your *only* signal that it silently lost both the atomic claim and the board's `dl_number` seed — do not ignore it. `board-snapshot` and `board-card-start` never read a board env's `KBCARD_API` at all, so they ignore it as they always have.
- **[host] `board-card-start` — per-board tokens are a host-local opt-in.** The hook consults a board env's `KBCARD_TOKEN_FILE` **only** when the repo's board id came from a repo-local `git config kanban.board-id`. When the board id comes from the committed `.release-pr.json`, the hook keeps using the host/default token exactly as before — a committed, PR-editable file must not be able to select which board's credential the hook sends. `git config kanban.board-id` now also takes precedence over `.release-pr.json`'s `promote.board_id` (in practice the two are mutually-exclusive populations, so this rarely decides anything). **No action** — an install that sets no per-board token behaves identically.
- **[host] `board-card-start` reports *why* a card did not move.** A card fetch that failed on an unreachable API, a rejected token (401/403), or a server error used to be reported as **"card … does not exist"** — sending you to hunt a missing card instead of a broken token. Each cause is now named distinctly in the diagnostic log. Awareness only; no action.

### v0.15.0

- **[host] new tool `bin/agent-board-toolkit-runtime-check` — re-run the symlink loop.** It judges what actually **executes** rather than the checkout, catching the two live-observed topologies a "patch the checkout, then grep the checkout" verification certifies wrongly: real-file **copies** (native mingw64 `ln`, a manual `cp`) and a **pinned runtime** (`PATH` resolving into a checkout detached at a tag that never advances). It also warns on a mixed runtime — a partial upgrade where the on-`PATH` tools disagree about the lib they source — and reports an unverifiable topology as UNKNOWN rather than passing it silently. A symlink install never picks up a *new* tool by itself, so **re-run the INSTALL §2 link loop** (also shown in §2 above) after pulling.
- **[host] a short board read now exits 4 — it used to exit 0, so check anything that wraps these tools.** `fetch_board_cards` detected `total > read_n`, warned INCOMPLETE, and then returned **0**, so a caller could act on a read the lib had just declared incomplete (`next-dl` minted a DL from one). It now exits **4** with the partial data still emitted, and `next-dl` / `dl-a0-backfill-triaged` refuse it. **Update any wrapper that ignored the exit code of a board read, or that treats every non-zero as fatal** — rc 4 means "partial, and it says so".
- **[vendor] re-vendor `bin/_kb-board-lib.sh` — and `bin/promote-released-cards` if you copied it.** The lib carries the rc-4 backstop above and the restored API error body (a 403 token-scope failure and a 422 validation failure were indistinguishable in the failure log after the v0.8.2 extraction). The `promote-released-cards` change is diagnostic-only: a *local* dry-run derives its baseline from local tags and can over-report the shipped range, so it now says so on stderr (suppressed under `GITHUB_ACTIONS`, where the invocation is remote-truth by construction).

### v0.15.1

- **No upgrade action.** Two fixes on host tools: the v0.15.0 staleness guard's warning now reaches its reader (it was written to **stderr**, and the SessionStart hook that consumes `board-snapshot` surfaces only stdout — a correct, installed guard that nobody could see), and `board-snapshot` renders each board's own column names instead of a hardcoded `In Progress`/`In Review`/`Held` map that a board-side rename silently falsified. `_kb-board-lib.sh` also gains an **opt-in** `KB_CURL_MAX_TIME` per-request cap; unset — the default — is byte-identical behavior, and it should be set around a *read*, never exported process-wide over the bins that write (a timed-out POST/PATCH is ambiguous, not failed).

### v0.16.0

- **No upgrade action.** New `kbcard archive` and `kbcard delete [--hard]` verbs (the board API has no HTTP `DELETE`; these replace the hand-rolled `curl` that removal previously required) plus two `board-snapshot` fixes — a board no longer inherits a **sibling board's** stage ids in its untriaged count, and each board is fetched once per run instead of twice. Untriaged counts may change on a host that snapshots more than one board: that is the fix landing, not a regression.

### v0.17.0

- **[host] `install-board-hooks` now installs TWO hooks — re-run it in every repo that has it.** `hooks/pre-push` joins `hooks/post-checkout`: a **fail-soft** advisory that warns when a branch name references a card in a spelling the auto-move grammar will not accept (e.g. `card_4524`), reusing the mover's own matcher so the two can never disagree. It never blocks a push and always exits 0. An existing install carries only the post-checkout symlink — `install-board-hooks <repo>` again to pick the second one up (still non-destructive: it refuses to clobber a repo's own non-symlink hook).
- **[host] the branch→card grammar widened, so a branch that moved nothing may now move a card.** The separator after `card` is optional: `card4524`, `card-4524`, `card/4524`, `card#4524` and `#4524` all correlate. It still requires the literal `card`/`#` at a token boundary and ≥2 digits, so DL tokens and version numbers stay safe. **Awareness** — if you were relying on the glued spelling being inert, opt the card out with a `no-automove` tag or a `block_reason`. The bridge writeback is unchanged and still wants `card-<id>`/`card#<id>`.
- **[host] optional: name your swimlanes in the board env.** `kbcard list --swimlane <name|id>` resolves names from **id-keyed** `KB_SWIMLANE_<id>=<name>` entries in `~/.kanban-<name>-board.env` (see `examples/kanban-board.env.example`); without them the filter still works by numeric id, and a board declaring none says so rather than printing an empty list. Also new and opt-in: `create-card --triaged`.

### v0.18.0

- **No upgrade action.** New optional `--issue` / `--issue-url` correlation flags on `kbcard create-card` and `patch` (they stamp `payload.issue_number`/`payload.issue_url`), an unconfigured-board error that now names its own fix instead of reading as breakage, and three same-behavior consolidations (payload assembly, the selftest prelude, assorted intra-file dedup). No config migration.

### v0.19.0

- **No upgrade action.** `kbcard patch --swimlane <name|id>` closes the write side of the read filter that shipped in v0.17.0 (`--swimlane none`/`0` un-assigns), and an unresolved swimlane **name** now enumerates the board's defined lanes instead of leaving a reader to infer the board has none. Both read the same optional `KB_SWIMLANE_<id>=<name>` board-env entries recorded under **v0.17.0**; no existing invocation changes.

### v0.20.0 — deploy-ordering release

- **[host/vendor/release-CI] the v3 flat task-write cutover is UNCONDITIONAL — these tools must run against a kanban carrying DL-219.** Every task `POST`/`PATCH` now sends the task object **flat** (top-level), dropping the `{task: {…}}` envelope. There is **no version probe, no wrapped fallback and no shim**, so this release moves in lockstep with the kanban deploy: **do not advance a host, or re-vendor, past v0.19.0 until the kanban your tools write to serves DL-219** — and once that deploy lands, a copy still sending the wrapped body is the one that breaks. Eight write sites across `kbcard` (create-card/move/patch), both `board-card-start` writes, `dl-a0-backfill-triaged`, `dl-a1-register-field` and `promote-released-cards` are affected, so **[vendor] re-vendor every one of those you copied**, in the same window. `task_links` / `_action` bodies are unaffected.
- **[host] `kbcard archive` can now refuse.** It gates on the framework's shipped `may_archive` invariant and **refuses (rc 1)** to archive the only card of a still-live, untwinned coordination source; `--force` overrides and is audited, and an unlocatable `may_archive` primitive fails loud rather than archiving anyway. Accept the refusal, or pass `--force` knowingly.
- **[host] `board-session-close`'s inverse-drift leg moved to the framework's `kanban-reconcile.py --detect`, and it can now tell you the check is OFF.** The hook is resolved version-agnostically (`$KANBAN_RECONCILE_HOOK` → the coord plugin dir on `$PATH` → the marketplace clone → the newest cached version), and an **unresolvable** hook is now rc 1 `DID NOT RUN` instead of a silent skip. **Action, if you want the inverse leg armed:** give each board an `inverse_check_columns` entry in `coordination.config.json`'s `kanban.boards[]`. Without it the hook runs the forward leg only and the ritual prints a loud `⚠` naming the board — OFF is a legitimate choice, and the warning exists so degraded coverage is never read as a clean pass.

### v0.20.1

- **No upgrade action.** Test/CI only: a network-free static guard that fails if any `bin/` file re-introduces the `{task: {…}}` wrapper the v0.20.0 cutover removed — including the standalone-vendored `promote-released-cards`, which cannot source the shared lib — plus a docs stamp sync. **No file under `bin/`, `hooks/`, `promote/` or `examples/` changed at this release**, so there is nothing to re-vendor.

### v0.21.0

- **[host] declining a card now CLEARS its refs — pass `--keep-refs` if you were relying on them staying.** Both decline call-sites (`kbcard move --column wont_do` and `patch --column wont_do`) null `payload.dl_number`, `pr_number` and `pr_url` in the same PATCH, closing the write-site half of the stale-stamp class: a recycled ref could otherwise resurrect a declined card into Released at the next promote. `--keep-refs` opts out, an explicit ref flag passed in the declining call still wins, and non-decline moves are byte-unchanged.
- **[release-CI] optional anti-resurrection guard: `--shipped-stages <ids>` / the `shipped-stage-ids` action input.** A DL/PR-matched card whose current stage is outside the given set is skipped and logged instead of promoted. **Opt-in — absent is byte-identical to the previous behavior** (proven empirically), so adopt on your own window; a malformed set is rc 2 before any PATCH. **[vendor]** re-vendor `promote-released-cards` (or bump the action pin) to have the flag at all.
- **[host] new `kbcard field list` / `field set-options` verbs** — a custom-field schema read plus an idempotent converge-to-set enum reconcile (never an append). Opt-in; one semantic worth knowing before you use it: option **removal is definition-only**, so a card keeps a removed value orphaned — no clear, no cascade.

### v0.22.0

- **[host] optional new dispatch-time card move — registering it is a manual step.** `hooks/agent-dispatch-card-start` is a Claude Code **`PreToolUse`** hook for the subagent-dispatch tool: it moves a card to In Progress the moment a build is dispatched, closing the window `hooks/post-checkout` only closes at branch creation. It is that hook's **peer, not its replacement** — either may fire first and the move is idempotent — and it acts **only** on a line-start `BOARD-CARD: <board-key>#<card-id>` marker in the dispatch prompt (a bare card-number scan is deliberately not used; prose mentions many ids). **`install-board-hooks` does NOT install it** and never will: it symlinks git hooks, and this is a `settings.json` entry. **Action, if you want it:** add the `PreToolUse` `Agent`-matcher block from [`HOOKS.md`](HOOKS.md) to your Claude Code `settings.json`. Fail-soft on every path (it always exits 0 — a non-zero `PreToolUse` would block the dispatch). Skip all of this if you do not dispatch subagents.

### v0.23.0

- **No upgrade action.** `board-session-close` gains a **read-only** "archive-eligible done cards" leg: per configured board it reports the un-archived done-card count and runs a bounded sample through the shipped `may_archive` gate to show concrete candidates. It surfaces, never archives — the authoritative per-card gate stays in `kbcard archive`. Its two new files are `_`-prefixed **siblings**, resolved beside the real `board-session-close` through `readlink -f` rather than looked up on `PATH`, so they need no symlink loop.

### v0.23.1

- **[host/vendor] the CLIs now REJECT `--flag ""` where they silently accepted it.** An explicitly-empty value was indistinguishable from an absent flag, so it selected a **default path** and exited 0 — an unexpanded shell variable was the usual way in. **Any caller using `--flag ""` to mean "use the default" must omit the flag instead**; whitespace-only values already died and are unchanged. Two of the shapes this closes show the cost: `kbcard patch --dl "$DL"` with `DL` unset PATCHed `{}` and reported success (leaving a card without the ref it needs to ever promote), and `promote-released-cards --shipped-stages ""` ran **unguarded** with a summary byte-identical to a guarded run. **[vendor] the vendored surface IS affected** — re-vendor `bin/kbcard`, `bin/_kb-board-lib.sh`, `bin/promote-released-cards` and `bin/release-pr-body`; `promote/action.yml` is unchanged, so action-pinning consumers see no interface change.
- **[release-CI] check how your promote step wires `shipped-stage-ids`.** `docs/INSTALL.md` §6a used to recommend `shipped-stage-ids: ${{ vars.KANBAN_SHIPPED_STAGE_IDS }}`; an **unset** variable renders blank, the action correctly omits the flag, and the promote then runs **unguarded** while the workflow still reads as guard-enabled. The recipe is now a literal, with the variable form demoted to an aside carrying a preflight. **If you copied the variable form, either set the variable or inline the ids.** Relatedly, an unguarded promote now announces itself on **stderr** (the summary is deliberately byte-identical-when-absent, by an explicit v0.21.0 compat decision).

### v0.24.0

- **[host] four narrowings — each closes a wrong input that was answered at rc 0.** (1) `kbcard "" <verb>` printed usage and exited **0**, so a caller checking `rc` read a no-op as a completed write; an empty first argument is now a failed expansion, not a help request. (2) An explicitly-empty **positional** is refused by name across the bins that take one — it was previously invisible and let the next argument take its place, so `install-board-hooks "" <repo>` installed into `<repo>`. (3) `board-card-start` honours `--lint` in any position and refuses an empty/unknown/extra argument; it previously dropped a non-leading `--lint` and moved a card for real. (4) Guards spelled as bash bracket **ranges** are pinned to ASCII, so under a UTF-8 shell they no longer admit the wider set the locale's collation allowed. **Re-check any script that passed an empty argument deliberately.** One further observable: `patch --triaged` no longer re-**sorts** the card's tags.
- **[host] `install-board-hooks` now INSTALLS into topologies it used to refuse — re-run it there.** A `--separate-git-dir` checkout and a submodule are supported (the linked-worktree refusal is unchanged), and the hook-health rules were rewritten around real failure modes: an **empty** `core.hooksPath` (git then dispatches *no* hooks at all — it does not fall back to `.git/hooks`), a `~`-prefixed or `..`-escaping one, a non-canonical path spelling, and a hook that carries the executable bit but cannot be exec'd (CRLF endings, a missing shebang interpreter). **If the installer ever refused one of your repos, or a card quietly stopped moving in one, re-run it now** — and note `board-session-close` gained a leg that reports checkouts whose `post-checkout` no longer reaches `board-card-start`, which is how you find the rest.
- **[vendor] a broad re-vendor release.** Eleven `bin/` files changed, including `_kb-board-lib.sh`, `kbcard`, `next-dl`, `promote-released-cards`, `board-card-start`, `adopt-to-dl`, `install-board-hooks` and both `dl-a*` bins — re-vendor whichever you copied (§3), remembering the lib for any lib-sourcing bin. `promote/action.yml`'s vendor surface is unchanged. New capability, no action: `kbcard patch --name / --tags / --type / --external-id / --origin` can now correct the five fields that were previously settable only at birth (`--tags` **replaces** the whole list; `--type` strips any `type:*` tag before writing the native id), plus `create-card --swimlane` and `list --swimlane none|0`.

### v0.25.0

- **[host/vendor] one narrowing: `agent-board-toolkit-drift-check` refuses a third positional.** `agent-board-toolkit-drift-check <toolkit> <repo> <anything-else>` previously exited **0** with `drift-check: OK`, reading the first two arguments and dropping the rest without a word — a green drift report about something other than what was asked, in the tool that *is* the drift gate. It now exits **2** naming the extra argument, and an empty-positional refusal says **which** slot is empty. Every documented invocation passes exactly two positionals; fix any caller of yours that passes more.
- **[host] new tool `bin/release-artifacts-check` — re-run the symlink loop** if you want it on `PATH` (same reason as v0.15.0: a symlink tracks its target's content, not the set of tools).
- **[release-CI] optional: adopt the `release-artifacts/` composite action.** It asserts that every member of your `.release-pr.json` `artifacts` array actually moved in a release PR — present in the PR's own changes, still existing at head, and carrying the version being shipped — where that array was previously only *printed* as a `- [ ]` checklist. SHA-pinned on the same terms as `promote`; the recipe is `docs/INSTALL.md` §6c, and see **v0.26.0** for the `types:` line that recipe was missing. A repo that declares no `artifacts` array is unaffected: the check reports that nothing was declared and exits 0.
- **[host] `board-card-start` gained `-h`/`--help`** (previously the only usage surface a hand-typed invocation reached was the unknown-option refusal, whose remedy read as advice to target a branch literally named `--help`). No action.

### v0.26.0

- **[host] `next-dl --peek` now answers from the board's DL counter, not an offline scan — stop treating the old answer as authoritative.** `--peek` took its maximum over DL numbers that had reached a **card**, so a number already claimed from the counter but never stamped was invisible to it and `--peek` handed back a number the server had already issued (measured on a real board: `--peek` said `DL-0220` while the counter's next was **222**). A DL is a correlation key, so a reused one silently merges two unrelated work items. `--peek` now reads the board's non-consuming DL-sequence counter and falls back to the offline scan only where that endpoint is **absent** (404/unreachable ⇒ pre-endpoint behavior, unchanged). **Two live changes:** a board whose kanban serves the route starts reporting different, authoritative numbers — if your `--peek` and a direct counter read disagree, your `next-dl` predates this fix — and a **present-but-errored** endpoint is now rc 1 with the cause on stderr, where it previously answered a plausible wrong number from the floor. The default (claim) path is untouched.
- **[release-CI] optional: `card_token_regex` in `.release-pr.json`, and `promote-released-cards --cards`.** If your commit subjects say `card#NNNN` rather than `DL-NNN`, `release-pr-body`'s `## Card coverage` section derived an unconditionally empty manifest and reported clean **without checking anything**. Add a `"card_token_regex"` key — and **do not simply re-spell `ref_token_regex`**: its numeric part is matched against `payload.dl_number`, so under a `card#` spelling `card#42` correlates with whichever card carries **DL-42**. The two keys are two id spaces (`ref_token_regex` → `payload.dl_number`; `card_token_regex` → the card's own `id`). Adopting neither key is byte-identical, but note that `examples/release-pr.json.example` now sets it, so a config copied from that template has the coverage section on.
- **[release-CI] if you copied the `INSTALL.md` §6c release-artifacts recipe before this release, add `edited` to its `types:`.** Retargeting a PR's base fires `edited`, not `synchronize`, and the gate's verdict is a function of the base (the merge base drives both the classification and the asserted diff) — so a stale verdict survived a base retarget. The same omission was fixed in this repo's own gate.
- **[vendor] re-vendor `bin/next-dl`, `bin/promote-released-cards` and `bin/release-pr-body`.** `promote/action.yml`, `bin/kbcard` and `bin/_kb-board-lib.sh` are unchanged this release.

### v0.27.0

- **[host] new tool `bin/dependabot-deploy-reconcile` — re-run the symlink loop.** Same structural reason this section gives every time a release adds a bin: a symlink tracks its target's *content*, not the *set* of tools, so a new tool never lands on `PATH` without the loop. `agent-board-toolkit-runtime-check` gains the new tool in its `TOOLS` set and will print a warn line naming exactly that until you re-run it — that line is the check doing its job, and the re-symlink it prescribes is the fix. The tool itself is host-local and read-only (it asks whether the fix a *closed* Dependabot alert claims is actually present in what is deployed and running); it writes only its own JSON artifact under `~/.cache/coord/dependabot-reconcile/`.
- **[host] two new preflight entries in [`INSTALL.md`](INSTALL.md) §0 — neither is fatal.** `ps`: absent, the new tool reports an instrument failure rather than a wrong answer. Coreutils `timeout`: absent — the default on macOS, and possible under an MSYS install — `board-session-close`'s advisory legs still run, each printing a one-line warning that it is running **unbounded**. Install coreutils if you want the 60s per-leg bound.
- **Awareness, no action:** `board-session-close` grows a `── Dependabot fixed-alert vs deployed-tree reconciliation ──` section and runs both advisory legs under that 60s wall-clock bound (a killed leg prints a ⚠ and still never blocks the close). The archive leg's missing-sibling warning was reworded in the same extraction — relevant only if something of yours matches on its exact text.
