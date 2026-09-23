# ceph-utils

Assorted BASH and Python command line scripts for administering a [Ceph](https://ceph.io/) storage cluster — built to cut down on repetitive typing and to pull information from multiple sources with a single command.

Maintained by [Gerard Hand](https://github.com/lancs-gridpp).

## Contents

- [Available Scripts](#available-scripts)
  - [Admin](#admin)
  - [Scrubbing](#scrubbing)
  - [CephFS](#cephfs)
  - [Misc](#misc)
  - [Known Bug Workarounds](#known-bug-workarounds)
- [Installation](#installation)
- [Contributing](#contributing)

## Available Scripts

### Admin

| Script | Description |
|---|---|
| `backfilling` | Set/unset the OSD backfilling flag, optionally muting the `OSDMAP_FLAGS` health warning. |
| `bottleneck` | Analyse a set of OSD numbers to find what they have in common. |
| `cluster_dump.sh` | Export cluster maps to files. Usage: `cluster_dump.sh [-h] [-c <name>] <out options> [<prefix>]` |
| `endmaint` | Take a host out of maintenance mode. Usage: `endmaint <hostname>` |
| `findosd` | Find the host running a given OSD and report drive info (make, serial number, etc.). Usage: `findosd <osd_id>` |
| `ok2stop` | Check whether it's safe to stop services on a host, or stop a specific OSD. |
| `lessjq` | Pipe formatted JSON into `less` for easier reading. |
| `restartosd` | Safely restart a given OSD via Ceph orchestration, verifying it comes back up. |
| `scrubbing` | Set/unset the OSD scrubbing flags, optionally muting the `OSDMAP_FLAGS` health warning. |
| `startmaint` | Put a host into maintenance mode. Usage: `startmaint <hostname>` |
| `starttmux` | Start a `tmux` session with a predefined set of windows. |
| `startceph` | Bring the cluster back into a working state. Usage: `startceph` |
| `stopceph` | Stop the CephFS filesystem and put the cluster into a "down" state. Usage: `stopceph` |

### Scrubbing

| Script | Description                                                                                               |
|---|-----------------------------------------------------------------------------------------------------------|
| `activescrubs` | Show PGs currently scrubbing, with periodic updates.                                                      |
| `ceph_scrub_sheculer` | Disable ceph PG scrub scheduling and manually scrub PGs starting with PGs with the oldest scrubbing dates | 
| `scrubinfo` | Show PG scrubbing information.                                                                            |
| `scrubintervals` | Show the current scrubbing configuration settings.                                                        |

### CephFS

| Script | Description |
|---|---|
| `cephfs_mounts` | Look for CephFS clients with failed mounts. |
| `clientlist` | Generate a list of CephFS clients. |
| `clientload` | Show the load for each CephFS client. |
| `clienttop` | Show CephFS clients ordered by average load, refreshing automatically. |

### Misc

| Script | Description |
|---|---|
| `pgerrs` | List inconsistent PGs and object errors. |

### Known Bug Workarounds

| Script | Description |
|---|---|
| `remove_org_weight` | Works around the `ENOENT: Module Not Found` error seen when running `ceph orch` commands, caused by [tracker.ceph.com/issues/67329](https://tracker.ceph.com/issues/67329). |

## Installation

Download _update-ceph-utils_ and make the file executable.  When this script is run it will extract the files from github into _/usr/local/share/ceph-utils_.  It will then create symbolic links to the files in _/usr/local/bin_.  If you want to use different locations for the files change `CEPH_UTILS_DIR` and `BIN_DIR` in the script. 

> Most scripts assume a working `ceph` CLI and appropriate cluster admin credentials are already configured on the host they're run from.

## Contributing

Issues and pull requests are welcome on the [GitHub repository](https://github.com/lancs-gridpp/ceph-utils).