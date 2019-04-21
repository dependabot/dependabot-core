# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/composer/update_checker/latest_version_finder"

RSpec.describe Dependabot::Composer::UpdateChecker::LatestVersionFinder do
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
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
  let(:security_advisories) { [] }
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
      content: fixture("composer_files", manifest_fixture_name),
      name: "composer.json"
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      content: fixture("lockfiles", lockfile_fixture_name),
      name: "composer.lock"
    )
  end
  let(:manifest_fixture_name) { "exact_version" }
  let(:lockfile_fixture_name) { "exact_version" }

  before do
    sanitized_name = dependency_name.downcase.gsub("/", "--")
    fixture = fixture("packagist_responses", "#{sanitized_name}.json")
    url = "https://packagist.org/p/#{dependency_name.downcase}.json"
    stub_request(:get, url).to_return(status: 200, body: fixture)
  end

  describe "#latest_version" do
    subject { finder.latest_version }

    let(:packagist_url) { "https://packagist.org/p/monolog/monolog.json" }
    let(:packagist_response) { fixture("packagist_response.json") }

    before do
      stub_request(:get, packagist_url).
        to_return(status: 200, body: packagist_response)
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
      it { is_expected.to be_nil }
    end

    context "when packagist returns an empty array" do
      before do
        stub_request(:get, packagist_url).
          to_return(status: 200, body: '{"packages":[]}')
      end

      it { is_expected.to be_nil }
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

      it { is_expected.to be_nil }
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
        expect(finder.latest_version).to eq(Gem::Version.new("1.22.1"))
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
      let(:gemfury_response) { fixture("gemfury_response.json") }
      let(:gemfury_url) do
        "https://php.fury.io/dependabot-throwaway/packages.json"
      end

      before do
        stub_request(:get, gemfury_url).
          to_return(status: 200, body: gemfury_response)
      end

      it { is_expected.to eq(Gem::Version.new("2.2.0")) }
      it "doesn't hit the main registry (since requested not to)" do
        finder.latest_version
        expect(WebMock).to_not have_requested(:get, packagist_url)
      end

      context "when a 404 is returned" do
        before { stub_request(:get, gemfury_url).to_return(status: 404) }
        it { is_expected.to be_nil }
      end

      context "when an empty body is returned" do
        before do
          stub_request(:get, gemfury_url).to_return(status: 200, body: "")
        end

        it "raises a helpful error" do
          expect { finder.latest_version }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::DependencyFileNotResolvable)
              expect(error.message).to include(gemfury_url)
            end
        end
      end

      context "when a hash with bad keys is returned" do
        before do
          stub_request(:get, gemfury_url).
            to_return(status: 200, body: { odd: "data" }.to_json)
        end
        it { is_expected.to be_nil }
      end

      context "when given credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "composer_repository",
            "registry" => "php.fury.io",
            "username" => "user",
            "password" => "pass"
          }]
        end

        it "uses the credentials" do
          finder.latest_version
          expect(WebMock).
            to have_requested(:get, gemfury_url).
            with(basic_auth: %w(user pass))
        end

        context "without a username and password" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "composer_repository",
              "registry" => "php.fury.io"
            }]
          end

          it "uses the credentials" do
            finder.latest_version
            expect(WebMock).to have_requested(:get, gemfury_url)
          end
        end
      end
    end

    context "with an unreachable source (speccing we don't try to reach it)" do
      let(:manifest_fixture_name) { "git_source_unreachable_git_url" }
      let(:lockfile_fixture_name) { "git_source_unreachable_git_url" }
      it { is_expected.to eq(Gem::Version.new("1.22.1")) }
    end
  end
end
