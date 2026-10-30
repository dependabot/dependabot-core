# typed: strict
# frozen_string_literal: true

require "dependabot/elm/language"
require "dependabot/elm/requirement"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Elm::Language do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Elm::Language) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:language) { described_class.new(version, requirement) }
  sig { returns(String) }
  let(:version) { "0.19.1" }
  sig { returns(T.nilable(Dependabot::Elm::Requirement)) }
  let(:requirement) { Dependabot::Elm::Requirement.new(">= 0.19.0") }
  # rubocop:enable RSpec/ScatteredLet

  describe "#initialize" do
    context "when version and requirement are both strings initially" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(String) }
      let(:version) { "0.19.1" }
      sig { returns(Dependabot::Elm::Requirement) }
      let(:requirement) { Dependabot::Elm::Requirement.new(">= 0.19.0") }
      # rubocop:enable RSpec/ScatteredLet

      it "sets the version correctly as a string" do
        expect(language.version.to_s).to eq(version)
      end

      it "sets the requirement correctly as a Dependabot::Elm::Requirement" do
        expect(language.requirement).to eq(requirement)
      end

      it "sets the name correctly" do
        expect(language.name).to eq(Dependabot::Elm::LANGUAGE)
      end
    end

    context "when version is a string and requirement is a Dependabot::Elm::Requirement" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(String) }
      let(:version) { "0.19.1" }
      sig { returns(Dependabot::Elm::Requirement) }
      let(:requirement) { Dependabot::Elm::Requirement.new(">= 0.19.0") }
      # rubocop:enable RSpec/ScatteredLet

      it "sets the version correctly" do
        expect(language.version.to_s).to eq(version)
      end

      it "sets the requirement correctly" do
        expect(language.requirement).to eq(requirement)
      end

      it "sets the name correctly" do
        expect(language.name).to eq(Dependabot::Elm::LANGUAGE)
      end
    end

    context "when requirement is nil" do
      sig { returns(NilClass) }
      let(:requirement) { nil }

      it "sets requirement to nil" do
        expect(language.requirement).to be_nil
      end
    end
  end

  describe "#unsupported?" do
    it "returns false by default as no specific support or deprecation for languages is currently defined" do
      expect(language.unsupported?).to be false
    end
  end

  describe "#deprecated?" do
    it "returns false by default as no specific deprecation for languages is currently defined" do
      expect(language.deprecated?).to be false
    end
  end
end
