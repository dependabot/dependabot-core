#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

# ============================================================================
# RUNNER SCRIPT - Local Repository Dependency Updates
# ============================================================================
#
# This script executes a full dependency update run for a LOCAL repository and
# writes the proposed changes directly to your local dependency files (go.mod,
# package.json, Gemfile, etc.) without creating a pull request.
#
# ────────────────────────────────────────────────────────────────────────────
# Key Difference from bin/dry-run.rb:
# ────────────────────────────────────────────────────────────────────────────
#
# bin/dry-run.rb:
#   - Works with REMOTE GitHub repositories (requires GitHub access token)
#   - Fetches files from GitHub API
#   - Must run inside a dev container (bin/docker-dev-shell)
#   - Does NOT modify local files
#   - Usage: ruby bin/dry-run.rb PACKAGE_MANAGER GITHUB_REPO
#   - Example: ruby bin/dry-run.rb go_modules octocat/Hello-World
#
# bin/runner.rb (this script):
#   - Works with LOCAL filesystem repositories (no GitHub token needed)
#   - Reads files directly from your local path
#   - Runs standalone on your machine (no container required)
#   - WRITES updates directly to local dependency files
#   - Usage: ruby bin/runner.rb [OPTIONS] PACKAGE_MANAGER LOCAL_REPO_ROOT_PATH
#   - Example: ruby bin/runner.rb go_modules /Users/you/my-project
#
# ────────────────────────────────────────────────────────────────────────────
# Prerequisites:
# ────────────────────────────────────────────────────────────────────────────
#
# 1. Install Ruby dependencies:
#    cd /path/to/dependabot-core
#    bundle install               # Install root Gemfile dependencies
#    cd updater && bundle install # Install updater Gemfile dependencies
#
# 2. Ensure required language runtimes are installed for your ecosystem:
#    - go_modules: Go 1.21+ (install via: brew install go)
#    - npm_and_yarn: Node.js (install via: brew install node)
#    - bundler: Ruby (usually pre-installed on macOS)
#    - pip/python: Python (install via: brew install python)
#    - cargo: Rust (install via: brew install rust)
#    - etc.
#
# ────────────────────────────────────────────────────────────────────────────
# Usage:
# ────────────────────────────────────────────────────────────────────────────
#
#   ruby bin/runner.rb [OPTIONS] PACKAGE_MANAGER[,PACKAGE_MANAGER...] LOCAL_REPO_ROOT_PATH
#
# ────────────────────────────────────────────────────────────────────────────
# Examples:
# ────────────────────────────────────────────────────────────────────────────
#
# Basic usage (updates all dependencies):
#   ruby bin/runner.rb go_modules /Users/you/my-go-project
#
# Multiple ecosystems:
#   ruby bin/runner.rb go_modules,npm_and_yarn /Users/you/my-fullstack-app
#
# Subdirectory (if dependency files are not in repo root):
#   ruby bin/runner.rb --dir /backend go_modules /Users/you/my-monorepo
#   ruby bin/runner.rb --dir backend go_modules /Users/you/my-monorepo  # auto-adds leading /
#
# Update specific dependencies only:
#   ruby bin/runner.rb --dep github.com/aws/aws-sdk-go-v2 go_modules /Users/you/my-project
#
# Update strategy (how to update version requirements):
#   ruby bin/runner.rb --requirements-update-strategy bump_versions go_modules /path
#
# ────────────────────────────────────────────────────────────────────────────
# Common Options:
# ────────────────────────────────────────────────────────────────────────────
#
#   --dir DIRECTORY                  Subdirectory path (relative to repo root)
#                                    Auto-prepends "/" if missing
#                                    Example: --dir backend  OR  --dir /backend
#
#   --dep DEPENDENCIES               Comma-separated list of specific dependencies
#                                    Example: --dep react,lodash
#
#   --requirements-update-strategy   How to update version requirements:
#                                    - auto (default): Let Dependabot decide
#                                    - lockfile_only: Only update lockfile
#                                    - widen_ranges: Widen version ranges if needed
#                                    - bump_versions: Always bump to new version
#                                    - bump_versions_if_necessary: Bump only if needed
#
#   --security-updates-only          Only update vulnerable dependencies
#
#   --vendor-dependencies            Vendor dependencies (e.g., for Go modules)
#
#   --branch BRANCH                  Specify branch (defaults to repo's current branch)
#
#   --pull-request                   Output pull request metadata (title, description)
#
# ────────────────────────────────────────────────────────────────────────────
# Supported Package Managers:
# ────────────────────────────────────────────────────────────────────────────
#
# Package managers:
# - bazel
# - bun
# - bundler
# - cargo
# - composer
# - conda
# - devcontainers
# - docker
# - docker_compose
# - dotnet_sdk
# - elm
# - go_modules
# - gradle
# - helm
# - hex
# - maven
# - npm_and_yarn
# - nuget
# - pip (includes pipenv)
# - pub
# - rust_toolchain
# - submodules
# - swift
# - terraform
# - opentofu
# - vcpkg

# rubocop:disable Style/GlobalVars

require "etc"

$LOAD_PATH << "./bazel/lib"
$LOAD_PATH << "./bun/lib"
$LOAD_PATH << "./bundler/lib"
$LOAD_PATH << "./cargo/lib"
$LOAD_PATH << "./common/lib"
$LOAD_PATH << "./composer/lib"
$LOAD_PATH << "./conda/lib"
$LOAD_PATH << "./devcontainers/lib"
$LOAD_PATH << "./docker_compose/lib"
$LOAD_PATH << "./docker/lib"
$LOAD_PATH << "./dotnet_sdk/lib"
$LOAD_PATH << "./elm/lib"
$LOAD_PATH << "./git_submodules/lib"
$LOAD_PATH << "./github_actions/lib"
$LOAD_PATH << "./go_modules/lib"
$LOAD_PATH << "./gradle/lib"
$LOAD_PATH << "./helm/lib"
$LOAD_PATH << "./hex/lib"
$LOAD_PATH << "./julia/lib"
$LOAD_PATH << "./maven/lib"
$LOAD_PATH << "./npm_and_yarn/lib"
$LOAD_PATH << "./nuget/lib"
$LOAD_PATH << "./pub/lib"
$LOAD_PATH << "./python/lib"
$LOAD_PATH << "./rust_toolchain/lib"
$LOAD_PATH << "./swift/lib"
$LOAD_PATH << "./terraform/lib"
$LOAD_PATH << "./opentofu/lib"
$LOAD_PATH << "./uv/lib"
$LOAD_PATH << "./vcpkg/lib"

updater_image_gemfile = File.expand_path("../dependabot-updater/Gemfile", __dir__)
updater_repo_gemfile = File.expand_path("../updater/Gemfile", __dir__)

ENV["BUNDLE_GEMFILE"] ||= File.exist?(updater_image_gemfile) ? updater_image_gemfile : updater_repo_gemfile

require "bundler"
Bundler.setup

require "optparse"
require "json"
require "debug"
require "logger"
require "dependabot/logger"
require "stackprof"

Dependabot.logger = Logger.new($stdout)

require "dependabot/credential"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/config/file_fetcher"
require "dependabot/simple_instrumentor"

require "dependabot/bazel"
require "dependabot/bun"
require "dependabot/bundler"
require "dependabot/cargo"
require "dependabot/composer"
require "dependabot/conda"
require "dependabot/devcontainers"
require "dependabot/docker"
require "dependabot/docker_compose"
require "dependabot/dotnet_sdk"
require "dependabot/elm"
require "dependabot/git_submodules"
require "dependabot/github_actions"
require "dependabot/go_modules"
require "dependabot/gradle"
require "dependabot/helm"
require "dependabot/hex"
require "dependabot/julia"
require "dependabot/maven"
require "dependabot/npm_and_yarn"
require "dependabot/nuget"
require "dependabot/pub"
require "dependabot/python"
require "dependabot/swift"
require "dependabot/terraform"
require "dependabot/opentofu"
require "dependabot/uv"
require "dependabot/vcpkg"

# GitHub credentials with write permission to the repo you want to update
# (so that you can create a new branch, commit and pull request).
# If using a private registry it's also possible to add details of that here.

$options = {
  credentials: [],
  provider: "github",
  directory: "/",
  dependency_names: nil,
  branch: nil,
  cache_steps: [],
  write: false,
  reject_external_code: false,
  requirements_update_strategy: nil,
  commit: nil,
  updater_options: {},
  security_advisories: [],
  security_updates_only: false,
  vendor_dependencies: false,
  ignore_conditions: [],
  pull_request: false,
  cooldown: nil
}

# Commenting the following out as this runner script will attempt
# to run dependabot on a local path
# unless ENV["LOCAL_GITHUB_ACCESS_TOKEN"].to_s.strip.empty?
#   $options[:credentials] << Dependabot::Credential.new(
#     {
#       "type" => "git_source",
#       "host" => "github.com",
#       "username" => "x-access-token",
#       "password" => ENV.fetch("LOCAL_GITHUB_ACCESS_TOKEN", nil)
#     }
#   )
# end

# unless ENV["LOCAL_AZURE_ACCESS_TOKEN"].to_s.strip.empty?
#   raise "LOCAL_AZURE_ACCESS_TOKEN supplied without LOCAL_AZURE_FEED_URL" unless ENV["LOCAL_AZURE_FEED_URL"]

#   $options[:credentials] << Dependabot::Credential.new(
#     {
#       "type" => "nuget_feed",
#       "host" => "pkgs.dev.azure.com",
#       "url" => ENV.fetch("LOCAL_AZURE_FEED_URL", nil),
#       "token" => ":#{ENV.fetch('LOCAL_AZURE_ACCESS_TOKEN', nil)}"
#     }
#   )
# end

unless ENV["LOCAL_CONFIG_VARIABLES"].to_s.strip.empty?
  # For example:
  # "[{\"type\":\"npm_registry\",\"registry\":\
  #     "registry.npmjs.org\",\"token\":\"123\"}]"
  $options[:credentials].concat(
    JSON.parse(ENV.fetch("LOCAL_CONFIG_VARIABLES", nil)).map do |data|
      Dependabot::Credential.new(data)
    end
  )
end

unless ENV["SECURITY_ADVISORIES"].to_s.strip.empty?
  # For example:
  # [{"dependency-name":"name",
  #   "patched-versions":[],
  #   "unaffected-versions":[],
  #   "affected-versions":["< 0.10.0"]}]
  $options[:security_advisories].concat(JSON.parse(ENV.fetch("SECURITY_ADVISORIES", nil)))
end

unless ENV["IGNORE_CONDITIONS"].to_s.strip.empty?
  # For example:
  # [{"dependency-name":"ruby","version-requirement":">= 3.a, < 4"}]
  $options[:ignore_conditions] = JSON.parse(ENV.fetch("IGNORE_CONDITIONS", nil))
end

if ENV.key?("COOLDOWN") && !ENV["COOLDOWN"].to_s.strip.empty?
  $options[:cooldown] = JSON.parse(ENV.fetch("COOLDOWN", "{}"))
end

# rubocop:disable Metrics/BlockLength
option_parse = OptionParser.new do |opts|
  opts.banner = "usage: ruby bin/runner.rb [OPTIONS] PACKAGE_MANAGER[,PACKAGE_MANAGER...] LOCAL_REPO_ROOT_PATH"

  opts.on("--provider PROVIDER", "SCM provider e.g. github, azure, bitbucket") do |value|
    $options[:provider] = value
  end

  opts.on("--dir DIRECTORY", "Dependency file directory") do |value|
    # Ensure directory starts with "/" for proper path handling
    $options[:directory] = value.start_with?("/") ? value : "/#{value}"
  end

  opts.on("--branch BRANCH", "Repo branch") do |value|
    $options[:branch] = value
  end

  opts.on(
    "--dep DEPENDENCIES",
    "Comma separated list of dependencies to update"
  ) do |value|
    $options[:dependency_names] = value.split(",").map { |o| o.strip.downcase }
  end

  # opts.on("--cache STEPS", "Cache e.g. files, dependencies") do |value|
  #   $options[:cache_steps].concat(value.split(",").map(&:strip))
  # end

  # opts.on("--write", "Write the update to the cache directory") do |_value|
  #   $options[:write] = true
  # end

  opts.on("--reject-external-code", "Reject external code") do |_value|
    $options[:reject_external_code] = true
  end

  opts_req_desc = "Options: lockfile_only, auto, widen_ranges, bump_versions or " \
                  "bump_versions_if_necessary"
  opts.on("--requirements-update-strategy STRATEGY", opts_req_desc) do |value|
    if value == "auto"
      $options[:requirements_update_strategy] = nil
    else
      strategy = Dependabot::RequirementsUpdateStrategy.values.find { |v| v.serialize == value } or
        raise OptionParser::InvalidArgument, "Invalid requirements update strategy: #{value}. #{opts_req_desc}"
      $options[:requirements_update_strategy] = strategy
    end
  end

  opts.on("--commit COMMIT", "Commit to fetch dependency files from") do |value|
    $options[:commit] = value
  end

  opts.on("--vendor-dependencies", "Vendor dependencies") do |_value|
    $options[:vendor_dependencies] = true
  end

  opts_opt_desc = "Comma separated list of updater options, " \
                  "available options depend on PACKAGE_MANAGER"
  opts.on("--updater-options OPTIONS", opts_opt_desc) do |value|
    $options[:updater_options] = value.split(",").to_h do |o|
      if o.include?("=") # key/value pair, e.g. "goprivate=true"
        o.split("=", 2).map.with_index do |v, i|
          if i.zero?
            v.strip.downcase.to_sym
          else
            v.strip
          end
        end
      else # just a key, e.g. "record_ecosystem_versions"
        [o.strip.downcase.to_sym, true]
      end
    end

    $options[:updater_options].each do |name, val|
      Dependabot::Experiments.register(name, val)
    end
  end

  opts.on(
    "--security-updates-only",
    "Only update vulnerable dependencies"
  ) do |_value|
    $options[:security_updates_only] = true
  end

  opts.on(
    "--profile",
    "Profile using Stackprof. Output in `tmp/stackprof-<datetime>.dump`"
  ) do
    $options[:profile] = true
  end

  opts.on(
    "--pull-request",
    "Output pull request information metadata: title, description"
  ) do
    $options[:pull_request] = true
  end

  opts.on("--enable-beta-ecosystems", "Enable beta ecosystems") do |_value|
    Dependabot::Experiments.register(:enable_beta_ecosystems, true)
  end

  opts.on("--cooldown JSON", "Cooldown configuration as a JSON object") do |value|
    cooldown_options = JSON.parse(value)
    raise "Invalid cooldown configuration" unless cooldown_options.is_a?(Hash)

    # Convert kebab-case keys to snake_case and symbolize keys
    cooldown_options = cooldown_options.each_with_object({}) do |(key, val), result|
      result[key.tr("-", "_").to_sym] = val
    end

    $options[:cooldown] = cooldown_options
  rescue JSON::ParserError
    puts "Invalid JSON format for cooldown parameter. Please provide a valid JSON string."
    exit 1
  end
end
# rubocop:enable Metrics/BlockLength

# Parse options before validating arguments
option_parse.parse!

# Ensure valid arguments are provided
if ARGV.length < 2
  puts option_parse.help
  exit 1
end

# Validate package managers
valid_package_managers = %w(
  bazel
  bun
  bundler
  cargo
  composer
  conda
  devcontainers
  docker
  docker_compose
  dotnet_sdk
  elm
  git_submodules
  github_actions
  go_modules
  gradle
  helm
  hex
  maven
  npm_and_yarn
  nuget
  pip
  pub
  python
  rust_toolchain
  swift
  terraform
  opentofu
  uv
  vcpkg
)

# Parse package managers (comma-separated)
$package_managers = ARGV[0].split(",").map(&:strip)

# Validate each package manager
$package_managers.each do |pm|
  unless valid_package_managers.include?(pm)
    puts "Invalid package manager: #{pm}"
    exit 1
  end
end

# Get local repo path
$local_repo_path = File.expand_path(ARGV[1])

# Validate that the local repo path exists
unless Dir.exist?($local_repo_path)
  puts "Error: Local repository path does not exist: #{$local_repo_path}"
  exit 1
end

# Derive a repo name from the path (use directory name for cache naming)
path_parts = $local_repo_path.split("/").reject(&:empty?)
repo_dir_name = path_parts[-1]
$repo_name = "local/#{repo_dir_name}"

puts "=> Running Dependabot on local repository: #{$local_repo_path}"
puts "=> Processing ecosystems: #{$package_managers.join(', ')}"
puts "=> Using repo identifier: #{$repo_name}"

# Ensure the script does not exit prematurely
begin

  # rubocop:enable Metrics/PerceivedComplexity
  # rubocop:enable Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/AbcSize

  def fetch_files(fetcher)
    puts "=> reading local repo from #{$repo_contents_path}"
    # Fetch files directly from the local repository
    fetcher.files
  rescue Dependabot::RepoNotFound => e
    puts " => handled error whilst fetching dependencies: RepoNotFound #{e.message}"
    exit 1 # Exit with a non-zero status for repo not found errors
  rescue StandardError => e
    error_details = Dependabot.fetcher_error_details(e)
    raise unless error_details

    puts " => handled error whilst fetching dependencies: #{error_details.fetch(:"error-type")} " \
         "#{error_details.fetch(:"error-detail")}"

    []
  end

  def parse_dependencies(parser)
    parser.parse
  rescue StandardError => e
    error_details = Dependabot.parser_error_details(e)
    raise unless error_details

    puts " => handled error whilst parsing dependencies: #{error_details.fetch(:"error-type")} " \
         "#{error_details.fetch(:"error-detail")}"

    []
  end

  def log_conflicting_dependencies(conflicting_dependencies)
    return unless conflicting_dependencies.any?

    puts " => The update is not possible because of the following conflicting " \
         "dependencies:"

    conflicting_dependencies.each do |conflicting_dep|
      puts "   #{conflicting_dep['explanation']}"
    end
  end

  StackProf.start(raw: true) if $options[:profile]

  $network_trace_count = 0
  Dependabot::SimpleInstrumentor.subscribe do |*args|
    name = args.first
    $network_trace_count += 1 if name == "excon.request"

    payload = args.last
    if name == "excon.request" || name == "excon.response"
      puts "🌍 #{name == 'excon.response' ? "<-- #{payload[:status]}" : "--> #{payload[:method].upcase}"}" \
           " #{Excon::Utils.request_uri(payload)}"
    end
  end

  $source = Dependabot::Source.new(
    provider: $options[:provider],
    repo: $repo_name,
    directory: $options[:directory],
    branch: $options[:branch],
    commit: $options[:commit]
  )

  # Use the local repository path directly instead of cloning
  $repo_contents_path = $local_repo_path

  # Initial fetcher_args for config file fetching (without update_config)
  initial_fetcher_args = {
    source: $source,
    credentials: $options[:credentials],
    repo_contents_path: $repo_contents_path,
    options: $options[:updater_options]
  }

  $config_file = begin
    cfg_file = Dependabot::Config::FileFetcher.new(**initial_fetcher_args).config_file
    Dependabot::Config::File.parse(cfg_file.content)
  rescue Dependabot::RepoNotFound, Dependabot::DependencyFileNotFound
    Dependabot::Config::File.new(updates: [])
  end

  # Process each package manager
  $package_managers.each do |package_manager|
    $package_manager = package_manager
    puts "\n" + "=" * 80
    puts "Processing ecosystem: #{$package_manager}"
    puts "=" * 80

    $update_config = begin
      config = $config_file.update_config(
        $package_manager,
        directory: $options[:directory],
        target_branch: $options[:branch]
      )
      config
    rescue KeyError
      puts "⚠️  Skipping #{$package_manager}: Invalid package manager"
      next
    end

  fetcher_args = initial_fetcher_args.merge(update_config: $update_config)

  fetcher = Dependabot::FileFetchers.for_package_manager($package_manager).new(**fetcher_args)
  $files = fetch_files(fetcher)
  if $files.empty?
    puts "⚠️  No dependency files found for #{$package_manager}, skipping"
    next
  end

  ecosystem_versions = fetcher.ecosystem_versions
  puts "🎈 Ecosystem Versions log: #{ecosystem_versions}" unless ecosystem_versions.nil?

  # Parse the dependency files
  puts "=> parsing dependency files"
  parser = Dependabot::FileParsers.for_package_manager($package_manager).new(
    dependency_files: $files,
    repo_contents_path: $repo_contents_path,
    source: $source,
    credentials: $options[:credentials],
    reject_external_code: $options[:reject_external_code]
  )

  dependencies = parse_dependencies(parser)

  if $options[:dependency_names].nil?
    dependencies.select!(&:top_level?)
  else
    dependencies.select! do |d|
      $options[:dependency_names].include?(d.name.downcase)
    end
  end

  def update_checker_for(dependency)
    Dependabot::UpdateCheckers.for_package_manager($package_manager).new(
      dependency: dependency,
      dependency_files: $files,
      credentials: $options[:credentials],
      repo_contents_path: $repo_contents_path,
      requirements_update_strategy: $options[:requirements_update_strategy],
      ignored_versions: ignored_versions_for(dependency),
      security_advisories: security_advisories,
      update_cooldown: update_cooldown,
      options: $options[:updater_options]
    )
  end

  def update_cooldown
    return unless $options[:cooldown]

    Dependabot::Package::ReleaseCooldownOptions.new(**$options[:cooldown])
  end

  def ignored_versions_for(dep)
    if $options[:ignore_conditions].any?
      ignore_conditions = $options[:ignore_conditions].map do |ic|
        Dependabot::Config::IgnoreCondition.new(
          dependency_name: ic["dependency-name"],
          versions: [ic["version-requirement"]].compact,
          update_types: ic["update-types"]
        )
      end
      Dependabot::Config::UpdateConfig.new(ignore_conditions: ignore_conditions)
                                      .ignored_versions_for(dep,
                                                            security_updates_only: $options[:security_updates_only])
    else
      $update_config.ignored_versions_for(dep)
    end
  end

  def security_advisories
    $options[:security_advisories].map do |adv|
      vulnerable_versions = adv["affected-versions"] || []
      safe_versions = (adv["patched-versions"] || []) +
                      (adv["unaffected-versions"] || [])

      # Handle case mismatches between advisory name and parsed dependency name
      dependency_name = adv["dependency-name"].downcase
      Dependabot::SecurityAdvisory.new(
        dependency_name: dependency_name,
        package_manager: $package_manager,
        vulnerable_versions: vulnerable_versions,
        safe_versions: safe_versions
      )
    end
  end

  # If a version update for a peer dependency is possible we should
  # defer to the PR that will be created for it to avoid duplicate PRs.
  def peer_dependency_should_update_instead?(dependency_name, updated_deps)
    # This doesn't apply to security updates as we can't rely on the
    # peer dependency getting updated.
    return false if $options[:security_updates_only]

    updated_deps
      .reject { |dep| dep.name == dependency_name }
      .any? do |dep|
        original_peer_dep = ::Dependabot::Dependency.new(
          name: dep.name,
          version: dep.previous_version,
          requirements: dep.previous_requirements,
          package_manager: dep.package_manager
        )
        update_checker_for(original_peer_dep)
          .can_update?(requirements_to_unlock: :own)
      end
  end

  def file_updater_for(dependencies)
    Dependabot::FileUpdaters.for_package_manager($package_manager).new(
      dependencies: dependencies,
      dependency_files: $files,
      repo_contents_path: $repo_contents_path,
      credentials: $options[:credentials],
      options: $options[:updater_options]
    )
  end

  def security_fix?(dependency)
    security_advisories.any? do |advisory|
      advisory.fixed_by?(dependency)
    end
  end

  puts "=> updating #{dependencies.count} dependencies: #{dependencies.map(&:name).join(', ')}"

  # rubocop:disable Metrics/BlockLength
  checker_count = 0
  dependencies.each do |dep|
    checker_count += 1
    checker = update_checker_for(dep)
    name_version = "\n=== #{dep.name} (#{dep.version})"
    vulnerable = checker.vulnerable? ? " (vulnerable 🚨)" : ""
    puts name_version + vulnerable

    puts " => checking for updates #{checker_count}/#{dependencies.count}"
    puts " => latest available version is #{checker.latest_version}"

    if $options[:security_updates_only] && !checker.vulnerable?
      if checker.version_class.correct?(checker.dependency.version)
        puts "    (no security update needed as it's not vulnerable)"
      else
        puts "    (can't update vulnerable dependencies for " \
             "projects without a lockfile as the currently " \
             "installed version isn't known 🚨)"
      end
      next
    end

    if checker.vulnerable?
      if checker.lowest_security_fix_version
        puts " => earliest available non-vulnerable version is " \
             "#{checker.lowest_security_fix_version}"
      else
        puts " => there is no available non-vulnerable version"
      end
    end

    if checker.up_to_date?
      puts "    (no update needed as it's already up-to-date)"
      next
    end

    latest_allowed_version = if checker.vulnerable?
                               checker.lowest_resolvable_security_fix_version
                             else
                               checker.latest_resolvable_version
                             end
    puts " => latest allowed version is #{latest_allowed_version || dep.version}"

    requirements_to_unlock =
      if !checker.requirements_unlocked_or_can_be?
        if checker.can_update?(requirements_to_unlock: :none) then :none
        else
          :update_not_possible
        end
      elsif checker.can_update?(requirements_to_unlock: :own) then :own
      elsif checker.can_update?(requirements_to_unlock: :all) then :all
      else
        :update_not_possible
      end

    puts " => requirements to unlock: #{requirements_to_unlock}"

    if checker.respond_to?(:requirements_update_strategy)
      puts " => requirements update strategy: " \
           "#{checker.requirements_update_strategy}"
    end

    if requirements_to_unlock == :update_not_possible
      if checker.vulnerable? || $options[:security_updates_only]
        puts "    (no security update possible 🙅‍♀️)"
      else
        puts "    (no update possible 🙅‍♀️)"
      end

      log_conflicting_dependencies(checker.conflicting_dependencies)
      next
    end

    updated_deps = checker.updated_dependencies(
      requirements_to_unlock: requirements_to_unlock
    )

    if peer_dependency_should_update_instead?(checker.dependency.name, updated_deps)
      puts "    (no update possible, peer dependency can be updated)"
      next
    end

    if $options[:security_updates_only] &&
       updated_deps.none? { |d| security_fix?(d) }
      puts "    (updated version is still vulnerable 🚨)"
      log_conflicting_dependencies(checker.conflicting_dependencies)
      next
    end

    # Removal is only supported for transitive dependencies which are removed as a
    # side effect of the parent update
    deps_to_update = updated_deps.reject(&:removed?)
    updater = file_updater_for(deps_to_update)
    updated_files = updater.updated_dependency_files

    updated_deps = updated_deps.reject do |d|
      next false if d.name == checker.dependency.name
      next true if d.top_level? && d.requirements == d.previous_requirements

      d.version == d.previous_version
    end

    msg = Dependabot::PullRequestCreator::MessageBuilder.new(
      dependencies: updated_deps,
      files: updated_files,
      credentials: $options[:credentials],
      source: $source,
      commit_message_options: $update_config.commit_message_options.to_h,
      github_redirection_service: Dependabot::PullRequestCreator::DEFAULT_GITHUB_REDIRECTION_SERVICE
    ).message

    puts " => #{msg.pr_name.downcase}"

    # Always write updated files to the local repository
    updated_files.each do |updated_file|
      file_path = File.join($local_repo_path, $options[:directory], updated_file.name)
      puts " => writing updated file: #{file_path}"
      dirname = File.dirname(file_path)
      FileUtils.mkdir_p(dirname)
      if updated_file.operation == Dependabot::DependencyFile::Operation::DELETE
        FileUtils.rm_f(file_path)
        puts "    deleted #{updated_file.name}"
      else
        File.write(file_path, updated_file.decoded_content)
        puts "    updated #{updated_file.name}"
      end
    end

    if $options[:pull_request]
      puts "Pull Request Title: #{msg.pr_name}"
      puts "--description--\n#{msg.pr_message}\n--/description--"
      puts "--commit--\n#{msg.commit_message}\n--/commit--"
    end
  rescue StandardError => e
    error_details = Dependabot.updater_error_details(e)
    raise unless error_details

    puts " => handled error whilst updating #{dep.name}: #{error_details.fetch(:"error-type")} " \
         "#{error_details.fetch(:"error-detail")}"
  end
  end # End of package_managers.each loop

  StackProf.stop if $options[:profile]
  StackProf.results("tmp/stackprof-#{Time.now.strftime('%Y-%m-%d-%H:%M')}.dump") if $options[:profile]

  puts "🌍 Total requests made: '#{$network_trace_count}'"

  # rubocop:enable Metrics/BlockLength

  # rubocop:enable Style/GlobalVars
rescue StandardError => e
  puts "An error occurred: #{e.class}, #{e.message}"
  exit 1
end

# Ensure the script exits successfully if no errors occur
puts "Dry-run completed successfully."
exit 0
