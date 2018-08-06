# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/php/composer/lockfile_updater"

RSpec.describe Dependabot::FileUpdaters::Php::Composer::LockfileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
    )
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:files) { [composer_json, lockfile] }
  let(:composer_json) do
    Dependabot::DependencyFile.new(
      name: "composer.json",
      content: fixture("php", "composer_files", manifest_fixture_name)
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "composer.lock",
      content: fixture("php", "lockfiles", lockfile_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "exact_version" }
  let(:lockfile_fixture_name) { "exact_version" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "monolog/monolog",
      version: "1.22.1",
      requirements: requirements,
      previous_version: "1.0.1",
      previous_requirements: previous_requirements,
      package_manager: "composer"
    )
  end
  let(:requirements) do
    [{
      file: "composer.json",
      requirement: "1.22.1",
      groups: [],
      source: nil
    }]
  end
  let(:previous_requirements) do
    [{
      file: "composer.json",
      requirement: "1.0.1",
      groups: [],
      source: nil
    }]
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "the updated lockfile" do
    subject(:updated_lockfile_content) do
      raw = updater.updated_lockfile_content
      JSON.parse(raw).to_json
    end

    it "has details of the updated item" do
      expect(updated_lockfile_content).to include("\"version\":\"1.22.1\"")
    end

    it { is_expected.to include "\"prefer-stable\":false" }

    context "when an old version of PHP is specified" do
      context "as a platform requirement" do
        let(:manifest_fixture_name) { "old_php_platform" }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "illuminate/support",
            version: "5.4.36",
            requirements: [{
              file: "composer.json",
              requirement: "^5.2.0",
              groups: ["runtime"],
              source: nil
            }],
            previous_version: "5.2.7",
            previous_requirements: [{
              file: "composer.json",
              requirement: "^5.2.0",
              groups: ["runtime"],
              source: nil
            }],
            package_manager: "composer"
          )
        end

        it "has details of the updated item" do
          expect(updated_lockfile_content).
            to include("\"version\":\"v5.4.36\"")
        end
      end
    end

    context "with a plugin that would cause errors" do
      let(:manifest_fixture_name) { "plugin" }
      let(:lockfile_fixture_name) { "plugin" }

      it "has details of the updated item" do
        expect(updated_lockfile_content).to include("\"version\":\"1.22.1\"")
      end
    end

    context "with a plugin that conflicts with the current composer version" do
      let(:manifest_fixture_name) { "outdated_flex" }
      let(:lockfile_fixture_name) { "outdated_flex" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "symphony/lock",
          version: "4.1.3",
          requirements: [{
            file: "composer.json",
            requirement: "^4.1",
            groups: ["runtime"],
            source: nil
          }],
          previous_version: "4.1.1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "^4.1",
            groups: ["runtime"],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "raises a helpful error" do
        expect { updated_lockfile_content }.to raise_error do |error|
          expect(error).to be_a Dependabot::DependencyFileNotResolvable
          expect(error.message).to start_with("One of your Composer plugins")
        end
      end
    end

    context "that requires an environment variable" do
      let(:manifest_fixture_name) { "env_variable" }

      context "that hasn't been provided" do
        it "raises a MissingEnvironmentVariable error" do
          expect { updated_lockfile_content }.to raise_error do |error|
            expect(error).to be_a(Dependabot::MissingEnvironmentVariable)
            expect(error.environment_variable).to eq("ACF_PRO_KEY")
          end
        end
      end

      context "that has been provided" do
        let(:updater) do
          described_class.new(
            dependency_files: files,
            dependencies: [dependency],
            credentials: [
              {
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              },
              {
                "type" => "php_environment_variable",
                "env-key" => "ACF_PRO_KEY",
                "env-value" => "example_key"
              }
            ]
          )
        end

        it "runs just fine (we get a 400 here because our key is wrong)" do
          expect { updated_lockfile_content }.to raise_error do |error|
            expect(error).
              to be_a(Dependabot::SharedHelpers::HelperSubprocessFailed)
            expect(error.message).to include("400 Bad Request")
          end
        end
      end
    end

    context "with a path source" do
      let(:files) { [composer_json, lockfile, path_dep] }
      let(:manifest_fixture_name) { "path_source" }
      let(:lockfile_fixture_name) { "path_source" }
      let(:path_dep) do
        Dependabot::DependencyFile.new(
          name: "components/path_dep/composer.json",
          content: fixture("php", "composer_files", "path_dep")
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/monolog",
          version: "1.22.1",
          requirements: [{
            file: "composer.json",
            requirement: "1.22.*",
            groups: [],
            source: nil
          }],
          previous_version: "1.0.1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.*",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "has details of the updated item" do
        expect(updated_lockfile_content).to include("\"version\":\"1.22.1\"")
      end
    end

    context "when the new version is covered by the old requirements" do
      let(:manifest_fixture_name) { "minor_version" }
      let(:lockfile_fixture_name) { "covered_version" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/monolog",
          version: "1.0.2",
          requirements: [{
            file: "composer.json",
            requirement: "1.0.*",
            groups: [],
            source: nil
          }],
          previous_version: "1.0.0",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.*",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "has details of the updated item" do
        updated_dep = JSON.parse(updated_lockfile_content).
                      fetch("packages").
                      find { |p| p["name"] == "monolog/monolog" }

        expect(updated_dep.fetch("version")).to eq("1.0.2")
      end
    end

    context "when the dependency is a development dependency" do
      let(:manifest_fixture_name) { "development_dependencies" }
      let(:lockfile_fixture_name) { "development_dependencies" }

      it "has details of the updated item" do
        expect(updated_lockfile_content).to include("\"version\":\"1.22.1\"")
      end
    end

    context "when the dependency is a subdependency" do
      let(:manifest_fixture_name) { "subdependency_update_required" }
      let(:lockfile_fixture_name) { "subdependency_update_required" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "illuminate/contracts",
          version: "5.2.45",
          previous_version: "5.2.37",
          requirements: [],
          previous_requirements: [],
          package_manager: "composer"
        )
      end

      it "has details of the updated item" do
        expect(updated_lockfile_content).to include("\"version\":\"v5.2.45\"")
        expect(updated_lockfile_content).
          to include("22bde7b048a33c702d9737fc1446234fff9b1363")
      end
    end

    context "with a private registry" do
      let(:manifest_fixture_name) { "private_registry" }
      let(:lockfile_fixture_name) { "private_registry" }
      before { `composer clear-cache --quiet` }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "dependabot/dummy-pkg-a",
          version: "2.2.0",
          previous_version: "2.1.0",
          requirements: [{
            file: "composer.json",
            requirement: "*",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "composer.json",
            requirement: "*",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      context "with good credentials" do
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "type" => "composer_repository",
              "registry" => "php.fury.io",
              "username" => "yFu9PBmw1HxNjFB818TW", # Throwaway account
              "password" => ""
            }
          ]
        end

        it "has details of the updated item" do
          expect(updated_lockfile_content).to include("\"version\":\"2.2.0\"")
        end
      end
    end

    context "when another dependency has git source with a bad reference" do
      let(:lockfile_fixture_name) { "git_source_bad_ref" }
      let(:manifest_fixture_name) { "git_source_bad_ref" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "symfony/polyfill-mbstring",
          version: "1.6.0",
          requirements: [{
            file: "composer.json",
            requirement: "1.6.0",
            groups: [],
            source: nil
          }],
          previous_version: "1.0.1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.1",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "raises a helpful errors" do
        expect { updated_lockfile_content }.to raise_error do |error|
          expect(error).to be_a Dependabot::GitDependencyReferenceNotFound
          expect(error.dependency).to eq("monolog/monolog")
        end
      end
    end

    context "with a git source using no-api" do
      let(:manifest_fixture_name) { "git_source_no_api" }
      let(:lockfile_fixture_name) { "git_source_no_api" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "symfony/polyfill-mbstring",
          version: "1.6.0",
          requirements: [{
            file: "composer.json",
            requirement: "1.6.0",
            groups: [],
            source: nil
          }],
          previous_version: "1.0.1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.1",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it { is_expected.to_not include('"support": {') }
    end

    context "when another dependency has an unreachable git source" do
      let(:lockfile_fixture_name) { "git_source_unreachable" }
      let(:manifest_fixture_name) { "git_source_unreachable" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "symfony/polyfill-mbstring",
          version: "1.6.0",
          requirements: [{
            file: "composer.json",
            requirement: "1.6.0",
            groups: [],
            source: nil
          }],
          previous_version: "1.0.1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.1",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "raises a helpful errors" do
        expect { updated_lockfile_content }.to raise_error do |error|
          expect(error).to be_a Dependabot::GitDependenciesNotReachable
          expect(error.dependency_urls).
            to eq(["https://github.com/no-exist-sorry/monolog.git"])
        end
      end
    end

    context "when there are patches" do
      let(:manifest_fixture_name) { "patches" }
      let(:lockfile_fixture_name) { "patches" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ehime/hello-world",
          version: "1.0.5",
          requirements: [{
            file: "composer.json",
            requirement: "1.0.5",
            groups: [],
            source: nil
          }],
          previous_version: "1.0.4",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.4",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "doesn't strip the patches" do
        updated_dep = JSON.parse(updated_lockfile_content).
                      fetch("packages").
                      find { |p| p["name"] == "ehime/hello-world" }

        expect(updated_dep.dig("extra", "patches_applied")).
          to include("[PATCH] markdown modified")
      end
    end

    context "regression spec for media-organizer" do
      let(:manifest_fixture_name) { "media_organizer" }
      let(:lockfile_fixture_name) { "media_organizer" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/monolog",
          version: "1.23.0",
          requirements: [{
            file: "composer.json",
            requirement: "~1.0",
            groups: [],
            source: nil
          }],
          previous_version: "1.20.0",
          previous_requirements: [{
            file: "composer.json",
            requirement: "~1.0",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "has details of the updated item" do
        updated_dep = JSON.parse(updated_lockfile_content).
                      fetch("packages-dev").
                      find { |p| p["name"] == "monolog/monolog" }

        expect(Gem::Version.new(updated_dep.fetch("version"))).
          to be >= Gem::Version.new("1.23.0")
      end
    end

    context "when a subdependency needs to be updated" do
      let(:manifest_fixture_name) { "subdependency_update_required" }
      let(:lockfile_fixture_name) { "subdependency_update_required" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "illuminate/support",
          version: "5.6.23",
          requirements: [{
            file: "composer.json",
            requirement: "^5.6.23",
            groups: ["runtime"],
            source: nil
          }],
          previous_version: "5.2.0",
          previous_requirements: [{
            file: "composer.json",
            requirement: "^5.2.0",
            groups: ["runtime"],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "has details of the updated item" do
        expect(updated_lockfile_content).to include("\"version\":\"v5.6.23\"")
        expect(updated_lockfile_content).
          to include("ba383d0a3bf6aa0b7a1307fdc4aa46ba")
      end
    end

    context "updating to a specific version when reqs would allow higher" do
      let(:manifest_fixture_name) { "subdependency_update_required" }
      let(:lockfile_fixture_name) { "subdependency_update_required" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "illuminate/support",
          version: "5.3.0",
          requirements: [{
            file: "composer.json",
            requirement: "^5.2.0",
            groups: ["runtime"],
            source: nil
          }],
          previous_version: "5.2.0",
          previous_requirements: [{
            file: "composer.json",
            requirement: "^5.2.0",
            groups: ["runtime"],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "has details of the updated item" do
        expect(updated_lockfile_content).to include("\"version\":\"v5.3.0\"")
        expect(updated_lockfile_content).
          to include("e244eda135819216ac30441464e27d4d")
      end
    end
  end
end
