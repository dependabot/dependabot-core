# typed: false
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
      latest_allowable_version: latest_allowable_version,
      repo_contents_path: nil
    )
  end

  let(:latest_allowable_version) { dependency.version }
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:ignored_versions) { [] }

  # Variable to control the npm fallback version feature flag
  let(:npm_fallback_version_above_v6_enabled) { true }

  # Variable to control the enabling feature flag for the corepack fix
  let(:enable_corepack_for_npm_and_yarn) { true }

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:npm_fallback_version_above_v6).and_return(npm_fallback_version_above_v6_enabled)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_corepack_for_npm_and_yarn).and_return(enable_corepack_for_npm_and_yarn)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout).and_return(true)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    context "without a lockfile" do
      let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }
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
        expect { latest_resolvable_version }
          .to raise_error("Not a subdependency!")
      end
    end

    context "with an invalid package.json" do
      let(:dependency_files) { project_dependency_files("npm6/nonexistent_dependency") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.5.3",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it "gracefully handles package not found exception" do
        expect(latest_resolvable_version).to be_nil
      end
    end

    context "with a yarn.lock" do
      let(:dependency_files) { project_dependency_files("yarn/no_lockfile_change") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.1.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      # NOTE: The latest version is 6.0.2, but we can't reach it as other
      # dependencies constrain us
      it { is_expected.to eq(Gem::Version.new("5.7.4")) }
    end

    context "with a pnpm-lock.yaml" do
      let(:dependency_files) { project_dependency_files("pnpm/no_lockfile_change") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.1.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      # NOTE: The latest version is 6.0.2, but we can't reach it as other
      # dependencies constrain us
      it { is_expected.to eq(Gem::Version.new("5.7.4")) }
    end

    context "with a npm8 package-lock.json" do
      let(:dependency_files) { project_dependency_files("npm8/subdependency_update") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.5.3",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      it "calls run_npm_updater when npm8? is true" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:npm8?).and_return(true)
        expect(resolver).to receive(:run_npm_updater).and_call_original
        expect(latest_resolvable_version).to eq(Gem::Version.new("5.7.4"))
      end

      # NOTE: The latest vision is 6.0.2, but we can't reach it as other
      # dependencies constrain us
      it "calls run_npm6_updater when npm8? is false" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:npm8?).and_return(false)
        expect(resolver).to receive(:run_npm6_updater).and_call_original
        expect(latest_resolvable_version).to eq(Gem::Version.new("5.7.4"))
      end
    end

    context "with a npm6 package-lock.json" do
      let(:dependency_files) { project_dependency_files("npm6/subdependency_update") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.5.3",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      # NOTE: The latest vision is 6.0.2, but we can't reach it as other
      # dependencies constrain us
      it { is_expected.to eq(Gem::Version.new("5.7.4")) }
    end

    context "with a npm5 package-lock.json" do
      let(:npm_fallback_version_above_v6_enabled) { false }
      let(:dependency_files) { project_dependency_files("npm5/subdependency_update") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.5.3",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      # NOTE: npm5 lockfiles have exact version requires so can't easily
      # update specific sub-dependencies to a new version, make sure we keep
      # the same version
      it { is_expected.to eq(Gem::Version.new("5.2.1")) }
    end

    context "when sub-dependency is bundled" do
      let(:dependency_files) { project_dependency_files("npm6/bundled_sub_dependency") }

      let(:dependency_name) { "tar" }
      let(:version) { "4.4.10" }
      let(:previous_version) { "4.4.1" }
      let(:requirements) { [] }
      let(:previous_requirements) { [] }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "tar",
          version: "4.4.1",
          requirements: [],
          package_manager: "npm_and_yarn",
          subdependency_metadata: [{ npm_bundled: true }]
        )
      end

      it { is_expected.to be_nil }
    end

    context "with a yarn.lock and a package-lock.json" do
      let(:dependency_files) { project_dependency_files("npm6_and_yarn/npm_subdependency_update") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.5.3",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      it { is_expected.to eq(Gem::Version.new("5.7.4")) }

      context "when using npm5" do
        let(:npm_fallback_version_above_v6_enabled) { false }
        let(:dependency_files) { project_dependency_files("npm5_and_yarn/npm_subdependency_update") }

        # NOTE: npm5 lockfiles have exact version requires so can't easily
        # update specific sub-dependencies to a new version, make sure we keep
        # the same version
        it { is_expected.to eq(Gem::Version.new("5.2.1")) }
      end
    end

    context "when updating a sub-dependency across both yarn and npm lockfiles" do
      let(:dependency_files) { project_dependency_files("npm6_and_yarn/nested_sub_dependency_update") }

      let(:latest_allowable_version) { "2.0.2" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "extend",
          version: "2.0.2",
          previous_version: nil,
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it { is_expected.to eq(Gem::Version.new("2.0.2")) }

      context "when out of range version" do
        let(:dependency_files) do
          project_dependency_files("npm6_and_yarn/nested_sub_dependency_update_npm_out_of_range")
        end

        it "updates out of range to latest resolvable version" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("1.3.0"))
        end
      end
    end
  end
end
