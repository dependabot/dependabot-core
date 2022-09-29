#!/bin/bash
# This pull takes a while, adding it to the prebuild
docker pull ghcr.io/dependabot/dependabot-updater:latest
docker pull ghcr.io/github/dependabot-update-job-proxy/dependabot-update-job-proxy:latest
