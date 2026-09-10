Name:           container_snapclient-selinux
Version:        1.0
Release:        1.fc44
Summary:        SELinux policy for isolated snapclient_t sandboxed container environments
License:        MIT

BuildRequires:  checkpolicy, policycoreutils, selinux-policy-devel
Requires:       policycoreutils, libselinux-utils

%global modulename container_snapclient

%description
This SELinux policy module provisions the custom snapclient_t container domain,
granting access to the PulseAudio socket and ALSA devices for audio playback
from a Snapcast audio client container.

%prep
cp "%{_sourcedir}/%{modulename}.cil" .

%build
# File arrives pre-compiled from build-selinux; no build steps needed.

%install
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
* Sat May 28 2026 Daniel Gray <dngray@polarbear.army> - 1.0-1
- Initial policy module for snapclient container domain
