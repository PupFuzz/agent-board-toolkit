# shellcheck shell=bash
# _bin-set-lib.sh — the ONE definition of "bin/'s public tool names", shared by the two checks
# that need exactly this set. Sourced after _selftest-prelude.sh, alongside it.
#
# WHY THIS IS SHARED AND THE OTHER bin/ ENUMERATIONS ARE NOT. tests/ holds four enumerations of
# bin/ and they do not all want the same answer — measured on card#5339:
#   * no-task-wrapper-selftest.sh   scans `_`-prefixed files ON PURPOSE (the shared lib is
#                                   exactly where a re-introduced write wrapper would hide).
#   * help-output-selftest.sh       skips directories (a directory has no source to grep).
# Those two are correct as they stand and each says so at its own call site; do not fold them in
# here. Only these two callers want this rule, and they want it identically:
#   * readme-bin-coverage-selftest.sh — README's table must document exactly this set.
#   * runtime-check-selftest.sh       — runtime-check's TOOLS array must probe exactly this set.
# The reasons differ (a doc inventory vs. a PATH probe set) and stay stated at each call site;
# the computation is one, so it lives once (card#5389).
#
# THE RULE, on the two axes that separate the four:
#   * `_`-prefixed entries are EXCLUDED, by NAME — the shared lib and the python helpers are
#     implementation, neither documented as tools nor probed on PATH.
#   * entries are NOT filtered by type and NOT filtered by the +x bit. The one `_`-prefixed
#     DIRECTORY (`__pycache__`) is already excluded by the name rule, so a `-type f` filter
#     would buy nothing and would silently drop two real defects instead: a non-`_` directory
#     dropped into bin/, and a tool that lost its +x bit. Both stay in the set and read RED at
#     whichever caller sees them.

# _public_bin_names <dir> — every public tool name in <dir>, C-collated. Globs the directory
# rather than `find`, so the exclusion is the NAME rule above and nothing else.
_public_bin_names() {
    local d="$1" f b
    for f in "$d"/*; do
        [[ -e "$f" ]] || continue
        b="$(basename "$f")"
        case "$b" in _*) continue ;; esac
        printf '%s\n' "$b"
    done | LC_ALL=C sort
}
