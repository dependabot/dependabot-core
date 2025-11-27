# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/crystal_shards/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::CrystalShards::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "kemal",
      version: "1.0.0",
      requirements: requirements,
      package_manager: "crystal_shards"
    )
  end

  let(:requirements) do
    [{
      file: "shard.yml",
      requirement: "~> 1.0.0",
      groups: ["dependencies"],
      source: {
        type: "git",
        url: "https://github.com/kemalcr/kemal"
      }
    }]
  end

  let(:credentials) { [] }

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    it "returns the source URL from requirements" do
      expect(source_url).to eq("https://github.com/kemalcr/kemal")
    end

    context "when no source is present" do
      let(:requirements) do
        [{
          file: "shard.yml",
          requirement: "~> 1.0.0",
          groups: ["dependencies"],
          source: nil
        }]
      end

      it "returns nil" do
        expect(source_url).to be_nil
      end
    end
  end
end
