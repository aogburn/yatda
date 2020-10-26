#!/bin/bash
#
# Yatda is just Yet Another Thread Dump Analyzer.  It focuses on 
# providing quick JBoss EAP 7 specific statistics and known concerns.
#
# Usage: sh ./yatda.sh -f <THREAD_DUMP_FILE_NAME>
#    -f: thead dump file name
#    -t: specify a thread name to focus on
#    -s: specify a particular generic line indicating thread usage
#    -n: number of stack lines to focus on from specified threads
#    -a: number of stack lines to focus on from all threads
#

# default string references to search for generic EAP 7 request stats
DUMP_NAME="Full thread dump "
ALL_THREAD_NAME=" nid=0x"
REQUEST_THREAD_NAME="default task-"
REQUEST_TRACE="io.undertow.server.Connectors.executeRootHandler"
REQUEST_COUNT=0
SPECIFIED_THREAD_COUNT=0
SPECIFIED_USE_COUNT=0
SPECIFIED_LINE_COUNT=20
ALL_LINE_COUNT=10


# flags
while getopts r:t:s:n:a:f: flag
do
    case "${flag}" in
        r) REQUEST_THREAD_NAME=${OPTARG};;
        t) SPECIFIED_THREAD_NAME=${OPTARG};;
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

if [ "x$SPECIFIED_THREAD_NAME" != "x" ]; then
    echo >> $FILE_NAME.yatda
    SPECIFIED_THREAD_COUNT=`grep "$ALL_THREAD_NAME" $FILE_NAME | egrep "$SPECIFIED_THREAD_NAME" | wc -l`
    echo "Total number of $SPECIFIED_THREAD_NAME threads: " $SPECIFIED_THREAD_COUNT >> $FILE_NAME.yatda

    if [[ "x$SPECIFIED_TRACE" != x && $SPECIFIED_THREAD_COUNT -gt 0 ]]; then
        SPECIFIED_USE_COUNT=`grep "$SPECIFIED_TRACE" $FILE_NAME | wc -l`
        echo "Total number of in process $SPECIFIED_THREAD_NAME threads: " $SPECIFIED_USE_COUNT >> $FILE_NAME.yatda

        SPECIFIED_PERCENT=`printf %.2f "$((10**4 * $SPECIFIED_USE_COUNT / $SPECIFIED_THREAD_COUNT ))e-2" `
        echo "Percent of present $SPECIFIED_THREAD_NAME threads in use: " $SPECIFIED_PERCENT >> $FILE_NAME.yatda

        if [ $DUMP_COUNT -gt 1 ]; then
            echo "Average number of in process $SPECIFIED_THREAD_NAME threads per thread dump: " `expr $SPECIFIED_COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
            echo "Average number of $SPECIFIED_THREAD_COUNT threads per thread dump: " `expr $SPECIFIED_THREAD_COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
        fi
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


# check EJB strict max pool exhaustion
COUNT=`grep "at org.jboss.as.ejb3.pool.strictmax.StrictMaxPool.get" $FILE_NAME | wc -l`
if [ $COUNT -gt 0 ]; then
    echo >> $FILE_NAME.yatda
    echo $((i++)) ": The amount of threads waiting for an EJB instance in org.jboss.as.ejb3.pool.strictmax.StrictMaxPool.get is $COUNT.  This indicates an EJB instance pool needs to be increased for the load (https://access.redhat.com/solutions/255033).  Check other threads actively processing in org.jboss.as.ejb3.component.pool.PooledInstanceInterceptor.processInvocation to see if EJB instances are used up in any specific calls." >> $FILE_NAME.yatda
fi


# check datasource exhaustion
COUNT=`grep "at org.jboss.jca.core.connectionmanager.pool.api.Semaphore.tryAcquire" $FILE_NAME | wc -l`
if [ $COUNT -gt 0 ]; then
    echo >> $FILE_NAME.yatda
    echo $((i++)) ": The amount of threads waiting for a datasource connection in org.jboss.jca.core.connectionmanager.pool.api.Semaphore.tryAcquire is $COUNT.  This indicates a datasource pool needs to be increased for the load or connections are being leaked or used too long (https://access.redhat.com/solutions/17782)." >> $FILE_NAME.yatda
fi


# check log contention
COUNT=`grep "at org.jboss.logmanager.handlers.WriterHandler.doPublish" $FILE_NAME | wc -l`
if [ $COUNT -gt 0 ]; then
    echo >> $FILE_NAME.yatda
    echo $((i++)) ": The amount of threads in org.jboss.logmanager.handlers.WriterHandler.doPublish is $COUNT.  High amounts of threads here may indicate logging that is too verbose and/or log writes that are too slow.  Consider decreasing log verbosity or configure an async log handler (https://access.redhat.com/solutions/444033) to limit response time impacts from log writes." >> $FILE_NAME.yatda
fi


# check java.util.Arrays.copyOf calls
COUNT=`grep "at java.util.Arrays.copyOf" $FILE_NAME | wc -l`
if [ $COUNT -gt 0 ]; then
    echo >> $FILE_NAME.yatda
    echo $((i++)) ": The amount of threads in java.util.Arrays.copyOf is $COUNT.  Notable amounts of threads here or a significant time spent here in any thread may indicate a lot of time blocked in safe point pausing for GC because of little free heap space or the Array copies and other activity generating excessive amounts of temporary heap garbage.  GC logs should be reviewed to confirm or rule out GC performance concerns." >> $FILE_NAME.yatda
fi

echo >> $FILE_NAME.yatda
# end Findings


if [ $REQUEST_THREAD_COUNT -gt 0 ]; then
    # This returns counts of the top line from all request thread stacks
    echo "## Top lines of request threads ##" >> $FILE_NAME.yatda
    egrep "\"$REQUEST_THREAD_NAME" -A 2 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
    echo >> $FILE_NAME.yatda

    # This returns counts of the unique 20 top lines from all request thread stacks
    echo "## Most common from first $SPECIFIED_LINE_COUNT lines of request threads ##" >> $FILE_NAME.yatda
    egrep "\"$REQUEST_THREAD_NAME" -A `expr $SPECIFIED_LINE_COUNT + 1` $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
    echo >> $FILE_NAME.yatda
fi


if [ $SPECIFIED_THREAD_COUNT -gt 0 ]; then
    # This returns counts of the top line from all request thread stacks
    echo "## Top lines of $SPECIFIED_THREAD_NAME threads ##" >> $FILE_NAME.yatda
    egrep "\"$SPECIFIED_THREAD_NAME" -A 2 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
    echo >> $FILE_NAME.yatda

    # This returns counts of the unique 20 top lines from all request thread stacks
    echo "## Most common from first $SPECIFIED_LINE_COUNT lines of $SPECIFIED_THREAD_NAME threads ##" >> $FILE_NAME.yatda
    egrep "\"$SPECIFIED_THREAD_NAME" -A `expr $SPECIFIED_LINE_COUNT + 1` $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
    echo >> $FILE_NAME.yatda
fi


# This returns counts of the top line from all thread stacks
echo "## Top lines of all threads ##" >> $FILE_NAME.yatda
grep "$ALL_THREAD_NAME" -A 2 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
echo >> $FILE_NAME.yatda

# This returns counts of the unique 20 top lines from all request thread stacks
echo "## Most common from first $ALL_LINE_COUNT lines of all threads ##" >> $FILE_NAME.yatda
grep "$ALL_THREAD_NAME" -A `expr $ALL_LINE_COUNT + 1` $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda


# Focus on EAP boot threads
echo  >> $FILE_NAME.yatda
echo "## EAP BOOT THREAD INFO ##" >> $FILE_NAME.yatda
echo  >> $FILE_NAME.yatda
COUNT=`grep "ServerService Thread Pool " $FILE_NAME | wc -l`
if [ $COUNT -gt 0 ]; then
    echo "Number of ServerService threads: " $COUNT >> $FILE_NAME.yatda
    if [ $DUMP_COUNT -gt 1 ]; then
        echo "Average number of ServerService threads per thread dump: " `expr $COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
    fi
    echo "## Most common from first 10 lines of ServerService threads ##" >> $FILE_NAME.yatda
    grep "ServerService Thread Pool " -A 11 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
    echo  >> $FILE_NAME.yatda
fi

COUNT=`grep "MSC service thread " $FILE_NAME | wc -l`
if [ $COUNT -gt 0 ]; then
    echo "Number of MSC service threads: " $COUNT >> $FILE_NAME.yatda

    TASK_COUNT=`grep "org.jboss.msc.service.ServiceControllerImpl\\$ControllerTask.run" $FILE_NAME | wc -l`
    echo "Total number of running ControllerTasks: " $TASK_COUNT >> $FILE_NAME.yatda

    MSC_PERCENT=`printf %.2f "$((10**4 * $TASK_COUNT / $COUNT ))e-2" `
    echo "Percent of present MSC threads in use: " $MSC_PERCENT >> $FILE_NAME.yatda


    if [ $DUMP_COUNT -gt 1 ]; then
        echo "Average number of MSC service threads per thread dump: " `expr $COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
    fi
    if [[ `expr $COUNT % 2` == 0 ]]; then
        NUMBER_CORES=`expr $COUNT / 2`
        NUMBER_CORES=`expr $NUMBER_CORES / $DUMP_COUNT`
        echo "*The number of present MSC threads is a multple of 2 so this may be a default thread pool size fitting $NUMBER_CORES CPU cores. If these are all in use during start up, the thread pool may need to be increased via -Dorg.jboss.server.bootstrap.maxThreads and -Djboss.msc.max.container.threads properties per https://access.redhat.com/solutions/508413." >> $FILE_NAME.yatda
    fi
    echo "## Most common from first 10 lines of MSC threads ##" >> $FILE_NAME.yatda
    grep "MSC service thread " -A 11 $FILE_NAME | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
fi
