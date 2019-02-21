#!/usr/bin/env ruby
# frozen_string_literal: true

# This script is does a full update run for a given repo (optionally for a
# specific dependency only), and shows the proposed changes to any dependency
# files without actually creating a pull request.
#
# It's used regularly by the Dependabot team to manually debug issues, so
# should always be up-to-date.
#
# Usage:
#   ruby bin/dry-run.rb [OPTIONS] PACKAGE_MANAGER GITHUB_REPO
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
# - elm
# - submodules
# - docker
# - terraform

$LOAD_PATH << "./bundler/lib"
$LOAD_PATH << "./cargo/lib"
$LOAD_PATH << "./common/lib"
$LOAD_PATH << "./composer/lib"
$LOAD_PATH << "./dep/lib"
$LOAD_PATH << "./docker/lib"
$LOAD_PATH << "./elm/lib"
$LOAD_PATH << "./git_submodules/lib"
$LOAD_PATH << "./go_modules/lib"
$LOAD_PATH << "./gradle/lib"
$LOAD_PATH << "./hex/lib"
$LOAD_PATH << "./maven/lib"
$LOAD_PATH << "./npm_and_yarn/lib"
$LOAD_PATH << "./nuget/lib"
$LOAD_PATH << "./terraform/lib"

require "bundler"
ENV["BUNDLE_GEMFILE"] = File.join(__dir__, "../omnibus/Gemfile")
Bundler.setup

require "optparse"
require "json"

require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"

require "dependabot/bundler"
require "dependabot/cargo"
require "dependabot/composer"
require "dependabot/dep"
require "dependabot/docker"
require "dependabot/elm"
require "dependabot/git_submodules"
require "dependabot/go_modules"
require "dependabot/gradle"
require "dependabot/hex"
require "dependabot/maven"
require "dependabot/npm_and_yarn"
require "dependabot/nuget"
require "dependabot/terraform"

# GitHub credentials with write permission to the repo you want to update
# (so that you can create a new branch, commit and pull request).
# If using a private registry it's also possible to add details of that here.

$options = {
  credentials: [],
  directory: "/",
  dependency_name: nil,
  branch: nil,
  cache_steps: [],
}

if ENV["LOCAL_GITHUB_ACCESS_TOKEN"]
  $options[:credentials] << {
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => ENV["LOCAL_GITHUB_ACCESS_TOKEN"]
  }
end

if ENV["LOCAL_CONFIG_VARIABLES"]
  # For example:
  # LOCAL_CONFIG_VARIABLES="[{\"type\":\"npm_registry\",\"registry\":\"registry.npmjs.org\",\"token\":\"123\"}]"
  $options[:credentials].concat(JSON.parse(ENV["LOCAL_CONFIG_VARIABLES"]))
end

option_parse = OptionParser.new do |opts|
  opts.banner = "usage: ruby bin/dry-run.rb [OPTIONS] PACKAGE_MANAGER REPO"

  opts.on("--dir DIRECTORY", "Dependency file directory") do |value|
    $options[:directory] = value
  end

  opts.on("--branch BRANCH", "Repo branch") do |value|
    $options[:branch] = value
  end

  opts.on("--dep DEPENDENCY", "Dependency to update") do |value|
    $options[:dependency_name] = value
  end

  opts.on("--cache STEPS", "Cache e.g. files, dependencies, updates") do |value|
    $options[:cache_steps].concat(value.split(",").map(&:strip))
  end
end

option_parse.parse!

# Full name of the GitHub repo you want to create pull requests for
if ARGV.length < 2
  puts option_parse.help
  exit 1
end

$package_manager, $repo_name = ARGV

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

def cached_read(name)
  raise "Provide something to cache" unless block_given?
  return yield unless $options[:cache_steps].include?(name)

  cache_path = File.join("tmp", $repo_name.split("/"), "cache", "#{name}.bin")
  cache_dir = File.dirname(cache_path)
  FileUtils.mkdir_p(cache_dir) unless Dir.exist?(cache_dir)
  cached = File.read(cache_path) if File.exist?(cache_path)
  return Marshal.load(cached) if cached

  data = yield
  File.write(cache_path, Marshal.dump(data))
  data
end

source = Dependabot::Source.new(
  provider: "github",
  repo: $repo_name,
  directory: $options[:directory],
  branch: $options[:branch]
)

# Fetch the dependency files
puts "=> fetching dependency files"

fetcher = Dependabot::FileFetchers.for_package_manager($package_manager).
          new(source: source, credentials: $options[:credentials])

files = cached_read("files") { fetcher.files }

# Dump dependency files in tmp/githublogin@repo-name/dependency-files
files.map do |f|
  files_path = File.join("tmp", $repo_name.split("/"), "dependency-files", f.name)
  files_dir = File.dirname(files_path)
  FileUtils.mkdir_p(files_dir) unless Dir.exist?(files_dir)
  File.write(files_path, f.content)
end

# Parse the dependency files
puts "=> parsing dependency files"
parser = Dependabot::FileParsers.for_package_manager($package_manager).new(
  dependency_files: files,
  source: source,
  credentials: $options[:credentials]
)

dependencies = cached_read("dependencies") { parser.parse }

if $options[:dependency_name].nil?
  dependencies.select!(&:top_level?)
else
  dependencies.select! { |d| d.name == $options[:dependency_name] }
end

puts "=> updating #{dependencies.count} dependencies"

dependencies.each do |dep|
  puts "\n=== #{dep.name} (#{dep.version})"
  checker = Dependabot::UpdateCheckers.for_package_manager($package_manager).new(
    dependency: dep,
    dependency_files: files,
    credentials: $options[:credentials]
  )

  puts " => checking for updates"
  updated_deps = cached_read("updates") do
    requirements_to_unlock =
      if !checker.requirements_unlocked_or_can_be?
        if checker.can_update?(requirements_to_unlock: :none) then :none
        else :update_not_possible
        end
      elsif checker.can_update?(requirements_to_unlock: :own) then :own
      elsif checker.can_update?(requirements_to_unlock: :all) then :all
      else :update_not_possible
      end

    return [] if requirements_to_unlock == :update_not_possible

    checker.updated_dependencies(
      requirements_to_unlock: requirements_to_unlock
    )
  end

  updated_deps.select! do |d|
    next true if d.version != d.previous_version
    d.requirements != d.previous_requirements
  end

  if updated_deps.empty?
    puts "    (no update available)"
    next
  end

  new_dep = updated_deps.find { |d| d.name == dep.name }
  puts " => updating to #{new_dep.version}"

  # Generate updated dependency files
  updater = Dependabot::FileUpdaters.for_package_manager($package_manager).new(
    dependencies: updated_deps,
    dependency_files: files,
    credentials: $options[:credentials]
  )

  updated_files = updater.updated_dependency_files
  updated_files.each do |updated_file|
    original_file = files.find { |f| f.name == updated_file.name }
    show_diff(original_file, updated_file)
  end
end
