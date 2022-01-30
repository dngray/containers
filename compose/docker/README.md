# Create networks

1. Create the networks
   ```
   sudo docker network create --subnet=172.18.0.0/16 -d bridge -o com.docker.network.bridge.name=direct1_net direct1_net
   sudo docker network create --subnet=172.19.0.0/16 -d bridge -o com.docker.network.bridge.name=direct2_net direct2_net
   sudo docker network create --subnet=172.20.0.0/16 -d bridge -o com.docker.network.bridge.name=traefik_net traefik_net
   ```

# Stuff that is already configured

1. Create some fwmarks, this is already taken care of for you in /etc/iptables/rules-save
   ```
   sudo iptables -t mangle -A PREROUTING -s 172.18.0.0/16 -j MARK --set-xmark 0x7/0xffffffff
   sudo iptables -t mangle -A PREROUTING -s 172.19.0.0/16 -j MARK --set-xmark 0x2/0xffffffff
   ```

2. Add the require sysctl for fwmarking, this is already taken care of in /etc/sysctl.d/local.conf
   ```
   sudo sysctl -w net.ipv4.conf.all.rp_filter=2
   ```

3. Add the fwmarks for the respective tables, already taken care of in /etc/network/route and brought on like in /etc/network/interfaces
   ```
   sudo ip rule add fwmark 7 table CONTAINERS prio 700
   sudo ip route add default via 192.168.7.1 table CONTAINERS
   sudo ip route add 192.168.7.1 dev bond0.7 table CONTAINERS
   ```
   ```
   sudo ip rule add fwmark 2 table ISP prio 200
   sudo ip route add default via 192.168.2.1 table ISP
   sudo ip route add 192.168.2.1 dev bond0.2 table ISP
   ```

# Testing

1. Testing a VPN connection, this can either be podman or docker. If the container doesn't have wget (busybox based ones do), use curl instead ie `curl <url>`
   ```
   sudo podman exec -it test ash
   wget -q -O - ifconfig.me
   ```
