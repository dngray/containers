Name:           containers_gpg_socket-selinux
Version:        1.0
Release:        1.fc43
Summary:        SELinux policy for containers and GPG socket

License:        MIT
# No Source0 for the .pp.gz since it's generated during the build process

BuildRequires:  selinux-policy-devel, make

%description
This SELinux policy module allows containers to access the GPG socket.

%prep
# No preparation steps needed

%build
# Compile the .te file into the .mod file and package into a .pp.gz file
checkmodule -M -m -o containers_gpg_socket.mod %{_sourcedir}/containers_gpg_socket.te
semodule_package -o containers_gpg_socket.pp -m containers_gpg_socket.mod
gzip containers_gpg_socket.pp

%install
mkdir -p %{buildroot}%{_datadir}/selinux/packages
install -m 644 containers_gpg_socket.pp.gz %{buildroot}%{_datadir}/selinux/packages/

%files
%defattr(-,root,root,-)
%{_datadir}/selinux/packages/containers_gpg_socket.pp.gz

%changelog
* Tue Sep 18 2025 Daniel Gray <dngray@polarbear.army> - 1.0-1
- Initial RPM release
