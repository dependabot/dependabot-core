#!/usr/bin/env ruby
# frozen_string_literal: true

unless %w(minor patch).include?(ARGV[0])
  puts "usage: bin/bump-version.rb minor|patch [--dry-run]"
  exit 1
end
component = ARGV[0].to_sym
dry_run = ARGV[1] == "--dry-run"

# rubocop:disable Lint/LiteralAsCondition
unless `which gh` && $?.success?
  puts "Please install the gh cli: brew install gh"
  exit 1
end

unless `gh auth status -h github.com > /dev/null 2>&1` && $?.success?
  puts "Please login to GitHub first: gh auth login"
  exit 1
end
# rubocop:enable Lint/LiteralAsCondition

CHANGELOG_PATH = File.join(__dir__, "..", "CHANGELOG.md")
CHANGELOG_CONTENTS = File.read(CHANGELOG_PATH)

def proposed_changes(version, _new_version)
  dependabot_team = `gh api -X GET 'orgs/dependabot/teams/maintainers/members' --jq '.[].login'`
  dependabot_team = dependabot_team.split("\n").map(&:strip) + ["dependabot"]

  commit_subjects = `git log --pretty="%s" v#{version}..HEAD`.lines
  merge_subjects = commit_subjects.select do |s|
    s.downcase.start_with?("merge pull request #") && !s.match?(/release[-_\s]notes/i)
  end
  pr_numbers = merge_subjects.map { |s| s.match(/#(\d+)/)[1].to_i }
  puts "⏳ fetching pull request details"
  pr_details = pr_numbers.map do |pr_number|
    pr_details = `gh pr view #{pr_number} --json title,author --jq ".title,.author.login"`
    title, author = pr_details.split("\n").map(&:strip)
    {
      title: title,
      author: author,
      number: pr_number
    }
  end

  pr_details.map do |details|
    line = "- #{details[:title]}"
    line += " (@#{details[:author]})" unless dependabot_team.include?(details[:author])
    line += " PR ##{details[:number]}"
    line
  end
end

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

if dry_run
  puts "Would update version file:"
  puts new_version_contents
else
  File.write(version_path, new_version_contents)
  puts "☑️  common/lib/dependabot/version.rb updated"

end

proposed_changes = proposed_changes(version, new_version)

# Update CHANGELOG
if dry_run
  puts "Would update CHANGELOG:"
  puts proposed_changes
else
  new_changelog_contents = [
    "## v#{new_version}, #{Time.now.strftime('%e %B %Y').strip}\n",
    proposed_changes.join("\n") + "\n",
    CHANGELOG_CONTENTS
  ].join("\n")

  File.write(CHANGELOG_PATH, new_changelog_contents)
  puts "☑️  CHANGELOG.md updated"
end

unless dry_run
  puts
  puts "Double check the changes (editing CHANGELOG.md where necessary), then"
  puts "commit, tag, and push the release:"
  puts
  puts "git checkout -b v#{new_version}-release-notes"
  puts "git add CHANGELOG.md common/lib/dependabot/version.rb"
  puts "git commit -m 'v#{new_version}'"
  puts "git push origin HEAD:v#{new_version}-release-notes"
  puts "# ... create PR, verify, merge, for example:"
  puts "gh pr create"
  puts "# tag the approved release notes:"
  puts "git fetch"
  puts "git tag 'v#{new_version}' 'origin/v#{new_version}-release-notes'"
  puts "git push origin v#{new_version}"
  puts
end
