# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/java_script/yarn"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::JavaScript::Yarn do
  it_behaves_like "an update checker"

  before do
    stub_request(:get, "https://registry.npmjs.org/etag").
      to_return(status: 200, body: fixture("javascript", "npm_response.json"))
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
      package_manager: "yarn"
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
            package_manager: "yarn"
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
          package_manager: "yarn"
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
            package_manager: "yarn"
          )
        end

        context "and a requirement that exactly matches" do
          let(:requirement) { "^1.7.0" }
          it { is_expected.to be_falsey }
        end

        context "and a requirement that covers but doesn't exactly match" do
          # TODO: Arguably, we might want this to return false (to reduce the
          # number of PRs repos without a lockfile receive).
          let(:requirement) { "^1.6.0" }
          it { is_expected.to be_truthy }
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
          package_manager: "yarn"
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

    context "when the latest version is a prerelease" do
      before do
        body = fixture("javascript", "npm_response_prerelease.json")
        stub_request(:get, "https://registry.npmjs.org/etag").
          to_return(status: 200, body: body)
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }

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
            package_manager: "yarn"
          )
        end

        it { is_expected.to eq(Gem::Version.new("2.0.0.pre.rc1")) }
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
          package_manager: "yarn"
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
          package_manager: "yarn"
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
              package_manager: "yarn"
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
        stub_request(:get, "https://registry.npmjs.org/etag").
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(
            status: 200,
            body: fixture("javascript", "npm_response.json")
          )
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "when the npm link fails at first" do
      before do
        body = fixture("javascript", "npm_response_prerelease.json")
        stub_request(:get, "https://registry.npmjs.org/etag").
          to_raise(Excon::Error::Timeout).then.
          to_return(status: 200, body: body)
      end

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "when the npm link resolves to a 404" do
      before do
        stub_request(:get, "https://registry.npmjs.org/etag").
          to_return(status: 404, body: "{\"error\":\"Not found\"}")
      end

      it "raises an error" do
        # TODO: This should raise a better error
        expect { checker.latest_version }.to raise_error(NoMethodError)
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
            package_manager: "yarn"
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
        stub_request(:get, "https://registry.npmjs.org/etag").
          to_return(status: 200, body: body)
      end

      it { is_expected.to eq(Gem::Version.new("1.6.0")) }
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "etag",
        version: "1.0.0",
        requirements: [
          {
            file: "package.json",
            requirement: original_requirement,
            groups: [],
            source: nil
          }
        ],
        package_manager: "yarn"
      )
    end

    let(:original_requirement) { "^1.0.0" }
    let(:latest_resolvable_version) { nil }

    before do
      allow(checker).
        to receive(:latest_resolvable_version).
        and_return(latest_resolvable_version)
    end

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }
      its([:requirement]) { is_expected.to eq(original_requirement) }
    end

    context "when there is a resolvable version" do
      let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

      context "and a full version was previously specified" do
        let(:original_requirement) { "1.2.3" }
        its([:requirement]) { is_expected.to eq("1.5.0") }
      end

      context "and a partial version was previously specified" do
        let(:original_requirement) { "0.1" }
        its([:requirement]) { is_expected.to eq("1.5") }
      end

      context "and only the major part was previously specified" do
        let(:original_requirement) { "1" }
        let(:latest_resolvable_version) { Gem::Version.new("4.5.0") }
        its([:requirement]) { is_expected.to eq("4") }
      end

      context "and the new version has fewer digits than the old one§" do
        let(:original_requirement) { "1.1.0.1" }
        its([:requirement]) { is_expected.to eq("1.5.0") }
      end

      context "and the new version has much fewer digits than the old one§" do
        let(:original_requirement) { "1.1.0.1" }
        let(:latest_resolvable_version) { Gem::Version.new("4") }
        its([:requirement]) { is_expected.to eq("4") }
      end

      context "and a caret was previously specified" do
        let(:original_requirement) { "^1.2.3" }
        its([:requirement]) { is_expected.to eq("^1.5.0") }
      end

      context "and a pre-release was previously specified" do
        let(:original_requirement) { "^1.2.3-rc1" }
        its([:requirement]) { is_expected.to eq("^1.5.0") }
      end

      context "and a pre-release was previously specified with four places" do
        let(:original_requirement) { "^1.2.3.rc1" }
        its([:requirement]) { is_expected.to eq("^1.5.0") }
      end

      context "and an x.x was previously specified" do
        let(:original_requirement) { "^0.x.x" }
        its([:requirement]) { is_expected.to eq("^1.x.x") }
      end

      context "and an x.x was previously specified with four places" do
        let(:original_requirement) { "^0.x.x.rc1" }
        its([:requirement]) { is_expected.to eq("^1.x.x") }
      end

      context "and there were multiple requirements" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "etag",
            version: "1.0.0",
            requirements: [
              {
                file: "package.json",
                requirement: original_requirement,
                groups: [],
                source: nil
              },
              {
                file: "another/package.json",
                requirement: other_requirement,
                groups: [],
                source: nil
              }
            ],
            package_manager: "yarn"
          )
        end
        let(:original_requirement) { "^1.2.3" }
        let(:other_requirement) { "^0.x.x" }

        it "updates both requirements" do
          expect(checker.updated_requirements).to match_array(
            [
              {
                file: "package.json",
                requirement: "^1.5.0",
                groups: [],
                source: nil
              },
              {
                file: "another/package.json",
                requirement: "^1.x.x",
                groups: [],
                source: nil
              }
            ]
          )
        end
      end
    end
  end
end
