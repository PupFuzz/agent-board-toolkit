# shellcheck shell=bash
# _board-walk-sim.sh — a STATEFUL stand-in for the kanban `GET /tasks/search.json` answer, so a
# selftest can change the board BETWEEN the page requests of one whole-board walk (card#10626).
#
# WHY A SIMULATOR AND NOT CANNED PAGES. The defect this reproduces is a card DISPLACED across a
# page boundary by a write that lands mid-walk: a row leaves the set (archive, delete, move to
# another board) or enters it (create, unarchive, restore), and every later row changes page. A
# canned page table can only encode the answer the fixture author already expected, so it cannot
# show that a walk strategy is wrong; this computes each answer from the board's state AT THAT
# REQUEST, the way the server does, and lets the same fixture drive the old walk and the new one.
#
# WHAT IT MODELS, read at the server (TasksController::search + QueryParser, kanban-board dev):
#   * rows ordered by `id` DESCENDING (`$query->orderByDesc('id')`) — so a created card, which
#     takes the next id, lands at the HEAD of page 1;
#   * offset pagination: `limit` rows per page, `page` 1-based, `meta.total` = the size of the
#     whole matching set, `meta.last_page` = max(1, ceil(total / limit)) (Laravel's paginator);
#   * a structured `id<N` token in `q` (`/^id(<=|>=|<|>|=)(\d+)$/`) narrowing the set to ids
#     below N. `%20` separates tokens and `%3C` is `<`, the encoding the walk sends.
# It does not model anything else in `q`: a `board_id=` token is accepted and ignored (one board).
#
# USE — source after _selftest-prelude.sh and _mktmp_scratch, then:
#     bws_init "$TMP/sim" '[1,2,3]' '[]'   # live ids, archived ids
#     bws_after 1 archive 2                # applied after the 1st request is answered
#     bws_after 2 create                   # ← a new card, id = the highest id ever + 1
#     bws_race 1 unarchive 50              # applied BETWEEN the 1st request's count and select
#     bws_respond "<request url>"          # prints the JSON body; state lives in files, so it
#                                          # works from inside a `$(…)` subshell
# Ops: archive <id> | unarchive <id> | create.
# Knobs, read per call: BWS_IGNORE_ID=1 answers as a server that does NOT apply the `id<N` token;
# BWS_ORDER=asc answers in ascending id order. Both exist to show the walk refuses a server that
# breaks the two properties it keys on, rather than reading it as a complete board.
#
# bws_race MODELS THE WITHIN-REQUEST RACE (card#10626 review round 1), distinct from bws_after's
# BETWEEN-request one: the real server runs a COUNT then a separate SELECT with no transaction
# around them (Laravel's paginate()), so a write landing in that gap changes what the SELECT
# sees without changing what the COUNT (and so meta.total / meta.last_page) already reported.
# bws_respond reproduces this literally — it snapshots total/last_page from a COUNT-only read,
# applies any bws_race op queued for this request, THEN reads the data array from the
# (possibly now different) live state, using the frozen total/last_page in the response's meta.

bws_init() { # <dir> <live-json> [archived-json]
    BWS_DIR="$1"
    mkdir -p "$BWS_DIR"
    printf '%s' "$2" > "$BWS_DIR/live.json"
    printf '%s' "${3:-[]}" > "$BWS_DIR/archived.json"
    printf '0' > "$BWS_DIR/calls"
    : > "$BWS_DIR/plan"
    : > "$BWS_DIR/race-plan"
}

bws_after() { # <request-number> <op> [id]
    printf '%s %s %s\n' "$1" "$2" "${3:-}" >> "$BWS_DIR/plan"
}

bws_race() { # <request-number> <op> [id] — applied between THIS request's count and select
    printf '%s %s %s\n' "$1" "$2" "${3:-}" >> "$BWS_DIR/race-plan"
}

bws_calls() { cat "$BWS_DIR/calls"; }

_bws_apply() { # <plan-file> <request-number>
    local plan="$1" n op id live arch
    while read -r n op id; do
        [[ "$n" == "$2" ]] || continue
        live="$(cat "$BWS_DIR/live.json")"; arch="$(cat "$BWS_DIR/archived.json")"
        case "$op" in
            archive)
                jq -c --argjson i "$id" 'map(select(. != $i))' <<<"$live" > "$BWS_DIR/live.json"
                jq -c --argjson i "$id" '. + [$i]' <<<"$arch" > "$BWS_DIR/archived.json" ;;
            unarchive)
                jq -c --argjson i "$id" 'map(select(. != $i))' <<<"$arch" > "$BWS_DIR/archived.json"
                jq -c --argjson i "$id" '. + [$i]' <<<"$live" > "$BWS_DIR/live.json" ;;
            create)
                jq -c --argjson a "$arch" '. + [((. + $a) | max) + 1]' <<<"$live" > "$BWS_DIR/live.json" ;;
            *) echo "_board-walk-sim: unknown op '$op'" >&2; return 1 ;;
        esac
    done < "$plan"
}

bws_respond() { # <url>
    local url="$1" q lim page cur="" tok n total last_page
    q="${url#*q=}"; q="${q%%&*}"
    q="${q//%20/ }"; q="${q//%3C/<}"
    lim="${url#*limit=}"; lim="${lim%%&*}"
    page="${url#*page=}"; page="${page%%&*}"
    for tok in $q; do
        [[ "$tok" =~ ^id\<([0-9]+)$ ]] && cur="${BASH_REMATCH[1]}"
    done
    [[ -n "${BWS_IGNORE_ID:-}" ]] && cur=""
    n=$(( $(cat "$BWS_DIR/calls") + 1 ))
    printf '%s' "$n" > "$BWS_DIR/calls"
    # THE COUNT — read BEFORE any race op for this request, exactly as the server's own COUNT
    # query runs before its SELECT. total/last_page below are FROZEN from this snapshot.
    read -r total last_page < <(jq -r --arg cur "$cur" --argjson lim "$lim" '
        (if $cur == "" then . else map(select(. < ($cur | tonumber))) end) as $s
        | ($s | length) as $t
        | ([1, (($t + $lim - 1) / $lim | floor)] | max) as $lp
        | "\($t) \($lp)"' "$BWS_DIR/live.json")
    _bws_apply "$BWS_DIR/race-plan" "$n"
    # THE SELECT — reads the live state AFTER the race op above, so it can differ from what the
    # frozen total/last_page just declared. This is the literal non-atomicity, not a stand-in
    # for it: a real server's COUNT and SELECT are two requests to the same possibly-changing
    # table, and nothing here makes them agree.
    jq -c --argjson lim "$lim" --argjson page "$page" --arg cur "$cur" --arg order "${BWS_ORDER:-desc}" \
        --argjson total "$total" --argjson last_page "$last_page" '
        (if $cur == "" then . else map(select(. < ($cur | tonumber))) end
         | sort | if $order == "desc" then reverse else . end) as $s
        | { data: [ $s[(($page - 1) * $lim):($page * $lim)][] | {id: .} ],
            meta: { total: $total, per_page: $lim, current_page: $page, last_page: $last_page } }' \
        "$BWS_DIR/live.json"
    _bws_apply "$BWS_DIR/plan" "$n"
}
