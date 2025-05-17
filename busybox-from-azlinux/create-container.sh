#!/usr/bin/env bash
set -uxo pipefail

#--------------------------------------------------------------------
# Paths
#--------------------------------------------------------------------
ROOT=~/azurelinux
BASE="$ROOT/busybox-from-azlinux"
PKGBLD_RPMS="$ROOT/out/RPMS/x86_64"
PIPELINES="$ROOT/.pipelines"
SCRIPT="$PIPELINES/containerSourceData/scripts/BuildGoldenContainer.sh"
TOOLCHAIN_TARBALL="$PKGBLD_RPMS/toolchain_rpms.tar.gz"

#--------------------------------------------------------------------
# Image housekeeping
#--------------------------------------------------------------------
IMAGE_NAME="azurelinuxlocal.azurecr.io/base/busybox:latest"
if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "Removing old image $IMAGE_NAME..."
    docker rmi -f "$IMAGE_NAME"
    docker system prune -f
fi

#--------------------------------------------------------------------
# Verify RPM contains the test file
#--------------------------------------------------------------------
sudo chown -R "$USER":"$USER" "$PKGBLD_RPMS"
ls -l "$PKGBLD_RPMS"/*.rpm

echo "Checking if /busybox/ronnybj.txt is part of the RPM..."
if ! rpm -qlp "$PKGBLD_RPMS/busybox-1.36.1-10.azl3.x86_64.rpm" \
        | grep -q '/busybox/ronnybj.txt'; then
    echo "Error: /busybox/ronnybj.txt is not part of the RPM. Aborting."
    exit 1
fi
echo "/busybox/ronnybj.txt is present in the RPM."

#--------------------------------------------------------------------
# Re-create rpms.tar.gz expected by BuildGoldenContainer.sh
#--------------------------------------------------------------------
echo "Recreating RPMs tarball at $PKGBLD_RPMS/rpms.tar.gz"
rm -rf "$PKGBLD_RPMS/RPMS"
mkdir -p "$PKGBLD_RPMS/RPMS"
cp "$PKGBLD_RPMS"/*.rpm "$PKGBLD_RPMS/RPMS/"
(
    cd "$PKGBLD_RPMS"
    tar czf rpms.tar.gz RPMS
)

#--------------------------------------------------------------------
# Ensure (possibly empty) toolchain tarball exists
#--------------------------------------------------------------------
if [[ ! -f "$TOOLCHAIN_TARBALL" ]]; then
    echo "Creating empty toolchain RPM tarball at $TOOLCHAIN_TARBALL"
    tar czf "$TOOLCHAIN_TARBALL" --files-from /dev/null
fi

echo "RPM dir:" "$PKGBLD_RPMS"

# Ensure the local repo file exists in the build context
if [[ ! -f "$BASE/azurelinuxlocal.repo" ]]; then
    cp "$PIPELINES/containerSourceData/azurelinuxlocal.repo" "$BASE/azurelinuxlocal.repo"
fi

# Optional: Show contents of the local repo file for debugging
if [[ -f "$BASE/azurelinuxlocal.repo" ]]; then
    echo "Contents of $BASE/azurelinuxlocal.repo:"
    cat "$BASE/azurelinuxlocal.repo"
else
    echo "WARNING: $BASE/azurelinuxlocal.repo does not exist!"
fi

#--------------------------------------------------------------------
# Extract version from RPM filename on host (not inside container)
#--------------------------------------------------------------------
COMPONENT_VERSION=$(ls "$PKGBLD_RPMS"/busybox-*.rpm | head -n1 | sed -E 's/.*busybox-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)\..*/\1/')
echo "Extracted component version: $COMPONENT_VERSION"

mkdir -p "$BASE/scripts"
ln -sf "$PIPELINES/containerSourceData/scripts/BuildContainerCommonSteps.sh" \
    "$BASE/scripts/BuildContainerCommonSteps.sh"

cp "$PIPELINES/containerSourceData/Dockerfile-Initial" \
   "$BASE/Dockerfile-Initial"

#--------------------------------------------------------------------
# Invoke the helper that builds the container
#--------------------------------------------------------------------
bash "$SCRIPT" \
    -a "mcr.microsoft.com/azurelinux/base/core:3.0" \
    -b azurelinuxlocal \
    -c "base/busybox" \
    -d "busybox" \
    -e "busybox.name" \
    -f "busybox.pkg" \
    -g "Dockerfile-Busybox" \
    -j OUTPUT \
    -k "$PKGBLD_RPMS/rpms.tar.gz" \
    -l "$BASE" \
    -m "false" \
    -n "false" \
    -p development \
    -q "false" \
    -u "true" \
    -w "$TOOLCHAIN_TARBALL" \
    -v "echo $COMPONENT_VERSION"

echo "BuildGoldenContainer.sh exited with code $?"


# Tag the image with :latest locally
docker tag azurelinuxlocal.azurecr.io/base/busybox azurelinuxlocal.azurecr.io/base/busybox:latest

#--------------------------------------------------------------------
# Export the image filesystem and open a shell for inspection
#--------------------------------------------------------------------
CONTAINER_ID=$(docker create "$IMAGE_NAME")
docker export "$CONTAINER_ID" -o "$ROOT/busybox-base.tar"
docker rm "$CONTAINER_ID"
echo "Container filesystem exported to $ROOT/busybox-base.tar"
echo "Starting the container for interactive use..."
docker run --rm -it azurelinuxlocal.azurecr.io/base/busybox:latest sh