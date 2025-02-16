# typed: true
# frozen_string_literal: true

def common_dir
  @common_dir ||= Gem::Specification.find_by_name("dependabot-common").gem_dir
end

def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

def create_dependency(name:, version:, required_version:, previous_required_version:, file: "package.json")
  Dependabot::Dependency.new(
    name: name,
    version: version,
    package_manager: "bun",
    requirements: [{
      file: file,
      requirement: required_version,
      groups: ["dependencies"],
      source: nil
    }],
    previous_requirements: [{
      file: file,
      requirement: previous_required_version,
      groups: ["dependencies"],
      source: nil
    }]
  )
end
