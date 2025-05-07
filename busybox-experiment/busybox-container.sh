# 1. Make sure BuildKit is enabled (needed for the RUN --mount lines)
export DOCKER_BUILDKIT=1          # or use `docker buildx`

# 2. Prepare Stage/ tree and local repo file
STAGE_DIR=".pipelines/containerSourceData/busybox/Stage"
mkdir -p "${STAGE_DIR}/RPMS"

# Create the local repo file for tdnf
cat > "${STAGE_DIR}/azurelinuxlocal.repo" <<EOF
[localrepo]
name=Local RPMs
baseurl=file:///localrepo/RPMS
enabled=1
gpgcheck=0
priority=1
EOF

# 3. Build the image
docker build --no-cache -f .pipelines/containerSourceData/busybox/Dockerfile-Busybox \
  --build-arg BASE_IMAGE=mcr.microsoft.com/azurelinux/base/core:3.0 \
  --build-arg AZL_VERSION=3.0 \
  --build-arg RPMS_TO_INSTALL="busybox bash" \
  -t busydoc:latest \
  .pipelines/containerSourceData/busybox

# 4. Run the container
docker run --rm -it \
  --name busydoc \
  busydoc:latest \
  bash -c "echo '--- Content of ronnybj.txt from RPM usign bash ---' && cat /usr/share/busybox/ronnybj.txt"