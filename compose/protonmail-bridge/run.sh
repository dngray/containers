#/bin/sh

sudo docker run --rm -it -v /mnt/container_data/pm_bridge:/root \
                         --name protonmail-bridge \
                         -p 1025:25/tcp -p 1143:143/tcp \
                         protonmail-bridge-protonmail-bridge init
