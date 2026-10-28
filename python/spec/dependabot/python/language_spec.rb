# typed: strict
# frozen_string_literal: true

require "dependabot/python/language"
require "dependabot/ecosystem"
require_relative "../../spec_helper"

RSpec.describe Dependabot::Python::Language do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Python::Language) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:language) do
    described_class.new(
      detected_version: detected_version,
      raw_version: raw_version
    )
  end

  sig { returns(String) }
  let(:detected_version) { "3.11" }

  sig { returns(String) }
  let(:raw_version) { "3.13.1" }
  # rubocop:enable RSpec/ScatteredLet

  describe "#deprecated?" do
    it "returns false" do
      expect(language.deprecated?).to be false
    end

    context "when detected version is unsupported" do
      sig { override.returns(String) }
      let(:detected_version) { "3.9.1" }

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
      sig { override.returns(String) }
      let(:detected_version) { "3.9" }

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
      sig { override.returns(String) }
      let(:detected_version) { "3.9" }

      it "raises a ToolVersionNotSupported error" do
        expect { language.raise_if_unsupported! }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end
  end
end
