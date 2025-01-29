# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dotnet_sdk/metadata_finder"
require "dependabot/source"

RSpec.describe Dependabot::DotnetSdk::MetadataFinder do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "dotnet-sdk",
      version: "8.0.402",
      package_manager: "dotnet_sdk",
      requirements: []
    )
  end
  let(:metadata_finder) { described_class.new(dependency: dependency, credentials: []) }

  describe "#source_url" do
    subject(:source) { metadata_finder.source_url }

    it "returns the correct source URL" do
      expect(source).to eq("https://github.com/dotnet/sdk")
    end
  end
end
