#!/usr/bin/env ruby
# frozen_string_literal: true

# Processes a Bitbucket Server (aka Bitbucket Data Center) to find out of date
# dependencies. Creates Jira tickets and PRs for each out of date dependency.
#
# Usage: (invoked from Docker)
#   ruby update_script.rb
#
# Environment variables:
#   PROJECT_PATH: Full name of the repo to create pull requests for.
#   DIRECTORY_PATH: Directory where the base dependency files are. Defaults to /
#   BRANCH: Branch to look at. Defaults to repo's default branch. Defaults to repo default.
#   PACKAGE_MANAGER: Name of package manager to use. Defaults to nuget.
#   GITHUB_ACCESS_TOKEN: Access token for Github; used to get changelog info.
#   BITBUCKET_ACCESS_TOKEN: Access token for Bitbucket; used to clone repos and post PRs.
#   JIRA_API_TOKEN: Access token for Jira; used to create Jira issues.
#   NAMESPACE: Provides the namespace for APIs. Example: "projects/my_proj" or "users/jdoe".

$LOAD_PATH << "./bundler/lib"
$LOAD_PATH << "./cargo/lib"
$LOAD_PATH << "./common/lib"
$LOAD_PATH << "./composer/lib"
$LOAD_PATH << "./docker/lib"
$LOAD_PATH << "./elm/lib"
$LOAD_PATH << "./git_submodules/lib"
$LOAD_PATH << "./github_actions/lib"
$LOAD_PATH << "./go_modules/lib"
$LOAD_PATH << "./gradle/lib"
$LOAD_PATH << "./hex/lib"
$LOAD_PATH << "./maven/lib"
$LOAD_PATH << "./npm_and_yarn/lib"
$LOAD_PATH << "./nuget/lib"
$LOAD_PATH << "./python/lib"
$LOAD_PATH << "./pub/lib"
$LOAD_PATH << "./terraform/lib"

require "bundler"
ENV["BUNDLE_GEMFILE"] = File.join(__dir__, "../omnibus/Gemfile")
Bundler.setup

require "optparse"
require "json"
require "debug"
require "logger"
require "dependabot/logger"
require "stackprof"

Dependabot.logger = Logger.new($stdout)

require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/config/file_fetcher"

require "dependabot/bundler"
require "dependabot/cargo"
require "dependabot/composer"
require "dependabot/docker"
require "dependabot/elm"
require "dependabot/git_submodules"
require "dependabot/github_actions"
require "dependabot/go_modules"
require "dependabot/gradle"
require "dependabot/hex"
require "dependabot/maven"
require "dependabot/npm_and_yarn"
require "dependabot/nuget"
require "dependabot/python"
require "dependabot/pub"
require "dependabot/terraform"

require_relative "bitbucket_server/bitbucket_server_provider"

bitbucket_creds = {
  "type" => "git_source",
  "host" => "stash.air-watch.com",
  "username" => "x-access-token",
  "token" => ENV["BITBUCKET_ACCESS_TOKEN"]
}

credentials = [
  {
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => ENV["GITHUB_ACCESS_TOKEN"]
  },
]

# Full name of the repo you want to create pull requests for.
repo_name = ENV["PROJECT_PATH"] # namespace/project

# Directory where the base dependency files are.
directory = ENV["DIRECTORY_PATH"] || "/"

# Branch to look at. Defaults to repo's default branch
branch = ENV["BRANCH"]

# Provides the namespace for APIs. Example: "projects/my_proj" or "users/jdoe".
namespace = ENV["BITBUCKET_REPO_NAMESPACE"]

# Name of the package manager you'd like to do the update for. Options are:
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
# - elm
# - submodules
# - docker
# - terraform
package_manager = ENV["PACKAGE_MANAGER"] || "nuget"

# Expected to be a JSON object passed to the underlying components
options = JSON.parse(ENV["OPTIONS"] || "{}", {:symbolize_names => true})
puts "Running with options: #{options}"

ext_provider = BitbucketServerProvider.new(
  hostname: "stash.air-watch.com",
  api_endpoint: "https://stash.air-watch.com/rest/api/1.0/",
  repo: repo_name,
  directory: directory,
  branch: branch,
  credentials: bitbucket_creds,
  namespace: namespace
)

source = Dependabot::Source.new(
  ext_provider: ext_provider
)

# Fetch the dependency files
puts "Fetching #{package_manager} dependency files for #{repo_name}"
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: source,
  options: options
  )

files = fetcher.files
commit = fetcher.commit

# Parse the dependency files
puts "Parsing dependencies information"
parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
  dependency_files: files,
  source: source,
  credentials: credentials,
  options: options,
  )

dependencies = parser.parse

dependencies.select(&:top_level?).each do |dep|
  # Get update details for the dependency
  checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
    dependency: dep,
    dependency_files: files,
    credentials: credentials,
    options: options,
    )

  next if checker.up_to_date?

  requirements_to_unlock =
    if !checker.requirements_unlocked_or_can_be?
      if checker.can_update?(requirements_to_unlock: :none) then :none
      else :update_not_possible
      end
    elsif checker.can_update?(requirements_to_unlock: :own) then :own
    elsif checker.can_update?(requirements_to_unlock: :all) then :all
    else :update_not_possible
    end

  next if requirements_to_unlock == :update_not_possible

  updated_deps = checker.updated_dependencies(
    requirements_to_unlock: requirements_to_unlock
  )

  # Generate updated dependency files
  puts "Updating #{dep.name} (from #{dep.version})..."
  updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
    dependencies: updated_deps,
    dependency_files: files,
    credentials: credentials,
    options: options,
    )

  updated_files = updater.updated_dependency_files

  # Get details about the update to use in the Jira issue
  msg = Dependabot::PullRequestCreator::MessageBuilder.new(
    dependencies: updated_deps,
    files: updated_files,
    credentials: credentials,
    pr_message_header: "Update dependencies in project",
    source: source,
    github_redirection_service: nil
  ).message

  # Create a Jira issue to track the update

  # Don't create a new ticket, just use an old one. This saves having to pull in the Jira code.
  # issue_id = create_issue_for_package(ENV.fetch("JIRA_PROJECT"), dep.name, summary: msg.pr_name)
  issue_id = "TESTABHI-2"
  puts "  Reusing old Jira issue #{issue_id}"

  # Create a pull request for the update
  pr_creator = Dependabot::PullRequestCreator.new(
    source: source,
    base_commit: commit,
    dependencies: updated_deps,
    files: updated_files,
    credentials: credentials,
    author_details: { name: "Dependabot", email: "no-reply@github.com" },
    commit_message_options: { prefix: issue_id },
    branch_name_prefix: issue_id,
    pr_message_header: "#{issue_id} #{msg.pr_name}"
  )
  pr_creator.create
  puts "  Created PR: #{issue_id} #{msg.pr_name}"
end

puts "Done"
