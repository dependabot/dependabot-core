#!/bin/bash
# Prebuilding Python since it takes a long time. This also gets us a pre-built update-core image
# which will make building all of the other images faster too. If another image is taking a long
# time to build, consider adding it here.
script/build python
docker pull ghcr.io/github/dependabot-update-job-proxy/dependabot-update-job-proxy:latest
