#
# Powerwall
#

.PHONY: pypowerwall-network-create
pypowerwall-network-create:
	sudo docker network create --subnet=172.28.0.0/16 \
	--ipv6 --subnet fd28:2::/48 \
	pypowerwall_backend

.PHONY: influxdb-network-create
influxdb-network-create:
	sudo docker network create --subnet=172.29.0.0/16 \
	--ipv6 --subnet fd29:1::/48 \
	influxdb_backend

.PHONY: pypowerwall
pypowerwall:
	sudo docker run -d \
		--name pypowerwall \
		--hostname pypowerwall \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		-e PW_AUTH_PATH=.auth \
		-v ${c_data}/pypowerwall/.auth:/app/.auth \
		--network=pypowerwall_backend --ip=172.28.0.2 \
		--env-file ${PWD}/powerwall/data/pypowerwall.env \
		docker.io/jasonacox/pypowerwall:0.12.0t66

.PHONY: influxdb
influxdb:
	sudo docker run -d \
		--name influxdb \
		--hostname influxdb \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--user=1100:1100 \
		--network=influxdb_backend --ip=172.29.0.2 \
		-v ${PWD}/powerwall/data/influxdb.conf:/etc/influxdb/influxdb.conf:ro \
		-v ${c_data}/influxdb:/var/lib/influxdb \
		docker.io/influxdb:1.8

.PHONY: telegraf
telegraf:
	sudo docker run -d \
		--name telegraf \
		--hostname telegraf \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--user=1102:1102 \
		-v ${PWD}/powerwall/data/telegraf.conf:/etc/telegraf/telegraf.conf:ro \
		docker.io/telegraf:1.28.2

.PHONY: telegraf-net-connect
telegraf-net-connect:
	sudo docker network connect influxdb_backend telegraf
	sudo docker network connect pypowerwall_backend telegraf

.PHONY: weather411
weather411:
	sudo docker run -d \
		--name weather411 \
		--hostname weather411 \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--user=1304:1304 \
		-e WEATHERCONF=/var/lib/weather/weather411.conf \
		-v ${PWD}/powerwall/data/weather411.conf:/var/lib/weather/weather411.conf \
		--network=influxdb_backend \
		docker.io/jasonacox/weather411

powerwall-net-create: pypowerwall-network-create influxdb-network-create

powerwall-run: powerwall-net-create \
	influxdb \
	pypowerwall \
	telegraf \
	weather411 \
	telegraf-net-connect

.PHONY: powerwall-clean
powerwall-clean:
	sudo docker stop influxdb pypowerwall telegraf weather411
	sudo docker network rm influxdb_backend pypowerwall_backend
	sudo docker rm influxdb pypowerwall telegraf weather411
