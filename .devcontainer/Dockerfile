# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.245.2/containers/ubuntu/.devcontainer/base.Dockerfile

# [Choice] Ubuntu version (use ubuntu-22.04 or ubuntu-18.04 on local arm64/Apple Silicon): ubuntu-22.04, ubuntu-20.04, ubuntu-18.04
ARG VARIANT="jammy"
FROM mcr.microsoft.com/vscode/devcontainers/base:0-${VARIANT}

# [Optional] Uncomment this section to install additional OS packages.
# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends <your-package-list-here>

# Configures Ubuntu to use Azure mirrors, which are often faster and more reliable
# From https://github.com/Azure/LinuxPatchExtension/blob/master/src/tools/references/apt/sources.list.d/ubuntu.sources
# This is also used in other places such as the runner builds: https://github.com/actions/runner-images/blob/2f8d6ab9ef24fd8bda80b5259650fe1dc4311320/images/ubuntu/scripts/build/configure-apt-sources.sh#L11
RUN set -e; \
    release=$( . /etc/os-release && echo "$VERSION_CODENAME" ); \
    cat <<EOF | tee /etc/apt/sources.list.d/ubuntu.sources

# Prefer Azure mirrors
Types: deb
URIs: http://azure.archive.ubuntu.com/ubuntu/
Suites: ${release} ${release}-updates ${release}-backports
Components: main universe restricted multiverse
Architectures: i386,amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://azure.archive.ubuntu.com/ubuntu/
Suites: ${release}-security
Components: main universe restricted multiverse
Architectures: i386,amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

# Fallback to the main Ubuntu archive if the above is not available
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: ${release} ${release}-updates ${release}-backports
Components: main universe restricted multiverse
Architectures: i386,amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

# Ports Ubuntu archive is the only mirror with arm64 support
Types: deb
URIs: http://ports.ubuntu.com/
Suites: ${release} ${release}-updates ${release}-backports
Components: main universe restricted multiverse
Architectures: arm64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: ${release}-security
Components: main universe restricted multiverse
Architectures: i386,amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

EOF

