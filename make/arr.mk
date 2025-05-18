#
# arr
#

all-arr-clean: all-arr-containers-clean all-arr-images-clean

all-arr-containers-clean:
	sudo docker rm -f lidarr
	sudo docker rm -f prowlarr
	sudo docker rm -f qbittorrent
	sudo docker rm -f radarr
	sudo docker rm -f sabnzbd
	sudo docker rm -f sonarr
	sudo docker rm -f vpn_usenet
	sudo docker rm -f vpn_bittorrent

all-arr-images-clean:
	sudo docker rmi -f ghcr.io/linuxserver/lidarr
	sudo docker rmi -f lscr.io/linuxserver/prowlarr:develop
	sudo docker rmi -f ghcr.io/linuxserver/qbittorrent
	sudo docker rmi -f ghcr.io/linuxserver/radarr
	sudo docker rmi -f ghcr.io/linuxserver/sabnzbd
	sudo docker rmi -f ghcr.io/linuxserver/sonarr
	sudo docker rmi -f ghcr.io/wfg/openvpn-client
