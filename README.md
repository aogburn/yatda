# yatda
Yet another thread dump analyzer (yatda) is a simple script of helpful greps to help analyze java thread dumps for concerns, with a particular focus on JBoss/Tomcat threads and issues. The focal point of thread dumps is often where the thread is currently executing, or the top of the thread stack. So yatda collects and sorts the tops of thread stacks to see what threads are most commonly doing. It provides specific usage and stats of JBoss request threads and boot threads and can be specified to look for some other custom thread name if there is some other thread of interest.

# installation

wget https://raw.githubusercontent.com/aogburn/yatda/master/yatda.sh

# updating 

When run, yatda will look for a new version to use and update itself with a simple wget if so.  Uncomment the CHECK_UPDATE flag in the script if you need to disable those update checks. The script may be updated over time with new helpful checks, stats, or known issue searches.

# usage

* To run:
> ./yatda.sh -f thread-dump-file-name
* This will produce a report to thread-dump-file-name.yatda. If there are multiple thread dumps in the file, this will look across them all collectively with reported averages. That can be helpful, but yatda reports from individual dumps to compare may also be helpful. Split the file to separate dumps quickly like so for separate thread dump files to run yatda on:
> csplit -f 'tdump' -z thread-dump-file-name '/Full thread dump/-2' '{*}'
* If JBoss's request thread name has been customized, then specify the custom thread name with the -r flag.
* If you want to focus on another specific thread type besides request/boot threads, then specify that thread name with the -t flag.  Use the -s flag to specify some class/method that would indicate the thread is in use so yatda can derive usage statistics (for instance, it uses io.undertow.server.Connectors.executeRootHandler to determine general usage of request threads for EAP 7).
* By default, yatda focuses on the first 20 lines of thread stacks for request threads (some times there are a lot of generic frames at the top for something like a socket read before you get to the more interesting class frame that called it) or custom specified threads (-t); this can be changed via the -n flag.  It focuses on the first 10 lines for all threads; this can be changed via th -a flag. That may be done if you need to try looking at narrow or wider sections of thread stacks from their first line. Avoid setting these excessively large as that can contribute to miscounts.
