# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/julia/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Julia::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:dependency) do
    # Use the real Example package for testing
    Dependabot::Dependency.new(
      name: "Example",
      version: "0.4.1",
      requirements: requirements,
      package_manager: "julia",
      metadata: { julia_uuid: "7876af07-990d-54b4-ab0e-23690620f79a" }
    )
  end
  let(:dependency_name) { "Example" }
  let(:requirements) { [] } # Simplified
  let(:credentials) { [] } # Simplified

  # NOTE: The "a dependency metadata finder" shared example validates basic contract compliance.
  # Julia's MetadataFinder implements the required methods, returning nil for unavailable data
  # which satisfies the shared example's expectations.
  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "when using real Example package" do
      it "returns the actual source URL from Julia helper" do
        # This should call the real Julia helper and get the actual source URL
        expect(source_url).to eq("https://github.com/JuliaLang/Example.jl")
      end
    end

    context "when package has no UUID" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Example",
          version: "0.4.1",
          requirements: requirements,
          package_manager: "julia"
          # No metadata with UUID
        )
      end

      it "returns nil due to missing UUID" do
        expect(source_url).to be_nil
      end
    end

    context "when package has invalid UUID" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Example",
          version: "0.4.1",
          requirements: requirements,
          package_manager: "julia",
          metadata: { julia_uuid: "invalid-uuid" }
        )
      end

      it "returns nil due to invalid UUID" do
        expect(source_url).to be_nil
      end
    end

    context "when package does not exist" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "NonExistentPackage999",
          version: "1.0.0",
          requirements: requirements,
          package_manager: "julia",
          metadata: { julia_uuid: "00000000-0000-0000-0000-000000000000" }
        )
      end

      it "returns nil for non-existent package" do
        expect(source_url).to be_nil
      end
    end
  end

  # NOTE: Additional metadata methods like changelog_url, commit_sha_for_tag, etc.
  # are inherited from the base class and return nil/default values as appropriate.
  # These are covered by the shared example tests above.
end
