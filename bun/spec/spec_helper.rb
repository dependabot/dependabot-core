# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

extend T::Sig # rubocop:disable Style/MixinUsage

sig { returns(String) }
def common_dir
  @common_dir ||= T.let(Gem::Specification.find_by_name("dependabot-common").gem_dir, T.nilable(String))
end

sig { params(path: String).returns(T::Boolean) }
def require_common_spec(path)
  require "#{common_dir}/spec/dependabot/#{path}"
end

require "#{common_dir}/spec/spec_helper.rb"

sig do
  params(
    name: String,
    version: T.nilable(String),
    required_version: T.nilable(Dependabot::DependencyRequirement::Requirement),
    previous_required_version: T.nilable(Dependabot::DependencyRequirement::Requirement),
    file: String
  ).returns(Dependabot::Dependency)
end
def create_bun_dependency(name:, version:, required_version:, previous_required_version:, file: "package.json")
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
