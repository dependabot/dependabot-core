#!/usr/bin/env bash
# Shell functions for Lake package manager operations

# Ensure elan is in PATH
export PATH="$HOME/.elan/bin:$PATH"

# Update all Lake dependencies
# Input: JSON with "directory" field
# Output: JSON with updated lake-manifest.json content
lake_update_all() {
  local args="$1"
  local dir=$(echo "$args" | jq -r '.directory // "."')

  cd "$dir" || {
    echo '{"error": "Directory not found: '"$dir"'"}'
    return 1
  }

  # Set up the toolchain if lean-toolchain exists
  if [ -f "lean-toolchain" ]; then
    toolchain=$(cat lean-toolchain)
    elan override set "$toolchain" 2>/dev/null || true
  fi

  # Run lake update
  local update_output
  if ! update_output=$(lake update 2>&1); then
    echo '{"error": "lake update failed", "output": '"$(echo "$update_output" | jq -Rs .)"'}'
    return 1
  fi

  # Read the updated manifest
  if [ -f "lake-manifest.json" ]; then
    local manifest_content
    manifest_content=$(cat lake-manifest.json)

    # Also read lean-toolchain if it exists
    local toolchain_content=""
    if [ -f "lean-toolchain" ]; then
      toolchain_content=$(cat lean-toolchain)
    fi

    echo '{"result": {"lake_manifest": '"$manifest_content"', "lean_toolchain": '"$(echo "$toolchain_content" | jq -Rs .)"', "output": '"$(echo "$update_output" | jq -Rs .)"'}}'
  else
    echo '{"error": "lake-manifest.json not found after update"}'
    return 1
  fi
}

# Check for available updates without applying them
# Input: JSON with "directory" field
# Output: JSON with update availability info
lake_check_updates() {
  local args="$1"
  local dir=$(echo "$args" | jq -r '.directory // "."')

  cd "$dir" || {
    echo '{"error": "Directory not found: '"$dir"'"}'
    return 1
  }

  # Set up the toolchain
  if [ -f "lean-toolchain" ]; then
    toolchain=$(cat lean-toolchain)
    elan override set "$toolchain" 2>/dev/null || true
  fi

  # Store original manifest
  local original_manifest=""
  if [ -f "lake-manifest.json" ]; then
    original_manifest=$(cat lake-manifest.json)
  fi

  # Run lake update in a temporary copy to check what would change
  local temp_dir=$(mktemp -d)
  cp -r . "$temp_dir/"
  cd "$temp_dir" || {
    echo '{"error": "Failed to create temp directory"}'
    return 1
  }

  local update_output
  update_output=$(lake update 2>&1) || true

  local updated_manifest=""
  if [ -f "lake-manifest.json" ]; then
    updated_manifest=$(cat lake-manifest.json)
  fi

  # Clean up temp directory
  cd - > /dev/null
  rm -rf "$temp_dir"

  # Compare manifests
  local has_updates="false"
  if [ "$original_manifest" != "$updated_manifest" ]; then
    has_updates="true"
  fi

  echo '{"result": {"has_updates": '"$has_updates"', "original_manifest": '"${original_manifest:-null}"', "updated_manifest": '"${updated_manifest:-null}"'}}'
}

# Get the current lake-manifest.json content
# Input: JSON with "directory" field
# Output: JSON with manifest content
lake_get_manifest() {
  local args="$1"
  local dir=$(echo "$args" | jq -r '.directory // "."')

  cd "$dir" || {
    echo '{"error": "Directory not found: '"$dir"'"}'
    return 1
  }

  if [ -f "lake-manifest.json" ]; then
    local manifest_content
    manifest_content=$(cat lake-manifest.json)
    echo '{"result": {"manifest": '"$manifest_content"'}}'
  else
    echo '{"error": "lake-manifest.json not found"}'
    return 1
  fi
}
