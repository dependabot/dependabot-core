# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java_script/npm_and_yarn"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::JavaScript::NpmAndYarn do
  it_behaves_like "an update checker"

  let(:registry_listing_url) { "https://registry.npmjs.org/etag" }
  before do
    stub_request(:get, registry_listing_url).
      to_return(status: 200, body: fixture("javascript", "npm_response.json"))
    stub_request(:get, registry_listing_url + "/1.7.0").
      to_return(status: 200)
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials
    )
  end
  let(:dependency_files) { [] }

  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "etag",
      version: "1.0.0",
      requirements: [
        { file: "package.json", requirement: "^1.0.0", groups: [], source: nil }
      ],
      package_manager: "npm_and_yarn"
    )
  end

  describe "#can_update?" do
    subject { checker.can_update? }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }

      context "with no version" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            requirements: [
              {
                file: "package.json",
                requirement: "^0.9.0",
                groups: [],
                source: nil
              }
            ],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to be_truthy }
      end
    end

    context "given an up-to-date dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.7.0",
          requirements: [
            {
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }
          ],
          package_manager: "npm_and_yarn"
        )
      end

      it { is_expected.to be_falsey }

      context "with no version" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: nil,
            requirements: [
              {
                file: "package.json",
                requirement: requirement,
                groups: [],
                source: nil
              }
            ],
            package_manager: "npm_and_yarn"
          )
        end

        context "and a requirement that exactly matches" do
          let(:requirement) { "^1.7.0" }
          it { is_expected.to be_falsey }
        end

        context "and a requirement that covers but doesn't exactly match" do
          let(:requirement) { "^1.6.0" }
          it { is_expected.to be_falsey }
        end
      end
    end

    context "for a scoped package name" do
      before do
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
          to_return(
            status: 200,
            body: fixture("javascript", "npm_response.json")
          )
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep/1.7.0").
          to_return(status: 200)
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@blep/blep",
          version: "1.0.0",
          requirements: [
            {
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }
          ],
          package_manager: "npm_and_yarn"
        )
      end
      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }
    it { is_expected.to eq(Gem::Version.new("1.7.0")) }
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(Gem::Version.new("1.7.0")) }

    it "only hits the registry once" do
      checker.latest_version
      expect(WebMock).to have_requested(:get, registry_listing_url).once
    end

    context "with a git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "is-number",
          version: current_version,
          requirements: [
            {
              requirement: req,
              file: "package.json",
              groups: ["devDependencies"],
              source: {
                type: "git",
                url: "https://github.com/jonschlinkert/is-number",
                branch: nil,
                ref: ref
              }
            }
          ],
          package_manager: "npm_and_yarn"
        )
      end
      let(:current_version) { "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8" }
      before do
        git_url = "https://github.com/jonschlinkert/is-number.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: ["x-access-token", "token"]).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "is-number"),
            headers: git_header
          )
      end

      context "with a branch" do
        let(:ref) { "master" }
        let(:req) { nil }

        it "fetches the latest SHA-1 hash of the head of the branch" do
          expect(checker.latest_version).
            to eq("0c6b15a88bc10cd47f67a09506399dfc9ddc075d")
        end

        context "that doesn't exist" do
          let(:ref) { "non-existant" }
          let(:req) { nil }

          it "fetches the latest SHA-1 hash of the head of the branch" do
            expect(checker.latest_version).to eq(current_version)
          end
        end
      end

      context "with a ref that looks like a version" do
        let(:ref) { "2.0.0" }
        let(:req) { nil }
        before do
          repo_url = "https://api.github.com/repos/jonschlinkert/is-number"
          stub_request(:get, repo_url + "/tags?per_page=100").
            to_return(
              status: 200,
              body: fixture("github", "is_number_tags.json"),
              headers: { "Content-Type" => "application/json" }
            )
          stub_request(:get, repo_url + "/git/refs/tags/4.0.0").
            to_return(
              status: 200,
              body: fixture("github", "ref.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "fetches the latest SHA-1 hash of the latest version tag" do
          expect(checker.latest_version).
            to eq("aa218f56b14c9653891f9e74264a383fa43fefbd")
        end

        context "but there are no tags" do
          before do
            repo_url = "https://api.github.com/repos/jonschlinkert/is-number"
            stub_request(:get, repo_url + "/tags?per_page=100").
              to_return(
                status: 200,
                body: [].to_json,
                headers: { "Content-Type" => "application/json" }
              )
          end

          it "returns the current version" do
            expect(checker.latest_version).to eq(current_version)
          end
        end
      end

      context "with a requirement" do
        let(:ref) { nil }
        let(:req) { "^2.0.0" }
        before do
          repo_url = "https://api.github.com/repos/jonschlinkert/is-number"
          stub_request(:get, repo_url + "/tags?per_page=100").
            to_return(
              status: 200,
              body: fixture("github", "is_number_tags.json"),
              headers: { "Content-Type" => "application/json" }
            )
          stub_request(:get, repo_url + "/git/refs/tags/4.0.0").
            to_return(
              status: 200,
              body: fixture("github", "ref.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "fetches the latest SHA-1 hash of the latest version tag" do
          expect(checker.latest_version).
            to eq("aa218f56b14c9653891f9e74264a383fa43fefbd")
        end

        context "but there are no tags" do
          before do
            repo_url = "https://api.github.com/repos/jonschlinkert/is-number"
            stub_request(:get, repo_url + "/tags?per_page=100").
              to_return(
                status: 200,
                body: [].to_json,
                headers: { "Content-Type" => "application/json" }
              )
          end

          it "returns the current version" do
            expect(checker.latest_version).to eq(current_version)
          end
        end
      end
    end

    context "when the user wants a dist tag" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.0.0",
          requirements: [
            {
              file: "package.json",
              requirement: "stable",
              groups: [],
              source: nil
            }
          ],
          package_manager: "npm_and_yarn"
        )
      end
      before do
        stub_request(:get, registry_listing_url + "/1.5.1").
          to_return(status: 200)
      end
      it { is_expected.to eq(Gem::Version.new("1.5.1")) }
    end

    context "when the latest version is a prerelease" do
      before do
        body = fixture("javascript", "npm_response_prerelease.json")
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: body)
        stub_request(:get, registry_listing_url + "/2.0.0-rc1").
          to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }

      context "and the user wants a .x version" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.7.0",
            requirements: [
              {
                file: "package.json",
                requirement: "1.x",
                groups: [],
                source: nil
              }
            ],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end

      context "and the user wants pre-release versions" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.7.0.beta1",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.0.0",
                groups: [],
                source: nil
              }
            ],
            package_manager: "npm_and_yarn"
          )
        end

        it { is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1")) }

        context "but only says so in their requirements (with a .)" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "etag",
              version: nil,
              requirements: [
                {
                  file: "package.json",
                  requirement: requirement,
                  groups: [],
                  source: nil
                }
              ],
              package_manager: "npm_and_yarn"
            )
          end
          let(:requirement) { "^2.0.0-pre" }

          it { is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1")) }

          context "specified with a dash" do
            let(:requirement) { "^2.0.0-pre" }
            it { is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1")) }
          end
        end
      end
    end

    context "for a private npm-hosted dependency" do
      before do
        body = fixture("javascript", "npm_response_prerelease.json")
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
          to_return(status: 404, body: "{\"error\":\"Not found\"}")
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
          with(headers: { "Authorization" => "Bearer secret_token" }).
          to_return(status: 200, body: body)
        stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep/1.7.0").
          to_return(status: 200)
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@blep/blep",
          version: "1.0.0",
          requirements: [
            {
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: nil
            }
          ],
          package_manager: "npm_and_yarn"
        )
      end

      context "with credentials" do
        let(:credentials) do
          [
            {
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "registry" => "registry.npmjs.org",
              "token" => "secret_token"
            }
          ]
        end

        it { is_expected.to eq(Gem::Version.new("1.7.0")) }
      end

      context "without credentials" do
        let(:credentials) do
          [
            {
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ]
        end

        it "raises a to Dependabot::PrivateSourceNotReachable error" do
          expect { checker.latest_version }.
            to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
              expect(error.source).to eq("registry.npmjs.org")
            end
        end
      end
    end

    context "for a dependency hosted on another registry" do
      before do
        body = fixture("javascript", "gemfury_response_etag.json")
        stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
          to_return(status: 404, body: "{\"error\":\"Not found\"}")
        stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
          with(headers: { "Authorization" => "Bearer secret_token" }).
          to_return(status: 200, body: body)
        stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep/1.8.1").
          to_return(status: 200)
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@blep/blep",
          version: "1.0.0",
          requirements: [
            {
              file: "package.json",
              requirement: "^1.0.0",
              groups: [],
              source: {
                type: "private_registry",
                url: "https://npm.fury.io/dependabot"
              }
            }
          ],
          package_manager: "npm_and_yarn"
        )
      end

      context "with credentials" do
        let(:credentials) do
          [
            {
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "registry" => "npm.fury.io/dependabot",
              "token" => "secret_token"
            }
          ]
        end

        it { is_expected.to eq(Gem::Version.new("1.8.1")) }

        context "without https" do
          before do
            body = fixture("javascript", "gemfury_response_etag.json")
            stub_request(:get, "https://npm.fury.io/dependabot/@blep%2Fblep").
              with(headers: { "Authorization" => "Bearer secret_token" }).
              to_return(status: 404)
            stub_request(:get, "http://npm.fury.io/dependabot/@blep%2Fblep").
              with(headers: { "Authorization" => "Bearer secret_token" }).
              to_return(status: 200, body: body)
            stub_request(
              :get, "http://npm.fury.io/dependabot/@blep%2Fblep/1.8.1"
            ).to_return(status: 200)
          end

          let(:dependency) do
            Dependabot::Dependency.new(
              name: "@blep/blep",
              version: "1.0.0",
              requirements: [
                {
                  file: "package.json",
                  requirement: "^1.0.0",
                  groups: [],
                  source: {
                    type: "private_registry",
                    url: "http://npm.fury.io/dependabot"
                  }
                }
              ],
              package_manager: "npm_and_yarn"
            )
          end

          it { is_expected.to eq(Gem::Version.new("1.8.1")) }
        end
      end

      context "without credentials" do
        let(:credentials) do
          [
            {
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ]
        end

        it "raises a to Dependabot::PrivateSourceNotReachable error" do
          expect { checker.latest_version }.
            to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
              expect(error.source).to eq("npm.fury.io/dependabot")
            end
        end

        context "with credentials in the .npmrc" do
          let(:dependency_files) { [npmrc] }
          let(:npmrc) do
            Dependabot::DependencyFile.new(
              name: ".npmrc",
              content: fixture("javascript", "npmrc", "auth_token")
            )
          end

          it { is_expected.to eq(Gem::Version.new("1.8.1")) }

          context "that require an environment variable" do
            let(:npmrc) do
              Dependabot::DependencyFile.new(
                name: ".npmrc",
                content: fixture("javascript", "npmrc", "env_auth_token")
              )
            end

            it "raises a to Dependabot::PrivateSourceNotReachable error" do
              expect { checker.latest_version }.
                to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
                  expect(error.source).to eq("npm.fury.io/dependabot")
                end
            end
          end
        end
      end
    end

    context "when the npm link resolves to a redirect" do
      let(:redirect_url) { "https://registry.npmjs.org/eTag" }

      before do
        stub_request(:get, registry_listing_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(
            status: 200,
            body: fixture("javascript", "npm_response.json")
          )
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "when the npm link resolves to an empty hash" do
      before do
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: "{}")
      end

      it { is_expected.to be_nil }
    end

    context "when the npm link fails at first" do
      before do
        body = fixture("javascript", "npm_response_prerelease.json")
        stub_request(:get, registry_listing_url).
          to_raise(Excon::Error::Timeout).then.
          to_return(status: 200, body: body)
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "when the latest version has been yanked" do
      before do
        body = fixture("javascript", "npm_response_old_latest.json")
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: body)
        stub_request(:get, registry_listing_url + "/1.7.0").
          to_return(status: 404)
        stub_request(:get, registry_listing_url + "/1.6.0").
          to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.6.0")) }
    end

    context "when the npm link resolves to a 404" do
      before do
        stub_request(:get, registry_listing_url).
          to_return(status: 404, body: "{\"error\":\"Not found\"}")
      end

      it "raises an error" do
        expect { checker.latest_version }.to raise_error(RuntimeError)
      end

      context "for a namespaced dependency" do
        before do
          stub_request(:get, "https://registry.npmjs.org/@blep%2Fblep").
            to_return(status: 404, body: "{\"error\":\"Not found\"}")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "@blep/blep",
            version: "1.0.0",
            requirements: [
              {
                file: "package.json",
                requirement: "^1.0.0",
                groups: [],
                source: nil
              }
            ],
            package_manager: "npm_and_yarn"
          )
        end

        it "raises a to Dependabot::PrivateSourceNotReachable error" do
          expect { checker.latest_version }.
            to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
              expect(error.source).to eq("registry.npmjs.org")
            end
        end
      end
    end

    context "when the latest version is older than another, non-prerelease" do
      before do
        body = fixture("javascript", "npm_response_old_latest.json")
        stub_request(:get, registry_listing_url).
          to_return(status: 200, body: body)
        stub_request(:get, registry_listing_url + "/1.6.0").
          to_return(status: 200)
      end

      it { is_expected.to eq(Gem::Version.new("1.6.0")) }
    end
  end

  describe "#updated_requirements" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.0",
        requirements: dependency_requirements,
        package_manager: "npm_and_yarn"
      )
    end
    let(:dependency_requirements) do
      [
        {
          file: "package.json",
          requirement: "^1.0.0",
          groups: [],
          source: nil
        }
      ]
    end

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).
        to receive(:new).
        with(
          requirements: dependency_requirements,
          updated_source: nil,
          latest_version: "1.7.0",
          latest_resolvable_version: "1.7.0",
          library: false
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [
            {
              file: "package.json",
              requirement: "^1.7.0",
              groups: [],
              source: nil
            }
          ]
        )
    end
  end
end
