# typed: true
# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

module PackageManagerHelper
  def self.bundler_version
    "2"
  end

  # Returns the major version of the Bundler installed in the native helper's
  # GEM_HOME, or nil when no helper-installed Bundler can be found. Lets specs
  # gate behavior on the actual helper runtime instead of hard-coded paths or
  # exact patch versions.
  def self.helper_bundler_major_version
    helpers_root = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", "/opt")
    gemspecs = Dir.glob("#{helpers_root}/bundler/v#{bundler_version}/.bundle/specifications/bundler-*.gemspec")
    return nil if gemspecs.empty?

    versions = gemspecs.map { |f| Gem::Version.new(File.basename(f).match(/bundler-(.*)\.gemspec/)[1]) }
    versions.max.segments.first
  end

  # True when the native helper's runtime Bundler is a major version that
  # cannot resolve `bundler < 3` constraints (i.e. Bundler 4+).
  def self.helper_running_bundler_v4?
    major = helper_bundler_major_version
    !major.nil? && major >= 4
  end
end

def bundler_project_dependency_files(project, directory: "/")
  project_dependency_files(File.join("bundler#{PackageManagerHelper.bundler_version}", project), directory: directory)
    .each do |dep|
      dep.support_file = dep.name.end_with?(".ruby-version", ".tool-versions")
    end
end

def bundler_project_dependency_file(project, filename:)
  project_dependency_files = bundler_project_dependency_files(project)
  dependency_file = project_dependency_files.find { |file| file.name == filename }

  unless dependency_file
    raise "Dependency File '#{filename} does not exist for project '#{project}'. " \
          "This is the list of files found:\n  * #{project_dependency_files.map(&:name).join("\n  * ")}"
  end

  dependency_file
end

def bundler_build_tmp_repo(project)
  build_tmp_repo(project, path: "projects/bundler2")
end

def suppress_output
  original_stderr = $stderr.clone
  original_stdout = $stdout.clone
  $stderr.reopen(File.new(File::NULL, "w"))
  $stdout.reopen(File.new(File::NULL, "w"))
  yield
ensure
  $stdout.reopen(original_stdout)
  $stderr.reopen(original_stderr)
end

RSpec.configure do |config|
  config.after do
    # Cleanup side effects from cloning git gems, so that they don't interfere
    # with other specs.
    bundle_path = File.join(
      Dependabot::Utils::BUMP_TMP_DIR_PATH,
      ".bundle",
      "ruby",
      RbConfig::CONFIG["ruby_version"]
    )

    FileUtils.rm_rf File.join(bundle_path, "bundler")
    FileUtils.rm_rf File.join(bundle_path, "cache", "bundler", "git")
  end
end
