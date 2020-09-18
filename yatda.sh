#!/bin/bash
#
# Yatda is just Yet Another Thread Dump Analyzer.  It focuses on 
# providing quick JBoss EAP 7 specific statistics and known concerns.
#
# Usage: sh ./yatda.sh <THREAD_DUMP_FILE_NAME>
#    -f: thead dump file name
#    -t: specify a thread name to focus on
#    -s: specify a particular generic line indicating thread usage
#    -n: number of stack lines to focus on from specified threads
#    -a: number of stack lines to focus on from all threads
#

# default string references to search for generic EAP 7 request stats
DUMP_NAME="Full thread dump "
#ALL_THREAD_NAME=" nid="
ALL_THREAD_NAME=" nid=0x"
REQUEST_THREAD_NAME="default task-"
REQUEST_TRACE="io.undertow.server.Connectors.executeRootHandler"
REQUEST_COUNT=0
SPECIFIED_LINE_COUNT=20
ALL_LINE_COUNT=10


# flags
while getopts t:s:n:a:f: flag
do
    case "${flag}" in
        t) SPECIFIED_THREAD=${OPTARG};;
        s) SPECIFIED_TRACE=${OPTARG};;
        n) SPECIFIED_LINE_COUNT=${OPTARG};;
        a) ALL_LINE_COUNT=${OPTARG};;
        f) FILE_NAME=${OPTARG};;
    esac
done

if [ "x$FILE_NAME" = "x" ]; then
    echo "Please specify file name with -f flag"
    exit
fi

# Check for a new yatda.sh.  Uncomment next line if you want to avoid this check
# CHECK_UPDATE="false"
if [ "x$CHECK_UPDATE" = "x" ]; then
    echo "Checking update. Uncomment CHECK_UPDATE in script if you wish to skip."
    DIR=`dirname "$(readlink -f "$0")"`
    SUM=`md5sum $DIR/yatda.sh | awk '{ print $1 }'`
    NEWSUM=`curl https://raw.githubusercontent.com/aogburn/yatda/master/md5`
    echo $DIR
    echo $SUM
    echo $NEWSUM
    if [ "x$NEWSUM" != "x" ]; then
        if [ $SUM != $NEWSUM ]; then
            echo "Version difference detected.  Downloading new version. Please re-run yatda."
            wget -q https://raw.githubusercontent.com/aogburn/yatda/master/yatda.sh -O $DIR/yatda.sh
            exit
        fi
    fi
    echo "Check complete."
fi


# Use different thread details if it looks like a thread dump from JBossWeb/Tomcat
if [ `grep 'org.apache.tomcat.util' $FILE_NAME | wc -l` -gt 0 ]; then
    echo "Treating as dump from JBossWeb or Tomcat"
    REQUEST_THREAD_NAME="http-|ajp-"
    REQUEST_TRACE="org.apache.catalina.connector.CoyoteAdapter.service"
fi


# Handle java 11 dump differently
# Not needed currently
#if [ `grep "$DUMP_NAME" $FILE_NAME | grep " 11\." | wc -l` -gt 0 ]; then
#    echo "Treating as dump from java 11"
#fi


# Here we'll whip up some thread usage stats

DUMP_COUNT=`grep "$DUMP_NAME" $FILE_NAME | wc -l`
echo "Number of thread dumps: " $DUMP_COUNT > $FILE_NAME.yatda

THREAD_COUNT=`grep "$ALL_THREAD_NAME" $FILE_NAME | wc -l`
echo "Total number of threads: " $THREAD_COUNT >> $FILE_NAME.yatda

REQUEST_THREAD_COUNT=`grep "$ALL_THREAD_NAME" $FILE_NAME | egrep "$REQUEST_THREAD_NAME" | wc -l`
echo "Total number of request threads: " $REQUEST_THREAD_COUNT >> $FILE_NAME.yatda

if [ $REQUEST_THREAD_COUNT -gt 0 ]; then
    REQUEST_COUNT=`grep "$REQUEST_TRACE" $FILE_NAME | wc -l`
    echo "Total number of in process requests: " $REQUEST_COUNT >> $FILE_NAME.yatda

    REQUEST_PERCENT=`printf %.2f "$((10**4 * $REQUEST_COUNT / $REQUEST_THREAD_COUNT ))e-2" `
    echo "Percent of present request threads in use for requests: " $REQUEST_PERCENT >> $FILE_NAME.yatda

    if [ $DUMP_COUNT -gt 1 ]; then
        echo "Average number of in process requests per thread dump: " `expr $REQUEST_COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
        echo "Average number of request threads per thread dump: " `expr $REQUEST_THREAD_COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
        echo "Average number of threads per thread dump: " `expr $THREAD_COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
    fi
fi
#end stats


# Here we'll try to point out any specific known issues
echo >> $FILE_NAME.yatda
echo "## Specific findings ##" >> $FILE_NAME.yatda
i=1

# request thread default and core count
if [[ $REQUEST_THREAD_COUNT -gt 0 && `expr $REQUEST_THREAD_COUNT % 16` == 0 ]]; then
NUMBER_CORES=`expr $REQUEST_THREAD_COUNT / 16`
NUMBER_CORES=`expr $NUMBER_CORES / $DUMP_COUNT`
    echo >> $FILE_NAME.yatda
    echo $((i++)) ": The number of present request threads is a multple of 16 so this may be a default thread pool size fitting $NUMBER_CORES CPU cores." >> $FILE_NAME.yatda
fi


# request thread exhaustion
if [ $REQUEST_COUNT -gt 0 ] && [ $REQUEST_COUNT == $REQUEST_THREAD_COUNT ]; then
#if [ $REQUEST_COUNT == $REQUEST_THREAD_COUNT ]; then
    echo >> $FILE_NAME.yatda
    echo $((i++)) ": The number of processing requests is equal to the number of present request threads.  This may indicate thread pool exhaustion so the task-max-threads may need to be increased (https://access.redhat.com/solutions/2455451)." >> $FILE_NAME.yatda
fi


# check datasource exhaustion


# check java.util.Arrays.copyOf calls

echo >> $FILE_NAME.yatda
# end Findings


# This returns counts of the top line from all request thread stacks
echo "## Top lines of request threads ##" >> $FILE_NAME.yatda
egrep "\"$REQUEST_THREAD_NAME" -A 2 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
echo >> $FILE_NAME.yatda

# This returns counts of the unique 20 top lines from all request thread stacks
echo "## Most common from first $SPECIFIED_LINE_COUNT lines of request threads ##" >> $FILE_NAME.yatda
egrep "\"$REQUEST_THREAD_NAME" -A `expr $SPECIFIED_LINE_COUNT + 1` $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
echo >> $FILE_NAME.yatda


# This returns counts of the top line from all thread stacks
echo "## Top lines of all threads ##" >> $FILE_NAME.yatda
grep "$ALL_THREAD_NAME" -A 2 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
echo >> $FILE_NAME.yatda

# This returns counts of the unique 20 top lines from all request thread stacks
echo "## Most common from first $ALL_LINE_COUNT lines of all threads ##" >> $FILE_NAME.yatda
grep "$ALL_THREAD_NAME" -A `expr $ALL_LINE_COUNT + 1` $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
