#!/usr/bin/env bash
set -euo pipefail

# Clean build environment
sudo rm -rf $HOME/rpmbuild/BUILD/bash-*
sudo rm -rf $HOME/rpmbuild/BUILDROOT/bash-*
sudo rm -rf $HOME/rpmbuild/SOURCES/bash-*

BUILD_BASH=0  # Set to 0 to skip building bash from source

if [[ "$BUILD_BASH" -eq 1 ]]; then
  # --- Use a temp directory for SRPM extraction to avoid polluting the repo ---
  SRPM_TMPDIR=".srpm-extract-tmp"
  rm -rf "$SRPM_TMPDIR"
  mkdir -p "$SRPM_TMPDIR"
  pushd "$SRPM_TMPDIR"
  curl -LO https://packages.microsoft.com/azurelinux/3.0/prod/base/srpms/bash-5.2.15-3.azl3.src.rpm
  rpm2cpio bash-5.2.15-3.azl3.src.rpm | cpio -idmv
  mv bash.spec ../SPECS/bash/
  mkdir -p $HOME/rpmbuild/SOURCES
  cp bash-*.tar.gz *.patch *.sig *.sh bash_completion $HOME/rpmbuild/SOURCES/ 2>/dev/null || true
  popd
  rm -rf "$SRPM_TMPDIR"
else
  echo "Skipping bash build as BUILD_BASH=0"
  mkdir -p $HOME/rpmbuild/RPMS/x86_64
  curl -Lo $HOME/rpmbuild/RPMS/x86_64/bash-5.2.15-3.azl3.x86_64.rpm \
    https://packages.microsoft.com/azurelinux/3.0/prod/base/x86_64/bash-5.2.15-3.azl3.x86_64.rpm
fi

# 1) Ensure output dir for Stage RPMs and SPECS
STAGE_DIR="./.pipelines/containerSourceData/busybox/Stage"
STAGE_RPMS="${STAGE_DIR}/RPMS"
STAGE_SPECS="${STAGE_DIR}/SPECS"

mkdir -p "${STAGE_RPMS}"
mkdir -p "${STAGE_SPECS}"

# Copy spec files
cp "$(pwd)/SPECS/busybox/busybox.spec" "${STAGE_SPECS}/"
cp "$(pwd)/SPECS/bash/bash.spec" "${STAGE_SPECS}/"

# 2) Build busybox (and optionally bash) RPMs inside a Fedora container
docker run --rm \
  -v "$HOME/rpmbuild":/root/rpmbuild \
  -v "$(pwd)/SPECS":/src/SPECS:ro \
  fedora:latest \
  bash -lc "
    dnf install -y rpm-build rpmdevtools gcc make bzip2 \
      glibc-static glibc-headers \
      libselinux-devel libsepol-devel \
      kernel-headers kernel-devel \
      libnl3-devel ncurses-devel readline-devel \
      wget yum-utils sharutils zip which && \
    mkdir -p /root/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS} && \
    cp /src/SPECS/busybox/busybox.spec /root/rpmbuild/SPECS/ && \
    cp /src/SPECS/busybox/*.config /root/rpmbuild/SOURCES/ && \
    cp /src/SPECS/busybox/*.patch  /root/rpmbuild/SOURCES/ && \
    wget -O /root/rpmbuild/SOURCES/busybox-1.36.1.tar.bz2 \
         https://www.busybox.net/downloads/busybox-1.36.1.tar.bz2 && \
    rpmbuild -ba /root/rpmbuild/SPECS/busybox.spec --define 'dist .azl3' && \
    if [[ $BUILD_BASH -eq 1 ]]; then \
      cp /src/SPECS/bash/bash.spec /root/rpmbuild/SPECS/ && \
      rpmbuild -ba /root/rpmbuild/SPECS/bash.spec --define 'dist .azl3'; \
    else \
      echo 'Skipping bash build as BUILD_BASH=0'; \
    fi
  "

# 3) Copy the freshly‐built RPMs into your Docker Stage dir
find "$HOME/rpmbuild/RPMS/x86_64/" -name "*fc*.rpm" -delete

cp "$HOME/rpmbuild/RPMS/x86_64/"busybox-*.rpm   "${STAGE_RPMS}/"
cp "$HOME/rpmbuild/RPMS/x86_64/"bash-*.rpm      "${STAGE_RPMS}/"
if ls "$HOME/rpmbuild/RPMS/x86_64/"*fc*.rpm 2>/dev/null; then
  echo "ERROR: Fedora RPMs detected. Only Azure Linux RPMs should be staged."
  exit 1
fi

# 4) Verify the RPMs are staged
rpm -qpl .pipelines/containerSourceData/busybox/Stage/RPMS/busybox-*.rpm

echo "✓ RPMs staged in ${STAGE_RPMS}"
echo "✓ SPECS staged in ${STAGE_SPECS}"