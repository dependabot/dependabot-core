# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

def bundler_2_available?
  ENV["SUITE_NAME"] == "bundler2"
end

# Load project files prepended with the bundler version, which is currently only ever bundler1
def bundler_project_dependency_files(project)
  project_dependency_files(File.join("bundler1", project))
end

RSpec.configure do |config|
  config.around do |example|
    if bundler_2_available? && example.metadata[:bundler_v1_only]
      example.skip
    elsif !bundler_2_available? && example.metadata[:bundler_v2_only]
      example.skip
    else
      example.run
    end
  end
end
