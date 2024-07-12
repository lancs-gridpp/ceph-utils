# ceph-utils
Assorted BASH and Python command line scripts to either cut down the amount of typing or get information from multiple places with one command.

ok2stop <hostname>
Performs checks to see if it is safe to put <hostname> into maintenance mode

startmaint <hostname>
Puts <hostname> into maintenance mode

endmaint <hostname>
Takes <hostname> out of maintenance mode

findosd <osdid>
Finds the host running <osdid> and gets some info (make,serial number,etc) of the drive used.

cluster_dump.sh [-h] [-c <name>] <out options> [<prefix>]
Export maps from the cluster to files.

stopceph
Stop the cephfs file system and put the cluster in "down" state.

startceph
Put the cluster back in a working state

