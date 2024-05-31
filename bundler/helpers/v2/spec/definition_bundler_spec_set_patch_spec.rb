# typed: false
# frozen_string_literal: true

# rubocop:disable RSpec/FilePath
# rubocop:disable RSpec/SpecFilePathFormat

require "native_spec_helper"
require "shared_contexts"
require "bundler/spec_set"

RSpec.describe Bundler::SpecSet do
  let(:primary_source) { instance_double(Bundler::Source::Git) }
  let(:secondary_source) { instance_double(Bundler::Source::Path) }
  let(:primary_spec_set) do
    instance_double(Bundler::LazySpecification, full_name: "foo-1.0.0-x86_64-linux", source: primary_source)
  end
  let(:secondary_spec_set) do
    instance_double(Bundler::LazySpecification, full_name: "foo-1.0.0-arm64-darwin", source: secondary_source)
  end

  before do
    allow(primary_spec_set).to receive(:is_a?).with(Bundler::LazySpecification).and_return(true)
    allow(secondary_spec_set).to receive(:is_a?).with(Bundler::LazySpecification).and_return(true)

    allow(primary_source).to receive(:cached!)
    allow(primary_source).to receive(:remote!)
    allow(secondary_source).to receive(:cached!)
    allow(secondary_source).to receive(:remote!)

    allow(primary_spec_set).to receive(:materialize_for_installation).and_return(primary_spec_set)
    allow(secondary_spec_set).to receive(:materialize_for_installation).and_return(secondary_spec_set)
  end

  describe "#materialized_for_all_platforms" do
    context "when cache_all_platforms is enabled" do
      let(:spec_set) { described_class.new([primary_spec_set, secondary_spec_set]) }

      before do
        described_class.prepend(BundlerSpecSetPatch)
      end

      it "uses cached gems for secondary sources" do
        expect(primary_spec_set.source).to receive(:cached!).ordered
        expect(primary_spec_set.source).to receive(:remote!).ordered
        expect(primary_spec_set).to receive(:materialize_for_installation).and_return(primary_spec_set).ordered

        expect(secondary_spec_set.source).to receive(:cached!).ordered
        expect(secondary_spec_set.source).to receive(:remote!).ordered
        expect(secondary_spec_set).to receive(:materialize_for_installation).and_return(secondary_spec_set).ordered

        result = spec_set.materialized_for_all_platforms
        expect(result).to include(primary_spec_set, secondary_spec_set)
      end

      it "raises an error if a gem cannot be found in any of the sources" do
        allow(primary_spec_set).to receive(:materialize_for_installation).and_return(nil)

        expect do
          spec_set.materialized_for_all_platforms
        end.to raise_error(Bundler::GemNotFound,
                           "Could not find foo-1.0.0-x86_64-linux in any of the sources")
      end
    end
  end
end

# rubocop:enable RSpec/FilePath
# rubocop:enable RSpec/SpecFilePathFormat
