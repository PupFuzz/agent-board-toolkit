#!/usr/bin/env python3
"""_kbc-may-archive.py — kbcard's archive-time safety gate (roundtable #39).

Reads ONE JSON object on stdin and prints ONE decision line on stdout:

    {"card": <task>, "surviving_cards": [<task>...], "repo": "<owner/repo>|"",
     "board_id": "<id>"}
        -> "ok\t<reason>" | "blocked\t<reason>" | "noprimitive\t<reason>"

It is a THIN caller of the framework's shipped `may_archive` primitive
(`kanban_common.may_archive`) — it invents no archive policy of its own. Its only
job is to (a) locate the plugin-maintained `kanban_common` version-agnostically,
(b) build the tri-state per-source resolver over the card's backing coordination
sources using the framework's own `gh_json` GitHub-state reader, and (c) surface
the primitive's `(ok, reason)` in a shape kbcard's bash can branch on. Both (a) and
(b) live in the shared `_kbc-archive-lib.py` — the session-close archive-eligible
leg is the second consumer of that same plumbing (canon #5).

The resolver contract (see may_archive's docstring): given one source descriptor
from `_card_backing_sources` return "live" (open PR/issue), "terminal"
(closed/merged), or "unresolvable" (a read that could not determine state — 404 /
network / a source kbcard cannot map). "unresolvable" is FAIL-CLOSED at the
primitive (blocked unless a surviving twin keeps the source discoverable).

If `kanban_common` cannot be located the gate cannot verify archive safety, so this
prints `noprimitive` and kbcard REFUSES the archive (unless --force) — it never
silently archives unchecked. Locating mirrors `board-session-close`'s
`resolve_reconcile_hook` (env override, coord dir on PATH, marketplace clone,
newest cache) so a plugin bump never breaks it.
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys

_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_kbc-archive-lib.py")


def _load_lib():
    spec = importlib.util.spec_from_file_location("kbc_archive_lib", _LIB)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


_lib = _load_lib()
# The selftest execs this module and calls `_resolve_kanban_common()` directly, so
# keep the name bound to the shared locator.
_resolve_kanban_common = _lib.resolve_kanban_common


def _emit(token: str, reason: str) -> int:
    sys.stdout.write(f"{token}\t{reason}")
    return 0


def main() -> int:
    try:
        req = json.loads(sys.stdin.read() or "{}")
    except Exception as e:  # noqa: BLE001 — malformed input is a fail-closed refusal
        return _emit("noprimitive", f"archive-gate input unreadable: {e}")

    path = _lib.resolve_kanban_common()
    if not path:
        return _emit("noprimitive",
                     "may_archive primitive not found (kanban_common unresolvable "
                     "via $KBCARD_KANBAN_COMMON, the coord plugin on $PATH, the "
                     "marketplace clone, or the plugin cache)")
    try:
        kc = _lib.load_kanban_common(path)
        may_archive = kc.may_archive
        kc._derive_card_source  # presence check — the shared resolver needs it
    except Exception as e:  # noqa: BLE001
        return _emit("noprimitive", f"kanban_common loaded but unusable: {e}")

    if req.get("card") is None:  # explicit null / absent — NOT an empty-object card
        return _emit("noprimitive",
                     "archive-gate got no card object (fetch returned null/absent "
                     ".data) — cannot verify archive safety")
    card = req.get("card")
    surviving = req.get("surviving_cards") or []
    cfg_repo = (req.get("repo") or "").strip() or None
    # The card's own source is the resolver's fallback repo (built inside the
    # shared factory); for a single-repo board the config repo is the authority.
    resolve = _lib.make_github_state_resolver(kc, card, cfg_repo)

    try:
        ok, reason = may_archive(card, resolve, surviving_cards=surviving)
    except Exception as e:  # noqa: BLE001 — a primitive fault is fail-closed
        return _emit("noprimitive", f"may_archive raised: {e}")
    return _emit("ok" if ok else "blocked", reason)


if __name__ == "__main__":
    sys.exit(main())
