# agent-board-toolkit — new install

Follow top to bottom. Every command is copy-pasteable; placeholders are in `<angle brackets>` or `ALL_CAPS`. Expected output is shown after each verify step.

## 0. Prerequisites

```bash
for c in bash curl jq git gh ps timeout; do command -v "$c" >/dev/null && echo "ok: $c" || echo "MISSING: $c"; done
```
All must print `ok:`. (`gh` is only needed for tools that touch GitHub — `board-session-close`, `dependabot-deploy-reconcile`, and `gh-code-search`, which is a thin guarded wrapper around `gh api search/code` and refuses at rc 2 without it. `release-pr-body` needs no `gh`, but it does need `git fetch` access to `origin` — it resolves **both ends** of the release range from the remote: the baseline from the remote's release branch, since the local one is stale by design under the branch-off-dev flow, and the head from the remote's integration branch, since the local one lags every merge that lands after a release worktree is cut. Each leg has its own explicit override — `--base <tag>` and `--head <ref>` — and each skips only its own leg's fetch, so an offline run passes both. An explicit ref must still **resolve in the checkout**: the flag says which ref to use, not that a ref this repo does not have should be read as an empty range, so a `--base`/`--head` naming no commit here is refused at rc 2 rather than generating a body and a `shipped-cards` manifest that list nothing.)

Two of these are newer and **not** fatal if missing, so they are listed to be checked rather than assumed:

- **`ps`** — `dependabot-deploy-reconcile` reads the whole process table to decide whether the tree it inspects is the one actually running. Without it that tool reports an instrument failure rather than a wrong answer.
- **`timeout`** (coreutils) — bounds each advisory leg of `board-session-close`. **macOS ships no `timeout` by default**, and the MSYS/Git-Bash install in §2 may not either. When it is absent the legs still run, and each one prints a one-line warning saying it is running **unbounded**: it can no longer hang the close's exit code, but it can hang its clock. Install coreutils (`brew install coreutils` provides `gtimeout`; symlink or alias it as `timeout`) to get the bound back.


## 1. Get the toolkit

```bash
# Option A — clone (recommended; makes upgrades a `git pull`):
git clone <agent-board-toolkit-remote-url> ~/agent-board-toolkit
# Option B — if you were handed a copy, just place it at ~/agent-board-toolkit
cat ~/agent-board-toolkit/VERSION    # confirm you have it, e.g. -> 0.1.0
```

## 2. Put the tools on your PATH (agent host)

Symlink each tool into a directory already on your `PATH` (e.g. `~/.local/bin`). Symlinks (not copies) keep the host on the single source — upgrades are then just step §1's `git pull`.

> **This block is the ONE OWNER of the `PATH` symlink loop.** Every other place in this repository that tells you to run it — [`UPGRADE.md`](UPGRADE.md) §2 and §6, the *Worked example* at the end of this file, `agent-board-toolkit-runtime-check`'s remediation lines — points here instead of re-spelling it. The one deliberate exception is [`VERSIONING.md`](../VERSIONING.md) step 11, which links a **different** source checkout (a release-pinned one) and so cannot be a pointer; `tests/path-link-recipe-selftest.sh` executes both copies against a fixture and reds if a third appears, or if either stops refusing a non-regular-file entry.

```bash
mkdir -p ~/.local/bin
for t in ~/agent-board-toolkit/bin/*; do [ -f "$t" ] || { echo "skipped (not a regular file): $t" >&2; continue; }; ln -sfn "$t" ~/.local/bin/"$(basename "$t")"; done
hash -r
command -v kbcard    # -> /home/<you>/.local/bin/kbcard  (a symlink into ~/agent-board-toolkit/bin)
```

> **`[ -f "$t" ]` and `-n` are load-bearing — do not simplify them away.** `bin/` is globbed, so
> whatever is in it becomes a `PATH` entry, and `ln -sf` **dereferences a symlink-to-directory
> instead of replacing it**: it creates the new link *inside* the target and exits **0**. Both
> guards close one end of that:
> - **`[ -f "$t" ]` skips a source entry that is not a regular file.** Without it, a directory
>   in `bin/` (a `__pycache__/` left by a python helper is the one that has really happened —
>   and it is **gitignored**, so `git status` shows nothing) is linked onto `PATH` on the first
>   run, and on the **second** run the loop links that `PATH` entry back through itself and
>   plants `bin/__pycache__/__pycache__ -> bin/__pycache__` — a symlink cycle **inside your
>   toolkit checkout** — at rc 0, silently. Measured: run 1 rc 0, run 2 rc 0 with the cycle
>   present. The skip is announced on stderr rather than silent, so an entry that does not get
>   linked is named; a clean `bin/` prints nothing.
> - **`-n` on the `ln` closes the same shape at the *destination* end.** If `~/.local/bin/<tool>`
>   is itself a symlink to a directory, plain `ln -sf` puts the link inside that directory and
>   exits 0, so the tool never appears on `PATH` while the install reports success. `-n` replaces
>   the link instead. It is a no-op on every ordinary destination, so re-running stays idempotent.
>
> **One residual, stated rather than implied:** a destination that is a **real** directory (not a
> symlink to one) is still written into, by `ln -sfn` exactly as by `ln -sf` — `-n` is defined over
> symlinks, and measured on GNU coreutils 9.4 that case is rc 0 with the link created inside. It is
> left open deliberately: it needs a directory in your `PATH` dir named exactly after a toolkit
> tool, and unlike the case above it is **loud at first use** (the `PATH` entry is a directory, so
> the command does not run) rather than silent forever.
>
> **The framework's own install arm (`install-linked-bin.sh`) closes only the DESTINATION end — do
> not read this recipe as merely restating it.** Its destination guard refuses a `~/.local/bin/<tool>`
> that is a directory or a symlink-to-directory, and it links with `ln -sfn`; but its source glob is
> **unguarded** (`items=("$srcabs"/*)`, no `[ -f ]`), so a directory in `bin/` is **linked onto
> `PATH` on run 1 at rc 0** and then, on run 2, that same destination guard sees the symlink-to-
> directory it just created and **hard-fails the whole install** (`RESULT=NOT_INSTALLED …
> #install-arm-failed rc=1`). Measured on GNU coreutils 9.4 with a `__pycache__/` in the source
> `bin/`. This recipe therefore guards a shape the framework arm does not; the source-end gap is
> filed against the coord plugin (card#7234), not worked around here. **Anything in `bin/` that is
> not a regular file is not installed** — today that set is empty (every `bin/` entry is a regular
> file), so on a clean checkout this loop installs exactly the same tools the unguarded one did.

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

**Also export `KANBAN_EXPECTED_HOST`** here (the host part of `KBCARD_API`, e.g. `kanban.example.com`). There is **no baked default**, and it is now load-bearing for the whole toolkit rather than for the two token-sending guards alone:

- **Every tool preflights the api base it resolved.** Before a token file is even located, the host of the resolved `KBCARD_API` must equal `KANBAN_EXPECTED_HOST` or be a subdomain of it. Otherwise the run **refuses at setup**: `kbcard`, `dl-a0-backfill-triaged`, `dl-a1-register-field` and `adopt-to-dl` exit `2`; `next-dl` warns and skips the board check; `board-stats` exits `1`; `board-snapshot` prints a `SKIPPED` line and stays non-blocking. **An unset or empty `KANBAN_EXPECTED_HOST` refuses too** — with nothing declared, no host is recognised. The predicate is the **host alone**, so an `http://127.0.0.1:8000/api/v3` install passes this preflight as long as it declares `KANBAN_EXPECTED_HOST=127.0.0.1`.
  - **One tool is an exception, and it is the card-movement hook.** `board-card-start` guards the api base it is about to send the token to with the *second* guard below, which requires **`https://`** as well as the host — so on a plaintext `http://` board that hook **fail-softs and moves no card** (`api_base '…' failed the https-host trust guard`), while every other tool runs normally. A plaintext local board is therefore a supported install for reading and for `kbcard`, but card automation on checkout will not run on it. If you need the hook, terminate TLS in front of the board and point `KBCARD_API` at the `https://` URL.
- **It is also the anti-exfiltration guard's expected host** — the local `board-card-start` post-checkout hook (and any locally-run `promote-released-cards`) **refuses to send the writeback token** unless the api base it resolved is `https://` on this host. Without it, `board-card-start` fail-softs (no card move). Each of those two tools resolves that base from **outside** the repo when the committed `.release-pr.json` `api_base` is a scrubbed placeholder, which it normally is: the hook falls back to `KBCARD_API` from this file, and `promote-released-cards` reads `$KANBAN_API_BASE` (§4). Neither fallback skips the guard — a base from either source is validated identically.

This is the local counterpart to the CI-side `KANBAN_EXPECTED_HOST` in §4/§5; one setting here activates card automation for every repo on the host. (CI jobs set it in their own env, not from this file.)

> **If a tool suddenly refuses with `api base host '…' is not '…'`, read it as a question about `~/.kanban-host.env`, not about the tool.** Either the host you meant is not the one declared — fix whichever line is wrong — or something rewrote that file. The refusal names both ways out.

## 3b. Per-board config + token

Each board you manage needs one env file and one token file. The `--board <name>` flag selects `~/.kanban-<name>-board.env`.

```bash
# a) board IDs — copy the template and fill in YOUR board's numeric IDs:
cp ~/agent-board-toolkit/examples/kanban-board.env.example ~/.kanban-<name>-board.env
chmod 600 ~/.kanban-<name>-board.env
# how to find the IDs is documented inline in that file (workflows/card_types/custom_fields endpoints).
# ⛔ read the DECLARED TYPES box in that file before you fill in the KB_CF_* ids — the ids are
#    only half of what a board needs, and the other half is not in this file (see the box below).

# b) token — a file containing ONLY the bearer token (no quotes, no export):
printf '%s' '<YOUR_API_TOKEN>' > ~/.kanban-<name>-token
chmod 600 ~/.kanban-<name>-token

# c) point KBCARD_TOKEN_FILE at this board's token file:
echo 'export KBCARD_TOKEN_FILE="$HOME/.kanban-<name>-token"' >> ~/.kanban-<name>-board.env
```

> ⛔ **A custom field's DECLARED TYPE is a board-setup prerequisite, and getting it wrong breaks the board at first use — silently, until the first write.** kanban validates every payload value against its field's declared type, per board, so a contract-fixed key declared with a type that does not accept what these tools *write* rejects every write to it. The one that bites: **`dl_number` must be declared `string`.** Every writer of it — `kbcard --dl`, `next-dl`, `adopt-to-dl`, `dl-a1-register-field` — stamps the canonical `DL-NNNN` **string** through one renderer, so a **`number`**-typed `dl_number` answers every one of those writes `422 {"message":"Must be a number."}`. Its mirror image is just as real, and is why "declare everything string" is not a safe default: **`pr_number` / `issue_number` must be declared `number`**, because `kbcard` coerces a numeric value to a JSON number before the write and a `string`-typed field rejects that with `Must be a string.`
>
> ⚠ **The by-ref correlation index does not catch a wrong `dl_number` type** — it canonicalizes a ref by stripping non-digits, so it resolves from *either* type. A healthy-looking index is why the wrong declaration survives setup, not evidence that it is right.
>
> **Check what your board actually declares** — `kbcard --board <name> field list` prints each field's `key` **and `type`**. On a DL board, the `dl-a1-register-field` tool both declares `dl_number` correctly on a fresh board and **refuses** on a board that already declares it wrong, printing the remedy. **Fixing a wrong declaration does not cost a delete-and-recreate** — per `kbcard field retype`'s contract the server converts the definition and every stored value in one transaction, issuing no delete: `kbcard --board <name> field retype --field dl_number --to string --restamp-dl` (`--restamp-dl` rewrites the converted values to the canonical `DL-NNNN` form; without it a card holding `305` becomes the string `"305"`, which a custom-field DSL filter spelled `DL-0305` does not match).

> `KBCARD_API` is **board-independent** — set it **once** in `~/.kanban-host.env` (§3), not here. A board env that sets it is **refused** (as of v0.14.0) rather than silently honored, with a message naming the file. What "refused" means per tool: `kbcard`, `dl-a0-backfill-triaged`, `dl-a1-register-field`, and `adopt-to-dl` **exit 2 and do nothing**; `next-dl` **warns and skips the board check**, then still mints from its offline scan (fail-soft by design — but that scan is non-atomic, so fix the board env rather than rely on it; since card#7214 the degrade also prints the cause, and `next-dl --require-counter` refuses at **rc 4** instead of minting from it). `board-snapshot` and `board-card-start` never read a board env's `KBCARD_API` at all, so they ignore one.

> **Token-file precedence**, uniform across every tool: **this board env's `KBCARD_TOKEN_FILE` > `~/.kanban-host.env`'s > an ambient one > the coord credential store's `[kanban] api_token_file` pointer.** So a per-board token set here wins over a host-level default — that is the point of setting it here — and any of the three DECLARED tiers wins over the store, which is discovered rather than declared for this board. (One exception: `board-card-start` consults a board env's token only for a repo whose board id comes from a repo-local `git config kanban.board-id` — see [HOOKS.md](HOOKS.md).)
>
> ⛔ **There is no baked default. Step (c) above is REQUIRED unless the host env declares one, or the coord credential store points at one.** A board for which no tier names a token file is **refused**, with a message naming the board env and the exact line to add. `~/.kanban-dev-token` was a baked default until card#7245, and being one file for every board that had not set its own is what made a single overwrite of it take every board down at once.
>
> **The fourth tier is a POINTER SOMEBODY WROTE, not a default (card#7316).** If `${COORD_CREDENTIALS:-~/.config/coord/credentials.ini}` declares
>
> ```ini
> [kanban]
> api_token_file = ~/.kanban-dev-token
> ```
>
> then a board that declares nothing resolves through that pointer instead of being refused — so a host whose credential store already holds this secret does not have to keep a second copy of it for this toolkit to find. Three things to know before relying on it:
>
> - **It is POINTER-ONLY.** An *inline* `api_token =` value in that file is **refused**, with a message naming the pointer form, and its value is never read or echoed. That file is also the first thing anyone greps when auth breaks, so a value in it lands in transcripts; the toolkit will not become a second consumer of that form.
> - **It is board-independent.** The store holds one `[kanban] api_token_file`, so every board that declares nothing resolves the same file. A board that must not share it declares its own `KBCARD_TOKEN_FILE` — which wins, because the discovery is last.
> - **A host with no such store behaves exactly as before**: no message, no change, the same refusal. Point `COORD_CREDENTIALS` at a non-existent path to turn the tier off deliberately.

> ⛔ **MIGRATING ONTO THE POINTER MEANS DELETING THE COPY, and that step is the one an install forgets.** Dropping step (c)'s `KBCARD_TOKEN_FILE` line so the store's pointer resolves does **not** remove `~/.kanban-<name>-token`: the file stays on the box holding a live token, out of whatever rotates the store's, and nothing about the running install looks any different. Delete it in the same sitting — `rm ~/.kanban-<name>-token` — or, if you are keeping the per-board token, leave step (c) in place and let the pointer stay shadowed.
>
> **`agent-board-toolkit-runtime-check` reports a seat that is carrying more than one (card#8376),** so this is a state you find out about rather than one you have to remember. It resolves every source — this process's `KBCARD_TOKEN_FILE`, `~/.kanban-host.env`, every `~/.kanban-*-board.env`, the store's pointer — and compares what they hold **by digest, internally**:
>
> - **the same token in two files ⇒ ✗ and rc 1**, naming the file to delete and the one to keep (the store's pointer wins that choice, since the store already manages it);
> - **a readable token file no board resolves, holding a different token ⇒ ⚠ and rc 0** — a second live credential, reported and not gated, because a store whose kanban token belongs to the framework's own tooling while every board here declares its own is a supported install;
> - **several boards each with their own token, all in use ⇒ silent.** Per-board isolation is the topology this section recommends, and the check does not report it as duplication.
>
> It names **sources and paths only** — never a token value, and never a digest. `board-snapshot` runs it at SessionStart, so a duplicate surfaces there.

> **The default board (no `--board` flag)** reads `~/.kanban-dev-board.env`, and takes its token from whatever that file (or the host env) declares. On a box whose primary board is **not** named `dev`, you have three ways to work flag-free — pick one:
> - name that board `dev` (env at `~/.kanban-dev-board.env`), **or**
> - **set `KBCARD_BOARD_ENV`** to your primary board's env file — e.g. `echo 'export KBCARD_BOARD_ENV="$HOME/.kanban-<name>-board.env"' >> ~/.profile` (recommended on a single-board box), **or**
> - always pass `--board <name>`.
>
> Without one of these, a bare `kbcard` on a non-`dev` box exits `2` with `board env file not readable: …/.kanban-dev-board.env` — the error names these fixes and lists the `~/.kanban-*-board.env` files it did find, so a fresh box on a non-`dev` board isn't left reverse-engineering the default.

## 4. Per-repo release config (only for repos that cut releases)

`promote-released-cards`, `release-pr-body` and `release-artifacts-check` read `<repo>/.release-pr.json`:

```bash
cp ~/agent-board-toolkit/examples/release-pr.json.example <your-repo>/.release-pr.json
# edit: set promote.{board_id, released_stage_id}, ref_token_regex (e.g. "DL-[0-9]+"),
# card_token_regex (e.g. "card#[0-9]+"), version_file/version_regex, dev/main branch names,
# and the artifacts set.
# promote.api_base: LEAVE IT A PLACEHOLDER and name the real host in $KANBAN_API_BASE
# instead — the box below says why, and what happens if you commit a real one.
# main_branch/dev_branch (optional, defaults "main"/"dev"): the branch the release
# baseline tag is resolved from, and the branch whose commits are bundled — omit both
# if your repo already uses those names.
# tag_format (optional, default "v{{version}}"): how a version maps to its git tag —
# set "{{version}}" for unprefixed tags, or e.g. "release-{{version}}". It names the tag in
# BOTH tools that act on one: release-pr-body's baseline exclude and body header, and the tag
# release-tag-check (§6d) waits for — `release-pr-body --tag` is the single reader, so the two
# cannot disagree.
# ⚠ SET IT TOGETHER WITH YOUR TAGGING WORKFLOW. The key tells these tools what to EXPECT; it
# does not change what your tagging workflow CREATES, and nothing in the toolkit constrains
# that workflow. If the two disagree, §6d's gate waits for a tag nobody creates and refuses
# every release (it names the mismatch as a candidate cause, but it cannot fix it).
# Version extraction
# keeps exactly what YOUR version_regex matches, so a .NET Major.Minor.Build.Revision
# version needs a 4-segment version_regex: measured, a 3-segment one reads 1.22.1.0 as
# 1.22.1 and the release then tags and reports the truncated version, silently.
# version_extract_cmd (optional): a repo-relative path to an executable whose STDOUT is the
# version. Set it when your version lives INSIDE a code file — see the box below.
jq . <your-repo>/.release-pr.json   # must parse (no trailing commas); remove the "_comment" line if you like
```

> **`version_extract_cmd` — set it when `version_regex` has to match CONTEXT to find your version.** `release-pr-body` resolves the version as the **whole first `version_regex` match**, which is right for a bare `VERSION` file (the match *is* the version) and wrong for a version declared inside a code file, where the regex must carry surrounding text to be unambiguous. With `"version_file": "config/app.php"` and `"version_regex": "'version' => '[0-9.]+'"`, the version became the string `'version' => '0.43.0'` and the release PR's scope line rendered `release PR — v'version' => '0.43.0'.` — measured on a real release.
>
> Point the key at the extractor **your repo already has**, rather than adding a capture group: a repo whose version needs context almost always owns a script for it already, because its tagging workflow needed one first — and then "what version is this repo at" has **two implementations**, which is the actual defect. `"version_extract_cmd": "bin/extract-version.sh"` makes the release body and the tag agree **by construction**. Its stdout **is** the version, taken verbatim; empty output, more than one line, or a non-zero exit is a refusal (rc 2) — never a silent fall-back to `version_regex`, which is the answer this key exists to override. `--version X.Y.Z` still beats it and runs nothing.
>
> ⛔ **It runs a command named by a config file — know the boundary.** The value is an **argv[0], not a command line**: it is exec'd **with no shell**, so arguments, `>`, `|`, `;` and `$(…)` are not interpreted (a value carrying them names no file and is refused); it must be **inside the repo** (an absolute path or a `..` component is refused); a value with no `/` is run as `./<value>`, never resolved through `$PATH`; and it must exist and be executable. What is trusted is the repo: the config and the script are both committed, and this tool is run by a releaser in a checkout of the code they are about to ship, where anyone who can edit either can already edit `bin/`. **That argument does not extend to CI over an untrusted head, so the key stops here:** `release-artifacts-check` (§6c) does **not** read it and must not — its classification compares the version at **two refs** (`git show <ref>:<file>`), which a command running in one checkout cannot answer, and executing a script the PR under review names would hand that PR code execution inside the job judging it. **Keep `version_file`/`version_regex` set** even when you set this key: they are what the §6c gate classifies by, and a regex that matches its context classifies perfectly well — it is only as a *displayed value* that the match is unusable.

> **`ref_token_regex` and `card_token_regex` are TWO ID SPACES, not two spellings of one.** Both are optional and independent; set whichever your commit subjects actually use (set both if they use both).
> - **`ref_token_regex`** (e.g. `"DL-[0-9]+"`) — the token's numeric part is a **decision-log number**, correlated against a card's `payload.dl_number`.
> - **`card_token_regex`** (e.g. `"card#[0-9]+"`) — the token's numeric part is a **card id**, correlated against the card's own `id`.
>
> **Do not migrate by re-spelling `ref_token_regex`.** If your subjects moved from `DL-NNN` to `card#NNNN`, add the second key — do not change the first. `promote-released-cards` reads `ref_token_regex` too and matches on `dl_number`, so a `card#` spelling there makes a range naming `card#42` correlate with whichever card carries `DL-42`: it **moves that card and reports `0 no-card`**. Leaving `ref_token_regex` unset (or on its old spelling) with no matching tokens in range is harmless — the manifest footer is simply omitted.
>
> **What each key buys.** `release-pr-body` renders a `## Card coverage` section that dry-runs `promote-released-cards` over the range's refs and names any that have **no tracking card** — so a typo'd id, or a card belonging to a different board, is caught at release-prep rather than by a red post-merge promote run. It needs `.promote.board_id` + `$KANBAN_WRITEBACK_TOKEN` + the promote tool on `PATH`; **without any one of them the body carries no coverage section at all.** The section's presence IS the claim that coverage was measured — it never renders a placeholder saying it was not, because a heading whose only content is "not checked here" tells the merger nothing about the merge — one was struck by hand from a release PR body, and a hand-removal does not hold, since the next release re-emits it. ⚠ **The obligation therefore belongs in YOUR release doc:** state in your `VERSIONING.md` (or equivalent release flow) that `promote-released-cards --dry-run` is run over the release range **before merging**. A body with no coverage section means the check did not run — not that it passed. Each key also adds a machine-readable footer: `<!-- release-manifest:shipped-refs=DL-1,DL-2 -->` and `<!-- release-manifest:shipped-cards=5877,5874 -->` (bare ids — there is no token spelling for a consumer to parse).
>
> **Card ids are never derived from commit subjects by the mover.** `promote-released-cards` accepts them only via the explicit `--cards "5877,5874"` flag, because a descriptive `card#NNNN` mention in a subject ("supersedes card#1234") would otherwise relocate an unrelated card — with a DL token that misfire needs a matching `dl_number` stamp as well, but an id *is* the match. `release-pr-body` does derive them from subjects, and passes them with `--dry-run`.

> **`artifacts` is a must-move-together SET, not a memo.** Each entry is `<path> <prose>` — the path is the **leading whitespace-delimited token**, so **a member path may not contain whitespace**; everything after the first space is prose. `{{version}}` is expanded, and a single-level `{a,b}` brace set is allowed in the path (`sboms/v{{version}}.{spdx,cdx}.json` ⇒ two members). `release-pr-body` renders the set as the release PR's `- [ ]` checklist; `release-artifacts-check` (§6c) **asserts** it. Three member shapes, distinguished by the prose you write — and the shape a member was judged by is **printed on its OK line**, so check it says what you intended:
> - `docs/CHANGELOG.md → [{{version}}] section` — the literal text `[{{version}}] section` (matched case-insensitively) requires a **line beginning `## [<version>]`** in the file at head. This is the only **strong** shape. The trigger is that exact wording: `[{{version}}] entry` or `… heading` is **not** recognized and silently falls through to the weak shape below — which is why the OK line names the shape it used (`via '## [X.Y.Z]' heading line` vs `via content mention`).
> - a path whose **filename carries the version** (`sboms/v{{version}}.json`) — existence at head is the whole assertion.
> - anything else (`CLAUDE.md § Recent releases row`) — the file's content at head must **contain the version string. This test is UNANCHORED**: with version `0.25.0`, a file containing only `10.25.0` (or `0.25.01`) satisfies it. It is the catch-all for members whose agreement has no structure to key on, so it is deliberately weak — a member that needs a real assertion should use the `[{{version}}] section` shape.
>
> Every member must additionally appear in the PR's own changes and still exist at head **as a regular file** — a deletion appears in a diff, so the existence leg is what catches it, and a member that is a symlink, a directory or a submodule entry at head is refused by name rather than read (each of those answers a content read with something — a target path, a tree listing, a commit log — that can carry the version while asserting nothing about a release artifact). Declare only what a release genuinely must move: an over-declared entry fails every release PR, and an under-declared one is invisible — no tool can assert a member you never named.

> **The declared set is read from the FORK POINT as well as head, and head may only WIDEN it.** `.release-pr.json` is editable by the very PR the gate is judging, so a head-only read let a PR narrow the verdict it was judged by: delete an entry while still updating the file it named and every leg passed, rc 0, with no trace anywhere — and from the next release the fork point no longer carried the entry either. `release-artifacts-check` therefore compares the set declared at `merge-base(base, head)` against head's:
> - **added entries, and added brace alternatives, are free** — a widening is the normal case and changes nothing (the comparison is on *expanded members* with `{{version}}` held as a placeholder, so reordering a brace set is a no-op and adding an alternative is not a removal).
> - **`version_file` / `version_regex` are read from the fork point only.** A head edit to either is *ignored*, not refused — so retargeting them can no longer make a real release PR classify as "version unchanged", and a legitimate change to them still costs nothing.
> - **a member declared at the fork point and absent from head fails in its own right** (rc 1), whether or not that member's own checks would have passed, and **on every PR class** — a release PR *and* an ordinary one. The removal and its acknowledgement are wanted in the same PR.
>
> **`retired_artifacts` is how a legitimate retirement gets through** — an optional array beside `artifacts`, in the same entry format, read at **head** (it is the PR's own declaration; a fork-point read would make retirement impossible). Move the entry across and the run prints a `RETIRED: <entry>` line and exits 0 instead of refusing. The failure message prints the exact line to paste. Two rules: a member listed in **both** arrays is a config error (rc 2), so a tombstone cannot be planted against a member that is still declared; and once the retirement has passed through one release the entry is inert — the fork point no longer carries the member, so nothing consults it. Retiring is deliberately a *declaration*, not a silence: the diff shows a key named `retired_artifacts` changing, and the CI log names what stopped being asserted.
>
> **A repo whose fork point has no usable config is warned, never refused.** Config absent (the adoption PR that creates it — all three real adoptions created it *inside* a release PR), unparseable, or missing the classification keys: the run prints a `::warning::` naming the fallback, classifies with head's keys, and compares against an empty baseline — i.e. exactly the pre-fork-point behaviour. Refusing would be an rc no PR could fix, since those keys can only reach the fork point through a merged release. **The same rule holds per ENTRY.** A malformed entry (no leading path token — an empty string included — an empty brace set, or the reserved comparison token written literally) is `rc 2` when head declares it, because the PR that wrote it can fix it; read from the **fork point** it gets a `::warning::` naming the entry and is dropped from the baseline, its siblings still compared. Refusing there would be unfixable in the same way: the only repair for a malformed entry is to delete it, and the PR carrying that deletion would be redded by the entry it is deleting.

> **`.release-pr.json` is security-sensitive.** `.promote.api_base` is the host the release-CI writeback token (`KANBAN_WRITEBACK_TOKEN`) is sent to. A PR that edits `api_base` to an attacker host would exfiltrate the token on the next promote run. `promote-released-cards` (and `board-card-start`) reject any `api_base` that is not `https://` on the **expected host** before sending the token. **`KANBAN_EXPECTED_HOST` is REQUIRED — there is no baked default** (the toolkit ships onto your own kanban host, so it assumes none). Set **`KANBAN_EXPECTED_HOST`** in the promote-CI env (a repo/org variable — out-of-band from this PR-editable file) to your kanban host; the guard accepts that host or a subdomain of it. Leaving it unset makes the guard **fail closed** — the token is never sent. Review any `api_base` change as a credential-scope change.

> **You are meant to leave `api_base` as a placeholder, and name the real host in `$KANBAN_API_BASE` instead.** The real kanban host does not belong in a repo — least of all one that is vendored — so committing it is the thing to avoid, not the thing to do. `promote-released-cards` reads **`$KANBAN_API_BASE`** in preference to `.promote.api_base`; unset or empty means "use the committed value". **Both sources meet the same host guard**, so an env-supplied base that is not `https://` on `$KANBAN_EXPECTED_HOST` refuses exactly as a committed one does — the override moves the *target* out of the repo, it does not exempt it from the *constraint*. With the target and the constraint both supplied out-of-band, a PR editing `.release-pr.json` can move **neither**. Every run states, on stderr, **which of the two channels** the base it is about to use came from — the one thing a two-source resolution can get wrong that nothing else in the output reveals. It deliberately does not echo the base itself, since a legitimate api_base may carry userinfo; a **refusal** does echo it, because you cannot fix a value you cannot see — with any **userinfo masked to `***`**, so the host you need is on the line and the credential is not (a base with no userinfo is printed verbatim, exactly as before).
>
> **Running it by hand** (the release-prep dry run `release-pr-body`'s `## Card coverage` section also performs — and which needs all three variables, since a config carrying only the placeholder refuses before the first request):
>
> ```bash
> export KANBAN_API_BASE="https://kanban.example.com/api/v3"   # your host — NOT committed anywhere
> export KANBAN_EXPECTED_HOST="kanban.example.com"             # or from ~/.kanban-host.env (§3)
> export KANBAN_WRITEBACK_TOKEN="$(cat ~/.kanban-<board>-token)"
> promote-released-cards --dry-run            # -> `api_base resolved from $KANBAN_API_BASE, host-guarded against '…'` then the summary
> ```
>
> `--dry-run` moves nothing; drop it only when you mean to promote. A run that refuses with `api_base '…' is not https:// on '…'` names, in the same line, which channel the offending value came from — fix that one.

## 5. Verify (expected output shown)

```bash
kbcard list --column backlog            # -> JSON array of cards (or [] if empty) on STDOUT, plus ONE line on
                                        #    stderr: `kbcard: list --column backlog: <M> of <N> board cards
                                        #    matched`. That line is the filter's denominator, not an error —
                                        #    every filtered read prints it; an unfiltered one prints none. A
                                        #    non-empty, well-formed result proves token + board IDs + API base
                                        #    are all correct.
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
    api-base: ${{ vars.KANBAN_API_BASE }}   # the real api base, passed to the script as $KANBAN_API_BASE; use it when the committed value is a placeholder (it normally is). Still host-validated against expected-host
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

> **Vendoring a *lib-sourcing* bin (not `promote-released-cards`)?** The interactive/hook bins `source` `bin/_kb-board-lib.sh` as a sibling, so you must copy **the lib too** into the same `bin/` (`cp ~/agent-board-toolkit/bin/_kb-board-lib.sh <repo>/bin/`). **Which bins those are is derived, not listed** — `grep -lE '^[[:space:]]*source "\$KB_LIB"' ~/agent-board-toolkit/bin/*` answers it for the version you are vendoring, which a list written here cannot (the list this replaced was already wrong for the newest bin in the tree). Without the lib the tool refuses at startup — since v0.11.2 that is a self-naming message pointing back at this section, **not** the bare `source: …/_kb-board-lib.sh: No such file` it used to be — and it refuses on **every** invocation, `--help` included, because the lib is loaded before any argument is read. `board-card-start` is the one deliberate variant: it runs from a git hook that must never block a checkout, so it reports that board automation was skipped and still exits 0. `agent-board-toolkit-drift-check` also flags a lib-sourcing bin vendored without the co-located lib. The release bins need no lib — but two of them need each OTHER, which is the same failure one directory over: `release-tag-check` resolves its release classification and its tag name by exec'ing siblings in the `bin/` it was copied into, and refuses by name (rc 2) when one is not there. **Which siblings a bin needs is derived, not listed** — and the derivation is on the PROPERTY (*this file resolves its own directory, and then names something else in it*), never on the variable a given bin happens to spell that directory into. Run this against the version you are vendoring:
>
> ```bash
> cd ~/agent-board-toolkit/bin
> for f in *; do
>   [ -f "$f" ] || continue                       # a stray bin/__pycache__/ is a directory, not a bin
>   grep -qE 'dirname.*(\$0|BASH_SOURCE|__file__)' "$f" || continue
>   sibs="$(grep -v '^[[:space:]]*#' "$f" | grep -oE '[A-Za-z0-9_][A-Za-z0-9._-]+' | sort -u \
>           | grep -Fxf <(ls) | grep -Fxv "$f" | tr '\n' ' ')"
>   printf '%s needs: %s\n' "$f" "${sibs:-(nothing)}"
> done
> ```
>
> The first `grep` is the property; the second half intersects the file's own non-comment text with the **actual contents of `bin/`**, so what comes back is always a set of files you can copy. An earlier recipe here matched two variable NAMES (`$SELF_DIR`, `$d`) instead, and a name-matching pattern answers about the NAME, not the property: re-run against this tree it returned exactly the two bins that use those two spellings, a documentation filename as a spurious third, and a `grep: bin/__pycache__: Is a directory` — while `adopt-to-dl` (`next-dl`, `kbcard`), `dependabot-deploy-reconcile` (`_dependabot-reconcile.py`) and `board-session-close` (`install-board-hooks`, its advisory-leg helpers) resolve their own directory under other spellings and appeared nowhere. **Weakest properties, so this is not over-cited** — the first is the only SILENT one, and the rest all err toward over-collection: **a file whose text does not match the property `grep` produces no line at all**, so a bin that resolves its own directory some other way is absent from the output rather than reported as unexamined, and you cannot tell that from a clean run. Invert the first `grep` to list what it skipped, and read those — on this tree none of them resolves its own directory another way, but that is a fact about today's `bin/`, not about the recipe. Then: it over-collects a sibling merely *named* in a message or help string (err toward one file too many — copying a bin you did not need costs nothing); it cannot see a sibling whose filename is assembled at run time from pieces; and it answers only about files in `bin/`, so a bin needing a sibling **directory** — `install-board-hooks` needs `hooks/` — comes back as `(nothing)` and is not this recipe's question. Vendor them together, and re-vendor them together: a new bin beside an old sibling gets the old sibling's answer. §6a/§6c/§6d consumers have nothing to do here — an action carries the whole `bin/`.

> **Vendoring `board-session-close`, or any of the `bin/_kbc-*.py` helpers?** There is a SECOND sibling lib on the same terms, in Python: `bin/_kbc-archive-lib.py`, which the helpers path-load beside themselves. **Which helpers those are is derived, not listed** — `grep -l '_kbc-archive-lib.py' ~/agent-board-toolkit/bin/*.py` answers it for the version you are vendoring. **Re-vendor `bin/_kbc-archive-lib.py` TOGETHER with any helper you copied**, exactly as the bash lib above: shared code moves INTO that lib over time (`stage_field_maps` and `live_cards` did), so a new helper beside an old lib fails at runtime with `AttributeError: module '…' has no attribute 'stage_field_maps'` — and it fails at the call site, mid-report, not at startup. `board-session-close` resolves its advisory legs as siblings of itself with no env override, so a copy vendored **without** them still runs and says which leg did not run (advisory — a missing leg never blocks a close), but it cannot report what that leg reports.

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
          fetch-depth: 0     # REQUIRED — see "What the check reads" in agent-board-toolkit docs/INSTALL.md §6c
      - uses: <owner>/agent-board-toolkit/release-artifacts@<full-40-char-SHA>  # vX.Y.Z
        with:
          base-sha: ${{ github.event.pull_request.base.sha }}
          head-sha: ${{ github.event.pull_request.head.sha }}
          # config: .release-pr.json   # optional; the default
```

**Why `edited` is in `types:`, and where else you owe it.** The default `pull_request` event set (`opened`, `synchronize`, `reopened`) does not fire when a PR *field* is edited after opening, so a gate whose verdict is a function of such a field keeps answering about the pre-edit value — here the **base**, which a retarget changes. The obligation generalises to any workflow of yours that reads `github.event.pull_request.*` (a title-reading gate has it for the title) — including one on `pull_request_target`, which fires on the same activity types and populates the same object. The toolkit holds that rule over **its own** `.github/workflows/` in CI; a recipe pasted into your repository is outside that reach and is yours to keep.

**What the check reads.** It resolves the merge base of `base-sha` and `head-sha`, reads **the config itself at both ends** of that range (the fork point's copy is the declared set and the classification keys the PR is judged by — see §4), reads the version file at **both** ends, and reads each declared member's type and contents at **head** — all of it `git show`/`git ls-tree`/`git cat-file` against the local clone, none of which a shallow one can serve. That is what `fetch-depth: 0` is for. **This section owns that inventory**: the toolkit's own [`release-artifacts-gate.yml`](../.github/workflows/release-artifacts-gate.yml) points here rather than restating it.

**The config is read from COMMITS, never from the working tree.** On a `pull_request` event the checkout is the *merge* ref, so a tree read answers about a merge nobody wrote. Two consequences worth knowing before you adopt: a config that exists only in the checkout and is **not committed at head** is refused (rc 2) rather than used, and a config **committed at head but absent from the checkout** is fine. `--config` may name a path in a subdirectory; it is normalized to repository-root-relative once, and a `--config` whose directory is not inside **this** repository's checkout is refused by name — including one that resolves inside a *different* repository, where the normalized path would otherwise be re-rooted here and the run would answer about this repository's own config instead of the one named.

> **Lockstep — one sanctioned copy.** [`release-artifacts/action.yml`](../release-artifacts/action.yml)'s `description:` restates the read inventory above *and* the fail-closed rule below, because a SHA-pinned consumer reads the action itself and cannot follow a pointer into these docs. **Correcting either one here means correcting `release-artifacts/action.yml` in the same change.**

**The asserted range is `merge-base(base-sha, head-sha)..head-sha` — the PR's own changes — never base's tip.** That is a correctness requirement, not a refinement, because base-branch drift after the fork point corrupts both halves of the check:

- **the MOVED leg:** a hotfix landing on the base branch after the fork makes that file differ between base's tip and head, so it appears in a base-tip diff and *spuriously satisfies* "this artifact moved" for a member the PR never touched. Measured on a fixture: base-tip exits **0** with `all 5 declared artifact member(s) moved and agree`, merge-base exits **1** naming the member.
- **the CLASSIFICATION:** a version bump arriving on the base branch makes base's tip read the *same* version as head, so a real release PR is classified "version unchanged" and the entire gate silently does not run. Base-tip exits **0** with `not a release PR; nothing to assert` on a PR that is genuinely missing a member.

You still pass `base-sha` — it is what the fork point is resolved *from*.

**No `paths:` filter, deliberately.** The gate must observe every PR in order to *classify* it: a PR whose version **value** is unchanged between the fork point and head is not a release PR and asserts no member. That is not the same as costing nothing — the config is read at **both** ends and the fork-point comparison (§4) runs *before* the classification and independently of it, so an ordinary PR that drops a declared entry without acknowledging it is refused exactly as a release PR would be. Classifying by value rather than by "the version file appears in the diff" is what makes this correct for a repo whose `version_file` is a whole config file (kanban's is `config/app.php`), where the file-moved test would misfire on any unrelated edit.

**An equal value at both ends is not on its own a non-release, because the value is the FIRST `version_regex` match over content head owns.** Any line matching the regex above the version line — a `# was 0.1.0` comment, an older version string in a config array, a deliberately prepended line — makes both ends extract the same value, and a real release PR would read as "version unchanged" with every member leg silently not running, for the price of one line and no config edit. So on an equal classifying value the check compares the two ends' **sets** of matched values, which head cannot make equal while shipping a version the fork point does not carry:

- **exactly one value present at head and absent from the fork point** *names the version being shipped* — the PR is classified as a release of that version, behind a `::warning::` saying so, and every declared member is asserted against it;
- **more than one** is `rc 2`: which version is being shipped is genuinely unknown, and reading that as "not a release PR" would be a silent non-run;
- **none** is the ordinary unchanged verdict. A value the fork point carries and head *drops* is a deletion, not a release, and does not enter the test.

> **Cost, stated so you can price it before adopting.** A `version_regex` that matches more than the version declaration puts an ordinary PR in reach of the first rule: add a version-shaped string to the version file on a non-release PR and it is classified as a release of that value, so the declared members are asserted and the check reds. The remedy is the regex — tighten it to the declaration (kanban's `'version' => '[0-9.]+'` shape, not a bare `[0-9.]+`) — and it must land in **its own PR**, because `version_regex` is read from the fork point and takes effect only once merged.

**It fails closed** (rc 2) on an unresolvable merge base, an unreadable version file, a config not committed at head, a member declared in both `artifacts` and `retired_artifacts`, or a version file that carries several values head introduced while its classifying match is unchanged — naming which end of the range it is and the path, rather than reading any of them as "not a release PR", which would be a silent non-run of the entire gate. A shallow checkout is the usual cause of the first two, hence `fetch-depth: 0`.

**What it deliberately does not close.** Stated so an adopter knows the shape of the guarantee rather than inferring a stronger one:

1. **A prose edit that downgrades a member's assertion strength** (`[{{version}}] section` → `… entry`) still passes, at the weaker arm. The closing mechanism exists — prefer the fork point's prose — and is declined because attacker-weakening and a legitimate change of changelog format are the *same observable*, and since the fork point is the previous release the corrected prose could never land. The OK line **names the arm**, so a downgrade is legible in the CI log.
2. **Renaming the config *and* retargeting the workflow's `config:` input in one PR** takes the no-usable-fork-point-config path, behind a single `::warning::` — or any PR whose merge base predates the config, which takes the same path. Bounded by the workflow file being head-editable, which no config-level design can close.
3. **A rename with no workflow edit** is rc 2 — only the paired change goes green.
4. **`retired_artifacts` is a head-editable narrowing surface by construction.** It is declared, logged and one line; it is not impossible.
5. **A version file whose *whole matched value set* head can make equal to the fork point's.** The set comparison above closes the prepended-line shape, and the remaining reach is narrow: head must ship a version the fork point already carries somewhere in that file. What is *not* closed is the regex itself — a `version_regex` matching more than the version declaration is a config the repo owns, and this check can only report on the values that regex selects.
6. **An under-declared `artifacts` array is invisible.** No tool can assert a member you never named.

### 6d. GitHub Actions consumer — the untagged-release gate

Consume `release-tag-check` via the [`release-tag-check/`](../release-tag-check/action.yml) composite action, SHA-pinned on the same terms as §6a. It goes in the workflow that **reports a release as shipped** — the promote job, a deploy, a notification — and refuses to let that report happen while the release's tag does not exist:

```yaml
name: Promote released cards on merge to main
on:
  push:
    branches: [main]
permissions:
  contents: read          # sufficient — the gate polls refs with `git ls-remote` and writes nothing
jobs:
  promote:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<full-40-char-SHA>  # vX.Y.Z
        with:
          fetch-depth: 0     # REQUIRED — the release classification reads both ends of the range
          fetch-tags: true   # for the §6a promote step below — NOT for this gate, which polls
                             # the REMOTE (the tag is created after this checkout is taken, so
                             # no local ref set can carry it)

      - name: Refuse to promote an untagged release
        if: github.event_name == 'push'   # a workflow_dispatch run has no github.event.before
        timeout-minutes: 10               # a BACKSTOP, sized above the tool's own bound — see below
        uses: <owner>/agent-board-toolkit/release-tag-check@<full-40-char-SHA>  # vX.Y.Z
        with:
          before-sha: ${{ github.event.before }}
          after-sha: ${{ github.sha }}
          # config: .release-pr.json   # optional; the default
          # remote / timeout / interval / read-timeout — optional; blank = the tool's own
          # defaults, which are where those numbers are argued. Leave them blank unless you
          # have a reason, and state the reason where you set them.

      - uses: <owner>/agent-board-toolkit/promote@<full-40-char-SHA>  # vX.Y.Z
        with: { ... }        # §6a
```

**Order is the whole point.** The gate must run **before** the step that reports the release. A gate placed after it refuses a release that has already been reported — the board is already wrong, and the red run is now about a state you have to repair by hand.

**Why this exists at all, in one line:** a tagging workflow and a promoting workflow that share the `push: <main>` trigger with no `needs:` between them are **two independent runs**, so the promoting one wins the race on *every* release and reports "shipped" before the tag exists — and on the release where the tag never arrives at all, that report is simply false and stays false. (This repo's own v0.28.0: the tag push took a 403, promote reported success three seconds later, and the board asserted a shipped release for 17m27s until a human re-ran the job.) The tool therefore **waits** rather than refusing on sight; an immediate hard-refuse would red every release. `release-tag-check --help` owns the bound, why it is what it is, and what happens when it is reached — it is not restated here.

**Your `tag_format` is what names the tag it waits for** (§4). A repo on a non-`v` scheme (`{{version}}`, `release-{{version}}`, a date string) is asserted against the tag that scheme names — the same key `release-pr-body` resolves the tag from. A repo that leaves the key unset gets `v<version>`, unchanged. ⚠ **The key and your tagging workflow must be set together:** `tag_format` tells this gate what to expect and does **not** change what your tagging workflow creates — the toolkit constrains that workflow in no way at all. A repo that sets the key without moving its tagger has a gate waiting for a tag nobody creates, which refuses **every** release at the bound; the refusal takes a second look and names the tag that IS at the commit as a candidate cause, but that is a diagnosis, not a repair.

**Size the `timeout-minutes` backstop above the tool's own worst-case runtime** — stated in [`bin/release-tag-check`](../bin/release-tag-check)'s header, and deliberately not restated here: it moved once when a second bounded read was added, and the copies of it did not. That ordering is the difference between a job that reports `failure` — a refused release — and one that reports `cancelled`, which is not a verdict about the tag at all. The tool bounds each individual poll so its own wait is what ends first; on a host with no coreutils `timeout` on `PATH` it says so on a `::warning::` and the polls are unbounded (GitHub-hosted runners ship coreutils).

**What a refusal is, and is not.** A red gate means *check whether the tag exists* — not *the board write failed*. Three refusals with three different messages: the tag is absent past the bound, the tag exists at a **different** commit (two merges claimed one version, or the release PR forgot to bump the version file — refused immediately, since waiting cannot change it), or the remote could not be **read** on the final poll, in which case the tag is **UNMEASURED, not absent** and the message asserts nothing about it. All three exit 1: a release that cannot be confirmed must not be reported as shipped.

The first of those takes a **second look before it names a cause**, without the tag-name filter, and says which of three worlds it measured: no tag of any name is at the commit (the release merged untagged — check your tagging workflow's run), *some other* tag is (the release IS tagged and this gate waited for a name your tagger does not create — check `tag_format` against that workflow, above), or that second look could not read the remote either, in which case the refusal says the **cause** is unmeasured rather than picking one. A refusal names its own cause or claims nothing; sending an operator to a workflow run that succeeded is the failure mode this replaces.

> ⚠ **The refusal is loud in Actions and silent on your board.** When the gate refuses, the cards simply stay where they were — there is no "release refused" signal on the board itself. Watch the workflow run, not the column.

> **Lockstep — one sanctioned copy.** [`release-tag-check/action.yml`](../release-tag-check/action.yml)'s `description:` restates the preconditions above (checkout depth, the `push`-only guard, the caller-owned backstop), because a SHA-pinned consumer reads the action itself and cannot follow a pointer into these docs. **Correcting either one here means correcting `release-tag-check/action.yml` in the same change.**

## Worked example (host install, primary board named `dev`)

```bash
git clone <agent-board-toolkit-remote-url> ~/agent-board-toolkit
# ...then run §2's PATH symlink loop against that clone. It is not repeated here: §2 is its one
# owner, and the two guards in it are the difference between installing your tools and planting a
# symlink cycle inside the clone above. Then:
hash -r
# §3 host config — BOTH lines, not just the api base: KANBAN_EXPECTED_HOST is what makes the
# resolved KBCARD_API a host this box recognises, and with it unset every host is unrecognised.
cp ~/agent-board-toolkit/examples/kanban-host.env.example ~/.kanban-host.env && chmod 600 ~/.kanban-host.env
# ...edit KBCARD_API and KANBAN_EXPECTED_HOST in ~/.kanban-host.env...
cp ~/agent-board-toolkit/examples/kanban-board.env.example ~/.kanban-dev-board.env && chmod 600 ~/.kanban-dev-board.env
# ...fill in IDs in ~/.kanban-dev-board.env...
printf '%s' 'TOKEN_HERE' > ~/.kanban-dev-token && chmod 600 ~/.kanban-dev-token
# ...and DECLARE it: there is no default token path, so this line is not optional.
echo 'export KBCARD_TOKEN_FILE="$HOME/.kanban-dev-token"' >> ~/.kanban-dev-board.env
kbcard list --column backlog        # -> [ {...}, ... ] on stdout, `… <M> of <N> board cards matched`
                                    #    on stderr (the filter's denominator)   ✓ install verified
```
