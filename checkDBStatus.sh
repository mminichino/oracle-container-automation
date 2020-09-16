#!/bin/bash
# LICENSE UPL 1.0
#
# Copyright (c) 1982-2018 Oracle and/or its affiliates. All rights reserved.
#
# Since: May, 2017
# Author: gerald.venzl@oracle.com
# Description: Checks the status of Oracle Database.
# Return codes: 0 = DB is open and ready to use
#               1 = DB is not open
#               2 = Sql Plus execution failed
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
# 

ORACLE_SID="`grep $ORACLE_HOME /etc/oratab | cut -d: -f1`"
OPEN_MODE="READ WRITE"
ORAENV_ASK=NO
source oraenv

# Check Oracle at least one DB has open_mode "READ WRITE" and store it in status
status=`sqlplus -s / as sysdba << EOF
   set heading off;
   set pagesize 0;
   select open_mode from v\\$database;
   exit;
EOF`

# Store return code from SQL*Plus
ret=$?

# SQL Plus execution was successful and DB is open
if [ $ret -eq 0 ] && [ "$status" = "$OPEN_MODE" ]; then
   exit 0;
# DB is not open
elif [ "$status" != "$OPEN_MODE" ]; then
   exit 1;
# SQL Plus execution failed
else
   exit 2;
fi;