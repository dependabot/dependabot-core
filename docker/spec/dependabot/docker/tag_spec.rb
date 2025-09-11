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

  describe "ISO timestamp tag formats" do
    let(:minio_tag) { described_class.new("RELEASE.2025-01-20T14-49-07Z") }
    let(:newer_minio_tag) { described_class.new("RELEASE.2025-02-18T16-25-55Z") }
    let(:older_minio_tag) { described_class.new("RELEASE.2024-12-15T10-30-45Z") }
    let(:standard_iso_tag) { described_class.new("2025-01-20T14:49:07Z") }
    let(:iso_with_millis) { described_class.new("2025-01-20T14:49:07.123Z") }
    let(:iso_with_timezone) { described_class.new("2025-01-20T14:49:07+00:00") }
    let(:versioned_iso_tag) { described_class.new("v2025-01-20T14:49:07Z") }
    let(:build_iso_tag) { described_class.new("build.2025-01-20T14:49:07Z") }
    let(:date_only_tag) { described_class.new("2025-01-20") }
    let(:prefixed_date_only) { described_class.new("RELEASE.2025-01-20") }
    let(:versioned_date_only) { described_class.new("v2025-01-20") }

    describe "#comparable?" do
      it "recognizes various ISO timestamp formats as comparable" do
        expect(minio_tag.comparable?).to be true
        expect(standard_iso_tag.comparable?).to be true
        expect(iso_with_millis.comparable?).to be true
        expect(iso_with_timezone.comparable?).to be true
        expect(versioned_iso_tag.comparable?).to be true
        expect(build_iso_tag.comparable?).to be true
        expect(date_only_tag.comparable?).to be true
        expect(prefixed_date_only.comparable?).to be true
        expect(versioned_date_only.comparable?).to be true
      end
    end

    describe "#version" do
      it "extracts the timestamp as version from various formats" do
        expect(minio_tag.version).to eq("2025-01-20T14-49-07Z")
        expect(standard_iso_tag.version).to eq("2025-01-20T14:49:07Z")
        expect(iso_with_millis.version).to eq("2025-01-20T14:49:07.123Z")
        expect(iso_with_timezone.version).to eq("2025-01-20T14:49:07+00:00")
        expect(versioned_iso_tag.version).to eq("2025-01-20T14:49:07Z")
        expect(build_iso_tag.version).to eq("2025-01-20T14:49:07Z")
        expect(date_only_tag.version).to eq("2025-01-20")
        expect(prefixed_date_only.version).to eq("2025-01-20")
        expect(versioned_date_only.version).to eq("2025-01-20")
      end
    end

    describe "#prefix" do
      it "identifies various prefixes correctly" do
        expect(minio_tag.prefix).to eq("RELEASE.")
        expect(standard_iso_tag.prefix).to be_nil
        expect(versioned_iso_tag.prefix).to eq("v")
        expect(build_iso_tag.prefix).to eq("build.")
        expect(date_only_tag.prefix).to be_nil
        expect(prefixed_date_only.prefix).to eq("RELEASE.")
        expect(versioned_date_only.prefix).to eq("v")
      end
    end

    describe "#suffix" do
      it "has appropriate suffix handling for ISO tags" do
        expect(minio_tag.suffix).to be_nil
        expect(standard_iso_tag.suffix).to be_nil
        expect(versioned_iso_tag.suffix).to be_nil
      end
    end

    describe "#format" do
      it "identifies all ISO timestamp tags with the same format type" do
        expect(minio_tag.format).to eq(:iso_timestamp)
        expect(standard_iso_tag.format).to eq(:iso_timestamp)
        expect(iso_with_millis.format).to eq(:iso_timestamp)
        expect(iso_with_timezone.format).to eq(:iso_timestamp)
        expect(versioned_iso_tag.format).to eq(:iso_timestamp)
        expect(build_iso_tag.format).to eq(:iso_timestamp)
        expect(date_only_tag.format).to eq(:iso_timestamp)
        expect(prefixed_date_only.format).to eq(:iso_timestamp)
        expect(versioned_date_only.format).to eq(:iso_timestamp)
      end
    end

    describe "#numeric_version" do
      it "normalizes timestamps for comparison" do
        expect(minio_tag.numeric_version).to eq("2025-01-20T14-49-07Z")
        expect(standard_iso_tag.numeric_version).to eq("2025-01-20T14-49-07Z")
        expect(iso_with_millis.numeric_version).to eq("2025-01-20T14-49-07.123Z")
        expect(versioned_iso_tag.numeric_version).to eq("2025-01-20T14-49-07Z")
        expect(date_only_tag.numeric_version).to eq("2025-01-20")
        expect(prefixed_date_only.numeric_version).to eq("2025-01-20")
        expect(versioned_date_only.numeric_version).to eq("2025-01-20")
      end
    end

    describe "#comparable_to?" do
      it "can compare ISO timestamp tags with same format but different prefixes" do
        expect(minio_tag.comparable_to?(standard_iso_tag)).to be true
        expect(standard_iso_tag.comparable_to?(versioned_iso_tag)).to be true
        expect(build_iso_tag.comparable_to?(minio_tag)).to be true
        expect(date_only_tag.comparable_to?(prefixed_date_only)).to be true
        expect(versioned_date_only.comparable_to?(date_only_tag)).to be true
      end

      it "cannot compare ISO timestamp tags with different formats" do
        normal_tag = described_class.new("1.2.3")
        expect(minio_tag.comparable_to?(normal_tag)).to be false
        expect(normal_tag.comparable_to?(standard_iso_tag)).to be false
      end
    end

    describe "#canonical?" do
      it "treats ISO timestamp tags as canonical" do
        expect(minio_tag.canonical?).to be true
        expect(standard_iso_tag.canonical?).to be true
        expect(iso_with_millis.canonical?).to be true
        expect(versioned_iso_tag.canonical?).to be true
        expect(date_only_tag.canonical?).to be true
        expect(prefixed_date_only.canonical?).to be true
        expect(versioned_date_only.canonical?).to be true
      end
    end
  end

  describe "edge cases for ISO timestamp format" do
    it "handles different valid timestamp formats correctly" do
      # Test various valid timestamp formats
      tag1 = described_class.new("2025-01-01T00:00:00Z")
      tag2 = described_class.new("RELEASE.2025-12-31T23-59-59Z")
      tag3 = described_class.new("v2025-06-15T12:30:45.500Z")
      tag4 = described_class.new("build_2025-03-10T08:15:30+05:30")
      # Test date-only formats
      tag5 = described_class.new("2025-01-01")
      tag6 = described_class.new("RELEASE.2025-12-31")
      tag7 = described_class.new("v2025-06-15")

      expect(tag1.comparable?).to be true
      expect(tag2.comparable?).to be true
      expect(tag3.comparable?).to be true
      expect(tag4.comparable?).to be true
      expect(tag5.comparable?).to be true
      expect(tag6.comparable?).to be true
      expect(tag7.comparable?).to be true
      expect(tag1.comparable_to?(tag2)).to be true
      expect(tag5.comparable_to?(tag6)).to be true
    end

    it "does not match invalid timestamp formats as ISO timestamps" do
      # Should not match the ISO timestamp format if format is wrong
      invalid_tag1 = described_class.new("RELEASE-2025-01-20T14-49-07Z") # hyphen instead of period
      invalid_tag2 = described_class.new("25-01-20T14:49:07Z") # invalid year format (2 digits)
      invalid_tag3 = described_class.new("2025-1-20T14:49:07Z") # invalid month format (1 digit)
      invalid_tag4 = described_class.new("2025-01-2T14:49:07Z") # invalid day format (1 digit)
      invalid_tag5 = described_class.new("2025-01-20T1:49:07Z") # invalid hour format (1 digit)
      # Date-only invalid formats - these may be valid as other formats but not ISO timestamps
      invalid_tag6 = described_class.new("25-01-20") # invalid year format (2 digits)
      invalid_tag7 = described_class.new("2025-1-20") # invalid month format (1 digit)
      invalid_tag8 = described_class.new("2025-01-2") # invalid day format (1 digit)

      # None of these should match the ISO timestamp format
      expect(invalid_tag1.format).not_to eq(:iso_timestamp)
      expect(invalid_tag2.format).not_to eq(:iso_timestamp)
      expect(invalid_tag3.format).not_to eq(:iso_timestamp)
      expect(invalid_tag4.format).not_to eq(:iso_timestamp)
      expect(invalid_tag5.format).not_to eq(:iso_timestamp)
      expect(invalid_tag6.format).not_to eq(:iso_timestamp)
      expect(invalid_tag7.format).not_to eq(:iso_timestamp)
      expect(invalid_tag8.format).not_to eq(:iso_timestamp)

      # The timestamp ones should not be comparable at all since they have malformed timestamps
      expect(invalid_tag1.comparable?).to be false
      expect(invalid_tag2.comparable?).to be false
      expect(invalid_tag3.comparable?).to be false
      expect(invalid_tag4.comparable?).to be false
      expect(invalid_tag5.comparable?).to be false
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
