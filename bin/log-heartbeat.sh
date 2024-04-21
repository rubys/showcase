#!/usr/bin/bash

if [[ -z "$FLY_MACHINE_ID" ]]; then
  sleep 3
  printenv
  sleep infinity
else
  # staggered start time
  sleep $((16#$FLY_MACHINE_ID % 1800))

  while true; do
    echo "HEARTBEAT $FLY_MACHINE_ID $FLY_REGION"
    sleep 1800
  done
fi
