# frozen_string_literal: true

require "rspec/its"
require "webmock/rspec"
require "vcr"
require "debug"
require "simplecov"
require "simplecov-console"
require "stackprof"
require "uri"

require "dependabot/dependency_file"
require "dependabot/experiments"
require "dependabot/registry_client"
require_relative "dummy_package_manager/dummy"
require_relative "warning_monkey_patch"

if ENV["COVERAGE"]
  SimpleCov::Formatter::Console.output_style = "block"
  SimpleCov.formatter = if ENV["CI"]
                          SimpleCov::Formatter::Console
                        else
                          SimpleCov::Formatter::HTMLFormatter
                        end

  SimpleCov.start do
    add_filter "/spec/"

    enable_coverage :branch
    minimum_coverage line: 80, branch: 70
    # TODO: Enable minimum coverage per file once outliers have been increased
    # minimum_coverage_by_file 80
    refuse_coverage_drop
  end
end

Dependabot::SharedHelpers.run_shell_command("git config --global user.email no-reply@github.com")
Dependabot::SharedHelpers.run_shell_command("git config --global user.name dependabot-ci")

RSpec.configure do |config|
  config.color = true
  config.order = :rand
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
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
  # episodes. :once is VCR default
  record_mode = ENV["VCR"] ? ENV["VCR"].to_sym : :once
  config.default_cassette_options = { record: record_mode }
end

def fixture(*name)
  File.read(File.join("spec", "fixtures", File.join(*name)))
end

# Creates a temporary directory and copies in any files from the specified
# project path. The project path will typically contain a dependency file and a
# lockfile, but it may also include a vendor directory. A git repo will be
# initialized in the tmp directory.
#
# @param project [String] the project directory, located in
# "spec/fixtures/projects"
# @return [String] the path to the new temp repo.
def build_tmp_repo(project, path: "projects")
  project_path = File.expand_path(File.join("spec/fixtures", path, project))

  tmp_dir = Dependabot::Utils::BUMP_TMP_DIR_PATH
  prefix = Dependabot::Utils::BUMP_TMP_FILE_PREFIX
  FileUtils.mkdir_p(tmp_dir)
  tmp_repo = Dir.mktmpdir(prefix, tmp_dir)
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

def project_dependency_files_updated_expected(project)
  project_path = File.expand_path(File.join("spec/fixtures/projects_updated_expected", project))

  raise "Fixture does not exist for project: '#{project}'" unless Dir.exist?(project_path)

  Dir.chdir(project_path) do
    # NOTE: Include dotfiles (e.g. .npmrc)
    files = Dir.glob("**/*", File::FNM_DOTMATCH)
    files = files.select { |f| File.file?(f) }
    files.map do |filename|
      content = File.read(filename)
      Dependabot::DependencyFile.new(
        name: filename,
        content: content
      )
    end
  end
end

def capture_stderr
  previous_stderr = $stderr
  $stderr = StringIO.new
  yield
ensure
  $stderr = previous_stderr
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
