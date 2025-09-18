# Install SELinux policy so gpg and gpg-agent can work

1. Install dependencies for build env
   ```text
   sudo dnf install rpm-build selinux-policy-devel
   ```

2. Prepare rpm

   ```text
   mkdir -p ~/rpmbuild/{BUILD,RPMS,SPECS,SOURCES}
   cp containers_gpg_socket.spec ~/rpmbuild/SPECS/
   cp containers_gpg_socket.te ~/rpmbuild/SOURCES/
   ```

3. Build

   ```text
   rpmbuild -ba rpmbuild/SPECS/containers_gpg_socket.spec
   ```

4. Install

   ```text
   rpm -ivh containers_gpg_socket-selinux-1.0-1.fc42.noarch.rpm
   ```

   or on ostree distribution

   ```text
   rpm-ostree install containers_gpg_socket-selinux-1.0-1.fc42.noarch.rpm
   ```
