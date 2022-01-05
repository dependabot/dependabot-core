# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/composer/file_updater/lockfile_updater"

RSpec.describe Dependabot::Composer::FileUpdater::LockfileUpdater do
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
  let(:files) { project_dependency_files(project_name) }
  let(:project_name) { "exact_version" }

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
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

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
        let(:project_name) { "old_php_platform" }
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
          expect(updated_lockfile_content).to include("\"version\":\"v5.4.36\"")
        end
      end

      context "with an application using a >= PHP constraint" do
        let(:project_name) { "php_specified" }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "phpdocumentor/reflection-docblock",
            version: "4.3.1",
            requirements: [{
              file: "composer.json",
              requirement: "4.3.1",
              groups: ["runtime"],
              source: nil
            }],
            previous_version: "2.0.4",
            previous_requirements: [{
              file: "composer.json",
              requirement: "2.0.4",
              groups: ["runtime"],
              source: nil
            }],
            package_manager: "composer"
          )
        end

        it "has details of the updated item" do
          expect(updated_lockfile_content).to include("\"version\":\"4.3.1\"")
        end
      end

      context "with an application using a ^ PHP constraint" do
        let(:project_name) { "php_specified_min_invalid" }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "phpdocumentor/reflection-docblock",
            version: "3.3.2",
            requirements: [{
              file: "composer.json",
              requirement: "3.3.2",
              groups: ["runtime"],
              source: nil
            }],
            previous_version: "2.0.4",
            previous_requirements: [{
              file: "composer.json",
              requirement: "2.0.4",
              groups: ["runtime"],
              source: nil
            }],
            package_manager: "composer"
          )
        end

        it "has details of the updated item" do
          expect(updated_lockfile_content).to include("\"version\":\"3.3.2\"")
        end
      end

      context "and an extension is specified that we don't have" do
        let(:project_name) { "missing_extension" }
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
          expect(updated_lockfile_content).to include("\"version\":\"v5.4.36\"")
          expect(updated_lockfile_content).
            to include("\"platform-overrides\":{\"php\":\"5.6.4\"}")
        end
      end
    end

    context "with a plugin that would cause errors (composer v1)" do
      let(:project_name) { "v1/plugin" }

      it "has details of the updated item" do
        expect(updated_lockfile_content).to include("\"version\":\"1.22.1\"")
      end
    end

    context "with a plugin that would cause errors (composer v2)" do
      let(:project_name) { "plugin" }

      it "raises a helpful error" do
        expect { updated_lockfile_content }.to raise_error do |error|
          expect(error.message).to include("Your requirements could not be resolved to an installable set of packages.")
          expect(error.message).to include("requires composer-plugin-api ^1.0 -> found composer-plugin-api[2.")
          expect(error).to be_a Dependabot::DependencyFileNotResolvable
        end
      end
    end

    context "with a plugin that conflicts with the current composer version v1" do
      let(:project_name) { "v1/outdated_flex" }
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
          expect(error.message).to start_with("One of your Composer plugins is not compatible")
          expect(error).to be_a Dependabot::DependencyFileNotResolvable
        end
      end
    end

    context "with a plugin that conflicts with the current composer version v2" do
      let(:project_name) { "outdated_flex" }
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
          expect(error.message).to include("Your requirements could not be resolved to an installable set of packages.")
          expect(error.message).to include("requires composer-plugin-api ^1.0 -> found composer-plugin-api[2.")
          expect(error).to be_a Dependabot::DependencyFileNotResolvable
        end
      end
    end

    context "that requires an environment variable (composer v1)" do
      let(:project_name) { "v1/env_variable" }

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
            credentials: [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "php_environment_variable",
              "env-key" => "ACF_PRO_KEY",
              "env-value" => "example_key"
            }]
          )
        end

        it "runs just fine (we get a 404 here because our key is wrong)" do
          expect { updated_lockfile_content }.to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotResolvable)
            expect(error.message).to include("404")
          end
        end
      end
    end

    context "that requires an environment variable (composer v2)" do
      let(:project_name) { "env_variable" }

      context "that hasn't been provided" do
        it "raises a MissingEnvironmentVariable error" do
          expect { updated_lockfile_content }.to raise_error do |error|
            expect(error).to be_a(Dependabot::MissingEnvironmentVariable)
            expect(error.message).to eq("Missing environment variable ACF_PRO_KEY")
          end
        end
      end

      context "that has been provided" do
        let(:updater) do
          described_class.new(
            dependency_files: files,
            dependencies: [dependency],
            credentials: [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "php_environment_variable",
              "env-key" => "ACF_PRO_KEY",
              "env-value" => "example_key"
            }]
          )
        end

        it "runs just fine (we get a 404 here because our key is wrong)" do
          expect { updated_lockfile_content }.to raise_error do |error|
            expect(error).to be_a(Dependabot::DependencyFileNotResolvable)
            expect(error.message).to include("404")
          end
        end
      end
    end

    context "with a path source" do
      let(:project_name) { "path_source" }

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
      let(:project_name) { "covered_version" }

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
      let(:project_name) { "development_dependencies" }

      it "has details of the updated item" do
        expect(updated_lockfile_content).to include("\"version\":\"1.22.1\"")
      end
    end

    context "when the dependency is a subdependency" do
      let(:project_name) { "subdependency_update_required" }

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

      context "and is limited by a library's PHP version" do
        let(:project_name) { "php_specified_in_library" }

        let(:dependency) do
          Dependabot::Dependency.new(
            name: "doctrine/inflector",
            version: "1.1.0",
            previous_version: "1.0",
            requirements: [],
            previous_requirements: [],
            package_manager: "composer"
          )
        end

        it "has details of the updated item" do
          expect(updated_lockfile_content).to include("\"version\":\"v1.1.0\"")
          expect(updated_lockfile_content).
            to include("90b2128806bfde671b6952ab8bea493942c1fdae")
        end
      end
    end

    context "with a private registry" do
      let(:project_name) { "private_registry" }
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
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "composer_repository",
            "registry" => "php.fury.io",
            "username" => "yFu9PBmw1HxNjFB818TW", # Throwaway account
            "password" => ""
          }]
        end

        it "has details of the updated item" do
          expect(updated_lockfile_content).to include("\"version\":\"2.2.0\"")
        end
      end
    end

    context "with a laravel nova" do
      let(:project_name) { "laravel_nova" }
      before { `composer clear-cache --quiet` }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "laravel/nova",
          version: "2.0.9",
          previous_version: "2.0.7",
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

      context "with bad credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "composer_repository",
            "registry" => "nova.laravel.com",
            "username" => "username",
            "password" => "password"
          }]
        end

        it "raises a helpful errors" do
          expect { updated_lockfile_content }.to raise_error do |error|
            expect(error).to be_a Dependabot::PrivateSourceAuthenticationFailure
            expect(error.source).to eq("nova.laravel.com")
          end
        end
      end
    end

    context "when another dependency has git source with a bad reference" do
      let(:project_name) { "git_source_bad_ref" }

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

    context "when another dependency has git source with a bad commit" do
      let(:project_name) { "git_source_bad_commit" }

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
          expect(error.dependency).
            to eq("monolog/monolog")
        end
      end
    end

    context "with a git source using no-api" do
      let(:project_name) { "git_source_no_api" }

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

      it "updates the lockfile correctly" do
        # Doesn't update the commit SHA of the git dependency
        expect(updated_lockfile_content).
          to include('"5267b03b1e4861c4657ede17a88f13ef479db482"')
        expect(updated_lockfile_content).
          to_not include('"303b8a83c87d5c6d749926cf02620465a5dcd0f2"')
        expect(updated_lockfile_content).to include('"version":"dev-example"')

        # Does update the specified dependency
        expect(updated_lockfile_content).
          to include('"2ec8b39c38cb16674bbf3fea2b6ce5bf117e1296"')
        expect(updated_lockfile_content).to include('"version":"v1.6.0"')

        # Cleans up the additions we made
        expect(updated_lockfile_content).to_not include('"support": {')
      end
    end

    context "when another dependency has an unreachable git source" do
      let(:project_name) { "git_source_unreachable" }

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

    context "when there are patches (composer v1)" do
      let(:project_name) { "v1/patches" }

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

    context "when there are patches (composer v2)" do
      let(:project_name) { "patches" }

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

      # This is a known issue in the composer-patches plugin and composer v2:
      # https://github.com/cweagans/composer-patches/issues/338
      pending "doesn't strip the patches" do
        updated_dep = JSON.parse(updated_lockfile_content).
                      fetch("packages").
                      find { |p| p["name"] == "ehime/hello-world" }

        expect(updated_dep.dig("extra", "patches_applied")).
          to include("[PATCH] markdown modified")
      end
    end

    context "regression spec for media-organizer" do
      let(:project_name) { "media_organizer" }

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
      let(:project_name) { "subdependency_update_required" }

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
        expect(updated_lockfile_content).to include("ba383d0a3bf6aa0b7a1307fdc")
      end
    end

    context "updating to a specific version when reqs would allow higher" do
      let(:project_name) { "subdependency_update_required" }

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
        expect(updated_lockfile_content).to include("e244eda135819216ac3044146")
      end
    end

    context "with a missing git repository source" do
      let(:project_name) { "git_source_unreachable" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "symfony/polyfill-mbstring",
          version: "1.0.1",
          requirements: [{
            file: "composer.json",
            requirement: "1.0.1",
            groups: ["runtime"],
            source: nil
          }],
          previous_version: "1.0.1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.1",
            groups: ["runtime"],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { updated_lockfile_content }.
          to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
            expect(error.dependency_urls).
              to eq(["https://github.com/no-exist-sorry/monolog.git"])
          end
      end
    end

    context "with a missing vcs repository source" do
      let(:project_name) { "vcs_source_unreachable" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "symfony/polyfill-mbstring",
          version: "1.0.1",
          requirements: [{
            file: "composer.json",
            requirement: "1.0.1",
            groups: ["runtime"],
            source: nil
          }],
          previous_version: "1.0.1",
          previous_requirements: [{
            file: "composer.json",
            requirement: "1.0.1",
            groups: ["runtime"],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { updated_lockfile_content }.
          to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
            expect(error.dependency_urls).
              to eq(["https://github.com/dependabot-fixtures/this-repo-does-not-exist.git"])
          end
      end
    end
  end
end
