#!/usr/bin/env bash
# _promote-curl-stub.sh — the `curl` stand-in that lets a selftest drive
# `bin/promote-released-cards` END TO END, as a process, network-free: it serves a canned board
# on a GET and records every card move on a PATCH.
#
# WHY IT IS SHARED (card#8421). The stub is not a helper anybody wanted twice — it is the ONLY
# way to exercise this tool, whose whole subject (the correlation, the guards, the reports, the
# exit policy) lives at top level in a standalone that must not be sourced. Two selftests had
# already hand-rolled it, and a third was about to: that is the second-real-caller line, and a
# fourth divergent copy of the fixture that decides what "the board said" means is a defect in
# waiting, not a style choice. This file is the copy; a caller sources it and calls
# `promote_install_curl_stub`.
#
# ⚠ NOT YET THE ONLY COPY. `tests/promote-ref-canon-selftest.sh` keeps its own url-ONLY stub,
# because its `moved()` asserts whole-LINE equality against the logged url — this stub logs
# `<url>\t<body>`, so adopting it there would mean rewriting a deliberately strict assertion
# into a substring one. That is a change to a test's strength, which belongs in its own PR;
# it is recorded in docs/CONSOLIDATION-PLAN.md rather than folded in here.
#
# CONTRACT — the environment the stub reads, all of it optional except the first two:
#   $BOARD_FILE     (required) the file whose contents every GET returns verbatim.
#   $PATCH_LOG      (required) appended `<url>\t<body>` on every `-X PATCH`.
#   $GET_LOG        when set, appended `<url>` on every non-PATCH request. Lets a caller
#                   assert that a refusal happened BEFORE ANY READ — an absence that is
#                   otherwise unobservable, and that `.promote.source` exists to guarantee.
#   $STUB_GET_FAIL  when set, a GET exits 22 — how `curl -fsS` fails on a non-2xx, the only
#                   route to fetch_whole_board's read-failure die. Scoped to the GET so a
#                   caller can still see whether any PATCH was attempted after it.

# promote_install_curl_stub <dir> — write the stub to <dir>/curl and prepend <dir> to $PATH.
promote_install_curl_stub() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/curl" <<'STUB'
#!/usr/bin/env bash
# Minimal curl stand-in for promote-released-cards' api(): a PATCH (via `-X PATCH`) is a card
# move — log "<url>\t<body>" and return success; anything else is the paged board GET.
method=GET; url=""; data=""; want_data=0
for a in "$@"; do
  if [ "$want_data" = 1 ]; then data="$a"; want_data=0; continue; fi
  case "$a" in
    -X) method=_next ;;
    PATCH|GET|POST) [ "$method" = _next ] && method="$a" ;;
    -d) want_data=1 ;;
    http://*|https://*) url="$a" ;;
  esac
done
if [ "$method" = PATCH ]; then
  printf '%s\t%s\n' "$url" "$data" >> "$PATCH_LOG"
  printf '{"data":{"id":0}}'
else
  [ -n "${GET_LOG:-}" ] && printf '%s\n' "$url" >> "$GET_LOG"
  # STUB_GET_FAIL makes the board READ fail the way `curl -fsS` fails on a non-2xx (rc 22),
  # which is the only way to reach fetch_whole_board's read-failure die (card#7500). Scoped to
  # the GET so a test can still observe whether any PATCH was attempted after it.
  [ -n "${STUB_GET_FAIL:-}" ] && exit 22
  cat "$BOARD_FILE"
fi
STUB
    chmod +x "$dir/curl"
    export PATH="$dir:$PATH"
}
