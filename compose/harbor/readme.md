# Manual instructions for setting up Harbor

Even with Harbor 2.13.1 there seems to be a problem with an [incorrect database
password](https://github.com/goharbor/harbor/issues/19653#issuecomment-1875248259),
causing the `harbor-core` container to fail start. The password you set in
`harbor.yml` doesn't appear to be used in the database.

1. Set the password:

   ```bash
   cat reset_password.sql | docker exec -i harbor-db psql -U postgres
   ```

1. Restart containers.

1. Move the files to the correct directory. By default `install.sh` puts the
   data in `/data` and `~/harbor/common`. I like to move those to
`/opt/appdata/harbor/` and modify the path in the docker compose file:

   ```text
   %s/- \.\/common/- \/opt\/appdata\/harbor\/common/g
   %s/- \/data/- \/opt\/appdata\/harbor\/data/g
   %s/source: \/data\//source: \/opt\/appdata\/harbor\/data\//g
   ```

1. Add this network to the proxy container:

   ```yaml
   networks:
     harbor:
       ipv4_address: 172.30.0.100
   ```

   and to the bottom:

   ```yaml
   networks:
     harbor:
       enable_ipv6: false
       ipam:
         config:
           - subnet: 172.30.0.0/16
             gateway: 172.30.0.1
   ```
