# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/java_script/npm_and_yarn"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::JavaScript::NpmAndYarn do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.0",
      requirements: [
        { file: "package.json", requirement: "^1.0", groups: [], source: nil }
      ],
      package_manager: "npm_and_yarn"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:credentials) do
    [
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end
  let(:dependency_name) { "etag" }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }
    let(:npm_url) { "https://registry.npmjs.org/etag" }

    before do
      stub_request(:get, npm_url).to_return(status: 200, body: npm_response)
    end

    context "for a git dependency" do
      let(:npm_response) { nil }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "d5ac0584ee9ae7bd9288220a39780f155b9ad4c8",
          requirements: [
            {
              file: "package.json",
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/jshttp/etag",
                branch: nil,
                ref: "master"
              }
            }
          ],
          package_manager: "npm_and_yarn"
        )
      end

      it { is_expected.to eq("https://github.com/jshttp/etag") }

      it "doesn't hit npm" do
        source_url
        expect(WebMock).to_not have_requested(:get, npm_url)
      end
    end

    context "when there is a github link in the npm response" do
      let(:npm_response) { fixture("javascript", "npm_responses", "etag.json") }

      it { is_expected.to eq("https://github.com/jshttp/etag") }

      it "caches the call to npm" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there is a bitbucket link in the npm response" do
      let(:npm_response) do
        fixture("javascript", "npm_response_bitbucket.json")
      end

      it { is_expected.to eq("https://bitbucket.org/jshttp/etag") }

      it "caches the call to npm" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there's a link without the expected structure" do
      let(:npm_response) do
        fixture("javascript", "npm_response_string_link.json")
      end

      it { is_expected.to eq("https://github.com/jshttp/etag") }

      it "caches the call to npm" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there isn't a source link in the npm response" do
      let(:npm_response) do
        fixture("javascript", "npm_response_no_source.json")
      end

      it { is_expected.to be_nil }

      it "caches the call to npm" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when the npm link resolves to a redirect" do
      let(:redirect_url) { "https://registry.npmjs.org/eTag" }
      let(:npm_response) { fixture("javascript", "npm_responses", "etag.json") }

      before do
        stub_request(:get, npm_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: npm_response)
      end

      it { is_expected.to eq("https://github.com/jshttp/etag") }
    end

    context "when the npm link 404s" do
      before { stub_request(:get, npm_url).to_return(status: 404) }
      let(:npm_response) { fixture("javascript", "npm_responses", "etag.json") }

      # Not an idea error, but this should never happen
      specify { expect { finder.source_url }.to raise_error(JSON::ParserError) }
    end

    context "for a scoped package name" do
      before do
        stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag").
          to_return(status: 200, body: npm_response)
      end
      let(:dependency_name) { "@etag/etag" }
      let(:npm_response) { fixture("javascript", "npm_responses", "etag.json") }

      it "requests the escaped name" do
        finder.source_url

        expect(WebMock).
          to have_requested(:get,
                            "https://registry.npmjs.org/@etag%2Fetag")
      end

      context "that is private" do
        before do
          stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag").
            to_return(status: 404, body: "{\"error\":\"Not found\"}")
          stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 200, body: npm_response)
        end

        context "with credentials" do
          let(:credentials) do
            [
              {
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              },
              {
                "type" => "npm_registry",
                "registry" => "registry.npmjs.org",
                "token" => "secret_token"
              }
            ]
          end

          it { is_expected.to eq("https://github.com/jshttp/etag") }
        end

        context "without credentials" do
          before do
            stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag").
              with(headers: { "Authorization" => "Bearer secret_token" }).
              to_return(status: 404)
          end

          it { is_expected.to be_nil }
        end
      end

      context "that is hosted on gemfury" do
        before do
          body = fixture("javascript", "gemfury_response_etag.json")
          stub_request(:get, "https://npm.fury.io/dependabot/@etag%2Fetag").
            to_return(status: 404, body: "{\"error\":\"Not found\"}")
          stub_request(:get, "https://npm.fury.io/dependabot/@etag%2Fetag").
            with(headers: { "Authorization" => "Bearer secret_token" }).
            to_return(status: 200, body: body)
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
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              },
              {
                "type" => "npm_registry",
                "registry" => "npm.fury.io/dependabot",
                "token" => "secret_token"
              }
            ]
          end

          it { is_expected.to eq("https://github.com/jshttp/etag") }
        end

        context "without credentials" do
          before do
            stub_request(:get, "https://registry.npmjs.org/@etag%2Fetag").
              with(headers: { "Authorization" => "Bearer secret_token" }).
              to_return(status: 404)
          end

          it { is_expected.to be_nil }
        end
      end
    end
  end

  describe "#homepage_url" do
    subject(:homepage_url) { finder.homepage_url }
    let(:npm_url) { "https://registry.npmjs.org/etag" }

    before do
      stub_request(:get, npm_url).to_return(status: 200, body: npm_response)
    end

    context "when there is a homepage link in the npm response" do
      let(:npm_response) do
        fixture("javascript", "npm_response_no_source.json")
      end

      it "returns the specified homepage" do
        expect(homepage_url).to eq("https://example.come/jshttp/etag")
      end
    end
  end
end
