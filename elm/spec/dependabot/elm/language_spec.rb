# typed: false
# frozen_string_literal: true

require "dependabot/elm/language"
require "dependabot/elm/requirement"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::Elm::Language do
  let(:language) { described_class.new(version, requirement) }
  let(:version) { "0.19.1" }
  let(:requirement) { Dependabot::Elm::Requirement.new(">= 0.19.0") }

  describe "#initialize" do
    context "when version and requirement are both strings initially" do
      let(:version) { "0.19.1" }
      let(:requirement) { Dependabot::Elm::Requirement.new(">= 0.19.0") }

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
      let(:version) { "0.19.1" }
      let(:requirement) { Dependabot::Elm::Requirement.new(">= 0.19.0") }

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
