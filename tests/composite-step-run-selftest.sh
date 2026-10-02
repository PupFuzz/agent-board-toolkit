#!/usr/bin/env bash
# composite-step-run-selftest.sh — hold `tests/_composite-step-run.sh` to what its header says it
# does: run a composite action's one `run:` step as the runner would, and REFUSE (exit 64) every
# step shape it does not model. `ci.yml`'s expected-failure smoke steps rest on it (card#9022), so
# a refusal that stopped firing would let a failure test pass for a step the runner would run
# differently — an `if:` on the step is the worked case.
#
# Each fixture below is the CLEAN action plus one edit, so a refusal names that edit and nothing
# else, and the clean action running is the control that the refusal is not a blanket one.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/_selftest-prelude.sh"
RUN="$HERE/_composite-step-run.sh"
_need -x "$RUN"
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { echo "python3 PyYAML is required" >&2; exit 2; }
_mktmp_scratch

# _fixture <name> <action.yml text> — one action directory per case.
_fixture() { mkdir -p "$TMP/$1"; printf '%s\n' "$2" > "$TMP/$1/action.yml"; }
RC=0; OUT=""
# _run <dir> [args...] — run the helper, capture rc and merged output.
_run() { RC=0; OUT="$("$RUN" "$TMP/$1" "${@:2}" 2>&1)" || RC=$?; }

CLEAN_HEAD="name: 'f'
description: 'fixture'
inputs:
  word: {description: 'w', required: false, default: 'dflt'}
  code: {description: 'c', required: false, default: '0'}
runs:
  using: 'composite'
  steps:
    - name: the step
      id: s
      shell: bash
      env:
        WORD: \${{ inputs.word }}
        CODE: \${{ inputs.code }}"
CLEAN_RUN='      run: |
        echo "WORD=$WORD PATH_OK=$([ -f "$GITHUB_ACTION_PATH/action.yml" ] && echo yes)"
        exit "$CODE"'

echo "== the clean action runs, as the runner would =="
_fixture clean "$CLEAN_HEAD
$CLEAN_RUN"
_run clean --input word=hello
eq "a given input reaches the env"                 "0" "$RC"
eq "  … with its value, and GITHUB_ACTION_PATH set" "WORD=hello PATH_OK=yes" "$OUT"
_run clean
eq "an omitted input takes its declared default"   "WORD=dflt PATH_OK=yes" "$OUT"
_run clean --input code=3
eq "the step's own exit status is passed through"  "3" "$RC"

# The runner runs `shell: bash` with -e and -o pipefail. A body whose pipeline fails mid-way must
# stop there, which it would not under plain `bash`.
_fixture pipefail "$CLEAN_HEAD
      run: |
        false | true
        echo reached"
_run pipefail
eq "the body runs under -e -o pipefail (a failed pipeline stops it)" "1" "$RC"
eq "  … before the next line"                     "false" "$(has 'reached' "$OUT")"

echo "== every unmodelled shape is REFUSED at exit 64, naming the cause =="
# _refused <label> <fixture> <needle> [args...]
_refused() {
    _run "$2" "${@:4}"
    eq "$1 ⇒ exit 64" "64" "$RC"
    eq "  … naming the cause ($3)" "true" "$(has "$3" "$OUT")"
}

_fixture key-if "$CLEAN_HEAD
      if: \${{ false }}
$CLEAN_RUN"
_refused "an if: on the step"                 key-if "['if']"

_fixture key-wd "$CLEAN_HEAD
      working-directory: elsewhere
$CLEAN_RUN"
_refused "a working-directory: on the step"    key-wd "['working-directory']"

_fixture run-expr "$CLEAN_HEAD
      run: |
        echo \"\${{ inputs.word }}\""
_refused "\${{ in the run: body"               run-expr "contains an Actions expression"

_fixture bool-default "${CLEAN_HEAD/default: \'dflt\'/default: false}
$CLEAN_RUN"
_refused "a non-string input default"          bool-default "non-string default"

_fixture env-expr "$CLEAN_HEAD
        TOKEN: \${{ inputs.word == 'x' && github.token || '' }}
$CLEAN_RUN"
_refused "an env expression it cannot evaluate" env-expr "pass --env TOKEN="
_run env-expr --env TOKEN=
eq "  … and runs once the caller supplies it" "0" "$RC"

_refused "a --input naming no declared input"  clean "is not an input of" --input wrod=x

_fixture two-steps "$CLEAN_HEAD
$CLEAN_RUN
    - shell: bash
      run: echo second"
_refused "more than one step"                  two-steps "exactly one run: step"

_fixture sh-shell "${CLEAN_HEAD/shell: bash/shell: sh}
$CLEAN_RUN"
_refused "a shell other than bash"             sh-shell "only bash is run here"

_summary composite-step-run-selftest
