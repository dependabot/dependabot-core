# typed: false
# frozen_string_literal: true

require "dependabot/uv/language"
require "dependabot/ecosystem"
require_relative "../../spec_helper"

RSpec.describe Dependabot::Uv::Language do
  let(:language) do
    described_class.new(
      detected_version: detected_version,
      raw_version: raw_version
    )
  end

  let(:detected_version) { "3.11" }
  let(:raw_version) { "3.13.1" }

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
