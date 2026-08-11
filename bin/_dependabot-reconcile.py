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
UNVERIFIABLE (the read itself is not to be trusted) or UNDECIDABLE (the read is fine but the
comparison cannot be made). A silent skip would make the instrument's clean-looking output the
most dangerous thing it produces.

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
import subprocess
import sys
import time

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
    args = entry.get("args") or []
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
    """One `gh api --paginate` alerts query, through four gates.

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
    if state is not None:
        for alert in data:
            got = (alert or {}).get("state")
            if got != state:
                raise InstrumentError(
                    f"gh api (state={state}) returned alert #{(alert or {}).get('number')} "
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


# --------------------------------------------------------------------------- the leg

def read_installed(node_modules: str, name: str):
    """(version, package_json_path, fault) for a top-level install.

    TOP-LEVEL ONLY, on purpose: that is what Node resolves for a bare `require`/`import` at
    the entry point, which is what the running server loaded. Nested copies are not read —
    they make the loaded copy ambiguous, and ambiguity is reported (see nested_copies), not
    resolved by guessing.

    `fault` separates ABSENT from UNREADABLE. They are different findings — a package that is
    not installed is a decidable fact about the deployment, while a package.json that is
    present and will not parse is a read this instrument cannot trust — and collapsing the
    second into "package not in deployment" would be a wrong-but-specific cause, which is
    worse than an honest generic one.
    """
    pkg = os.path.join(node_modules, name, "package.json")
    if not os.path.exists(pkg):
        return None, pkg, "absent"
    try:
        with open(pkg, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception as e:  # noqa: BLE001
        return None, pkg, f"unreadable ({e})"
    version = data.get("version")
    if not isinstance(version, str) or not version:
        return None, pkg, "present but carries no version string"
    return version, pkg, None


def nested_copies(node_modules: str, names) -> dict:
    """{name: [paths]} for every alerted name that also exists under a NESTED node_modules.

    A nested copy means npm resolved two versions of one package, and which one the running
    process loaded depends on the import graph — a fact this instrument cannot read. So the
    presence of ANY nested copy of an alerted name makes that alert UNVERIFIABLE rather than
    letting the top-level read stand in for it.
    """
    found: dict = {}
    wanted = set(names)
    if not os.path.isdir(node_modules):
        return found
    for dirpath, dirnames, _files in os.walk(node_modules):
        if dirpath == node_modules or os.path.basename(dirpath) != "node_modules":
            continue
        for name in wanted:
            candidate = os.path.join(dirpath, name)
            if os.path.exists(candidate):
                found.setdefault(name, []).append(candidate)
    return found


def disposition_for(alert, ctx):
    """The one disposition engine. Ordered fail-closed: a reason the read cannot be trusted
    is reported BEFORE any comparison is attempted on it."""
    dep = alert.get("dependency") or {}
    pkg = dep.get("package") or {}
    ecosystem = pkg.get("ecosystem")
    name = pkg.get("name") or ""
    manifest = dep.get("manifest_path")
    patched = (((alert.get("security_vulnerability") or {})
                .get("first_patched_version") or {}).get("identifier"))

    if ecosystem not in DECLARED_ECOSYSTEMS:
        return (f"UNVERIFIABLE: ecosystem {ecosystem} not in this run's declared leg set "
                f"({', '.join(DECLARED_ECOSYSTEMS)})", None, patched, False)
    if manifest not in DECLARED_MANIFESTS:
        return (f"UNVERIFIABLE: manifest_path {manifest} not in leg's declared scope",
                None, patched, False)

    # From here the alert IS this leg's business, so every row carries the deployed path.
    if ctx["process_error"]:
        return (f"UNVERIFIABLE: {ctx['process_error']}", None, patched, True)
    # The tree itself could not be read. This MUST come before any per-package read, because
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
        # An injected identity REPLACES the file read, so the checks that qualify that read
        # (ambiguous nested copy, mtime vs process start) have nothing to qualify and are
        # skipped rather than run against a file this disposition is not about.
        installed = injected
    else:
        if name in ctx["nested"]:
            return (f"UNVERIFIABLE: nested node_modules copy of {name} present — "
                    f"loaded copy ambiguous", None, patched, True)
        installed, pkg_json, fault = read_installed(ctx["node_modules"], name)
        if fault == "absent":
            return ("UNDECIDABLE: package not in deployment", None, patched, True)
        if fault:
            return (f"UNVERIFIABLE: package.json {fault}", None, patched, True)
        try:
            mtime = os.path.getmtime(pkg_json)
        except OSError as e:
            return (f"UNVERIFIABLE: package.json unreadable after being parsed ({e})",
                    installed, patched, True)
        if mtime > ctx["process_start"]:
            return ("UNVERIFIABLE: package.json modified after the running process started",
                    installed, patched, True)

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
            readable = os.access(os.path.join(install, "node_modules"), os.R_OK | os.X_OK)
            reason = ("detected via ps, not readable under this agent's credentials"
                      if not readable else
                      "detected via ps, outside this run's declared leg (this agent's own "
                      "install only)")
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
            # The OLDEST matching process: a package.json newer than the earliest thing still
            # running from this tree is a file that process did not load.
            process_start = min(p[1] for p in own if p[1] is not None)

        # --- can this run READ the tree it is about? --------------------------------------
        # The same predicate already applied to every FOREIGN install above, now applied to
        # the one install actually read (canon #5 — one primitive, not a sibling of it). Its
        # absence here is what let an unreadable tree render as a decidable fact about the
        # deployment. Absent and unreadable are named apart because they are different
        # operator actions — wait for the reinstall to finish, versus fix the permissions —
        # while sharing one prefix so the row and the coverage entry stay one claim.
        if not os.path.isdir(node_modules):
            nm_error = (f"node_modules not readable at {node_modules} "
                        f"(directory does not exist)")
        elif not os.access(node_modules, os.R_OK | os.X_OK):
            nm_error = (f"node_modules not readable at {node_modules} "
                        f"(not readable under this agent's credentials)")
        else:
            nm_error = None

        # ONE reason string, shared: a row saying UNVERIFIABLE beside a coverage entry saying
        # `covered: true` would be the instrument contradicting itself, and a reader would have
        # no way to tell which half to believe.
        coverage_faults = [f for f in (process_error, nm_error) if f]
        leg["coverage_scope"] = [{
            "machine": scope["machine"],
            "install_path": deployed,
            "covered": not coverage_faults,
            "reason": "; ".join(coverage_faults) or None,
        }] + others

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
        names = sorted({((a.get("dependency") or {}).get("package") or {}).get("name")
                        for a in population
                        if (((a.get("dependency") or {}).get("package") or {})
                            .get("ecosystem")) in DECLARED_ECOSYSTEMS} - {None})
        ctx = {
            "node_modules": node_modules,
            "nested": nested_copies(node_modules, names),
            "injected": opts.injected,
            "process_error": process_error,
            "process_start": process_start,
            "nm_error": nm_error,
        }
        for alert in sorted(population, key=lambda a: a.get("number") or 0):
            dep = alert.get("dependency") or {}
            pkg = dep.get("package") or {}
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


def render(scope, rows, artifact):
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
    print(f"  {denominator['rows_emitted']} row(s) over a population of "
          f"{denominator['alerts_in_population']} alert(s) "
          f"(state={POPULATION_STATE}); {tally or 'no dispositions'}")
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
