# Install SELinux policy so gpg and gpg-agent can work

1. Install dependencies for build env

   ```text
   sudo dnf install rpm-build selinux-policy-devel
   ```

2. Prepare rpm

   ```text
   mkdir -p ~/rpmbuild/{BUILD,RPMS,SPECS,SOURCES}
   cp container_aerc.spec ~/rpmbuild/SPECS/
   cp container_aerc.te ~/rpmbuild/SOURCES/
   ```

3. Build

   ```text
   rpmbuild -ba rpmbuild/SPECS/container_aerc.spec
   ```

4. Install

   ```text
   rpm -ivh container_aerc-selinux-1.0-1.fc42.noarch.rpm
   ```

   or on ostree distribution

   ```text
   rpm-ostree install container_aerc-selinux-1.0-1.fc42.noarch.rpm
   ```
