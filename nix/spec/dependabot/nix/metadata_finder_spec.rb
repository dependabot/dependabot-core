# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/nix/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Nix::MetadataFinder do
  extend T::Sig

  sig { returns(Dependabot::Nix::MetadataFinder) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(T::Array[Dependabot::Credential]) }
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
  sig { returns(String) }
  let(:url) { "https://github.com/NixOS/nixpkgs" }
  sig { returns(Dependabot::Dependency) }
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
  # rubocop:enable RSpec/ScatteredLet

  before do
    stub_request(:get, "https://example.com/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    sig { returns(T.nilable(String)) }
    subject(:source_url) { finder.source_url }

    context "when the URL is a github one" do
      sig { returns(String) }
      let(:url) { "https://github.com/NixOS/nixpkgs" }

      it { is_expected.to eq("https://github.com/NixOS/nixpkgs") }
    end

    context "when the URL is a gitlab one" do
      sig { returns(String) }
      let(:url) { "https://gitlab.com/myorg/myrepo" }

      it { is_expected.to eq("https://gitlab.com/myorg/myrepo") }
    end

    context "when the source is a NixOS channel tarball" do
      sig { returns(Dependabot::Dependency) }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "bd0ff2d3eac24699c3664d5966b9ef36f388e2ca",
          previous_version: "3030f185ba6a4bf4f18b87f345f104e6a6961f34",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            groups: [],
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz",
              branch: nil,
              ref: "nixos-26.05"
            }
          }],
          package_manager: "nix"
        )
      end

      it { is_expected.to eq("https://github.com/NixOS/nixpkgs") }
    end
  end
end
