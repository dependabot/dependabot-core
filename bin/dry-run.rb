# frozen_string_literal: true

# This script is does a full update run for a given repo (optionally for a
# specific dependency only), and shows the proposed changes to any dependency
# files without actually creating a pull request.
#
# It's used regularly by the Dependabot team to manually debug issues, so
# should always be up-to-date.
#
# Usage:
#   ruby bin/dry-run.rb PACKAGE_MANAGER GITHUB_REPO [DEPENDENCY]
#
# ! You'll need to have a GitHub access token (a personal access token is
# ! fine) available as the environment variable LOCAL_GITHUB_ACCESS_TOKEN.
#
# Example:
#   ruby bin/dry-run.rb go_modules zonedb/zonedb
#
# Package managers:
# - bundler
# - pip (includes pipenv)
# - npm_and_yarn
# - maven
# - gradle
# - cargo
# - hex
# - composer
# - nuget
# - dep
# - go_modules
# - elm-package
# - submodules
# - docker
# - terraform

require "optparse"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"

# GitHub credentials with write permission to the repo you want to update
# (so that you can create a new branch, commit and pull request).
# If using a private registry it's also possible to add details of that here.
credentials = []
if ENV["LOCAL_GITHUB_ACCESS_TOKEN"]
  credentials << {
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => ENV["LOCAL_GITHUB_ACCESS_TOKEN"]
  }
end

# Directory where the base dependency files are.
directory = "/"

# Name of an individual dependency to udpate
dependency_name = nil

option_parse = OptionParser.new do |opts|
  opts.banner = "usage: ruby bin/dry-run.rb [options] PACKAGE_MANAGER REPO"

  opts.on("--dir DIRECTORY", "Dependency file directory") do |value|
    directory = value
  end

  opts.on("--dep DEPENDENCY", "Dependency to update") do |value|
    dependency_name = value
  end
end
option_parse.parse!

# Full name of the GitHub repo you want to create pull requests for.
if ARGV.length < 2
  puts option_parse.help
  exit 1
end
package_manager, repo_name = ARGV

source = Dependabot::Source.new(
  provider: "github",
  repo: repo_name,
  directory: directory,
  branch: nil
)

# Fetch the dependency files
puts "=> fetching dependency files"
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).
          new(source: source, credentials: credentials)
files = fetcher.files

# Parse the dependency files
puts "=> parsing dependency files"
parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
  dependency_files: files,
  source: source,
  credentials: credentials
)
dependencies = parser.parse

if dependency_name.nil?
  dependencies.select!(&:top_level?)
else
  dependencies.select! { |d| d.name == dependency_name }
end

puts "=> updating #{dependencies.count} dependencies"

def show_diff(original_file, updated_file)
  if original_file.content == updated_file.content
    puts "    no change to #{original_file.name}"
    return
  end

  original_tmp_file = Tempfile.new("original")
  original_tmp_file.write(original_file.content)
  original_tmp_file.close

  updated_tmp_file = Tempfile.new("updated")
  updated_tmp_file.write(updated_file.content)
  updated_tmp_file.close

  diff = `diff #{original_tmp_file.path} #{updated_tmp_file.path}`
  puts
  puts "    ± #{original_file.name}"
  puts "    ~~~"
  puts diff.lines.map { |line| "    " + line }.join("")
  puts "    ~~~"
end

dependencies.each do |dep|
  puts "\n=== #{dep.name} (#{dep.version})"
  checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
    dependency: dep,
    dependency_files: files,
    credentials: credentials
  )

  puts " => checking for updates"
  updated_deps = checker.updated_dependencies(requirements_to_unlock: :own)
  updated_deps.select! do |d|
    next true if d.version != d.previous_version
    d.requirements != d.previous_requirements
  end

  if updated_deps.empty?
    puts "    (no update available)"
    next
  end

  new_version = updated_deps.find { |d| d.name == dep.name }.version
  puts " => updating to #{new_version}"

  # Generate updated dependency files
  updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
    dependencies: updated_deps,
    dependency_files: files,
    credentials: credentials
  )

  updated_files = updater.updated_dependency_files
  updated_files.each do |updated_file|
    original_file = files.find { |f| f.name == updated_file.name }
    show_diff(original_file, updated_file)
  end
end
