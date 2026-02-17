#!/usr/bin/env bash
# Install Hex from GitHub main branch to work around httpc compatibility issues
# in newer Erlang/OTP versions that affect Hex 2.3.1

set -e

echo "Installing Hex from GitHub for improved OTP 26/27 compatibility..."
mix archive.install github hexpm/hex branch main --force || {
  echo "GitHub installation failed, falling back to local version..."
  if [ -n "$HEX_VERSION" ]; then
    mix local.hex "$HEX_VERSION" --force --if-missing
  else
    echo "No HEX_VERSION specified and GitHub install failed"
    exit 1
  fi
}
