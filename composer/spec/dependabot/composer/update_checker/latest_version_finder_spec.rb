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
      raise_on_ignored: raise_on_ignored,
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
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }
  let(:dependency_name) { "monolog/monolog" }
  let(:dependency_version) { "1.0.1" }
  let(:requirements) do
    [{ file: "composer.json", requirement: "1.0.*", groups: [], source: nil }]
  end
  let(:credentials) { github_credentials }
  let(:files) { project_dependency_files(project_name) }
  let(:project_name) { "exact_version" }

  before do
    sanitized_name = dependency_name.downcase.gsub("/", "--")
    fixture = fixture("packagist_responses", "#{sanitized_name}.json")
    url = "https://repo.packagist.org/p/#{dependency_name.downcase}.json"
    stub_request(:get, url).to_return(status: 200, body: fixture)
  end

  describe "#latest_version" do
    subject { finder.latest_version }

    let(:packagist_url) { "https://repo.packagist.org/p/monolog/monolog.json" }
    let(:packagist_response) { fixture("packagist_response.json") }

    before do
      stub_request(:get, packagist_url).
        to_return(status: 200, body: packagist_response)
    end

    it { is_expected.to eq(Gem::Version.new("1.22.1")) }

    context "raise_on_ignored when later versions are allowed" do
      let(:raise_on_ignored) { true }
      it "doesn't raise an error" do
        expect { subject }.to_not raise_error
      end
    end

    context "when the user is on the latest version" do
      let(:dependency_version) { "1.22.1" }
      it { is_expected.to eq(Gem::Version.new("1.22.1")) }

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "doesn't raise an error" do
          expect { subject }.to_not raise_error
        end
      end
    end

    context "when the user is ignoring all later versions" do
      let(:ignored_versions) { ["> 1.0.1"] }
      it { is_expected.to eq(Gem::Version.new("1.0.1")) }

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "raises an error" do
          expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 1.22.0.a, < 1.23"] }
      it { is_expected.to eq(Gem::Version.new("1.21.0")) }
    end

    context "when the dependency version isn't known" do
      let(:dependency_version) { nil }

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "doesn't raise an error" do
          expect { subject }.to_not raise_error
        end
      end
    end

    context "when the dependency version isn't known" do
      let(:dependency_version) { nil }

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "doesn't raise an error" do
          expect { subject }.to_not raise_error
        end
      end
    end

    context "when the user is ignoring all versions" do
      let(:ignored_versions) { [">= 0"] }
      it "returns nil" do
        expect(subject).to be_nil
      end

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "raises an error" do
          expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
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
      let(:project_name) { "exact_version_without_lockfile" }
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
      let(:packagist_url) { "https://repo.packagist.org/p/monolog/something.json" }

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
            "https://repo.packagist.org/p/monolog/monolog.json"
          )
      end
    end

    context "with a private composer registry" do
      let(:project_name) { "private_registry" }
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
            "registry" => "php.fury.io.evil.com",
            "username" => "user",
            "password" => "pass"
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

        context "in an auth.json file" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }]
          end
          let(:project_name) { "private_registry_with_auth_json" }

          it "uses the credentials" do
            finder.latest_version
            expect(WebMock).
              to have_requested(:get, gemfury_url).
              with(basic_auth: %w(user pass))
          end

          context "that can't be parsed" do
            let(:project_name) { "private_registry_with_unparseable_auth_json" }

            it "raises a helpful error" do
              expect { finder.latest_version }.
                to raise_error do |error|
                  expect(error).to be_a(Dependabot::DependencyFileNotParseable)
                  expect(error.file_name).to eq("auth.json")
                end
            end
          end
        end
      end
    end

    context "with an unreachable source (speccing we don't try to reach it)" do
      let(:project_name) { "git_source_unreachable_git_url" }
      it { is_expected.to eq(Gem::Version.new("1.22.1")) }
    end
  end

  describe "#lowest_security_fix_version" do
    subject { finder.lowest_security_fix_version }

    let(:dependency_version) { "1.0.1" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "composer",
          vulnerable_versions: ["<= 1.11.0"]
        )
      ]
    end
    it { is_expected.to eq(Gem::Version.new("1.12.0")) }
  end
end
