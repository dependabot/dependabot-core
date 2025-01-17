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

  let(:detected_version) { "3.8.20" }
  let(:raw_version) { "3.13.1" }

  describe "#deprecated?" do
    let(:detected_version) { "3.8.20" }
    let(:raw_version) { "3.13.1" }

    before do
      allow(::Dependabot::Experiments).to receive(:enabled?)
        .with(:python_3_8_deprecation_warning)
        .and_return(deprecation_enabled)
      allow(::Dependabot::Experiments).to receive(:enabled?)
        .with(:python_3_8_unsupported_error)
        .and_return(unsupported_enabled)
    end

    context "when python_3_8_deprecation_warning is enabled and detected version is deprecated" do
      let(:deprecation_enabled) { true }
      let(:unsupported_enabled) { false }

      it "returns true" do
        expect(language.deprecated?).to be true
      end
    end

    context "when python_3_8_deprecation_warning is enabled but detected version is not deprecated" do
      let(:detected_version) { "3.13" }
      let(:raw_version) { "3.13.1" }

      let(:deprecation_enabled) { true }
      let(:unsupported_enabled) { false }

      it "returns false" do
        expect(language.deprecated?).to be false
      end
    end

    context "when python_3_8_deprecation_warning is disabled" do
      let(:deprecation_enabled) { false }
      let(:unsupported_enabled) { false }

      it "returns false" do
        expect(language.deprecated?).to be false
      end
    end

    context "when detected version is unsupported" do
      let(:deprecation_enabled) { true }
      let(:unsupported_enabled) { true }

      it "returns false, as unsupported takes precedence" do
        expect(language.deprecated?).to be false
      end
    end
  end

  describe "#unsupported?" do
    let(:detected_version) { "3.8" }
    let(:raw_version) { "3.13.1" }

    before do
      allow(::Dependabot::Experiments).to receive(:enabled?)
        .with(:python_3_8_unsupported_error)
        .and_return(unsupported_enabled)
    end

    context "when python_3_8_unsupported_error is enabled and detected version is unsupported" do
      let(:unsupported_enabled) { true }

      it "returns true" do
        expect(language.unsupported?).to be true
      end
    end

    context "when python_3_8_unsupported_error is enabled but detected version is supported" do
      let(:detected_version) { "3.13" }
      let(:raw_version) { "3.13.1" }

      let(:unsupported_enabled) { true }

      it "returns false" do
        expect(language.unsupported?).to be false
      end
    end

    context "when python_3_8_unsupported_error is disabled" do
      let(:unsupported_enabled) { false }

      it "returns false" do
        expect(language.unsupported?).to be false
      end
    end
  end

  describe "#raise_if_unsupported!" do
    let(:version) { "3.8" }

    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:python_3_8_unsupported_error)
        .and_return(unsupported_enabled)
    end

    context "when python_3_8_unsupported_error is enabled and detected version is unsupported" do
      let(:unsupported_enabled) { true }

      it "raises a ToolVersionNotSupported error" do
        expect { language.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "when python_3_8_unsupported_error is disabled" do
      let(:unsupported_enabled) { false }

      it "does not raise an error" do
        expect { language.raise_if_unsupported! }.not_to raise_error
      end
    end
  end
end
