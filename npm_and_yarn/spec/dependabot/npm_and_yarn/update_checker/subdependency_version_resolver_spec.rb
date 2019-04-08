# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/update_checker/version_resolver"

namespace = Dependabot::NpmAndYarn::UpdateChecker
RSpec.describe namespace::SubdependencyVersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      latest_allowable_version: latest_allowable_version
    )
  end

  let(:latest_allowable_version) { dependency.version }
  let(:dependency_files) { [package_json, yarn_lock] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("package_files", manifest_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "package.json" }
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: fixture("yarn_lockfiles", yarn_lock_fixture_name)
    )
  end
  let(:yarn_lock_fixture_name) { "yarn.lock" }
  let(:npm_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("npm_lockfiles", npm_lock_fixture_name)
    )
  end
  let(:npm_lock_fixture_name) { "package-lock.json" }
  let(:shrinkwrap) do
    Dependabot::DependencyFile.new(
      name: "npm-shrinkwrap.json",
      content: fixture("npm_lockfiles", shrinkwrap_fixture_name)
    )
  end
  let(:shrinkwrap_fixture_name) { "package-lock.json" }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:ignored_versions) { [] }

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    context "without a lockfile" do
      let(:dependency_files) { [package_json] }

      let(:manifest_fixture_name) { "package.json" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.0.0",
          requirements: [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it "raises a helpful error" do
        expect { latest_resolvable_version }.
          to raise_error("Not a subdependency!")
      end
    end

    context "with an invalid package.json" do
      let(:dependency_files) { [package_json, npm_lock] }

      let(:manifest_fixture_name) { "non_existant_dependency.json" }
      let(:npm_lock_fixture_name) { "subdependency_update.json" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.1.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it "gracefully handles package not found exception" do
        expect(latest_resolvable_version).to be_nil
      end
    end

    context "with a yarn.lock" do
      let(:dependency_files) { [package_json, yarn_lock] }

      let(:manifest_fixture_name) { "no_lockfile_change.json" }
      let(:yarn_lock_fixture_name) { "no_lockfile_change.lock" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.1.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      # Note: The latest vision is 6.0.2, but we can't reach it as other
      # dependencies constrain us
      it { is_expected.to eq(Gem::Version.new("5.7.3")) }
    end

    context "with a package-lock.json" do
      let(:dependency_files) { [package_json, npm_lock] }

      let(:manifest_fixture_name) { "no_lockfile_change.json" }
      let(:npm_lock_fixture_name) { "subdependency_update.json" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.2.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      # Note: The latest vision is 6.0.2, but we can't reach it as other
      # dependencies constrain us
      it { is_expected.to eq(Gem::Version.new("5.7.3")) }

      context "when using npm5 lockfile" do
        let(:npm_lock_fixture_name) { "subdependency_update_npm5.json" }

        # Note: npm5 lockfiles have exact version requires so can't easily
        # update specific sub-dependencies to a new version, make sure we keep
        # the same version
        it { is_expected.to eq(Gem::Version.new("5.2.1")) }
      end
    end

    context "with a yarn.lock and a package-lock.json" do
      let(:dependency_files) { [package_json, npm_lock, yarn_lock] }
      let(:manifest_fixture_name) { "no_lockfile_change.json" }
      let(:npm_lock_fixture_name) { "subdependency_update.json" }
      let(:yarn_lock_fixture_name) { "no_lockfile_change.lock" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.2.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      it { is_expected.to eq(Gem::Version.new("5.7.3")) }

      context "when using npm5" do
        let(:npm_lock_fixture_name) { "subdependency_update_npm5.json" }

        # Note: npm5 lockfiles have exact version requires so can't easily
        # update specific sub-dependencies to a new version, make sure we keep
        # the same version
        it { is_expected.to eq(Gem::Version.new("5.2.1")) }
      end
    end

    context "when updating a sub dep across both yarn and npm lockfiles" do
      let(:dependency_files) do
        [
          package_json,
          npm_lock,
          yarn_lock,
          npm_package_update,
          npm_lock_update,
          npm_package_up_to_date,
          npm_lock_up_to_date,
          yarn_package_update,
          yarn_lock_update
        ]
      end

      let(:npm_package_update) do
        Dependabot::DependencyFile.new(
          name: "packages/package1/package.json",
          content: fixture("package_files", "lerna_sub_dependency_update.json")
        )
      end
      let(:npm_lock_update) do
        Dependabot::DependencyFile.new(
          name: "packages/package1/package-lock.json",
          content: fixture("npm_lockfiles", "lerna_sub_dependency_update.json")
        )
      end

      let(:npm_package_up_to_date) do
        Dependabot::DependencyFile.new(
          name: "packages/package2/package.json",
          content: fixture("package_files",
                           "lerna_sub_dependency_up_to_date.json")
        )
      end
      let(:npm_lock_up_to_date) do
        Dependabot::DependencyFile.new(
          name: "packages/package2/package-lock.json",
          content: fixture("npm_lockfiles",
                           "lerna_sub_dependency_up_to_date.json")
        )
      end

      let(:yarn_package_update) do
        Dependabot::DependencyFile.new(
          name: "packages/package3/package.json",
          content: fixture("package_files", "lerna_sub_dependency_update.json")
        )
      end
      let(:yarn_lock_update) do
        Dependabot::DependencyFile.new(
          name: "packages/package3/yarn.lock",
          content: fixture("yarn_lockfiles",
                           "lerna_sub_dependency_update.lock")
        )
      end

      let(:npm_package_update_out_of_range) do
        Dependabot::DependencyFile.new(
          name: "packages/package4/package.json",
          content: fixture("package_files",
                           "lerna_sub_dependency_update_out_of_range.json")
        )
      end
      let(:npm_lock_update_out_of_range) do
        Dependabot::DependencyFile.new(
          name: "packages/package4/package-lock.json",
          content: fixture("npm_lockfiles",
                           "lerna_sub_dependency_update_out_of_range.json")
        )
      end

      let(:latest_allowable_version) { "2.4.0" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "mime",
          version: "2.3.0",
          previous_version: nil,
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it { is_expected.to eq(Gem::Version.new("2.4.2")) }

      context "when out of range version" do
        let(:dependency_files) do
          [
            package_json,
            npm_lock,
            yarn_lock,
            npm_package_update,
            npm_lock_update,
            npm_package_up_to_date,
            npm_lock_up_to_date,
            yarn_package_update,
            yarn_lock_update,
            npm_package_update_out_of_range,
            npm_lock_update_out_of_range
          ]
        end

        it "updates out of range to latest resolvable version" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("1.6.0"))
        end
      end
    end
  end
end
