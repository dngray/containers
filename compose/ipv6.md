# IPv6

## Docker

1. If using IPv6 with Docker, remember to [enable support](https://docs.docker.com/engine/daemon/ipv6/) by adding this to `/etc/docker/daemon.json`:

   ```json
   {
     "ipv6": true,
     "fixed-cidr-v6": "fd00:1234:5678::/64"
   }
   ```

2. Docker must then be restarted

   ```text
   sudo systemctl restart docker
   ```

## Podman

1. The default `podman` bridge does not have IPv6 enabled by default.
2. Create a new bridge:

   ```bash
   podman network create --ipv6 podman1
   ```

3. Examine the bridge:

   ```bash
   podman network inspect podman1
   ```

4. The new bridge should have this defined (showing automated IPv4/IPv6 dual-stack and DNS support):

   ```json
   [
       {
             "name": "podman1",
             "id": "2f8ae...",
             "driver": "bridge",
             "network_interface": "podman1",
             "subnets": [
                 {
                       "subnet": "10.89.1.0/24",
                       "gateway": "10.89.1.1"
                 },
                 {
                       "subnet": "fd12:3456:789a:1::/64",
                       "gateway": "fd12:3456:789a:1::1"
                 }
             ],
             "ipv6_enabled": true,
             "dns_enabled": true
       }
   ]
   ```
