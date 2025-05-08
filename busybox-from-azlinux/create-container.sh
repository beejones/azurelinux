#!/usr/bin/env bash
ROOT=~/busybox/work.05-06/azurelinux
BASE="$ROOT/.pipelines/containerSourceData"
RPMS_DIR="$BASE/busybox/Stage/RPMS"
SCRIPT="$BASE/scripts/BuildGoldenContainer.sh"
TOOLCHAIN_TARBALL="$RPMS_DIR/toolchain_rpms.tar.gz"

# Ensure the RPMs directory exists
mkdir -p "$RPMS_DIR"

# Ensure the toolchain tarball exists (empty if not needed)
if [[ ! -f "$RPMS_DIR/rpms.tar.gz" ]]; then
  echo "Creating RPMs tarball at $RPMS_DIR/rpms.tar.gz"
  # Only include RPMs if they exist
  shopt -s nullglob
  RPM_FILES=("$RPMS_DIR"/*.rpm)
  if (( ${#RPM_FILES[@]} )); then
    tar czvf "$RPMS_DIR/rpms.tar.gz" -C "$RPMS_DIR" -- *.rpm
  else
    # Create an empty tarball if no RPMs are present (to avoid script failure)
    tar czvf "$RPMS_DIR/rpms.tar.gz" --files-from /dev/null
  fi
  shopt -u nullglob
fi

bash "$SCRIPT" \
  -a "mcr.microsoft.com/azurelinux/base/core:3.0" \
  -b azurelinuxlocal \
  -c "base/busybox" \
  -d "busybox" \
  -e "busybox.name" \
  -f "busybox.pkg" \
  -g "Dockerfile-Busybox" \
  -j OUTPUT \
  -k "$RPMS_DIR/rpms.tar.gz" \
  -l "$BASE" \
  -m "false" \
  -n "false" \
  -p development \
  -q "false" \
  -u "true" \
  -w "$TOOLCHAIN_TARBALL"

# Extract the filesystem of the new container image as a tarball
# ...existing code...

# Extract the filesystem of the new container image as a tarball
IMAGE_NAME="azurelinuxlocal.azurecr.io/base/busybox:latest"
CONTAINER_ID=$(docker create "$IMAGE_NAME")
docker export "$CONTAINER_ID" -o "$ROOT/busybox-base.tar"
#docker rm "$CONTAINER_ID"
echo "Container filesystem exported to $ROOT/busybox-base.tar"

# Run the container interactively (with a shell)
echo "Starting the container for interactive use..."
docker run --rm -it "$IMAGE_NAME" /bin/sh