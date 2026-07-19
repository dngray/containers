# Add Gvisor (runsc) runtimes

Make sure to use the folllowing
[platform](https://gvisor.dev/docs/user_guide/platforms/) and
[network](https://gvisor.dev/docs/user_guide/networking/) options.

## Podman

1.  If you're using [`podman-run`](https://docs.podman.io/en/latest/markdown/podman-run.1.html) just specify the [`--runtime-flag`](https://docs.podman.io/en/stable/markdown/podman.1.html#runtime-flag-flag) like:

    ```conf
    --runtime=runsc \
    --runtime-flag platform=kvm \
    --runtime-flag network=host \
    ```

Set these in `/etc/containers/containers.conf` if you want to use [`podman compose`](https://docs.podman.io/en/latest/markdown/podman-compose.1.html). Don't change the default runtime as it won't work with with [`podman-exec`](https://docs.podman.io/en/latest/markdown/podman-exec.1.html).

2. Set which runtimes support json:

   ```conf
   runtime_supports_json = ["crun", "runc", "kata", "runsc", "youki", "krun",
   "runsc-kvm", "runsc-kvm-debug", "runsc-kvm-uds-open", "runsc-systrap",
   "runsc-systrap-debug", "runsc-systrap-uds-open"]
   ```

3. Set which runtimes support KVM:

   ```conf
   runtime_supports_kvm = ["kata", "krun", "runsc-kvm", "runsc-kvm-debug", "runsc-kvm-uds-open"]
   ```

4. Set runtime paths:

   ```conf
   runsc-kvm = [
     "/opt/runtimes/runsc-kvm"
   ]

   runsc-kvm-debug = [
     "/opt/runtimes/runsc-kvm-debug"
   ]

   runsc-kvm-uds-open = [
     "/opt/runtimes/runsc-kvm-uds-open"
   ]

   runsc-systrap = [
     "/opt/runtimes/runsc-systrap"
   ]

   runsc-systrap-debug = [
     "/opt/runsc-systrap-debug"
   ]

   runsc-systrap-uds-open = [
     "/opt/runsc-systrap-uds-open"
   ]
   ```

## Docker

1. Add the following to `/etc/docker/daemon.json`

   ```json
   {
     "default-runtime": "runsc-kvm",
     "runtimes": {
       "runsc-kvm": {
         "path": "/usr/bin/runsc",
         "runtimeArgs": [
           "--platform=kvm",
           "--network=host"
         ]
       },
       "runsc-systrap": {
         "path": "/usr/bin/runsc",
         "runtimeArgs": [
           "--platform=systrap",
           "--network=host"
         ]
       },
       "runsc-kvm --host-uds=open": {
         "path": "/usr/bin/runsc",
         "runtimeArgs": [
           "--platform=kvm",
           "--network=host",
           "--host-uds=open"
         ]
       },
       "runsc-systrap --host-uds=open": {
         "path": "/usr/bin/runsc",
         "runtimeArgs": [
           "--platform=systrap",
           "--network=host",
           "--host-uds=open"
         ]
       },
       "runsc-kvm-debug": {
         "path": "/usr/bin/runsc",
         "runtimeArgs": [
           "--platform=kvm",
           "--network=host",
           "--debug-log=/tmp/runsc-kvm/",
           "--debug",
           "--strace"
         ]
       },
       "runsc-systrap-debug": {
         "path": "/usr/bin/runsc",
         "runtimeArgs": [
           "--platform=systrap",
           "--network=host",
           "--debug-log=/tmp/runsc-systrap/",
           "--debug",
           "--strace"
         ]
       }
     }
   }
   ```
