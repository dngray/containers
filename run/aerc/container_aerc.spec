Name:           container_aerc-selinux
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
# Compile the .te file into the .mod file and package into a .pp.bz2 file
checkmodule -M -m -o container_aerc.mod %{_sourcedir}/container_aerc.te
semodule_package -o container_aerc.pp -m container_aerc.mod
bzip2 container_aerc.pp

%install
mkdir -p %{buildroot}%{_datadir}/selinux/packages
install -m 644 container_aerc.pp.bz2 %{buildroot}%{_datadir}/selinux/packages/

%files
%defattr(-,root,root,-)
%{_datadir}/selinux/packages/container_aerc.pp.bz2

%changelog
* Tue Sep 18 2025 Daniel Gray <dngray@polarbear.army> - 1.0-1
- Initial RPM release
