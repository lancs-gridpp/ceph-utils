#!/usr/bin/env bash
trap "do_exit" INT
#------------------------------------------------------------------------------------------------
#
# Licence: MIT
# Created by: Theofilos Mouratidis <t.mour@cern.ch>  Date: 2019/05/24
#
# Modfied by: Gerard Hand <g.hand@cern.ch>           Date: 2024/07/22
# - Added option to run in "cephadm shell"
# - Created directory structure for holding the data files.
#
#
# https://github.com/cernceph/ceph-scripts/blob/master/tools/cluster_dump.sh
#
#------------------------------------------------------------------------------------------------
# cluster_dump.sh

# Create files containing cluster data.  -d option added to create subdirectories to hold the data files.
# The name of the subdirectories are based on cluster name and the current date/time.
#
# ./<cluster_id>/ -+--> data<timestamp1>/
#                  |
#                  +--> data<timestamp2>/
#                  |
#                  +--> data<timestamp3>/
#
CLUSTER="ceph"
SAVE_WHAT=""
PREFIX=""
TIMESTAMP=$(date +%Y%m%d_%H%M)
DODIRS=0

declare -A CMD=(
    ["pg"]="pg dump ,, Saves the pg state"
    ["pg-json"]="pg dump -f json-pretty ,, Saves the pg state (json)"
    ["osd"]="osd dump ,, Saves the osd state"
    ["osd-json"]="osd dump -f json-pretty ,, Saves the osd state (json)"
    ["crush"]="osd getcrushmap 2> /dev/null | cephadm shell crushtool -d - ,, Saves the crushmap"
    ["tree"]="osd tree ,, Saves the osd tree"
    ["tree-json"]="osd tree -f json-pretty ,, Saves the osd tree (json)"
    ["df"]="osd df ,, Saves the osd df"
    ["df-json"]="osd df -f json-pretty ,, Saves the osd df (json)"
    ["osd-map"]="osd getmap ,, Saves the osd map"
    ["mon-map"]="mon getmap ,, Saves the mon map"
    ["mds-map"]="fs dump ,, Saves the mds map"
)

function do_exit() {
    echo "Script terminated"
    exit 1
}

function show_help() {
    echo "  This script saves data from ceph. It is mainly used to log critical data for recovery reasons"
    echo
    show_usage
    echo
    # Use \t to align your fields in the table
    OUT=""
    OUT="$OUT\n  -h/--help\t  Show this message"
    OUT="$OUT\n  -c/--cluster <name>\t  Select cluster"
    OUT="$OUT\n  -d\t  Create output directories"
    echo -e "$OUT" | column -ts $'\t'
    echo
    show_output_options
    echo
    echo "  Example command: "
    echo "    cluster_dump -a -c erin /tmp/out"
    echo "  This will dump all the output options to the /tmp/out_* prefix for cluster erin"
    echo
}

function show_usage() {
    echo " Usage:"
    echo "  cluster_dump.sh [-h] [-c <name>] <out options> [<prefix>]"
}

function show_output_options() {
    echo " OUTPUT OPTIONS:"
    OUT="  -a, --all\t Select all output options"
    for key in ${!CMD[@]}; do
        OUT="$OUT\n  --$key\t${CMD[$key]##*",,"}"
    done
    echo -e "$OUT" | sort -r | column -ts $'\t' -o $'\t\t'
}

while test $# -gt 0; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        # Can define additional arguments with custom functionality as:
        # -m|--mycommand)
        #   do_stuff
        # ;;
        # for main functionality just use the $CMD dictionary above
        -c|--cluster)
            shift
            case "$1" in
                [a-zA-Z0-9_]*)
                    CLUSTER="$1"
                    ;;
                *)
                    echo "After -c, $1 doesn't look like a cluster name"
                    exit 0
                    ;;
            esac
            ;;
        -a|--all)
            if [[ $SAVE_WHAT == "" ]]; then
                SAVE_WHAT="all"
            else
                echo "All flag is incompatible with these others: $SAVE_WHAT"
                exit 0
            fi
            ;;
        -d)
            DODIRS=1
            ;;
        *)
            found=false
            if [[ "$1" =~ ^- ]]; then
                if [[ "$1" =~ ^-- ]]; then
                    ARG="${1//-}"
                    if [[ "${!CMD[@]}" =~ "$ARG" ]]; then
                        if [[ "$SAVE_WHAT" =~ "all" ]]; then
                            echo "All flag is incompatible with these others: $ARG"
                            exit 0
                        fi
                        if grep -v "$ARG" <<< "$SAVE_WHAT" > /dev/null; then
                            SAVE_WHAT="$SAVE_WHAT $ARG"
                            found=true
                        fi
                    fi
                fi
                if [[ $found == false ]]; then
                    echo "Unknown argument $ARG"
                    exit 0
                fi
            else
                PREFIX=$1
            fi
            ;;
    esac
    shift
done

if [[ $SAVE_WHAT == "all" ]]; then
    SAVE_WHAT="${!CMD[@]}"
elif [[ $SAVE_WHAT == "" ]]; then
    echo -e "You must specify an output option.\n"
    show_output_options
    exit 0
fi

if [[ "$DODIRS" == "1" ]]; then
    if [[ "$PREFIX" != "" ]]; then
        echo "The prefix ($PREFIX) is ignored when using the -d option"
    fi

    if [[ ! -d "./$CLUSTER" ]]; then
        echo "Creating directory: ./$CLUSTER"
        mkdir $CLUSTER
    fi

    if [[ ! -d "./$CLUSTER/$TIMESTAMP" ]]; then
        echo "Creating directory: ./$CLUSTER/$TIMESTAMP"
        mkdir $CLUSTER/$TIMESTAMP
    fi

    PREFIX="$CLUSTER/$TIMESTAMP/"
else
    # A prefix is being used for output files.  Check it's a valid prefix.

    # Is the prefix an existing directory
    if test -d "$PREFIX"; then
        # Make sure the / is on the end of the path.
        [[ "$PREFIX" != */ ]] && PREFIX="$PREFIX/"
    else
        # Check if a file can be created using the prefix
        tmp="${PREFIX}_ab34f5h4df56hf456bfk"
        if touch "$tmp" > /dev/null 2>&1; then
            # Remove the temp file just created.
            rm -f $tmp
            # Make sure the _ is on the end of the path.
            [[ "$PREFIX" != *_ ]] && PREFIX="${PREFIX}_"
        else
            # There is either a file permissions problem or directories that don't exist in $PREFIX.
            echo "ERROR: Unable to create files using the prefix '$PREFIX'"
            exit 0
       fi
    fi
fi

exec_cmd() {
    local FNAME=$3$2
#    eval "ceph --cluster $CLUSTER $1 > ${PREFIX}${CLUSTER}_$2_$(date +%Y%m%d_%H%M) 2>> /var/log/ceph/cluster_dump.log"
    printf "%-${OKPOS}s" "Creating $FNAME"
    eval "ceph --cluster $CLUSTER $1 > $FNAME 2>> /var/log/ceph/cluster_dump.log"

    if [[ "$?" != "0" ]]; then
        echo "ERROR"
    else
        echo "OK"
    fi
}

OKPOS=10
for key in $SAVE_WHAT; do
    FNAME="creating $PREFIX$key"
    if [[ ${#FNAME} -gt $OKPOS ]]; then
        OKPOS=${#FNAME}
    fi
done
let OKPOS+=10

for key in $SAVE_WHAT; do
    exec_cmd "${CMD[$key]%%",,"*}" $key $PREFIX
done

