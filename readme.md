# Containers

Just the containers I use.

## IPv6

### Docker

If using IPv6 with docker remember to [enable
support](https://docs.docker.com/config/daemon/ipv6/) by adding this to
`/etc/docker/daemon.json`

```json
{
  "experimental": true,
  "ip6tables": true
}
```

### Podman

For podman see [How to configure Podman 4.0 for IPv6](https://developers.redhat.com/articles/2022/08/10/how-conifgure-podman-40-ipv6)

1. Install `netavark`
2. Set `network_backend = "netavark"` in `/etc/containers/containers.conf`
3. The default `podman0` bridge does not have IPv6 defined and DNS disabled.
4. Create a new bridge `podman network create --ipv6  podman1`
5. Examine bridge: `podman network inspect podman1`
6. The new bridge should have this defined:

   ```json
       {
             "subnet": "fd96:7c2e:b8d2:bf65::/64",
             "gateway": "fd96:7c2e:b8d2:bf65::1"
       }
   ],
   "ipv6_enabled": true,
   ```
