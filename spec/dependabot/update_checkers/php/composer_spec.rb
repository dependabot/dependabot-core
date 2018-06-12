# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/php/composer"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Php::Composer do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: files,
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "composer"
    )
  end
  let(:ignored_versions) { [] }
  let(:dependency_name) { "monolog/monolog" }
  let(:dependency_version) { "1.0.1" }
  let(:requirements) do
    [{ file: "composer.json", requirement: "1.0.*", groups: [], source: nil }]
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:files) { [composer_file, lockfile] }
  let(:composer_file) do
    Dependabot::DependencyFile.new(
      content: fixture("php", "composer_files", manifest_fixture_name),
      name: "composer.json"
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      content: fixture("php", "lockfiles", lockfile_fixture_name),
      name: "composer.lock"
    )
  end
  let(:manifest_fixture_name) { "exact_version" }
  let(:lockfile_fixture_name) { "exact_version" }

  before do
    sanitized_name = dependency_name.downcase.tr("/", ":")
    fixture = fixture("php", "packagist_responses", "#{sanitized_name}.json")
    url = "https://packagist.org/p/#{dependency_name.downcase}.json"
    stub_request(:get, url).to_return(status: 200, body: fixture)
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    let(:packagist_url) { "https://packagist.org/p/monolog/monolog.json" }
    let(:packagist_response) { fixture("php", "packagist_response.json") }

    before do
      stub_request(:get, packagist_url).
        to_return(status: 200, body: packagist_response)
      allow(checker).to receive(:latest_resolvable_version).
        and_return(Gem::Version.new("1.17.0"))
    end

    it { is_expected.to eq(Gem::Version.new("1.22.1")) }

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 1.22.0.a, < 1.23"] }
      it { is_expected.to eq(Gem::Version.new("1.21.0")) }
    end

    context "when using a pre-release" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/monolog",
          version: "1.0.0-RC1",
          requirements: [{
            file: "composer.json",
            requirement: "1.0.0-RC1",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end
      it { is_expected.to eq(Gem::Version.new("1.23.0-rc1")) }
    end

    context "without a lockfile" do
      let(:files) { [composer_file] }
      it { is_expected.to eq(Gem::Version.new("1.22.1")) }

      context "when using a pre-release" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "monolog/monolog",
            version: nil,
            requirements: [{
              file: "composer.json",
              requirement: "1.0.0-RC1",
              groups: [],
              source: nil
            }],
            package_manager: "composer"
          )
        end
        it { is_expected.to eq(Gem::Version.new("1.23.0-rc1")) }
      end
    end

    context "when packagist 404s" do
      before { stub_request(:get, packagist_url).to_return(status: 404) }
      it { is_expected.to eq(Gem::Version.new("1.17.0")) }
    end

    context "when packagist returns an empty array" do
      before do
        stub_request(:get, packagist_url).
          to_return(status: 200, body: '{"packages":[]}')
        allow(checker).to receive(:latest_resolvable_version).
          and_return(Gem::Version.new("1.17.0"))
      end

      it { is_expected.to eq(Gem::Version.new("1.17.0")) }
    end

    context "when packagist returns details of a different dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/something",
          version: "1.0.1",
          requirements: [{
            file: "composer.json",
            requirement: "1.0.*",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end
      let(:packagist_url) { "https://packagist.org/p/monolog/something.json" }

      it { is_expected.to eq(Gem::Version.new("1.17.0")) }
    end

    context "with a package with capitals" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/MonoLog",
          version: "1.0.1",
          requirements: [{
            file: "composer.json",
            requirement: "1.0.*",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end

      it "downcases the dependency name" do
        expect(checker.latest_version).to eq(Gem::Version.new("1.22.1"))
        expect(WebMock).
          to have_requested(
            :get,
            "https://packagist.org/p/monolog/monolog.json"
          )
      end
    end

    context "with a private composer registry" do
      let(:manifest_fixture_name) { "private_registry" }
      let(:lockfile_fixture_name) { "private_registry" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "dependabot/dummy-pkg-a",
          version: "2.1.0",
          requirements: [{
            file: "composer.json",
            requirement: "*",
            groups: [],
            source: nil
          }],
          package_manager: "composer"
        )
      end
      let(:gemfury_response) { fixture("php", "gemfury_response.json") }
      let(:gemfury_url) do
        "https://php.fury.io/dependabot-throwaway/packages.json"
      end

      before do
        stub_request(:get, gemfury_url).
          to_return(status: 200, body: gemfury_response)
      end

      it { is_expected.to eq(Gem::Version.new("2.2.0")) }
      it "doesn't hit the main registry (since requested not to)" do
        checker.latest_version
        expect(WebMock).to_not have_requested(:get, packagist_url)
      end

      context "when a 404 is returned" do
        before { stub_request(:get, gemfury_url).to_return(status: 404) }
        it { is_expected.to eq(Gem::Version.new("1.17.0")) }
      end

      context "when a hash with bad keys is returned" do
        before do
          stub_request(:get, gemfury_url).
            to_return(status: 200, body: { odd: "data" }.to_json)
        end
        it { is_expected.to eq(Gem::Version.new("1.17.0")) }
      end

      context "when given credentials" do
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
              "username" => "user",
              "password" => "pass"
            }
          ]
        end

        it "uses the credentials" do
          checker.latest_version
          expect(WebMock).
            to have_requested(:get, gemfury_url).
            with(basic_auth: %w(user pass))
        end
      end
    end

    context "with an unreachable source (speccing we don't try to reach it)" do
      let(:manifest_fixture_name) { "git_source_unreachable_git_url" }
      let(:lockfile_fixture_name) { "git_source_unreachable_git_url" }
      it { is_expected.to eq(Gem::Version.new("1.22.1")) }
    end

    context "with a path source" do
      let(:files) { [composer_file, lockfile, path_dep] }
      let(:manifest_fixture_name) { "path_source" }
      let(:lockfile_fixture_name) { "path_source" }
      let(:path_dep) do
        Dependabot::DependencyFile.new(
          name: "components/path_dep/composer.json",
          content: fixture("php", "composer_files", "path_dep")
        )
      end
      before do
        stub_request(:get, "https://packagist.org/p/path_dep/path_dep.json").
          to_return(status: 404)
      end

      context "that is not the dependency we're checking" do
        it { is_expected.to eq(Gem::Version.new("1.22.1")) }
      end

      context "that is the dependency we're checking" do
        let(:dependency_name) { "path_dep/path_dep" }
        let(:current_version) { "1.0.1" }
        let(:requirements) do
          [{
            requirement: "1.0.*",
            file: "composer.json",
            groups: ["runtime"],
            source: { type: "path" }
          }]
        end

        it { is_expected.to be_nil }
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "returns a non-normalized version, following semver" do
      expect(subject.segments.count).to eq(3)
    end

    it { is_expected.to be >= Gem::Version.new("1.22.0") }

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 1.22.0.a, < 3.0"] }
      it { is_expected.to eq(Gem::Version.new("1.21.0")) }
    end

    context "without a lockfile" do
      let(:files) { [composer_file] }
      it { is_expected.to be >= Gem::Version.new("1.22.0") }

      context "when there are conflicts at the version specified" do
        let(:manifest_fixture_name) { "conflicts" }
        let(:dependency_name) { "phpdocumentor/reflection-docblock" }
        let(:dependency_version) { nil }
        let(:requirements) do
          [{
            file: "composer.json",
            requirement: "^4.3",
            groups: [],
            source: nil
          }]
        end
        it { is_expected.to be >= Gem::Version.new("4.3.0") }
      end

      context "when an old version of PHP is specified" do
        let(:manifest_fixture_name) { "old_php_specified" }
        let(:dependency_name) { "illuminate/support" }
        let(:dependency_version) { "5.2.7" }
        let(:requirements) do
          [{
            file: "composer.json",
            requirement: "^5.2.0",
            groups: ["runtime"],
            source: nil
          }]
        end

        # 5.5.0 series requires PHP 7
        it { is_expected.to be >= Gem::Version.new("5.4.36") }
        pending { is_expected.to be < Gem::Version.new("5.5.0") }

        context "as a platform requirement" do
          let(:manifest_fixture_name) { "old_php_platform" }
          it { is_expected.to be >= Gem::Version.new("5.4.36") }
          it { is_expected.to be < Gem::Version.new("5.5.0") }

          context "and an extension is specified that we don't have" do
            let(:manifest_fixture_name) { "missing_extension" }

            it "raises a helpful error" do
              expect { checker.latest_resolvable_version }.
                to raise_error do |error|
                  expect(error).to be_a(Dependabot::DependencyFileNotResolvable)
                  expect(error.message).
                    to include("extension ext-maxminddb * is missing")
                  expect(error.message).
                    to include("platform config: ext-maxminddb.\n")
                end
            end
          end

          context "but the platform requirement only specifies an extension" do
            let(:manifest_fixture_name) { "bad_php" }

            it "raises a helpful error" do
              expect { checker.latest_resolvable_version }.
                to raise_error do |error|
                  expect(error).to be_a(Dependabot::DependencyFileNotResolvable)
                  expect(error.message).
                    to include("This package requires php 5.6.4 but")
                end
            end
          end
        end
      end
    end

    context "with a dev dependency" do
      let(:manifest_fixture_name) { "development_dependencies" }
      let(:lockfile_fixture_name) { "development_dependencies" }
      it { is_expected.to be >= Gem::Version.new("1.22.0") }
    end

    context "with a path source" do
      let(:files) { [composer_file, lockfile, path_dep] }
      let(:manifest_fixture_name) { "path_source" }
      let(:lockfile_fixture_name) { "path_source" }
      let(:path_dep) do
        Dependabot::DependencyFile.new(
          name: "components/path_dep/composer.json",
          content: fixture("php", "composer_files", "path_dep")
        )
      end
      before do
        stub_request(:get, "https://packagist.org/p/path_dep/path_dep.json").
          to_return(status: 404)
      end

      context "that is not the dependency we're checking" do
        it { is_expected.to be >= Gem::Version.new("1.22.0") }
      end

      context "that is the dependency we're checking" do
        let(:dependency_name) { "path_dep/path_dep" }
        let(:current_version) { "1.0.1" }
        let(:requirements) do
          [{
            requirement: "1.0.*",
            file: "composer.json",
            groups: ["runtime"],
            source: { type: "path" }
          }]
        end

        it { is_expected.to be_nil }
      end
    end

    context "with a private registry" do
      let(:manifest_fixture_name) { "private_registry" }
      let(:lockfile_fixture_name) { "private_registry" }
      before { `composer clear-cache --quiet` }

      let(:dependency_name) { "dependabot/dummy-pkg-a" }
      let(:dependency_version) { nil }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "*",
          groups: [],
          source: nil
        }]
      end

      before do
        url = "https://php.fury.io/dependabot-throwaway/packages.json"
        stub_request(:get, url).
          to_return(status: 200, body: fixture("php", "gemfury_response.json"))
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

        it { is_expected.to be >= Gem::Version.new("2.2.0") }
      end

      context "with bad credentials" do
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
              "username" => "bad",
              "password" => ""
            }
          ]
        end

        it "raises a helpful error message" do
          expect { checker.latest_resolvable_version }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::PrivateSourceNotReachable)
              expect(error.source).to eq("php.fury.io")
            end
        end
      end

      context "with no credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        end

        it "raises a helpful error message" do
          expect { checker.latest_resolvable_version }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::PrivateSourceNotReachable)
              expect(error.source).to eq("php.fury.io")
            end
        end
      end
    end

    context "with a replaced dependency" do
      let(:manifest_fixture_name) { "replaced_dependency" }
      let(:lockfile_fixture_name) { "replaced_dependency" }
      let(:dependency_name) { "illuminate/console" }
      let(:dependency_version) { nil }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "5.5.*",
          groups: [],
          source: nil
        }]
      end
      it { is_expected.to be_nil }
    end

    context "with a replaced direct dependency" do
      let(:manifest_fixture_name) { "replaced_direct_dependency" }
      let(:files) { [composer_file] }
      let(:dependency_name) { "neos/flow" }
      let(:dependency_version) { nil }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "*",
          groups: [],
          source: nil
        }]
      end
      it { is_expected.to be_nil }
    end

    context "with a PEAR dependency" do
      let(:manifest_fixture_name) { "pear" }
      let(:lockfile_fixture_name) { "pear" }
      let(:dependency_name) { "pear-pear.horde.org/Horde_Date" }
      let(:dependency_version) { "2.4.1" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "^2.4.0@stable",
          groups: [],
          source: nil
        }]
      end

      it "is between 2.0.0 and 3.0.0" do
        expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
        expect(latest_resolvable_version).to be > Gem::Version.new("2.0.0")
      end
    end

    context "with a version conflict at the latest version" do
      let(:manifest_fixture_name) { "version_conflict_at_latest" }
      let(:lockfile_fixture_name) { "version_conflict_at_latest" }
      let(:dependency_name) { "doctrine/dbal" }
      let(:dependency_version) { "2.1.5" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "1.0.*",
          groups: [],
          source: nil
        }]
      end

      it "is between 2.0.0 and 3.0.0" do
        expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
        expect(latest_resolvable_version).to be > Gem::Version.new("2.0.0")
      end
    end

    context "with a version conflict in the current files" do
      let(:manifest_fixture_name) { "version_conflict" }
      let(:dependency_name) { "monolog/monolog" }
      let(:dependency_version) { "2.1.5" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "1.0.*",
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to be_nil }
    end

    context "with an update that can't resolve" do
      let(:manifest_fixture_name) { "version_conflict_on_update" }
      let(:lockfile_fixture_name) { "version_conflict_on_update" }
      let(:dependency_name) { "longman/telegram-bot" }
      let(:dependency_version) { "2.1.5" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "1.0.*",
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to be_nil }
    end

    context "with a dependency with a git source" do
      let(:manifest_fixture_name) { "git_source" }
      let(:lockfile_fixture_name) { "git_source" }
      it { is_expected.to be >= Gem::Version.new("1.22.1") }

      context "that is not the gem we're checking" do
        let(:dependency_name) { "symfony/polyfill-mbstring" }
        let(:dependency_version) { "1.0.1" }
        let(:requirements) do
          [{
            file: "composer.json",
            requirement: "1.0.*",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be >= Gem::Version.new("1.3.0") }

        context "that is unreachable" do
          let(:manifest_fixture_name) { "git_source_unreachable" }
          let(:lockfile_fixture_name) { "git_source_unreachable" }

          it "raises a helpful error" do
            expect { checker.latest_resolvable_version }.
              to raise_error do |error|
                expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
                expect(error.dependency_urls).
                  to eq(["https://github.com/no-exist-sorry/monolog.git"])
              end
          end

          context "with a git URL" do
            let(:manifest_fixture_name) { "git_source_unreachable_git_url" }
            let(:lockfile_fixture_name) { "git_source_unreachable_git_url" }

            it "raises a helpful error" do
              expect { checker.latest_resolvable_version }.
                to raise_error do |error|
                  expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
                  expect(error.dependency_urls).
                    to eq(["https://github.com/no-exist-sorry/monolog.git"])
                end
            end
          end
        end
      end
    end

    context "when an alternative source is specified" do
      let(:manifest_fixture_name) { "alternative_source" }
      let(:lockfile_fixture_name) { "alternative_source" }
      let(:dependency_name) { "wpackagist-plugin/acf-to-rest-api" }
      let(:dependency_version) { "2.2.1" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "*",
          groups: ["runtime"],
          source: nil
        }]
      end

      before do
        stub_request(:get, "https://wpackagist.org/packages.json").
          to_return(
            status: 200,
            body: fixture("php", "wpackagist_response.json")
          )
      end

      it { is_expected.to be >= Gem::Version.new("3.0.2") }
    end

    context "when an autoload is specified" do
      let(:manifest_fixture_name) { "autoload" }
      let(:lockfile_fixture_name) { "autoload" }
      let(:dependency_name) { "illuminate/support" }
      let(:dependency_version) { "5.2.7" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "^5.2.0",
          groups: ["runtime"],
          source: nil
        }]
      end

      it { is_expected.to be >= Gem::Version.new("5.2.30") }
    end

    context "when a sub-dependency would block the update" do
      let(:manifest_fixture_name) { "subdependency_update_required" }
      let(:lockfile_fixture_name) { "subdependency_update_required" }
      let(:dependency_name) { "illuminate/support" }
      let(:dependency_version) { "5.2.0" }
      let(:requirements) do
        [{
          file: "composer.json",
          requirement: "^5.2.0",
          groups: ["runtime"],
          source: nil
        }]
      end

      # 5.5.0 series and up require an update to illuminate/contracts
      it { is_expected.to be >= Gem::Version.new("5.6.23") }
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "monolog/monolog",
        version: "1.0.1",
        requirements: dependency_requirements,
        package_manager: "composer"
      )
    end
    let(:dependency_requirements) do
      [{
        file: "composer.json",
        requirement: "1.0.*",
        groups: [],
        source: nil
      }]
    end

    before do
      allow(checker).
        to receive(:latest_resolvable_version).
        and_return(Gem::Version.new("1.6.0"))
      allow(checker).
        to receive(:latest_version).
        and_return(Gem::Version.new("1.7.0"))
    end

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).
        to receive(:new).
        with(
          requirements: dependency_requirements,
          latest_version: "1.7.0",
          latest_resolvable_version: "1.6.0",
          library: false
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [{
            file: "composer.json",
            requirement: "1.6.*",
            groups: [],
            source: nil
          }]
        )
    end
  end
end
