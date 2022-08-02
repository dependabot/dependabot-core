# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

module PackageManagerHelper
  def self.use_bundler_1?
    ENV["SUITE_NAME"] == "bundler1"
  end

  def self.use_bundler_2?
    !use_bundler_1?
  end

  def self.bundler_version
    use_bundler_2? ? "2.3.19" : "1.17.3"
  end

  def self.bundler_major_version
    bundler_version.split(".").first
  end
end

def bundler_project_dependency_files(project)
  project_dependency_files(File.join("bundler#{PackageManagerHelper.bundler_major_version}", project))
end

def bundler_project_dependency_file(project, filename:)
  dependency_file = bundler_project_dependency_files(project).find { |file| file.name == filename }

  raise "Dependency File '#{filename} does not exist for project '#{project}'" unless dependency_file

  dependency_file
end

def bundler_build_tmp_repo(project)
  build_tmp_repo(project, path: "projects/bundler1")
end

RSpec.configure do |config|
  config.around do |example|
    if PackageManagerHelper.use_bundler_2? && example.metadata[:bundler_v1_only]
      example.skip
    elsif PackageManagerHelper.use_bundler_1? && example.metadata[:bundler_v2_only]
      example.skip
    else
      example.run
    end
  end
end
