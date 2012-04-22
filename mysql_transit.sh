#!/bin/bash
#
# Copyright (c) 2012 Forschooner,Inc
# Description   : MySQL DB dump, restore, and count the number of records
# Author        : N.Hashimoto
#

# ------------------------------------------------------------
# configurations
# ------------------------------------------------------------
export LANG=C

opt_v=1.00
date_min=$(date '+%Y%m%d%H%M')
hostname=$(hostname)
dump_dir=/tmp/${hostname}

mysql_host="localhost"
mysql_port="3306"
mysql_user=""
mysql_password=""
mysql_db=""
#mysql_opt_dump="--opt --single-transaction --flush-logs --default-character-set=utf8 --hex-blob --master-data=1"
mysql_opt_dump="--opt --single-transaction --flush-logs --default-character-set=binary --hex-blob --master-data=2"
mysql_opt_restore="--default-character-set=binary"

# check the direcoty to output
if [ -d ${dump_dir} ] ; then
  true
else
  mkdir -p ${dump_dir}
fi

# ------------------------------------------------------------
# functions
# ------------------------------------------------------------
# help usage
usage() {
cat << EOF
Usage: `basename $0` -m <dump/dumpall/restore/count> -f <mysqldump file path> -d <database> -H <hostname> -P <port> -u <mysql user> -p <mysql password>
 -m	specify what to do, below.
	dump	-> mysqldump the database
	dumpall	-> mysqldump all of the databases.
	restore	-> restore the mysqldump file with -f option.
	count	-> count the number of the records in the database.
 -H	specify the host to connect.(default: localhost)
 -P	specify the port to connect.(defaut: 3306)
 -p	specify the password to connect the database.
 -u	specify the user to connect the database.
 -d	specify the database to dump, necessary when -m dump option used.
 -f	mysqldump file to restore, necessary when with -m restore option used.
 -h	show command option
 -V	show command version

EOF
exit 2
}

while getopts "d:f:m:p:u:H:P:h:V" opt ; do
  case $opt in
  d )
  opt_d="$OPTARG"
  mysql_db=$opt_d
  ;;

  f )
  opt_f="$OPTARG"
  dumpfile=$opt_f
  ;;

  m )
  opt_m="$OPTARG"
  mode=$opt_m
  ;;

  p )
  opt_p="$OPTARG"
  mysql_password=$opt_p
  ;;

  u )
  opt_u="$OPTARG"
  mysql_user=$opt_u
  ;;

  H )
  opt_H="$OPTARG"
  mysql_host=$opt_H
  ;;

  P )
  opt_P="$OPTARG"
  mysql_port=$opt_P
  ;;

  h )
  usage
  ;;

  V )
  echo "`basename $0` $opt_v" ; exit 0
  ;;

  * )
  usage
  ;;

  esac
done
shift `expr $OPTIND - 1`

# ------------------------------------------------------------
# begin script
# ------------------------------------------------------------
# Verify if current user is root
root_id=$(id -u)
if [ "$root_id" -eq 0 ]; then
  true
else
  echo 'you need to run this script as root!'
  exit 2
fi

# begin dumping or restoring
case $mode in
  dump )

  # mysqldump the database to be specified & compress
  { echo "`date '+%F %X'` dump ${mysql_db} begin" ;

  mysqldump ${mysql_opt_dump} -h ${mysql_host} -P ${mysql_port} -u ${mysql_user} -p${mysql_password} ${mysql_db} | gzip \
  > ${dump_dir}/${mysql_db}_${date_min}.sql.gz ;
  retval=$? ;

  if [ "${retval}" -eq 0 ]; then
    echo "`date '+%F %X'` dump ${mysql_db} succeed."
  else
    echo "`date '+%F %X'` dump ${mysql_db} fail."
  fi ;

  } | tee ${dump_dir}/dump_${mysql_db}_${date_min}.log 2>&1
  ;;
  
  dumpall )

  # mysqldump all of the databases & compress
  { echo "`date '+%F %X'` mysqldump all of the databases begin" ;

  mysqldump -A ${mysql_opt_dump} -h ${mysql_host} -P ${mysql_port} -u ${mysql_user} -p${mysql_password} | gzip \
  > ${dump_dir}/mysqldumpall_${date_min}.sql.gz ;
  retval=$? ;

  if [ "${retval}" -eq 0 ]; then
    echo "`date '+%F %X'` mysqldump all of the databases succeed."
  else
    echo "`date '+%F %X'` mysqldump all of the databases fail."
  fi ;

  } | tee ${dump_dir}/mysqldumpall_${date_min}.log 2>&1
  ;;

  restore )
  
  # check if defined -f, the dump file to restore
  if [ "${dumpfile}" ]; then
    true
  else
    usage
  fi

  # compressed, uncompress the dump file
  if [ -f "${dumpfile}" ]; then
    file ${dumpfile} | egrep 'gzip compressed data' >/dev/null 2>&1
    retval=$?

    if [ "${retval}" -eq 0 ]; then
       gzip -d ${dumpfile}
       dumpfile=$(echo ${dumpfile} | sed -e 's/\.gz//')
    fi

  else
    ls ${dumpfile}
  fi

  # restore the dump file
  { echo "`date '+%F %X'` restore ${mysql_db} begin" ;

  mysql -h ${mysql_host} -P ${mysql_port} -u ${mysql_user} -p${mysql_password} ${mysql_opt_restore} ${mysql_db} < ${dumpfile} ;
  retval=$? ;

  if [ "${retval}" -eq 0 ]; then
    echo "`date '+%F %X'` restore ${mysql_db} succeed." 
  else
    echo "`date '+%F %X'` restore ${mysql_db} fail." 
  fi ;

  } | tee ${dump_dir}/restore_${date_min}.log 2>&1
  ;;

  count )

  # count the number of the records of all the tables
  { echo "`date '+%F %X'` count ${mysql_db} begin" ;

  # extract the tables of the database to be specified
  mysqlshow -h ${mysql_host} -P ${mysql_port} -u ${mysql_user} -p${mysql_password} ${mysql_db} | awk '{print $2}' | egrep "${mysql_db}_" \
  > ${dump_dir}/${mysql_db}_tables.txt ;

  while read line ; do
    mysql -h ${mysql_host} -P ${mysql_port} -u ${mysql_user} -p${mysql_password} ${mysql_db} \
    -e "SELECT COUNT(*) FROM $line\G" | awk '/COUNT/ {print $2}' | sed -e "s/^/$line,/" \
    >> ${dump_dir}/${mysql_db}_cnt_${date_min}.csv
  done < ${dump_dir}/${mysql_db}_tables.txt ;

  [ -f ${dump_dir}/${mysql_db}_tables.txt ] && rm -f ${dump_dir}/${mysql_db}_tables.txt ;

  echo "`date '+%F %X'` count ${mysql_db} finished" ;
  } | tee ${dump_dir}/count_${date_min}.log 2>&1
  ;;

  * )
  usage
  ;;

esac

