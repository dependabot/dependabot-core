# frozen_string_literal: true

require "spec_helper"
require "dependabot/haskell/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Haskell::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: nil,
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".github/cabals/cabal.yml",
        source: dependency_source
      }],
      package_manager: "haskell"
    )
  end
  let(:dependency_name) { "actions/checkout" }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/actions/checkout",
      ref: "master",
      branch: nil
    }
  end
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

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "for a git source" do
      let(:dependency_source) do
        {
          type: "git",
          url: "https://github.com/actions/checkout",
          ref: "master",
          branch: nil
        }
      end

      it { is_expected.to eq("https://github.com/actions/checkout") }
    end

    context "for a subdependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: nil,
          requirements: [],
          package_manager: "haskell"
        )
      end

      it { is_expected.to eq("https://github.com/actions/checkout") }
    end
  end
end
