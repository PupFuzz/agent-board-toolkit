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
the primitive's `(ok, reason)` in a shape kbcard's bash can branch on.

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

import glob
import importlib.util
import json
import os
import sys


def _resolve_kanban_common() -> "str | None":
    """Path to the plugin's bundled kanban_common.py, or None. Order mirrors
    board-session-close resolve_reconcile_hook, targeting the examples/ copy the
    reconcile hook path-loads (never the optional user-site coord package)."""
    rel = os.path.join("templates", "kanban", "examples", "kanban_common.py")
    override = os.environ.get("KBCARD_KANBAN_COMMON")
    if override:
        return override if os.path.isfile(override) else None
    for pdir in os.environ.get("PATH", "").split(os.pathsep):
        # A coord plugin bin dir names the loaded version: .../coord/<ver>/bin
        norm = pdir.rstrip("/")
        if norm.endswith("/bin") and "/agent-board-framework/coord/" in norm:
            c = os.path.join(norm[: -len("/bin")], rel)
            if os.path.isfile(c):
                return c
    home = os.path.expanduser("~")
    c = os.path.join(home, ".claude", "plugins", "marketplaces",
                     "agent-board-framework", "plugins", "coord", rel)
    if os.path.isfile(c):
        return c
    cache = sorted(glob.glob(os.path.join(
        home, ".claude", "plugins", "cache", "agent-board-framework",
        "coord", "*", rel)))
    return cache[-1] if cache else None


def _load(path: str):
    spec = importlib.util.spec_from_file_location("kanban_common_kbc", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _emit(token: str, reason: str) -> int:
    sys.stdout.write(f"{token}\t{reason}")
    return 0


def main() -> int:
    try:
        req = json.loads(sys.stdin.read() or "{}")
    except Exception as e:  # noqa: BLE001 — malformed input is a fail-closed refusal
        return _emit("noprimitive", f"archive-gate input unreadable: {e}")

    path = _resolve_kanban_common()
    if not path:
        return _emit("noprimitive",
                     "may_archive primitive not found (kanban_common unresolvable "
                     "via $KBCARD_KANBAN_COMMON, the coord plugin on $PATH, the "
                     "marketplace clone, or the plugin cache)")
    try:
        kc = _load(path)
        may_archive = kc.may_archive
        derive_source = kc._derive_card_source
    except Exception as e:  # noqa: BLE001
        return _emit("noprimitive", f"kanban_common loaded but unusable: {e}")

    card = req.get("card") or {}
    surviving = req.get("surviving_cards") or []
    cfg_repo = (req.get("repo") or "").strip() or None
    # The card's own source (from pr_url / issue_url / payload.repo) via the
    # framework's server-mirroring normalizer — used when a by-ref descriptor
    # carries no explicit repo. For a single-repo board the config repo is the
    # authority; per-card derivation is the fallback for a card without it.
    card_source = derive_source(card)

    def resolve(src):
        kind, ref = src
        if kind != "by_ref":
            # A stable-id (id:<sid>) mirrors a coordination source kbcard has no
            # GitHub handle for — cannot determine liveness → fail-closed.
            return "unresolvable"
        repo = ref.get("repo") or cfg_repo or card_source
        if not repo:
            return "unresolvable"
        sub = "pr" if ref.get("kind") == "pr" else "issue"
        try:
            data = kc.gh_json([sub, "view", str(ref.get("number")),
                               "--repo", repo, "--json", "state"])
        except Exception:  # noqa: BLE001 — 404 / network / auth → unresolvable
            return "unresolvable"
        state = str((data or {}).get("state") or "").upper()
        if state == "OPEN":
            return "live"
        if state in ("CLOSED", "MERGED"):
            return "terminal"
        return "unresolvable"

    try:
        ok, reason = may_archive(card, resolve, surviving_cards=surviving)
    except Exception as e:  # noqa: BLE001 — a primitive fault is fail-closed
        return _emit("noprimitive", f"may_archive raised: {e}")
    return _emit("ok" if ok else "blocked", reason)


if __name__ == "__main__":
    sys.exit(main())
