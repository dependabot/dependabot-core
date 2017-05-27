# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "bump/dependency"
require "bump/dependency_metadata_finders/java_script/yarn"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Bump::DependencyMetadataFinders::JavaScript::Yarn do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Bump::Dependency.new(
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

  describe "#github_repo" do
    subject(:github_repo) { finder.github_repo }
    let(:npm_url) { "http://registry.npmjs.org/etag" }

    before do
      stub_request(:get, npm_url).to_return(status: 200, body: npm_response)
    end

    context "when there is a github link in the npm response" do
      let(:npm_response) { fixture("javascript", "npm_response.json") }

      it { is_expected.to eq("jshttp/etag") }

      it "caches the call to npm" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there's a link without the expected structure" do
      let(:npm_response) do
        fixture("javascript", "npm_response_string_link.json")
      end

      it { is_expected.to eq("jshttp/etag") }

      it "caches the call to npm" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there isn't a github link in the npm response" do
      let(:npm_response) do
        fixture("javascript", "npm_response_no_github.json")
      end

      it { is_expected.to be_nil }

      it "caches the call to npm" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when the npm link resolves to a redirect" do
      let(:redirect_url) { "http://registry.npmjs.org/eTag" }
      let(:npm_response) { fixture("javascript", "npm_response.json") }

      before do
        stub_request(:get, npm_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: npm_response)
      end

      it { is_expected.to eq("jshttp/etag") }
    end

    context "for a scoped package name" do
      before do
        stub_request(:get, "http://registry.npmjs.org/@etag%2Fsomething").
          to_return(status: 200, body: npm_response)
      end
      let(:dependency_name) { "@etag/something" }
      let(:npm_response) { fixture("javascript", "npm_response.json") }

      it "requests the escaped name" do
        finder.github_repo

        expect(WebMock).
          to have_requested(:get, "http://registry.npmjs.org/@etag%2Fsomething")
      end
    end
  end
end
