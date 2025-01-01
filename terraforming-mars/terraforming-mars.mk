#
# terraforming-mars
# https://github.com/terraforming-mars/terraforming-mars/wiki/Docker-Setup
#

.PHONY: mars-postgres
mars-postgres:
	sudo docker run -d \
		--name TerraformingMars-DB \
		--hostname terraformingmars-db \
		--runtime=runsc-kvm \
		--restart=on-failure:3 \
		--read-only \
		--cpu-shares=768 \
		--memory=512m \
		--pids-limit=2048 \
		--cap-drop=all \
		--user=1100:1100 \
		--security-opt=no-new-privileges \
		-e POSTGRES_USER: ${POSTGRESQL_USER} \
		-e POSTGRES_PASSWORD: ${POSTGRESQL_PASS} \
		-e POSTGRES_DB: terraforming-mars \
		-v ${c_user}/terraforming-mars/db:/var/lib/postgresql/data:rw \
		docker.io/postgres:14.5

.PHONY: terraforming-mars
terraforming-mars:
	sudo docker run -d \
		--name TerraformingMars \
		--hostname terraforming-mars \
		--runtime=runsc-kvm \
		--restart=on-failure:3 \
		--read-only \
		--pids-limit=2048 \
		--security-opt=no-new-privileges \
		--cap-drop=all \
		-p 127.0.0.1:8540:8080 \
		-e POSTGRES_HOST=postgresql://$POSTGRESQL_USER:$POSTGRESQL_PASS@terraformingmars-db/terraforming-mars?sslmode=disable \
		-e NODE_ENV=production \
		andrewsav/terraforming-mars:latest

terraforming-mars-run: mars-posgres \
	terraforming-mars

.PHONY: terraforming-mars-clean
terraforming-clean:
	sudo docker stop mars-postgres terraforming-mars
	sudo docker rm mars-postgres terraforming-mars
