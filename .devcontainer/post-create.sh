#!/usr/bin/env bash
gh release download --repo dependabot/cli -p "*linux-amd64.tar.gz"
tar xzvf ./*.tar.gz >/dev/null 2>&1
sudo mv dependabot /usr/local/bin
rm ./*.tar.gz

# The image comes loaded with 8.0 SDK, but we need the 7.0 and 9.0 runtimes for running tests
sudo wget https://dot.net/v1/dotnet-install.sh
sudo chmod +x dotnet-install.sh
sudo ./dotnet-install.sh -c 7.0 --runtime dotnet --install-dir /usr/share/dotnet/shared
sudo ./dotnet-install.sh -c 9.0 --install-dir /usr/share/dotnet
sudo rm ./dotnet-install.sh

echo "export LOCAL_GITHUB_ACCESS_TOKEN=$GITHUB_TOKEN" >> ~/.bashrc
