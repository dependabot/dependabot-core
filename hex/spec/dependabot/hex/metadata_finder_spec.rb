# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/hex/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Hex::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:dependency_source) { nil }
  let(:dependency_name) { "phoenix" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.3.0",
      requirements: [{
        file: "mix.exs",
        requirement: "~> 1.2",
        groups: [],
        source: dependency_source
      }],
      package_manager: "hex"
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    let(:hex_url) { "https://hex.pm/api/packages/phoenix" }

    before do
      stub_request(:get, hex_url).to_return(status: 200, body: hex_response)

      stub_request(:get, "https://example.com/status").to_return(
        status: 200,
        body: "Not GHES",
        headers: {}
      )
    end

    context "when there is a github link in the hex.pm response" do
      let(:hex_response) do
        fixture("registry_api", "phoenix_response.json")
      end

      it { is_expected.to eq("https://github.com/phoenixframework/phoenix") }

      it "caches the call to hex.pm" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, hex_url).once
      end
    end

    context "when there is no recognised source link in the hex.pm response" do
      let(:hex_response) do
        fixture("registry_api", "phoenix_response_no_source.json")
      end

      it { is_expected.to be_nil }

      it "caches the call to hex.pm" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, hex_url).once
      end
    end

    context "when the hex.pm link resolves to a redirect" do
      let(:redirect_url) { "https://hex.pm/api/packages/Phoenix" }
      let(:hex_response) do
        fixture("registry_api", "phoenix_response.json")
      end

      before do
        stub_request(:get, hex_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(status: 200, body: hex_response)
      end

      it { is_expected.to eq("https://github.com/phoenixframework/phoenix") }
    end

    context "when using a git source" do
      let(:hex_response) { nil }
      let(:dependency_source) do
        { type: "git", url: "https://github.com/my_fork/phoenix" }
      end

      it { is_expected.to eq("https://github.com/my_fork/phoenix") }

      context "when it doesn't match a supported source" do
        let(:dependency_source) do
          { type: "git", url: "https://example.com/my_fork/phoenix" }
        end

        it { is_expected.to be_nil }
      end
    end
  end
end
