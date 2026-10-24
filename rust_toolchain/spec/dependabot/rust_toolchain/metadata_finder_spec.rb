# typed: strict
# frozen_string_literal: true

require "spec_helper"

require "dependabot/source"

require "dependabot/rust_toolchain/metadata_finder"

RSpec.describe Dependabot::RustToolchain::MetadataFinder do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "rust-toolchain",
      version: "1.72.0",
      package_manager: "rust_toolchain",
      requirements: []
    )
  end
  sig { returns(Dependabot::RustToolchain::MetadataFinder) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:metadata_finder) { described_class.new(dependency: dependency, credentials: []) }
  # rubocop:enable RSpec/ScatteredLet

  describe "#source_url" do
    sig { returns(T.nilable(String)) }
    subject(:source) { metadata_finder.source_url }

    it "returns the correct source URL" do
      expect(source).to eq("https://github.com/rust-lang/rust")
    end
  end
end
