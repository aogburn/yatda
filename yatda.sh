#!/bin/bash
#
# Yatda is just Yet Another Thread Dump Analyzer.  It focuses on 
# providing quick JBoss EAP 7+ specific statistics and known concerns.
#
# Usage: sh ./yatda.sh <THREAD_DUMP_FILE_NAME>
LC_ALL=C
# default string references to search for generic EAP 7+ request stats
DUMP_NAME="Full thread dump "
ALL_THREAD_NAME=" nid=0x"
REQUEST_THREAD_NAME="default task-"
REQUEST_TRACE="io.undertow.server.Connectors.executeRootHandler"
EJB_TRACE="org.jboss.ejb.protocol.remote.EJBServerChannel\$ReceiverImpl.handleInvocationRequest"
IDLE_TRACE="(a org.jboss.threads.EnhancedQueueExecutor)|ThreadPoolExecutor.getTask"
REQUEST_COUNT=0
SPECIFIED_THREAD_COUNT=0
SPECIFIED_USE_COUNT=0
SPECIFIED_LINE_COUNT=20
ALL_LINE_COUNT=10
CPU_THRESHOLD=40
GC_CPU_THRESHOLD=1
JAVA_11="false"
FILE_PREFIX="file://"

# Colors
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

VALID_UPDATE_MODES=(force ask never)

YATDA_SH="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

usage() {
    if [ ! "x$1" = "x" ]; then
        echo
        echo -e "$1"
        echo
    fi
    echo "Usage:"
    echo " sh ./$YATDA_SH <options> <THREAD_DUMP_FILE>"
    echo
    echo "Yatda is just Yet Another Thread Dump Analyzer.  It focuses on "
    echo "providing quick JBoss EAP 7+ specific statistics and known concerns."
    echo
    echo "Options:"
    echo " -r, --requestThread             specify a name for request threads instead of 'default task'"
    echo " -t, --specifiedThread           specify a thread name to focus on"
    echo " -s, --specifiedTrace            specify a particular generic line indicating thread usage"
    echo " -n, --specifiedLineCount        number of stack lines to focus on from request or specified threads"
    echo " -a, --allLineCount              number of stack lines to focus on from all threads"
    echo " -c, --cpuThreshold              threshold of %CPU use for non-GC threads from java 11+ dumps"
    echo " -g, --gcCpuThreshold            threshold of %CPU use for GC threads from java 11+ dumps"
    echo " -u, --updateMode                the update mode to use, one of [${VALID_UPDATE_MODES[*]}], default: force"
    echo " -h, --help                      show this help"
}

# is_valid_option <argument> <array> <option>
is_valid_option() {
    ARGUMENT=$1
    ARRAY=$2
    OPTION=$3

    if [[ ! " ${ARRAY[*]} " =~ " ${ARGUMENT} " ]]; then
        echo "${YATDA_SH}: invalid argument '$ARGUMENT' for option '$OPTION', must be one of [${ARRAY[*]}]"
        return 22 # -> Invalid Argument
    else
        return 0  # -> Success
    fi
}

# source a global $HOME/.yatda/config if available
if [ -d $HOME/.yatda ] && [ -f $HOME/.yatda/config ]; then
    source $HOME/.yatda/config
fi

# set required variables with default values, if not set in $HOME/.yatda/config
[ -z $UPDATE_MODE ] && UPDATE_MODE="force"
[ -z $MD5 ] && MD5="https://raw.githubusercontent.com/aogburn/yatda/master/md5"
[ -z $REMOTE_YATDA_SH ] && REMOTE_YATDA_SH="https://raw.githubusercontent.com/aogburn/yatda/master/yatda.sh"

# parse the cli options
OPTS=$(getopt -o 'r:,t:,s:,n:,a:,c:,g:,h,u:' --long 'requestThread,specifiedThread,specifiedTrace,specifiedLineCount,allLineCount,cpuThreshold,gcCpuThreshold,help,updateMode:' -n "${YATDA_SH}" -- "$@")

# if getopt has a returned an error, exit with the return code of getopt
res=$?; [ $res -gt 0 ] && exit $res

eval set -- "$OPTS"
unset OPTS

# flags
while true; do
    case "$1" in
        '-r'|'--requestThread')
            REQUEST_THREAD_NAME=$2
            shift 2
            ;;
        '-t'|'--specifiedThread')
            SPECIFIED_THREAD_NAME=$2
            shift 2
            ;;
        '-s'|'--specifiedTrace')
            SPECIFIED_TRACE=$2
            shift 2
            ;;
        '-n'|'--specifiedLineCount')
            SPECIFIED_LINE_COUNT=$2
            shift 2
            ;;
        '-a'|'--allLineCount')
            ALL_LINE_COUNT=$2
            shift 2
            ;;
        '-c'|'--cpuThreshold')
            CPU_THRESHOLD=$2
            shift 2
            ;;
        '-g'|'--gcCpuThreshold')
            GC_CPU_THRESHOLD=$2
            shift 2
            ;;
        '-h'|'--help')
            usage; exit 0; shift
            ;;
        '-u'|'--updateMode')
            is_valid_option "$2" "${VALID_UPDATE_MODES[*]}" "-u, --update"
            result=$?
            if [ $result -gt 0 ]; then
                exit $result
            fi
            UPDATE_MODE=$2
            shift 2
            ;;
        '--') shift; break;;
        * )
            echo "Invalid Option: $1"
            echo ""
            usage; exit; shift
            ;;
    esac
done

# check if filename is given
if [ $# -eq 0 ]; then
    echo "Please specify file name"
    exit 22
fi

# after parsing the options, '$1' is the file name
FILE_NAME=$1
FULL_FILE_NAME=`readlink -f $FILE_NAME`

# Check for a new yatda.sh if UPDATE_MODE is not 'never'
DIR=`dirname "$(readlink -f "$0")"`
if [ "$UPDATE_MODE" != "never" ]; then
    echo "Checking script update. Use option '-u never' to skip the update check"

    if [[ "$OSTYPE" == "darwin"* ]]; then
       SUM=`md5 -r $DIR/$YATDA_SH | awk '{ print $1 }'`
    else
       SUM=`md5sum $DIR/$YATDA_SH | awk '{ print $1 }'`
    fi
    
    NEWSUM=`curl -s $MD5 | awk '{ print $1 }'`

    if [ "x$NEWSUM" != "x" ]; then
        if [ $SUM != $NEWSUM ]; then

            echo
            echo "$YATDA_SH - $SUM - local"
            echo "$YATDA_SH - $NEWSUM - remote"

            if [ "$UPDATE_MODE" = "ask" ]; then
                while true; do
                    echo
                    read -p "A new version of $YATDA_SH is available, do you want to update?" yn
                    case $yn in
                        [Yy]* ) UPDATE="true"; break;;
                        [Nn]* ) UPDATE="false"; break;;
                        * ) echo "Choose yes or no.";;
                    esac
                done
            else
                UPDATE="true"
            fi

            if [ "$UPDATE" = "true" ]; then
                echo "Downloading new version. Please re-run $YATDA_SH."
                wget -q $REMOTE_YATDA_SH -O $DIR/$YATDA_SH
                exit
            fi
        fi
    fi

    echo
    echo "Checks complete."
fi

if [ "x$FILE_NAME" = "x" ]; then
    usage "${RED}No <THREAD_DUMP_FILE> provided.${NC}"
    exit
elif [ ! -f "$FILE_NAME" ]; then
    usage "${YELLOW}<THREAD_DUMP_FILE> '$FILE_NAME' does not exist.${NC}"
    exit
fi

TRIM_FILE=$FILE_NAME.yatda-tmp.trim

sed '/^Found .* Java-level deadlock/,/^Found [0-9] deadlock/d' $FILE_NAME > $TRIM_FILE

# Use different thread details if it looks like a thread dump from JBossWeb/Tomcat
if [ `grep 'org.apache.tomcat.util' $TRIM_FILE | wc -l` -gt 0 ]; then
    echo "Treating as dump from JBossWeb or Tomcat"
        if [ "$REQUEST_THREAD_NAME" == "default task-" ]; then
            REQUEST_THREAD_NAME="http-|ajp-"
        fi
        if [ "$REQUEST_TRACE" == "io.undertow.server.Connectors.executeRootHandler" ]; then
            REQUEST_TRACE="org.apache.catalina.connector.CoyoteAdapter.service"
        fi
fi


echo -e "${RED}### Summarizing $FILE_PREFIX$FULL_FILE_NAME - see file://$FULL_FILE_NAME.yatda for more info ###${NC}"
echo "### Summary of $FILE_PREFIX$FULL_FILE_NAME ###" > $FILE_NAME.yatda

# Here we'll whip up some thread usage stats

DUMP_COUNT=`grep "$DUMP_NAME" $TRIM_FILE | wc -l`
echo -en "${GREEN}"
echo "Number of thread dumps: " $DUMP_COUNT | tee -a $FILE_NAME.yatda

echo -en "${YELLOW}"
{
echo "Dump dates:"
grep -B 1 "Full thread dump" $TRIM_FILE | grep "20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]" > $FILE_NAME.yatda-tmp.dates
if [ $DUMP_COUNT -gt 20 ]; then
    head -n 10 $FILE_NAME.yatda-tmp.dates
    echo "..."
    tail -n 10 $FILE_NAME.yatda-tmp.dates
else
    cat $FILE_NAME.yatda-tmp.dates
fi
} | tee -a $FILE_NAME.yatda

grep "$ALL_THREAD_NAME" $TRIM_FILE > $FILE_NAME.yatda-tmp.allthreads
THREAD_COUNT=`cat $FILE_NAME.yatda-tmp.allthreads | wc -l`

echo -en "${GREEN}"
echo "Total number of threads: " $THREAD_COUNT | tee -a $FILE_NAME.yatda

REQUEST_THREAD_COUNT=`cat $FILE_NAME.yatda-tmp.allthreads | grep -E "$REQUEST_THREAD_NAME" | wc -l`
echo -en "${YELLOW}"
echo "Total number of request threads: " $REQUEST_THREAD_COUNT | tee -a $FILE_NAME.yatda

if [ $REQUEST_THREAD_COUNT -gt 0 ]; then
    sed -E -n "/$REQUEST_THREAD_NAME/,/java\.lang\.Thread\.run/p" $TRIM_FILE > $TRIM_FILE.requests
    REQUEST_COUNT=`grep "$REQUEST_TRACE" $TRIM_FILE.requests | wc -l`
    echo -en "${GREEN}"
    echo "Total number of in process requests: " $REQUEST_COUNT | tee -a $FILE_NAME.yatda

    EJB_COUNT=`grep "$EJB_TRACE" $TRIM_FILE.requests | wc -l`
    echo -en "${YELLOW}"
    echo "Total number of in process remote EJBs: " $EJB_COUNT | tee -a $FILE_NAME.yatda

    IDLE_COUNT=`grep -E "$IDLE_TRACE" $TRIM_FILE.requests | wc -l`
    echo -en "${GREEN}"
    echo "Total number of idle request threads: " $IDLE_COUNT | tee -a $FILE_NAME.yatda

    IN_USE_COUNT=`expr $REQUEST_THREAD_COUNT - $IDLE_COUNT`
    echo -en "${YELLOW}"
    echo "Total number of in use request threads (requests, EJBs, or other tasks): " $IN_USE_COUNT | tee -a $FILE_NAME.yatda

    REQUEST_PERCENT=`printf %.2f "$((10**4 * $REQUEST_COUNT / $REQUEST_THREAD_COUNT ))e-2" `
    echo -en "${GREEN}"
    echo "Percent of present request threads in use for requests: " $REQUEST_PERCENT | tee -a $FILE_NAME.yatda

    EJB_PERCENT=`printf %.2f "$((10**4 * $EJB_COUNT / $REQUEST_THREAD_COUNT ))e-2" `
    echo -en "${YELLOW}"
    echo "Percent of present request threads in use for remote EJBs: " $EJB_PERCENT | tee -a $FILE_NAME.yatda

    IDLE_PERCENT=`printf %.2f "$((10**4 * $IDLE_COUNT / $REQUEST_THREAD_COUNT ))e-2" `
    echo -en "${GREEN}"
    echo "Percent of present idle request threads: " $IDLE_PERCENT | tee -a $FILE_NAME.yatda

    IN_USE_PERCENT=`printf %.2f "$((10**4 * $IN_USE_COUNT / $REQUEST_THREAD_COUNT ))e-2" `
    echo -en "${YELLOW}"
    echo "Percent of present request threads in use (requests, EJBs, or other tasks): " $IN_USE_PERCENT | tee -a $FILE_NAME.yatda


    if [ $DUMP_COUNT -gt 1 ]; then
        echo -en "${GREEN}"
        echo "Average number of in process requests per thread dump: " `expr $REQUEST_COUNT / $DUMP_COUNT` | tee -a $FILE_NAME.yatda
        echo -en "${YELLOW}"
        echo "Average number of in process remote EJBs per thread dump: " `expr $EJB_COUNT / $DUMP_COUNT` | tee -a $FILE_NAME.yatda
        echo -en "${GREEN}"
        echo "Average number of idle request threads per thread dump: " `expr $IDLE_COUNT / $DUMP_COUNT` | tee -a $FILE_NAME.yatda
        echo -en "${YELLOW}"
        echo "Average number of in use request threads per thread dump: " `expr $IN_USE_COUNT / $DUMP_COUNT` | tee -a $FILE_NAME.yatda
        echo -en "${GREEN}"
        echo "Average number of request threads per thread dump: " `expr $REQUEST_THREAD_COUNT / $DUMP_COUNT` | tee -a $FILE_NAME.yatda
        echo -en "${YELLOW}"
        echo "Average number of threads per thread dump: " `expr $THREAD_COUNT / $DUMP_COUNT` | tee -a $FILE_NAME.yatda
    fi
fi

if [ "x$SPECIFIED_THREAD_NAME" != "x" ]; then
    echo | tee -a $FILE_NAME.yatda
    sed -E -n "/$SPECIFIED_THREAD_NAME/,/java\.lang\.Thread\.run/p" $TRIM_FILE > $TRIM_FILE.specifics

    SPECIFIED_THREAD_COUNT=`cat $FILE_NAME.yatda-tmp.allthreads | grep -E "$SPECIFIED_THREAD_NAME" | wc -l`
    echo "Total number of $SPECIFIED_THREAD_NAME threads: " $SPECIFIED_THREAD_COUNT | tee -a $FILE_NAME.yatda

    if [[ "x$SPECIFIED_TRACE" != x && $SPECIFIED_THREAD_COUNT -gt 0 ]]; then
        SPECIFIED_USE_COUNT=`grep "$SPECIFIED_TRACE" $TRIM_FILE.specifics | wc -l`
        echo "Total number of in process $SPECIFIED_THREAD_NAME threads: " $SPECIFIED_USE_COUNT | tee -a $FILE_NAME.yatda

        SPECIFIED_PERCENT=`printf %.2f "$((10**4 * $SPECIFIED_USE_COUNT / $SPECIFIED_THREAD_COUNT ))e-2" `
        echo "Percent of present $SPECIFIED_THREAD_NAME threads in use: " $SPECIFIED_PERCENT | tee -a $FILE_NAME.yatda

        if [ $DUMP_COUNT -gt 1 ]; then
            echo "Average number of in process $SPECIFIED_THREAD_NAME threads per thread dump: " `expr $SPECIFIED_THREAD_COUNT / $DUMP_COUNT` | tee -a $FILE_NAME.yatda
        fi
    fi

    if [ $DUMP_COUNT -gt 1 ]; then
            echo "Average number of $SPECIFIED_THREAD_NAME threads per thread dump: " `expr $SPECIFIED_THREAD_COUNT / $DUMP_COUNT` | tee -a $FILE_NAME.yatda
    fi
fi
#end stats


# Here we'll try to point out any specific known issues
echo | tee -a $FILE_NAME.yatda
echo -en "${RED}"
echo "## Specific findings ##" | tee -a $FILE_NAME.yatda
echo -en "${NC}"
i=1

# request thread default and core count
if [[ $REQUEST_THREAD_COUNT -gt 0 && `expr $REQUEST_THREAD_COUNT % 16` == 0 ]]; then
NUMBER_CORES=`expr $REQUEST_THREAD_COUNT / 16`
NUMBER_CORES=`expr $NUMBER_CORES / $DUMP_COUNT`
    echo | tee -a $FILE_NAME.yatda
    echo $i": The number of present request threads is a multiple of 16 so this may be a default thread pool size fitting $NUMBER_CORES CPU cores." | tee -a $FILE_NAME.yatda
    i=$((i+1))
fi


# request thread exhaustion
if [ $REQUEST_COUNT -gt 0 ] && [ $REQUEST_COUNT == $REQUEST_THREAD_COUNT ]; then
    echo | tee -a $FILE_NAME.yatda
    echo $i": The number of processing requests is equal to the number of present request threads.  This may indicate thread pool exhaustion so the task-max-threads may need to be increased (https://access.redhat.com/solutions/2455451).  Spikes in CPU on the I/O threads can also be a side effect of this thread exhaustion per https://access.redhat.com/solutions/7031598, which can be avoided with its noted workarounds." | tee -a $FILE_NAME.yatda
    i=$((i+1))
fi


# check EJB strict max pool exhaustion
COUNT=`grep "at org.jboss.as.ejb3.pool.strictmax.StrictMaxPool.get" $TRIM_FILE | wc -l`
if [ $COUNT -gt 0 ]; then
    echo | tee -a $FILE_NAME.yatda
    echo $i": The amount of threads waiting for an EJB instance in org.jboss.as.ejb3.pool.strictmax.StrictMaxPool.get is $COUNT.  This indicates an EJB instance pool needs to be increased for the load (https://access.redhat.com/solutions/255033).  Check other threads actively processing in org.jboss.as.ejb3.component.pool.PooledInstanceInterceptor.processInvocation to see if EJB instances are used up in any specific calls." | tee -a $FILE_NAME.yatda
    i=$((i+1))
fi


# check datasource exhaustion
COUNT=`grep "at org.jboss.jca.core.connectionmanager.pool.api.Semaphore.tryAcquire" $TRIM_FILE | wc -l`
if [ $COUNT -gt 0 ]; then
    echo | tee -a $FILE_NAME.yatda
    echo $i": The amount of threads waiting for a datasource connection in org.jboss.jca.core.connectionmanager.pool.api.Semaphore.tryAcquire is $COUNT.  This indicates a datasource pool needs to be increased for the load or connections are being leaked or used too long (https://access.redhat.com/solutions/17782)." | tee -a $FILE_NAME.yatda
    i=$((i+1))
fi


# check log contention
COUNT=`grep "at org.jboss.logmanager.handlers.WriterHandler.doPublish" $TRIM_FILE | wc -l`
if [ $COUNT -gt 0 ]; then
    echo | tee -a $FILE_NAME.yatda
    echo $i": The amount of threads in org.jboss.logmanager.handlers.WriterHandler.doPublish is $COUNT.  High amounts of threads here may indicate logging that is too verbose and/or log writes that are too slow.  Consider decreasing log verbosity or configure an async log handler (https://access.redhat.com/solutions/444033) to limit response time impacts from log writes." | tee -a $FILE_NAME.yatda
    i=$((i+1))
fi


# check java.util.Arrays.copyOf calls
COUNT=`grep "at java.util.Arrays.copyOf" $TRIM_FILE | wc -l`
if [ $COUNT -gt 0 ]; then
    echo | tee -a $FILE_NAME.yatda
    echo $i": The amount of threads in java.util.Arrays.copyOf is $COUNT.  Notable amounts of threads here or a significant time spent here in any thread may indicate a lot of time blocked in safe point pausing for GC because of little free heap space or the Array copies and other activity generating excessive amounts of temporary heap garbage.  GC logs should be reviewed to confirm or rule out GC performance concerns." | tee -a $FILE_NAME.yatda
    i=$((i+1))
fi

echo | tee -a $FILE_NAME.yatda
# end Findings


if [ $REQUEST_THREAD_COUNT -gt 0 ]; then
    # This returns states of all request threads
    echo -en "${RED}"
    echo "## Request thread states ##" | tee -a $FILE_NAME.yatda
    echo -en "${NC}"
    awk -v name="$REQUEST_THREAD_NAME" '$0~name {getline; print}' $TRIM_FILE.requests | sed -E 's/java.lang.Thread.State: (.*)/\1/g' | sort | uniq -c | sort -nr | tee -a $FILE_NAME.yatda
    echo | tee -a $FILE_NAME.yatda

    # This returns counts of the top line from all request thread stacks with their state
    echo -en "${RED}"
    echo "## Top lines of request threads ##" | tee -a $FILE_NAME.yatda
    echo -en "${NC}"
    awk -v name="$REQUEST_THREAD_NAME" '$0~name {getline; printf $0; getline; print}' $TRIM_FILE.requests | sed -E 's/java.lang.Thread.State: (.*)/\1/g' | sort | uniq -c | sort -nr | tee -a $FILE_NAME.yatda
    echo | tee -a $FILE_NAME.yatda

    # This returns counts of the unique 20 top lines from all request thread stacks
    echo -en "${RED}"
    echo "## Most common from first $SPECIFIED_LINE_COUNT lines of request threads ##" | tee -a $FILE_NAME.yatda
    echo -en "${NC}"
    grep -E "$REQUEST_THREAD_NAME" -A `expr $SPECIFIED_LINE_COUNT + 1` $TRIM_FILE.requests | grep -E " at |	at " | sort | uniq -c | sort -nr | tee -a $FILE_NAME.yatda
    echo | tee -a $FILE_NAME.yatda

    # This returns monitor stats from all request thread stacks
    echo -en "${RED}"
    echo "## Most common monitors of request threads ##" | tee -a $FILE_NAME.yatda
    echo -en "${NC}"
    grep -E "\- .*wait.*<0x.*" $TRIM_FILE.requests | grep -v "org.jboss.threads.EnhancedQueueExecutor" | sort | uniq -c | sort -nr > $FILE_NAME.yatda-tmp.monitors
    while read -r line; do
        {
            echo $line
            echo "Locked by:"
            MONITOR_ID=`echo $line | sed -E 's/.*<0x(.*)>.*/\1/g'`
            tac $TRIM_FILE.requests | sed -E -n "/locked <0x$MONITOR_ID/,/nid=/p" | tac
            #MONITOR_OWNERS=`echo $MONITOR_OWNERS | sed -E 's/.*("default task-.*").*/\1/g'`
            echo
        } | tee -a $FILE_NAME.yatda
    done < $FILE_NAME.yatda-tmp.monitors

#sed -E -n "/$REQUEST_THREAD_NAME/,/java\.lang\.Thread\.run/p" $TRIM_FILE > $TRIM_FILE.requests
fi


if [ $SPECIFIED_THREAD_COUNT -gt 0 ]; then
    # This returns states of all specified threads
    echo -en "${RED}"
    echo "## Specified thread states ##" | tee -a $FILE_NAME.yatda
    echo -en "${NC}"
    awk -v name="$SPECIFIED_THREAD_NAME" '$0~name {getline; print}' $TRIM_FILE.requests | sed -E 's/java.lang.Thread.State: (.*)/\1/g' | sort | uniq -c | sort -nr | tee -a $FILE_NAME.yatda
    echo | tee -a $FILE_NAME.yatda

    # This returns counts of the top line from all specified thread stacks with their state
    echo -en "${RED}"
    echo "## Top lines of $SPECIFIED_THREAD_NAME threads ##" | tee -a $FILE_NAME.yatda
    echo -en "${NC}"
    awk -v name="$SPECIFIED_THREAD_NAME" '$0~name {getline; printf $0; getline; print}' $TRIM_FILE.specifics | sed -E 's/java.lang.Thread.State: (.*)/\1/g' | sort | uniq -c | sort -nr | tee -a $FILE_NAME.yatda
    echo | tee -a $FILE_NAME.yatda

    # This returns counts of the unique 20 top lines from all specified thread stacks
    echo -en "${RED}"
    echo "## Most common from first $SPECIFIED_LINE_COUNT lines of $SPECIFIED_THREAD_NAME threads ##" | tee -a $FILE_NAME.yatda
    echo -en "${NC}"
    grep -E "$SPECIFIED_THREAD_NAME" -A `expr $SPECIFIED_LINE_COUNT + 1` $TRIM_FILE.specifics | grep -E " at |	at " | sort | uniq -c | sort -nr | tee -a $FILE_NAME.yatda
    echo | tee -a $FILE_NAME.yatda
fi

# This returns states of all threads
echo "## All thread states ##" >> $FILE_NAME.yatda
echo -en "${NC}"
awk -v name="$ALL_THREAD_NAME" '$0~name {getline; print}' $TRIM_FILE.requests | sed -E 's/java.lang.Thread.State: (.*)/\1/g' | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
echo >> $FILE_NAME.yatda

# This returns counts of the top line from all thread stacks with their state
echo "## Top lines of all threads ##" >> $FILE_NAME.yatda
awk -v name="$ALL_THREAD_NAME" '$0~name {getline; printf $0; getline; print}' $TRIM_FILE | grep "Thread.State" | sed -E 's/java.lang.Thread.State: (.*)/\1/g' | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
echo >> $FILE_NAME.yatda

# This returns counts of the unique 20 top lines from all request thread stacks
echo "## Most common from first $ALL_LINE_COUNT lines of all threads ##" >> $FILE_NAME.yatda
grep "$ALL_THREAD_NAME" -A `expr $ALL_LINE_COUNT + 1` $TRIM_FILE | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda


# Focus on EAP boot threads
echo  >> $FILE_NAME.yatda
echo "## EAP BOOT THREAD INFO ##" >> $FILE_NAME.yatda
echo  >> $FILE_NAME.yatda
COUNT=`grep "ServerService Thread Pool " $TRIM_FILE | wc -l`
if [ $COUNT -gt 0 ]; then
    echo "Number of ServerService threads: " $COUNT >> $FILE_NAME.yatda
    if [ $DUMP_COUNT -gt 1 ]; then
        echo "Average number of ServerService threads per thread dump: " `expr $COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
    fi
    echo "## Most common from first 10 lines of ServerService threads ##" >> $FILE_NAME.yatda
    grep "ServerService Thread Pool " -A 11 $TRIM_FILE | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
    echo  >> $FILE_NAME.yatda
fi

COUNT=`grep "MSC service thread " $TRIM_FILE | wc -l`
if [ $COUNT -gt 0 ]; then
    echo "Number of MSC service threads: " $COUNT >> $FILE_NAME.yatda

    TASK_COUNT=`grep "org.jboss.msc.service.ServiceControllerImpl\\$ControllerTask.run" $TRIM_FILE | wc -l`
    echo "Total number of running ControllerTasks: " $TASK_COUNT >> $FILE_NAME.yatda

    MSC_PERCENT=`printf %.2f "$((10**4 * $TASK_COUNT / $COUNT ))e-2" `
    echo "Percent of present MSC threads in use: " $MSC_PERCENT >> $FILE_NAME.yatda


    if [ $DUMP_COUNT -gt 1 ]; then
        echo "Average number of MSC service threads per thread dump: " `expr $COUNT / $DUMP_COUNT` >> $FILE_NAME.yatda
    fi
    if [[ `expr $COUNT % 2` == 0 ]]; then
        NUMBER_CORES=`expr $COUNT / 2`
        NUMBER_CORES=`expr $NUMBER_CORES / $DUMP_COUNT`
        echo "*The number of present MSC threads is a multiple of 2 so this may be a default thread pool size fitting $NUMBER_CORES CPU cores. If these are all in use during start up, the thread pool may need to be increased via -Dorg.jboss.server.bootstrap.maxThreads and -Djboss.msc.max.container.threads properties per https://access.redhat.com/solutions/508413." >> $FILE_NAME.yatda
    fi
    echo "## Most common from first 10 lines of MSC threads ##" >> $FILE_NAME.yatda
    grep "MSC service thread " -A 11 $TRIM_FILE | grep "at " | sort | uniq -c | sort -nr >> $FILE_NAME.yatda
fi


# Handle java 11+ dump differently to process addtional CPU
if [ `grep "$DUMP_NAME" $TRIM_FILE | grep -E "VM \(1[1-9]\." | wc -l` -gt 0 ]; then
    JAVA_11="true"
fi


if [ "$JAVA_11" == "true" ]; then
    # Calculate GC thread CPU deltas
    #GC thread names
    #ParGC Thread#
    #VM Thread
    #"GC Thread#n" os_prio=0 cpu=204.85ms elapsed=7.43s tid=0x000055758eef2800 nid=0x3feb runnable
    #"G1 Main Marker" os_prio=0 cpu=6.53ms elapsed=7.43s tid=0x000055758eefb000 nid=0x3fec runnable
    #"G1 Conc#n" os_prio=0 cpu=518.97ms elapsed=7.43s tid=0x000055758eefd000 nid=0x3fed runnable
    #"G1 Refine#n" os_prio=0 cpu=5.14ms elapsed=7.43s tid=0x000055758ef8b000 nid=0x3fee runnable
    #"G1 Young RemSet Sampling"

    echo
    echo -en "${RED}"
    echo "## Java 11+ GC CPU summary of $FILE_NAME - check $FILE_NAME.yatda-gc-cpu for more details of any high GC consumers above the $GC_CPU_THRESHOLD% GC CPU threshold (-g flag to adjust) ##"
    echo -en "${NC}"
    echo "## Java 11+ GC CPU summary of $FILE_NAME ##" > $FILE_NAME.yatda-gc-cpu
    echo "## high GC consumers above the $GC_CPU_THRESHOLD% GC CPU threshold (-g flag to adjust) ## ##" >> $FILE_NAME.yatda-gc-cpu

    GC_THREAD_NAMES="VM Thread|GC Thread|G1 "
    MAX_GC_PERCENTAGE=0
    MAX_GC_DELTA_PERCENTAGE=0

    MAX_NON_GC_PERCENTAGE=0
    MAX_NON_GC_DELTA_PERCENTAGE=0

    grep -B 1 "$DUMP_NAME" $TRIM_FILE | grep -E "^20[0-9][0-9]\-" > $FILE_NAME.yatda-tmp.timestamps
    grep -E "\"$GC_THREAD_NAMES" $FILE_NAME.yatda-tmp.allthreads | sed -E 's/^"(.*)" os_prio=.*/\1/g' | sort | uniq > $FILE_NAME.yatda-tmp.gc-threads
    COUNT=`cat $FILE_NAME.yatda-tmp.gc-threads | wc -l`
    i=1
    while read -r line ; do
        echo -en "${YELLOW}"
        echo "   $i. $line CPU summary" >> $FILE_NAME.yatda-gc-cpu
        echo -en "${NC}"
        NEW_CPU=""
        NEW_ELAPSED=""
        while read -r line2; do
            OLD_CPU=$NEW_CPU
            OLD_ELAPSED=$NEW_ELAPSED
            NEW_CPU=`echo $line2 | sed -E 's/^.*cpu=([0-9]+)\..*/\1/g'`
            #converted elapsed from s to ms
            NEW_ELAPSED="`echo $line2 | sed -E 's/^.*elapsed=([0-9]+)\.([0-9][0-9]).*/\1\2/g'`0"
            # trim any leading 0
            NEW_ELAPSED="`echo $NEW_ELAPSED | sed -E 's/^0(.*)/\1/g'`"


            GC_PERCENTAGE=`printf %.0f "$((10**4 * $NEW_CPU / $NEW_ELAPSED ))e-2" `
            if [ $GC_PERCENTAGE -gt $MAX_GC_PERCENTAGE ]; then
                MAX_GC_PERCENTAGE=$GC_PERCENTAGE
                MAX_GC_LINE=$line2
            fi

            if [ "x$OLD_CPU" != "x" ]; then
                GC_DELTA_PERCENTAGE=`printf %.0f "$((10**4 * ($NEW_CPU - $OLD_CPU) / ($NEW_ELAPSED - $OLD_ELAPSED)))e-2" `
                if [ $GC_DELTA_PERCENTAGE -gt $MAX_GC_DELTA_PERCENTAGE ]; then
                    MAX_GC_DELTA_PERCENTAGE=$GC_DELTA_PERCENTAGE
                    MAX_GC_DELTA_LINE=$line2
                fi

                # report GC consumer above our $GC_CPU_THRESHOLD
                if [ $GC_DELTA_PERCENTAGE -gt $GC_CPU_THRESHOLD ]; then
                    echo "------------------------------------------------------------------------------" >> $FILE_NAME.yatda-gc-cpu
                    THREAD_LINE="`echo $line2 | sed -E 's/^.*cpu=(.*) nid=.*/\1/g'`"
                    #THREAD_LINE="`echo $line2 | sed -E 's/^"(.*)"(.*)/\\"\1\\"\2/g'`"
                    #get the prior time stamp
                    grep -E "($THREAD_LINE)|^20[0-9][0-9]\-" $TRIM_FILE | grep -B 1 "$THREAD_LINE" >> $FILE_NAME.yatda-gc-cpu
                    #sed "${i}q;d" $FILE_NAME.yatda-tmp.timestamps >> $FILE_NAME.yatda-gc-cpu
                    echo "TOTAL CPU: $NEW_CPU ms ELAPSED: $NEW_ELAPSED ms PERCENTAGE: $GC_PERCENTAGE" >> $FILE_NAME.yatda-gc-cpu
                    echo "DELTA CPU: `expr $NEW_CPU - $OLD_CPU` ms ELAPSED: `expr $NEW_ELAPSED - $OLD_ELAPSED` ms PERCENTAGE: $GC_DELTA_PERCENTAGE" >> $FILE_NAME.yatda-gc-cpu
                    echo "------------------------------------------------------------------------------" >> $FILE_NAME.yatda-gc-cpu
                    echo >> $FILE_NAME.yatda-gc-cpu
                fi
            fi
        done < <(grep "\"$line\"" $FILE_NAME.yatda-tmp.allthreads)
        printf "$i of $COUNT GC threads done\033[0K\r"
        i=$((i+1))
    done < <(cat $FILE_NAME.yatda-tmp.gc-threads)

    echo >> $FILE_NAME.yatda-gc-cpu
    echo "Max total CPU percent of a GC thread: $MAX_GC_PERCENTAGE" | tee -a $FILE_NAME.yatda-gc-cpu
    echo "    $MAX_GC_LINE" | tee -a $FILE_NAME.yatda-gc-cpu
    echo "Max CPU percent between dumps of a GC thread: $MAX_GC_DELTA_PERCENTAGE" | tee -a $FILE_NAME.yatda-gc-cpu
    echo "    $MAX_GC_DELTA_LINE" | tee -a $FILE_NAME.yatda-gc-cpu


    # Calculate non-GC thread CPU deltas
    echo 
    echo -en "${RED}"
    echo "## Java 11+ non-GC CPU summary of $FILE_NAME - check $FILE_NAME.yatda-cpu for more details of any high consumers above the $CPU_THRESHOLD% CPU threshold (-c flag to adjust) ##"
    echo -en "${NC}"
    echo "## Java 11+ non-GC thread CPU summary of $FILE_NAME ##" > $FILE_NAME.yatda-cpu
    echo "## high consumers above the $CPU_THRESHOLD% CPU threshold (-c flag to adjust) ## ##" >> $FILE_NAME.yatda-cpu
    echo >> $FILE_NAME.yatda-cpu

    grep -v -E "\"$GC_THREAD_NAMES" $FILE_NAME.yatda-tmp.allthreads | sed -E 's/^".* nid=0x([[:alnum:]]*) .*/0x\1/g' | sort | uniq > $FILE_NAME.yatda-tmp.non-gc-threads
    COUNT=`cat $FILE_NAME.yatda-tmp.non-gc-threads | wc -l`
    i=1
    while read -r line ; do
        NEW_CPU=""
        NEW_ELAPSED=""
        # a helpful echo if needing to view and debug CPU processing activity
        #echo $line
        while read -r line2; do
            # a helpful echo if needing to view and debug CPU processing activity
            #echo $line2
            OLD_CPU=$NEW_CPU
            OLD_ELAPSED=$NEW_ELAPSED
            NEW_CPU=`echo $line2 | sed -E 's/^.*cpu=([0-9]+)\..*/\1/g'`
            #converted elapsed from s to ms
            NEW_ELAPSED="`echo $line2 | sed -E 's/^.*elapsed=([0-9]+)\.([0-9][0-9]).*/\1\2/g'`0"
            # trim any leading 0
            NEW_ELAPSED="`echo $NEW_ELAPSED | sed -E 's/^0(.*)/\1/g'`"

            NON_GC_PERCENTAGE=`printf %.0f "$((10**4 * $NEW_CPU / $NEW_ELAPSED ))e-2" `
            if [ $NON_GC_PERCENTAGE -gt $MAX_GC_PERCENTAGE ]; then
                MAX_NON_GC_PERCENTAGE=$NON_GC_PERCENTAGE
                MAX_NON_GC_LINE=$line2
            fi
            if [ "x$OLD_CPU" != "x" ]; then
                NON_GC_DELTA_PERCENTAGE=`printf %.0f "$((10**4 * ($NEW_CPU - $OLD_CPU) / ($NEW_ELAPSED - $OLD_ELAPSED)))e-2" `
                if [ $NON_GC_DELTA_PERCENTAGE -gt $MAX_NON_GC_DELTA_PERCENTAGE ]; then
                    MAX_NON_GC_DELTA_PERCENTAGE=$NON_GC_DELTA_PERCENTAGE
                    MAX_NON_GC_DELTA_LINE=$line2
                fi

                # report non GC consumer above our $CPU_THRESHOLD
                if [ $NON_GC_DELTA_PERCENTAGE -gt $CPU_THRESHOLD ]; then
                    echo "------------------------------------------------------------------------------" >> $FILE_NAME.yatda-cpu
                    THREAD_LINE="`echo $line2 | sed -E 's/^.*cpu=(.*)\[.*/\1/g'`"
                    #get the prior time stamp
                    grep -E "($THREAD_LINE)|^20[0-9][0-9]\-" $TRIM_FILE | grep -B 1 "$THREAD_LINE" >> $FILE_NAME.yatda-cpu
                    echo "TOTAL CPU: $NEW_CPU ms ELAPSED: $NEW_ELAPSED ms PERCENTAGE: $NON_GC_PERCENTAGE" >> $FILE_NAME.yatda-cpu
                    echo "DELTA CPU: `expr $NEW_CPU - $OLD_CPU` ms ELAPSED: `expr $NEW_ELAPSED - $OLD_ELAPSED` ms PERCENTAGE: $NON_GC_DELTA_PERCENTAGE" >> $FILE_NAME.yatda-cpu
                    grep -A 10 -E "$THREAD_LINE" $TRIM_FILE | grep -v "$THREAD_LINE" | sed -E '/^$.*/,+10d' >> $FILE_NAME.yatda-cpu
                    echo "------------------------------------------------------------------------------" >> $FILE_NAME.yatda-cpu
                    echo >> $FILE_NAME.yatda-cpu
                fi
            fi
        done < <(grep "$line " $FILE_NAME.yatda-tmp.allthreads)
        printf "$i of $COUNT threads done\033[0K\r"
        i=$((i+1))
    done < <(cat $FILE_NAME.yatda-tmp.non-gc-threads)

    echo >> $FILE_NAME.yatda-cpu
    echo "Max total CPU percent of a non GC thread: $MAX_NON_GC_PERCENTAGE" | tee -a $FILE_NAME.yatda-cpu
    echo "    $MAX_NON_GC_LINE" | tee -a $FILE_NAME.yatda-cpu
    echo "Max CPU percent between dumps of a non GC thread: $MAX_NON_GC_DELTA_PERCENTAGE" | tee -a $FILE_NAME.yatda-cpu
    echo "    $MAX_NON_GC_DELTA_LINE" | tee -a $FILE_NAME.yatda-cpu
fi


#clean up tmp files
rm -f $FILE_NAME.yatda-tmp.*
