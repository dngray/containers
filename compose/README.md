# Create networks

1. Create the network
   ```
   sudo docker network create --subnet=172.18.0.0/16 -d bridge -o com.docker.network.bridge.name=traefik-proxy traefik-proxy
   ```

# Testing

1. Testing a VPN connection, this can either be podman or docker. If the container doesn't have wget (busybox based ones do), use curl instead ie `curl <url>`
   ```
   sudo podman exec -it {{ container name }} wget -q -O - ifconfig.co/country
   sudo podman exec -it {{ container name }} curl ifconfig.co/country
   ```
