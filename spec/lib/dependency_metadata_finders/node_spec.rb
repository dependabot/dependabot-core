# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "bump/dependency"
require "bump/dependency_metadata_finders/node"

RSpec.describe Bump::DependencyMetadataFinders::Node do
  let(:dependency) do
    Bump::Dependency.new(
      name: dependency_name,
      version: "1.0",
      language: "node"
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
      stub_request(:get, "http://registry.npmjs.org/etag").
        to_return(status: 200, body: npm_response)
    end

    context "when there is a github link in the npm response" do
      let(:npm_response) { fixture("npm_response.json") }

      it { is_expected.to eq("kesla/etag") }

      it "caches the call to npm" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there's a link without the expected structure" do
      let(:npm_response) { fixture("npm_response_string_link.json") }

      it { is_expected.to eq("kesla/etag") }

      it "caches the call to npm" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end

    context "when there isn't github link in the npm response" do
      let(:npm_response) { fixture("npm_response_no_github.json") }

      it { is_expected.to be_nil }

      it "caches the call to npm" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, npm_url).once
      end
    end
  end
end
