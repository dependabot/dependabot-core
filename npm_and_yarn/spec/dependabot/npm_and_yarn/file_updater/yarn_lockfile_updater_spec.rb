# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::YarnLockfileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials
    )
  end
  let(:dependencies) { [dependency] }
  let(:files) { [package_json, yarn_lock] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com"
    }]
  end
  let(:package_json) do
    Dependabot::DependencyFile.new(
      content: package_json_body,
      name: "package.json"
    )
  end
  let(:package_json_body) { fixture("package_files", manifest_fixture_name) }
  let(:manifest_fixture_name) { "package.json" }
  let(:yarn_lock) do
    Dependabot::DependencyFile.new(
      name: "yarn.lock",
      content: yarn_lock_body
    )
  end
  let(:yarn_lock_body) { fixture("yarn_lockfiles", yarn_lock_fixture_name) }
  let(:yarn_lock_fixture_name) { "yarn.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      previous_version: previous_version,
      requirements: requirements,
      previous_requirements: previous_requirements,
      package_manager: "npm_and_yarn"
    )
  end
  let(:dependency_name) { "fetch-factory" }
  let(:version) { "0.0.2" }
  let(:previous_version) { "0.0.1" }
  let(:requirements) do
    [{
      file: "package.json",
      requirement: "^0.0.2",
      groups: ["dependencies"],
      source: nil
    }]
  end
  let(:previous_requirements) do
    [{
      file: "package.json",
      requirement: "^0.0.1",
      groups: ["dependencies"],
      source: nil
    }]
  end

  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "errors" do
    subject(:updated_yarn_lock_content) { updater.updated_yarn_lock_content(yarn_lock) }

    context "with a dependency version that can't be found" do
      let(:manifest_fixture_name) { "yanked_version.json" }

      it "raises a helpful error" do
        expect { updated_yarn_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a sub dependency name that can't be found" do
      let(:manifest_fixture_name) do
        "github_sub_dependency_name_missing.json"
      end
      let(:yarn_lock_fixture_name) do
        "github_sub_dependency_name_missing.lock"
      end

      let(:dependency_name) { "test-missing-dep-name-npm-package" }
      let(:requirements) do
        [{
          requirement: nil,
          file: "package.json",
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/dependabot-fixtures/"\
            "test-missing-dep-name-npm-package",
            branch: nil,
            ref: ref
          }
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: nil,
          file: "package.json",
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/dependabot-fixtures/"\
            "test-missing-dep-name-npm-package",
            branch: nil,
            ref: old_ref
          }
        }]
      end
      let(:previous_version) { "1be88e036981a8511eacf3f20e0a21507349988d" }
      let(:version) { "346e79a12f34c5937bf0f016bced0723f864fe19" }
      let(:ref) { "v1.0.1" }
      let(:old_ref) { "v1.0.0" }

      it "raises a helpful error" do
        expect { updated_yarn_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with an invalid requirement in the package.json" do
      let(:manifest_fixture_name) { "invalid_requirement.json" }
      let(:yarn_lock_fixture_name) { "yarn.lock" }

      it "raises a helpful error" do
        expect { updated_yarn_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when there is a private dep we don't have access to" do
      let(:manifest_fixture_name) { "private_source.json" }
      let(:yarn_lock_fixture_name) { "private_source.lock" }

      it "raises a helpful error" do
        expect { updated_yarn_lock_content }.
          to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end

      context "that is unscoped" do
        let(:manifest_fixture_name) { "private_source_unscoped.json" }
        let(:yarn_lock_fixture_name) { "private_source_unscoped.lock" }

        let(:dependency_name) { "my-private-dep-asdlfkasdf" }
        let(:version) { "1.0.1" }
        let(:previous_version) { "1.0.0" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: ["devDependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: ["devDependencies"],
            source: nil
          }]
        end

        it "raises a helpful error" do
          expect { updated_yarn_lock_content }.
            to raise_error do |error|
            expect(error).
              to be_a(Dependabot::PrivateSourceAuthenticationFailure)
            expect(error.source).to eq("npm-proxy.fury.io/<redacted>")
          end
        end

        context "with bad credentials" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "npm_registry",
              "registry" => "npm-proxy.fury.io/dependabot",
              "token" => "bad_token"
            }]
          end

          # TODO: Fix broken test
          it "raises a helpful error" do
            expect { updated_yarn_lock_content }.
              to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
          end
        end
      end
    end

    context "because we're updating to a nonexistent version" do
      let(:yarn_lock_fixture_name) { "yarn.lock" }
      let(:manifest_fixture_name) { "package.json" }

      let(:dependency_name) { "fetch-factory" }
      let(:version) { "5.0.2" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^5.0.2",
          groups: ["dependencies"],
          source: nil
        }]
      end

      it "raises an unhandled error" do
        expect { updated_yarn_lock_content }.
          to raise_error(Dependabot::InconsistentRegistryResponse)
      end
    end

    context "with a dependency that can't be found" do
      let(:manifest_fixture_name) { "nonexistent_dependency.json" }
      let(:yarn_lock_fixture_name) { "yanked_version.lock" }

      it "raises a helpful error" do
        expect { updated_yarn_lock_content }.
          to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a registry that times out" do
      let(:manifest_fixture_name) { "package.json" }
      let(:yarn_lock_fixture_name) { "yarn.lock" }
      let(:yarnrc) do
        Dependabot::DependencyFile.new(
          name: ".yarnrc",
          content: 'registry "https://timeout.cv/repository/mirror/"'
        )
      end

      let(:files) { [package_json, yarn_lock, yarnrc] }
      # This test is extremely slow (it takes 1m45 to run) so should only be
      # run locally.
      # it "raises a helpful error" do
      #   expect { updated_yarn_lock_content }.
      #     to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
      #       expect(error.source).to eq("timeout.cv/repository/mirror")
      #     end
      # end
    end

    context "when scoped sub dependency version is missing" do
      let(:manifest_fixture_name) do
        "github_scoped_sub_dependency_version_missing.json"
      end
      let(:yarn_lock_fixture_name) do
        "github_scoped_sub_dependency_version_missing.lock"
      end

      let(:dependency_name) do
        "@dependabot/test-missing-scoped-dep-version-npm-package"
      end
      let(:requirements) do
        [{
          requirement: nil,
          file: "package.json",
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/dependabot-fixtures/"\
            "test-missing-scoped-dep-version-npm-package",
            branch: nil,
            ref: ref
          }
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: nil,
          file: "package.json",
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/dependabot-fixtures/"\
            "test-missing-scoped-dep-version-npm-package",
            branch: nil,
            ref: old_ref
          }
        }]
      end
      let(:previous_version) { "fe5138f33735fb07891d348cd1e985fe3134211c" }
      let(:version) { "7abd161c8eba336f06173f0a97bc8decc3cd9c2c" }
      let(:ref) { "v1.0.4" }
      let(:old_ref) { "v1.0.3" }

      it "raises an error" do
        expect { updated_yarn_lock_content }.
          to raise_error(Dependabot::InconsistentRegistryResponse)
      end
    end

    context "when sub dependency version is missing" do
      let(:manifest_fixture_name) do
        "github_sub_dependency_version_missing.json"
      end
      let(:yarn_lock_fixture_name) do
        "github_sub_dependency_version_missing.lock"
      end

      let(:dependency_name) { "test-missing-dep-version-npm-package" }
      let(:requirements) do
        [{
          requirement: nil,
          file: "package.json",
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/dependabot-fixtures/"\
            "test-missing-dep-version-npm-package",
            branch: nil,
            ref: ref
          }
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: nil,
          file: "package.json",
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/dependabot-fixtures/"\
            "test-missing-dep-version-npm-package",
            branch: nil,
            ref: old_ref
          }
        }]
      end
      let(:previous_version) { "f56186c1643a9a09a86dfe09b1890921330c28bb" }
      let(:version) { "3deb2768be1591f2fdbdec40aa6a63ba6b270b40" }
      let(:ref) { "v1.0.3" }
      let(:old_ref) { "v1.0.2" }

      it "raises an error" do
        expect { updated_yarn_lock_content }.
          to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
      end
    end

    context "when a git src dependency doesn't have a valid package.json" do
      let(:manifest_fixture_name) { "git_missing_version.json" }
      let(:yarn_lock_fixture_name) { "git_missing_version.lock" }

      let(:dependency_name) { "raven-js" }
      let(:requirements) do
        [{
          requirement: nil,
          file: "package.json",
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/getsentry/raven-js",
            branch: nil,
            ref: ref
          }
        }]
      end
      let(:previous_requirements) do
        [{
          requirement: nil,
          file: "package.json",
          groups: ["dependencies"],
          source: {
            type: "git",
            url: "https://github.com/getsentry/raven-js",
            branch: nil,
            ref: old_ref
          }
        }]
      end
      let(:previous_version) { "c2b377e7a254264fd4a1fe328e4e3cfc9e245570" }
      let(:version) { "70b24ed25b73cc15472b2bd1c6032e22bf20d112" }
      let(:ref) { "4.4.1" }
      let(:old_ref) { "3.23.1" }

      it "raises helpful error" do
        expect { updated_yarn_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end
  end
end
