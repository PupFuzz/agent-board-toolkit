# Recovering a stranded DL allocation counter

When [`bin/next-dl`](../bin/next-dl) suddenly mints numbers in the wrong (far-too-high)
range — e.g. the next DL comes back as `100002` on a board whose real sequence is in the
low hundreds — the board's **DL allocation counter is stranded**. This runbook is the
end-to-end recovery, driven entirely over the board's kanbantool-v3 API, so an agent with
only an API token (no server shell) can fix it.

> **Scope.** Board-agnostic: it targets the kanbantool-v3 **DL-sequence** endpoint shapes
> (`boards/{board}/dl-sequence*.json`) that `next-dl` already consumes. A board's kanban must
> expose the inspect + reset endpoints (kanban DL-201 or later). On an older kanban that only
> ships the `claim` endpoint, the counter can only be reset from a **server shell** with the
> `kanban:dl-reset-sequence` artisan command — see that kanban's own deployment runbook.

## Why it strands (the mechanism)

The counter (`board_dl_sequences.last_value`) behind `next-dl`'s atomic claim is a
**monotonic high-water mark**: a claim returns `GREATEST(last_value, liveMax) + 1` and only
ever advances `last_value`. `liveMax` is the highest DL number still **indexed** on the
board — and a DL ref is **retained** for archived AND soft-deleted (trashed) cards, by design
(so a real, later-deleted DL can never be reissued). Two things strand it:

1. **A hard-deleted high DL** raises `last_value` once, then its ref cascades away when the
   card is hard-deleted — dropping `liveMax` but leaving `last_value` stuck high.
2. **A junk high DL on a trashed card** (a sentinel like `DL-99999` on a scratch/smoke-test
   card that got soft-deleted) keeps pinning `liveMax` — its ref is retained, so a reset
   can't walk the floor below it until the card is **force-deleted**.

Either way, every subsequent claim mints in the wrong range until you recover.

## Recover it (API-driven, no server shell)

Throughout, `<board>` is the board id; the endpoints are relative to the board's kanban API
base (`.release-pr.json` `api_base` / your `$KB_API`). Reads use the read token, the
mutations the write token.

### 1. Diagnose — read the counter and find what pins the floor

```bash
# The next number without consuming it — the symptom, at a glance.
next-dl <project> --peek

# The full counter state + what pins liveMax + the top DL refs with lifecycle status.
GET  boards/<board>/dl-sequence.json?show_refs=1
#   → { last_value, live_max, next, trashed_pinner, refs:[{ref,task_id,status,…}] }
```

> **`--peek` reads the counter** (the same `dl-sequence` route as the inspect call below), so it
> shows the stranded value. Before card#6232 it answered from an offline `max+1` scan over the
> board's *stamped* DL numbers, which returns `liveMax + 1` — the **correct-looking low value** —
> so on a stranded board the old `--peek` hid the very symptom this step looks for. If your
> `--peek` disagrees with the inspect call, your `next-dl` predates that fix.

`trashed_pinner` (non-null) is the auto-flag for cause #2: a **trashed** card still pinning
`live_max`. `refs` lists the highest DL refs with each owning card's `status`
(`live`/`archived`/`trashed`). Read it in full — you need **every** trashed pinner, not just
the top one (see step 2).

### 2. Enumerate EVERY trashed pinner — do not stop at the first

```bash
# All soft-deleted cards on the board that still carry a DL/pr ref.
GET  tasks/search.json?q=board_id=<board>&trashed=1
```

`liveMax` is the max over **all** retained refs, so removing only the highest trashed pinner
just re-strands the counter at the **next** junk ref below it. (Real incident: a board
stranded with two junk pinners, `DL-99999` and `DL-999` — force-deleting only the first left
it stranded at 999.) Collect the full set of trashed cards carrying a junk DL before you
delete anything.

### 3. Force-delete each junk pinner

For every junk trashed card from step 2:

```bash
# If the card is still live, soft-delete it first:
PATCH tasks/<id>.json        {"_action": "delete"}
# Then hard-delete the trashed card (cascades its DL ref away → drops liveMax):
POST  tasks/<id>/force-delete.json
```

Force-delete requires the board's card-delete permission (`task.delete`) and the card must be
trashed. **Do not** weaken the ref-retention to "fix" this — the retention is load-bearing:
a genuinely soft-deleted DL must never be reissued.

### 4. Reset the counter

```bash
# Dry-run first — computes the result, writes nothing:
POST boards/<board>/dl-sequence/reset.json   {"floor": <n>, "dry_run": true}
# Then apply. Omit floor to default to liveMax → next = liveMax + 1 (the minimum next DL):
POST boards/<board>/dl-sequence/reset.json   {"floor": <n>}
#   → { floor, last_value, live_max, next, floor_below_live_max, trashed_pinner }
```

Reset requires the board's DL-sequence-manage permission — **board admin / owner only**
(narrower than card force-delete, which a delegated card-manager may hold; a board admin
holds both, so the whole recovery self-serves). `floor` must be a non-negative integer.

**Safe by construction:** a claim floors at `GREATEST(last_value, liveMax)`, so lowering
`last_value` can **never** reissue a DL still indexed on the board — `liveMax` re-establishes
the floor. A `floor` below `liveMax` is not an error, but the next claim is pinned at
`liveMax + 1` regardless (`floor_below_live_max: true`); if `trashed_pinner` is still
non-null you missed a pinner in step 2 — go back.

### 5. Verify

```bash
GET  boards/<board>/dl-sequence.json          # next == the expected low value, trashed_pinner == null
next-dl <project> --peek                       # same value, through the tool operators actually use
```

The inspect call is the **authoritative** check: `next` back in the expected range and
`trashed_pinner: null` is what "recovered" means.

The `--peek` line is **not a second opinion on the counter** — since card#6232 it reads that same
route, so a matching answer is one measurement displayed twice, not corroboration. What it does
check is the leg the inspect call cannot: that the **operator's own tool** — its board env, token
and `api_base` — resolves to the board you just fixed. A mismatch means your `next-dl` is reading a
different board or predates card#6232, not that the reset failed.

## One-line summary

Diagnose (`next-dl --peek` + inspect) → **sweep ALL** trashed pinners
(`tasks/search.json?…&trashed=1`) → force-delete each → reset (default floor =
`liveMax`) → verify. The sweep must be exhaustive: any trashed DL ref left below the max
re-establishes the floor.
