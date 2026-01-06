# typed: false
# frozen_string_literal: true

require "dependabot/python/language"
require "dependabot/ecosystem"
require_relative "../../spec_helper"

RSpec.describe Dependabot::Python::Language do
  let(:language) do
    described_class.new(
      detected_version: detected_version,
      raw_version: raw_version
    )
  end

  let(:detected_version) { "3.11" }
  let(:raw_version) { "3.13.1" }

  describe "PRE_INSTALLED_PYTHON_VERSIONS" do
    it "is sorted in descending order" do
      versions = described_class::PRE_INSTALLED_PYTHON_VERSIONS
      expect(versions).to eq(versions.sort.reverse)
    end

    it "has the highest version first" do
      versions = described_class::PRE_INSTALLED_PYTHON_VERSIONS
      expect(versions.first).to eq(versions.max)
    end

    it "has the lowest version last" do
      versions = described_class::PRE_INSTALLED_PYTHON_VERSIONS
      expect(versions.last).to eq(versions.min)
    end

    it "matches PRE_INSTALLED_HIGHEST_VERSION with the first element" do
      expect(described_class::PRE_INSTALLED_PYTHON_VERSIONS.first)
        .to eq(described_class::PRE_INSTALLED_HIGHEST_VERSION)
    end
  end

  describe "#deprecated?" do
    it "returns false" do
      expect(language.deprecated?).to be false
    end

    context "when detected version is deprecated but not unsupported" do
      let(:detected_version) { "3.8.1" }

      before do
        allow(language).to receive(:unsupported?).and_return(false)
      end

      it "returns true" do
        expect(language.deprecated?).to be true
      end
    end

    context "when detected version is unsupported" do
      it "returns false, as unsupported takes precedence" do
        expect(language.deprecated?).to be false
      end
    end
  end

  describe "#unsupported?" do
    it "returns false" do
      expect(language.unsupported?).to be false
    end

    context "when detected version is unsupported" do
      let(:detected_version) { "3.8" }

      it "returns true" do
        expect(language.unsupported?).to be true
      end
    end
  end

  describe "#raise_if_unsupported!" do
    it "does not raise an error" do
      expect { language.raise_if_unsupported! }.not_to raise_error
    end

    context "when detected version is unsupported" do
      let(:detected_version) { "3.8" }

      it "raises a ToolVersionNotSupported error" do
        expect { language.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end
  end
end
