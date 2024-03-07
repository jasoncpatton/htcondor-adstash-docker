#!/bin/bash
# This script evaluates exiting processes to
# determine if supervisord should be killed.
# http://supervisord.org/events.html

# Signal readiness to start
echo "READY"

# Set a default 20 minute timeout
ADSTASH_TIMEOUT="${ADSTASH_TIMEOUT:-1200}"
ADSTASH_TIMED_OUT=true

# Read lines from stdin
while read -t $ADSTASH_TIMEOUT line; do

    # Each line containers a header with the length of data to read
    echo "Processing header: $line" >&2
    bytes=$(echo $line | grep -oP "(?<=len:)\w+")

    # Read the data and extract the process name and if it exited expectedly
    read -n $bytes result
    echo "Got result: $result" >&2
    process=$(echo $result | grep -oP '(?<=processname:)\w+')
    expected=$(echo $result | grep -oP '(?<=expected:)\w+')

    # Tell supervisord to exit if a certain process exited expectedly
    if [ "$process" = "adstash" ] && [ "$expected" -eq "1" ]; then
        echo "Adstash exited normally, stopping supervisord..." >&2
        ADSTASH_TIMED_OUT=false
        kill -SIGQUIT $(cat "/var/run/supervisord.pid")
    fi

    # Signal readiness again
    echo "RESULT 2"
    echo -n "OK"
    echo "READY"

done < /dev/stdin

# Tell supervisord to exit if we timed out
if $ADSTASH_TIMED_OUT; then
    echo "Adstash failed to exit in $ADSTASH_TIMEOUT seconds, stopping supervisord..." >&2
    kill -SIGQUIT $(cat "/var/run/supervisord.pid")
fi
