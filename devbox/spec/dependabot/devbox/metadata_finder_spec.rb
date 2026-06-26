# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders"
require "dependabot/devbox/metadata_finder"

RSpec.describe Dependabot::Devbox::MetadataFinder do
  let(:finder) { described_class.new(dependency: dependency, credentials: credentials) }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "ripgrep",
      version: "14.1.0",
      requirements: [{
        requirement: "latest",
        file: "devbox.json",
        groups: [],
        source: { type: "nixhub" }
      }],
      package_manager: "devbox"
    )
  end
  let(:search_url) { "https://search.devbox.sh/v1/search?q=ripgrep" }

  def stub_nixhub(homepage)
    stub_request(:get, search_url).to_return(
      status: 200,
      body: {
        packages: [
          { name: "ripgrep", versions: [{ version: "14.1.0", homepage: homepage }] }
        ]
      }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  it "is registered for the devbox package manager" do
    expect(Dependabot::MetadataFinders.for_package_manager("devbox")).to eq(described_class)
  end

  context "when the homepage is a git host URL" do
    before { stub_nixhub("https://github.com/BurntSushi/ripgrep") }

    it "derives the source from the homepage" do
      expect(finder.source_url).to eq("https://github.com/BurntSushi/ripgrep")
    end
  end

  context "when the homepage is not a recognised git host" do
    before { stub_nixhub("https://www.python.org") }

    it "returns no source" do
      expect(finder.source_url).to be_nil
    end
  end

  context "when the package has no homepage" do
    before { stub_nixhub(nil) }

    it "returns no source" do
      expect(finder.source_url).to be_nil
    end
  end

  context "when the registry request times out" do
    before { stub_request(:get, search_url).to_timeout }

    it "returns no source" do
      expect(finder.source_url).to be_nil
    end
  end
end
