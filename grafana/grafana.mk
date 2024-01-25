#
# Grafana
# Depends: influxdb, pypowerwall
#

.PHONY: grafana-net-create
grafana-net-create:
	sudo docker network create --subnet=172.27.0.0/16 \
	--ipv6 --subnet fd27:1::/48 \
	grafana_frontend

.PHONY: grafana
grafana:
	sudo docker run -d \
		--name grafana \
		--hostname grafana \
		--runtime=runsc-kvm \
		--restart=unless-stopped \
		--read-only \
		--memory=8g \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		--user=1103:1103 \
		--env-file ${PWD}/grafana/grafana.env \
		--network=grafana_frontend --ip=172.27.0.2 \
		-v ${c_data}/grafana:/var/lib/grafana \
		docker.io/grafana/grafana:9.1.2-ubuntu

.PHONY: grafana-net-connect
grafana-net-connect:
	sudo docker network connect influxdb_backend grafana
	sudo docker network connect pypowerwall_backend grafana

.PHONY: grafana-run
grafana-run: grafana-net-create \
	grafana \
	grafana-net-connect

.PHONY: grafana-clean
grafana-clean:
	sudo docker stop grafana
	sudo docker network grafana_frontend
	sudo docker rm grafana
