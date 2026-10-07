#!/usr/bin/env bash
go install github.com/dependabot/cli/cmd/dependabot@latest

bundle install

echo "export LOCAL_GITHUB_ACCESS_TOKEN=$GITHUB_TOKEN" >> ~/.bashrc
