# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/npm_lockfile_updater"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::NpmLockfileUpdater do
  let(:updater) do
    described_class.new(
      lockfile: package_lock,
      dependency_files: files,
      dependencies: dependencies,
      credentials: credentials
    )
  end
  let(:dependencies) { [dependency] }

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com"
    }]
  end

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
  let(:package_lock) do
    files.find { |f| f.name == "package-lock.json" }
  end

  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  before { FileUtils.mkdir_p(tmp_path)  }

  subject(:updated_npm_lock_content) { updater.updated_lockfile.content }

  describe "npm 6 specific" do
    # NOTE: This is no longer failing in npm 8
    context "with a corrupted npm lockfile (version missing)" do
      let(:files) { project_dependency_files("npm6/version_missing") }

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

    # NOTE: This spec takes forever to run using npm 8
    context "when a git src dependency doesn't have a valid package.json" do
      let(:files) { project_dependency_files("npm6/git_missing_version") }

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

      it "raises a DependencyFileNotResolvable error" do
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "git sub-dependency with invalid from that is updating from an npm5 lockfile" do
      let(:files) { project_dependency_files("npm5/git_sub_dep_invalid") }

      it "cleans up from field and successfully updates" do
        updated_fetch_factory_version =
          JSON.parse(updated_npm_lock_content).
          fetch("dependencies")["fetch-factory"]["version"]
        expect(updated_fetch_factory_version).to eq("0.0.2")
      end
    end

    # NOTE: This no longer raises in npm 8
    context "when there is a private git dep we don't have access to" do
      let(:files) { project_dependency_files("npm6/github_dependency_private") }

      let(:dependency_name) { "strict-uri-encode" }
      let(:version) { "1.1.0" }
      let(:requirements) { [] }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }.
          to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
          expect(error.dependency_urls).
            to eq(
              [
                "https://github.com/hmarr/dependabot-test-private-npm-package.git/"
              ]
            )
        end
      end
    end
  end

  describe "npm 8 specific" do
    # NOTE: This used to raise in npm 6
    context "when there is a private git dep we don't have access to" do
      let(:files) { project_dependency_files("npm8/github_dependency_private") }

      let(:dependency_name) { "strict-uri-encode" }
      let(:version) { "1.1.0" }
      let(:requirements) { [] }

      it "updates the dependency and leaves the private git dep alone" do
        parsed_lockfile = JSON.parse(updated_npm_lock_content)
        expect(parsed_lockfile.fetch("dependencies")["strict-uri-encode"]["version"]).
          to eq("1.1.0")
        expect(parsed_lockfile.fetch("dependencies")["bus-replacement-service"]["version"]).
          to include("19c4dba3bfce7574e28f1df2138d47ab4cc665b3")
      end
    end

    context "when the packages name needs sanitizing" do
      let(:files) { project_dependency_files("npm8/simple") }

      it "restores the packages name attribute" do
        parsed_lockfile = JSON.parse(updated_npm_lock_content)
        expected_updated_npm_lock_content = fixture("updated_projects", "npm8", "simple", "package-lock.json")
        expect(updated_npm_lock_content).to eq(expected_updated_npm_lock_content)
        expect(parsed_lockfile.dig("packages", "", "name")).to eq("project-name")
      end
    end

    context "when the lockfile does not have indentation" do
      let(:files) { project_dependency_files("npm8/simple_no_indentation") }

      it "defaults to npm and uses two spaces" do
        expected_updated_npm_lock_content = fixture("updated_projects", "npm8", "simple_no_indentation",
                                                    "package-lock.json")
        expect(updated_npm_lock_content).to eq(expected_updated_npm_lock_content)
      end
    end

    context "when the lockfile contains a trailing newline" do
      let(:files) { project_dependency_files("npm8/lockfile_with_newline") }

      it "ignores the newline when calculating indentation" do
        expected_updated_npm_lock_content = fixture("updated_projects", "npm8", "lockfile_with_newline",
                                                    "package-lock.json")
        expect(updated_npm_lock_content).to eq(expected_updated_npm_lock_content)
      end
    end

    context "when there's an out of date packages name attribute" do
      let(:files) { project_dependency_files("npm8/packages_name_outdated") }
      let(:dependency_name) { "etag" }
      let(:version) { "1.8.1" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^1.8.1",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_version) { "1.8.0" }
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^1.0.0",
          groups: ["dependencies"],
          source: nil
        }]
      end

      it "maintains the original packages name attribute" do
        parsed_lockfile = JSON.parse(updated_npm_lock_content)
        expected_updated_npm_lock_content = fixture(
          "updated_projects", "npm8", "packages_name_outdated", "package-lock.json"
        )
        expect(updated_npm_lock_content).to eq(expected_updated_npm_lock_content)
        expect(parsed_lockfile.dig("packages", "", "name")).to eq("old-name")
      end
    end

    context "when the original lockfile didn't have a packages name attribute" do
      let(:files) { project_dependency_files("npm8/packages_name_missing") }
      let(:dependency_name) { "etag" }
      let(:version) { "1.8.1" }
      let(:requirements) do
        [{
          file: "package.json",
          requirement: "^1.8.1",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:previous_version) { "1.8.0" }
      let(:previous_requirements) do
        [{
          file: "package.json",
          requirement: "^1.0.0",
          groups: ["dependencies"],
          source: nil
        }]
      end

      it "doesn't add a packages name attribute" do
        parsed_lockfile = JSON.parse(updated_npm_lock_content)
        expected_updated_npm_lock_content = fixture(
          "updated_projects", "npm8", "packages_name_missing", "package-lock.json"
        )
        expect(updated_npm_lock_content).to eq(expected_updated_npm_lock_content)
        expect(parsed_lockfile.dig("packages", "").key?("name")).to eq(false)
      end
    end
  end

  %w(npm6 npm8).each do |npm_version|
    describe "#{npm_version} updates" do
      let(:files) { project_dependency_files("#{npm_version}/simple") }

      it "has details of the updated item" do
        parsed_lockfile = JSON.parse(updated_npm_lock_content)
        expect(parsed_lockfile["dependencies"]["fetch-factory"]["version"]).
          to eq("0.0.2")
      end

      context "when the requirement has not been updated" do
        let(:requirements) { previous_requirements }

        it "has details of the updated item" do
          parsed_lockfile = JSON.parse(updated_npm_lock_content)
          expect(parsed_lockfile["dependencies"]["fetch-factory"]["version"]).
            to eq("0.0.2")

          expect(
            parsed_lockfile.dig(
              "dependencies", "fetch-factory", "requires", "es6-promise"
            )
          ).to eq("^3.0.2")
        end
      end

      context "git sub-dependency with invalid from" do
        let(:files) { project_dependency_files("#{npm_version}/git_sub_dep_invalid_from") }

        it "cleans up from field and successfully updates" do
          expect(JSON.parse(updated_npm_lock_content)["dependencies"]["fetch-factory"]["version"]).
            to eq("0.0.2")
        end
      end
    end

    describe "#{npm_version} errors" do
      context "with a sub dependency name that can't be found" do
        let(:files) { project_dependency_files("#{npm_version}/github_sub_dependency_name_missing") }

        let(:dependency_name) { "test-missing-dep-name-npm-package" }
        let(:requirements) do
          [{
            requirement: nil,
            file: "package.json",
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/" \
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
              url: "https://github.com/dependabot-fixtures/" \
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
        let(:files) { project_dependency_files("#{npm_version}/invalid_requirement") }

        it "raises a helpful error" do
          expect { updated_npm_lock_content }.
            to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end

      context "because we're updating to a nonexistent version" do
        let(:files) { project_dependency_files("#{npm_version}/simple") }

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
        let(:files) { project_dependency_files("#{npm_version}/nonexistent_dependency_yanked_version") }

        it "raises a helpful error" do
          expect { updated_npm_lock_content }.
            to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
        end
      end

      context "with a git reference that Yarn would find but npm wouldn't" do
        let(:files) { project_dependency_files("#{npm_version}/git_dependency_yarn_ref") }

        it "raises a helpful error" do
          expect { updated_npm_lock_content }.
            to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end

      context "when scoped sub dependency version is missing" do
        let(:files) { project_dependency_files("#{npm_version}/github_scoped_sub_dependency_version_missing") }

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
              url: "https://github.com/dependabot-fixtures/" \
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
              url: "https://github.com/dependabot-fixtures/" \
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
        let(:files) { project_dependency_files("#{npm_version}/github_sub_dependency_version_missing") }

        let(:dependency_name) { "test-missing-dep-version-npm-package" }
        let(:requirements) do
          [{
            requirement: nil,
            file: "package.json",
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/" \
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
              url: "https://github.com/dependabot-fixtures/" \
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

      context "with an invalid package name" do
        let(:files) { project_dependency_files("#{npm_version}/invalid_package_name") }
        let(:dependency_name) { "fetch-factory:" }

        it "raises a helpful error" do
          expect { updated_npm_lock_content }.
            to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end

      context "with a dependency version that can't be found" do
        let(:files) { project_dependency_files("#{npm_version}/yanked_version") }

        let(:dependency_name) { "etag" }
        let(:version) { "1.8.0" }
        let(:previous_version) { "1.0.0" }
        let(:requirements) do
          [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: ["dependencies"],
            source: nil
          }]
        end
        let(:previous_requirements) do
          [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: ["dependencies"],
            source: nil
          }]
        end

        it "raises a helpful error" do
          expect { updated_npm_lock_content }.
            to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end
    end
  end

  context "when updating a git source dependency that is not pinned to a hash" do
    subject { JSON.parse(updated_npm_lock_content) }

    let(:files) { project_dependency_files("npm6/ghpr_no_hash_pinning") }
    let(:dependency_name) { "npm6-dependency" }
    let(:version) { "HEAD" }
    let(:previous_version) { "5d1be9ff4e12eb17c04591bba13aad6d71c86a1b" }
    let(:requirements) do
      [{
        file: "package.json",
        requirement: nil,
        groups: ["dependencies"],
        source: {
          type: "git",
          url: "https://github.com/dependabot-fixtures/npm6-dependency",
          branch: nil,
          ref: "master"
        }
      }]
    end
    let(:previous_requirements) do
      [{
        file: "package.json",
        requirement: nil,
        groups: ["dependencies"],
        source: {
          type: "git",
          url: "https://github.com/dependabot-fixtures/npm6-dependency",
          branch: nil,
          ref: "master"
        }
      }]
    end

    it "pins the version to a hash and ensures that the `from` field matches the original constraint" do
      expect(subject["dependencies"]["npm6-dependency"]["version"]).
        to match(%r{github:dependabot-fixtures/npm6-dependency#[0-9a-z]{40}})
      expect(subject["dependencies"]["npm6-dependency"]["from"]).to eq("github:dependabot-fixtures/npm6-dependency")
    end
  end
end
