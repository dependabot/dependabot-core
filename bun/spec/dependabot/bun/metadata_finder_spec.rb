# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Bun::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  it_behaves_like "a dependency metadata finder"

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
