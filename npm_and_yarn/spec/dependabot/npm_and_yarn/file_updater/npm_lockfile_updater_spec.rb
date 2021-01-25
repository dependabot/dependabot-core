# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/npm_lockfile_updater"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::NpmLockfileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials
    )
  end
  let(:dependencies) { [dependency] }
  let(:files) { [package_json, package_lock] }
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
  let(:package_lock) do
    Dependabot::DependencyFile.new(
      name: "package-lock.json",
      content: package_lock_body
    )
  end
  let(:package_lock_body) { fixture("npm_lockfiles", npm_lock_fixture_name) }
  let(:npm_lock_fixture_name) { "package-lock.json" }
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
    subject(:updated_npm_lock_content) { updater.updated_lockfile_content(package_lock) }

    context "with a sub dependency name that can't be found" do
      let(:manifest_fixture_name) do
        "github_sub_dependency_name_missing.json"
      end
      let(:npm_lock_fixture_name) do
        "github_sub_dependency_name_missing.json"
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
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with an invalid requirement in the package.json" do
      let(:manifest_fixture_name) { "invalid_requirement.json" }
      let(:npm_lock_fixture_name) { "package-lock.json" }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when there is a private git dep we don't have access to" do
      let(:manifest_fixture_name) { "github_dependency_private.json" }
      let(:npm_lock_fixture_name) { "github_dependency_private.json" }

      let(:dependency_name) { "strict-uri-encode" }
      let(:version) { "1.1.0" }
      let(:requirements) { [] }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
          expect(error.dependency_urls).
            to eq(
              [
                "ssh://git@github.com/hmarr/"\
                "dependabot-test-private-npm-package.git"
              ]
            )
        end
      end
    end

    context "because we're updating to a nonexistent version" do
      let(:npm_lock_fixture_name) { "package-lock.json" }
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
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::InconsistentRegistryResponse)
      end
    end

    context "with a dependency that can't be found" do
      let(:manifest_fixture_name) { "nonexistent_dependency.json" }
      let(:npm_lock_fixture_name) { "yanked_version.json" }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a git reference that Yarn would find but npm wouldn't" do
      let(:manifest_fixture_name) { "git_dependency_yarn_ref.json" }
      let(:npm_lock_fixture_name) { "git_dependency_yarn_ref.json" }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a corrupted npm lockfile (version missing)" do
      let(:manifest_fixture_name) { "package.json" }
      let(:npm_lock_fixture_name) { "version_missing.json" }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message).
            to include(
              "lockfile has some corrupt entries with missing versions"
            )
        end
      end
    end

    context "when scoped sub dependency version is missing" do
      let(:manifest_fixture_name) do
        "github_scoped_sub_dependency_version_missing.json"
      end
      let(:npm_lock_fixture_name) do
        "github_scoped_sub_dependency_version_missing.json"
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
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::InconsistentRegistryResponse)
      end
    end

    context "when sub dependency version is missing" do
      let(:manifest_fixture_name) do
        "github_sub_dependency_version_missing.json"
      end
      let(:npm_lock_fixture_name) do
        "github_sub_dependency_version_missing.json"
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
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
      end
    end

    context "when a git src dependency doesn't have a valid package.json" do
      let(:manifest_fixture_name) { "git_missing_version.json" }
      let(:npm_lock_fixture_name) { "git_missing_version.json" }

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

      it "raises a HelperSubprocessFailed error" do
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with an invalid package name" do
      let(:manifest_fixture_name) { "invalid_package_name.json" }
      let(:npm_lock_fixture_name) { "invalid_package_name.json" }
      let(:dependency_name) { "fetch-factory:" }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end
  end
end
