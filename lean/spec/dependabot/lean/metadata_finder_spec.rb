# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/lean/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Lean::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "lean4",
      version: "4.26.0",
      requirements: [{
        requirement: "4.26.0",
        file: "lean-toolchain",
        groups: [],
        source: { type: "default" }
      }],
      package_manager: "lake"
    )
  end
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

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    it "returns the Lean GitHub URL" do
      expect(finder.source_url).to eq("https://github.com/leanprover/lean4")
    end
  end
end
