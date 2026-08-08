Name:           container_aerc-selinux
Version:        1.0
Release:        1.fc44
Summary:        SELinux policy for aerc containers and GPG socket access
License:        MIT

BuildRequires:  selinux-policy-devel, make, checkpolicy, policycoreutils
Requires:       policycoreutils, libselinux-utils
Requires(post): policycoreutils, selinux-policy-targeted
Requires(postun): policycoreutils

%global selinuxtype targeted
%global modulename container_aerc

%description
This SELinux policy module allows containerized applications (specifically aerc)
to access home directories and the host GPG agent socket.

%prep
# No preparation steps needed

%build
checkmodule -M -m -o %{modulename}.mod %{_sourcedir}/%{modulename}.te
semodule_package -o %{modulename}.pp -m %{modulename}.mod
bzip2 -9 %{modulename}.pp

%check
checkmodule -M -m -o %{modulename}.check %{_sourcedir}/%{modulename}.te
rm %{modulename}.check

%install
mkdir -p %{buildroot}%{_datadir}/selinux/packages
install -m 644 %{modulename}.pp.bz2 %{buildroot}%{_datadir}/selinux/packages/

%post
/usr/sbin/semodule -n -s %{selinuxtype} -i %{_datadir}/selinux/packages/%{modulename}.pp.bz2 > /dev/null 2>&1 || :
if /usr/sbin/selinuxenabled ; then
    /usr/sbin/load_policy
fi

%postun
if [ $1 -eq 0 ]; then
    /usr/sbin/semodule -n -r %{modulename} > /dev/null 2>&1 || :
    if /usr/sbin/selinuxenabled ; then
        /usr/sbin/load_policy
    fi
fi

%files
%defattr(-,root,root,-)
%{_datadir}/selinux/packages/%{modulename}.pp.bz2

%changelog
* Wed May 06 2026 Daniel Gray <dngray@polarbear.army> - 1.0-1
- Initial release for Fedora 44
- Added GPG agent socket bridge for containerized aerc
