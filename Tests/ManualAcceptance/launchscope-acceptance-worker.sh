#!/bin/sh

if [ "${1:-}" = "--once" ]; then
  exit 0
fi

while true; do
  /bin/sleep 60
done
