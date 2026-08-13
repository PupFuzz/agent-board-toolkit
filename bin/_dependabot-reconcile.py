#!/usr/bin/env python3
"""_dependabot-reconcile.py — the implementation behind `bin/dependabot-deploy-reconcile`.

The public entry is the bash wrapper beside this file; it owns the usage header (and the help
arm that prints it) and the exit-code contract stated there. This file owns the reads, the
gates and the disposition engine. It is `_`-prefixed for the same reason
`_kbc-archive-eligible.py` is: implementation, not a tool — it is neither documented in
README's table nor probed on PATH, and it carries no help arm of its own, which is why it is
absent from help-output-selftest.sh's registry rather than excluded by it.

ONE LEG ONLY, and the scope object says so rather than the reader inferring it: the
`bridge-npm` installed-tree leg. Its evidence class is `installed-file` — the identity IS the
version of the file Node loads, so no git tag is read and none is claimed. The other legs of
the design (a git-state leg, a kanban-board leg, a toolkit leg) are NOT implemented here; an
alert this leg does not cover gets an explicit UNVERIFIABLE row naming why, never silence.

FAIL-CLOSED IS THE WHOLE POINT. Every path that cannot produce a trustworthy answer emits
UNVERIFIABLE (the read itself is not to be trusted), UNDECIDABLE (the read is fine but the
comparison cannot be made), or PROCESS_PREDATES_TREE (the read is fine and the comparison was
made, about a tree the running process demonstrably never loaded). A silent skip would make the
instrument's clean-looking output the most dangerous thing it produces.

THE READ IS BOUND TO THE RUNNING PROCESS, OR IT IS NOT AN ANSWER. A version read off disk is a
claim about a FILE; the question is about the code a live process LOADED. The two part company
whenever the tree is written after the process started — `npm ci` into the install of a server
nobody restarted is the ordinary way, and it is the shape that produced this leg's own incident:
the tree measured clean while the still-running process carried the vulnerable code it had
loaded before. So every run states the binding explicitly — the running process's start time
against the newest write anywhere in the deployed tree — and a tree written after the process
started is its OWN disposition, `PROCESS_PREDATES_TREE`, never folded into FIXED_CONFIRMED and
never left as a footnote a reader has to go looking for.

THE COMPARATOR IS A DELIBERATE PROXY: `installed >= first_patched_version` under SemVer 2.0
precedence. `vulnerable_version_range` is never parsed — each ecosystem's range grammar differs
with no single published spec, and a range-parsing bug is a silent FALSE NEGATIVE (a genuinely
vulnerable version cleared). The proxy can over-report and never under-reports, which is the
right direction for a triage signal. `>=` and not `>`: an installed version EQUAL to the first
patched version IS fixed, and that boundary is exercised by the selftest through the real
argument path rather than argued about here.
"""
from __future__ import annotations

import json
import os
import re
import socket
import stat
import subprocess
import sys
import time
import traceback

# Host-local by nature, exactly like board-session-close's BSC_WORKTREES: this is the agent
# host's own session instrument, not a vendored per-repo tool. The deployed DIRECTORY is
# resolved (never hardcoded) because it is what the reconciliation is about; the repository the
# alerts come from is not derivable from that directory and is named here.
REPO = "PupFuzz/agent-webhook-bridge"
LEG_ID = "bridge-npm"
DECLARED_ECOSYSTEMS = ("npm",)
DECLARED_MANIFESTS = ("examples/channel-servers/package-lock.json",)

# The MCP entry whose launched .mjs names the deployed channel-server directory.
MCP_SERVER_KEY = "kanbanboard-agent"

# THE VALIDATED STATE ENUM. Every `state=` literal this file sends comes from here, and the
# reason is measured API behaviour, not tidiness: an UNKNOWN state value answers HTTP 200 with
# `[]` (`?state=all` and `?state=bogus` both do), so a typo'd filter yields an empty population
# at a success status — indistinguishable from a real "no alerts in this state" to anything that
# only checks the status code. A MIS-CASED known value is not that case: the filter is applied
# case-insensitively (`?state=Fixed` / `?state=FIXED` return the same set as `?state=fixed`),
# which is why the enum is spelled in the API's own lower case and not relied on for casing.
ALERT_STATES = ("open", "fixed", "dismissed", "auto_dismissed")
POPULATION_STATE = "fixed"

ARTIFACT_DIRS = {False: "dependabot-reconcile", True: "dependabot-reconcile-test"}

# A channel-server process's own .mjs path, as it appears in `ps` output (space-delimited, so
# \S+ is the whole path token). Used for the host-wide coverage statement (F16).
#
# KEYED ON `channel-servers/<file>.mjs` ALONE, deliberately not on the repository name: an
# install cloned into a differently-named directory is still a channel server this run does not
# cover, and requiring the literal `agent-webhook-bridge` in the path made such an install match
# neither the own-install branch nor the others list — it vanished from coverage_scope entirely,
# which is the one outcome a coverage statement must never produce. The install is named by each
# entry's own `install_path`, so nothing is lost by not spelling the repo here.
CHANNEL_SERVER_RE = re.compile(r"\S*channel-servers/\S+\.mjs")

# The official SemVer 2.0 grammar. A version that does not match is NOT ordered against
# anything — it becomes UNDECIDABLE rather than a guess.
_SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)

USAGE = ("usage: dependabot-deploy-reconcile [--test-mode] "
         "[--inject-identity bridge-npm=<pkg>@<version>]...")


class InstrumentError(Exception):
    """A read or a gate failed — the run cannot produce trustworthy dispositions."""


class NotConfigured(Exception):
    """This host runs no deployed channel server, so there is nothing here to reconcile.

    NOT a failure, and the distinction is the whole point: an instrument that cannot tell
    "this host is not part of what I measure" from "I could not read what I measure" reports
    an INSTRUMENT FAILURE at every session close on every host that was never in scope,
    forever — and a warning that always fires is one nobody reads when it means something.
    A config that EXISTS but is broken is the other case and stays an InstrumentError.
    """


class UsageError(Exception):
    """The invocation itself is wrong."""


# --------------------------------------------------------------------------- args

class Options:
    def __init__(self) -> None:
        self.test_mode = False
        self.injected: dict = {}


def parse_args(argv: list) -> Options:
    opts = Options()
    seen_inject = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--test-mode":
            opts.test_mode = True
        elif a == "--inject-identity":
            i += 1
            if i >= len(argv) or not argv[i].strip():
                raise UsageError("--inject-identity needs a value of the form "
                                 "bridge-npm=<pkg>@<version>")
            seen_inject = True
            leg, sep, spec = argv[i].partition("=")
            if not sep or leg != LEG_ID:
                raise UsageError(f"--inject-identity: unknown leg {leg!r} "
                                 f"(this run implements {LEG_ID!r} only)")
            name, at, version = spec.rpartition("@")
            # rpartition, not partition: a scoped package name is itself @-prefixed
            # (`@hono/node-server@2.0.5`), and splitting on the FIRST @ would name the leg's
            # own scope as the package and lose the version.
            if not at or not name or not version:
                raise UsageError(f"--inject-identity: {spec!r} is not <pkg>@<version>")
            opts.injected[name] = version
        else:
            raise UsageError(f"unknown argument {a!r}")
        i += 1
    if seen_inject and not opts.test_mode:
        # A hard error, never a silent override: an injected identity in a REAL run would
        # report a disposition about a version nothing on this host is running.
        raise UsageError("--inject-identity is accepted only alongside --test-mode")
    return opts


# --------------------------------------------------------------------------- reads

def resolve_launch_script() -> str:
    """The .mjs the deployed channel server is LAUNCHED from, per the MCP config.

    Never hardcoded: the launching config is the only thing on this host that states which
    tree the running server was started from, so deriving the path from it is what ties the
    files read below to the process checked for staleness — and matching the process on this
    exact path is what makes "the tree I read" and "the tree it is running" the same claim.

    Two outcomes besides success, and the split between them is deliberate. NO config file at
    all, or a well-formed config that simply does not declare this server, means the host is
    not one this instrument is about — NotConfigured, rc 0. Anything else that stops the
    resolution is BREAKAGE: a config that is present and unreadable or unparseable, one whose
    shape is not what this reader assumes at any level, or an entry that IS declared but
    launches no `.mjs` — something meant to run here and cannot be located, which is exactly
    the state a session-close instrument should shout about — InstrumentError, rc 1.
    """
    path = os.path.join(os.path.expanduser("~"), ".mcp.json")
    try:
        with open(path, encoding="utf-8") as fh:
            cfg = json.load(fh)
    except FileNotFoundError as e:
        raise NotConfigured(f"{path} does not exist") from e
    except Exception as e:  # noqa: BLE001
        # Present but unreadable/unparseable is NOT an unconfigured host — the file exists, so
        # something put it there, and answering "nothing to reconcile" would be a guess about
        # contents nobody read.
        raise InstrumentError(f"could not read {path}: {e}") from e
    # SHAPE BEFORE CONTENT, at each level. A config that PARSES but is not the shape this
    # reader assumes is breakage, and it has to be told apart from an unconfigured host at
    # every level rather than once: a `mcpServers` that is a string makes the `not in` test
    # below a SUBSTRING test that answers True, which would report a malformed config as a
    # host that simply is not configured — the exact swallowing this split exists to prevent.
    # Without these, two of the three shapes died on an AttributeError traceback instead.
    if not isinstance(cfg, dict):
        raise InstrumentError(
            f"{path} parses but is a JSON {type(cfg).__name__}, not an object — a malformed "
            f"config is breakage, not an unconfigured host")
    servers = cfg.get("mcpServers")
    if servers is None:
        raise NotConfigured(f"{path} declares no mcpServers at all")
    if not isinstance(servers, dict):
        raise InstrumentError(
            f"{path}: mcpServers is a JSON {type(servers).__name__}, not an object")
    if MCP_SERVER_KEY not in servers:
        raise NotConfigured(f"{path} declares no mcpServers.{MCP_SERVER_KEY} entry")
    entry = servers.get(MCP_SERVER_KEY)
    if not isinstance(entry, dict):
        raise InstrumentError(
            f"{path}: mcpServers.{MCP_SERVER_KEY} is a JSON {type(entry).__name__}, not an "
            f"object — the entry is declared, so this is a broken config, not an absent one")
    args = entry.get("args")
    if not isinstance(args, list):
        # Shape before content, same as the three checks above: a scalar here would make
        # the membership scan below iterate a string (or die on an int) rather than look
        # for a launch script. An empty list falls through to the broken-config arm.
        args = []
    mjs = next((a for a in args if isinstance(a, str) and a.endswith(".mjs")), None)
    if not mjs:
        raise InstrumentError(
            f"{path}: mcpServers.{MCP_SERVER_KEY} launches no .mjs script — the deployed "
            f"channel-server directory is not derivable")
    return mjs


def _validate_state(state: str) -> str:
    if state not in ALERT_STATES:
        raise InstrumentError(
            f"refusing to query state={state!r}: not one of {', '.join(ALERT_STATES)} — "
            f"this API answers 200 with [] for an unknown value, so an unvalidated literal "
            f"yields an EMPTY population at a success status, indistinguishable from a real "
            f"'no alerts in this state'")
    return state


def gh_alerts(state) -> list:
    """One `gh api --paginate` alerts query, through the gates below.

    NO COUNT OF THEM IS GIVEN, on purpose — this said "four" and was stale the moment the
    element-shape gate was added. The gates are the guard clauses in the body; they are what
    a reader should count, and `tests/dependabot-reconcile-selftest.sh` § "the per-query
    gates" is what asserts each one can fire.

    `state=None` is the deliberate no-filter query (the integrity control's denominator); it
    has no state literal, so the re-assert gate does not apply to it and says so.
    """
    url = f"repos/{REPO}/dependabot/alerts"
    if state is not None:
        url += "?state=" + _validate_state(state)
    label = f"state={state}" if state is not None else "no state filter"
    try:
        proc = subprocess.run(["gh", "api", "--paginate", url],
                              capture_output=True, text=True)
    except Exception as e:  # noqa: BLE001
        raise InstrumentError(f"gh api ({label}) could not be executed: {e}") from e
    if proc.returncode != 0:
        raise InstrumentError(
            f"gh api ({label}) exited {proc.returncode}: "
            f"{(proc.stderr or '').strip()[:400]}")
    try:
        data = json.loads(proc.stdout or "")
    except Exception as e:  # noqa: BLE001
        raise InstrumentError(
            f"gh api ({label}) did not return parseable JSON: {e}") from e
    if not isinstance(data, list):
        raise InstrumentError(
            f"gh api ({label}) returned {type(data).__name__}, not a JSON array — an alert "
            f"population is an array, and anything else is an error document at HTTP 200")
    # GENERIC BOUNDARY VALIDATION, not a defence against a specific observed bug: the filter is
    # an instruction to a remote server, and every disposition below is a claim about the
    # population it returned, so each response is asserted to be the one that was asked for
    # rather than trusted to be. No live shape is known that violates this today — that is the
    # point of a boundary check, and finding out by reading a wrong population would be worse
    # than the loop costs. (`state=None` is the deliberate no-filter query and has nothing to
    # re-assert.)
    # ELEMENT SHAPE, asserted here so nothing downstream has to. An array whose ELEMENTS are
    # not objects satisfies the array check above and then kills the first `.get` it reaches —
    # an AttributeError traceback, no INSTRUMENT FAILURE framing, and no artifact, which
    # contradicts the exit contract's promise that a gate failure still records what was
    # measured. Every consumer of an alert population in this file (the disposition loop, the
    # name set, the sort key) assumes a dict, so this is the one place to establish it.
    #
    # The SCALAR half is here too, for the two fields whose TYPE (not just presence) the code
    # downstream depends on. It buys a NAMED cause where the backstop in main() would other-
    # wise report a generic unhandled-exception line: both are correct, one is actionable.
    # `type(x) is T` rather than isinstance, so a JSON `true` is not accepted as a `number`
    # (bool subclasses int) and rendered as "#True".
    for i, alert in enumerate(data):
        if not isinstance(alert, dict):
            raise InstrumentError(
                f"gh api ({label}) returned a {type(alert).__name__} at index {i}, not an "
                f"alert object — the array is well-formed but its contents are not alerts, "
                f"and nothing here can be disposed from them")
        number = alert.get("number")
        if number is not None and type(number) is not int:
            raise InstrumentError(
                f"gh api ({label}) returned a {type(number).__name__} `number` ({number!r}) "
                f"at index {i}, not an integer — alert numbers are sorted and rendered as "
                f"identities, and a population mixing types cannot even be ordered")
    if state is not None:
        for alert in data:
            got = alert.get("state")
            if got != state:
                raise InstrumentError(
                    f"gh api (state={state}) returned alert #{alert.get('number')} "
                    f"in state {got!r} — the server did not honour the filter, so this "
                    f"population is not the one that was asked for")
    return data


def ps_processes() -> list:
    """[(pid, start_epoch_or_None, args)] for every process on the host.

    `ps` is read WHOLE and filtered in python, so no pattern this tool searches for ever
    enters a command line. That is why `pgrep -f` / `pkill -f` are refused rather than
    escaped: their pattern is matched against the very argv that carries it, so the wrapper
    shell issuing the call self-matches. Here there is no such argv to match.
    """
    env = dict(os.environ, LC_ALL="C")
    try:
        proc = subprocess.run(["ps", "-eo", "pid=,lstart=,args="],
                              capture_output=True, text=True, env=env)
    except Exception as e:  # noqa: BLE001
        raise InstrumentError(f"ps could not be executed: {e}") from e
    if proc.returncode != 0:
        raise InstrumentError(f"ps exited {proc.returncode}: "
                              f"{(proc.stderr or '').strip()[:200]}")
    out = []
    for line in (proc.stdout or "").splitlines():
        parts = line.split()
        if len(parts) < 7:
            continue
        pid = parts[0]
        # `lstart` is a fixed five-field local-time stamp: "Mon Aug 10 23:19:25 2026".
        stamp = " ".join(parts[1:6])
        args = " ".join(parts[6:])
        try:
            start = time.mktime(time.strptime(stamp, "%a %b %d %H:%M:%S %Y"))
        except ValueError:
            start = None
        out.append((pid, start, args))
    return out


# --------------------------------------------------------------------------- semver

def _is_node(args: str) -> bool:
    """Is this command line a node invocation? A path merely MENTIONING the .mjs (an editor,
    a grep, this instrument's own reader) is not the running server."""
    first = args.split(" ", 1)[0]
    return os.path.basename(first) == "node"


def semver_key(version: str):
    """A comparable key under SemVer 2.0 precedence, or None if it is not a semver.

    Build metadata is ignored (spec §10). A release sorts ABOVE any pre-release of the same
    triple (§11.3), numeric pre-release identifiers compare numerically and rank below
    alphanumeric ones, and a longer identifier list wins when every preceding field is equal.
    """
    if not isinstance(version, str):
        return None
    v = version.strip()
    if v[:1] == "v":
        v = v[1:]
    m = _SEMVER_RE.match(v)
    if not m:
        return None
    major, minor, patch, pre = m.group(1), m.group(2), m.group(3), m.group(4)
    if pre is None:
        pre_key = (1,)
    else:
        ids = []
        for part in pre.split("."):
            if part.isdigit():
                ids.append((0, int(part), ""))
            else:
                ids.append((1, 0, part))
        pre_key = (0, tuple(ids))
    return (int(major), int(minor), int(patch), pre_key)


# --------------------------------------------------------------------------- readability

# The one string that means "this directory is genuinely not there" — a DECIDABLE fact about
# the deployment, and the only fault below that a caller may treat as one.
DIR_ABSENT = "directory does not exist"


def package_name_fault(name):
    """None when `name` is a package name this run may turn into a path; else why not.

    POSITIVE VALIDATION — the whole point, and a deliberate break with how this file grew.
    Every earlier version of this check enumerated BAD shapes (not a str, unhashable, a list),
    and each round of review found one more the list did not name: a `None` that `or ""` turned
    into the node_modules ROOT (so the tool read `node_modules/package.json` and reported a
    FIXED_CONFIRMED about a package that does not exist), an empty string doing the same, and a
    `../`-bearing name that read a file OUTSIDE the deployed tree entirely and minted
    FIXED_CONFIRMED from it. A blocklist cannot close that class, because the class is "the
    shapes nobody thought of". So this states what a package name IS and refuses the rest.

    The grammar, which is npm's: exactly ONE path component, or TWO in the `@scope/name` form.
    Each segment must be non-empty and neither `.` nor `..`, and may not contain a separator or
    a NUL. `@` alone is not a scope.

    A fault here is that ALERT's problem, not the run's: it yields an UNVERIFIABLE row naming
    the reason, because one malformed alert must not destroy the other eighteen measurements.
    """
    if name is None:
        return "the alert carries no package name"
    if type(name) is not str:
        return f"the package name is a {type(name).__name__}, not a string"
    if not name:
        return "the package name is empty"
    segments = name.split("/")
    # Per-segment rules FIRST, so the message names the thing that is actually wrong: for
    # "../pkg" the interesting fact is the relative segment, not the component count.
    for segment in segments:
        if not segment or segment in (".", ".."):
            return f"package name {name!r} has an empty or relative path segment"
        if "\\" in segment or "\0" in segment:
            return f"package name {name!r} contains a path separator or NUL byte"
    if len(segments) == 2:
        if not segments[0].startswith("@") or len(segments[0]) < 2:
            return (f"package name {name!r} has two components but the first is not an "
                    f"@scope")
    elif len(segments) != 1:
        return (f"package name {name!r} is neither a single component nor the @scope/name "
                f"form")
    return None


def contained_path(root: str, *parts):
    """`root` joined with `parts`, or None if the result would escape `root`.

    THE BELT, and it is independent of the grammar above on purpose. A grammar is a claim about
    what inputs look like and can be wrong again; this is a claim about what this leg is allowed
    to READ, and it holds whatever the grammar admits. It is what would have caught the `../`
    traversal without anyone having predicted that particular shape — which, given that five
    review rounds each found a shape the previous one had not predicted, is the check worth
    having. Strictly UNDER the root: resolving to the root itself is what an empty name did.
    """
    root_normal = os.path.normpath(root)
    candidate = os.path.normpath(os.path.join(root_normal, *parts))
    if not candidate.startswith(root_normal + os.sep):
        return None
    return candidate


def as_obj(value):
    """`value` when it is a JSON object, else an empty one.

    THE NESTED HALF of the element-shape gate in `gh_alerts`, and it is a separate primitive
    because it closes a separate hole. The `x.get(...) or {}` idiom this replaces guards
    against null and a MISSING key only: a present-but-wrong-typed value is truthy, sails
    through, and kills the next `.get`. Measured, not theorised — `dependency` as a string,
    `dependency.package` as a string, and a package.json parsing to a JSON array each produced
    an AttributeError traceback instead of a named instrument failure.

    Degrading a malformed nested object to an empty one is deliberate and safe HERE precisely
    because every field read out of it feeds a fail-closed disposition: an absent ecosystem or
    version does not become a clean verdict, it becomes UNVERIFIABLE/UNDECIDABLE naming what
    was missing. The shape of a remote payload is not this program's to assume at any depth.
    """
    return value if isinstance(value, dict) else {}


def dir_fault(path: str):
    """None when `path` is a directory this process can list AND traverse; else why not.

    THE ONE READABILITY PREDICATE, and it exists because this file kept re-deriving it. Every
    directory read here goes through it, because the stdlib calls it replaces all report a
    PERMISSION failure as ABSENCE: `os.path.exists` answers False, `os.walk` yields nothing,
    `os.listdir` raises where the caller was not looking. Absence is a decidable fact about a
    deployment; a read that failed is not — collapsing the second into the first is how this
    instrument mints its most confident claims out of things it never saw. Naming them apart
    once, here, is the fix; a third hand-written copy of the check would be the defect.

    R_OK|X_OK, not R_OK alone: LISTING a directory needs read, and stat-ing anything inside it
    needs execute. A directory with read but no execute (mode 444) lists its children happily
    and then answers "not a directory" for every one of them — the quietest form of the same
    lie, invisible to an `onerror` handler because nothing ever raises.

    `os.stat` rather than `os.path.exists`, so a PermissionError on the path's own parent is
    reported as what it is instead of as DIR_ABSENT, which a caller is entitled to trust.
    """
    try:
        st = os.stat(path)
    except FileNotFoundError:
        return DIR_ABSENT
    except OSError as e:
        return f"not stat-able ({e.strerror or e})"
    if not stat.S_ISDIR(st.st_mode):
        return "is not a directory"
    if not os.access(path, os.R_OK | os.X_OK):
        return "not readable under this agent's credentials"
    return None


# --------------------------------------------------------------------------- the leg

def read_installed(node_modules: str, name: str):
    """(version, package_json_path, fault) for a top-level install.

    TOP-LEVEL ONLY, on purpose: that is what Node resolves for a bare `require`/`import` at
    the entry point, which is what the running server loaded. Nested copies are not read —
    they make the loaded copy ambiguous, and ambiguity is reported (see scan_tree), not
    resolved by guessing.

    `fault` separates ABSENT from UNREADABLE. They are different findings — a package that is
    not installed is a decidable fact about the deployment, while a package.json that is
    present and will not parse is a read this instrument cannot trust — and collapsing the
    second into "package not in deployment" would be a wrong-but-specific cause, which is
    worse than an honest generic one.

    That separation used to be FALSE AS WRITTEN, which is why the package DIRECTORY is now
    gated by `dir_fault` before the file is looked for: `os.path.exists` on the package.json
    answers False when the package is missing AND when the directory holding it cannot be
    traversed, so an unreadable install reported "package not in deployment" — the docstring
    above described an intent the code did not implement.
    """
    pkg_dir = contained_path(node_modules, name)
    if pkg_dir is None:
        # The belt. The caller already validated the name's grammar, so reaching this means the
        # grammar and this invariant disagree — and the invariant wins, because it is the one
        # that says what this leg may read.
        return None, os.path.join(node_modules, str(name)), (
            f"package path for {name!r} would resolve outside the deployed tree")
    pkg = os.path.join(pkg_dir, "package.json")
    fault = dir_fault(pkg_dir)
    if fault == DIR_ABSENT:
        return None, pkg, "absent"      # the one decidable answer here
    if fault:
        return None, pkg, f"package directory {fault}"
    if not os.path.exists(pkg):
        # The directory IS traversable (checked above), so this absence is a real one.
        return None, pkg, "absent"
    try:
        with open(pkg, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as e:  # noqa: BLE001
        return None, pkg, f"package.json unreadable ({e})"
    if not isinstance(data, dict):
        return None, pkg, (f"package.json parses to a JSON {type(data).__name__}, not an "
                           f"object")
    version = data.get("version")
    if not isinstance(version, str) or not version:
        return None, pkg, "package.json present but carries no version string"
    return version, pkg, None


def scan_tree(node_modules: str, names):
    """One pass over the deployed tree: ({name: [paths]}, (newest_mtime, path), fault).

    TWO QUESTIONS, ONE TRAVERSAL, and they share it because they need the same thing — every
    directory and every entry under `node_modules`, with the same statement about what could not
    be reached. The second question (when was this tree last written?) would otherwise be a
    second walk with its own fault handling, i.e. a second divergent implementation of the one
    thing this function already does.

    THE NEWEST WRITE is `max(mtime)` over every directory and every entry the scan reaches,
    lstat'd — a symlink's own mtime is when the link was made, which is an install action.
    Directories are included because a package REMOVED leaves no entry behind, only a bumped
    parent. It is what `process_tree_binding` compares the running process's start time against,
    and when `fault` is set it is a FLOOR rather than the maximum — the caller must not read an
    unfaulted "nothing newer" out of a scan that did not finish.

    Question one — nested copies. A nested copy means npm resolved two versions of one package,
    and which one the running process loaded depends on the import graph — a fact this
    instrument cannot read. So the presence of ANY nested copy of an alerted name makes that
    alert UNVERIFIABLE rather than letting the top-level read stand in for it.

    WHICH MAKES AN INCOMPLETE SCAN THE DANGEROUS DIRECTION, and why this returns a fault
    instead of just a dict: "no nested copy found" is what LETS the top-level read stand, so a
    subtree this process could not enter does not degrade the answer — it INVERTS it, turning
    the tool's strongest clean verdict (FIXED_CONFIRMED) out of a directory nobody read.

    NO COUNT OF THE WAYS THAT CAN HAPPEN IS CLAIMED HERE, deliberately. This docstring has
    twice said "both ways are closed" and been wrong the next time somebody looked — first
    when the unreadable LEAF turned up, then when the SYMLINK did. A number in prose is a
    completeness claim nobody re-derives, so the authority is the fixture set instead:
    `tests/dependabot-reconcile-selftest.sh`, the cases under "an unscannable SUBTREE" and
    "a SYMLINKED subtree", each watched red against the mechanism it covers. What is written
    here is only WHY each mechanism is needed, which is what a reader cannot recover from a
    test name:

      * a subtree that cannot be LISTED raises inside `os.walk`, which by default swallows it
        silently (`onerror=None`) — hence the handler;
      * a LEAF directory that can be listed but not TRAVERSED (mode 444) raises nothing at
        all. There is nothing below it for walk to scandir, so `onerror` can never fire for
        it, and a package directory that could not be read reads exactly like one holding no
        nested copy. Only checking the directory itself catches this, which is what the
        per-`dirpath` check below is for.
      * a SYMLINKED directory is never yielded as a `dirpath` at all under the default
        `followlinks=False`, so neither mechanism above ever runs on it — only inspecting
        `dirnames` sees it. Recorded, not followed: following would need its own cycle guard,
        and this scan's contract is to say when it could not see, not to see everything.

    The 444 case with subdirectories sits between the two and is caught by the handler on
    Linux, though for a reason worth writing down rather than relying on silently: `readdir`
    supplies `d_type`, so `entry.is_dir()` answers without a stat, walk tries to descend, and
    the scandir raises. On a filesystem that answers `DT_UNKNOWN` (some network mounts),
    `is_dir()` falls back to a stat that fails, the child is quietly filed as a non-directory,
    and the per-`dirpath` check is again the only thing that sees it. That fallback is not
    reproducible on this host's filesystem and is therefore asserted by the leaf case above
    rather than directly — a stated bound, not a claim of coverage.
    """
    found: dict = {}
    faults: list = []
    newest: list = [None, None]      # [mtime, path] — a list so the closure below can move it
    wanted = set(names)
    root_fault = dir_fault(node_modules)
    if root_fault:
        return found, None, (f"nested-copy scan could not start at {node_modules} "
                             f"({root_fault})")

    def _onerror(err):
        faults.append(f"{getattr(err, 'filename', node_modules)} ({err.strerror or err})")

    def _bump(path, st):
        if newest[0] is None or st.st_mtime > newest[0]:
            newest[0], newest[1] = st.st_mtime, path

    for dirpath, _dirnames, _files in os.walk(node_modules, onerror=_onerror):
        sub_fault = dir_fault(dirpath)
        if sub_fault:
            faults.append(f"{dirpath} ({sub_fault})")
            continue
        try:
            _bump(dirpath, os.stat(dirpath))
        except OSError as e:
            # `dir_fault` just stat'd this successfully, so reaching here means the tree moved
            # under the scan. Recorded rather than ignored: it makes the newest write a floor,
            # which is exactly what `fault` tells the caller.
            faults.append(f"{dirpath} (could not be stat'd: {e.strerror or e})")
            continue
        # POSITIVE CLASSIFICATION OF EVERY ENTRY, and this replaced a `dirnames`-only symlink
        # scan for the reason that keeps recurring: the blocklist missed a shape. A symlink
        # whose TARGET cannot be stat'd (a target under a mode-000 parent) is classified by
        # os.walk's own is_dir() as a FILE — it swallows the OSError — so it never appeared in
        # `dirnames` at all and the symlink scan never saw it. Driven, it minted
        # FIXED_CONFIRMED.
        #
        # THE PROPERTY, stated so it can be checked rather than trusted: every entry is either
        # POSITIVELY CONFIRMED HARMLESS or RECORDED. There is no third bucket, and no shape has
        # to be predicted. Exactly three things are harmless — a plain directory (walk will
        # descend into it and every check here runs again there), a plain regular file (it
        # cannot hide a subtree), and a symlink that resolves to a regular file (the
        # node_modules/.bin case, which likewise cannot hide a subtree). Everything else —
        # symlink to a directory, symlink whose target will not stat, device/socket/FIFO where
        # a directory could have been, or an entry that raises while being classified — is a
        # place a nested copy might be that this run did not look.
        try:
            entries = list(os.scandir(dirpath))
        except OSError as e:
            faults.append(f"{dirpath} (could not be listed: {e.strerror or e})")
            continue
        for entry in entries:
            try:
                # lstat FIRST, and inside the same guard: an entry whose own timestamp cannot be
                # read is an entry this scan cannot date, which is a fault for the same reason
                # an unclassifiable one is — the newest write it reports would be a floor with
                # nothing saying so.
                _bump(entry.path, entry.stat(follow_symlinks=False))
                if entry.is_symlink():
                    try:
                        linked_stat = os.stat(entry.path)      # follows the link
                    except OSError as e:
                        faults.append(f"{entry.path} (symlink whose target cannot be "
                                      f"stat'd: {e.strerror or e})")
                        continue
                    if stat.S_ISREG(linked_stat.st_mode):
                        continue                               # a .bin-style file symlink
                    faults.append(f"{entry.path} (symlinked subtree, not traversed)")
                elif entry.is_dir(follow_symlinks=False):
                    continue                                   # walk descends; rechecked there
                elif entry.is_file(follow_symlinks=False):
                    continue                                   # cannot hide a subtree
                else:
                    faults.append(f"{entry.path} (neither a regular file nor a directory, so "
                                  f"it cannot be confirmed to hide nothing)")
            except OSError as e:
                faults.append(f"{entry.path} (could not be classified or dated: "
                              f"{e.strerror or e})")
        if dirpath == node_modules or os.path.basename(dirpath) != "node_modules":
            continue
        for name in wanted:
            candidate = contained_path(dirpath, name)
            if candidate is not None and os.path.exists(candidate):
                found.setdefault(name, []).append(candidate)
    write = (newest[0], newest[1]) if newest[0] is not None else None
    if faults:
        return found, write, ("nested-copy scan incomplete, so an absent nested copy is not a "
                              "measured absence: " + "; ".join(sorted(set(faults))))
    return found, write, None


# --------------------------------------------------------------------- the running process

# STATED ON EVERY RUN, not buried in a design document, because each one is a divergence this
# binding cannot see and a reader is entitled to know what a BOUND answer does not cover.
BINDING_LIMITS = (
    "mtime is the only evidence — an install replaced with its timestamps preserved "
    "(rsync -a, cp -p, a tar restore) reads as unchanged",
    "the start time comes from `ps lstart`: one-second resolution, parsed as local time, so a "
    "write inside the same second as the start reads as newer (the comparison is strict, which "
    "errs toward reporting divergence)",
    "the binding is a property of the TREE, not of each file: one write anywhere under "
    "node_modules unbinds every row, including packages whose own files did not move",
    "only this host's own configured install is measured — every other channel-server process "
    "detected here is reported UNVERIFIABLE in coverage_scope, never read",
)


def _iso(epoch):
    # `is not None`, not truthiness: an epoch of 0 is a real (if absurd) timestamp, and
    # rendering it as "never measured" would be the instrument lying about its own read.
    if epoch is None:
        return None
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch))


def process_tree_binding(process_start, pids, write, scan_incomplete):
    """(binding, divergence) — is the tree just measured the tree the running process LOADED?

    THE QUESTION THE ON-DISK READ CANNOT ANSWER ABOUT ITSELF. Every version this leg reports is
    read from a file; the claim being made is about a live process. `npm ci` into the install of
    a server nobody restarted breaks the two apart, and the break is silent: the tree measures
    clean while the process keeps serving what it loaded. So the relation is measured and stated
    on every run — including when it holds, because "the binding was checked and holds" and "the
    binding was never checked" are indistinguishable from a report that only speaks up on
    trouble.

    `divergence` is not None only when the answer is a definite NO, which is why an INCOMPLETE
    scan can still produce one: the newest write it found is a floor, and a floor already past
    the process start is a measurement, not a guess. The other direction is not symmetric — a
    floor BELOW the start affirms nothing, so `bound` is None and the tree-level fault the
    incomplete scan already raises is what the rows carry.
    """
    binding = {
        "process_pids": list(pids),
        "process_start": _iso(process_start),
        "start_source": "ps lstart (one-second resolution, local time)",
        "tree_newest_write": _iso(write[0]) if write else None,
        "tree_newest_path": write[1] if write else None,
        "tree_scan_complete": not scan_incomplete,
        "bound": None,
        "statement": None,
        "limitations": list(BINDING_LIMITS),
    }
    if process_start is None:
        binding["statement"] = ("there is no running process for this install to bind the tree "
                                "to")
        return binding, None
    if write is None:
        binding["statement"] = ("the deployed tree could not be read, so it has no measured "
                                "write time to compare")
        return binding, None
    if write[0] > process_start:
        binding["bound"] = False
        divergence = (
            f"the deployed tree was written at {_iso(write[0])}, AFTER the running process "
            f"started at {_iso(process_start)} (newest write: {write[1]}) — the running "
            f"process cannot have loaded the tree measured here")
        binding["statement"] = divergence
        return binding, divergence
    if scan_incomplete:
        binding["statement"] = (
            f"the newest write this run could see is {_iso(write[0])}, but the tree scan "
            f"did not finish, so that is a floor and not the tree's last write")
        return binding, None
    binding["bound"] = True
    binding["statement"] = (
        f"the whole tree predates the running process (newest write {_iso(write[0])} at "
        f"{write[1]}, process started {_iso(process_start)}), so the tree measured below IS "
        f"the tree that process loaded")
    return binding, None


def disposition_for(alert, ctx):
    """The one disposition engine. Ordered fail-closed: a reason the read cannot be trusted
    is reported BEFORE any comparison is attempted on it."""
    dep = as_obj(alert.get("dependency"))
    pkg = as_obj(dep.get("package"))
    ecosystem = pkg.get("ecosystem")
    name = pkg.get("name")
    manifest = dep.get("manifest_path")
    patched = as_obj(as_obj(alert.get("security_vulnerability"))
                     .get("first_patched_version")).get("identifier")

    if ecosystem not in DECLARED_ECOSYSTEMS:
        return (f"UNVERIFIABLE: ecosystem {ecosystem} not in this run's declared leg set "
                f"({', '.join(DECLARED_ECOSYSTEMS)})", None, patched, False)
    if manifest not in DECLARED_MANIFESTS:
        return (f"UNVERIFIABLE: manifest_path {manifest} not in leg's declared scope",
                None, patched, False)

    # From here the alert IS this leg's business, so every row carries the deployed path.
    #
    # The name grammar is checked HERE and not earlier, and that placement is the point: the
    # grammar is NPM'S, and an out-of-leg alert's name is legal in its own ecosystem —
    # composer's `vendor/package` is the live example, and checking first reported a real
    # composer alert as a malformed name instead of as an ecosystem this run does not cover.
    # A name is only required to be path-safe for the leg that actually turns it into a path.
    name_fault = package_name_fault(name)
    if name_fault:
        return (f"UNVERIFIABLE: {name_fault}", None, patched, True)
    if ctx["process_error"]:
        return (f"UNVERIFIABLE: {ctx['process_error']}", None, patched, True)
    # THE RUNNING-PROCESS BINDING, and it is checked BEFORE the tree-level read faults below
    # because it is the only one of them that is a POSITIVE measurement: the tree was written
    # after the process started, which is a fact even from a scan that did not finish. It is
    # also the loudest thing this instrument can find — every version below it would be read
    # out of a tree the running process demonstrably never loaded — so it gets its own word
    # rather than one more UNVERIFIABLE among four, and the row says which write proved it.
    if ctx["tree_diverged"]:
        return (f"PROCESS_PREDATES_TREE: {ctx['tree_diverged']}", None, patched, True)
    # The tree itself could not be read — either its root, or a subtree the nested-copy scan
    # could not enter. This MUST come before any per-package read, because
    # `read_installed` cannot tell "this package is not installed" from "no package in this
    # tree is visible to me": both surface as a missing package.json, and the second one
    # answered as the first is a decidable FACT about the deployment minted out of a read that
    # never happened — precisely the inversion the fail-closed rule exists to prevent. It is
    # reachable in the ordinary way, not a contrived one: `npm ci` removes node_modules before
    # repopulating it, and this instrument runs at session close.
    if ctx["nm_error"]:
        return (f"UNVERIFIABLE: {ctx['nm_error']}", None, patched, True)

    injected = ctx["injected"].get(name)
    if injected is not None:
        # An injected identity REPLACES the file read, so the check that qualifies that read
        # (an ambiguous nested copy) has nothing to qualify and is skipped rather than run
        # against a file this disposition is not about. The binding above is NOT skipped with
        # it: it is a fact about the host, not about the file, and a synthetic version disposed
        # against a tree nothing loaded is exactly as misleading as a real one.
        installed = injected
    else:
        if name in ctx["nested"]:
            return (f"UNVERIFIABLE: nested node_modules copy of {name} present — "
                    f"loaded copy ambiguous", None, patched, True)
        installed, _pkg_json, fault = read_installed(ctx["node_modules"], name)
        if fault == "absent":
            return ("UNDECIDABLE: package not in deployment", None, patched, True)
        if fault:
            # Each fault names its own subject (package.json vs package directory), so this
            # renders one message instead of guessing a prefix that fits only some of them.
            return (f"UNVERIFIABLE: {fault}", None, patched, True)
        # NO PER-FILE mtime CHECK HERE ANY MORE, and its removal is the point rather than a
        # casualty: the tree-level binding above subsumes it (the newest write over the whole
        # tree is >= any file's, so a package.json newer than the process start can no longer
        # reach this line) and answers the question the per-file version could not — a tree
        # rewritten around this package still leaves it loaded from something else.

    if not patched:
        return ("UNDECIDABLE: no first_patched_version", installed, patched, True)
    a, b = semver_key(installed), semver_key(patched)
    if a is None or b is None:
        return ("UNDECIDABLE: non-semver version, cannot order", installed, patched, True)
    return ("FIXED_CONFIRMED" if a >= b else "STILL_EXPOSED", installed, patched, True)


# --------------------------------------------------------------------------- output

_SYMBOL = {"FIXED_CONFIRMED": "✓", "STILL_EXPOSED": "✗"}


def main(argv) -> int:
    try:
        opts = parse_args(argv)
    except UsageError as e:
        print(f"dependabot-deploy-reconcile: {e}", file=sys.stderr)
        print(USAGE, file=sys.stderr)
        return 2

    started = time.time()
    run_ts = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(started))
    scope = {
        "run_ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(started)),
        "machine": socket.gethostname(),
        "repos_covered": [REPO],
        "alert_states_queried": {
            "included": [POPULATION_STATE],
            "excluded": [s for s in ALERT_STATES if s != POPULATION_STATE],
            "counts": {},
            "unfiltered_total": None,
            "sum_integrity": "not measured",
        },
        "legs": [{
            "leg_id": LEG_ID,
            "evidence_class": "installed-file",
            "exact_tag_verified": "n/a",
            "declared_ecosystems": list(DECLARED_ECOSYSTEMS),
            "declared_manifests": list(DECLARED_MANIFESTS),
            "deployed_path": None,
            "coverage_scope": [],
            # Filled by process_tree_binding. Present from the start (rather than added on
            # success) so a run that dies before the binding is measured still SHOWS the field
            # it never filled instead of a reader having to notice an absent key.
            "running_process_binding": None,
        }],
        "denominator": {
            "alerts_in_population": None,
            "rows_emitted": 0,
            "by_disposition": {},
        },
        "injected_identity": (dict(opts.injected) if opts.injected else None),
        "test_mode": opts.test_mode,
        "instrument_failures": [],
    }
    leg = scope["legs"][0]
    rows = []
    deployed = None

    try:
        launch = resolve_launch_script()
        deployed = os.path.dirname(launch)
        leg["deployed_path"] = deployed
        leg["launch_script"] = launch
        node_modules = os.path.join(deployed, "node_modules")

        # --- the host-wide coverage statement (never a silent "one install exists") -------
        procs = ps_processes()
        own = [p for p in procs if launch in p[2] and _is_node(p[2])]
        others = []
        for _pid, _start, args in procs:
            m = CHANNEL_SERVER_RE.search(args)
            if not m or not _is_node(args):
                continue
            if m.group(0) == launch:
                continue
            install = os.path.dirname(m.group(0))
            # Same predicate as the own-install gate below and as both per-package reads —
            # one primitive, four call sites (canon #5). It was hand-written here.
            foreign_fault = dir_fault(os.path.join(install, "node_modules"))
            if foreign_fault is None:
                reason = ("detected via ps, outside this run's declared leg (this agent's "
                          "own install only)")
            elif foreign_fault == DIR_ABSENT:
                # A DIFFERENT FINDING, not a flavour of unreadable: a process still running
                # from a tree that no longer exists is the ordinary shape of a replaced or
                # deleted release clone, and calling it "unreadable" would send a reader to
                # check permissions on a path that is simply gone.
                reason = ("detected via ps, but its node_modules no longer exists — a "
                          "process still running from a deleted or replaced install")
            else:
                reason = (f"detected via ps, and its node_modules is not readable from "
                          f"here ({foreign_fault})")
            entry = {"machine": scope["machine"], "install_path": install,
                     "covered": False, "reason": reason}
            if entry not in others:
                others.append(entry)

        process_error = None
        process_start = None
        if not own:
            process_error = "no running process for this install"
        elif all(p[1] is None for p in own):
            process_error = ("running process found but its start time could not be parsed "
                             "from ps lstart")
        else:
            # The OLDEST matching process: a tree written after the earliest thing still
            # running from it is a tree that process did not load.
            process_start = min(p[1] for p in own if p[1] is not None)

        # --- can this run READ the tree it is about? --------------------------------------
        # The same predicate already applied to every FOREIGN install above, now applied to
        # the one install actually read (canon #5 — one primitive, not a sibling of it). Its
        # absence here is what let an unreadable tree render as a decidable fact about the
        # deployment. Absent and unreadable are named apart because they are different
        # operator actions — wait for the reinstall to finish, versus fix the permissions —
        # while sharing one prefix so the row and the coverage entry stay one claim.
        root_fault = dir_fault(node_modules)
        nm_error = (f"node_modules not readable at {node_modules} ({root_fault})"
                    if root_fault else None)

        # ONE reason string, shared: a row saying UNVERIFIABLE beside a coverage entry saying
        # `covered: true` would be the instrument contradicting itself, and a reader would have
        # no way to tell which half to believe.
        #
        # The entry is built NOW and amended later rather than built once at the end, because
        # the two are in tension: the nested-copy fault is only knowable after the alert names
        # are (it needs them), while an instrument failure in the queries below must not leave
        # the coverage statement missing entirely. So `coverage_faults` accumulates and
        # `own_coverage` is re-derived from it in place.
        coverage_faults = [f for f in (process_error, nm_error) if f]
        own_coverage = {
            "machine": scope["machine"],
            "install_path": deployed,
            "covered": not coverage_faults,
            "reason": "; ".join(coverage_faults) or None,
        }
        leg["coverage_scope"] = [own_coverage] + others

        # --- the alert population, and its measured exclusions --------------------------
        population = gh_alerts(POPULATION_STATE)
        counts = {POPULATION_STATE: len(population)}
        for state in ALERT_STATES:
            if state != POPULATION_STATE:
                counts[state] = len(gh_alerts(state))
        unfiltered = gh_alerts(None)
        states = scope["alert_states_queried"]
        states["counts"] = counts
        states["unfiltered_total"] = len(unfiltered)

        total = sum(counts.values())
        if total != len(unfiltered):
            states["sum_integrity"] = (
                f"FAILED: per-state total {total} != unfiltered total {len(unfiltered)}")
            raise InstrumentError(
                f"state-integrity gate: the four per-state queries total {total} alerts "
                f"while the unfiltered query returns {len(unfiltered)} — one of the five "
                f"reads is incomplete, so no population here can be trusted")
        states["sum_integrity"] = "ok"

        scope["denominator"]["alerts_in_population"] = len(population)
        if not population:
            if unfiltered:
                raise InstrumentError(
                    f"state={POPULATION_STATE} returned 0 alerts while the unfiltered query "
                    f"returned {len(unfiltered)} — the filter, not the repository, produced "
                    f"the empty population")
            # A genuinely empty repository. Said out loud rather than rendered as a clean run
            # over nothing (canon #9: an empty result is a measurement that never happened
            # until it has been shown to be a real one).
            states["sum_integrity"] = (
                states["sum_integrity"] + " (the unfiltered query confirms the repository "
                "genuinely has zero alerts in every state)")

        # --- dispositions ---------------------------------------------------------------
        # Only names that PASSED validation may be joined into a path by the nested-copy
        # scan; an unvalidated one would escape the tree there just as it did in the
        # per-package read.
        names = sorted({n for n in (
            as_obj(as_obj(a.get("dependency")).get("package")).get("name")
            for a in population
            if as_obj(as_obj(a.get("dependency")).get("package"))
            .get("ecosystem") in DECLARED_ECOSYSTEMS)
            if package_name_fault(n) is None})
        nested, tree_write, nested_fault = scan_tree(node_modules, names)
        # THE BINDING, measured before a single version is compared and recorded whichever way
        # it comes out — a report that only mentions the process when something is wrong cannot
        # be told apart from one that never looked.
        binding, tree_diverged = process_tree_binding(
            process_start, [p[0] for p in own], tree_write, bool(nested_fault))
        leg["running_process_binding"] = binding
        if tree_diverged:
            # Into the coverage statement as well as the rows: an install whose running process
            # never loaded the tree that was read is not an install this run covered, and the
            # two halves of one claim must not disagree.
            coverage_faults.append(tree_diverged)
            own_coverage["covered"] = False
            own_coverage["reason"] = "; ".join(coverage_faults)
        if nested_fault:
            # A subtree this run could not enter is a TREE-LEVEL fault, exactly like an
            # unreadable node_modules root, and is promoted to one: "no nested copy here" is
            # what lets the top-level read stand, so an unscanned subtree would otherwise
            # upgrade every alert to FIXED_CONFIRMED. Same value into the rows and into the
            # coverage entry, so the two cannot disagree.
            coverage_faults.append(nested_fault)
            own_coverage["covered"] = False
            own_coverage["reason"] = "; ".join(coverage_faults)
        ctx = {
            "node_modules": node_modules,
            "nested": nested,
            "injected": opts.injected,
            "process_error": process_error,
            "tree_diverged": tree_diverged,
            "nm_error": nm_error or nested_fault,
        }
        for alert in sorted(population, key=lambda a: a.get("number") or 0):
            dep = as_obj(alert.get("dependency"))
            pkg = as_obj(dep.get("package"))
            disposition, installed, patched, in_leg = disposition_for(alert, ctx)
            rows.append({
                "alert_number": alert.get("number"),
                "repo": REPO,
                "ecosystem": pkg.get("ecosystem"),
                "package": pkg.get("name"),
                "manifest_path": dep.get("manifest_path"),
                "scope": dep.get("scope"),
                "installed_version": installed,
                "first_patched_version": patched,
                "disposition": disposition,
                "deployed_path": deployed if in_leg else None,
                "checked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            })
    except NotConfigured as e:
        # ONE LINE, no scope object, NO ARTIFACT, rc 0. An artifact is a record of a
        # measurement, and nothing was measured here; writing one per session close on a host
        # that runs no channel server would grow an evidence trail of non-events.
        print(f"— not configured on this host ({e}) — no deployed channel server to "
              f"reconcile; nothing was measured and no artifact was written")
        return 0
    except InstrumentError as e:
        scope["instrument_failures"].append(str(e))
    except Exception as e:  # noqa: BLE001
        # THE BACKSTOP, and it is what makes every per-site type check defence-in-depth rather
        # than the only wall. Three wrong-typed scalars in an alert payload (a `number` that
        # mixes int and str so the sort dies, an unhashable `name`, a non-string `name` reaching
        # os.path.join) each escaped as a raw traceback: rc 1 by accident of the interpreter,
        # NO artifact at all, and no INSTRUMENT FAILURE framing — so the one thing the exit
        # contract promises for a failed run, that the artifact still records what was measured,
        # was false exactly when it mattered. Guarding those three sites individually would have
        # left the fourth to be found the same way. Anything unexpected now lands here, keeps
        # whatever was measured, and is reported in the instrument's own vocabulary.
        #
        # Deliberately AFTER the two handlers above, so NotConfigured's rc-0 skip and
        # InstrumentError's named causes keep their own paths; this only catches what neither
        # anticipated. It is stated as a defect in the instrument, never as a finding about the
        # deployment — a reader must not mistake a bug here for exposure out there.
        scope["unhandled_traceback"] = traceback.format_exc()
        scope["instrument_failures"].append(
            f"UNHANDLED {type(e).__name__}: {e} — this is a DEFECT IN THIS INSTRUMENT, not a "
            f"finding about the deployment. The rows and scope recorded here are whatever had "
            f"been measured when it fired; the traceback is in the artifact under "
            f"scope.unhandled_traceback")

    scope["denominator"]["rows_emitted"] = len(rows)
    by_disposition: dict = {}
    for row in rows:
        key = row["disposition"].split(":", 1)[0]
        by_disposition[key] = by_disposition.get(key, 0) + 1
    scope["denominator"]["by_disposition"] = by_disposition

    artifact = write_artifact(scope, rows, run_ts, opts.test_mode)
    render(scope, rows, artifact)
    return 1 if scope["instrument_failures"] else 0


def write_artifact(scope, rows, run_ts, test_mode):
    """Write the JSON artifact; return its path, or None with the failure recorded in scope.

    Test-mode runs write to their OWN directory. Mixing a synthetic run into the real
    artifact directory would leave an injected identity sitting in the evidence trail that a
    later reader has no way to tell from a measurement.
    """
    base = os.path.join(os.path.expanduser("~"), ".cache", "coord",
                        ARTIFACT_DIRS[bool(test_mode)])
    path = os.path.join(base, f"{REPO.split('/')[-1]}-{run_ts}.json")
    try:
        os.makedirs(base, exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({"scope": scope, "rows": rows}, fh, indent=2, sort_keys=False)
            fh.write("\n")
    except OSError as e:
        scope["instrument_failures"].append(f"could not write the JSON artifact {path}: {e}")
        return None
    return path


def render_binding(leg):
    """The running-process binding and the installs this run did NOT measure, on stdout.

    Both already live in the scope object, which is printed below — and that is exactly why
    they are printed HERE too. A statement a reader has to find inside a hundred-line JSON dump
    is one nobody reads on the day it matters, and these two are what qualify every row above:
    which process the versions are claimed about, and which running channel servers on this
    host were never looked at.
    """
    binding = leg.get("running_process_binding")
    if binding:
        state = {True: "BOUND", False: "NOT BOUND", None: "NOT ESTABLISHED"}[binding["bound"]]
        symbol = {True: "✓", False: "✗", None: "⚠"}[binding["bound"]]
        print(f"{symbol} running-process binding — {state}: {binding['statement']}")
        # `join`, not the list itself: a python repr (`['2004897']`) in an operator-facing
        # report is the implementation leaking into the one surface that is read by eye.
        print(f"    process: {', '.join(binding['process_pids']) or 'none'} started "
              f"{binding['process_start'] or '?'} ({binding['start_source']}); "
              f"newest tree write {binding['tree_newest_write'] or '?'} at "
              f"{binding['tree_newest_path'] or '?'}"
              f"{'' if binding['tree_scan_complete'] else ' (SCAN INCOMPLETE — a floor)'}")
        for limit in binding["limitations"]:
            print(f"    limitation: {limit}")
    # The out-of-leg installs are the declared-scope half of the same honesty: detected, named,
    # and never measured. Selected by NOT being the install this leg read — never by list
    # position, which would relabel this agent's own install as somebody else's the first time
    # the entries are built in a different order.
    for entry in leg.get("coverage_scope", []):
        if entry.get("install_path") != leg.get("deployed_path") and not entry.get("covered"):
            print(f"⚠ other channel-server install {entry['install_path']} — UNVERIFIABLE: "
                  f"{entry['reason']}")


def render(scope, rows, artifact):
    for leg in scope["legs"]:
        render_binding(leg)
    for row in rows:
        disposition = row["disposition"]
        symbol = _SYMBOL.get(disposition, "⚠")
        # No "installed ?" placeholder: a row this leg never read a version for must not
        # render a field suggesting it looked and found nothing.
        if row["installed_version"]:
            versions = (f"  installed {row['installed_version']} vs patched "
                        f"{row['first_patched_version'] or '?'}")
        elif row["first_patched_version"]:
            versions = f"  patched {row['first_patched_version']}"
        else:
            versions = ""
        print(f"{symbol} #{row['alert_number']} {row['ecosystem']} {row['package']}"
              f"{versions}  [scope: {row['scope']}]  {disposition}")
    denominator = scope["denominator"]
    tally = ", ".join(f"{k}={v}" for k, v in sorted(denominator["by_disposition"].items()))
    # `alerts_in_population` is None when the run died before the population was measured, and
    # "a population of None alert(s)" reads as a number nobody can act on. An unmeasured
    # denominator is said out loud instead (canon #9).
    measured = denominator["alerts_in_population"]
    population_phrase = (f"a population of {measured} alert(s) (state={POPULATION_STATE})"
                         if measured is not None else
                         "a population that was never measured")
    print(f"  {denominator['rows_emitted']} row(s) over {population_phrase}; "
          f"{tally or 'no dispositions'}")
    print("  scope object:")
    for line in json.dumps(scope, indent=2, sort_keys=False).splitlines():
        print(f"    {line}")
    if artifact:
        print(f"  artifact: {artifact}")
    for failure in scope["instrument_failures"]:
        print(f"⚠ dependabot-deploy-reconcile: INSTRUMENT FAILURE — {failure}",
              file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
