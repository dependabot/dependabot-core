#!/bin/bash
gh release download --repo dependabot/cli -p "*linux-amd64.tar.gz"
tar xzvf "*.tar.gz" >/dev/null 2>&1
sudo mv dependabot /usr/local/bin
rm "*.tar.gz"

echo "export LOCAL_GITHUB_ACCESS_TOKEN=$GITHUB_TOKEN" >> ~/.bashrc
