#!/usr/bin/env ruby
# frozen_string_literal: true

# Applies suite-specific smoke input overrides without rewriting YAML formatting.
# This keeps smoke expectations deterministic while preserving raw fixture style.

smoke_file = ARGV[0]
suite_name = ARGV[1]

if smoke_file.nil? || suite_name.nil?
  warn "usage: apply_smoke_overrides.rb <smoke.yaml> <suite-name>"
  exit 1
end

content = File.read(smoke_file)

# Keep this policy narrow and explicit. These suites use Poetry lockfiles where
# transitive certifi releases can cause unrelated expectation churn.
poetry_suites = ["smoke-poetry.yaml", "smoke-python-poetry.yaml"]
unless poetry_suites.include?(suite_name)
  exit 0
end

unless content.include?("        ignore-conditions:") &&
       content.include?("directory: /poetry") &&
       content.include?("name = \"certifi\"")
  exit 0
end

exit 0 if content.include?("dependency-name: certifi")

certifi_version_match = content.match(/name = "certifi".*?\n\s*version = "([^"]+)"/m)
exit 0 unless certifi_version_match

certifi_version = certifi_version_match[1]
insert_block = [
  "            - dependency-name: certifi",
  "              source: tests/#{suite_name}",
  "              version-requirement: \">#{certifi_version}\""
].join("\n")

updated = content.sub(/^        source:$/, "#{insert_block}\n        source:")

# If we cannot find the input source anchor, do not change anything.
exit 0 if updated == content

File.write(smoke_file, updated)
