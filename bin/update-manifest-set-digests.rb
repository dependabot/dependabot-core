#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

# Regenerates common/lib/dependabot/manifest_sets/digests.json after the catalog, schema or fixtures change.
#   bin/update-manifest-set-digests.rb          # rewrite the manifest
#   bin/update-manifest-set-digests.rb --check  # exit 1 if it is stale

$LOAD_PATH.unshift(File.expand_path("../common/lib", __dir__))
require "dependabot/manifest_sets/digests"

data_dir = File.expand_path("../common/lib/dependabot/manifest_sets", __dir__)
digests = Dependabot::ManifestSets::Digests

if ARGV.include?("--check")
  next_step = "run bin/update-manifest-set-digests.rb"
  abort("#{digests.manifest_path(data_dir)} is stale; #{next_step}") unless digests.up_to_date?(data_dir)
  puts "manifest-set digests are up to date"
else
  digests.write(data_dir)
  puts "wrote #{digests.manifest_path(data_dir)}"
end
