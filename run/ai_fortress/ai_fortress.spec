Name:           ai_fortress-selinux
Version:        1.0
Release:        1.fc44
Summary:        Generic SELinux policy jail for AI agents (Aider, OpenCode, etc.)
License:        MIT

# We only need checkpolicy to run the syntax validation test during the build stage
BuildRequires:  checkpolicy, policycoreutils
Requires:       policycoreutils, libselinux-utils

%global modulename ai_fortress

%description
This SELinux policy creates a restricted jail (fortress_agent_t) for AI
agents. It restricts file access to designated workspace (fortress_src_t),
config, and cache directories while allowing read-only access to global
Git and SSH configurations for agentic workflows.

%prep
# Your create-rpm wrapper copies your generated .cil file into the SOURCES folder. 
# We pull it directly into the local build environment here.
cp "%{_sourcedir}/%{modulename}.cil" .

%build
# File arrives pre-compiled and injected via build-selinux; no build steps needed.

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
