#!/usr/bin/bash

# staggered start time
sleep $((16#$FLY_MACHINE_ID % 1800))

while true; do
  echo "HEARTBEAT $FLY_REGION $FLY_MACHINE_ID"
  sleep 1800
done
