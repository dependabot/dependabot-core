# typed: true
# frozen_string_literal: true

require "rspec/its"
require "rspec/sorbet"
require "webmock/rspec"
require "vcr"
require "debug"
require "simplecov"
require "simplecov_json_formatter"
require "stackprof"
require "uri"

# SimpleCov _must_ be started before any dependabot code is loaded
SimpleCov.start do
  command_name "test-process-#{ENV.fetch('TEST_ENV_NUMBER', 1)}"
  add_filter "/spec/"
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

require "dependabot/dependency_file"
require "dependabot/experiments"
require "dependabot/registry_client"
require_relative "dummy_package_manager/dummy"
require_relative "warning_monkey_patch"

ENV["GIT_AUTHOR_NAME"] = "dependabot-ci"
ENV["GIT_AUTHOR_EMAIL"] = "no-reply@github.com"
ENV["GIT_COMMITTER_NAME"] = "dependabot-ci"
ENV["GIT_COMMITTER_EMAIL"] = "no-reply@github.com"

RSpec.configure do |config|
  config.color = true
  config.order = :rand
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.expect_with(:rspec) { |expectations| expectations.max_formatted_output_length = 1000 }
  config.raise_errors_for_deprecations!
  config.example_status_persistence_file_path = ".rspec_status"

  config.after do
    # Ensure we clear any cached timeouts between tests
    Dependabot::RegistryClient.clear_cache!

    # Ensure we reset any experiments between tests
    Dependabot::Experiments.reset!
  end

  config.around do |example|
    if example.metadata[:profile]
      example_name = example.metadata[:full_description].strip.gsub(/[\s#\.-]/, "_").gsub("::", "_").downcase
      name = "../tmp/stackprof_#{example_name}.dump"
      StackProf.run(mode: :wall, interval: 100, raw: true, out: name) do
        example.run
      end
    else
      example.run
    end
  end
end

RSpec::Sorbet.allow_doubles!

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

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

def fixture(*name)
  File.read(File.join("spec", "fixtures", File.join(*name)))
end

# Creates a temporary directory and writes the provided files into it.
#
# @param files [DependencyFile] the files to be written into the temporary directory
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
# "spec/fixtures/projects"
# @return [String] the path to the new temp repo.
def build_tmp_repo(project,
                   path: "projects",
                   tmp_dir_path: Dependabot::Utils::BUMP_TMP_DIR_PATH,
                   tmp_dir_prefix: Dependabot::Utils::BUMP_TMP_FILE_PREFIX)
  project_path = File.expand_path(File.join("spec/fixtures", path, project))

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

def project_dependency_files(project, directory: "/")
  project_path = File.expand_path(File.join("spec/fixtures/projects", project, directory))

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
