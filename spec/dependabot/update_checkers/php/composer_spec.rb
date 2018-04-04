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
      credentials: credentials
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "monolog/monolog",
      version: "1.0.1",
      requirements: [
        { file: "composer.json", requirement: "1.0.*", groups: [], source: nil }
      ],
      package_manager: "composer"
    )
  end
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
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

    context "when using a pre-release" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/monolog",
          version: "1.0.0-RC1",
          requirements: [
            {
              file: "composer.json",
              requirement: "1.0.0-RC1",
              groups: [],
              source: nil
            }
          ],
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
            requirements: [
              {
                file: "composer.json",
                requirement: "1.0.0-RC1",
                groups: [],
                source: nil
              }
            ],
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
          requirements: [
            {
              file: "composer.json",
              requirement: "1.0.*",
              groups: [],
              source: nil
            }
          ],
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
          requirements: [
            {
              file: "composer.json",
              requirement: "1.0.*",
              groups: [],
              source: nil
            }
          ],
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
          requirements: [
            {
              file: "composer.json",
              requirement: "*",
              groups: [],
              source: nil
            }
          ],
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
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
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
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "returns a non-normalized version, following semver" do
      expect(subject.segments.count).to eq(3)
    end

    it { is_expected.to be >= Gem::Version.new("1.22.0") }

    context "without a lockfile" do
      let(:files) { [composer_file] }
      it { is_expected.to be >= Gem::Version.new("1.22.0") }
    end

    context "with a dev dependency" do
      let(:manifest_fixture_name) { "development_dependencies" }
      let(:lockfile_fixture_name) { "development_dependencies" }
      it { is_expected.to be >= Gem::Version.new("1.22.0") }
    end

    context "with a private registry" do
      let(:manifest_fixture_name) { "private_registry" }
      let(:lockfile_fixture_name) { "private_registry" }
      before { `composer clear-cache --quiet` }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "dependabot/dummy-pkg-a",
          version: nil,
          requirements: [
            {
              file: "composer.json",
              requirement: "*",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      context "with good credentials" do
        let(:credentials) do
          [
            {
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
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
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
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
          [
            {
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
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
    end

    context "with a replaced dependency" do
      let(:manifest_fixture_name) { "replaced_dependency" }
      let(:lockfile_fixture_name) { "replaced_dependency" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "illuminate/console",
          version: nil,
          requirements: [
            {
              file: "composer.json",
              requirement: "5.5.*",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end
      it { is_expected.to be_nil }
    end

    context "with a PEAR dependency" do
      let(:manifest_fixture_name) { "pear" }
      let(:lockfile_fixture_name) { "pear" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "pear-pear.horde.org/Horde_Date",
          version: "2.4.1",
          requirements: [
            {
              file: "composer.json",
              requirement: "^2.4.0@stable",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      it "is between 2.0.0 and 3.0.0" do
        expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
        expect(latest_resolvable_version).to be > Gem::Version.new("2.0.0")
      end
    end

    context "with a version conflict at the latest version" do
      let(:manifest_fixture_name) { "version_conflict_at_latest" }
      let(:lockfile_fixture_name) { "version_conflict_at_latest" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "doctrine/dbal",
          version: "2.1.5",
          requirements: [
            {
              file: "composer.json",
              requirement: "1.0.*",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      it "is between 2.0.0 and 3.0.0" do
        expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
        expect(latest_resolvable_version).to be > Gem::Version.new("2.0.0")
      end
    end

    context "with a version conflict in the current files" do
      let(:manifest_fixture_name) { "version_conflict" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "monolog/monolog",
          version: "2.1.5",
          requirements: [
            {
              file: "composer.json",
              requirement: "1.0.*",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      it { is_expected.to be_nil }
    end

    context "with an update that can't resolve" do
      let(:manifest_fixture_name) { "version_conflict_on_update" }
      let(:lockfile_fixture_name) { "version_conflict_on_update" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "longman/telegram-bot",
          version: "2.1.5",
          requirements: [
            {
              file: "composer.json",
              requirement: "1.0.*",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      it { is_expected.to be_nil }
    end

    context "with a dependency with a git source" do
      let(:manifest_fixture_name) { "git_source" }
      let(:lockfile_fixture_name) { "git_source" }
      it { is_expected.to be >= Gem::Version.new("1.22.1") }

      context "that is not the gem we're checking" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "symfony/polyfill-mbstring",
            version: "1.0.1",
            requirements: [
              {
                file: "composer.json",
                requirement: "1.0.*",
                groups: [],
                source: nil
              }
            ],
            package_manager: "composer"
          )
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
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "wpackagist-plugin/acf-to-rest-api",
          version: "2.2.1",
          requirements: [
            {
              file: "composer.json",
              requirement: "*",
              groups: ["runtime"],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      it { is_expected.to be >= Gem::Version.new("3.0.2") }
    end

    context "when an autoload is specified" do
      let(:manifest_fixture_name) { "autoload" }
      let(:lockfile_fixture_name) { "autoload" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "illuminate/support",
          version: "v5.2.7",
          requirements: [
            {
              file: "composer.json",
              requirement: "^5.2.0",
              groups: ["runtime"],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      it { is_expected.to be >= Gem::Version.new("5.2.30") }
    end

    context "when an old version of PHP is specified" do
      let(:manifest_fixture_name) { "old_php_specified" }
      let(:lockfile_fixture_name) { "old_php_specified" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "illuminate/support",
          version: "v5.2.7",
          requirements: [
            {
              file: "composer.json",
              requirement: "^5.2.0",
              groups: ["runtime"],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      it { is_expected.to be >= Gem::Version.new("5.4.36") }

      # 5.5.0 series requires PHP 7
      it { is_expected.to be < Gem::Version.new("5.5.0") }
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
      [
        {
          file: "composer.json",
          requirement: "1.0.*",
          groups: [],
          source: nil
        }
      ]
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
          [
            {
              file: "composer.json",
              requirement: "1.6.*",
              groups: [],
              source: nil
            }
          ]
        )
    end
  end
end
