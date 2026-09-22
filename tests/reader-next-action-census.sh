#!/usr/bin/env bash
# reader-next-action-census.sh — a CENSUS INSTRUMENT, not a gate. It re-derives the population
# of one defect class across a tree's shipped shell and prints it, bucketed. It asserts nothing
# about that population and is deliberately NOT named `*-selftest.sh`, so
# `ci-matrix-parity-selftest.sh`'s orphan gate (whose population IS `tests/*-selftest.sh`) does
# not claim it, `suite-home-containment`'s `*selftest*` glob does not run it, and it is wired
# into no workflow. Same shape, and for the same reason, as `readback-before-success-census.sh`,
# `single-row-projection-census.sh` and `mirror-pair-census.sh` beside it.
#
# THE DEFECT CLASS (card#10105). **A message that is literally TRUE can still be the wrong
# message**, because it names what the EMITTER observed rather than what the READER must do. The
# discriminator, which is what makes this a class and not a mood: a message belongs to it when it
# is literally true AND a competent reader's most rational next action, taken from that message
# alone, is WRONG. A message that is simply FALSE is an ordinary defect and is NOT in this class.
#
# The cost is not confusion, it is measured retries and wrong fixes. On the card: a promote run
# printed `✓ … moved` off a 2xx while the field never changed (28/28 cards, green run); a
# `ci-read` returning zero workflow runs read as *"CI has not finished"* when the real condition
# was *"this PR is CONFLICTING, so no run will EVER be dispatched"* (0 runs at the conflicted head
# vs 11 at the resolved head, same PR) and cost most of a day; an exit path's own text said
# *"re-running is safe"* — true for the unverified write it was written for, wrong for the
# server-REFUSED move the same path also produces.
#
# ⛔ WHY THIS IS A CENSUS AND NOT A GATE, and it is the card's own ruling rather than a
# convenience. The class is NOT mechanically decidable: "what will a competent reader do next,
# and is that right" is English, and it is a question about a reader, not about a program. The
# card says so outright — *"a check for this is not obvious and should not be hand-waved; the
# honest first step is a REVIEW-TIME question, not a linter"*. What IS mechanically decidable is
# the SHAPE of each site, which is what this file reports: it sorts the population into buckets
# that need no human judgement and prints the remainder — the sites where a human still has to
# read the message against its causes — rather than guessing at them. A gate over this population
# would need a suppression list, and a hand list that cannot red on a new member is card#6645's
# class, i.e. it would mint a second defect one layer up.
#
# ⛔ THE POPULATION WAS THE WHOLE POINT, AND IT DID NOT EXIST. The card carries a numbered list of
# instances — it grew after the card was written, so no figure for it is repeated here; read the
# card — and says of them: *"found by noticing them, not by deriving them — there is no census of
# user-reachable error strings in any of the three repos, and the first real work is deriving
# one, not fixing these four. Treat the list as evidence that the class exists, never as its
# membership."* This file is that derivation. It is also why it fixes NONE of those instances,
# and that is the card's instruction rather than a gap: most of them are not in this repo at
# all, and the two that are have cards of their own (card#9938's read-back report, and the
# rc-3 re-run sentence) — each a message change, i.e. a change to what this tool tells an
# operator, which is an ask-first gate and not something a census may take on itself.
#
# ⚠ THE CARD'S OWN FOUNDING INSTANCE WAS STRUCK, which is the best argument for deriving a
# population rather than collecting one. Instance 1 claimed a parse error named the wrong layer;
# measured, the schema WAS loaded and the payload genuinely WAS invalid JSON, so the message was
# true, precise, and correctly addressed. It survived RE-POINTED at something sharper — the error
# quoted `first 200 of 1214 bytes` and the invalid byte sat near 1100, so the EXCERPT was
# structurally incapable of containing the failure it was printed to explain. Four retries audited
# the region they were shown while the defect sat where the window could not reach. A collected
# list can be wrong about its own members; a derived one can only be wrong about its predicate,
# which is written down below and can be argued with.
#
# ⛔ WHY EVERY SWEEP HERE USES `command grep`. In an interactive Claude Code shell `grep` is a
# shell FUNCTION that execs `ugrep --ignore-files`, which silently honours `.gitignore` and still
# exits 0 — a truncated sweep that looks exactly like a clean result. A census that under-reports
# its own population reproduces the defect it is hired to measure.
#
# ─────────────────────────── THE PREDICATE, STATED ───────────────────────────
#
# UNIT — the EMISSION SITE. A non-comment line in the SHIPPED SHELL of the tree (`bin/` +
# `hooks/`, one level, minus the python shims — the population `_shipped_shell_files` derives
# from CI's own analyser step, so no `find` is hand-copied here) that redirects to stderr. stderr
# is the whole of it: it is the channel an operator and an agent both read a refusal on, and it
# is the one this fleet's tools put every diagnostic through.
#
# Each site carries two derived attributes and is bucketed on them.
#
#   NEXT-ACTION — the message text matches the imperative lexicon in `ACTION_RE` below. This is
#   the attribute that makes a message ABLE to misdirect at all: a message that prescribes
#   nothing cannot prescribe the wrong thing. It is the necessary half of the card's
#   discriminator, never the sufficient one.
#
#   ⛔ THE MESSAGE TEXT IS NOT THE EMISSION LINE'S LITERALS ALONE. A remedy prescribed by
#   several arms is the thing a maintainer HOISTS — this tree spells the result `*_note`, a
#   function that assembles the sentence and returns it, with the emission naming only
#   `$( owner … )`. Reading the caller line alone, those sites prescribe nothing and report
#   INERT, so the census would be blind in exactly the direction that loses findings: the more
#   carefully one remedy has been given ONE owner, the more certainly it would be missed. So
#   the prose of every in-file function called in a command substitution on the emission line
#   is folded into the text, and where that callee PRESCRIBES something its own call count
#   raises this site's CAUSES — the remedy is printed wherever the owner is called. A callee
#   that owns no prose, or owns prose and prescribes nothing, is neither (LEG 6a/6b).
#
#   CAUSES — how many distinct sites can reach this ONE text. An emission inside a function is
#   reached once per call site of that function; an emission at file scope is reached once. This
#   is the attribute that makes a prescribed action LIKELY to be wrong, and it is instance 3's
#   shape exactly: one remedy sentence, written for the cause it was minted on, inherited by
#   every other cause that later routed through the same arm.
#
# THE BUCKETS:
#   MULTI-CAUSE  NEXT-ACTION ∧ CAUSES >= 2. One prescribed action serving two or more conditions.
#                The remedy has to be right for ALL of them, and nothing checks that it is.
#   REVIEW       NEXT-ACTION ∧ CAUSES == 1. The card's review-time question applies, one site at
#                a time. Not a finding — a reading list.
#   INERT        no NEXT-ACTION. Reported in the denominator and nowhere else: it describes a
#                state without prescribing a response, so this class cannot reach it.
#   TRANSPORT    the site's own text is (near) empty once its note owners are folded in — every
#                word it prints came from its CALLER (`die() { echo "$KB_PROG: $*" >&2; exit 2;
#                }`), not from a sibling in the same file. A transport prescribes
#                nothing OF ITS OWN, so counting its callers as "causes served by one message"
#                would be a category error: those callers each supply their own message. It is
#                bucketed and printed rather than SUBTRACTED, for the same reason
#                `readback-before-success-census.sh` refuses to subtract its transport rows — an
#                exemption list is where the next missed member hides, and two rows of known
#                noise are cheaper than one.
#
# ⚠ WHAT THIS PREDICATE STRUCTURALLY CANNOT SEE — stated because a census that reads as total and
# is not is worse than a narrow one, and because the card's own report was read as exhaustive
# when its author had measured four of at least six:
#
#   N1  WHETHER THE PRESCRIBED ACTION IS RIGHT. That is the defect, it is English, and this file
#       can only put the site in front of a reader. A MULTI-CAUSE row is not a finding.
#   N2  A MULTI-LINE MESSAGE'S EARLIER LINES. The unit is the line carrying `>&2`, which in shell
#       is the LAST line of the command; a next-action clause on an earlier line of a `printf`
#       with several arguments, or inside a heredoc, is not read. Bounded and known, not assumed
#       — widen `_emit_text` if that stops being acceptable.
#   N3  CAUSES REACHED THROUGH A VARIABLE. A function invoked as `"$handler"` is not counted as a
#       call site, so its emission can report CAUSES=1 while several conditions reach it.
#   N4  CAUSES IN ANOTHER FILE. The call-site count is per FILE. `bin/_kb-board-lib.sh`'s
#       emissions are reached from every bin that sources it, so their CAUSES is a FLOOR and the
#       real number is larger — which biases this instrument toward under-reporting MULTI-CAUSE,
#       the direction that loses findings. Stated rather than smoothed over.
#   N5  THE EXCERPT SUB-SHAPE — a true message whose attached EVIDENCE cannot contain the cause
#       (the card's re-pointed instance 1, and the sharpest thing on it). It is not an attribute
#       of the emission line: it is a relation between a window's OFFSET and a failure's offset,
#       and the offset is not in the source. This tree's own bounded-excerpt property is owned by
#       `promote-refusal-detail-selftest.sh` §3, which asserts a refusal excerpt is bounded and
#       carries no credential; NEITHER that gate nor this file can say the window is ANCHORED ON
#       THE FAILURE. That remains unmechanised and is named here so a clean run is not read as
#       covering it.
#   N6  THE EMPTY-vs-UNREADABLE SHAPE (the card's instance 4). Already owned, as a real gate with
#       dispositions, by `read-outcome-collapse-selftest.sh` — a READ has three outcomes and that
#       file reds on a shell site collapsing them to two. Not re-derived here; a second
#       divergent implementation of one behaviour is a defect, not a style choice.
#   N7  ANY LANGUAGE BUT SHELL. See the ROOT note below.
#   N8  A REMEDY ASSEMBLED INTO A VARIABLE AT THE EMISSION'S OWN SCOPE. The note-owner inlining
#       above follows a `$( fn … )` into another function; it does not follow `msg="…"; echo
#       "$msg" >&2` in the same one, because inlining the enclosing function would inline every
#       string in it. Measured on this tree rather than assumed: the sites this misses are the
#       `USAGE` / `_bcs_usage` blocks plus two rendered denominators, i.e. usage dumps rather
#       than remedy sentences — the remedies here are all in `*_note` owners, which the
#       inlining does reach. Re-derive it before relying on that (the sweep is in this file's
#       history), because it is a property of today's tree and not of the predicate.
#   N9  ANYTHING PRINTED ON STDOUT, INCLUDING EVERY SUCCESS LINE. The unit is stderr, and a
#       SUCCESS is the sharpest carrier of this class — the card's instance 2 is a `✓ … moved`
#       printed off a 2xx while the field never changed. It is excluded here deliberately and
#       not by oversight: that instance is a report built from the REQUEST rather than from a
#       read of the result, which `readback-before-success-census.sh` beside this file already
#       re-derives as its own population. Widening this unit to every `echo` would re-implement
#       it divergently, which is a defect rather than a style choice. ⚠ The consequence still
#       holds and is what matters: a clean bucket here says NOTHING about success lines.
#
# ─────────────────────────── ROOT, AND WHY IT IS A PARAMETER ───────────────────────────
#
# ⛔ THE CLASS IS DELIBERATELY CROSS-REPO and the card says so: instances span `kanban-board`,
# `agent-webhook-bridge` and `agent-board-toolkit` plus the harness, and *"it is NOT a
# toolkit-only defect and must not be scoped to one repo when it is picked up."* It is filed on
# the toolkit board because the toolkit is this fleet's TOOLING home. So the instrument takes the
# tree to measure as its argument:
#
#     bash tests/reader-next-action-census.sh [<root>]      # default: this checkout
#
# ⚠ AND THE BOUND THAT COMES WITH IT, NAMED RATHER THAN LEFT TO BE DISCOVERED: the predicate is
# SHELL. Pointed at a checkout whose user-reachable messages are PHP, python or JavaScript, it
# reports on that checkout's shell TOOLING and says nothing whatever about the rest — and an
# empty population there is a measurement that never happened, not a clean result. Extending the
# predicate per language is the work that is NOT done here.
#
# ⛔ THE CONTROL ALWAYS RUNS AGAINST THIS FILE'S OWN CHECKOUT, whatever <root> is, and it runs
# FIRST. It anchors on REAL lines of this repo — never on a fixture this file wrote, because a
# control that mints its own sample proves only the sample. If the classifier has stopped
# discriminating, this file exits 2 and prints NOTHING: a population it cannot justify is worse
# than no population, which is the card's own lesson about a four-row table read as exhaustive.
# Each leg addresses its line by an ANCHOR grepped out of the file, never by a line number: a
# number here would rot on the next edit above it and red for the wrong reason.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SELF_ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=tests/_shipped-shell-lib.sh
source "$HERE/_shipped-shell-lib.sh"

ROOT="${1:-$SELF_ROOT}"
[ -d "$ROOT" ] || { echo "reader-next-action-census: no such directory: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"

# THE NEXT-ACTION LEXICON. It is an imperative-verb list and it is BOUNDED — that bound is the
# per-site predicate, the same way `lib-set-derivation-selftest.sh` bounds its keyword half to
# three literal spellings and says so. A next action phrased in words not listed here reports as
# INERT, which under-reports the reviewable remainder; that is the safe direction for a census
# whose output is a reading list. Widen it in the same change as any message that needs it.
#
# ⚠ `[Ss]ee ` and `[Pp]er ` are IN on purpose: "see docs/INSTALL.md §4" is a next action, and a
# pointer at the wrong doc is exactly this class — the card's instance 5 is a true sentence whose
# stale card pointer sent a reader to a CLOSED card, where the most rational next action from a
# true message ("this is released") was to STOP. A pointer misdirects like any other remedy.
ACTION_RE='(re-?run|rerun|re-?try|re-?read|re-?install|re-?vendor|re-?checkout|pass --|pass the|set [$]|export |install |vendor |stamp it|stamp the|fix (it|the|that|these|this)|run it|run `|use `|use the|see `|see docs/|per `|add (it|the)|remove (it|the)|delete (it|the)|declare |create (it|a|the)|correct (it|the)|replace (it|the)|resolve (it|the)|upgrade |check (it|the)|reinstall|retry)'

# THE TRANSPORT FLOOR. A site whose own literal prose is at most this many alphabetic WORDS after
# every expansion and punctuation run is stripped is a TRANSPORT: everything it prints came from
# its caller. Two, not zero — `die() { echo "release-artifacts-check: $*" >&2; }` leaves the
# program name, and `_put_err "$KB_PROG: $*"$'\n'"$USAGE"` leaves nothing at all, so a zero floor
# would call the first of those a message. It is a FLOOR and not a guess: the shortest real
# message in this tree's `bin/` is far longer, and a message that genuinely said three words
# would report as a message, which is the correct answer.
TRANSPORT_MAX_WORDS=2

# _classify <file> — one TAB-separated row per emission site in <file>:
#     <lineno>\t<bucket>\t<scope>\t<causes>
#
# The function-extent walk handles the ONE-LINE DEFINITION explicitly, and that is load-bearing
# rather than tidy: `die() { echo "drift-check: $*" >&2; exit 2; }` carries no `^}` line of its
# own, so a naive `^}` search runs on to the NEXT function's closing brace and swallows it —
# measured on `bin/agent-board-toolkit-drift-check`, where three unrelated file-scope emissions
# were attributed to `die` and reported as MULTI-CAUSE(6) on its caller count. That is a
# plausible-looking wrong answer, which is the one failure shape this file must not have, and
# LEG 3 of the control is pinned to it. The spelling tested is a line ENDING in `; }` or `;}` —
# NOT a bare trailing `}`, since `${x}` ends a great many opening lines — which is the rule
# `_selftest-prelude.sh`'s `_fn_src` already derived for the same hazard (card#8529).
_classify() {
    awk -v action_re="$ACTION_RE" -v tmax="$TRANSPORT_MAX_WORDS" '
    # quoted(L) — every QUOTED segment of a shell line, SPACE-JOINED, which is the only part of
    # it a reader ever sees. Reading the whole LINE instead was the first spelling and it was
    # wrong in both directions: `echo "drift-check: $*" >&2; exit 2;` counts `echo` and `exit` as
    # printed prose (so a transport reads as a message — LEG 3a), and a next-action verb
    # appearing in a FUNCTION NAME or a command would have scored a message that prints no such
    # word. A backslash escape inside the quotes is not part of the prose either.
    #
    # ⛔ THE SPACE BETWEEN SEGMENTS IS LOAD-BEARING, not formatting. Joined bare, the tail of one
    # segment fuses with the head of the next, and the expansion strip below then eats across the
    # seam: `[[ -n "$errbody" ]] && echo "kbcard: server said: $errbody"` became
    # `$errbodykbcard: server said:`, where `$errbodykbcard` is ONE identifier match — so the
    # message lost its first word, dropped to two, and a real message was bucketed TRANSPORT.
    # Measured on that exact line before the separator was added.
    function quoted(L,   i, c, out, q, prev) {
        out = ""; q = ""; prev = ""
        for (i = 1; i <= length(L); i++) {
            c = substr(L, i, 1)
            if (q == "") { if (c == "\"" || c == "'"'"'") { q = c; out = out " " } }
            else if (c == q && prev != "\\") q = ""
            else out = out c
            prev = c
        }
        return out
    }
    { src[NR] = $0 }
    END {
        n = NR
        # --- function extents ---
        nfn = 0
        for (i = 1; i <= n; i++) {
            if (src[i] !~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/) continue
            nfn++
            fname[nfn] = src[i]; sub(/[[:space:]]*\(\).*$/, "", fname[nfn])
            fstart[nfn] = i
            if (src[i] ~ /;[[:space:]]*\}[[:space:]]*$/) { fend[nfn] = i; continue }
            fend[nfn] = n
            for (j = i + 1; j <= n; j++) if (src[j] ~ /^\}/) { fend[nfn] = j; break }
        }
        # --- call sites per function name (non-comment, never the definition line) ---
        # THE UNIT IS A COMMAND POSITION, not an occurrence of the name, and that distinction
        # was measured rather than assumed. Counting every token that matched a definition name
        # reported `main` in `bin/board-session-close` as EIGHT causes: one real `main "$@"`,
        # plus its own `local main`, two `main=` assignments and four `"$main"` reads — so a
        # single-cause emission was bucketed MULTI-CAUSE(8) purely because a local variable
        # shares a name with the function. `swimlane_id` in `bin/kbcard` is the control for the
        # other direction: a real function, really called from eleven arms, which this must
        # still see.
        #
        # Each line is reduced to its command segments — split on `; | & ( ) { } \``, the shell
        # separators after which a COMMAND may begin — and a segment counts only when, after its
        # leading whitespace and any leading shell keyword, it STARTS with a known definition
        # name that is not immediately followed by `=`. A string literal starts with a quote and
        # a variable read starts with `$`, so neither can open a segment; `$(` is protected
        # through the variable-strip so a call inside a command substitution is still seen,
        # which is the direction that loses real callers.
        for (q = 1; q <= nfn; q++) { calls[fname[q]] = 0; isfn[fname[q]] = 1; defline[fstart[q]] = 1 }
        # --- the prose each function OWNS, for the note-owner inlining below ---
        # Every quoted segment inside the function extent, which for a note owner is the whole
        # of the sentence it builds: `_kbc_field_conversion_rerun_note` assembles three
        # alternative remedies into a local and returns it with `printf`, so reading only its
        # `>&2` lines (it has none) or only the caller line (which reads `$( … )`) sees neither.
        for (q = 1; q <= nfn; q++) {
            p = ""
            for (j = fstart[q]; j <= fend[q]; j++) {
                if (src[j] ~ /^[[:space:]]*#/) continue
                p = p " " quoted(src[j])
            }
            fnprose[fname[q]] = p
            # A callee is a NOTE OWNER only if it owns PROSE — the same floor that separates a
            # TRANSPORT from a message, reused rather than a second threshold. Without it every
            # emission that interpolates `$( _kb_prog )` (a helper returning the program name,
            # called from most of the lib) inherited that helper caller count and the whole lib
            # reported MULTI-CAUSE — a plausible-looking wrong answer, from a callee that
            # contributes no remedy at all. LEG 6 of the control is pinned to it.
            s = p
            gsub(/\$\([^)]*\)/, " ", s); gsub(/\$\{[^}]*\}/, " ", s)
            gsub(/\$[A-Za-z_][A-Za-z0-9_]*/, " ", s); gsub(/\\./, " ", s)
            # The lexicon runs BEFORE punctuation is stripped, for the reason the emission path
            # states: several entries are anchored on one. Measured the other way round, the
            # hyphen strip turned `Re-running this exact command` into `re running`, which
            # `re-?run` does not match, so the restamp note read as prescribing nothing.
            fnacts[fname[q]] = (tolower(s) ~ action_re)
            gsub(/[^A-Za-z]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
            fnwords[fname[q]] = (s == "") ? 0 : split(s, sw, " ")
        }
        for (i = 1; i <= n; i++) {
            if (src[i] ~ /^[[:space:]]*#/) continue
            if (i in defline) continue
            C = src[i]
            gsub(/\$\(/, "\001(", C)
            gsub(/\$\{[^}]*\}/, " ", C)
            gsub(/\$[A-Za-z_][A-Za-z0-9_]*/, " ", C)
            gsub(/\001/, "$", C)
            nseg = split(C, seg, /[;|&(){}`]+/)
            for (s = 1; s <= nseg; s++) {
                cmd = seg[s]
                sub(/^[[:space:]]+/, "", cmd)
                while (cmd ~ /^(if|then|elif|else|while|until|do|time|!)[[:space:]]+/)
                    sub(/^[A-Za-z!]+[[:space:]]+/, "", cmd)
                if (!match(cmd, /^[A-Za-z_][A-Za-z0-9_]*/)) continue
                head = substr(cmd, 1, RLENGTH)
                # `=` is an assignment target; `:` is an OBJECT KEY in one of the embedded jq
                # programs these bins carry, where `{` opens a jq object and the key that
                # follows it sits in what a shell lexer reads as command position. Measured:
                # `{swimlane_id: $swim}` and `swimlane_id: (.swimlane_id // null)` each counted
                # as a call of the real `swimlane_id()` function in `bin/kbcard`, inflating a
                # two-cause emission to four. Neither spelling is a call in shell.
                nxt = substr(cmd, RLENGTH + 1, 1)
                if (nxt == "=" || nxt == ":") continue
                if (head in isfn) calls[head]++
            }
        }
        # --- the emission sites ---
        for (i = 1; i <= n; i++) {
            if (src[i] ~ /^[[:space:]]*#/) continue
            if (src[i] !~ />&2/) continue
            L = src[i]

            # the INNERMOST enclosing function: a later definition whose extent contains this
            # line is nested inside an earlier one, so the last match wins.
            scope = "<file-scope>"; causes = 1
            for (q = 1; q <= nfn; q++)
                if (i >= fstart[q] && i <= fend[q]) { scope = fname[q]; causes = calls[fname[q]] + 0 }

            # THE PROSE THIS SITE PRINTS OF ITS OWN. Only the quoted segments, then every `${…}`
            # / `$name` expansion, every `$(…)` substitution and every backslash escape removed:
            # what survives is what a reader reads and this line supplied. N2 bounds it to the
            # `>&2` line.
            T = quoted(L)

            # NOTE-OWNER INLINING. A remedy hoisted into its own function — this tree spells
            # them `*_note` — is printed by an emission that names only `$( owner … )`, so the
            # prose strip below would delete the entire next action and the site would report
            # INERT. That is the WRONG direction to be blind in: hoisting a remedy to ONE owner
            # is what a reader does when several arms prescribe it, so the sites most likely to
            # be MULTI-CAUSE are exactly the ones a caller-line-only read cannot see. The prose
            # of every in-file function called in a command substitution ON this line is folded
            # in, and the callee caller count raises this site CAUSES: that prose is printed
            # wherever the owner is called, so that count is a lower bound on how
            # many conditions the remedy serves. Self-calls are skipped — a recursive helper
            # would otherwise inline itself.
            C2 = L
            while (match(C2, /\$\([[:space:]]*[A-Za-z_][A-Za-z0-9_]*/)) {
                nm = substr(C2, RSTART, RLENGTH)
                sub(/^\$\([[:space:]]*/, "", nm)
                C2 = substr(C2, RSTART + RLENGTH)
                if (!(nm in isfn) || nm == scope || fnwords[nm] <= tmax) continue
                T = T " " fnprose[nm]
                # CAUSES is inherited only from a callee that PRESCRIBES something. A renderer
                # that owns prose and no next action supplies no remedy, so counting its call
                # sites as conditions one remedy serves is the same category error the TRANSPORT
                # bucket exists to avoid: measured, `_kbc_user_render` (five calls, and prose
                # only because a broken quote pair leaks `|| true` into it) was reporting the
                # assign guard as MULTI-CAUSE(5) over a remedy it does not carry.
                if (fnacts[nm] && calls[nm] + 0 > causes) causes = calls[nm] + 0
            }

            gsub(/\$\([^)]*\)/, " ", T)
            # `quoted()` breaks a command substitution that itself contains quotes into
            # fragments, so an UNCLOSED `$( name` survives the strip above and the name then
            # reads as printed prose. It is not: `_kbc_field_rerun_note` contains `rerun`, so
            # the lexicon scored an emission on the callee NAME and a site printing no such
            # word reported REVIEW. Measured on the two `_kbc_field_rerun_note` calls in bin/kbcard.
            gsub(/\$\([[:space:]]*[A-Za-z_]?[A-Za-z0-9_]*/, " ", T)
            gsub(/\$\{[^}]*\}/, " ", T)
            gsub(/\$[A-Za-z_][A-Za-z0-9_]*/, " ", T)
            gsub(/\\./, " ", T)
            # THE LEXICON IS MATCHED ON THE PROSE, not on the line: `tolower` so the lexicon
            # needs no case alternatives, and this is done BEFORE punctuation is stripped
            # because several entries are anchored on one (`see docs/`, `pass --`, "use `").
            acts = (tolower(T) ~ action_re)

            gsub(/[^A-Za-z]+/, " ", T)
            sub(/^ /, "", T); sub(/ $/, "", T)
            words = (T == "") ? 0 : split(T, w, " ")

            if (words <= tmax)    bucket = "TRANSPORT"
            else if (!acts)       bucket = "INERT"
            else if (causes >= 2) bucket = "MULTI-CAUSE"
            else                  bucket = "REVIEW"

            printf "%d\t%s\t%s\t%d\n", i, bucket, scope, causes
        }
    }' "$1"
}

# _ctl_line <file> <anchor-ere> — the line number of the ONE line matching <anchor-ere>. Returns
# 1 (printing nothing) unless it matches EXACTLY once: a control that silently addressed the
# first of several matches would be pinning a line nobody chose.
_ctl_line() {
    local file="$1" anchor="$2" hits
    hits="$(command grep -cE "$anchor" "$file")" || return 1
    [[ "$hits" -eq 1 ]] || return 1
    command grep -nE "$anchor" "$file" | cut -d: -f1
}

# _ctl_row <file> <lineno> — the classified row for one line, as `<bucket>\t<scope>\t<causes>`.
_ctl_row() { _classify "$1" | awk -F'\t' -v L="$2" '$1==L { print $2"\t"$3"\t"$4 }'; }

# --- the control: four legs, every one on a REAL line of this checkout ---
_control() {
    local rc=0 f ln got want

    # LEG 1 — a real MULTI-CAUSE. `bin/kbcard`'s `_kbc_unverified` is the ONE owner of the
    # unverified-write report and prescribes ONE next action — "re-read before acting" — to every
    # arm that routes through it. That is instance 3's shape standing in this tree today. Its
    # caller count is asserted only as `>= 2`, never as a figure: a number here would be a
    # restatement of what the file contains and would red on the next caller added, which is
    # exactly the drift this repo keeps out of its comments.
    f="$SELF_ROOT/bin/kbcard"
    ln="$(_ctl_line "$f" '^[[:space:]]*echo "kbcard: \$verb \$subject: the write was SENT')" || {
        echo "control: LEG 1's anchor (the _kbc_unverified report in bin/kbcard) no longer matches exactly one line — the control cannot address the site it exists to classify" >&2
        return 1
    }
    IFS=$'\t' read -r got_b got_s got_c < <(_ctl_row "$f" "$ln")
    [[ "$got_b" == "MULTI-CAUSE" && "$got_s" == "_kbc_unverified" && "$got_c" -ge 2 ]] || {
        echo "control: LEG 1 (bin/kbcard:$ln, the shared unverified-write report) classified '$got_b/$got_s/$got_c', expected 'MULTI-CAUSE/_kbc_unverified/>=2'" >&2
        rc=1
    }

    # LEG 2 — a real INERT, i.e. the OPPOSITE verdict out of the same classifier. This line
    # describes a state and prescribes nothing, so a lexicon that had started matching everything
    # reds here. Leg 1 alone cannot catch that: it passes under an ACTION_RE that matches the
    # empty string.
    ln="$(_ctl_line "$f" 'refusing to act on a truncated denominator')" || {
        echo "control: LEG 2's anchor (the truncated-denominator refusal in bin/kbcard) no longer matches exactly one line — the control cannot address the site it exists to classify" >&2
        return 1
    }
    got="$(_ctl_row "$f" "$ln" | cut -f1)"; want="INERT"
    [[ "$got" == "$want" ]] || { echo "control: LEG 2 (bin/kbcard:$ln, a refusal prescribing no action) classified '$got', expected '$want'" >&2; rc=1; }

    # LEG 3 — THE ONE-LINE FUNCTION EXTENT, pinned to the wrong answer it produced. `die` in
    # `bin/agent-board-toolkit-drift-check` is defined and closed on ONE line; before the `; }`
    # rule its extent ran to the next function's `^}` and swallowed the file-scope emissions
    # below it, which were then reported as MULTI-CAUSE under `die`'s caller count. Two
    # assertions, because either alone passes under the bug: `die`'s OWN line must classify
    # TRANSPORT, and a file-scope emission BELOW it must not be attributed to `die`.
    f="$SELF_ROOT/bin/agent-board-toolkit-drift-check"
    ln="$(_ctl_line "$f" '^die\(\) \{')" || {
        echo "control: LEG 3's anchor (the one-line die() in bin/agent-board-toolkit-drift-check) no longer matches exactly one line" >&2
        return 1
    }
    got="$(_ctl_row "$f" "$ln" | cut -f1)"; want="TRANSPORT"
    [[ "$got" == "$want" ]] || { echo "control: LEG 3a (the one-line die() at $f:$ln) classified '$got', expected '$want' — a transport is being read as a message" >&2; rc=1; }
    got="$(_classify "$f" | awk -F'\t' -v L="$ln" '$1>L && $3=="die" { print $1; exit }')"
    [[ -z "$got" ]] || {
        echo "control: LEG 3b — $f:$got is BELOW the one-line die() and is attributed to it, so the function-extent walk has stopped honouring the '; }' rule and every emission under a one-line definition is being reported with that definition's caller count" >&2
        rc=1
    }

    # LEG 4 — THE DENOMINATOR PREDICATE ITSELF, which legs 1-3 cannot reach: each is HANDED a
    # file and a line, so nothing above has asserted that the sweep visits anything. This one
    # asserts BOTH halves against a real subject — `hooks/agent-dispatch-card-start`, which
    # carries a stderr emission and is the whole reason the population is `bin/` PLUS `hooks/`:
    #   (a) the file is a MEMBER of `_shipped_shell_files`, so a population narrowed to `bin/`
    #       alone reds here instead of silently shrinking what the printed total is over;
    #   (b) `_classify` actually reports an emission in it, so an emission predicate that had
    #       stopped matching reds too.
    # (a) is the leg the first spelling of this control lacked: it classified the file DIRECTLY,
    # bypassing `_shipped_shell_files`, so replacing the sweep with a `bin/`-only `find` left the
    # whole control green while the denominator lost a file. Measured.
    f="hooks/agent-dispatch-card-start"
    [ -r "$SELF_ROOT/$f" ] || { echo "control: LEG 4's subject ($f) is not readable — it cannot be the denominator witness" >&2; return 1; }
    [[ "$(_shipped_shell_files "$SELF_ROOT" | command grep -Fx "$f")" == "$f" ]] || {
        echo "control: LEG 4a — $f is not in _shipped_shell_files, so the printed denominator is NOT the shipped-shell population it claims" >&2
        rc=1
    }
    [[ -n "$(_classify "$SELF_ROOT/$f")" ]] || {
        echo "control: LEG 4b — $f carries a stderr emission and _classify reports none, so the emission predicate has stopped matching" >&2
        rc=1
    }

    # LEG 5 — THE NOTE-OWNER INLINING, pinned to the site that made it necessary. `bin/kbcard`'s
    # 000 arm prints nothing of its own but `the conversion request FAILED in transport`: the
    # entire next action is built by `_kbc_field_conversion_rerun_note`, which the emission names
    # only inside a command substitution. Read from the caller line alone it prescribes nothing
    # and reported INERT — i.e. the census was structurally blind to the shape the card's own
    # instance 3 has, which is the LAST direction a census of this class may be blind in, since
    # hoisting one remedy to one owner is precisely what a maintainer does when several arms
    # prescribe it. Asserted as the bucket, not as a figure.
    f="$SELF_ROOT/bin/kbcard"
    ln="$(_ctl_line "$f" '^[[:space:]]*000\) echo "kbcard: the conversion request FAILED in transport')" || {
        echo "control: LEG 5's anchor (the 000 arm of the change-type report in bin/kbcard) no longer matches exactly one line" >&2
        return 1
    }
    IFS=$'\t' read -r got_b got_s got_c < <(_ctl_row "$f" "$ln")
    [[ "$got_b" == "MULTI-CAUSE" && "$got_c" -ge 2 ]] || {
        echo "control: LEG 5 (bin/kbcard:$ln, whose whole remedy is built by a note owner it names in a command substitution) classified '$got_b/$got_s/$got_c', expected 'MULTI-CAUSE/…/>=2' — the note-owner inlining is not running, so every remedy this tree hoisted to ONE owner is invisible to the census" >&2
        rc=1
    }

    # LEG 6 — THE TWO GUARDS ON THAT INLINING, each on a real line, because inlining without
    # them produced a plausible-looking wrong answer rather than a loud one.
    # (a) A callee that owns NO prose is not a note owner. `_kb_prog` returns the program name
    #     and is called from most of `bin/_kb-board-lib.sh`; counting its callers reported the
    #     whole lib as MULTI-CAUSE with one shared cause count.
    f="$SELF_ROOT/bin/_kb-board-lib.sh"
    ln="$(_ctl_line "$f" 'refusing to guess which token to send')" || {
        echo "control: LEG 6a's anchor (the duplicate-coord refusal in bin/_kb-board-lib.sh) no longer matches exactly one line" >&2
        return 1
    }
    IFS=$'\t' read -r got_b got_s got_c < <(_ctl_row "$f" "$ln")
    [[ "$got_b" == "REVIEW" && "$got_c" -eq 1 ]] || {
        echo "control: LEG 6a (bin/_kb-board-lib.sh:$ln, which interpolates the program-name helper and nothing else) classified '$got_b/$got_s/$got_c', expected 'REVIEW/…/1' — a callee carrying no prose is being counted as a remedy owner" >&2
        rc=1
    }
    # (b) A callee that owns prose but PRESCRIBES nothing is not a note owner either.
    #     `_kbc_user_render` renders a holder; it supplies no next action, so its five call sites
    #     are not conditions one remedy serves. The assign refusal prescribes `--steal` in its
    #     OWN words, so it stays a one-cause REVIEW row.
    f="$SELF_ROOT/bin/kbcard"
    ln="$(_ctl_line "$f" 'REFUSING to assign — this card is already held by')" || {
        echo "control: LEG 6b's anchor (the assign refusal in bin/kbcard) no longer matches exactly one line" >&2
        return 1
    }
    IFS=$'\t' read -r got_b got_s got_c < <(_ctl_row "$f" "$ln")
    [[ "$got_b" == "REVIEW" && "$got_c" -eq 1 ]] || {
        echo "control: LEG 6b (bin/kbcard:$ln, which interpolates a renderer that prescribes nothing) classified '$got_b/$got_s/$got_c', expected 'REVIEW/…/1' — a callee that owns prose but no next action is being counted as a remedy owner" >&2
        rc=1
    }

    return "$rc"
}

if ! _control; then
    echo "reader-next-action-census: the classifier no longer DISCRIMINATES — refusing to print a population it cannot justify." >&2
    exit 2
fi

# The shipped-shell population is derived from CI's own analyser step; drift between the two is
# reported rather than silently measured around, since a gate measuring a set CI does not is the
# one thing keeping this file honest about its own denominator.
drift="$(_ci_shellcheck_drift "$SELF_ROOT")"
[[ -z "$drift" ]] || {
    echo "reader-next-action-census: ⚠ the shipped-shell derivation has drifted from ci.yml — the denominator below is NOT CI's population:" >&2
    printf '  %s\n' "$drift" >&2
}

echo "reader-next-action-census — root: $ROOT"
echo
printf '%-11s  %-46s  %-34s  %s\n' 'BUCKET' 'SITE' 'SCOPE' 'CAUSES'
n_total=0; n_multi=0; n_review=0; n_inert=0; n_transport=0
while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    while IFS=$'\t' read -r ln bucket scope causes; do
        [[ -n "$ln" ]] || continue
        n_total=$((n_total + 1))
        case "$bucket" in
            MULTI-CAUSE) n_multi=$((n_multi + 1)) ;;
            REVIEW)      n_review=$((n_review + 1)) ;;
            INERT)       n_inert=$((n_inert + 1)) ;;
            TRANSPORT)   n_transport=$((n_transport + 1)) ;;
        esac
        # INERT is counted and not printed: it is the bulk of the population and it is the one
        # bucket this class provably cannot reach, so printing it would bury the remainder.
        [[ "$bucket" == "INERT" ]] && continue
        printf '%-11s  %-46s  %-34s  %s\n' "$bucket" "$rel:$ln" "$scope" "$causes"
    done < <(_classify "$ROOT/$rel")
done < <(_shipped_shell_files "$ROOT")

echo
echo "denominator — stderr emissions in the shipped shell under this root: $n_total"
echo "  MULTI-CAUSE — one prescribed next action, two or more causes:     $n_multi"
echo "  REVIEW      — one prescribed next action, one cause:              $n_review"
echo "  TRANSPORT   — prints only what its caller handed it:              $n_transport"
echo "  INERT       — prescribes no next action (not printed above):      $n_inert"
echo
echo "A MULTI-CAUSE row is NOT a finding. The question this census exists to put in front of a"
echo "reader is the card's own, and it is answered per site, by a human:"
echo
echo "    for this message, what will a competent reader do next — and is that right"
echo "    for EVERY condition that reaches it?"
echo
echo "Read every N-note in this file's header — \`command grep -n '^#   N[0-9]' \$0\` lists them —"
echo "before ruling on any row, and before reading an empty bucket as a clean result."
