#!/usr/bin/env bash
set -euo pipefail

smoke_file="${1:-}"
suite_name="${2:-}"

if [[ -z "$smoke_file" || -z "$suite_name" ]]; then
  echo "usage: apply_smoke_overrides.sh <smoke.yaml> <suite-name>" >&2
  exit 1
fi

case "$suite_name" in
  smoke-poetry.yaml|smoke-python-poetry.yaml)
    ;;
  *)
    exit 0
    ;;
esac

if ! grep -q '^        ignore-conditions:' "$smoke_file"; then
  exit 0
fi

if ! grep -q 'directory: /poetry' "$smoke_file"; then
  exit 0
fi

if ! grep -q 'name = "certifi"' "$smoke_file"; then
  exit 0
fi

if grep -q 'dependency-name: certifi' "$smoke_file"; then
  exit 0
fi

certifi_version="$({
  awk '
    /name = "certifi"/ { in_certifi=1; next }
    in_certifi && /version = "/ {
      if (match($0, /"[^"]+"/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  ' "$smoke_file"
} || true)"

if [[ -z "$certifi_version" ]]; then
  exit 0
fi

awk -v certifi_version="$certifi_version" -v suite_name="$suite_name" '
  {
    if (!inserted && $0 ~ /^        source:$/) {
      print "            - dependency-name: certifi"
      print "              source: tests/" suite_name
      print "              version-requirement: \">" certifi_version "\""
      inserted = 1
    }
    print
  }
' "$smoke_file" > "$smoke_file.tmp"

mv "$smoke_file.tmp" "$smoke_file"
