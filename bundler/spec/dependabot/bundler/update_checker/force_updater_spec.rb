# typed: false
# frozen_string_literal: true

require "spec_helper"
require "shared_contexts"

require "dependabot/bundler/update_checker/force_updater"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/requirements_update_strategy"

RSpec.describe Dependabot::Bundler::UpdateChecker::ForceUpdater do
  include_context "when stubbing rubygems compact index"

  let(:updater) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      target_version: Gem::Version.new(target_version),
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
  let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }
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
        expect { updater.updated_dependencies }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when the ruby version would need to change" do
      let(:dependency_files) { bundler_project_dependency_files("legacy_ruby") }
      let(:target_version) { "2.0.5" }
      let(:dependency_name) { "public_suffix" }

      it "raises a resolvability error" do
        expect { updater.updated_dependencies }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when peer dependencies in the Gemfile should update together" do
      let(:dependency_files) { bundler_project_dependency_files("top_level_update") }
      let(:target_version) { "19.4" }
      let(:dependency_name) { "octicons" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 19.2",
          groups: [:default],
          source: nil
        }]
      end
      let(:expected_requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 19.4",
          groups: [:default],
          source: nil
        }]
      end

      it "updates all dependencies" do
        expect(updated_dependencies).to eq(
          [
            Dependabot::Dependency.new(
              name: "octicons",
              version: "19.4.0",
              previous_version: "19.2.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            ),
            Dependabot::Dependency.new(
              name: "octicons_helper",
              version: "19.4.0",
              previous_version: "19.2.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            )
          ]
        )
      end
    end

    context "when peer dependencies in the Gemfile should update together, but not unlock git gems too" do
      let(:dependency_files) { bundler_project_dependency_files("top_level_update_with_git_gems") }
      let(:target_version) { "5.12.0" }
      let(:dependency_name) { "sentry-rails" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 5.10",
          groups: [:default],
          source: nil
        }]
      end
      let(:expected_requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 5.12",
          groups: [:default],
          source: nil
        }]
      end

      it "updates all related dependencies" do
        expect(updated_dependencies).to eq(
          [
            Dependabot::Dependency.new(
              name: "sentry-rails",
              version: "5.12.0",
              previous_version: "5.10.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            ),
            Dependabot::Dependency.new(
              name: "sentry-ruby",
              version: "5.12.0",
              previous_version: "5.10.0",
              requirements: expected_requirements,
              previous_requirements: requirements,
              package_manager: "bundler"
            )
          ]
        )
      end
    end

    context "when peer dependencies in the Gemfile shouldn't update together, since one of them would be downgraded" do
      let(:dependency_files) { bundler_project_dependency_files("no_downgrades") }
      let(:target_version) { "7.1.1" }
      let(:dependency_name) { "rails" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "~> 7.1",
          groups: [:default],
          source: nil
        }]
      end

      it "raises a resolvability error" do
        pending "dependency updates probably broke this test, need a more robust one!"
        expect { updater.updated_dependencies }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when lockfile_only strategy is used and manifest would need updates" do
      let(:update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }
      let(:dependency_files) { bundler_project_dependency_files("lockfile_only_and_forced_updates") }
      let(:target_version) { "4.0.0.beta7" }
      let(:dependency_name) { "activeadmin" }
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: "4.0.0.beta6",
          groups: [:default],
          source: nil
        }]
      end

      it "raises a resolvability error" do
        expect { updater.updated_dependencies }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end
  end
end
