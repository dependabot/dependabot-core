# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java_script/npm_and_yarn/version_resolver"

namespace = Dependabot::UpdateCheckers::JavaScript::NpmAndYarn
RSpec.describe namespace::SubdependencyVersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end

  let(:dependency_files) { [package_json, yarn_lock] }
  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: fixture("javascript", "package_files", manifest_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "package.json" }
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: fixture("javascript", "yarn_lockfiles", yarn_lock_fixture_name)
    )
  end
  let(:yarn_lock_fixture_name) { "yarn.lock" }
  let(:npm_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: fixture("javascript", "npm_lockfiles", npm_lock_fixture_name)
    )
  end
  let(:npm_lock_fixture_name) { "package-lock.json" }
  let(:shrinkwrap) do
    Dependabot::DependencyFile.new(
      name: "npm-shrinkwrap.json",
      content: fixture("javascript", "npm_lockfiles", shrinkwrap_fixture_name)
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

      it { is_expected.to eq(Gem::Version.new("5.7.3")) }

      context "when using npm5" do
        let(:npm_lock_fixture_name) { "subdependency_update_npm5.json" }

        # Note: npm5 lockfiles have exact version requires so can't easily
        # update specific sub-dependencies to a new version, make sure we keep
        # the same version
        it { is_expected.to eq(Gem::Version.new("5.2.1")) }
      end
    end
  end
end
