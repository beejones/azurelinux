# Understanding the BusyBox RPM and Container Build Process

This document outlines the two main stages involved:
1.  Building a customized BusyBox RPM using a `.spec` file.
2.  Building a container image that utilizes this customized BusyBox RPM.

## 1. Building a Customized BusyBox RPM

The process of building an RPM (RPM Package Manager) package is orchestrated by a `.spec` file. This file is a blueprint that tells the `rpmbuild` tool how to compile the source code, install the compiled binaries, and package them into an RPM file. For BusyBox, this allows for significant customization.

### Key Concepts:

*   **RPM:** A package format used by many Linux distributions to distribute and manage software.
*   **`.spec` file:** A text file containing metadata and instructions for building an RPM.
*   **`rpmbuild`:** The command-line utility that processes the `.spec` file and source code to create RPMs.
*   **BuildRequires:** Dependencies needed only for building the package, not for running it.
*   **Source Files:** These typically include the source code tarball (`.tar.bz2`), patches (`.patch`), and any custom configuration files.

### The `busybox.spec` File Breakdown:

The `busybox.spec` file is divided into several sections, each serving a specific purpose:

1.  **Preamble (Header Section):**
    *   `Name`, `Version`, `Release`: Define the package's identity.
    *   `Summary`: A brief description of the package.
    *   `License`: Specifies the software license (e.g., GPLv2 for BusyBox).
    *   `Source0`, `Source1`, ...: Point to the source tarball (e.g., `busybox-%{version}.tar.bz2`) and any additional source files like default configuration files (`busybox-static.config`, `busybox-petitboot.config`).
    *   `Patch0`, `Patch1`, ...: List patch files to be applied to the source code. These can be for bug fixes, CVEs, or custom modifications.
    *   `BuildRequires`: Lists packages that must be installed on the build system for BusyBox to compile successfully (e.g., `gcc`, `glibc-static`, `libselinux-devel`, `sharutils`, `zip`, `which`).
    *   `Provides`: Can declare virtual provisions, like `bundled(md5-drepper2)`.

2.  **`%description` Section:**
    *   Provides a more detailed description of the package.

3.  **`%prep` (Preparation) Section:**
    *   `%autosetup -p1`: This macro automatically unpacks the source tarball (`Source0`) and applies all listed patches (`Patch0`, `Patch1`, etc.). The `-p1` option strips the first directory level from paths in the patch files.

4.  **`%build` Section:** This is where the actual compilation and customization happen.
    *   `make distclean`: Ensures a clean build environment by removing any artifacts from previous builds. This is done before each variant of BusyBox is built.
    *   **Building `busybox.static` (Primary Variant):**
        *   `cp %{SOURCE1} .config`: Copies a predefined configuration file (e.g., `busybox-static.config`, referenced as `%{SOURCE1}`) to `.config`. This `.config` file dictates which applets and features will be compiled into BusyBox.
        *   **Customization via `sed` and `echo`**:
            *   `sed -i '/^CONFIG_TC[ =]/d' .config`: Removes any existing line related to `CONFIG_TC`.
            *   `echo "# CONFIG_TC is not set" >> .config`: Explicitly disables the `CONFIG_TC` (Traffic Control) feature.
            *   Similar commands are used to disable `CONFIG_TC_CBQ` and other features like `CONFIG_FEATURE_HAVE_RPC`, `CONFIG_FEATURE_MOUNT_NFS`, `CONFIG_FEATURE_INETD_RPC`. This is a key part of tailoring BusyBox to specific needs, reducing its size, or avoiding problematic features.
        *   `yes "" | make oldconfig`: This command processes the `.config` file. It accepts default answers for any new configuration options that might have been introduced in the BusyBox version being built but are not specified in the provided `.config`.
        *   `make V=1 CC="gcc %{optflags}"`: Compiles BusyBox. `V=1` enables verbose output. `CC="gcc %{optflags}"` specifies the compiler and optimization flags.
        *   `cp busybox_unstripped busybox.static`: Copies the compiled, unstripped binary.
        *   `cp docs/busybox.1 docs/busybox.static.1`: Copies the man page.
    *   **Building `busybox.petitboot` (Secondary Variant):**
        *   The process is repeated with a different configuration file (`%{SOURCE2}`, e.g., `busybox-petitboot.config`) to create a variant optimized for Petitboot.
        *   Similar `sed` and `echo` commands are used to customize this variant's configuration.
    *   **Creating `ronnybj.txt`:**
        *   `echo "Ronny was here - BusyBox version: %{version}-%{release}" > ronnybj.txt`: A custom file is created containing a message and the specific version/release of the BusyBox RPM being built. This serves as a marker.
    *   **Downloading Additional RPMs:**
        *   `yumdownloader --destdir %{_rpmdir}/%{_arch} bash`: This command downloads the `bash` RPM into the directory where `rpmbuild` will place the newly built BusyBox RPMs. This ensures `bash` is co-located with the `busybox` artifacts.

5.  **`%install` Section:** This section describes how to install the compiled files into a temporary build root directory (`%{buildroot}`). This directory structure mirrors the final installation path on a target system.
    *   `rm -rf %{buildroot}`: Clears the build root.
    *   `mkdir -p %{buildroot}/sbin`, `mkdir -p %{buildroot}/%{_mandir}/man1`, `mkdir -p %{buildroot}%{_datadir}/busybox`: Creates the necessary directory structure within `%{buildroot}`.
    *   `install -m 755 busybox.static %{buildroot}/sbin/busybox`: Installs the primary `busybox` binary to `/sbin/` in the buildroot.
    *   `install -m 755 busybox.petitboot %{buildroot}/sbin/busybox.petitboot`: Installs the petitboot variant.
    *   `install -m 644 docs/busybox.static.1 %{buildroot}/%{_mandir}/man1/busybox.1`: Installs the man page.
    *   `install -m 644 ronnybj.txt %{buildroot}%{_datadir}/busybox/ronnybj.txt`: Installs the custom `ronnybj.txt` file into `/usr/share/busybox/` within the buildroot.

6.  **`%check` Section:**
    *   `cd testsuite`: Navigates to the BusyBox test suite directory.
    *   `SKIP_KNOWN_BUGS=1 ./runtest -v`: Executes the test suite. The `-v` flag enables verbose output. This step helps ensure the compiled BusyBox behaves as expected.

7.  **`%files` Section:** This is a critical section that lists all the files that should be included in the final RPM package. Paths are relative to the installation root (what `%{buildroot}` represented).
    *   `%license LICENSE`: Includes the license file.
    *   `/sbin/busybox`: Specifies the main busybox binary.
    *   `%{_mandir}/man1/busybox.1*`: Includes the man page (the `*` handles compression like `.gz`).
    *   `%{_datadir}/busybox/ronnybj.txt`: Includes the custom `ronnybj.txt` file.

8.  **`%package petitboot` (Subpackage Definition):**
    *   Allows defining a subpackage (e.g., `busybox-petitboot`). This subpackage will have its own summary and files list.
    *   `%files petitboot`: Lists files specific to the `busybox-petitboot` subpackage (e.g., `/sbin/busybox.petitboot`).

### The `rpmbuild` Process:

When `rpmbuild -ba busybox.spec` is executed (typically within the `scripts/build-busybox.sh` script which sets up a Fedora container environment):
1.  `rpmbuild` reads `busybox.spec`.
2.  It downloads/locates the `Source` files.
3.  It executes the `%prep` section (unpacking, patching).
4.  It executes the `%build` section (compiling, customizing configurations, creating `ronnybj.txt`, downloading `bash`).
5.  It executes the `%install` section (copying files to `%{buildroot}`).
6.  It executes the `%check` section (running tests).
7.  Finally, it packages the files listed in the `%files` sections (for the main package and any subpackages) from `%{buildroot}` into `.rpm` files.

The result is one or more RPM files (e.g., `busybox-%{version}-%{release}.%{_arch}.rpm`, `busybox-petitboot-...rpm`) and the downloaded `bash-...rpm`, all placed in `~/rpmbuild/RPMS/%{_arch}/`. These are then copied to the `./.pipelines/containerSourceData/busybox/Stage/RPMS/` directory by the `scripts/build-busybox.sh` script.

## 2. Building the Container Image

The `Dockerfile-Busybox` file defines the steps to build a container image that includes the customized BusyBox (and Bash) RPMs built in the previous stage.

### Key Concepts:

*   **Dockerfile:** A text file containing instructions to assemble a Docker image.
*   **Build Context:** The set of files at a specified `PATH` or `URL` that Docker can use during the build process.
*   **Stages:** Multi-stage builds allow you to use intermediate images for building and then copy only necessary artifacts to a final, smaller image.
*   **`tdnf`:** A lightweight package manager used in CBL-Mariner/Azure Linux.

### The `Dockerfile-Busybox` Breakdown:

1.  **Arguments (`ARG`):**
    *   `ARG BASE_IMAGE`: Defines the base image for the build stage (e.g., `mcr.microsoft.com/azurelinux/base/core:3.0`).
    *   `ARG AZL_VERSION`: Specifies the Azure Linux version.
    *   `ARG RPMS_TO_INSTALL`: A string listing the RPMs to install (e.g., "busybox bash").
    *   `ARG RPMS_PATH`: Path within the build stage where RPMs are expected (defaults to `/dockerStage/RPMS`).
    *   `ARG LOCAL_REPO_FILE`: Path to a local repository configuration file.

2.  **`BASE` Stage (`FROM $BASE_IMAGE AS BASE`):**
    *   **Create Local RPM Repository:**
        *   `RUN --mount=type=bind,source=./Stage/,target=/dockerStage/ ...`: This is a crucial step.
            *   `--mount=type=bind,source=./Stage/,target=/dockerStage/`: Mounts the `./Stage/` directory (from the host, which contains `RPMS/` sub-directory with our custom BusyBox and Bash RPMs) into the `/dockerStage/` directory within this build stage.
            *   `mkdir -p $LOCAL_REPO_PATH`: Creates a directory (e.g., `/localrepo`) to serve as a local RPM repository.
            *   `tdnf install -y ... createrepo`: Installs the `createrepo` utility.
            *   `cp -r ${RPMS_PATH} ${LOCAL_REPO_PATH}`: Copies the RPMs from the mounted `/dockerStage/RPMS` into the local repository path.
            *   `cp ${LOCAL_REPO_FILE} /etc/yum.repos.d/local.repo`: Copies a predefined `.repo` file to configure `tdnf` to use this local repository.
            *   `createrepo ... ${LOCAL_REPO_PATH}`: Generates the necessary metadata for the local RPM repository.
            *   `tdnf makecache`: Updates `tdnf`'s cache to recognize the new local repository.
            *   `tdnf autoremove -y createrepo`: Removes `createrepo` as it's no longer needed.
    *   **Install Packages into a Staging Location:**
        *   `RUN mkdir /staging`: Creates a temporary staging directory.
        *   `tdnf install -y --releasever=$AZL_VERSION --installroot /staging ${RPMS_TO_INSTALL}`:
            *   This command installs the packages listed in `RPMS_TO_INSTALL` (i.e., our custom `busybox` and `bash`) from the *local repository* created in the previous step.
            *   `--installroot /staging`: Specifies that the packages should be installed as if `/staging` were the root of the filesystem. All files from the RPMs (including `/sbin/busybox` and `/usr/share/busybox/ronnybj.txt`) are placed under `/staging`.
        *   `tdnf clean all`: Cleans up `tdnf` cache.
        *   `mkdir -p /staging/bin && ln -sf /sbin/busybox /staging/bin/sh`: Creates a `/bin` directory in staging and links `/sbin/busybox` to `/staging/bin/sh`, making BusyBox provide the `sh` shell.
    *   **Smoke Tests:**
        *   `RUN chroot /staging /sbin/busybox --install -s /bin`: Runs BusyBox's own install command within the chrooted `/staging` environment to create symlinks for its applets in `/staging/bin`.
        *   `chroot /staging /bin/sh -xec 'true'`: A simple test to ensure the shell works.
        *   Timezone and DNS checks are also performed within the chrooted `/staging` environment.

3.  **Final Stage (`FROM scratch`):**
    *   `FROM scratch`: Starts a new, empty image. This is done to create a minimal final image.
    *   **Copy Artifacts:**
        *   `COPY --from=BASE /staging/ .`: This copies the *entire contents* of the `/staging` directory from the `BASE` stage (which now contains the fully installed filesystem with our custom BusyBox, Bash, and `ronnybj.txt`) into the root of the final `scratch` image.
        *   `COPY --from=BASE EULA-Container.txt /`: Copies the EULA.
    *   **Default Command (`CMD`):**
        *   `CMD [ "sh" ]` (or `CMD [ "/bin/bash" ]` if changed): Sets the default command to execute when a container is run from this image.

### How the Customized RPM is Used in the Container:

1.  The `scripts/build-busybox.sh` script builds the customized `busybox-*.rpm` (containing `ronnybj.txt`) and the downloaded `bash-*.rpm`, placing them in `./.pipelines/containerSourceData/busybox/Stage/RPMS/`.
2.  When `scripts/busybox-container.sh` runs `docker build ...`, the `Dockerfile-Busybox` is processed.
3.  The `RUN --mount` command makes the `Stage/RPMS/` directory (with your custom RPMs) available inside the `BASE` build stage at `/dockerStage/RPMS/`.
4.  A local RPM repository is created within the `BASE` stage using these RPMs.
5.  The `tdnf install ... busybox bash` command installs these packages from this local repository into the `/staging` directory. Because it's using the local repository, it installs *your* version of `busybox` (the one with `ronnybj.txt` and other customizations from the spec file) and the `bash` RPM you downloaded.
6.  Finally, the `COPY --from=BASE /staging/ .` command transfers the entire installed filesystem from `/staging` (including `/sbin/busybox`, `/bin/bash`, and `/usr/share/busybox/ronnybj.txt`) into the final minimal `scratch` image.

This ensures that the container image is built using the precisely customized BusyBox RPM that was generated according to the `busybox.spec` file. The `ronnybj.txt` file, created during the RPM build and containing the version string, serves as proof of this linkage when its content is displayed from within the running container.
```<!-- filepath: /home/ronny/busybox/work.05-06/azurelinux/busybox-experiment/busybox-experiment.md -->
# Understanding the BusyBox RPM and Container Build Process

This document outlines the two main stages involved:
1.  Building a customized BusyBox RPM using a `.spec` file.
2.  Building a container image that utilizes this customized BusyBox RPM.

## 1. Building a Customized BusyBox RPM

The process of building an RPM (RPM Package Manager) package is orchestrated by a `.spec` file. This file is a blueprint that tells the `rpmbuild` tool how to compile the source code, install the compiled binaries, and package them into an RPM file. For BusyBox, this allows for significant customization.

### Key Concepts:

*   **RPM:** A package format used by many Linux distributions to distribute and manage software.
*   **`.spec` file:** A text file containing metadata and instructions for building an RPM.
*   **`rpmbuild`:** The command-line utility that processes the `.spec` file and source code to create RPMs.
*   **BuildRequires:** Dependencies needed only for building the package, not for running it.
*   **Source Files:** These typically include the source code tarball (`.tar.bz2`), patches (`.patch`), and any custom configuration files.

### The `busybox.spec` File Breakdown:

The `busybox.spec` file is divided into several sections, each serving a specific purpose:

1.  **Preamble (Header Section):**
    *   `Name`, `Version`, `Release`: Define the package's identity.
    *   `Summary`: A brief description of the package.
    *   `License`: Specifies the software license (e.g., GPLv2 for BusyBox).
    *   `Source0`, `Source1`, ...: Point to the source tarball (e.g., `busybox-%{version}.tar.bz2`) and any additional source files like default configuration files (`busybox-static.config`, `busybox-petitboot.config`).
    *   `Patch0`, `Patch1`, ...: List patch files to be applied to the source code. These can be for bug fixes, CVEs, or custom modifications.
    *   `BuildRequires`: Lists packages that must be installed on the build system for BusyBox to compile successfully (e.g., `gcc`, `glibc-static`, `libselinux-devel`, `sharutils`, `zip`, `which`).
    *   `Provides`: Can declare virtual provisions, like `bundled(md5-drepper2)`.

2.  **`%description` Section:**
    *   Provides a more detailed description of the package.

3.  **`%prep` (Preparation) Section:**
    *   `%autosetup -p1`: This macro automatically unpacks the source tarball (`Source0`) and applies all listed patches (`Patch0`, `Patch1`, etc.). The `-p1` option strips the first directory level from paths in the patch files.

4.  **`%build` Section:** This is where the actual compilation and customization happen.
    *   `make distclean`: Ensures a clean build environment by removing any artifacts from previous builds. This is done before each variant of BusyBox is built.
    *   **Building `busybox.static` (Primary Variant):**
        *   `cp %{SOURCE1} .config`: Copies a predefined configuration file (e.g., `busybox-static.config`, referenced as `%{SOURCE1}`) to `.config`. This `.config` file dictates which applets and features will be compiled into BusyBox.
        *   **Customization via `sed` and `echo`**:
            *   `sed -i '/^CONFIG_TC[ =]/d' .config`: Removes any existing line related to `CONFIG_TC`.
            *   `echo "# CONFIG_TC is not set" >> .config`: Explicitly disables the `CONFIG_TC` (Traffic Control) feature.
            *   Similar commands are used to disable `CONFIG_TC_CBQ` and other features like `CONFIG_FEATURE_HAVE_RPC`, `CONFIG_FEATURE_MOUNT_NFS`, `CONFIG_FEATURE_INETD_RPC`. This is a key part of tailoring BusyBox to specific needs, reducing its size, or avoiding problematic features.
        *   `yes "" | make oldconfig`: This command processes the `.config` file. It accepts default answers for any new configuration options that might have been introduced in the BusyBox version being built but are not specified in the provided `.config`.
        *   `make V=1 CC="gcc %{optflags}"`: Compiles BusyBox. `V=1` enables verbose output. `CC="gcc %{optflags}"` specifies the compiler and optimization flags.
        *   `cp busybox_unstripped busybox.static`: Copies the compiled, unstripped binary.
        *   `cp docs/busybox.1 docs/busybox.static.1`: Copies the man page.
    *   **Building `busybox.petitboot` (Secondary Variant):**
        *   The process is repeated with a different configuration file (`%{SOURCE2}`, e.g., `busybox-petitboot.config`) to create a variant optimized for Petitboot.
        *   Similar `sed` and `echo` commands are used to customize this variant's configuration.
    *   **Creating `ronnybj.txt`:**
        *   `echo "Ronny was here - BusyBox version: %{version}-%{release}" > ronnybj.txt`: A custom file is created containing a message and the specific version/release of the BusyBox RPM being built. This serves as a marker.
    *   **Downloading Additional RPMs:**
        *   `yumdownloader --destdir %{_rpmdir}/%{_arch} bash`: This command downloads the `bash` RPM into the directory where `rpmbuild` will place the newly built BusyBox RPMs. This ensures `bash` is co-located with the `busybox` artifacts.

5.  **`%install` Section:** This section describes how to install the compiled files into a temporary build root directory (`%{buildroot}`). This directory structure mirrors the final installation path on a target system.
    *   `rm -rf %{buildroot}`: Clears the build root.
    *   `mkdir -p %{buildroot}/sbin`, `mkdir -p %{buildroot}/%{_mandir}/man1`, `mkdir -p %{buildroot}%{_datadir}/busybox`: Creates the necessary directory structure within `%{buildroot}`.
    *   `install -m 755 busybox.static %{buildroot}/sbin/busybox`: Installs the primary `busybox` binary to `/sbin/` in the buildroot.
    *   `install -m 755 busybox.petitboot %{buildroot}/sbin/busybox.petitboot`: Installs the petitboot variant.
    *   `install -m 644 docs/busybox.static.1 %{buildroot}/%{_mandir}/man1/busybox.1`: Installs the man page.
    *   `install -m 644 ronnybj.txt %{buildroot}%{_datadir}/busybox/ronnybj.txt`: Installs the custom `ronnybj.txt` file into `/usr/share/busybox/` within the buildroot.

6.  **`%check` Section:**
    *   `cd testsuite`: Navigates to the BusyBox test suite directory.
    *   `SKIP_KNOWN_BUGS=1 ./runtest -v`: Executes the test suite. The `-v` flag enables verbose output. This step helps ensure the compiled BusyBox behaves as expected.

7.  **`%files` Section:** This is a critical section that lists all the files that should be included in the final RPM package. Paths are relative to the installation root (what `%{buildroot}` represented).
    *   `%license LICENSE`: Includes the license file.
    *   `/sbin/busybox`: Specifies the main busybox binary.
    *   `%{_mandir}/man1/busybox.1*`: Includes the man page (the `*` handles compression like `.gz`).
    *   `%{_datadir}/busybox/ronnybj.txt`: Includes the custom `ronnybj.txt` file.

8.  **`%package petitboot` (Subpackage Definition):**
    *   Allows defining a subpackage (e.g., `busybox-petitboot`). This subpackage will have its own summary and files list.
    *   `%files petitboot`: Lists files specific to the `busybox-petitboot` subpackage (e.g., `/sbin/busybox.petitboot`).

### The `rpmbuild` Process:

When `rpmbuild -ba busybox.spec` is executed (typically within the `scripts/build-busybox.sh` script which sets up a Fedora container environment):
1.  `rpmbuild` reads `busybox.spec`.
2.  It downloads/locates the `Source` files.
3.  It executes the `%prep` section (unpacking, patching).
4.  It executes the `%build` section (compiling, customizing configurations, creating `ronnybj.txt`, downloading `bash`).
5.  It executes the `%install` section (copying files to `%{buildroot}`).
6.  It executes the `%check` section (running tests).
7.  Finally, it packages the files listed in the `%files` sections (for the main package and any subpackages) from `%{buildroot}` into `.rpm` files.

The result is one or more RPM files (e.g., `busybox-%{version}-%{release}.%{_arch}.rpm`, `busybox-petitboot-...rpm`) and the downloaded `bash-...rpm`, all placed in `~/rpmbuild/RPMS/%{_arch}/`. These are then copied to the `./.pipelines/containerSourceData/busybox/Stage/RPMS/` directory by the `scripts/build-busybox.sh` script.

## 2. Building the Container Image

The `Dockerfile-Busybox` file defines the steps to build a container image that includes the customized BusyBox (and Bash) RPMs built in the previous stage.

### Key Concepts:

*   **Dockerfile:** A text file containing instructions to assemble a Docker image.
*   **Build Context:** The set of files at a specified `PATH` or `URL` that Docker can use during the build process.
*   **Stages:** Multi-stage builds allow you to use intermediate images for building and then copy only necessary artifacts to a final, smaller image.
*   **`tdnf`:** A lightweight package manager used in CBL-Mariner/Azure Linux.

### The `Dockerfile-Busybox` Breakdown:

1.  **Arguments (`ARG`):**
    *   `ARG BASE_IMAGE`: Defines the base image for the build stage (e.g., `mcr.microsoft.com/azurelinux/base/core:3.0`).
    *   `ARG AZL_VERSION`: Specifies the Azure Linux version.
    *   `ARG RPMS_TO_INSTALL`: A string listing the RPMs to install (e.g., "busybox bash").
    *   `ARG RPMS_PATH`: Path within the build stage where RPMs are expected (defaults to `/dockerStage/RPMS`).
    *   `ARG LOCAL_REPO_FILE`: Path to a local repository configuration file.

2.  **`BASE` Stage (`FROM $BASE_IMAGE AS BASE`):**
    *   **Create Local RPM Repository:**
        *   `RUN --mount=type=bind,source=./Stage/,target=/dockerStage/ ...`: This is a crucial step.
            *   `--mount=type=bind,source=./Stage/,target=/dockerStage/`: Mounts the `./Stage/` directory (from the host, which contains `RPMS/` sub-directory with our custom BusyBox and Bash RPMs) into the `/dockerStage/` directory within this build stage.
            *   `mkdir -p $LOCAL_REPO_PATH`: Creates a directory (e.g., `/localrepo`) to serve as a local RPM repository.
            *   `tdnf install -y ... createrepo`: Installs the `createrepo` utility.
            *   `cp -r ${RPMS_PATH} ${LOCAL_REPO_PATH}`: Copies the RPMs from the mounted `/dockerStage/RPMS` into the local repository path.
            *   `cp ${LOCAL_REPO_FILE} /etc/yum.repos.d/local.repo`: Copies a predefined `.repo` file to configure `tdnf` to use this local repository.
            *   `createrepo ... ${LOCAL_REPO_PATH}`: Generates the necessary metadata for the local RPM repository.
            *   `tdnf makecache`: Updates `tdnf`'s cache to recognize the new local repository.
            *   `tdnf autoremove -y createrepo`: Removes `createrepo` as it's no longer needed.
    *   **Install Packages into a Staging Location:**
        *   `RUN mkdir /staging`: Creates a temporary staging directory.
        *   `tdnf install -y --releasever=$AZL_VERSION --installroot /staging ${RPMS_TO_INSTALL}`:
            *   This command installs the packages listed in `RPMS_TO_INSTALL` (i.e., our custom `busybox` and `bash`) from the *local repository* created in the previous step.
            *   `--installroot /staging`: Specifies that the packages should be installed as if `/staging` were the root of the filesystem. All files from the RPMs (including `/sbin/busybox` and `/usr/share/busybox/ronnybj.txt`) are placed under `/staging`.
        *   `tdnf clean all`: Cleans up `tdnf` cache.
        *   `mkdir -p /staging/bin && ln -sf /sbin/busybox /staging/bin/sh`: Creates a `/bin` directory in staging and links `/sbin/busybox` to `/staging/bin/sh`, making BusyBox provide the `sh` shell.
    *   **Smoke Tests:**
        *   `RUN chroot /staging /sbin/busybox --install -s /bin`: Runs BusyBox's own install command within the chrooted `/staging` environment to create symlinks for its applets in `/staging/bin`.
        *   `chroot /staging /bin/sh -xec 'true'`: A simple test to ensure the shell works.
        *   Timezone and DNS checks are also performed within the chrooted `/staging` environment.

3.  **Final Stage (`FROM scratch`):**
    *   `FROM scratch`: Starts a new, empty image. This is done to create a minimal final image.
    *   **Copy Artifacts:**
        *   `COPY --from=BASE /staging/ .`: This copies the *entire contents* of the `/staging` directory from the `BASE` stage (which now contains the fully installed filesystem with our custom BusyBox, Bash, and `ronnybj.txt`) into the root of the final `scratch` image.
        *   `COPY --from=BASE EULA-Container.txt /`: Copies the EULA.
    *   **Default Command (`CMD`):**
        *   `CMD [ "sh" ]` (or `CMD [ "/bin/bash" ]` if changed): Sets the default command to execute when a container is run from this image.

### How the Customized RPM is Used in the Container:

1.  The `scripts/build-busybox.sh` script builds the customized `busybox-*.rpm` (containing `ronnybj.txt`) and the downloaded `bash-*.rpm`, placing them in `./.pipelines/containerSourceData/busybox/Stage/RPMS/`.
2.  When `scripts/busybox-container.sh` runs `docker build ...`, the `Dockerfile-Busybox` is processed.
3.  The `RUN --mount` command makes the `Stage/RPMS/` directory (with your custom RPMs) available inside the `BASE` build stage at `/dockerStage/RPMS/`.
4.  A local RPM repository is created within the `BASE` stage using these RPMs.
5.  The `tdnf install ... busybox bash` command installs these packages from this local repository into the `/staging` directory. Because it's using the local repository, it installs *your* version of `busybox` (the one with `ronnybj.txt` and other customizations from the spec file) and the `bash` RPM you downloaded.
6.  Finally, the `COPY --from=BASE /staging/ .` command transfers the entire installed filesystem from `/staging` (including `/sbin/busybox`, `/bin/bash`, and `/usr/share/busybox/ronnybj.txt`) into the final minimal `scratch` image.

This ensures that the container image is built using the precisely customized BusyBox RPM that was generated according to the `busybox.spec` file. The `ronnybj.txt` file, created during the RPM build and containing the version string, serves as proof of this linkage when its content is displayed from within the running container.