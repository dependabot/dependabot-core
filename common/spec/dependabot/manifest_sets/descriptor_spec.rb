# typed: false
# frozen_string_literal: true

require "json"
require "spec_helper"
require "dependabot/manifest_sets/descriptor"

RSpec.describe Dependabot::ManifestSets::Descriptor do
  let(:identity) { { ecosystem: "pypi", directory: "api", owner: "pip", graph_version: "1" } }

  def input(path, oid = "1" * 40)
    Dependabot::ManifestSets::InputFile.new(path: path, blob_oid: oid)
  end

  it "encodes a present set as a JSON string with its files" do
    descriptor = described_class.present(**identity, files: [input("api/requirements.txt")])

    expect(JSON.parse(descriptor.to_json_string)).to eq(
      "schema_version" => 1,
      "ecosystem" => "pypi",
      "directory" => "api",
      "owner" => "pip",
      "graph_version" => "1",
      "state" => "present",
      "files" => [{ "path" => "api/requirements.txt", "blob_oid" => "1" * 40 }]
    )
  end

  it "keeps an explicit empty file list for an absent set" do
    expect(described_class.absent(**identity).to_h).to include("state" => "absent", "files" => [])
    expect(described_class.absent(**identity).to_h).not_to have_key("reason")
  end

  it "refuses a present set without inputs" do
    expect { described_class.present(**identity, files: []) }.to raise_error(ArgumentError)
  end

  describe "limits" do
    it "accepts exactly the maximum number of files" do
      files = Array.new(described_class::MAX_FILES) { |i| input(format("api/r%04d.txt", i)) }

      expect(described_class.present(**identity, files: files).files.length).to eq(described_class::MAX_FILES)
    end

    it "is unresolvable, not truncated, with one file too many" do
      files = Array.new(described_class::MAX_FILES + 1) { |i| input(format("api/r%04d.txt", i)) }

      descriptor = described_class.present(**identity, files: files)

      expect(descriptor.to_h).to include("state" => "unresolvable", "reason" => "input_limit")
      expect(descriptor.to_h).not_to have_key("files")
    end

    it "is unresolvable when a path is too long" do
      files = [input("api/#{'a' * described_class::MAX_PATH_BYTES}")]

      expect(described_class.present(**identity, files: files).reason).to eq("input_limit")
    end

    it "is unresolvable when the encoded envelope is too large" do
      long = "a" * (described_class::MAX_PATH_BYTES - 10)
      count = (described_class::MAX_ENCODED_BYTES / described_class::MAX_PATH_BYTES) + 1
      files = Array.new(count) { |i| input(format("api/%04d#{long}", i)) }

      expect(described_class.present(**identity, files: files).reason).to eq("input_limit")
    end
  end
end
