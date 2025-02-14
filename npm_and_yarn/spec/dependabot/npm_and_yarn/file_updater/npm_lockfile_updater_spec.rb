# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/npm_and_yarn/file_updater/npm_lockfile_updater"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::NpmLockfileUpdater do
  subject(:updated_npm_lock_content) { updater.updated_lockfile.content }

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
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com"
    })]
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

  # Variable to control the npm fallback version feature flag
  let(:npm_fallback_version_above_v6_enabled) { true }

  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  # Variable to control the enabling feature flag for the corepack fix
  let(:enable_corepack_for_npm_and_yarn) { true }

  before do
    FileUtils.mkdir_p(tmp_path)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:npm_fallback_version_above_v6).and_return(npm_fallback_version_above_v6_enabled)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_corepack_for_npm_and_yarn).and_return(enable_corepack_for_npm_and_yarn)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:npm_v6_deprecation_warning).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:avoid_duplicate_updates_package_json).and_return(false)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "npm 6 specific" do
    # NOTE: This is no longer failing in npm 8
    context "with a corrupted npm lockfile (version missing)" do
      let(:npm_fallback_version_above_v6_enabled) { false }
      let(:files) { project_dependency_files("npm6/version_missing") }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include(
              "lockfile has some corrupt entries with missing versions"
            )
        end
      end
    end

    # NOTE: This spec takes forever to run using npm 8
    context "when a git src dependency doesn't have a valid package.json" do
      let(:npm_fallback_version_above_v6_enabled) { false }
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
        expect { updated_npm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when dealing with git sub-dependency with invalid from that is updating from an npm5 lockfile" do
      let(:npm_fallback_version_above_v6_enabled) { false }
      let(:files) { project_dependency_files("npm5/git_sub_dep_invalid") }

      it "cleans up from field and successfully updates" do
        updated_fetch_factory_version =
          JSON.parse(updated_npm_lock_content)
              .fetch("dependencies")["fetch-factory"]["version"]
        expect(updated_fetch_factory_version).to eq("0.0.2")
      end
    end

    # NOTE: This no longer raises in npm 8
    context "when there is a private git dep we don't have access to" do
      let(:npm_fallback_version_above_v6_enabled) { false }
      let(:files) { project_dependency_files("npm6/github_dependency_private") }

      let(:dependency_name) { "strict-uri-encode" }
      let(:version) { "1.1.0" }
      let(:requirements) { [] }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }
          .to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
          expect(error.dependency_urls)
            .to eq(
              [
                "https://github.com/hmarr/dependabot-test-private-npm-package.git/"
              ]
            )
        end
      end
    end

    context "when there is a dep hosted in github registry and no auth token is provided" do
      let(:npm_fallback_version_above_v6_enabled) { false }
      let(:files) { project_dependency_files("npm/simple_with_github_with_no_auth_token") }

      let(:dependency_name) { "@Codertocat/hello-world-npm" }
      let(:version) { "1.1.0" }
      let(:requirements) { [] }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }
          .to raise_error(Dependabot::InvalidGitAuthToken) do |error|
          expect(error.message)
            .to eq(
              "Missing or invalid authentication token while accessing github package : " \
              "https://npm.pkg.github.com/@Codertocat%2fhello-world-npm"
            )
        end
      end
    end

    context "when there is a dep hosted in github registry and invalid auth token is provided" do
      let(:npm_fallback_version_above_v6_enabled) { false }
      let(:files) { project_dependency_files("npm/simple_with_github_with_invalid_auth_token") }

      let(:dependency_name) { "@Codertocat/hello-world-npm" }
      let(:version) { "1.1.0" }
      let(:requirements) { [] }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }
          .to raise_error(Dependabot::InvalidGitAuthToken) do |error|
          expect(error.message)
            .to eq(
              "Missing or invalid authentication token while accessing github package : " \
              "https://npm.pkg.github.com/@Codertocat%2fhello-world-npm"
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
        expect(parsed_lockfile.fetch("dependencies")["strict-uri-encode"]["version"])
          .to eq("1.1.0")
        expect(parsed_lockfile.fetch("dependencies")["bus-replacement-service"]["version"])
          .to include("19c4dba3bfce7574e28f1df2138d47ab4cc665b3")
      end
    end

    context "when the package current-name is not defined in package.json" do
      let(:files) { project_dependency_files("npm8/current_name_is_missing") }

      it "restores the packages name attribute" do
        parsed_lockfile = JSON.parse(updated_npm_lock_content)
        expected_updated_npm_lock_content = fixture(
          "updated_projects",
          "npm8",
          "current_name_is_missing",
          "package-lock.json"
        )
        expected_parsed_lockfile = JSON.parse(expected_updated_npm_lock_content)

        expect(parsed_lockfile).to eq(expected_parsed_lockfile), "Differences found"
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

    context "with engines-strict and a version that won't work with Dependabot" do
      let(:files) { project_dependency_files("npm8/engines") }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
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
        expect(parsed_lockfile.dig("packages", "").key?("name")).to be(false)
      end
    end
  end

  context "when dealing with workspace with outdated deps not in root package.json" do
    let(:dependency_name) { "@swc/core" }
    let(:version) { "1.3.44" }
    let(:previous_version) { "1.3.40" }
    let(:requirements) do
      [{
        file: "packages/bump-version-for-cron/package.json",
        requirement: "^1.3.37",
        groups: ["dependencies"],
        source: nil
      }]
    end
    let(:previous_requirements) { requirements }

    let(:files) { project_dependency_files("npm8/workspace_outdated_deps_not_in_root_package_json") }

    it "updates" do
      expect(JSON.parse(updated_npm_lock_content)["packages"]["node_modules/@swc/core"]["version"])
        .to eq("1.3.44")
    end
  end

  context "with a registry that times out" do
    registry_source = "https://registry.npm.com"
    let(:files) { project_dependency_files("npm/simple_with_registry_that_times_out") }
    let(:error) { Dependabot::PrivateSourceTimedOut.new(registry_source) }

    it "raises a helpful error" do
      expect(error.source).to eq(registry_source)
      expect(error.message).to eq("The following source timed out: " + registry_source)
    end
  end

  %w(npm6 npm8).each do |npm_version|
    describe "#{npm_version} updates" do
      let(:npm_fallback_version_above_v6_enabled) { false } if npm_version == "npm6"
      let(:files) { project_dependency_files("#{npm_version}/simple") }

      it "has details of the updated item" do
        parsed_lockfile = JSON.parse(updated_npm_lock_content)
        expect(parsed_lockfile["dependencies"]["fetch-factory"]["version"])
          .to eq("0.0.2")
      end

      context "when the requirement has not been updated" do
        let(:requirements) { previous_requirements }

        it "has details of the updated item" do
          parsed_lockfile = JSON.parse(updated_npm_lock_content)
          expect(parsed_lockfile["dependencies"]["fetch-factory"]["version"])
            .to eq("0.0.2")

          expect(
            parsed_lockfile.dig(
              "dependencies", "fetch-factory", "requires", "es6-promise"
            )
          ).to eq("^3.0.2")
        end
      end

      context "when dealing with git sub-dependency with invalid from" do
        let(:files) { project_dependency_files("#{npm_version}/git_sub_dep_invalid_from") }

        it "cleans up from field and successfully updates" do
          expect(JSON.parse(updated_npm_lock_content)["dependencies"]["fetch-factory"]["version"])
            .to eq("0.0.2")
        end
      end

      context "when updating both top level and sub dependencies" do
        let(:files) do
          project_dependency_files("#{npm_version}/transitive_dependency_locked_by_intermediate_top_and_sub")
        end
        let(:dependencies) do
          [
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-transitive-dependency",
              version: "1.0.1",
              previous_version: "1.0.0",
              requirements: [{
                file: "package.json",
                requirement: "1.0.1",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              previous_requirements: [{
                file: "package.json",
                requirement: "1.0.0",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  url: "https://registry.npmjs.org"
                }
              }],
              package_manager: "npm_and_yarn"
            ),
            Dependabot::Dependency.new(
              name: "@dependabot-fixtures/npm-intermediate-dependency",
              version: "0.0.2",
              previous_version: "0.0.1",
              requirements: [],
              previous_requirements: [],
              package_manager: "npm_and_yarn"
            )
          ]
        end

        it "updates top level and sub dependencies" do
          expected_updated_npm_lock_content = fixture(
            "updated_projects",
            npm_version,
            "transitive_dependency_locked_by_intermediate_top_and_sub",
            "package-lock.json"
          )
          expect(updated_npm_lock_content).to eq(expected_updated_npm_lock_content)
        end
      end
    end

    describe "#{npm_version} errors" do
      let(:npm_fallback_version_above_v6_enabled) { false } if npm_version == "npm6"
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
          expect { updated_npm_lock_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end

      context "with an invalid requirement in the package.json" do
        let(:files) { project_dependency_files("#{npm_version}/invalid_requirement") }

        it "raises a helpful error" do
          expect { updated_npm_lock_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end

      context "when updating to a nonexistent version" do
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
          expect { updated_npm_lock_content }
            .to raise_error(Dependabot::InconsistentRegistryResponse)
        end
      end

      context "with a dependency that can't be found" do
        let(:files) { project_dependency_files("#{npm_version}/nonexistent_dependency_yanked_version") }

        it "raises a helpful error" do
          expect { updated_npm_lock_content }
            .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
        end
      end

      context "with a git reference that Yarn would find but npm wouldn't" do
        let(:files) { project_dependency_files("#{npm_version}/git_dependency_yarn_ref") }

        it "raises a helpful error" do
          expect { updated_npm_lock_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable)
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
          expect { updated_npm_lock_content }
            .to raise_error(Dependabot::InconsistentRegistryResponse)
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
          expect { updated_npm_lock_content }
            .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
        end
      end

      context "with an invalid package name" do
        let(:files) { project_dependency_files("#{npm_version}/invalid_package_name") }
        let(:dependency_name) { "fetch-factory:" }

        it "raises a helpful error" do
          expect { updated_npm_lock_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable)
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
          expect { updated_npm_lock_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end
    end
  end

  context "with a private registry that is inaccessible due to auth" do
    let(:files) { project_dependency_files("npm/simple_with_registry_with_auth") }
    let(:npmrc_content) do
      { registry: "https://pkgs.dev.azure.com/example/npm/registry/" }
    end
    let(:error) { Dependabot::PrivateSourceAuthenticationFailure.new(npmrc_content[:registry]) }

    it "raises a helpful error" do
      expect(error.source).to eq(npmrc_content[:registry])
      expect(error.to_s).to include(npmrc_content[:registry])
    end
  end

  context "when updating a git source dependency that is not pinned to a hash" do
    subject(:parsed_lock_file) { JSON.parse(updated_npm_lock_content) }

    let(:npm_fallback_version_above_v6_enabled) { false }
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
      expect(parsed_lock_file["dependencies"]["npm6-dependency"]["version"])
        .to match(%r{github:dependabot-fixtures/npm6-dependency#[0-9a-z]{40}})
      expect(parsed_lock_file["dependencies"]["npm6-dependency"]["from"])
        .to eq("github:dependabot-fixtures/npm6-dependency")
    end
  end

  context "with a private registry that is inaccessible due to missing or invalid auth" do
    subject(:updated_npm_lock) { updater.updated_lockfile_reponse(exception) }

    let(:files) { project_dependency_files("npm/simple_with_registry_with_auth") }
    let(:exception) { Exception.new(response) }

    context "with a private registry that is missing .npmrc auth info" do
      let(:response) { "Unable to authenticate, need: Basic, Bearer" }

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a private registry that is inaccessible due to missing Basic auth info" do
      let(:response) { "Unable to authenticate, need: Basic realm=\"https://example.pkgs.visualstudio.com/\"" }

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a private registry that is inaccessible due to changed auth info" do
      let(:response) do
        "Unable to authenticate, need: Bearer authorization_uri=https://login.windows.net/....," \
          "Basic  realm=\"https://exs.app.pkg1.visualstudio.com/\", TFS-Federated"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a private registry that is inaccessible due to missing auth info" do
      let(:response) { "Unable to authenticate, need: BASIC realm=\"Repository Manager\"" }

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a dependency with no access and E401 error" do
      let(:response) do
        "npm WARN using --force Recommended protections disabled.
      npm ERR! code E401
      npm ERR! Incorrect or missing password.
      npm ERR! If you were trying to login, change your password, create an
      npm ERR! authentication token or enable two-factor authentication then
      npm ERR! that means you likely typed your password in incorrectly.
      npm ERR! Please try again, or recover your password at:
      npm ERR!     https://www.npmjs.com/forgot
      npm ERR!
      npm ERR! If you were doing some other operation then your saved credentials are
      npm ERR! probably out of date. To correct this please try logging in again with:
      npm ERR!     npm login

      npm ERR! A complete log of this run can be found in: /home/dependabot/.npm/_logs" \
      "/2024-07-30T08_39_47_480Z-debug-0.log"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.message)
            .to include(
              "The following source could not be reached as it requires authentication " \
              "(and any provided details were invalid or lacked the required permissions): www.npmjs.com"
            )
        end
      end
    end

    context "with a dependency with no access and E403 error" do
      let(:response) do
        "npm WARN using --force Recommended protections disabled.
      npm ERR! code E403
      npm ERR! 403 403 Forbidden - GET https://a0us.jfrog.io/a0us/api/npm/npm/execa
      npm ERR! 403 In most cases, you or one of your dependencies are requesting
      npm ERR! 403 a package version that is forbidden by your security policy, or
      npm ERR! 403 on a server you do not have access to.

      npm ERR! A complete log of this run can be found in: /home/dependabot/.npm/_logs" \
      "/2024-07-30T13_02_59_179Z-debug-0.log"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.message)
            .to include(
              "The following source could not be reached as it requires authentication (and " \
              "any provided details were invalid or lacked the required permissions): a0us.jfrog.io"
            )
        end
      end
    end

    context "with a dependency with no access and E403 error" do
      let(:response) do
        "https://artifactory3-eu1.moneysupermarket.com/artifactory/api/npm/npm-repo/@aws-sdk%2fclient-s3" \
          ": Request \"https://artifactory3-eu1.moneysupermarket.com/artifactory/" \
          "api/npm/npm-repo/@aws-sdk%2fclient-s3\" returned a 403"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.message)
            .to include(
              "The following source could not be reached as it requires authentication (and any provided" \
              " details were invalid or lacked the required permissions): artifactory3-eu1.moneysupermarket.com"
            )
        end
      end
    end

    context "with a registry with access that results in eai access code failure" do
      let(:response) do
        "\n. request to https://registry.npmjs.org/next failed, reason: " \
          "getaddrinfo EAI_AGAIN ."
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
          expect(error.message)
            .to include(
              "Network Error. Access to https://registry.npmjs.org/next failed"
            )
        end
      end
    end

    context "with a registry with access that results in socket hang up error" do
      let(:response) { "https://registry.npm.xyz.org/qs: socket hang up" }

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
          expect(error.message)
            .to include(
              "https://registry.npm.xyz.org/qs"
            )
        end
      end
    end

    context "with a registry with access that results in empty reply from server error" do
      let(:response) do
        "Error while executing:
      /home/dependabot/bin/git ls-remote -h -t https://gitlab.dti.state.de.us/kpatel/sample-library

      fatal: unable to access 'https://gitlab.dti.state.de.us/kpatel/sample-library/': Empty reply from server

      exited with error code: 128"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
          expect(error.message)
            .to include(
              "https://gitlab.dti.state.de.us/kpatel/sample-library/"
            )
        end
      end
    end

    context "with a registry with access that results in empty reply from server error" do
      let(:response) { "https://npm.fontawesome.com/@fortawesome%2freact-fontawesome: authentication required" }

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.message)
            .to include(
              "The following source could not be reached as it requires authentication " \
              "(and any provided details were invalid or lacked the required permissions): " \
              "npm.fontawesome.com"
            )
        end
      end
    end

    context "with a registry with access that results in variation of socket hang up error" do
      let(:response) { "request to https://nexus.xyz.com/repository/npm-js/ejs failed,reason: socket hang up" }

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
          expect(error.message)
            .to include(
              "https://nexus.xyz.com/repository/npm-js/ejs"
            )
        end
      end
    end

    context "with a response with package not found error" do
      let(:response) do
        "Couldn't find package \"leemons-plugin-client-manager-frontend:" \
          "-react-private@1.0.0\" required by \"leemons-app@0.0.1\" on the \"npm\" registry."
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a response with package not found error" do
      let(:response) do
        "Couldn't find package \"animated\" on the \"npm\" registry."
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a response with EUNSUPPORTEDPROTOCOL error" do
      let(:response) do
        "npm WARN using --force Recommended protections disabled.
        npm ERR! code EUNSUPPORTEDPROTOCOL
        npm ERR! Unsupported URL Type \"link:\": link:dayjs/plugin/relativeTime"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a response with 500 Internal Server error" do
      let(:response) do
        "npm WARN using --force Recommended protections disabled.
        npm ERR! code E500
        npm ERR! 500 Internal Server Error - GET https://registry.npmjs.org/get-intrinsic"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a response with Unable to resolve reference error" do
      let(:response) do
        "npm WARN using --force Recommended protections disabled.
        npm ERR! Unable to resolve reference $eslint"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a registry with access that results in ESOCKETTIMEDOUT error" do
      let(:response) { "https://npm.pkg.github.com/@group%2ffe-release: ESOCKETTIMEDOUT" }

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
          expect(error.message)
            .to include(
              "https://npm.pkg.github.com/@group/fe-release"
            )
        end
      end
    end

    context "with a package.json file with invalid entry" do
      let(:response) { "premature close" }

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::DependencyFileNotParseable) do |error|
          expect(error.message)
            .to include(
              "Error parsing your package.json manifest"
            )
        end
      end
    end

    context "with a package-lock.json file with empty package object" do
      let(:response) { "Object for dependency \"anymatch\" is empty.\nSomething went wrong." }

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include(
              "Object for dependency \"anymatch\" is empty"
            )
        end
      end
    end

    context "with a npm error response that returns a git checkout error" do
      let(:response) do
        "Command failed: git checkout 8cb9036b503920679c95528fa584d3e973b64f75
      fatal: reference is not a tree: 8cb9036b503920679c95528fa584d3e973b64f75"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include(
              "Command failed: git checkout 8cb9036b503920679c95528fa584d3e973b64f75"
            )
        end
      end
    end

    context "with a npm error response that invalid version error" do
      let(:response) do
        "npm WARN using --force Recommended protections disabled.
        npm ERR! Invalid Version: ^8.0.1

        npm ERR! A complete log of this run can be found in: " \
        "/home/dependabot/.npm/_logs/2024-09-12T06_08_54_947Z-debug-0.log"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include(
              "Found invalid version \"^8.0.1\" while updating"
            )
        end
      end
    end
  end

  context "with a override that conflicts with direct dependency" do
    let(:files) { project_dependency_files("npm/simple_with_override") }
    let(:dependency_name) { "eslint" }
    let(:version) { "9.5.1" }
    let(:previous_version) { "^9.5.0" }
    let(:requirements) do
      [{
        file: "package.json",
        requirement: "^9.5.0",
        groups: ["devDependencies"],
        source: nil
      }]
    end
    let(:previous_requirements) { requirements }

    it "raises a helpful error" do
      expect { updated_npm_lock_content }.to raise_error(Dependabot::DependencyFileNotResolvable)
    end
  end

  context "with a registry package lookup that returns a 404" do
    let(:files) { project_dependency_files("npm/simple_with_no_access_registry") }
    let(:dependency_name) { "@gcorevideo/rtckit" }
    let(:version) { "3.3.1" }
    let(:previous_version) { "^3.3.0" }
    let(:requirements) do
      [{
        file: "package.json",
        requirement: "^3.3.0",
        groups: ["dependencies"],
        source: {
          type: "registry",
          url: "http://npmrepo.nl"
        }
      }]
    end
    let(:previous_requirements) { requirements }

    it "raises a helpful error" do
      expect { updated_npm_lock_content }.to raise_error(Dependabot::DependencyFileNotResolvable)
    end
  end

  context "with a dependency with nested aliases not supported" do
    let(:files) { project_dependency_files("npm/simple_with_nested_deps") }
    let(:dependency_name) { "express" }
    let(:version) { "4.19.2" }
    let(:previous_version) { "^4.17.1" }
    let(:requirements) do
      [{
        file: "package.json",
        requirement: "^4.17.1",
        groups: ["devDependencies"],
        source: nil
      }]
    end
    let(:previous_requirements) { requirements }

    context "when npm version is 6" do
      let(:npm_fallback_version_above_v6_enabled) { false }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when npm version is 8" do
      let(:npm_fallback_version_above_v6_enabled) { true }

      it "do not raises an error" do
        expect(updated_npm_lock_content).not_to be_nil
      end
    end
  end

  context "with a dependency with no access" do
    let(:files) { project_dependency_files("npm/simple_with_no_access") }
    let(:dependency_name) { "typescript" }
    let(:version) { "5.5.4" }
    let(:previous_version) { "^5.1.5" }
    let(:requirements) do
      [{
        file: "package.json",
        requirement: "^5.1.5",
        groups: ["devDependencies"],
        source: nil
      }]
    end
    let(:previous_requirements) { requirements }

    it "raises a helpful error" do
      expect { updated_npm_lock_content }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
    end
  end

  context "with a peer dependency that is unresolved" do
    let(:files) { project_dependency_files("npm/simple_with_peer_deps") }
    let(:dependency_name) { "eslint" }
    let(:version) { "9.8.0" }
    let(:previous_version) { "^8.43.0" }
    let(:requirements) do
      [{
        file: "package.json",
        requirement: "^8.43.0",
        groups: ["devDependencies"],
        source: nil
      }]
    end
    let(:previous_requirements) { requirements }

    it "raises a helpful error" do
      expect { updated_npm_lock_content }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
        expect(error.message)
          .to include(
            "Error while updating peer dependency."
          )
      end
    end
  end
end
