# typed: strict
# frozen_string_literal: true

require "dependabot/bundler/language"
require "dependabot/bundler/requirement"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Bundler::Language do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Bundler::Language) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:language) { described_class.new(version, requirement) }
  sig { returns(String) }
  let(:version) { "3.0.0" }
  sig { returns(T.nilable(Dependabot::Bundler::Requirement)) }
  let(:requirement) { Dependabot::Bundler::Requirement.new(">= 2.5.0") }
  # rubocop:enable RSpec/ScatteredLet

  describe "#initialize" do
    context "when version and requirement are both strings initially" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(String) }
      let(:version) { "3.0.0" }
      sig { returns(Dependabot::Bundler::Requirement) }
      let(:requirement) { Dependabot::Bundler::Requirement.new(">= 2.5.0") }
      # rubocop:enable RSpec/ScatteredLet

      it "sets the version correctly as a string" do
        expect(language.version).to eq(version)
      end

      it "sets the requirement correctly as a Dependabot::Bundler::Requirement" do
        expect(language.requirement).to eq(requirement)
      end

      it "sets the name correctly" do
        expect(language.name).to eq(Dependabot::Bundler::LANGUAGE)
      end
    end

    context "when version is a string and requirement is a Dependabot::Bundler::Requirement" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(String) }
      let(:version) { "3.0.0" }
      sig { returns(Dependabot::Bundler::Requirement) }
      let(:requirement) { Dependabot::Bundler::Requirement.new(">= 2.5.0") }
      # rubocop:enable RSpec/ScatteredLet

      it "sets the version correctly" do
        expect(language.version).to eq(version)
      end

      it "sets the requirement correctly" do
        expect(language.requirement).to eq(requirement)
      end

      it "sets the name correctly" do
        expect(language.name).to eq(Dependabot::Bundler::LANGUAGE)
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
