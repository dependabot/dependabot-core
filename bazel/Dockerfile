FROM ghcr.io/dependabot/dependabot-updater-core
# Install Bazel
RUN apt-get update && \
	apt-get install -y apt-transport-https curl gnupg && \
	curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor > /usr/share/keyrings/bazel-archive-keyring.gpg && \
	echo "deb [signed-by=/usr/share/keyrings/bazel-archive-keyring.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" > /etc/apt/sources.list.d/bazel.list && \
	apt-get update && \
	apt-get install -y bazel && \
	apt-get clean && rm -rf /var/lib/apt/lists/*
