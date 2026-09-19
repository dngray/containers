Name:           container_aerc-selinux
Version:        1.0
Release:        1.fc44
Summary:        SELinux policy for isolated aerc_t sandboxed container environments
License:        MIT

BuildRequires:  checkpolicy, policycoreutils, selinux-policy-devel
Requires:       policycoreutils, libselinux-utils

%global modulename container_aerc

%description
This SELinux policy module provisions the custom aerc_t container domain,
granting access to home files, GPG sockets, and bidirectional host desktop D-Bus alerts.

%prep
# Pull the pre-built, port-injected .cil file directly from your SOURCES workspace
cp "%{_sourcedir}/%{modulename}.cil" .

%build
# File arrives pre-compiled from build-selinux; no build steps needed.

%install
# Deploy the raw, scriptless, port-injected .cil file to the automatic package directory
mkdir -p %{buildroot}%{_datadir}/selinux/packages
install -m 644 %{modulename}.cil %{buildroot}%{_datadir}/selinux/packages/

%post
%selinux_modules_install -p 400 %{_datadir}/selinux/packages/%{modulename}.cil

%postun
if [ $1 -eq 0 ]; then
    %selinux_modules_uninstall -p 400 %{modulename}
fi

%files
%defattr(-,root,root,-)
%{_datadir}/selinux/packages/%{modulename}.cil

%changelog
* Wed May 27 2026 Daniel Gray <dngray@polarbear.army> - 1.0-1
- Refactored compilation steps to utilize platform devel Makefile wrappers
- Hardened process definitions to target the isolated aerc_t domain architecture
- Optimized post installation scripting pathways to support rpm-ostree environments cleanly
