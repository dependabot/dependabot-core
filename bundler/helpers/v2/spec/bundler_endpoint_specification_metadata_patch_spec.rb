# typed: false
# frozen_string_literal: true

require "native_spec_helper"

RSpec.describe BundlerEndpointSpecificationMetadataPatch do
  let(:spec_fetcher) { instance_double(Bundler::Fetcher, uri: URI("https://example.com")) }

  def build_spec(metadata)
    Bundler::EndpointSpecification.new("failbot", "2.0.1", "ruby", spec_fetcher, [], metadata)
  end

  it "does not raise when the registry serves an empty checksum array" do
    expect { build_spec([["checksum", []]]) }.not_to raise_error
  end

  it "leaves the checksum unset for an empty checksum array" do
    spec = build_spec([["checksum", []]])
    expect(spec.checksum).to be_nil
  end

  # The compact-index parser can emit a value-less entry (`["checksum"]`) rather
  # than an empty array, depending on the RubyGems GemParser version. Both shapes
  # reach this code, so both must be tolerated.
  it "does not raise when the checksum entry has no value at all" do
    expect { build_spec([["checksum"]]) }.not_to raise_error
  end

  it "ignores nil and blank metadata values" do
    expect { build_spec([["checksum", nil], ["ruby", []]]) }.not_to raise_error
  end

  it "still parses a well-formed checksum" do
    digest = "f" * 64
    spec = build_spec([["checksum", [digest]]])
    expect(spec.checksum).not_to be_nil
  end

  it "still parses ruby and rubygems requirements" do
    spec = build_spec([["ruby", [">= 3.1"]], ["rubygems", [">= 3.0"]], ["checksum", []]])
    expect(spec.required_ruby_version.to_s).to eq(">= 3.1")
    expect(spec.required_rubygems_version.to_s).to eq(">= 3.0")
  end

  it "still raises on a genuinely malformed (non-empty) checksum" do
    expect { build_spec([["checksum", ["not-a-valid-digest"]]]) }
      .to raise_error(Bundler::GemspecError)
  end
end
