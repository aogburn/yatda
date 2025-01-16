# yatda
Yet another thread dump analyzer (yatda) is a simple script of helpful greps to help analyze java thread dumps for concerns, with a particular focus on JBoss/Tomcat threads and issues. The focal point of thread dumps is often where the thread is currently executing, or the top of the thread stack. So yatda collects and sorts the tops of thread stacks to see what threads are most commonly doing. It provides specific usage and stats of JBoss request threads and boot threads and can be specified to look for some other custom thread name if there is some other thread of interest.

# installation
* To install, run the following in a directory where you want to keep the script.  This should be a directory without any spaces or special characters:
```
wget https://raw.githubusercontent.com/aogburn/yatda/master/yatda.sh
chmod 755 yatda.sh
```
# updating 

When run, yatda will look for a new version to use and update itself with a simple wget if so. This update check can be omitted by using the option '-u, --updateMode' with either the value 'never' (no update check is being performed) or 'ask' (the user is asked to update if a new version is found). The script may be updated over time with new helpful checks, stats, or known issue searches.

# usage

* To run:
```
 ./yatda.sh <THREAD_DUMP_FILE_NAME>
```
* This will produce a report to thread-dump-file-name.yatda. If there are multiple thread dumps in the file, this will look across them all collectively with reported averages. That can be helpful, but yatda reports from individual dumps to compare may also be helpful. Split the file to separate dumps quickly like so for separate thread dump files to run yatda on:
```
 csplit -f 'tdump' -z thread-dump-file-name '/Full thread dump/' '{*}'
```
* If JBoss's request thread name has been customized, then specify the custom thread name with the -r flag.
* If you want to focus on another specific thread type besides request/boot threads, then specify that thread name with the -t flag.  Use the -s flag to specify some class/method that would indicate the thread is in use so yatda can derive usage statistics (for instance, it uses io.undertow.server.Connectors.executeRootHandler to determine general usage of request threads for EAP 7+).
* By default, yatda focuses on the first 20 lines of thread stacks for request threads (some times there are a lot of generic frames at the top for something like a socket read before you get to the more interesting class frame that called it) or custom specified threads (-t); this can be changed via the -n flag.  It focuses on the first 10 lines for all threads; this can be changed via th -a flag. That may be done if you need to try looking at narrow or wider sections of thread stacks from their first line. Avoid setting these excessively large as that can contribute to miscounts.
* Options:
```
    -r, --requestThread             specify a name for request threads instead of 'default task'
    -t, --specifiedThread           specify a thread name to focus on
    -s, --specifiedTrace            specify a particular generic line indicating thread usage
    -n, --specifiedLineCount        number of stack lines to focus on from request or specified threads
    -a, --allLineCount              number of stack lines to focus on from all threads
    -u, --updateMode                the update mode to use, one of [${VALID_UPDATE_MODES[*]}], default: force
    -h, --help                      show this help
```
