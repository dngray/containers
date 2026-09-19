#!/usr/bin/env bash

set -euo pipefail

echo "Welcome to the Proton Mail Bridge docker container ${ENV_PROTONMAIL_BRIDGE_VERSION:-unknown} !"
echo "Copyright (C) 2026  asyncura - See LICENSE.txt"

# Default values, overridable at `docker run` time.
: "${PROTON_BRIDGE_SMTP_PORT:=1025}"
: "${PROTON_BRIDGE_IMAP_PORT:=1143}"
: "${PROTON_BRIDGE_HOST:=127.0.0.1}"
: "${CONTAINER_SMTP_PORT:=25}"
: "${CONTAINER_IMAP_PORT:=143}"

# On first launch, create a GPG key and initialize the pass password store
# that the bridge uses to store its credentials.
if [ ! -d "/root/.password-store/" ]; then
  echo "First launch detected: initializing GPG key and password store..."
  gpg --generate-key --batch /app/GPGparams.txt
  gpg --list-keys
  pass init ProtonMailBridge
fi

# Proton Mail Bridge listens only on the 127.0.0.1 interface inside the
# container, so we forward TCP traffic from all interfaces on the SMTP and
# IMAP container ports.
socat TCP-LISTEN:"$CONTAINER_SMTP_PORT",fork,reuseaddr TCP:"$PROTON_BRIDGE_HOST":"$PROTON_BRIDGE_SMTP_PORT" &
SOCAT_SMTP_PID=$!
socat TCP-LISTEN:"$CONTAINER_IMAP_PORT",fork,reuseaddr TCP:"$PROTON_BRIDGE_HOST":"$PROTON_BRIDGE_IMAP_PORT" &
SOCAT_IMAP_PID=$!

echo "Forwarding 0.0.0.0:${CONTAINER_SMTP_PORT} -> ${PROTON_BRIDGE_HOST}:${PROTON_BRIDGE_SMTP_PORT} (SMTP)"
echo "Forwarding 0.0.0.0:${CONTAINER_IMAP_PORT} -> ${PROTON_BRIDGE_HOST}:${PROTON_BRIDGE_IMAP_PORT} (IMAP)"

# Start the bridge CLI with its stdin on a fifo opened read-write: it never
# receives EOF, so the bridge won't stop, and the open doesn't block waiting
# for a writer.
rm -f /app/faketty
mkfifo /app/faketty

/app/bridge --cli <> /app/faketty &
BRIDGE_PID=$!

# Forward container stop signals to the bridge and the socat forwarders for a
# clean shutdown.
KEEPALIVE_PID=""
shutdown() {
  echo "Received stop signal, shutting down..."
  kill "$BRIDGE_PID" "$SOCAT_SMTP_PID" "$SOCAT_IMAP_PID" ${KEEPALIVE_PID:+"$KEEPALIVE_PID"} 2>/dev/null || true
  wait "$BRIDGE_PID" 2>/dev/null || true
  echo "Done."
  exit 0
}
trap shutdown TERM INT

wait "$BRIDGE_PID" || true

# The bridge exited but the container was not stopped. This is expected during
# the first-time setup: the user runs `pkill bridge` and then the interactive
# `/app/bridge --cli` to log in (only one bridge instance can run at a time),
# so keep the container alive instead of exiting.
echo "Proton Mail Bridge exited. Keeping the container running for interactive setup:"
echo "  docker exec -it <container> /bin/bash    then    /app/bridge --cli"
echo "Restart the container to bring the supervised bridge back up."

tail -f /dev/null &
KEEPALIVE_PID=$!
wait "$KEEPALIVE_PID" || true

echo "Done."
