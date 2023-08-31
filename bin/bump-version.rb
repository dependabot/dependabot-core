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

# Bump the updater's Gemfile.lock with the new version
`cd updater/ && bundle lock`
unless $?.success?
  puts "Failed to update `updater/Gemfile.lock`"
  exit $?.exitstatus
end
puts new_version
