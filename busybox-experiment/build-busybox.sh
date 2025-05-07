#!/usr/bin/env bash
set -euo pipefail

sudo rm -f $HOME/rpmbuild/RPMS/x86_64/*.rpm
sudo rm -f $HOME/rpmbuild/RPMS/x86_64/busybox-*.rpm
sudo rm -f $HOME/rpmbuild/RPMS/x86_64/bash-*.rpm
sudo rm -f .pipelines/containerSourceData/busybox/Stage/RPMS/*

# 1) Ensure output dir for Stage RPMs and SPECS
STAGE_DIR="./.pipelines/containerSourceData/busybox/Stage"
STAGE_RPMS="${STAGE_DIR}/RPMS"
STAGE_SPECS="${STAGE_DIR}/SPECS" # Define SPECS staging directory

mkdir -p "${STAGE_RPMS}"
mkdir -p "${STAGE_SPECS}" # Create SPECS staging directory

# Copy spec files (adjust path if your spec files are elsewhere)
cp "$(pwd)/SPECS/busybox/busybox.spec" "${STAGE_SPECS}/"
# Add other spec files if needed, e.g., cp "$(pwd)/SPECS/bash/bash.spec" "${STAGE_SPECS}/"


# 2) Build busybox (and bash) RPMs inside a Fedora container
# ... (rest of your docker run command to build RPMs) ...
# The existing docker run command for rpmbuild should remain as is.
# It uses -v "$(pwd)/SPECS":/src/SPECS:ro to access specs for building.
# The STAGE_SPECS directory is for the *next* script (busybox-container.sh)
# if it needs to mount them into the final running container.
docker run --rm \
  -v "$HOME/rpmbuild":/root/rpmbuild \
  -v "$(pwd)/SPECS":/src/SPECS:ro \
  fedora:latest \
  bash -lc "
    dnf install -y rpm-build gcc make bzip2 \
      glibc-static glibc-headers \
      libselinux-devel libsepol-devel \
      kernel-headers kernel-devel \
      libnl3-devel \
      wget yum-utils sharutils zip which && \
    mkdir -p /root/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS} && \
    cp /src/SPECS/busybox/busybox.spec /root/rpmbuild/SPECS/ && \
    cp /src/SPECS/busybox/*.config /root/rpmbuild/SOURCES/ && \
    cp /src/SPECS/busybox/*.patch  /root/rpmbuild/SOURCES/ && \
    wget -O /root/rpmbuild/SOURCES/busybox-1.36.1.tar.bz2 \
         https://www.busybox.net/downloads/busybox-1.36.1.tar.bz2 && \
    cd /root/rpmbuild/SPECS && rpmbuild -ba busybox.spec --define 'dist .azl3'
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
echo "✓ SPECS staged in ${STAGE_SPECS}" # Added for clarity