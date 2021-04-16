# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bundler/update_checker/force_updater"

RSpec.describe Dependabot::Bundler::UpdateChecker::ForceUpdater do
  include_context "stub rubygems compact index"

  let(:updater) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      target_version: target_version,
      requirements_update_strategy: update_strategy,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }],
      options: {}
    )
  end
  let(:dependency_files) { bundler_project_dependency_files("gemfile") }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: current_version,
      requirements: requirements,
      package_manager: "bundler"
    )
  end
  let(:dependency_name) { "rspec-mocks" }
  let(:current_version) { "3.5.0" }
  let(:target_version) { "3.6.0" }
  let(:update_strategy) { :bump_versions }
  let(:requirements) do
    [{
      file: "Gemfile",
      requirement: "~> 3.5.0",
      groups: [:default],
      source: nil
    }]
  end
  let(:expected_requirements) do
    [{
      file: "Gemfile",
      requirement: "~> 3.6.0",
      groups: [:default],
      source: nil
    }]
  end

  describe "#updated_dependencies" do
    subject(:updated_dependencies) { updater.updated_dependencies }

    context "when updating the dependency that requires the other" do
      let(:dependency_files) { bundler_project_dependency_files("version_conflict") }
      let(:target_version) { "3.6.0" }
      let(:dependency_name) { "rspec-mocks" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "3.5.0",
          groups: [:default],
          source: nil
        }]
      end
      let(:expected_requirements) do
        [{
          file: "Gemfile",
          requirement: "3.6.0",
          groups: [:default],
          source: nil
        }]
      end

      it "returns the right array of updated dependencies" do
        expect(updated_dependencies).to eq(
          [
            Dependabot::Dependency.new(
              name: "rspec-mocks",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            ),
            Dependabot::Dependency.new(
              name: "rspec-support",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            )
          ]
        )
      end
    end

    context "when updating the dependency that is required by the other" do
      let(:dependency_files) { bundler_project_dependency_files("version_conflict") }
      let(:target_version) { "3.6.0" }
      let(:dependency_name) { "rspec-support" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "3.5.0",
          groups: [:default],
          source: nil
        }]
      end
      let(:expected_requirements) do
        [{
          file: "Gemfile",
          requirement: "3.6.0",
          groups: [:default],
          source: nil
        }]
      end

      it "returns the right array of updated dependencies" do
        expect(updated_dependencies).to eq(
          [
            Dependabot::Dependency.new(
              name: "rspec-support",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            ),
            Dependabot::Dependency.new(
              name: "rspec-mocks",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            )
          ]
        )
      end
    end

    context "when two dependencies require the same subdependency" do
      let(:dependency_files) { bundler_project_dependency_files("version_conflict_mutual_sub") }

      let(:dependency_name) { "rspec-mocks" }
      let(:target_version) { "3.6.0" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 3.5.0",
          groups: [:default],
          source: nil
        }]
      end
      let(:expected_requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 3.6.0",
          groups: [:default],
          source: nil
        }]
      end

      it "returns the right array of updated dependencies" do
        expect(updated_dependencies).to eq(
          [
            Dependabot::Dependency.new(
              name: "rspec-mocks",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            ),
            Dependabot::Dependency.new(
              name: "rspec-expectations",
              version: "3.6.0",
              previous_version: "3.5.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            )
          ]
        )
      end
    end

    context "when another dependency would need to be downgraded" do
      let(:dependency_files) { bundler_project_dependency_files("subdep_blocked_by_subdep") }
      let(:target_version) { "2.0.0" }
      let(:dependency_name) { "dummy-pkg-a" }

      it "raises a resolvability error" do
        expect { updater.updated_dependencies }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when the ruby version would need to change" do
      let(:dependency_files) { bundler_project_dependency_files("legacy_ruby") }
      let(:target_version) { "2.0.5" }
      let(:dependency_name) { "public_suffix" }

      it "raises a resolvability error" do
        expect { updater.updated_dependencies }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end
  end
end
