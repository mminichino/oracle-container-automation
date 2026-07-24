#!/bin/bash
# LICENSE UPL 1.0
#
# Copyright (c) 1982-2016 Oracle and/or its affiliates. All rights reserved.
# 
# Since: November, 2016
# Author: gerald.venzl@oracle.com
# Description: Creates an Oracle Database based on following parameters:
#              $ORACLE_SID: The Oracle SID and CDB name
#              $ORACLE_PWD: The Oracle password
# 
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
# 

set -e

function err_exit {
  echo "[!] Error: $1"
  exit 1
}

# Check whether ORACLE_SID is passed on
export ORACLE_SID=${1:-oradb}

# Check whether ORACLE_PDB is passed on
export ORACLE_PDB=${ORACLE_PDB:-pdb_oradb}

CREATE_PDB=${CREATE_PDB:-0}

# Auto generate ORACLE PWD if not passed on
export ORACLE_PWD=${2:-"`openssl rand -base64 8`1"}
echo "ORACLE PASSWORD FOR SYS AND SYSTEM: $ORACLE_PWD";

# Replace place holders in response file
cp $ORACLE_BASE/$CONFIG_RSP $ORACLE_BASE/dbca.rsp
sed -i -e "s|###ORACLE_SID###|$ORACLE_SID|g" $ORACLE_BASE/dbca.rsp
sed -i -e "s|###ORACLE_PWD###|$ORACLE_PWD|g" $ORACLE_BASE/dbca.rsp
sed -i -e "s|###ORACLE_PDB###|$ORACLE_PDB|g" $ORACLE_BASE/dbca.rsp
sed -i -e "s|###ORACLE_CHARACTERSET###|$ORACLE_CHARACTERSET|g" $ORACLE_BASE/dbca.rsp

# If there is greater than 8 CPUs default back to dbca memory calculations
# dbca will automatically pick 40% of available memory for Oracle DB
# The minimum of 2G is for small environments to guarantee that Oracle has enough memory to function
# However, bigger environment can and should use more of the available memory
# This is due to Github Issue #307
if [ `nproc` -gt 8 ]; then
   sed -i -e 's|TOTALMEMORY = "2048"||g' $ORACLE_BASE/dbca.rsp
fi;

# Create network related config files (sqlnet.ora, tnsnames.ora, listener.ora)
mkdir -p $ORACLE_HOME/network/admin
echo "NAME.DIRECTORY_PATH= (TNSNAMES, EZCONNECT, HOSTNAME)" > $ORACLE_HOME/network/admin/sqlnet.ora

# Listener.ora
echo "LISTENER = 
(DESCRIPTION_LIST = 
  (DESCRIPTION = 
    (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1)) 
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521)) 
  ) 
) 

DEDICATED_THROUGH_BROKER_LISTENER=ON
DIAG_ADR_ENABLED = off
" > $ORACLE_HOME/network/admin/listener.ora

# Start LISTENER and run DBCA
lsnrctl start &&
dbca -silent -createDatabase -responseFile $ORACLE_BASE/dbca.rsp ||
 cat /opt/oracle/cfgtoollogs/dbca/$ORACLE_SID/$ORACLE_SID.log ||
 cat /opt/oracle/cfgtoollogs/dbca/$ORACLE_SID.log

echo "$ORACLE_SID= 
  (DESCRIPTION = 
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = $ORACLE_SID)
    )
  )" > $ORACLE_HOME/network/admin/tnsnames.ora

## Remove second control file
#sqlplus / as sysdba << EOF
#   ALTER SYSTEM SET control_files='$ORACLE_BASE/oradata/$ORACLE_SID/control01.ctl' scope=spfile;
#   exit;
#EOF

if [ "$CREATE_PDB" -eq 1 ];then
echo -n "Set PDB to auto open ..."
sqlplus / as sysdba << EOF
   ALTER PLUGGABLE DATABASE $ORACLE_PDB SAVE STATE;
   exit;
EOF
echo "Done."
fi

# Remove temporary response file
rm $ORACLE_BASE/dbca.rsp

LOGDIR=$ORACLE_BASE/archivelog

echo -n "Setting archive log destination to $LOGDIR ..."
sqlplus -S / as sysdba << EOF
   set heading off;
   set pagesize 0;
   set feedback off;
   ALTER SYSTEM SET log_archive_dest_1='location=$LOGDIR' SCOPE=spfile;
   exit;
EOF
if [ $? -ne 0 ]; then
   err_exit "Failed to set log destination"
else
   echo "Done."
fi

echo -n "Shutting down instance ..."
sqlplus -S / as sysdba << EOF
   set heading off;
   set pagesize 0;
   set feedback off;
   shutdown immediate;
   exit;
EOF
if [ $? -ne 0 ]; then
   err_exit "Failed to shutdown instance $ORACLE_SID ..."
else
   echo "Done."
fi

echo -n "Starting instance mounted ..."
sqlplus -S / as sysdba << EOF
   set heading off;
   set pagesize 0;
   set feedback off;
   startup mount;
   exit;
EOF
if [ $? -ne 0 ]; then
   err_exit "Failed to start instance $ORACLE_SID ..."
else
   echo "Done."
fi

echo -n "Setting archive log mode ..."
sqlplus -S / as sysdba << EOF
   set heading off;
   set pagesize 0;
   set feedback off;
   ALTER DATABASE ARCHIVELOG;
   ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
   ALTER SYSTEM SET undo_retention = 86400 SCOPE=BOTH;
   exit;
EOF
if [ $? -ne 0 ]; then
   err_exit "Failed to set archive log mode for $ORACLE_SID ..."
else
   echo "Done."
fi

echo -n "Opening database ..."
sqlplus -S / as sysdba << EOF
   set heading off;
   set pagesize 0;
   set feedback off;
   ALTER DATABASE OPEN;
   exit;
EOF
if [ $? -ne 0 ]; then
   err_exit "Failed to open $ORACLE_SID ..."
else
   echo "Done."
fi
