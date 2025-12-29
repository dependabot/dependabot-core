#!/usr/bin/env bash
# Native helper entry point for Lean/Lake operations
# Reads JSON from stdin, executes the requested function, outputs JSON to stdout

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/functions.sh"

# Read JSON input from stdin
input=$(cat)

# Extract function name and args
function_name=$(echo "$input" | jq -r '.function')
args=$(echo "$input" | jq -r '.args')

case "$function_name" in
  "update_all")
    lake_update_all "$args"
    ;;
  "check_updates")
    lake_check_updates "$args"
    ;;
  "get_manifest")
    lake_get_manifest "$args"
    ;;
  *)
    echo '{"error": "Unknown function: '"$function_name"'"}'
    exit 1
    ;;
esac
