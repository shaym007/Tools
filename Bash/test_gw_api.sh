#!/bin/bash

# Define the URLs and file paths
URL="rest.shay.cs.akeyless.fans"
LOG_FILE="/tmp/request_log.txt"
ERROR_FILE="/tmp/error_log.txt"
MAX_LINES=100


# Function to send GET request and log status
send_request() {
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  response=$(curl -s -o /dev/null -w "%{http_code}" $URL)

  # Check if the log file has reached the maximum number of lines
  if [ $(wc -l < $LOG_FILE) -ge $MAX_LINES ]; then
     # Move the first line to the end to cycle the log
     sed -i '1d' $LOG_FILE
  fi

  echo "$timestamp - Status: $response" >> $LOG_FILE
  if [ "$response" -ne 200 ]; then
    echo "$timestamp - Status: $response" >> $ERROR_FILE
  fi
}
# Loop to send requests every second
while true; do
  send_request
  sleep 1
done
