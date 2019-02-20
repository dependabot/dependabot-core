#!/usr/bin/env ruby
# frozen_string_literal: true

unless %w(minor patch).include?(ARGV[0])
  puts "usage: bin/bump-version.rb minor|patch"
  exit 1
end
component = ARGV[0].to_sym

# Update version file
version_path = File.join(__dir__, "..", "common", "lib", "dependabot",
                         "version.rb")
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
File.open(version_path, "w") { |f| f.write(new_version_contents) }

puts "✓ common/lib/dependabot/version.rb updated"

# Update CHANGELOG

changelog_path = File.join(__dir__, "..", "CHANGELOG.md")
changelog_contents = File.read(changelog_path)

commit_subjects = `git log --pretty="%s" v#{version}..HEAD`.lines
proposed_changes = commit_subjects.map { |line| "- #{line}" }.join("")

new_changelog_contents = [
  "## v#{new_version}, #{Time.now.strftime('%e %B %Y').strip}\n",
  proposed_changes,
  changelog_contents
].join("\n")
File.open(changelog_path, "w") { |f| f.write(new_changelog_contents) }

puts "✓ CHANGELOG.md updated"
puts
puts "Double check the changes (editing CHANGELOG.md where necessary), then"
puts "commit, tag, and push the release:"
puts
puts "git add CHANGELOG.md common/lib/dependabot/version.rb"
puts "git commit -m 'v#{new_version}'"
puts "git tag 'v#{new_version}'"
puts "git push --tags origin master"
puts
