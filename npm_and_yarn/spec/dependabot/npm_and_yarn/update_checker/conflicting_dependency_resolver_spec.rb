# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/update_checker/conflicting_dependency_resolver"

RSpec.describe(Dependabot::NpmAndYarn::UpdateChecker::ConflictingDependencyResolver) do
  let(:resolver) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end
  let(:dependency_files) { [package_json, npm_lock] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("package_files", manifest_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "subdependency_out_of_range_gt.json" }
  let(:npm_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("npm_lockfiles", npm_lock_fixture_name)
    )
  end
  let(:npm_lock_fixture_name) { "subdependency_out_of_range_gt.json" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: [],
      package_manager: "npm_and_yarn"
    )
  end
  let(:dependency_name) { "abind" }
  let(:current_version) { "1.0.5" }
  let(:target_version) { "2.0.0" }

  describe "#conflicting_dependencies" do
    subject(:conflicting_dependencies) do
      resolver.conflicting_dependencies(
        dependency: dependency,
        target_version: target_version
      )
    end

    it "returns the right array of blocking dependencies" do
      expect(conflicting_dependencies).to match_array(
        [
          {
            "name" => "objnest",
            "version" => "4.1.2",
            "requirement" => "^1.0.0"
          }
        ]
      )
    end

    context "with no blocking dependencies" do
      let(:target_version) { "1.0.0" }

      it "returns an empty array" do
        expect(conflicting_dependencies).to match_array([])
      end
    end

    context "yarn" do
      let(:yarn_lock) do
        Dependabot::DependencyFile.new(
          name: "yarn.lock",
          content: fixture("yarn_lockfiles", yarn_lock_fixture_name)
        )
      end
      let(:yarn_lock_fixture_name) { "subdependency_out_of_range_gt.lock" }

      let(:dependency_files) { [package_json, yarn_lock] }

      it "returns the right array of blocking dependencies" do
        expect(conflicting_dependencies).to match_array(
          [
            {
              "name" => "objnest",
              "version" => "4.1.4",
              "requirement" => "^1.0.0"
            }
          ]
        )
      end
    end
  end
end
