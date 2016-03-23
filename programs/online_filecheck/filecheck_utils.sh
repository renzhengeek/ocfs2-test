#!/bin/bash

PATH=$PATH:/usr/sbin/

DEBUGFS_BIN="`which sudo` -u root `which debugfs.ocfs2`"
FSWRECK_BIN="`which sudo` -u root `dirname ${0}`/fswreck"
SUDO_BASH="`which sudo` -u root bash -c"
SUDO_CAT="`which sudo` -u root `which cat`"

f_check_file()
{
   local inode=$1
   local check_file=$2
   local error_type=$3
   local log_file=$4

   echo -e "${SUDO_BASH} \"echo ${inode} > ${check_file}\"" >> ${log_file} 2>&1
   ${SUDO_BASH} "echo ${inode} > ${check_file}"
   sleep 0.1
   ${SUDO_CAT} ${check_file} > .tmp 2>&1
   cat .tmp | head -n 1 >> ${log_file} 2>&1
   LINE=`cat .tmp | tail -n 1`
   rm -f -- .tmp
   echo -e "${LINE}" >> ${log_file}
   local ERROR=`echo ${LINE} | awk '{print $3}'`
   f_LogMsg ${log_file} "Error type: ${ERROR}"
   if [ ${ERROR} != "${error_type}" ];then
      f_LogMsg ${log_file} "Unexpected error type, exit..."
      return 1
   fi

   return 0
}

f_fix_file()
{
   local inode=$1
   local fix_file=$2
   local log_file=$3

   echo -e "${SUDO_BASH} \"echo ${inode} > ${fix_file}\"" >> ${log_file} 2>&1
   ${SUDO_BASH} "echo ${inode} > ${fix_file}"
   sleep 0.1
   ${SUDO_CAT} ${fix_file} > .tmp 2>&1
   cat .tmp | head -n 1 >> ${log_file} 2>&1
   LINE=`cat .tmp | tail -n 1`
   rm -f -- .tmp
   echo -e "${LINE}" >> ${log_file}
   local RESULT=`echo ${LINE} | awk '{print $3}'`
   f_LogMsg ${log_file} "Fix result: ${RESULT}"
   if [ ${RESULT} != "SUCCESS" ];then
      f_LogMsg ${log_file} "Failed to fix! Exit..."
      return 1
   fi

   return 0
}

f_verify_inode_gen()
{
    local -i inode=$1
    local -i gen=$2
    DEVICE=$3

    fix_result=`${DEBUGFS_BIN} -R "stat <${inode}>" ${DEVICE}|grep "FS Generation:"`
    fix_gen=`echo ${fix_result} | awk '{print $3}'`
    if [ -z $fix_gen ];then
        echo "Failed to get FS generation number using debugfs.ocfs2";
        return 1;
    fi

    echo "fs generation=$fix_gen, wanted=$gen"
    if [ $fix_gen -ne $gen ];then
        echo "Verify: failed to fix."
        return 1
    fi

    return 0
}

f_verify_inode_block_num()
{
    local -i inode=$1
    local -i block_num=$2
    DEVICE=$3

    fix_result=`${DEBUGFS_BIN} -R "stat <${inode}>" ${DEVICE}|grep "Inode:"`
    fix_block_num=`echo ${fix_result} | awk '{print $2}'`

    echo "inode block number=$fix_block_num, wanted=$block_num"
    if [ $fix_block_num -ne $block_num ];then
        echo "Verify: failed to fix."
        return 1
    fi

    return 0
}

f_verify_inode_meta_ecc()
{
    local -i inode=$1
    local crc32=`printf "%d" $2`
    local ecc=`printf "%d" $3`
    DEVICE=$4

    fix_result=`${DEBUGFS_BIN} -R "stat <${inode}>" ${DEVICE}|grep "CRC32:"`
    fix_crc32=`echo ${fix_result} | awk '{print $2}'`
    fix_crc32=`printf "%d" 0x${fix_crc32}`
    fix_ecc=`echo ${fix_result} | awk '{print $4}'`
    fix_ecc=`printf "%d" 0x${fix_ecc}`

    echo "crc32=$fix_crc32, bad crc32=$crc32; ecc=$fix_ecc, bad ecc=$ecc"
    if [ $fix_crc32 -ne $crc32 ];then
        echo "Failed to verify this fix."
        return 1
    fi

    return 0
}
