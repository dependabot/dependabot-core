#!/usr/bin/env ruby
# frozen_string_literal: true

unless %w(minor patch).include?(ARGV[0])
  puts "usage: bin/bump-version.rb minor|patch"
  exit 1
end
component = ARGV[0].to_sym

unless `which gh` && $?.success?
  puts "Please install the gh cli: brew install gh"
  exit 1
end

unless `gh auth status -h github.com > /dev/null 2>&1` && $?.success?
  puts "Please login to GitHub first: gh auth login"
  exit 1
end

dependabot_team = `gh api -X GET 'orgs/dependabot/teams/reviewers/members' --jq '.[].login'`
dependabot_team = dependabot_team.split("\n").map(&:strip) + ["dependabot"]

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

puts "☑️  common/lib/dependabot/version.rb updated"

# Update CHANGELOG
changelog_path = File.join(__dir__, "..", "CHANGELOG.md")
changelog_contents = File.read(changelog_path)

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
    number: pr_number,
    link: "https://github.com/dependabot/dependabot-core/pull/#{pr_number}"
  }
end

proposed_changes = pr_details.map do |details|
  line = "- #{details[:title]}"
  line += " (@#{details[:author]})" unless dependabot_team.include?(details[:author])
  line += " [##{details[:number]}](#{details[:link]})"
  line
end

new_changelog_contents = [
  "## v#{new_version}, #{Time.now.strftime('%e %B %Y').strip}\n",
  proposed_changes.join("\n") + "\n",
  changelog_contents
].join("\n")
File.open(changelog_path, "w") { |f| f.write(new_changelog_contents) }

puts "☑️  CHANGELOG.md updated"
puts
puts "Double check the changes (editing CHANGELOG.md where necessary), then"
puts "commit, tag, and push the release:"
puts
puts "git checkout -b v#{new_version}-release-notes"
puts "git add CHANGELOG.md common/lib/dependabot/version.rb"
puts "git commit -m 'v#{new_version}'"
puts "git push origin HEAD:v#{new_version}-release-notes"
puts "git checkout v#{new_version}-release-notes"
puts "# ... create PR, verify, merge, for example:"
puts "gh pr create"
puts "# tag the approved release notes:"
puts "git fetch"
puts "git tag 'v#{new_version}' 'origin/v#{new_version}-release-notes'"
puts "git push --tags"
puts
