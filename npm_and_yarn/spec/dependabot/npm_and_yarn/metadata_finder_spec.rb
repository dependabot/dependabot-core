# typed: false
# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/npm_and_yarn/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::NpmAndYarn::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:dependency_name) { "etag" }
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.6.0",
      requirements: [
        { file: "package.json", requirement: "^1.0", groups: [], source: nil }
      ],
      package_manager: "npm_and_yarn"
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    let(:npm_url) { "https://registry.npmjs.org/etag" }

    before do
      stub_request(:get, npm_url + "/latest")
        .to_return(status: 200, body: npm_latest_version_response)
      stub_request(:get, npm_url)
        .to_return(status: 200, body: npm_all_versions_response)
      stub_request(:get, "https://example.come/status").to_return(
        status: 200,
        body: "Not GHES",
        headers: {}
      )
      stub_request(:get, "https://jshttp/status").to_return(status: 404)
    end

    context "when dealing with a git dependency" do
      let(:npm_all_versions_response) { nil }
      let(:npm_latest_version_response) { nil }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8",
          requirements: [{
            file: "package.json",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/jshttp/etag",
              branch: nil,
              ref: "master"
            }
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it { is_expected.to eq("https://github.com/jshttp/etag") }

      it "doesn't hit npm" do
        source_url
        expect(WebMock).not_to have_requested(:get, npm_url)
      end
    end

    context "when there is a github link in the npm response" do
      let(:npm_latest_version_response) do
        fixture("npm_responses", "etag-1.0.0.json")
      end
      let(:npm_all_versions_response) do
        fixture("npm_responses", "etag.json")
      end

      it { is_expected.to eq("https://github.com/jshttp/etag") }

      it "caches the call to npm" do
        2.times { source_url }
        expect(WebMock)
          .to have_requested(:get, npm_url + "/latest").once
        expect(WebMock)
          .not_to have_requested(:get, npm_url)
      end

      context "with a monorepo that specifies a directory" do
        let(:npm_latest_version_response) do
          fixture("npm_responses", "react-dom-with-dir.json")
        end
        let(:npm_all_versions_response) do
          fixture("npm_responses", "react-dom.json")
        end

        it "includes details of the directory" do
          expect(source_url).to eq(
            "https://github.com/facebook/react/tree/HEAD/packages/react-dom"
          )
        end
      end
    end

    context "when there is a bitbucket link in the npm response" do
      let(:npm_latest_version_response) { nil }
      let(:npm_all_versions_response) do
        fixture("npm_responses", "npm_response_bitbucket.json")
      end

      it { is_expected.to eq("https://bitbucket.org/jshttp/etag") }

      it "caches the call to npm" do
        2.times { source_url }
        expect(WebMock)
          .to have_requested(:get, npm_url + "/latest").once
        expect(WebMock)
          .to have_requested(:get, npm_url).once
      end
    end

    context "when there's a link without the expected structure" do
      let(:npm_latest_version_response) { nil }
      let(:npm_all_versions_response) do
        fixture("npm_responses", "npm_response_string_link.json")
      end

      it { is_expected.to eq("https://github.com/jshttp/etag") }

      it "caches the call to npm" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there's a link using GitHub shorthand" do
      let(:npm_latest_version_response) { nil }
      let(:npm_all_versions_response) do
        fixture("npm_responses", "npm_response_string_shorthand.json")
      end

      it { is_expected.to eq("https://github.com/jshttp/etag") }

      it "caches the call to npm" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there isn't a source link in the npm response" do
      let(:npm_latest_version_response) { nil }
      let(:npm_all_versions_response) do
        fixture("npm_responses", "npm_response_no_source.json")
      end

      it { is_expected.to be_nil }

      it "caches the call to npm" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when the npm link resolves to a redirect" do
      let(:redirect_url) { "https://registry.npmjs.org/eTag" }
      let(:npm_latest_version_response) { nil }
      let(:npm_all_versions_response) { fixture("npm_responses", "etag.json") }

      before do
        stub_request(:get, npm_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(status: 200, body: npm_all_versions_response)
      end

      it { is_expected.to eq("https://github.com/jshttp/etag") }
    end

    context "when the npm link 404s" do
      before do
        stub_request(:get, npm_url).to_return(status: 404)
        stub_request(:get, npm_url + "/latest").to_return(status: 404)
        stub_request(:get, npm_url + "/latest").to_return(status: 404)
      end

      let(:npm_latest_version_response) { nil }
      let(:npm_all_versions_response) { fixture("npm_responses", "etag.json") }

      # Not an ideal error, but this should never happen
      specify { expect { finder.source_url }.to raise_error(JSON::ParserError) }
    end

    context "when dealing with a scoped package name" do
      before do
        stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag/latest")
          .to_return(status: 200, body: npm_latest_version_response)
        stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag")
          .to_return(status: 200, body: npm_all_versions_response)
      end

      let(:dependency_name) { "@etag/etag" }
      let(:npm_latest_version_response) { nil }
      let(:npm_all_versions_response) { fixture("npm_responses", "etag.json") }

      it "requests the escaped name" do
        finder.source_url

        expect(WebMock)
          .to have_requested(:get, "https://registry.npmjs.org/@etag%2Fetag")
      end

      context "when registry is private" do
        before do
          stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag")
            .to_return(status: 404, body: '{"error":"Not found"}')
          stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag")
            .with(headers: { "Authorization" => "Bearer secret_token" })
            .to_return(status: 200, body: npm_all_versions_response)
        end

        context "with credentials" do
          let(:credentials) do
            [
              Dependabot::Credential.new({
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }),
              Dependabot::Credential.new({
                "type" => "npm_registry",
                "registry" => "registry.npmjs.org",
                "token" => "secret_token"
              })
            ]
          end

          it { is_expected.to eq("https://github.com/jshttp/etag") }
        end

        context "without credentials" do
          before do
            stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag")
              .with(headers: { "Authorization" => "Bearer secret_token" })
              .to_return(status: 404)
          end

          it { is_expected.to be_nil }
        end
      end

      context "when dependency is hosted on gemfury" do
        before do
          body = fixture("gemfury_responses", "gemfury_response_etag.json")
          stub_request(:get, "https://npm.fury.io/dependabot/@etag%2Fetag")
            .to_return(status: 404, body: '{"error":"Not found"}')
          stub_request(
            :get, "https://npm.fury.io/dependabot/@etag%2Fetag/latest"
          ).to_return(status: 404, body: '{"error":"Not found"}')
          stub_request(
            :get, "https://npm.fury.io/dependabot/@etag%2Fetag/latest"
          ).to_return(status: 404, body: '{"error":"Not found"}')
          stub_request(:get, "https://npm.fury.io/dependabot/@etag%2Fetag")
            .with(headers: { "Authorization" => "Bearer secret_token" })
            .to_return(status: 200, body: body)
        end

        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "1.0",
            requirements: [{
              file: "package.json",
              requirement: "^1.0",
              groups: [],
              source: {
                type: "registry",
                url: "https://npm.fury.io/dependabot"
              }
            }],
            package_manager: "npm_and_yarn"
          )
        end

        context "with credentials" do
          let(:credentials) do
            [
              Dependabot::Credential.new({
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }),
              Dependabot::Credential.new({
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot",
                "token" => "secret_token"
              })
            ]
          end

          it { is_expected.to eq("https://github.com/jshttp/etag") }
        end

        context "without credentials" do
          before do
            stub_request(
              :get, "https://registry.npmjs.org/@etag%2Fetag/latest"
            ).with(headers: { "Authorization" => "Bearer secret_token" })
              .to_return(status: 404)
            stub_request(
              :get, "https://registry.npmjs.org/@etag%2Fetag/latest"
            ).with(headers: { "Authorization" => "Bearer secret_token" })
              .to_return(status: 404)
            stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag")
              .with(headers: { "Authorization" => "Bearer secret_token" })
              .to_return(status: 404)
          end

          it { is_expected.to be_nil }
        end
      end
    end

    context "when multiple sources are detected" do
      let(:npm_latest_version_response) { nil }
      let(:npm_all_versions_response) { nil }
      let(:dependency_name) { "@etag/etag" }

      let(:credentials) do
        [
          Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }),
          Dependabot::Credential.new({
            "type" => "npm_registry",
            "registry" => "npm.fury.io/dependabot",
            "token" => "secret_token"
          })
        ]
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "1.0",
          requirements: [
            {
              file: "package.json",
              requirement: "^1.0",
              groups: [],
              source: {
                type: "registry",
                url: "https://registry.npmjs.org"
              }
            },
            {
              file: "package.json",
              requirement: "^1.0",
              groups: [],
              source: {
                type: "registry",
                url: "https://npm.fury.io/dependabot"
              }
            }
          ],
          package_manager: "npm_and_yarn"
        )
      end

      before do
        stub_request(
          :get, "https://npm.fury.io/dependabot/@etag%2Fetag/latest"
        ).to_return(status: 404, body: '{"error":"Not found"}').times(2)

        stub_request(:get, "https://npm.fury.io/dependabot/@etag%2Fetag")
          .with(headers: { "Authorization" => "Bearer secret_token" })
          .to_return(
            status: 200,
            body: fixture("gemfury_responses", "gemfury_response_etag.json")
          )
      end

      it "prefers to fetch metadata from the private registry" do
        expect(source_url).to eq("https://github.com/jshttp/etag")
      end
    end
  end

  describe "#homepage_url" do
    subject(:homepage_url) { finder.homepage_url }

    let(:npm_url) { "https://registry.npmjs.org/etag" }

    before do
      stub_request(:get, npm_url + "/latest")
        .to_return(status: 200, body: npm_latest_version_response)
      stub_request(:get, npm_url)
        .to_return(status: 200, body: npm_all_versions_response)
    end

    context "when there is a homepage link in the npm response" do
      let(:npm_all_versions_response) do
        fixture("npm_responses", "npm_response_no_source.json")
      end
      let(:npm_latest_version_response) { nil }

      it "returns the specified homepage" do
        expect(homepage_url).to eq("https://example.come/jshttp/etag")
      end
    end
  end

  describe "#maintainer_changes" do
    subject(:maintainer_changes) { finder.maintainer_changes }

    let(:npm_url) { "https://registry.npmjs.org/etag" }
    let(:npm_all_versions_response) do
      fixture("npm_responses", "etag.json")
    end

    before do
      stub_request(:get, npm_url)
        .to_return(status: 200, body: npm_all_versions_response)
    end

    context "when the user that pushed this version has pushed before" do
      it { is_expected.to be_nil }
    end

    context "when the user that pushed this version hasn't pushed before" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "1.6.0",
          previous_version: "1.0.0",
          requirements: [{
            file: "package.json",
            requirement: "^1.0",
            groups: [],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it "gives details of the new releaser" do
        expect(maintainer_changes).to eq(
          "This version was pushed to npm by " \
          "[dougwilson](https://www.npmjs.com/~dougwilson), a new releaser " \
          "for etag since your current version."
        )
      end
    end
  end
end
