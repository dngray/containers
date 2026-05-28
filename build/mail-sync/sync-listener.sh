#!/bin/bash
echo "Headless Mail Sync Socket Listener Online (Port 12345)..."
while true; do
  # Blocks cleanly until a client pokes the port, then captures the string argument
  REQUEST=$(nc -l 127.0.0.1 12345)
  ACTION=$(echo "$REQUEST" | awk '{print $1}')

  if [ "$ACTION" = "sync-inbox" ] || [ "$ACTION" = "sync-all" ]; then
    echo "--> Processing remote token signal: $ACTION"
    /usr/local/bin/container-email-sync "$ACTION"
  fi
done
