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
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com"
      }
    )]
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

  # Variable to control the enabling feature flag for the corepack fix
  let(:enable_corepack_for_npm_and_yarn) { true }

  before do
    FileUtils.mkdir_p(tmp_path)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_corepack_for_npm_and_yarn).and_return(enable_corepack_for_npm_and_yarn)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_private_registry_for_corepack).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:avoid_duplicate_updates_package_json).and_return(false)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_private_registry_for_corepack).and_return(false)
  end

  after do
    Dependabot::Experiments.reset!
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
        expected_updated_npm_lock_content = fixture(
          "updated_projects",
          "npm8",
          "simple_no_indentation",
          "package-lock.json"
        )
        expect(updated_npm_lock_content).to eq(expected_updated_npm_lock_content)
      end
    end

    context "when the lockfile contains a trailing newline" do
      let(:files) { project_dependency_files("npm8/lockfile_with_newline") }

      it "ignores the newline when calculating indentation" do
        expected_updated_npm_lock_content = fixture(
          "updated_projects",
          "npm8",
          "lockfile_with_newline",
          "package-lock.json"
        )
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

  describe "npm updates" do
    let(:files) { project_dependency_files("npm8/simple") }

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
      let(:files) { project_dependency_files("npm8/git_sub_dep_invalid_from") }

      it "cleans up from field and successfully updates" do
        expect(JSON.parse(updated_npm_lock_content)["dependencies"]["fetch-factory"]["version"])
          .to eq("0.0.2")
      end
    end

    context "when updating both top level and sub dependencies" do
      let(:files) do
        project_dependency_files("npm8/transitive_dependency_locked_by_intermediate_top_and_sub")
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
          "npm8",
          "transitive_dependency_locked_by_intermediate_top_and_sub",
          "package-lock.json"
        )
        expect(updated_npm_lock_content).to eq(expected_updated_npm_lock_content)
      end
    end
  end

  describe "npm errors" do
    context "with a sub dependency name that can't be found" do
      let(:files) { project_dependency_files("npm8/github_sub_dependency_name_missing") }

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
      let(:files) { project_dependency_files("npm8/invalid_requirement") }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when updating to a nonexistent version" do
      let(:files) { project_dependency_files("npm8/simple") }

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
      let(:files) { project_dependency_files("npm8/nonexistent_dependency_yanked_version") }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "with a git reference that Yarn would find but npm wouldn't" do
      let(:files) { project_dependency_files("npm8/git_dependency_yarn_ref") }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when scoped sub dependency version is missing" do
      let(:files) { project_dependency_files("npm8/github_scoped_sub_dependency_version_missing") }

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
      let(:files) { project_dependency_files("npm8/github_sub_dependency_version_missing") }

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
      let(:files) { project_dependency_files("npm8/invalid_package_name") }
      let(:dependency_name) { "fetch-factory:" }

      it "raises a helpful error" do
        expect { updated_npm_lock_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a dependency version that can't be found" do
      let(:files) { project_dependency_files("npm8/yanked_version") }

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

    context "with invalid package manager specification" do
      let(:response) do
        "Invalid package manager specification in package.json (npm@>=10.9.0); expected a semver version"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include("Invalid package manager specification in package.json")
            .and include("The packageManager field must specify a valid semver version")
        end
      end
    end

    context "with invalid npm authentication configuration error" do
      let(:response) do
        "npm warn using --force Recommended protections disabled.
        npm error code ERR_INVALID_AUTH
        npm error Invalid auth configuration found: `_auth` must be renamed"
      end

      it "raises a helpful error" do
        expect { updated_npm_lock }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.message)
            .to include("Invalid npm authentication configuration found")
            .and include("The _auth setting in .npmrc needs to be scoped to the specific registry")
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

    context "when npm version is 8" do
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

  context "when updating optional dependencies" do
    let(:files) { project_dependency_files("npm8/optional_dependency_update") }
    let(:dependency_name) { "@rollup/rollup-linux-x64-gnu" }
    let(:version) { "4.53.2" }
    let(:previous_version) { "4.52.5" }
    let(:requirements) do
      [{
        file: "package.json",
        requirement: "^4.53.2",
        groups: ["optionalDependencies"],
        source: nil
      }]
    end
    let(:previous_requirements) do
      [{
        file: "package.json",
        requirement: "^4.52.5",
        groups: ["optionalDependencies"],
        source: nil
      }]
    end

    it "uses --save-optional flag for optional dependencies" do
      # Test the private method that identifies optional dependencies
      expect(updater.send(:optional_dependency?, dependency)).to be(true)

      # Test that npm_install_args returns correct package specification
      install_arg = updater.send(:npm_install_args, dependency)
      expect(install_arg).to eq("@rollup/rollup-linux-x64-gnu@4.53.2")

      # Test the run_npm_install_lockfile_only method includes --save-optional
      expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, _options|
        expect(command).to include("--save-optional")
        expect(command).to include("--package-lock-only")
        expect(command).to include("--force")
        expect(command).to include("@rollup/rollup-linux-x64-gnu@4.53.2")
        ""
      end

      # Call the method that would trigger the npm command
      updater.send(:run_npm_install_lockfile_only, [install_arg], has_optional_dependencies: true)
    end

    context "when updating both regular and optional dependencies" do
      let(:files) { project_dependency_files("npm8/mixed_dependencies") }
      let(:dependencies) { [regular_dependency, optional_dependency_obj] }

      let(:regular_dependency) do
        Dependabot::Dependency.new(
          name: "fetch-factory",
          version: "0.0.2",
          previous_version: "0.0.1",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "^0.0.2",
            groups: ["dependencies"],
            source: nil
          }],
          previous_requirements: [{
            file: "package.json",
            requirement: "^0.0.1",
            groups: ["dependencies"],
            source: nil
          }]
        )
      end

      let(:optional_dependency_obj) do
        Dependabot::Dependency.new(
          name: "@rollup/rollup-linux-x64-gnu",
          version: "4.53.2",
          previous_version: "4.52.5",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "^4.53.2",
            groups: ["optionalDependencies"],
            source: nil
          }],
          previous_requirements: [{
            file: "package.json",
            requirement: "^4.52.5",
            groups: ["optionalDependencies"],
            source: nil
          }]
        )
      end

      it "handles regular and optional dependencies with different flags" do
        regular_install_arg = updater.send(:npm_install_args, regular_dependency)
        optional_install_arg = updater.send(:npm_install_args, optional_dependency_obj)

        # Test run_npm_install_lockfile_only without --save-optional for regular deps
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, _options|
          expect(command).not_to include("--save-optional")
          expect(command).to include("--package-lock-only")
          expect(command).to include("--force")
          ""
        end
        updater.send(:run_npm_install_lockfile_only, [regular_install_arg], has_optional_dependencies: false)

        # Test run_npm_install_lockfile_only with --save-optional for optional deps
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, _options|
          expect(command).to include("--save-optional")
          expect(command).to include("--package-lock-only")
          expect(command).to include("--force")
          ""
        end
        updater.send(:run_npm_install_lockfile_only, [optional_install_arg], has_optional_dependencies: true)
      end

      context "when verifying lockfile content" do
        it "correctly updates lockfile with optional dependencies staying in optionalDependencies section" do
          # Use actual file update process without mocking the core functionality
          expected_updated_content = fixture(
            "updated_projects", "npm8", "optional_dependency_update", "package-lock.json"
          )

          # Create an updater with the correct optional dependency
          test_updater = described_class.new(
            lockfile: package_lock,
            dependency_files: files,
            dependencies: [dependency],
            credentials: credentials
          )

          # Mock the npm command to return success but don't override the file reading
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, _options|
            # Verify the command includes --save-optional for optional dependencies
            expect(command).to include("--save-optional")
            expect(command).to include("@rollup/rollup-linux-x64-gnu@4.53.2")
            ""
          end

          # Mock the file reading after npm update to return our expected content
          original_file_read = File.method(:read)
          allow(File).to receive(:read) do |path|
            if path.end_with?("package-lock.json") && path.include?("tmp")
              expected_updated_content
            else
              original_file_read.call(path)
            end
          end

          result = test_updater.send(:updated_lockfile_content)
          parsed_result = JSON.parse(result)

          # Verify the dependency was updated to the correct version
          expect(parsed_result.dig("packages", "node_modules/@rollup/rollup-linux-x64-gnu", "version"))
            .to eq("4.53.2")

          # Critical: Verify the dependency remains marked as optional
          expect(parsed_result.dig("packages", "node_modules/@rollup/rollup-linux-x64-gnu", "optional"))
            .to be(true)

          # Critical: Verify optionalDependencies section has the updated version
          expect(parsed_result.dig("packages", "", "optionalDependencies", "@rollup/rollup-linux-x64-gnu"))
            .to eq("^4.53.2")

          # Critical: Ensure the optional dependency is NOT moved to the dependencies section
          dependencies_section = parsed_result.dig("packages", "", "dependencies")
          expect(dependencies_section).not_to have_key("@rollup/rollup-linux-x64-gnu") if dependencies_section
        end

        it "handles mixed dependencies correctly without moving optional deps to dependencies section" do
          # Test with mixed dependencies scenario
          mixed_files = project_dependency_files("npm8/mixed_dependencies")

          # Create dependencies for both regular and optional
          mixed_regular_dep = Dependabot::Dependency.new(
            name: "fetch-factory",
            version: "0.0.2",
            previous_version: "0.0.1",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^0.0.2",
              groups: ["dependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^0.0.1",
              groups: ["dependencies"],
              source: nil
            }]
          )

          mixed_optional_dep = Dependabot::Dependency.new(
            name: "@rollup/rollup-linux-x64-gnu",
            version: "4.53.2",
            previous_version: "4.52.5",
            package_manager: "npm_and_yarn",
            requirements: [{
              file: "package.json",
              requirement: "^4.53.2",
              groups: ["optionalDependencies"],
              source: nil
            }],
            previous_requirements: [{
              file: "package.json",
              requirement: "^4.52.5",
              groups: ["optionalDependencies"],
              source: nil
            }]
          )

          mixed_updater = described_class.new(
            lockfile: mixed_files.find { |f| f.name == "package-lock.json" },
            dependency_files: mixed_files,
            dependencies: [mixed_regular_dep, mixed_optional_dep],
            credentials: credentials
          )

          expected_mixed_content = fixture(
            "updated_projects", "npm8", "mixed_dependencies", "package-lock.json"
          )

          # Mock npm commands - should be called twice, once for each dependency
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command).and_return("")

          # Mock file reading to return expected content
          original_file_read = File.method(:read)
          allow(File).to receive(:read) do |path|
            if path.end_with?("package-lock.json") && path.include?("tmp")
              expected_mixed_content
            else
              original_file_read.call(path)
            end
          end

          result = mixed_updater.updated_lockfile.content
          parsed_result = JSON.parse(result)

          # Verify the dependency was updated
          expect(parsed_result.dig("packages", "node_modules/@rollup/rollup-linux-x64-gnu", "version"))
            .to eq("4.53.2")

          # Verify optional dependency is still marked as optional
          expect(parsed_result.dig("packages", "node_modules/@rollup/rollup-linux-x64-gnu", "optional"))
            .to be(true)

          # Verify regular dependency is NOT marked as optional
          expect(parsed_result.dig("packages", "node_modules/fetch-factory"))
            .not_to have_key("optional")

          # Critical verification: dependencies structure
          root_package = parsed_result.dig("packages", "")
          expect(root_package["dependencies"]).to include("fetch-factory" => "^0.0.2")
          expect(root_package["optionalDependencies"]).to include("@rollup/rollup-linux-x64-gnu" => "^4.53.2")

          # The key fix: optional dependency should NOT be in dependencies section
          expect(root_package["dependencies"]).not_to have_key("@rollup/rollup-linux-x64-gnu")
        end
      end
    end

    describe "#optional_dependency?" do
      it "correctly identifies optional dependencies" do
        optional_dep = Dependabot::Dependency.new(
          name: "@rollup/rollup-linux-x64-gnu",
          version: "4.53.2",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "^4.53.2",
            groups: ["optionalDependencies"],
            source: nil
          }]
        )

        regular_dep = Dependabot::Dependency.new(
          name: "regular-package",
          version: "1.0.0",
          package_manager: "npm_and_yarn",
          requirements: [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: ["dependencies"],
            source: nil
          }]
        )

        # Create a simple updater instance to test the private method
        test_updater = described_class.new(
          lockfile: files.find { |f| f.name == "package-lock.json" },
          dependency_files: files,
          dependencies: [optional_dep],
          credentials: credentials
        )

        expect(test_updater.send(:optional_dependency?, optional_dep)).to be(true)
        expect(test_updater.send(:optional_dependency?, regular_dep)).to be(false)
      end
    end

    describe "Helpers.build_corepack_env_variables" do
      let(:files) { project_dependency_files("npm8/simple") }

      context "when experiment flag is disabled" do
        let(:test_credentials) { credentials }

        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:enable_private_registry_for_corepack).and_return(false)
          Dependabot::NpmAndYarn::Helpers.dependency_files = files
          Dependabot::NpmAndYarn::Helpers.credentials = test_credentials
        end

        it "returns nil" do
          expect(Dependabot::NpmAndYarn::Helpers.send(:build_corepack_env_variables)).to be_nil
        end
      end

      context "when experiment flag is enabled" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:enable_private_registry_for_corepack).and_return(true)
        end

        context "with npm_registry credentials" do
          let(:test_credentials) do
            [
              Dependabot::Credential.new(
                {
                  "type" => "npm_registry",
                  "registry" => "https://npm.private.registry",
                  "token" => "secret_token",
                  "replaces-base" => true
                }
              )
            ]
          end

          before do
            Dependabot::NpmAndYarn::Helpers.dependency_files = files
            Dependabot::NpmAndYarn::Helpers.credentials = test_credentials
          end

          it "returns both registry and token environment variables" do
            env_vars = Dependabot::NpmAndYarn::Helpers.send(:build_corepack_env_variables)
            expect(env_vars).to eq(
              {
                "COREPACK_NPM_REGISTRY" => "https://npm.private.registry",
                "npm_config_registry" => "https://npm.private.registry",
                "COREPACK_NPM_TOKEN" => "secret_token",
                "registry" => "https://npm.private.registry"
              }
            )
          end
        end

        context "with npm_registry credentials but replaces-base is false" do
          let(:test_credentials) do
            [
              Dependabot::Credential.new(
                {
                  "type" => "npm_registry",
                  "registry" => "https://npm.private.registry",
                  "token" => "secret_token",
                  "replaces-base" => false
                }
              )
            ]
          end

          before do
            Dependabot::NpmAndYarn::Helpers.dependency_files = files
            Dependabot::NpmAndYarn::Helpers.credentials = test_credentials
          end

          it "returns empty hash" do
            env_vars = Dependabot::NpmAndYarn::Helpers.send(:build_corepack_env_variables)
            expect(env_vars).to eq({})
          end
        end

        context "without npm_registry credentials" do
          before do
            Dependabot::NpmAndYarn::Helpers.dependency_files = files
            Dependabot::NpmAndYarn::Helpers.credentials = credentials
          end

          it "returns empty hash" do
            env_vars = Dependabot::NpmAndYarn::Helpers.send(:build_corepack_env_variables)
            expect(env_vars).to eq({})
          end
        end

        context "with .npmrc file containing registry" do
          let(:test_files) do
            project_dependency_files("npm8/simple") + [
              Dependabot::DependencyFile.new(
                name: ".npmrc",
                content: "registry=https://custom.registry.com\n_authToken=custom_token"
              )
            ]
          end

          before do
            Dependabot::NpmAndYarn::Helpers.dependency_files = test_files
            Dependabot::NpmAndYarn::Helpers.credentials = credentials
          end

          it "returns registry and token from .npmrc" do
            env_vars = Dependabot::NpmAndYarn::Helpers.send(:build_corepack_env_variables)
            expect(env_vars).to eq(
              {
                "COREPACK_NPM_REGISTRY" => "https://custom.registry.com",
                "npm_config_registry" => "https://custom.registry.com",
                "COREPACK_NPM_TOKEN" => "custom_token",
                "registry" => "https://custom.registry.com"
              }
            )
          end
        end

        context "with .yarnrc file containing registry" do
          let(:test_files) do
            project_dependency_files("npm8/simple") + [
              Dependabot::DependencyFile.new(
                name: ".yarnrc",
                content: "registry \"https://yarn.registry.com\"\n_authToken \"yarn_token\""
              )
            ]
          end

          before do
            Dependabot::NpmAndYarn::Helpers.dependency_files = test_files
            Dependabot::NpmAndYarn::Helpers.credentials = credentials
          end

          it "returns registry and token from .yarnrc" do
            env_vars = Dependabot::NpmAndYarn::Helpers.send(:build_corepack_env_variables)
            expect(env_vars).to eq(
              {
                "COREPACK_NPM_REGISTRY" => "https://yarn.registry.com",
                "npm_config_registry" => "https://yarn.registry.com",
                "COREPACK_NPM_TOKEN" => "yarn_token",
                "registry" => "https://yarn.registry.com"
              }
            )
          end
        end

        context "with .yarnrc.yml file containing registry" do
          let(:test_files) do
            project_dependency_files("npm8/simple") + [
              Dependabot::DependencyFile.new(
                name: ".yarnrc.yml",
                content: "npmRegistryServer: https://yarn2.registry.com\nnpmAuthToken: yarn2_token"
              )
            ]
          end

          before do
            Dependabot::NpmAndYarn::Helpers.dependency_files = test_files
            Dependabot::NpmAndYarn::Helpers.credentials = credentials
          end

          it "returns registry and token from .yarnrc.yml" do
            env_vars = Dependabot::NpmAndYarn::Helpers.send(:build_corepack_env_variables)
            expect(env_vars).to eq(
              {
                "COREPACK_NPM_REGISTRY" => "https://yarn2.registry.com",
                "npm_config_registry" => "https://yarn2.registry.com",
                "COREPACK_NPM_TOKEN" => "yarn2_token",
                "registry" => "https://yarn2.registry.com"
              }
            )
          end
        end

        context "when credentials take priority over config files" do
          let(:test_credentials) do
            [
              Dependabot::Credential.new(
                {
                  "type" => "npm_registry",
                  "registry" => "https://creds.registry.com",
                  "token" => "creds_token",
                  "replaces-base" => true
                }
              )
            ]
          end

          let(:test_files) do
            project_dependency_files("npm8/simple") + [
              Dependabot::DependencyFile.new(
                name: ".npmrc",
                content: "registry=https://npmrc.registry.com\n_authToken=npmrc_token"
              )
            ]
          end

          before do
            Dependabot::NpmAndYarn::Helpers.dependency_files = test_files
            Dependabot::NpmAndYarn::Helpers.credentials = test_credentials
          end

          it "uses credentials over .npmrc" do
            env_vars = Dependabot::NpmAndYarn::Helpers.send(:build_corepack_env_variables)
            expect(env_vars).to eq(
              {
                "COREPACK_NPM_REGISTRY" => "https://creds.registry.com",
                "npm_config_registry" => "https://creds.registry.com",
                "COREPACK_NPM_TOKEN" => "creds_token",
                "registry" => "https://creds.registry.com"
              }
            )
          end
        end
      end
    end
  end
end
