# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/tag"

RSpec.describe Dependabot::Docker::Tag do
  describe "#same_but_more_precise?" do
    it "returns true when receiver is the same version as the parameter, just less precise, false otherwise" do
      expect(described_class.new("2.4").same_but_less_precise?(described_class.new("2.4.2"))).to be true
      expect(described_class.new("2.4").same_but_less_precise?(described_class.new("2.42"))).to be false
    end
  end

  describe "MinIO RELEASE tag format" do
    let(:minio_tag) { described_class.new("RELEASE.2025-01-20T14-49-07Z") }
    let(:newer_minio_tag) { described_class.new("RELEASE.2025-02-18T16-25-55Z") }
    let(:older_minio_tag) { described_class.new("RELEASE.2024-12-15T10-30-45Z") }

    describe "#comparable?" do
      it "recognizes MinIO RELEASE tags as comparable" do
        expect(minio_tag.comparable?).to be true
        expect(newer_minio_tag.comparable?).to be true
        expect(older_minio_tag.comparable?).to be true
      end
    end

    describe "#version" do
      it "extracts the timestamp as version" do
        expect(minio_tag.version).to eq("2025-01-20T14-49-07Z")
        expect(newer_minio_tag.version).to eq("2025-02-18T16-25-55Z")
      end
    end

    describe "#prefix" do
      it "identifies RELEASE as prefix" do
        expect(minio_tag.prefix).to eq("RELEASE.")
        expect(newer_minio_tag.prefix).to eq("RELEASE.")
      end
    end

    describe "#suffix" do
      it "has no suffix for MinIO tags" do
        expect(minio_tag.suffix).to be_nil
        expect(newer_minio_tag.suffix).to be_nil
      end
    end

    describe "#format" do
      it "identifies MinIO tags as timestamp format" do
        expect(minio_tag.format).to eq(:release_timestamp)
        expect(newer_minio_tag.format).to eq(:release_timestamp)
      end
    end

    describe "#numeric_version" do
      it "extracts numeric version for comparison" do
        expect(minio_tag.numeric_version).to eq("2025-01-20T14-49-07Z")
        expect(newer_minio_tag.numeric_version).to eq("2025-02-18T16-25-55Z")
      end
    end

    describe "#comparable_to?" do
      it "can compare MinIO tags with same format" do
        expect(minio_tag.comparable_to?(newer_minio_tag)).to be true
        expect(newer_minio_tag.comparable_to?(minio_tag)).to be true
      end

      it "cannot compare MinIO tags with different formats" do
        normal_tag = described_class.new("1.2.3")
        expect(minio_tag.comparable_to?(normal_tag)).to be false
        expect(normal_tag.comparable_to?(minio_tag)).to be false
      end
    end

    describe "#canonical?" do
      it "treats MinIO tags as canonical" do
        expect(minio_tag.canonical?).to be true
        expect(newer_minio_tag.canonical?).to be true
      end
    end
  end

  describe "edge cases for RELEASE format" do
    it "handles different timestamp formats correctly" do
      # Test various valid timestamp formats
      tag1 = described_class.new("RELEASE.2025-01-01T00-00-00Z")
      tag2 = described_class.new("RELEASE.2025-12-31T23-59-59Z")
      
      expect(tag1.comparable?).to be true
      expect(tag2.comparable?).to be true
      expect(tag1.comparable_to?(tag2)).to be true
    end

    it "does not match invalid RELEASE formats" do
      # Should not match if format is wrong
      invalid_tag = described_class.new("RELEASE-2025-01-20T14-49-07Z") # hyphen instead of period
      expect(invalid_tag.comparable?).to be false
    end

    it "does not interfere with other versioning schemes" do
      # Ensure existing behavior is preserved
      normal_tag = described_class.new("2.4.2")
      prefixed_tag = described_class.new("alpine-3.15")
      
      expect(normal_tag.comparable?).to be true
      expect(prefixed_tag.comparable?).to be true
      expect(normal_tag.format).to eq(:normal)
    end
  end
end
