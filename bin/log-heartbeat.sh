#!/usr/bin/bash

# staggered start time
sleep $((16#$FLY_MACHINE_ID % 1800))

while true; do
  echo "HEARTBEAT $FLY_MACHINE_ID $FLY_REGION"
  sleep 1800
done
