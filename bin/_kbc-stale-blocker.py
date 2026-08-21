#!/usr/bin/env python3
"""_kbc-stale-blocker.py — the session-close "which open card still says it is
BLOCKED by a card that has since become terminal" surfacing leg (card#7113 half A,
read-only).

THE DEFECT IT REPORTS. A card's own text states a constraint — *blocked behind
card#N* — that was TRUE when written. Nothing re-reads that card when #N ships, so
the card keeps asserting it, and the next reader (human or agent) hits the stale half
first and treats pullable work as blocked. Measured cost on this install: one card sat
in `backlog` reading as blocked for days after its blocker reached `released_to_main`.
This leg is the DERIVABLE half of that class: *a citation of a card id, in blocking
context, whose referent is terminal* is mechanically decidable. The other half — a
gate answered lower down in the same prose — has no machine-checkable predicate and is
a WRITING rule; ⛔ do not grow a keyword guesser for it here.

READ-ONLY by construction: every call it makes is a GET, and it never PATCHes,
archives or moves anything. Surfacing is the whole job; editing the stale card is the
agent's call. Same advisory contract as `_kbc-archive-eligible.py` in
`board-session-close`: FINDINGS RIDE THE REPORT AT rc 0 — a non-zero exit means the
INSTRUMENT failed (a board could not be read, the plumbing is missing), never that a
stale citation was found.

⛔ NON-GOAL — `board-snapshot`. This is a session-close leg only. `board-snapshot` is
the SessionStart hook and runs under a hard time budget on every session start; this
leg costs one board GET per roster board plus up to `_MAX_REFERENT_GETS` card GETs, and
buys nothing at session START that it does not buy better at session close, where the
operator is already reconciling cards.

────────────────────────────── THE PREDICATE, STATED ──────────────────────────────

POPULATION — every OPEN card on every roster board (`kanban.boards[]`): a card whose
stage `lane_type` is NOT `done`, read from the board GET (which returns the board's
ACTIVE tasks, so archived/deleted cards are not citers). Surfaces scanned are `name` +
`description`. ⚑ COMMENT THREADS ARE NOT SCANNED — a long-lived thread carries the
same shape and is a stated gap, not an oversight.

A card is FLAGGED when its text carries a CITATION in BLOCKING CONTEXT whose REFERENT
is TERMINAL, with three structural EXCLUSIONS. Each part below is a measured choice,
not a default:

1. CITATION — `card#N` / `card #N` / `cards #N`, case-insensitive, with any repo
   qualifier in front of it (`bridge card#5300`) simply ignored, since ids are global
   on this install and the qualifier adds nothing the id does not already say.
   ⛔ A BARE `#N` IS NOT A CITATION, and the figures below carry their denominator
   because it is the population (48 open cards, measured 2026-08-21) that makes them
   mean anything. A predicate keyed on `#N` — which necessarily also matches the `#N`
   inside `card#N` — sees 304 references and flags 27 OF THE 48; restricted to `#N`
   references that are NOT part of a `card#N` (151 of them), it still flags 8 of the 48,
   and not one of those references is a card citation at all: `#N` is also a PR number,
   a roundtable issue number and an engineering-canon rule number throughout this
   corpus. The `card` token is what makes the reference a card reference.

2. BLOCKING CONTEXT — a blocking marker must PRECEDE the citation ON THE SAME LINE,
   with at most `_MARKER_WINDOW` characters of intervening text — the window is measured
   from the MARKER'S END to the CITATION'S START, so it bounds what sits BETWEEN them and
   a longer marker does not buy a shorter reach — and with NO SENTENCE BOUNDARY in that
   intervening text. Markers: blocked / blocker / blocks / depends on / dependent on /
   gated on / gates on / waiting on / queued behind / queue behind / sequenced after /
   sequenced behind — matched on WORD BOUNDARIES over the WHOLE LINE (see the note at the
   scan itself: matching them over a truncated prefix makes the truncation point a word
   boundary, which is a false positive at exactly one alignment, and shortens the window
   by the marker's own length, which is a silent under-report).
   ⛔ BARE `behind` AND BARE `after` ARE NOT MARKERS. `Filed by the canon #7 sibling
   audit behind card#5410` is PROVENANCE, not a blocker, and provenance is how most
   `card#N` references in this corpus are written — that is why `card#N` anywhere flags
   27 of the 48 open cards while `card#N` in blocking context leaves ONE citation
   standing on the same corpus.
   The window is a bound, not a tuned figure — 40, 60, 80, 120 and 200 all return the
   IDENTICAL candidate set live (re-measured 2026-08-21 after the whole-line fix above,
   because the earlier sweep ran against the defective slice and could not have detected
   it). ⚑ Read that for what it is: evidence the figure is not fitted to this corpus, NOT
   evidence the bound is idle — this corpus simply carries no marker/citation pair at a
   middling distance, and the bound is what stops one appearing at the far end of a long
   table row from governing an unrelated citation.

3. EXCLUSIONS — `_EXCLUSIONS` below, applied only to citations that ALREADY have
   blocking context (so each exclusion count in the report is exactly "citations that
   would otherwise have been examined as blockers", never padding from citations that
   were never candidates). Each is structural, and each is INDEPENDENTLY justified:
     a. INLINE-CODE — the citation sits inside a backtick span. A quoted specimen is
        prose ABOUT the shape, not an assertion of it; this card (#7113) quotes the
        historical positive in a table cell and would otherwise flag itself.
        ⚑ ITS FALSE NEGATIVE, STATED WITH THE OTHER TWO RATHER THAN LEFT TO BE FOUND:
        back-ticking a card reference INSIDE a genuine blocking sentence — ``Blocked
        behind `card#6570` until it ships`` — is ordinary style in this corpus, and this
        exclusion drops it. The exclusion keys on the citation's own position, and
        "quoted specimen" versus "quoted reference in an assertion" is a distinction
        about the sentence, not about the span; drawing it is the half-B guesswork this
        leg refuses. So it is an accepted under-report, on the same side as (c) and as
        the `waiting` bound in (4), and it is named in the report's own footer.
     b. STRIKETHROUGH — the citation sits inside `~~…~~`. Retracted text is text the
        author has already withdrawn; asserting it back is reading the edit backwards.
     c. DISCHARGE-LINE — the line carries `UNBLOCKED` / `RESOLVED` / `DISCHARGED` / `✅`.
        A line announcing the discharge is not asserting the constraint.
        ⚑ ITS KNOWN FALSE NEGATIVE, STATED AND DELIBERATELY NOT FIXED: a line reading
        `UNBLOCKED? no — still blocked behind card#N` is suppressed, and so is any line
        that happens to use the ordinary English word "resolved" (the match is
        case-insensitive). Both under-report on the same side as the `waiting` bound in
        (4). Discriminating them needs sentence-level meaning, which is exactly the
        half-B guesswork this leg refuses to do.

4. REFERENT TERMINAL — the cited card's stage `lane_type == "done"`, or the referent is
   archived/deleted. The lane type is DERIVED from each board's own preload/GET stage
   shape via `_kbc-archive-lib.py`'s `stage_field_maps` — the classification
   `_kbc-archive-eligible.py` decides on and `board-stats` makes off the same shape.
   ⛔ NO STAGE ID IS HARDCODED: board consumers key on numeric stage ids and those
   differ per board, so the map is keyed by `(board_id, stage_id)` and a stage the
   corpus never described is reported UNRESOLVED rather than guessed at. The board
   qualifier in that key is load-bearing, not tidiness: stage ids are small integers
   drawn from ONE server-wide sequence, so an unqualified key lets another board's stage
   3 answer for ours — which is how a foreign card acquires one of our lane types (see
   (5), and the mutant in the selftest that demonstrates exactly that wrong flag).
   ⚑ `waiting` (Shipped to dev) IS DELIBERATELY NOT TERMINAL — a KNOWN UNDER-REPORT with
   its reason: the class as filed names `released_to_main` / `wont_do` / archived, and a
   blocker sitting in `shipped_to_dev` has not reached main, so a card waiting on it is
   arguably still correct. A guard's stated scope must equal its actual predicate, so it
   is stated here and in the report's own footer rather than left to be discovered.

5. REFERENT RESOLUTION IS CROSS-BOARD **WITHIN THIS TENANT, AND DELIBERATELY NO
   FURTHER**. ⛔ READ THIS BEFORE CHANGING THE RESOLUTION PATH: this kanban instance is
   MULTI-TENANT — one server, several tenants' boards — and **card ids are allocated
   GLOBALLY across all of them**. So `card#1120` on one of our cards resolves, via a bare
   `GET /tasks/1120.json`, to a REAL card that may belong to ANOTHER TENANT, and a report
   built on it would be confident and completely wrong. That is not hypothetical: it was
   measured live on this install (roundtable #327) — a mis-cited id resolved to another
   tenant's board and the only thing that stopped an automation acting on it was a
   token-scope 403, which is an accident, not a guard. This leg does not rely on that
   accident.
   The index is therefore built ONLY from the ROSTER boards (`kanban.boards[]`), read in
   full before any citation is resolved — citations cross OUR boards routinely, so a
   per-board scan would answer "absent" for a referent the next board's read supplies. An
   id that index does not carry gets ONE `GET /tasks/{id}.json`, bounded by
   `_MAX_REFERENT_GETS` per run and CACHED per id, and its `board_id` is then CHECKED
   AGAINST THE ROSTER SET.
   ⛔ THE ROSTER SET IS DECLARED FROM THE CONFIG, BEFORE ANY BOARD IS READ, and the ids
   are coerced to int because a configured `board_id` is a STRING here while every card's
   is an integer. Building it from boards that READ SUCCESSFULLY is the same sentence
   with a different meaning and it is wrong: one unreachable board then turns every
   citation of its cards into an OUT-OF-TENANT finding, and this report's remediation for
   that state is "fix the citation" — told to a reader whose citation was correct. Who a
   card BELONGS to is a fact about the config; whether this run can DECIDE anything about
   it is a fact about the read. They are tracked separately (`roster_boards` vs
   `boards_read`) for exactly that reason. Five outcomes, five distinct report states,
   never collapsed:
     * a ROSTER board that WAS read (an archived card, typically) — resolved normally;
     * a ROSTER board that could NOT be read this run — UNRESOLVED, saying so in those
       words. Never out-of-tenant (it is ours), never a flag (nothing was decided);
     * a NON-ROSTER board — reported OUT-OF-TENANT, naming BOTH boards, and it can never
       become a flag. Per the report above, an out-of-tenant resolution is ALWAYS a
       mis-citation, so it is surfaced as a finding in its own right rather than quietly
       dropped;
     * 404 — UNRESOLVED, the id genuinely does not exist;
     * anything else — UNRESOLVED, state undetermined. ⛔ A 403 IS NOT A 404 AND NOT AN
       EMPTY RESULT. The tri-state comes from the framework's own `fetch_card_status`,
       which gates on the HTTP STATUS and separates a 404 from every other failure, so a
       not-permitted read can never arrive here wearing "no such card".
   ⛔ THE NARROW SCOPE IS THE GUARD. Do not "fix" an out-of-tenant finding by widening a
   token or adding board access — the correct answer to a citation of another tenant's id
   is to correct the citation.
   A budget exhaustion is UNRESOLVED **and says the bound was hit**. ⛔ Nothing is
   silently dropped: every citation reaching this step lands in a reported state.

⚑ ONE OVER-REPORT SHAPE THIS PREDICATE CANNOT SEE, stated because it is live in the
corpus today: the marker→citation direction does not distinguish *"blocked by card#N"*
from *"this blocks card#N"* — in the second, the citation is the BLOCKED party, not the
blocker. `blocks` is in the marker set because the class as filed names it, so a line
like `It also blocks end-to-end validation of card#6873` reaches the referent check and
would flag if #6873 were terminal. Reading that direction needs sentence-level meaning
(half B again). The cost is bounded — it can only ever over-report onto a card the
operator then reads at source — and the alternative (dropping `blocks`) loses the
straightforward `blocks: card#N` spelling.

⛔ WHAT IS DELIBERATELY NOT BUILT — the `linked_tasks` relation-`blocks` leg the card
originally proposed. Measured on the live corpus before building anything: of the open
cards, THREE carry `linked_tasks` at all and every one of them is `relation_type:
"caused"` — ZERO are `blocks`, on any card, on any of the three boards. That leg reports
0 forever, at a cost of one detail GET PER OPEN CARD (the relation is not in the board
GET or the search projection). A check that cannot fire is a decoration; when the
relation is actually used, this is the file it belongs in.

────────────────────────────────── REPORTING ──────────────────────────────────

Every run prints its DENOMINATOR — boards scanned, open cards scanned, citations
examined, the disposition of every one of them, flags, unresolved referents, and the
referent-GET budget usage. A clean run therefore says WHAT POPULATION it was clean over:
an empty result here is a measurement, not a silence.

Fail LOUD, never silently skip (`board-session-close`'s ethos): a board whose id is
unset/REPLACE_ME is reported skipped, and an unresolvable `kanban_common` or a board
fetch failure prints a ⚠ to stderr and drives a non-zero exit — rc 1 the plumbing never
loaded, rc 2 the scan ran but at least one board or referent read failed, so the
population is smaller than it claims.
"""
from __future__ import annotations

import importlib.util
import os
import re
import sys

_LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_kbc-archive-lib.py")

# How far back from a citation a blocking marker may sit and still govern it. NOT a
# tuned figure: 40 / 60 / 80 / 120 all return the same citation set on the live corpus
# (measured 2026-08-20, 3 boards). It exists to stop a marker at the far end of a long
# line from governing an unrelated citation at the other end.
_MARKER_WINDOW = 60

# Referent GETs are the only per-CITATION network cost, and a corpus-absent id is the
# rare case (an archived blocker, or one on a board outside the roster). The bound keeps
# a pathological card — a table of fifty archived ids — from turning a session close into
# a network storm; hitting it is REPORTED, never silently truncating the answer.
_MAX_REFERENT_GETS = 25

# The quoted evidence line in a finding, truncated so one long table row cannot flood the
# ritual's output. The card id is what the operator acts on; the quote is orientation.
_QUOTE_MAX = 160

_CITATION_RE = re.compile(r"\bcards?[ \t]{0,2}#[ \t]{0,2}(\d+)", re.IGNORECASE)

_MARKER_RE = re.compile(
    r"\b(?:blocked|blocker|blocks|depends[ \t]+on|dependent[ \t]+on|gated[ \t]+on"
    r"|gates[ \t]+on|waiting[ \t]+on|queued[ \t]+behind|queue[ \t]+behind"
    r"|sequenced[ \t]+after|sequenced[ \t]+behind)\b",
    re.IGNORECASE,
)

# A sentence boundary is terminal punctuation followed by whitespace or end-of-line —
# NOT a bare `.`, which would cut `v0.73.0` and `card #6570.` in half and silently drop
# real citations.
_SENTENCE_RE = re.compile(r"[.!?](?:[ \t]|$)")

_DISCHARGE_RE = re.compile(r"\b(?:unblocked|resolved|discharged)\b|✅", re.IGNORECASE)

# Markdown inline code: a run of N backticks closed by the same run. Unbalanced ticks
# match nothing, which is the safe direction — an unmatched tick must not swallow the
# rest of the line and suppress a real citation.
_CODE_SPAN_RE = re.compile(r"(`+)(?:(?!\1).)*\1")
_STRIKE_SPAN_RE = re.compile(r"~~(?:(?!~~).)*~~")


def config_board_id(bc: dict) -> "tuple[int | None, str | None]":
    """(board id, refusal reason) for one `kanban.boards[]` entry.

    The id is COERCED TO INT because the two sides of every lookup in this file are the
    two sides of this coercion: a configured `board_id` is a STRING on this install
    (`"5"`), while a card row's and a board body's `id` are INTEGERS. An uncoerced roster
    would be a set no card can ever be a member of — which, in the tenancy gate below,
    would read as "every referent is another tenant's"."""
    raw = str(bc.get("board_id") or "").strip()
    if not raw or raw == "REPLACE_ME":
        return None, "board_id not configured"
    try:
        return int(raw), None
    except ValueError:
        return None, (f"board_id {raw!r} is not an integer, so no card's board_id can "
                      f"ever match it")


def _load_lib():
    spec = importlib.util.spec_from_file_location("kbc_archive_lib", _LIB)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _in_span(rx: "re.Pattern", line: str, idx: int) -> bool:
    return any(m.start() <= idx < m.end() for m in rx.finditer(line))


def _excl_inline_code(line: str, at: int) -> bool:
    return _in_span(_CODE_SPAN_RE, line, at)


def _excl_strikethrough(line: str, at: int) -> bool:
    return _in_span(_STRIKE_SPAN_RE, line, at)


def _excl_discharge_line(line: str, at: int) -> bool:  # noqa: ARG001 — line-scoped
    return bool(_DISCHARGE_RE.search(line))


# The exclusion registry: ONE owner for the class names the report counts by and the
# predicates that decide them, so a class can never be counted under a name nothing
# implements (or implemented under a name nothing reports). Order is report order.
# Each row is independently removable — which is exactly what
# tests/kbc-stale-blocker-selftest.sh does, one row at a time, to watch the case that
# row suppresses turn back into a flag.
_EXCLUSIONS = (
    ("inline-code", _excl_inline_code),
    ("strikethrough", _excl_strikethrough),
    ("discharge-line", _excl_discharge_line),
)


def blocking_citations(text: str):
    """Every citation in `text`, classified. Yields
    `(line, referent_id, disposition)` where disposition is
    `"no-blocking-context"`, one of the `_EXCLUSIONS` class names, or `"candidate"` —
    a citation asserted as a blocker, whose referent must now be resolved.

    Pure — no I/O, no config, no clock — so the whole predicate is decidable from a
    string, and the network half of this leg decides nothing about it."""
    for line in (text or "").split("\n"):
        # ⛔ THE MARKERS ARE MATCHED OVER THE WHOLE LINE, NEVER OVER A SLICE OF IT, and
        # that is a correctness requirement rather than an optimisation. `\b` is evaluated
        # against the string the regex is handed, so matching into `line[start-60:start]`
        # made the cut position itself a word boundary: a word whose SUFFIX is a marker
        # (`docblocks`, `roadblocks`, `unblocks`, `subblocker`) matched at exactly the one
        # alignment where the cut fell mid-word — the false positive the boundary exists to
        # prevent, reachable at one gap per marker. The same slice also shortened the
        # window by the marker's own length (a real `sequenced behind … card#N` reached
        # only 44 characters, not 60), silently under-reporting, which is the direction
        # that matters here. One list per line, reused by every citation on it.
        markers = list(_MARKER_RE.finditer(line))
        for m in _CITATION_RE.finditer(line):
            rid = int(m.group(1))
            # THE WINDOW IS MEASURED FROM THE MARKER'S END TO THE CITATION'S START — the
            # intervening text, not the marker's own length. The NEAREST qualifying marker
            # governs; an earlier one is not consulted, so a marker with a sentence
            # boundary after it does not hand the citation to the marker before it.
            marker = None
            for mm in markers:
                if mm.end() <= m.start() and m.start() - mm.end() <= _MARKER_WINDOW:
                    marker = mm
            if marker is None or _SENTENCE_RE.search(line[marker.end():m.start()]):
                yield line, rid, "no-blocking-context"
                continue
            hit = None
            for label, pred in _EXCLUSIONS:
                if pred(line, m.start()):
                    hit = label
                    break
            yield line, rid, hit or "candidate"


class _Corpus:
    """The roster's live cards indexed by id, plus each board's stage lane map, plus
    the bounded per-id detail read for an id the roster does not carry."""

    def __init__(self, client):
        self._client = client
        self.cards: dict = {}                  # id -> card row (live, roster boards)
        self.board_key: dict = {}              # board_id -> config key
        self.roster_boards: set = set()        # DECLARED in kanban.boards[] — the ONLY
                                               # boards this run may resolve into
        self.boards_read: set = set()          # of those, the ones actually READ
        self.lane: dict = {}                   # (board_id, stage_id) -> lane_type
        self.stage_name: dict = {}             # (board_id, stage_id) -> stage name
        self.gets = 0
        self.budget_hit = False
        self.read_errors = 0
        self._resolved: dict = {}              # id -> verdict tuple (cache)

    def declare_roster(self, board_id: int, key: str) -> None:
        """Register a CONFIGURED board — before any read, and whatever the read does.

        ⛔ THIS IS SEPARATE FROM `add_board` ON PURPOSE. The tenancy gate asks "is this
        referent one of OURS", which is a question about the CONFIG. Populating the set
        from successful reads instead answered "is this referent on a board that happened
        to respond", so one unreachable board turned every citation of its cards into an
        OUT-OF-TENANT finding — the report telling the reader to fix a citation that was
        correct. A board's READABILITY belongs in `boards_read` and changes what this run
        can DECIDE, never who the card belongs to."""
        self.roster_boards.add(board_id)
        self.board_key.setdefault(board_id, key)

    def add_board(self, lib, board_id: int, key: str, board: dict) -> list:
        lane, name = lib.stage_field_maps(board)
        for sid, lt in lane.items():
            self.lane[(board_id, sid)] = lt
            self.stage_name[(board_id, sid)] = name.get(sid)
        self.board_key[board_id] = key
        self.boards_read.add(board_id)
        live = lib.live_cards(board)
        for card in live:
            self.cards[card.get("id")] = card
        return live

    def card_board(self, card: dict, default=None):
        """The board a card row belongs to — ONE accessor, so the lane lookup, the
        tenancy gate and the citer's own column label cannot key on different fields."""
        bid = card.get("board_id")
        return default if bid is None else bid

    def _classify(self, card: dict) -> "tuple[str, str]":
        """(verdict, detail) for a card row this corpus can see."""
        if card.get("archived_at"):
            return "terminal", "archived"
        if card.get("deleted_at"):
            return "terminal", "deleted"
        bid = self.card_board(card)
        sid = card.get("workflow_stage_id")
        if bid in self.roster_boards and bid not in self.boards_read:
            # OURS, but this run could not read its board, so its lane map is absent.
            # Distinct from out-of-tenant (whose board is not ours at all) and from a
            # 404 (whose card does not exist): the only thing missing here is THIS RUN's
            # knowledge, and saying so is what stops a partial read reading as a verdict.
            return ("unresolved",
                    f"referent is on board {self.board_key.get(bid) or bid}, which is in "
                    f"the roster but could NOT BE READ this run — its lane type is "
                    f"unknown here, not terminal and not open")
        lt = self.lane.get((bid, sid))
        if lt is None:
            # A roster board's own stages are all in the map, so this is the board
            # answering with a stage its workflow did not declare — undecidable, and an
            # undecidable referent is reported, never assumed open.
            return ("unresolved",
                    f"referent sits in stage {sid} of board {bid}, which that board's "
                    f"own workflow never declared — its lane type is undecidable here")
        where = self.stage_name.get((bid, sid)) or f"stage {sid}"
        board = self.board_key.get(bid) or f"board {bid}"
        if lt == "done":
            return "terminal", f"{where} ({board})"
        return "open", f"{where} ({board}, lane_type {lt})"

    def resolve(self, rid: int) -> "tuple[str, str]":
        """(verdict, detail) for a cited id — "terminal", "open" or "unresolved"."""
        if rid in self._resolved:
            return self._resolved[rid]
        card = self.cards.get(rid)
        if card is not None:
            out = self._classify(card)
        elif self.gets >= _MAX_REFERENT_GETS:
            self.budget_hit = True
            out = ("unresolved",
                   f"not on any roster board and the per-run referent-read budget "
                   f"({_MAX_REFERENT_GETS}) was already spent — this id was NOT read")
        else:
            self.gets += 1
            # `fetch_card_status` is the framework's tri-state read and gates on the HTTP
            # STATUS: "absent" is a 404 and NOTHING else, so a 403 (the cross-tenant case
            # below, when a token happens to be scoped) lands in "error" and can never
            # arrive here as "no such card".
            status, row = self._client.fetch_card_status(rid)
            if status == "ok" and isinstance(row, dict):
                # ⛔ TENANCY GATE — ids are global on this multi-tenant instance, so a
                # successful read is NOT evidence the card is ours. Checked BEFORE any
                # classification, including the archived one: "archived" would otherwise
                # be reported as a terminal blocker about another tenant's card.
                if self.card_board(row) not in self.roster_boards:
                    out = ("out-of-tenant",
                           f"the id resolves to a card on board {self.card_board(row)}, "
                           f"which is NOT one of this roster's boards "
                           f"({sorted(self.roster_boards)}) — a citation of an id outside "
                           f"this tenant is a MIS-CITATION, not a blocker; fix the "
                           f"citation rather than widening any token")
                else:
                    out = self._classify(row)
            elif status == "absent":
                out = ("unresolved", "no such card (404) — the citation names an id "
                                     "that does not exist")
            else:
                # A read that FAILED is not a card that is absent (canon: an unreadable
                # response is not an empty one), and it is an instrument fault, so it
                # also drives the run's exit code.
                self.read_errors += 1
                out = ("unresolved", "the referent read FAILED (a non-404 status — a 403 "
                                     "not-permitted read is one, and on this shared "
                                     "instance is itself a hint the id is another "
                                     "tenant's — or a transport fault) — state "
                                     "undetermined, NOT absent")
        self._resolved[rid] = out
        return out


def _quote(line: str) -> str:
    s = line.strip()
    return s if len(s) <= _QUOTE_MAX else s[:_QUOTE_MAX - 1] + "…"


def main() -> int:
    lib = _load_lib()
    path = lib.resolve_kanban_common()
    if not path:
        print("⚠ kbc-stale-blocker: kanban board plumbing not found (kanban_common "
              "unresolvable via $KBCARD_KANBAN_COMMON, the coord plugin on $PATH, the "
              "marketplace clone, or the plugin cache) — the stale-blocker-citation "
              "scan DID NOT RUN.", file=sys.stderr)
        return 1
    try:
        kc = lib.load_kanban_common(path)
    except Exception as e:  # noqa: BLE001
        print(f"⚠ kbc-stale-blocker: kanban_common loaded but unusable: {e}",
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
    corpus = _Corpus(client)
    errors = 0
    scanned: list = []          # (board_id, key, live cards, open cards)

    # ── PASS 1: DECLARE the roster, before a single read ────────────────────────
    # The tenancy gate is a question about the CONFIG, so the set it consults is built
    # here — where no answer depends on whether a board responds. An entry this pass
    # cannot turn into an id is reported and is a member of nothing.
    entries: list = []
    declared = 0
    for bc in boards:
        key = bc.get("key") or "?"
        bid, refusal = config_board_id(bc)
        if bid is None:
            print(f"[STALE-BLOCKER] board ({key}): {refusal} — skipped, and it is in "
                  f"NO population this run: not scanned, and not a board a citation can "
                  f"resolve into")
            continue
        if bid in corpus.roster_boards:
            print(f"[STALE-BLOCKER] board {bid} ({key}): a SECOND kanban.boards[] entry "
                  f"for a board already declared — skipped, so its cards are counted "
                  f"once (a duplicate entry is a config defect worth fixing, not a "
                  f"reason to scan the board twice)")
            continue
        corpus.declare_roster(bid, key)
        entries.append((key, bid))
        declared += 1

    # ── PASS 2: READ each declared board ────────────────────────────────────────
    for key, bid in entries:
        try:
            board = client.fetch_board(bid)
        except SystemExit as e:
            # fetch_board is LOUD-FATAL by contract (card#4889) and SystemExit derives
            # from BaseException, so the `except Exception` arm below would miss it. One
            # unreachable board must not abort the others — WARN-and-continue and let the
            # error count drive the run's exit, the contract the archive-eligible leg and
            # kanban-inbox-check already keep. It DOES shrink the referent corpus, which
            # is why the report says how many boards it actually read.
            print(f"⚠ kbc-stale-blocker: board {bid} ({key}): board read FATAL (exit "
                  f"{e.code}) — this board is NOT scanned, and a citation of one of its "
                  f"cards can only be reported UNRESOLVED (it stays in the roster, so it "
                  f"is never mistaken for another tenant's)", file=sys.stderr)
            errors += 1
            continue
        except Exception as e:  # noqa: BLE001
            print(f"⚠ kbc-stale-blocker: board {bid} ({key}): board read FAILED — {e}; "
                  f"not scanned, and its cards resolve only as UNRESOLVED",
                  file=sys.stderr)
            errors += 1
            continue
        # The body must BE the board that was asked for. Its cards and stage rows are
        # keyed by the server's integer id, so indexing a body that answers with a
        # different id would file another board's stages under this board's key — and on
        # a shared instance "the id I asked for" and "the id I got" are exactly the pair
        # a tenancy decision must not conflate. An id-less body is refused for the same
        # reason: the fallback's answer would be wrong-but-plausible.
        body_id = board.get("id")
        if body_id != bid:
            print(f"⚠ kbc-stale-blocker: board {bid} ({key}): the board body identifies "
                  f"itself as {body_id!r}, not {bid} — refusing to index it, because its "
                  f"stages would be filed under a board they do not belong to",
                  file=sys.stderr)
            errors += 1
            continue
        live = corpus.add_board(lib, bid, key, board)
        open_cards = [c for c in live
                      if corpus.lane.get((corpus.card_board(c, bid),
                                          c.get("workflow_stage_id"))) != "done"]
        scanned.append((bid, key, live, open_cards))

    if not corpus.boards_read:
        # The two causes are different operator actions, so they are two messages: a
        # roster that declared nothing readable is a CONFIG state, an unreadable roster
        # is an ACCESS state, and reporting both as "no board could be read" sends the
        # reader to look at the wrong one.
        if not declared:
            print("⚠ kbc-stale-blocker: no kanban.boards[] entry carries a usable "
                  "board_id — every entry was skipped above, so nothing was scanned and "
                  "no citation could resolve into any board.", file=sys.stderr)
        else:
            print(f"⚠ kbc-stale-blocker: all {declared} declared board(s) failed to read "
                  f"— nothing was scanned, and every citation would be UNRESOLVED.",
                  file=sys.stderr)
        return 2

    # Every board is in the corpus BEFORE any citation is resolved: ids are global here
    # and citations cross boards, so resolving as we scan would answer "not in the
    # corpus" for a referent the next board's read was about to supply.
    counts = {"no-blocking-context": 0}
    for label, _ in _EXCLUSIONS:
        counts[label] = 0
    examined = 0
    candidates = 0
    findings: list = []
    unresolved: list = []
    foreign: list = []

    for bid, key, _live, open_cards in scanned:
        for card in open_cards:
            text = f"{card.get('name') or ''}\n{card.get('description') or ''}"
            for line, rid, disp in blocking_citations(text):
                examined += 1
                if disp != "candidate":
                    counts[disp] += 1
                    continue
                candidates += 1
                verdict, detail = corpus.resolve(rid)
                where = (corpus.stage_name.get((corpus.card_board(card, bid),
                                                card.get("workflow_stage_id")))
                         or f"stage {card.get('workflow_stage_id')}")
                row = (card.get("id"), key, where, rid, detail, _quote(line))
                if verdict == "terminal":
                    findings.append(row)
                elif verdict == "out-of-tenant":
                    foreign.append(row)
                elif verdict == "unresolved":
                    unresolved.append(row)

    # From the INDEX, not from a parallel sum over the per-board lists: the sentence says
    # "cards indexed as referents", and the index is `corpus.cards`.
    total_live = len(corpus.cards)
    total_open = sum(len(o) for _b, _k, _l, o in scanned)

    print("")
    for bid, key, live, open_cards in scanned:
        print(f"[STALE-BLOCKER] board {bid} ({key}): {len(live)} live card(s), "
              f"{len(open_cards)} open (scanned)")
    print(f"[STALE-BLOCKER] corpus: {len(corpus.boards_read)} of "
          f"{len(corpus.roster_boards)} declared board(s) read, {total_live} live "
          f"card(s) indexed as referents, {total_open} open card(s) scanned "
          f"(name + description), {examined} citation(s) examined")
    print(f"    no blocking marker before it: {counts['no-blocking-context']}")
    for label, _ in _EXCLUSIONS:
        print(f"    excluded, {label}: {counts[label]}")
    print(f"    asserted as a blocker: {candidates} → {len(findings)} flagged, "
          f"{len(foreign)} out-of-tenant, {len(unresolved)} unresolved referent(s); "
          f"{corpus.gets} referent GET(s) of {_MAX_REFERENT_GETS}")

    if findings:
        print("  ⚑ open card(s) citing a blocker that has since become TERMINAL:")
        for cid, key, where, rid, detail, quote in findings:
            print(f"    card#{cid} ({key}, {where}) cites card#{rid} as a blocker — "
                  f"referent is TERMINAL: {detail}")
            print(f"        {quote}")
    else:
        print("  (none) — no open card asserts a blocker that has become terminal")
    if foreign:
        print("  ⚑ citation(s) naming an id OUTSIDE this roster's boards — a mis-citation, "
              "and its own finding:")
        for cid, key, where, rid, detail, quote in foreign:
            print(f"    card#{cid} ({key}, {where}) cites card#{rid} — OUT-OF-TENANT: "
                  f"{detail}")
            print(f"        {quote}")
    if unresolved:
        print("  ? citation(s) whose referent could NOT be resolved (reported, not "
              "dropped):")
        for cid, key, where, rid, detail, quote in unresolved:
            print(f"    card#{cid} ({key}, {where}) cites card#{rid} — UNRESOLVED: "
                  f"{detail}")
            print(f"        {quote}")
    if corpus.budget_hit:
        print(f"  ⚠ the per-run referent-read budget ({_MAX_REFERENT_GETS}) was HIT — "
              f"at least one citation above is unresolved because this run stopped "
              f"reading, not because the board could not answer.")
    print("  scope: card ids are GLOBAL on this multi-tenant instance, and resolution is "
          "deliberately confined to the DECLARED roster boards — an id resolving "
          "elsewhere is reported OUT-OF-TENANT and never as a blocker, and an id on a "
          "roster board this run could not read is UNRESOLVED, never either. Three "
          "deliberate under-reports, all stated: `waiting`-lane (Shipped to dev) "
          "referents are NOT counted terminal, a citation inside `backticks` is dropped "
          "even inside a genuine blocking sentence, and a line announcing a discharge is "
          "dropped whatever else it says. Comment threads are not scanned at all.")

    errors += corpus.read_errors
    return 2 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
