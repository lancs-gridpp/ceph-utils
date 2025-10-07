# ceph-utils
Assorted BASH and Python command line scripts to either cut down the amount of typing or get information from multiple places with one command.

## Available Scripts

| Title | Description |
| --- | --- |
| activescrubs | Show the PGs that are currently scrubbing with period updates. |
| backfilling | Set/Unset the OSD backfilling flag and optionally mute the health warning OSDMAP_FLAGS |
| bottleneck | Anyalize the specified osd numbers to see what things they have in common |
| clientlist | Generate a list of clients connected using CephFS |
| cluster_dump.sh | Export maps from the cluster to files. Usage: `cluster_dump.sh [-h] [-c <name>] <out options> [<prefix>]` |
| endmaint | Takes `<hostname>` out of maintenance mode. Usage: `endmaint <hostname>` |
| findosd | Finds the host running `<osd_id>` and gets some info (make, serial number, etc) of the drive used. Usage: `findosd <osd_id>` |
| ok2stop | Performs checks to see if it is safe to stop services on `<hostname>` or stop the service for `<osd_id>`. Usage: `ok2stop <hostname>|<osd_id>` |
| lessjq | Output formatted JSON in less.  |
| pgerrs | List inconsistent PGs and object errors. |
| remove_org_weight | This is a fix for the error "ENOENT: Module Not Found" when running **ceph orch** commands caused by the bug https://tracker.ceph.com/issues/67329 |
| restartosd | Restart the specified osd id using ceph orhcestration.  Checks are made to make sure it is safe to restart the osd and the script verifies the osd has restarted. |
| scrubbing  | Set/Unset the OSD scrubbing flags and optionally mute the health warning OSDMAP_FLAGS |
| scrubinfo | Show the PG scrubbing information |
| startceph | Put the cluster back in a working state. Usage: `startceph` |
| startmaint | Puts `<hostname>` into maintenance mode. Usage: `startmaint <hostname>` |
| sarttmux | Create a tmux session with predefined windows created. |
| stopceph | Stop the cephfs file system and put the cluster in "down" state. Usage: `stopceph` |
