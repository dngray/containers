# Toolbx

These are mostly used on Fedora.

If you see an error like:

  ```text
  /bin/sh: error while loading shared libraries: /lib64/libc.so.6:
  cannot apply additional memory protection after relocation: Permission denied
  ```

When trying to build containers with this AVC:

  ```text
  audit[5394]: AVC avc:  denied  { read } for  pid=5394 comm="sh"
  path="/usr/lib64/libc.so.6" dev="dm-0" ino=2449144
  scontext=system_u:system_r:container_t:s0:c423,c856
  tcontext=unconfined_u:object_r:container_file_t:s0:c230,c577 tclass=file
  permissive=0
```

The solution seems to be:

  ```bash
  restorecon -RFv $HOME/.local/share/containers
  ```
