# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/elixir/hex"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Elixir::Hex do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.3.0",
      requirements: [
        {
          file: "mix.exs",
          requirement: "~> 1.2",
          groups: [],
          source: nil
        }
      ],
      package_manager: "hex"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end
  let(:dependency_name) { "phoenix" }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }
    let(:hex_url) { "https://hex.pm/api/packages/phoenix" }

    before do
      stub_request(:get, hex_url).to_return(status: 200, body: hex_response)
    end

    context "when there is a github link in the hex.pm response" do
      let(:hex_response) do
        fixture("elixir", "registry_api", "phoenix_response.json")
      end

      it { is_expected.to eq("https://github.com/phoenixframework/phoenix") }

      it "caches the call to hex.pm" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, hex_url).once
      end
    end

    context "when there is no recognised source link in the hex.pm response" do
      let(:hex_response) do
        fixture("elixir", "registry_api", "phoenix_response_no_source.json")
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
        fixture("elixir", "registry_api", "phoenix_response.json")
      end

      before do
        stub_request(:get, hex_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: hex_response)
      end

      it { is_expected.to eq("https://github.com/phoenixframework/phoenix") }
    end
  end
end
