#!/usr/bin/env ruby
# frozen_string_literal: true

unless %w(minor patch).include?(ARGV[0])
  puts "usage: bin/bump-version.rb minor|patch"
  exit 1
end
component = ARGV[0].to_sym

# Update version file
version_path = File.join(__dir__, "..", "common", "lib", "dependabot.rb")
version_contents = File.read(version_path)

version = version_contents.scan(/\d+.\d+.\d+/).first
segments = Gem::Version.new(version).segments
new_version =
  case component
  when :minor
    [segments[0], segments[1] + 1, 0].join(".")
  when :patch
    [segments[0], segments[1], segments[2] + 1].join(".")
  end

new_version_contents = version_contents.gsub(version, new_version)

File.write(version_path, new_version_contents)
puts "☑️  common/lib/dependabot.rb updated"

# Bump the updater's Gemfile.lock with the new version
`cd updater/ && bundle lock`
puts "☑️  updater/Gemfile.lock updated"
puts
puts "Now, create the PR"
puts
puts "git checkout -b v#{new_version}"
puts "git add common/lib/dependabot.rb updater/Gemfile.lock"
puts "git commit -m 'v#{new_version}'"
puts "git push origin HEAD:v#{new_version}"
puts "# ... create PR and merge after getting it approved."
# TODO all steps up to here should be automatically handled by the workflow...
# also, the workflow can accept as input minor/patch, and default to minor... so weekly cadence is minor.
# first step though is getting the action working manually, then move it to cron
# see example in https://github.com/dependabot/fetch-metadata/pull/347
# the PR should be manually reviewed/merged, and then the release notes manually tagged (so that a human can review the release notes)
#
# TODO: also update the placeholder gem description for `dependabot-core` gem on RubyGems
puts
puts "Once the PR is merged, create a new release tagged with that version using the format `v1.2.3`"
puts
puts "* You can do this via the web UI: https://github.com/dependabot/dependabot-core/releases/new"
puts "  Use the 'Generate release notes' button and then edit as needed."
puts "* Or via the GitHub CLI:"
# TODO this example command can be displayed on the github action summary screen
puts "    gh release create v1.X.X --generate-notes --draft"
puts "    > https://github.com/dependabot/fetch-metadata/releases/tag/untagged-XXXXXX"
puts "    # Use the generated URL to review/edit the release notes, and then publish it."
puts
puts "Once the release is tagged, it will be automatically pushed to RubyGems."
