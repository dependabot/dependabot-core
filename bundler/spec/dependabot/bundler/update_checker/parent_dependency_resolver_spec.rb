# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/update_checker/parent_dependency_resolver"

RSpec.describe Dependabot::Bundler::UpdateChecker::ParentDependencyResolver do
  include_context "stub rubygems compact index"

  let(:resolver) do
    described_class.new(
      dependency_files: dependency_files,
      repo_contents_path: repo_contents_path,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end
  let(:dependency_files) { [gemfile, lockfile] }
  let(:repo_contents_path) { nil }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: [],
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "dummy-pkg-a" }
  let(:current_version) { "1.0.1" }
  let(:target_version) { "2.0.0" }

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "Gemfile.lock")
  end
  let(:gemfile_body) { fixture("ruby", "gemfiles", "subdep_blocked_by_subdep") }
  let(:lockfile_body) do
    fixture("ruby", "lockfiles", "subdep_blocked_by_subdep.lock")
  end

  describe "#blocking_parent_dependencies" do
    subject(:blocking_parent_dependencies) do
      resolver.blocking_parent_dependencies(
        dependency: dependency,
        target_version: target_version
      )
    end

    it "returns the right array of blocking dependencies" do
      expect(blocking_parent_dependencies).to match_array(
        [
          {
            "name" => "dummy-pkg-b",
            "version" => "1.0.0",
            "requirement" => "< 2.0.0"
          }
        ]
      )
    end

    context "with no blocking dependencies" do
      let(:target_version) { "1.5.0" }
      it "returns an empty array" do
        expect(blocking_parent_dependencies).to match_array([])
      end
    end

    context "with multiple blocking dependencies" do
      let(:dependency_name) { "activesupport" }
      let(:current_version) { "5.0.0" }
      let(:target_version) { "6.0.0" }
      let(:gemfile_body) { fixture("ruby", "gemfiles", "multiple_blocking") }
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "multiple_blocking.lock")
      end

      it "returns all of the blocking dependencies" do
        expect(blocking_parent_dependencies).to match_array(
          [
            {
              "name" => "actionpack",
              "version" => "5.0.0",
              "requirement" => "= 5.0.0"
            },
            {
              "name" => "actionview",
              "version" => "5.0.0",
              "requirement" => "= 5.0.0"
            },
            {
              "name" => "activejob",
              "version" => "5.0.0",
              "requirement" => "= 5.0.0"
            }
          ]
        )
      end
    end
  end
end
