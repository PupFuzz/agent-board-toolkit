#!/usr/bin/env python3
"""_kbc-archive-lib.py — shared archive-gate plumbing for the toolkit's archive
tooling (roundtable #39).

Two archive-time consumers ride the framework's shipped `may_archive` primitive
(`kanban_common.may_archive`): the per-card stdin gate `_kbc-may-archive.py`
(kbcard's archive-safety check) and the session-close surfacing leg
`_kbc-archive-eligible.py` (the read-only "which done cards are safe to archive"
report). BOTH need the same two pieces — (a) the version-agnostic locator for the
plugin-maintained `kanban_common`, and (b) the tri-state GitHub-state per-source
`resolve(src)` reader `may_archive` injects over. This module is the SINGLE home
for both, so the second consumer extends the primitive rather than sibling-ing a
divergent copy (canon #5).

It is NOT importable by name (its filename carries hyphens, matching its sibling
scripts); a consumer path-loads it via `importlib.util.spec_from_file_location`,
the same by-path load the reconcile hook uses for `kanban_common`.
"""
from __future__ import annotations

import glob
import importlib.util
import os


def resolve_kanban_common() -> "str | None":
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


def load_kanban_common(path: str):
    """Path-load kanban_common under an isolated module name (never the optional
    user-site coord package)."""
    spec = importlib.util.spec_from_file_location("kanban_common_kbc", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def make_github_state_resolver(kc, card: dict, cfg_repo: "str | None" = None):
    """Build the tri-state `resolve(src)` reader `may_archive` injects over, for
    ONE card's backing sources. Returns a callable that maps a source descriptor
    from `_card_backing_sources` to "live" (OPEN issue/PR), "terminal" (CLOSED /
    MERGED), or "unresolvable" (a read that could not determine state — 404 /
    network / a source with no GitHub handle) — the tri-state `may_archive`
    fail-closes on.

    `cfg_repo` is the caller's already-normalized (str-or-None) board/config repo,
    the authority for a single-repo board; a by-ref descriptor's own `repo` wins
    over it, and the card's derived source (from pr_url / issue_url / payload.repo,
    via the framework's server-mirroring normalizer) is the final fallback."""
    card_source = kc._derive_card_source(card)

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

    return resolve
