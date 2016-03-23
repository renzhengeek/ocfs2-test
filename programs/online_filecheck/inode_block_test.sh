#!/bin/bash

################################################################################
# Global Variables
################################################################################
if [ -f `dirname ${0}`/o2tf.sh ]; then
    . `dirname ${0}`/o2tf.sh
fi

if [ -f `dirname ${0}`/filecheck_utils.sh ]; then
    . `dirname ${0}`/filecheck_utils.sh
fi

PATH=$PATH:/usr/sbin/

FSWRECK_BIN="`dirname ${0}`/fswreck"
DEBUGFS_BIN="`which debugfs.ocfs2`"
SUDO_FSWRECK="`which sudo` -u root `dirname ${0}`/fswreck"
SUDO_BASH="`which sudo` -u root bash -c"
SUDO_CAT="`which sudo` -u root `which cat`"

DEVICE=
MOUNT_POINT=
MOUNT_OPTS="errors=continue"
FEATURES="local,metaecc"

LOG_DIR=
DETAIL_LOG_FILE=

SYSDIR_OCFS2=/sys/fs/ocfs2
SYSDIR_DEVICE=
CHECK_FILE=
FIX_FILE=
SET_CACHE=
CACHE_MIN=10
CACHE_MAX=100

TEST_NO=0
TEST_PASS=0

set -o pipefail

################################################################################
# Utility Functions
################################################################################
function f_usage()
{
    echo "usage: `basename ${0}` <-d device> <-m mountpoint> <-l log-dir>"
    return 1;
}

function f_getoptions()
{
    if [ $# -eq 0 ]; then
        f_usage;
        return 1
    fi

    while getopts "d:m:l:h" options; do
        case $options in
            d ) DEVICE="$OPTARG";;
            m ) MOUNT_POINT="$OPTARG";;
            l ) LOG_DIR="$OPTARG";;
            h ) f_usage;;
            * ) f_usage;;
        esac
    done
}

function f_setup()
{
    f_getoptions $*

    if [ ! -x ${FSWRECK_BIN} ];then
       f_LogMsg ${DETAIL_LOG_FILE} "Fswreck tool must be provided to proceed testing..."
       return 1
    fi

    if [ ! -x ${DEBUGFS_BIN} ];then
       f_LogMsg ${DETAIL_LOG_FILE} "Debugfs.ocfs2 tool must be provided to proceed testing..."
       return 1
    fi

    LOG_SURFIX="`date +%Y-%m-%d_%H-%M-%S`"
    DETAIL_LOG_FILE="${LOG_DIR}/inode_block_test-${LOG_SURFIX}.log"

    SYSDIR_DEVICE="${SYSDIR_OCFS2}/`basename ${DEVICE}`"
    CHECK_FILE="${SYSDIR_DEVICE}/filecheck/check"
    FIX_FILE="${SYSDIR_DEVICE}/filecheck/fix"
    SET_CACHE="${SYSDIR_DEVICE}/filecheck/set"
}

function f_cleanup()
{
    :
}


################################################################################
# Core Function
################################################################################
function f_runtest()
{
    local -i rv=1
    local ERR_TYPE_ARRY="inode_gen inode_ecc inode_block_num cache_size"

    for type in ${ERR_TYPE_ARRY}; do
        ((TEST_NO++))

        case "${type}" in
        inode_gen )
            rv=f_inode_gen_check;;
        inode_ecc )
            rv=f_inode_ecc;;
        inode_block_num )
            rv=f_inode_block_num;;
        cache_size )
            rv=f_cache_size;;
        * ) echo -e "Unknown testing unit: ${type}" >> ${DETAIL_LOG_FILE}
            rv=1;;
        esac

        if [ $rv -eq 0 ];then
            ((TEST_PASS++))
        fi
    done

    return $rv
}

function f_inode_gen_check()
{
    echo -e "\n[${TEST_NO}] Inode generation number:" >> ${DETAIL_LOG_FILE}

    #fswreck
    echo -e "[*] Corrupt inode generation number:" >> ${DETAIL_LOG_FILE}
    f_LogMsg ${DETAIL_LOG_FILE} "${SUDO_FSWRECK} -c INODE_GEN ${DEVICE}"
    ${SUDO_FSWRECK} -c INODE_GEN ${DEVICE} > .tmp 2>&1
    f_exit_or_not $?
    cat .tmp >> ${DETAIL_LOG_FILE} 2>&1

    local LINE=`cat .tmp | tail -n 1`
    echo -e "Got the last line: ${LINE}" >> ${DETAIL_LOG_FILE}
    rm -f -- .tmp

    local TMP=${LINE#*#}
    local INO=${TMP%,*}
    f_LogMsg ${DETAIL_LOG_FILE} "Got inode number: ${INO}"
    local GOOD_GEN=`echo ${LINE}|awk '{print $7}'`
    f_LogMsg ${DETAIL_LOG_FILE} "Got good generation number: ${GOOD_GEN}"

    #check
    f_check_file ${INO} ${CHECK_FILE} "GENERATION" ${DETAIL_LOG_FILE}
    if [ $? -eq 0 ];then
        f_LogMsg ${DETAIL_LOG_FILE} "Check: PASSED"
    else
        f_LogMsg ${DETAIL_LOG_FILE} "Check: FAILED"
    fi

    #fix
    f_fix_file ${INO} ${FIX_FILE} ${DETAIL_LOG_FILE}
    if [ $? -eq 0 ];then
        f_LogMsg ${DETAIL_LOG_FILE} "Fix: PASSED"
    else
        f_LogMsg ${DETAIL_LOG_FILE} "Fix: FAILED"
    fi

    #verify
    echo -e "\n[*] Verify:" >> ${DETAIL_LOG_FILE} 2>&1
    f_verify_inode_gen ${INO} ${GOOD_GEN} ${DEVICE}>> ${DETAIL_LOG_FILE} 2>&1
    if [ $? -ne 0 ]; then
        echo "Fail: fix inode#${INO} generation." >> ${DETAIL_LOG_FILE} 2>&1
        return 1
    fi

    return 0
}

function f_inode_ecc()
{
    echo -e "\n[${TEST_NO}] Inode ecc:" >> ${DETAIL_LOG_FILE}

    #fswreck
    f_LogMsg ${DETAIL_LOG_FILE} "${SUDO_FSWRECK} -c INODE_BLOCK_ECC ${DEVICE}"
    ${SUDO_FSWRECK} -c INODE_BLOCK_ECC ${DEVICE} > .tmp 2>&1
    RET=$?
    f_exit_or_not ${RET}
    cat .tmp >> ${DETAIL_LOG_FILE} 2>&1

    local LINE=`cat .tmp | tail -n 1`
    rm -f -- .tmp
    local TMP=${LINE#*#}
    local INO=${TMP%,*}
    local BAD_CRC32=0x1234
    local BAD_ECC=0x1234

    #check
    f_check_file ${INO} ${CHECK_FILE} "BLOCKECC" ${DETAIL_LOG_FILE}
    if [ $? -eq 0 ];then
        f_LogMsg ${DETAIL_LOG_FILE} "Check: PASSED"
    else
        f_LogMsg ${DETAIL_LOG_FILE} "Check: FAILED"
    fi

    #fix
    f_fix_file ${INO} ${FIX_FILE} ${DETAIL_LOG_FILE}
    if [ $? -eq 0 ];then
        f_LogMsg ${DETAIL_LOG_FILE} "Fix: PASSED"
    else
        f_LogMsg ${DETAIL_LOG_FILE} "Fix: FAILED"
    fi

    #verify
    echo -e "\n[*] Verify:" >> ${DETAIL_LOG_FILE} 2>&1
    f_verify_inode_meta_ecc ${INO} ${BAD_CRC32} ${BAD_ECC} ${DEVICE}>> ${DETAIL_LOG_FILE} 2>&1
    if [ $? -ne 0 ]; then
        echo "Fail: fix inode#${INO} meta ecc." >> ${DETAIL_LOG_FILE} 2>&1
        return 1
    fi

    return 0
}

function f_inode_block_num()
{
    echo -e "\n[${TEST_NO}] Inode block number:" >> ${DETAIL_LOG_FILE}

    #fswreck
    echo -e "\n[*] Corrupt inode block number:" >> ${DETAIL_LOG_FILE}
    f_LogMsg ${DETAIL_LOG_FILE} "${SUDO_FSWRECK} -c INODE_BLKNO ${DEVICE}"
    ${SUDO_FSWRECK} -c INODE_BLKNO ${DEVICE} > .tmp 2>&1
    RET=$?
    f_exit_or_not ${RET}
    cat .tmp >> ${DETAIL_LOG_FILE} 2>&1

    local LINE=`cat .tmp | tail -n 1`
    rm -f -- .tmp
    local TMP=${LINE#*#}
    local INO=${TMP%,*}
    local GOOD_BLOCKNUM=`echo ${LINE}|awk '{print $7}'`

    #check
    f_check_file ${INO} ${CHECK_FILE} "BLOCKNO" ${DETAIL_LOG_FILE}
    if [ $? -eq 0 ];then
        f_LogMsg ${DETAIL_LOG_FILE} "Check: PASSED"
    else
        f_LogMsg ${DETAIL_LOG_FILE} "Check: FAILED"
    fi

    #fix
    f_fix_file ${INO} ${FIX_FILE} ${DETAIL_LOG_FILE}
    if [ $? -eq 0 ];then
        f_LogMsg ${DETAIL_LOG_FILE} "Fix: PASSED"
    else
        f_LogMsg ${DETAIL_LOG_FILE} "Fix: FAILED"
    fi

    #verify
    echo -e "\n[*] Verify:" >> ${DETAIL_LOG_FILE} 2>&1
    f_verify_inode_block_num ${INO} ${GOOD_BLOCKNUM} ${DEVICE}>> ${DETAIL_LOG_FILE} 2>&1
    if [ $? -ne 0 ]; then
        echo "Fail: fix inode#${INO}'s block number." >> ${DETAIL_LOG_FILE} 2>&1
        return 1
    fi

    return 0
}

#cache size to save check records
function f_cache_size()
{
    echo -e "\n[${TEST_NO}] Cache size setting:" >> ${DETAIL_LOG_FILE}

    #see if case size is valid
    local SIZE=`${SUDO_BASH} "cat ${SET_CACHE}"`
    f_LogMsg ${DETAIL_LOG_FILE} "${SUDO_BASH} \"cat ${SET_CACHE}\""
    f_LogMsg ${DETAIL_LOG_FILE} "Cache size: ${SIZE}"
    if [ ${SIZE} -gt ${CACHE_MAX} -o ${SIZE} -lt ${CACHE_MIN} ];then
        f_LogMsg ${DETAIL_LOG_FILE} "Cache size should be in [${CACHE_MIN}, ${CACHE_MAX}]."
        return 1
    fi

    #positive test case
    echo -e "Positive testing:" >> ${DETAIL_LOG_FILE}
    for size in ${CACHE_MIN} ${CACHE_MAX}; do
        f_LogMsg ${DETAIL_LOG_FILE} "${SUDO_BASH} \"echo ${size} > ${SET_CACHE}\""
        ${SUDO_BASH} "echo ${size} > ${SET_CACHE}" >> ${DETAIL_LOG_FILE} 2>&1
        if [ $? -ne 0 ]; then
            f_LogMsg ${DETAIL_LOG_FILE} "Faild to set case size to $size"
            return 1
        fi
    done

    #negative test case
    echo -e "Negative testing:" >> ${DETAIL_LOG_FILE}
    for size in ${CACHE_MIN}-1 ${CACHE_MAX}+1; do
        f_LogMsg ${DETAIL_LOG_FILE} "${SUDO_BASH} \"echo ${size} > ${SET_CACHE}\""
        ${SUDO_BASH} "echo ${size} > ${SET_CACHE}" >> ${DETAIL_LOG_FILE} 2>&1
        if [ $? -eq 0 ]; then
            f_LogMsg ${DETAIL_LOG_FILE} "We should *NOT* set case size to $size successfully."
            return 1
        fi
    done

    return 0
}

################################################################################
# Main Entry
################################################################################

#redefine the int signal hander
trap 'echo -ne "\n\n">>${DETAIL_LOG_FILE};echo  "Interrupted by Ctrl+C,Cleanuping ... "|tee
-a ${DETAIL_LOG_FILE}; f_cleanup; return 1' SIGINT

f_setup $*

START_TIME=${SECONDS}
f_LogMsg ${DETAIL_LOG_FILE} "=====================Inode block testing start:  `date`
====================="

f_runtest

END_TIME=${SECONDS}
f_LogMsg ${DETAIL_LOG_FILE} "=====================Inode block testing end: `date`
====================="

f_LogMsg ${DETAIL_LOG_FILE} "Time elapsed(s): $((${END_TIME}-${START_TIME}))"
f_LogMsg ${DETAIL_LOG_FILE} "Tests total: ${TEST_NO}"
f_LogMsg ${DETAIL_LOG_FILE} "Tests passed: ${TEST_PASS}"
