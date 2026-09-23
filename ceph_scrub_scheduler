#!/usr/bin/env python3
"""
ceph_scrub_scheduler.py

Scrubs all Ceph PGs from the oldest scrub date to the newest.  Shallow and
deep scrub can be specified.

The OSD flags noscrub and nodeep-scrub are set while the program is running
to prevent ceph scrubbing PGs that have been scrubbed more recently.  The
flags are always restored to their initial state at the program end.

Run on machines that have a working ceph command.

Compatible with python 3.6.8 (Rocky 8)
"""

import argparse
import json
import logging
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Tuple

log = logging.getLogger("ceph_scrub_scheduler")

# PG states that mean "don't try to scrub this right now"
BAD_STATE_MARKERS = ("down", "incomplete", "peering", "stale", "inactive")

# Used to parse ceph json looking for "inf" where a numeric value should be.
_BARE_INF_RE = re.compile(r'(?<=[:,\[\s])(-?inf)(?=[,\]\}\s])')

SOFTWARE_VERSION = "1.0"

class CephError(RuntimeError):
    pass


def run_ceph(args) -> str:
    """Run a ceph CLI command, returning stdout. Raises CephError on failure."""
    cmd = ["ceph"] + args
    log.debug(f"running: {' '.join(cmd)}")
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True,
            timeout=60, )
    except subprocess.TimeoutExpired as e:
        raise CephError(f"command timed out: {cmd}") from e
    if result.returncode != 0:
        raise CephError(f"command failed ({result.returncode}): {cmd}\n{result.stderr.strip()}")
    return result.stdout


def parse_ceph_json(text) -> dict:
    """Parse JSON from a `ceph ... --format json` command"""

    # Ceph emits bare `inf`/`-inf` as a float value, which isn't valid JSON.
    # Only replace it where it's acting as a JSON value (preceded/followed by
    # JSON structural characters), not when it's a substring inside a quoted
    # string such as "infra-pool".
    text = _BARE_INF_RE.sub(
        lambda m: "1.7976931348623157e+308" if m.group(1) == "inf" else "-1.7976931348623157e+308",
        text,
    )

    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        start = max(0, e.pos - 100)
        end = min(len(text), e.pos + 100)
        log.error("Failed to parse ceph JSON output at byte %d: ...%s...", e.pos, text[start:end])
        raise


def parse_stamp(stamp_str) -> datetime:
    """Parse a Ceph timestamp string into an aware datetime for comparison."""
    # Ceph timestamps look like '2025-01-01T12:34:56.789012+0000'
    try:
        return datetime.strptime(stamp_str, "%Y-%m-%dT%H:%M:%S.%f%z")
    except ValueError:
        # Some versions omit microseconds
        return datetime.strptime(stamp_str, "%Y-%m-%dT%H:%M:%S%z")


def get_pg_stats() -> dict:
    """Return a dict of pgid -> {'state', 'last_deep_scrub_stamp'} for all PGs."""
    out = run_ceph(["pg", "dump", "pgs", "--format", "json"])
    data = parse_ceph_json(out)
    # Newer ceph wraps in {"pg_stats": [...]}; older versions return a bare list
    pg_stats = data.get("pg_stats", data) if isinstance(data, dict) else data
    stats = {}
    for pg in pg_stats:
        # print(f"PG: {pg}") # DEBUG
        stats[pg["pgid"]] = {"state": pg.get("state", ""), "last_deep_scrub_stamp": pg.get("last_deep_scrub_stamp"),
            "last_shallow_scrub_stamp": pg.get("last_scrub_stamp"), }  # print(f"stat: {stats[pg['pgid']]}") # DEBUG
    return stats


def is_eligible(state) -> bool:
    return "active" in state and not any(marker in state for marker in BAD_STATE_MARKERS)


def build_queue(pg_stats) -> Tuple[list, list]:
    """Return deep and shallow scrub queues, oldest scrubbed first."""
    eligible = [(pgid, info) for pgid, info in pg_stats.items() if is_eligible(info["state"])]

    skipped = len(pg_stats) - len(eligible)
    if skipped:
        log.warning("%d PG(s) skipped (not active/clean at start): they will be "
                    "retried if/when they become eligible on a later poll", skipped, )

    def sort_key(item, stamp_field):
        stamp = item[1][stamp_field]
        if not stamp:
            return datetime.min.replace(tzinfo=timezone.utc)
        return parse_stamp(stamp)

    deep = sorted(eligible, key=lambda item: sort_key(item, "last_deep_scrub_stamp"))

    shallow = sorted(eligible, key=lambda item: sort_key(item, "last_shallow_scrub_stamp"))

    return ([pgid for pgid, _ in deep], [pgid for pgid, _ in shallow],)


def get_osd_flags() -> dict:
    """Get the current state of the OSD flags noscrub and nodeep-scrub."""
    out = run_ceph(["osd", "dump", "--format", "json"])
    # The json may contain 'inf' as a floating point value which makes json.decode() fail.
    # parse_ceph_json sanitizes the json before trying to decode it.
    data = parse_ceph_json(out)
    flags = set(f for f in data.get("flags", "").split(",") if f)
    return {"noscrub": "noscrub" in flags, "nodeep-scrub": "nodeep-scrub" in flags, }


def set_flags(flags) -> None:
    """Set noscrub/nodeep-scrub to the values passed in."""
    for flag in ("noscrub", "nodeep-scrub"):
        if flags[flag]:
            log.info(f"Setting OSD {flag} flag")
            run_ceph(["osd", "set", flag])
        else:
            log.info(f"Unsetting {flag} flag")
            run_ceph(["osd", "unset", flag])


class ScrubState:
    """Tracks queue/in-flight/completion state for one scrub type (deep or shallow)."""

    def __init__(self, name, command, stamp_field, max_concurrent, interval=None):
        self.name = name                        # "deep" or "shallow" -- used in logging.
        self.command = command                  # ceph pg subcommand: "deep-scrub" or "scrub".
        self.stamp_field = stamp_field          # pg_stats field that changes on completion.
        self.max_concurrent = max_concurrent    # Number of concurrent scrubs to run.
        self.interval = interval                # seconds between cycle restarts, or None.

        self.queue = []                         # Ordered list of PGs to scrub.
        self.in_flight = {}                     # List of PGs currently being scrubbed.
        self.pg_stats = {}                      # snapshot used for eligibility checks on top-up.
        self.completed = 0
        self.total = 0
        self.skipped_pgids = set()              # List of PGs that haven't been scrubbed because of the PG status.

        self.cycle_started = False              # True while a cycle is queued/running.
        self.start_time = 0.0                   # The time the current scrub cyle started.
        self.next_run = 0.0                     # Time the next scrub run should start.  Only if continuous scrubbing.
        self.finished_for_good = False          # True once a non-continuous run has drained


def get_scrub_intervals():
    """Read the cluster-wide default scrub intervals (in seconds) from ceph config."""
    deep_raw = run_ceph(["config", "get", "osd", "osd_deep_scrub_interval"])
    shallow_raw = run_ceph(["config", "get", "osd", "osd_scrub_min_interval"])
    return float(deep_raw.strip()), float(shallow_raw.strip())


def rebuild_state_queue(state, queue_pgids, pg_stats):
    """Reset a ScrubState for a new cycle using a freshly built queue."""
    state.queue = list(queue_pgids)
    state.in_flight = {}
    state.pg_stats = pg_stats
    state.completed = 0
    state.total = len(state.queue)
    state.skipped_pgids = set()
    state.cycle_started = True
    state.start_time = time.time()
    log.info(f"{state.name}: {state.total} PG(s) queued for this cycle")


def issue_scrub_commands(state):
    """Issue scrub commands for queued PGs until max_concurrent is reached."""
    while state.queue and len(state.in_flight) < state.max_concurrent:
        pgid = state.queue.pop(0)
        info = state.pg_stats.get(pgid, {})
        pg_state = info.get("state", "")

        if not is_eligible(pg_state):
            log.warning(f"{state.name}: skipping {pgid}: no longer eligible (state={pg_state})")
            state.skipped_pgids.add(pgid)
            state.completed += 1
            continue

        if "scrubbing" not in pg_state:
            log.info(f"{state.name.capitalize()}: issuing {state.command} for {pgid} "
                     f"({state.completed + len(state.in_flight) + 1}/{state.total} queued so far)")
            run_ceph(["pg", state.command, pgid])
        else:
            log.info(f"{state.name.capitalize()}: PG {pgid} is already scrubbing")

        state.in_flight[pgid] = info.get(state.stamp_field)


def check_progress(state, fresh_stats):
    """Update in-flight PGs for one scrub type against a fresh pg_stats snapshot."""
    for pgid in list(state.in_flight):
        # print(f"Checking {pgid}") # DEBUG
        info = fresh_stats.get(pgid)
        # print(f"Info: {info}") # DEBUG
        if info is None:
            log.warning(f"{state.name}: PG {pgid} no longer reported by ceph pg dump; treating as done")
            del state.in_flight[pgid]
            state.completed += 1
            continue

        old_stamp = state.in_flight[pgid]
        new_stamp = info.get(state.stamp_field)
        # print(f"new_stamp: {new_stamp}, old_stamp: {old_stamp}") # DEBUG
        finished = new_stamp and (old_stamp is None or parse_stamp(new_stamp) > parse_stamp(old_stamp))

        if finished:
            log.info(f"{state.name}: completed {state.command} of {pgid}")
            del state.in_flight[pgid]
            state.completed += 1
        elif not is_eligible(info.get("state", "")):
            log.warning(
                f"{state.name}: PG {pgid} left eligible state mid-scrub (state={info.get('state')})")  # else: still scrubbing, leave it in flight


def args_are_valid(args):
    if not (args.deep or args.shallow):
        log.error("You must specify at least one scrub type to run")
        return False

    #-----------------------------------------------------------------------------------------------------
    # GJH - Disabled this bit to allow both shallow and deep to run at the same time. Deeps scrubbing does
    # shallow scrubbing too so there may be some duplication of shallow scrubbing if both shallow and deep
    # are done at the same time.
    #-----------------------------------------------------------------------------------------------------
    # if args.deep and args.shallow:
    #     log.warning("--shallow ignored as deep scrubbing also includes a shallow scrub.")
    #     args.shallow = False

    if not args.deep and args.max_concurrent_deep:
        log.warning("You have specified max_concurrent_deep without running a deep scrub")
    else:
        if args.deep and not args.max_concurrent_deep:
            # Deep scrub specified so make sure the default max_concurrent_deep value is set.
            args.max_concurrent_deep = 50

    if not args.shallow and args.max_concurrent_shallow:
        log.warning("You have specified max_concurrent_shallow without running a shallow scrub")
    else:
        if args.shallow and not args.max_concurrent_shallow:
            # Shallow scrub specified so make sure the default max_concurrent_shallow value is set.
            args.max_concurrent_shallow = 50

    return True


def show_arg_summary(args):
    scrubs = ""
    concurrent = ""

    if args.deep:
        scrubs += "deep"
        concurrent += f"{args.max_concurrent_deep} deep scrubs"

    if args.shallow:
        if scrubs:
            scrubs += " and "
            concurrent += " and "
        scrubs += "shallow"
        concurrent += f"{args.max_concurrent_shallow} shallow scrubs"

    log.info(f"Command executed: {sys.argv}")
    log.info(f"Scrubs to be done: {scrubs}")
    log.info(f"Concurrent scrubs to be done: {concurrent}")
    log.info("Continuous scrubbing running" if args.continuous else "Single scrub running")


def seconds_to_string(total_seconds):
    """Convert seconds to a string like '1 year, 2 months, 3 days, 4 hours, 5 minutes, 6 seconds'"""
    units = [("year", 365 * 24 * 60 * 60), ("month", 30 * 24 * 60 * 60), ("day", 24 * 60 * 60), ("hour", 60 * 60),
        ("minute", 60), ("second", 1), ]

    parts = []
    seconds_remaining = int(total_seconds)

    show_approx = False
    for unit_name, unit_seconds in units:
        if seconds_remaining >= unit_seconds:
            if unit_name == "year" or unit_name == "month":
                show_approx = True
            value = seconds_remaining // unit_seconds
            seconds_remaining %= unit_seconds

            # Pluralize the unit name
            label = unit_name if value == 1 else unit_name + "s"
            parts.append(f"{value} {label}")

    prefix = "approx. " if show_approx else ""
    return prefix + (", ".join(parts) if parts else "0 seconds")

def main():
    # Used to indicate the OSD scrubbing flags should be set back to their initial state on program exit.
    flags_are_set = False

    # Set an empty value here to stop the IDE complaining.  What is stored in initial_flags only
    # matters when flags_are_set = True.
    initial_flags = {}

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-m", "--max-concurrent-deep", type=int, default=None,
                        help="Max simultaneous deep-scrubs to have in flight (default: 50)")
    parser.add_argument("-n", "--max-concurrent-shallow", type=int, default=None,
                        help="Max simultaneous shallow-scrubs to have in flight (default: 50)")
    parser.add_argument("-p", "--poll-interval", type=int, default=300,
                        help="Seconds between status polls (default: 300 = 5 minutes)")
    parser.add_argument("-c", "--continuous", action="store_true",
                        help="Run forever, restarting deep/shallow cycles independently at ceph's "
                             "configured osd_deep_scrub_interval / osd_scrub_min_interval")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable debug logging")
    parser.add_argument("-d", "--deep", action="store_true", help="Perform deep scrubbing")
    parser.add_argument("-s", "--shallow", action="store_true", help="Perform shallow scrubbing")
    parser.add_argument("-V", "--version", action="version", version="%(prog)s"+SOFTWARE_VERSION)
    args = parser.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)-7s %(message)s", )

    # Make sure the args specified are valid.
    if not args_are_valid(args):
        sys.exit(1)

    # Show a summary of what is going to be done.
    show_arg_summary(args)

    # Signal Handler for SIGINT and SIGTERM
    def cleanup(signum, frame):
        nonlocal flags_are_set
        log.info(
            f"Received signal {signal.Signals(signum).name} ({signum}) from frame {frame.f_code.co_filename}:{frame.f_lineno}")
        if flags_are_set:
            # The flags were altered at the start so put them back to what they were initially.
            log.debug(f"Resetting the OSD noscrubbing flags {initial_flags}")
            set_flags(initial_flags)
            # Ctrl-C can be pressed multiple times.  Clear flags_are_set at the end so it won't keep trying to
            # call set_flags once it has completed.
            flags_are_set = False
        sys.exit(1)

    signal.signal(signal.SIGINT, cleanup)
    signal.signal(signal.SIGTERM, cleanup)

    deep_interval = shallow_interval = None
    if args.continuous:
        log.debug("Reading scrub intervals from ceph config")
        deep_interval, shallow_interval = get_scrub_intervals()
        log.info(
            f"Continuous intervals: deep={deep_interval} seconds ({seconds_to_string(deep_interval)}), shallow={shallow_interval} seconds ({seconds_to_string(shallow_interval)})")

    states = []
    if args.deep:
        states.append(
            ScrubState("deep", "deep-scrub", "last_deep_scrub_stamp", args.max_concurrent_deep, deep_interval))
    if args.shallow:
        states.append(
            ScrubState("shallow", "scrub", "last_shallow_scrub_stamp", args.max_concurrent_shallow, shallow_interval))

    try:
        log.debug("Checking current noscrub/nodeep-scrub flag state")
        initial_flags = get_osd_flags()

        log.info(f"Initial state: noscrub={initial_flags['noscrub']} nodeep-scrub={initial_flags['nodeep-scrub']}")

        log.info("Fetching current PG stats")
        pg_stats = get_pg_stats()
        deep_pgids, shallow_pgids = build_queue(pg_stats)
        for state in states:
            rebuild_state_queue(state, deep_pgids if state.name == "deep" else shallow_pgids, pg_stats)

        if all(state.total == 0 for state in states):
            log.info("There are no PGs to scrub")
            return

        # If one of the OSD scrubbing flags isn't set, set both flags.
        if not initial_flags["noscrub"] or not initial_flags["nodeep-scrub"]:
            # If Ctrl-C is pressed while set_flags() is called it can leave the OSD flags partially set.
            # Set "flags_are_set" before actually updating the flags so that the handler for the
            # Ctrl-C press will put the OSD flags back as they should be.
            flags_are_set = True
            log.debug("Setting the OSD noscrub/nodeep-scrub flags")
            set_flags({"noscrub": True, "nodeep-scrub": True})

        while True:
            active_states = [s for s in states if not s.finished_for_good]

            if not active_states:
                # All the single run scrubs have finished so nothing else to do.
                break


            for state in active_states:
                if not state.queue and not state.in_flight and state.cycle_started:
                    # The queue is empty and no more PGs in flight so reset the scrub state.
                    log.info(f"{state.name.capitalize()}: done: {state.completed}/{state.total} PG(s) scrubbed, "
                             f"{len(state.skipped_pgids)} skipped as ineligible")
                    if state.skipped_pgids:
                        log.warning(f"{state.name.capitalize()}: skipped PGs: {', '.join(sorted(state.skipped_pgids))}")

                    # Work out when it should next restart based on the scrub_interval/deep_scrub_interval.
                    # The next start time is the previous start time + interval.
                    if args.continuous and state.interval is not None:
                        state.next_run = state.start_time + state.interval
                        if state.next_run < time.time():
                            log.warning(f"The {state.name} scrub took longer than {state.interval} seconds, defined in {state.stamp_field}")
                        state.cycle_started = False  # awaiting rebuild at next_run
                    else:
                        # This is just a single run so set the flag to say it has finished.
                        state.finished_for_good = True

            # Have both scrub types finished for good?  This doesn't apply to continuous run scrubbing.
            active_states = [s for s in states if not s.finished_for_good]
            if not active_states:
                break

            waiting_for_restart = [s for s in active_states if not s.cycle_started and time.time() < s.next_run]
            due_for_restart = [s for s in active_states if not s.cycle_started and time.time() >= s.next_run]

            if due_for_restart:
                # One or both scrubs are past the time to restart.  Rebuild the queue of PGs to scrub to start again.
                pg_stats = get_pg_stats()
                deep_pgids, shallow_pgids = build_queue(pg_stats)
                for state in due_for_restart:
                    rebuild_state_queue(state, deep_pgids if state.name == "deep" else shallow_pgids, pg_stats)

            for state in active_states:
                if state.cycle_started:
                    # Run the PG scrub commands.
                    issue_scrub_commands(state)

            runnable = [s for s in active_states if s.cycle_started]

            if not runnable and waiting_for_restart:
                # Nothing in flight, just wait for the next scheduled restart.
                sleep_for = max(min(s.next_run for s in waiting_for_restart) - time.time(), 1)
                log.info(f"All scrub types idle; sleeping {sleep_for:.0f}s until next scheduled restart")
                time.sleep(sleep_for)
                continue

            for state in runnable:
                log.info(f"{state.name.capitalize()} Scrubs: in flight {len(state.in_flight)}, queued {len(state.queue)}, "
                         f"completed {state.completed}/{state.total}")

            log.info(f"Sleeping {args.poll_interval}s before next poll")
            time.sleep(args.poll_interval)

            fresh_stats = get_pg_stats()
            for state in runnable:
                check_progress(state, fresh_stats)

    except CephError as e:
        log.error(f"Ceph command failed: {e}")
        sys.exit(1)
    finally:
        log.debug("Running finally code")
        if flags_are_set:
            # The flags were altered at the start so put them back to what they were initially.
            log.debug(f"Resetting the OSD noscrubbing flags {initial_flags}")
            set_flags(initial_flags)


if __name__ == "__main__":
    main()
