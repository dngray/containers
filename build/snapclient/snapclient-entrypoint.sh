#!/bin/sh
set -e

if [ $# -gt 0 ]; then
  exec "$@"
fi

SNAPCAST_URI="tcp://${SNAPCAST_HOST:-snapcast}:${SNAPCAST_PORT:-1704}"
LATENCY="${SNAPCAST_LATENCY:-200}"

export HOME=/tmp
export PULSE_COOKIE="/tmp/pulse-cookie"

# Read your new variable, fallback defaulting to 100ms if not specified
PULSE_BUF="${PULSE_BUFFER_TIME:-100}"

if [ -n "$PULSE_SERVER" ] || [ -S "/run/user/$(id -u)/pulse/native" ]; then
  [ -f "$PULSE_COOKIE" ] || dd if=/dev/urandom bs=256 count=1 of="$PULSE_COOKIE" 2>/dev/null || true
  # OPTIMIZATION: Dynamically appends your buffer time right out of the environment!
  exec /usr/bin/snapclient --player "pulse:buffer_time=${PULSE_BUF}" --latency "$LATENCY" "$SNAPCAST_URI"
elif [ -e /dev/snd ]; then
  exec /usr/bin/snapclient --player alsa --soundcard "${SOUNDCARD:-default}" --latency "$LATENCY" "$SNAPCAST_URI"
else
  exec /usr/bin/snapclient --latency "$LATENCY" "$SNAPCAST_URI"
fi
