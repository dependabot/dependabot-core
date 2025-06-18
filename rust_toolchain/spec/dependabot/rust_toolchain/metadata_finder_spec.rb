# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/source"

require "dependabot/rust_toolchain/metadata_finder"

RSpec.describe Dependabot::RustToolchain::MetadataFinder do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "rust-toolchain",
      version: "1.72.0",
      package_manager: "rust_toolchain",
      requirements: []
    )
  end
  let(:metadata_finder) { described_class.new(dependency: dependency, credentials: []) }

  describe "#source_url" do
    subject(:source) { metadata_finder.source_url }

    it "returns the correct source URL" do
      expect(source).to eq("https://github.com/rust-lang/rust")
    end
  end
end
