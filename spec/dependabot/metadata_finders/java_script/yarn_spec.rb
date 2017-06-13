# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/java_script/yarn"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::JavaScript::Yarn do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.0",
      package_manager: "yarn"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, github_client: github_client)
  end
  let(:github_client) { Octokit::Client.new(access_token: "token") }
  let(:dependency_name) { "etag" }

  describe "#source" do
    subject(:source) { finder.source }
    let(:npm_url) { "https://registry.npmjs.org/etag" }

    before do
      stub_request(:get, npm_url).to_return(status: 200, body: npm_response)
    end

    context "when there is a github link in the npm response" do
      let(:npm_response) { fixture("javascript", "npm_response.json") }

      its(["repo"]) { is_expected.to eq("jshttp/etag") }

      it "caches the call to npm" do
        2.times { source }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there is a bitbucket link in the npm response" do
      let(:npm_response) do
        fixture("javascript", "npm_response_bitbucket.json")
      end

      its(["repo"]) { is_expected.to eq("jshttp/etag") }

      it "caches the call to npm" do
        2.times { source }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there's a link without the expected structure" do
      let(:npm_response) do
        fixture("javascript", "npm_response_string_link.json")
      end

      its(["repo"]) { is_expected.to eq("jshttp/etag") }

      it "caches the call to npm" do
        2.times { source }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there isn't a source link in the npm response" do
      let(:npm_response) do
        fixture("javascript", "npm_response_no_source.json")
      end

      it { is_expected.to be_nil }

      it "caches the call to npm" do
        2.times { source }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when the npm link resolves to a redirect" do
      let(:redirect_url) { "https://registry.npmjs.org/eTag" }
      let(:npm_response) { fixture("javascript", "npm_response.json") }

      before do
        stub_request(:get, npm_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: npm_response)
      end

      its(["repo"]) { is_expected.to eq("jshttp/etag") }
    end

    context "for a scoped package name" do
      before do
        stub_request(:get, "https://registry.npmjs.org/@etag%2Fsomething").
          to_return(status: 200, body: npm_response)
      end
      let(:dependency_name) { "@etag/something" }
      let(:npm_response) { fixture("javascript", "npm_response.json") }

      it "requests the escaped name" do
        finder.source

        expect(WebMock).
          to have_requested(:get,
                            "https://registry.npmjs.org/@etag%2Fsomething")
      end
    end
  end
end
