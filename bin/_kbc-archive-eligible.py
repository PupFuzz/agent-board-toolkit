#!/usr/bin/env python3
"""_kbc-archive-eligible.py — the session-close "which done cards are SAFE to
archive" surfacing leg (roundtable #39 archive invariant, read-only).

READ-ONLY by construction: for each configured board (`kanban.boards[]`) it lists
the TERMINAL (done-lane) cards that the framework's shipped `may_archive` gate
reports as archive-eligible, so the agent can decide to run `kbcard archive #N`. It
NEVER writes / PATCHes anything — surfacing is its whole job; the archive is the
agent's call. Wired into `board-session-close` as a sibling section after the
inverse-drift leg, mirroring how that leg delegates to `kanban-reconcile.py`.

Per board it fetches the ONE board GET (`KanbanClient.fetch_board`), collects the
non-archived cards, and counts those in a `lane_type == "done"` stage — that count is
the cheap, actionable signal. It then runs the shipped
`may_archive(card, resolve, surviving_cards=<all non-archived>)` over a BOUNDED SAMPLE
of those done cards (the first `_MAX_DETAIL`) to show a concrete "safe to archive now"
starting point — bounded because the gate makes one `gh` call per backing source and the
authoritative per-card gate already runs in `kbcard archive` at archive time, so gating
the whole historical done backlog here would be a slow network storm for no added safety.
It uses the SAME shared GitHub-state resolver and kanban_common locator as
`_kbc-may-archive.py` (both live in `_kbc-archive-lib.py`; canon #5). The surviving-cards
set is EVERY non-archived card on the board, so a live source that still has a
non-archived twin is (correctly) reported eligible.

Fail LOUD, never silently skip (matching board-session-close's ethos): a board
whose id is unset/REPLACE_ME is reported as skipped; an unresolvable kanban_common
or a board fetch failure prints a ⚠ to stderr and drives a non-zero exit.
"""
from __future__ import annotations

import importlib.util
import os
import sys

_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_kbc-archive-lib.py")

# A board can carry a large historical un-archived-done backlog (hundreds of cards),
# and this runs at every session close — so the per-board DETAIL is capped while the
# summary count stays exact. The count is the actionable signal ("you have N to tidy");
# the capped sample + the tidy hint is enough to act on without drowning the ritual.
_MAX_DETAIL = 10


def _load_lib():
    spec = importlib.util.spec_from_file_location("kbc_archive_lib", _LIB)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _stage_field_maps(board: dict) -> "tuple[dict, dict]":
    """({stage_id: lane_type}, {stage_id: name}) from the board's
    workflows[].stages[] (a board GET's own stage shape)."""
    lane: dict = {}
    name: dict = {}
    for wf in board.get("workflows") or []:
        for s in wf.get("stages") or []:
            lane[s.get("id")] = s.get("lane_type")
            name[s.get("id")] = s.get("name")
    return lane, name


def _non_archived(board: dict) -> list:
    """Live cards from the ONE board GET: not archived, not deleted."""
    return [t for t in (board.get("tasks") or [])
            if not t.get("archived_at") and not t.get("deleted_at")]


def main() -> int:
    lib = _load_lib()
    path = lib.resolve_kanban_common()
    if not path:
        print("⚠ kbc-archive-eligible: may_archive primitive not found "
              "(kanban_common unresolvable via $KBCARD_KANBAN_COMMON, the coord "
              "plugin on $PATH, the marketplace clone, or the plugin cache) — the "
              "archive-eligible surfacing DID NOT RUN.", file=sys.stderr)
        return 1
    try:
        kc = lib.load_kanban_common(path)
        may_archive = kc.may_archive
    except Exception as e:  # noqa: BLE001
        print(f"⚠ kbc-archive-eligible: kanban_common loaded but unusable: {e}",
              file=sys.stderr)
        return 1

    cfg = kc.load_config()
    boards = (cfg.get("kanban") or {}).get("boards") or []
    if not boards:
        print("(no kanban.boards[] configured — nothing to check)")
        return 0

    token = kc.load_token()
    client = kc.KanbanClient(token, base_url=kc.kanban_base_url(),
                             verify=kc.kanban_tls_verify())
    errors = 0
    for bc in boards:
        key = bc.get("key") or "?"
        bid = str(bc.get("board_id") or "").strip()
        if not bid or bid == "REPLACE_ME":
            print(f"[ARCHIVE-ELIGIBLE] board ({key}): board_id not configured — "
                  f"skipped")
            continue
        try:
            board = client.fetch_board(bc["board_id"])
        except SystemExit as e:
            # fetch_board is LOUD-FATAL by contract (card#4889): it sys.exit(2)s on
            # any read failure, and SystemExit derives from BaseException so the
            # `except Exception` arm below would miss it. One unreachable board must
            # NOT abort the OTHER boards' surfacing — WARN-and-continue, and let the
            # non-zero errors count drive the loud run exit (same contract as
            # kanban-reconcile.py and kanban-inbox-check, card#4890).
            print(f"⚠ kbc-archive-eligible: board {bc.get('board_id')} ({key}): "
                  f"board read FATAL (exit {e.code}) — skipping this board",
                  file=sys.stderr)
            errors += 1
            continue
        except Exception as e:  # noqa: BLE001
            print(f"⚠ kbc-archive-eligible: board {bc.get('board_id')} ({key}): "
                  f"board read FAILED — {e}", file=sys.stderr)
            errors += 1
            continue

        lane, name = _stage_field_maps(board)
        cfg_repo = (bc.get("repo") or "").strip() or None
        surviving = _non_archived(board)
        terminal = [t for t in surviving
                    if lane.get(t.get("workflow_stage_id")) == "done"]

        # The done-count is the cheap, actionable signal ("board has N cards to tidy").
        # The may_archive gate makes one `gh` call PER backing source, so gating the whole
        # historical done backlog (hundreds of cards) at every session close is far too slow —
        # and redundant: `kbcard archive` runs the authoritative gate per card at archive time.
        # So gate only a BOUNDED sample here (the cards we'd show), to give a concrete
        # "safe to archive now" starting point without the network storm.
        checked = terminal[:_MAX_DETAIL]
        eligible: list = []
        for card in checked:
            resolve = lib.make_github_state_resolver(kc, card, cfg_repo)
            try:
                ok, reason = may_archive(card, resolve, surviving_cards=surviving)
            except Exception as e:  # noqa: BLE001 — a primitive fault is loud, not silent
                print(f"⚠ kbc-archive-eligible: board {bc.get('board_id')} ({key}) "
                      f"card #{card.get('id')}: may_archive raised — {e}",
                      file=sys.stderr)
                errors += 1
                continue
            if ok:
                col = name.get(card.get("workflow_stage_id")) or "?"
                eligible.append(
                    f"#{card.get('id')}  {card.get('name') or ''}  [{col}]  "
                    f"— {reason}")

        print(f"\n[ARCHIVE-ELIGIBLE] board {bc.get('board_id')} ({key}): "
              f"{len(terminal)} done card(s) not yet archived")
        if not terminal:
            print("  (none)")
            continue
        print(f"  of the first {len(checked)} checked, {len(eligible)} safe to archive now "
              f"(`kbcard archive` gates each at archive time):")
        for ln in eligible:
            print(f"    {ln}")
        if not eligible:
            print("    (none of the sample — a live source with no surviving twin holds them)")
        if len(terminal) > len(checked):
            print(f"  … {len(terminal) - len(checked)} more done card(s) not checked here — "
                  f"run `kbcard --board {key} archive --task <id>` to gate + tidy the backlog")

    return 2 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
