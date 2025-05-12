Name:           hcsshim
Version:        1.0
Release:        1%{?dist}
Summary:        Demo package to create /ronnybj.txt
License:        MIT
BuildArch:      noarch

%description
This package installs /ronnybj.txt with a custom message.

%install
mkdir -p %{buildroot}/
echo "ronnybj was here version %{version}" > %{buildroot}/ronnybj2.txt

%files
/ronnybj2.txt

%changelog
* Thu May 08 2025 Ronny <ronny@example.com> - 1.0-1
- Initial package for demo