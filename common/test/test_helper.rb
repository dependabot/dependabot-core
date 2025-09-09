# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "minitest/autorun"
require "minitest/reporters"
require "webmock/minitest"
require "vcr"
require "debug"
require "simplecov"
require "simplecov_json_formatter"
require "stackprof"
require "uri"
require "fileutils"
require "pathname"
require "stringio"

# SimpleCov _must_ be started before any dependabot code is loaded
SimpleCov.start do
  command_name "test-process-#{ENV.fetch('TEST_ENV_NUMBER', 1)}"
  add_filter "/test/"
  add_filter "/spec/"

  # Configure formatters - in CI use simple, locally use both simple and HTML
  if ENV["CI"]
    formatter SimpleCov::Formatter::SimpleFormatter
  else
    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::SimpleFormatter,
      SimpleCov::Formatter::HTMLFormatter
    ])
  end

  enable_coverage :branch
  primary_coverage :branch
  minimum_coverage line: 0, branch: 0
end

# Suppress SimpleCov's verbose output by default while preserving minitest output
# This approach is cleaner than environment variables and doesn't interfere with test output
SimpleCov.at_exit do
  if ENV["VERBOSE"] || ENV["CI"] || ENV["SIMPLECOV_VERBOSE"]
    # Show SimpleCov output in verbose modes
    SimpleCov.result.format!
  else
    # Silent mode - generate reports but suppress console output
    original_stdout = $stdout
    begin
      $stdout = StringIO.new
      SimpleCov.result.format!
    ensure
      $stdout = original_stdout
    end
  end
end

# Use progress reporter for clean output
Minitest::Reporters.use! Minitest::Reporters::ProgressReporter.new

require "dependabot/dependency_file"
require "dependabot/experiments"
require "dependabot/registry_client"
require_relative "../spec/dummy_package_manager/dummy"
require_relative "../spec/warning_monkey_patch"

ENV["GIT_AUTHOR_NAME"] = "dependabot-ci"
ENV["GIT_AUTHOR_EMAIL"] = "no-reply@github.com"
ENV["GIT_COMMITTER_NAME"] = "dependabot-ci"
ENV["GIT_COMMITTER_EMAIL"] = "no-reply@github.com"

# Sorbet-compatible test_each methods for table-driven tests
module TestEachHelpers
  extend T::Sig

  sig do
    type_parameters(:U)
      .params(iter: T::Enumerable[T.type_parameter(:U)],
              blk: T.proc.params(arg0: T.type_parameter(:U)).void)
      .void
  end
  def each_test_case(iter, &blk)
    iter.each(&blk)
  end

  sig do
    type_parameters(:K, :V)
      .params(hash: T::Hash[T.type_parameter(:K), T.type_parameter(:V)],
              blk: T.proc.params(arg0: [T.type_parameter(:K), T.type_parameter(:V)]).void)
      .void
  end
  def each_test_case_hash(hash, &blk)
    hash.each(&blk)
  end
end

# Base test class with common setup and helpers
class DependabotTestCase < Minitest::Test
  include TestEachHelpers
  extend T::Sig

  sig { void }
  def teardown
    # Ensure we clear any cached timeouts between tests
    Dependabot::RegistryClient.clear_cache!

    # Ensure we reset any experiments between tests
    Dependabot::Experiments.reset!
  end

  private

  # Helper method for profiling tests
  sig { params(example_name: String, block: T.proc.void).void }
  def with_profile(example_name, &block)
    if ENV["PROFILE_TESTS"]
      safe_name = example_name.strip.gsub(/[\s#\.-]/, "_").gsub("::", "_").downcase
      name = "../tmp/stackprof_#{safe_name}.dump"
      StackProf.run(mode: :wall, interval: 100, raw: true, out: name, &block)
    else
      yield
    end
  end
end

# VCR configuration (keeping existing setup)
VCR.configure do |config|
  config.cassette_library_dir = "test/fixtures/vcr_cassettes"
  config.hook_into :webmock

  unless ENV["DEPENDABOT_TEST_DEBUG_LOGGER"].nil?
    config.debug_logger = File.open(ENV["DEPENDABOT_TEST_DEBUG_LOGGER"], "w")
  end

  # Prevent auth headers and username:password params being written to VCR cassets
  config.before_record do |interaction|
    interaction.response.headers.transform_keys!(&:downcase).delete("set-cookie")
    interaction.request.headers.transform_keys!(&:downcase).delete("authorization")
    uri = URI.parse(interaction.request.uri)
    interaction.request.uri.sub!(%r{:\/\/.*#{Regexp.escape(uri.host)}}, "://#{uri.host}")
  end

  # Prevent access tokens being written to VCR cassettes
  unless ENV["DEPENDABOT_TEST_ACCESS_TOKEN"].nil?
    config.filter_sensitive_data("<TOKEN>") do
      ENV["DEPENDABOT_TEST_ACCESS_TOKEN"]
    end
  end

  # Let's you set default VCR mode with VCR=all for re-recording
  # episodes. We use :none here to avoid recording new cassettes
  # in CI if it doesn't already exist for a test
  record_mode = ENV["VCR"] ? ENV["VCR"].to_sym : :none
  config.default_cassette_options = { record: record_mode }
end

# Helper methods (ported from spec_helper.rb)
extend T::Sig

sig { params(name: String).returns(String) }
def fixture(name)
  File.read(File.join("test", "fixtures", name))
end

# Creates a temporary directory and writes the provided files into it.
#
# @param files [Array<DependencyFile>] the files to be written into the temporary directory
sig do
  params(
    files: T::Array[Dependabot::DependencyFile],
    tmp_dir_path: String,
    tmp_dir_prefix: String
  ).returns(String)
end
def write_tmp_repo(files,
                   tmp_dir_path: Dependabot::Utils::BUMP_TMP_DIR_PATH,
                   tmp_dir_prefix: Dependabot::Utils::BUMP_TMP_FILE_PREFIX)
  FileUtils.mkdir_p(tmp_dir_path)
  tmp_repo = Dir.mktmpdir(tmp_dir_prefix, tmp_dir_path)
  tmp_repo_path = Pathname.new(tmp_repo).expand_path
  FileUtils.mkpath(tmp_repo_path)

  files.each do |file|
    path = tmp_repo_path.join(file.name)
    FileUtils.mkpath(path.dirname)
    File.write(path, file.content)
  end

  Dir.chdir(tmp_repo_path) do
    Dependabot::SharedHelpers.run_shell_command("git init")
    Dependabot::SharedHelpers.run_shell_command("git add --all")
    Dependabot::SharedHelpers.run_shell_command("git commit -m init")
  end

  tmp_repo_path.to_s
end

# Creates a temporary directory and copies in any files from the specified
# project path. The project path will typically contain a dependency file and a
# lockfile, but it may also include a vendor directory. A git repo will be
# initialized in the tmp directory.
#
# @param project [String] the project directory, located in
# "test/fixtures/projects"
# @return [String] the path to the new temp repo.
sig do
  params(
    project: String,
    path: String,
    tmp_dir_path: String,
    tmp_dir_prefix: String
  ).returns(String)
end
def build_tmp_repo(project,
                   path: "projects",
                   tmp_dir_path: Dependabot::Utils::BUMP_TMP_DIR_PATH,
                   tmp_dir_prefix: Dependabot::Utils::BUMP_TMP_FILE_PREFIX)
  project_path = File.expand_path(File.join("test/fixtures", path, project))

  FileUtils.mkdir_p(tmp_dir_path)
  tmp_repo = Dir.mktmpdir(tmp_dir_prefix, tmp_dir_path)
  tmp_repo_path = Pathname.new(tmp_repo).expand_path
  FileUtils.mkpath(tmp_repo_path)

  FileUtils.cp_r("#{project_path}/.", tmp_repo_path)

  Dir.chdir(tmp_repo_path) do
    Dependabot::SharedHelpers.run_shell_command("git init")
    Dependabot::SharedHelpers.run_shell_command("git add --all")
    Dependabot::SharedHelpers.run_shell_command("git commit -m init")
  end

  tmp_repo_path.to_s
end

sig { params(project: String, directory: String).returns(T::Array[Dependabot::DependencyFile]) }
def project_dependency_files(project, directory: "/")
  project_path = File.expand_path(File.join("test/fixtures/projects", project, directory))

  raise "Fixture does not exist for project: '#{project}'" unless Dir.exist?(project_path)

  Dir.chdir(project_path) do
    # NOTE: Include dotfiles (e.g. .npmrc)
    files = Dir.glob("**/*", File::FNM_DOTMATCH)
    files = files.select { |f| File.file?(f) }
    files.map do |filename|
      content = File.read(filename)
      Dependabot::DependencyFile.new(
        name: filename,
        content: content,
        directory: directory
      )
    end
  end
end

# Spec helper to provide GitHub credentials if set via an environment variable
sig { returns(T::Array[T::Hash[String, String]]) }
def github_credentials
  if ENV["DEPENDABOT_TEST_ACCESS_TOKEN"].nil? && ENV["LOCAL_GITHUB_ACCESS_TOKEN"].nil?
    []
  else
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => ENV["DEPENDABOT_TEST_ACCESS_TOKEN"] || ENV.fetch("LOCAL_GITHUB_ACCESS_TOKEN", nil)
    }]
  end
end

# Load a command from the fixtures/commands directory
sig { params(name: String).returns(String) }
def command_fixture(name)
  path = File.join("test", "fixtures", "commands", name)
  raise "Command fixture '#{name}' does not exist" unless File.exist?(path)

  File.expand_path(path)
end

# Define an anonymous subclass of Dependabot::Requirement for testing purposes
TestRequirement = T.let(Class.new(Dependabot::Requirement) do
  extend T::Sig

  # Initialize with comma-separated requirement constraints
  sig { params(constraint_string: String).void }
  def initialize(constraint_string)
    requirements = constraint_string.split(",").map(&:strip)
    super(requirements)
  end
end, T.class_of(Dependabot::Requirement))

# Define an anonymous subclass of Dependabot::Version for testing purposes
TestVersion = T.let(Class.new(Dependabot::Version) do
  # Initialize with a version string
end, T.class_of(Dependabot::Version))
