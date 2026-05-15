# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/nix/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Nix::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { "https://github.com/NixOS/nixpkgs" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "nixpkgs",
      version: "3030f185ba6a4bf4f18b87f345f104e6a6961f34",
      previous_version: "oldsha123",
      requirements: [{
        file: "flake.lock",
        requirement: nil,
        groups: [],
        source: { type: "git", url: url, branch: "nixos-unstable", ref: "nixos-unstable" }
      }],
      previous_requirements: [{
        file: "flake.lock",
        requirement: nil,
        groups: [],
        source: { type: "git", url: url, branch: "nixos-unstable", ref: "nixos-unstable" }
      }],
      package_manager: "nix"
    )
  end

  before do
    stub_request(:get, "https://example.com/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "when the URL is a github one" do
      let(:url) { "https://github.com/NixOS/nixpkgs" }

      it { is_expected.to eq("https://github.com/NixOS/nixpkgs") }
    end

    context "when the URL is a gitlab one" do
      let(:url) { "https://gitlab.com/myorg/myrepo" }

      it { is_expected.to eq("https://gitlab.com/myorg/myrepo") }
    end
  end
end
