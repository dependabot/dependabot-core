# typed: false
# frozen_string_literal: true

require "dependabot/composer/language"
require "dependabot/ecosystem"
require "spec_helper"

ComposerLanguage = Dependabot::Composer::Language

RSpec.describe Dependabot::Composer::Language do
  let(:language) { described_class.new(version, requirement: requirement) }
  let(:version) { "7.4.33" }
  let(:requirement) { nil }

  describe "#initialize" do
    context "when version is a String" do
      it "sets the version correctly" do
        expect(language.version).to eq(Dependabot::Version.new(version))
      end

      it "sets the name correctly" do
        expect(language.name).to eq(ComposerLanguage::NAME)
      end

      it "sets the deprecated_versions correctly" do
        expect(language.deprecated_versions).to eq([])
      end

      it "sets the supported_versions correctly" do
        expect(language.supported_versions).to eq([])
      end

      it "sets the requirement correctly" do
        expect(language.requirement).to be_nil
      end
    end

    context "when a requirement is provided" do
      let(:requirement) { Dependabot::Composer::Requirement.new([">=7.4", "<8.0"]) }

      it "sets the requirement correctly" do
        expect(language.requirement.requirements).to eq([
          [">=", Gem::Version.new("7.4")],
          ["<", Gem::Version.new("8.0")]
        ])
      end
    end
  end

  describe "#deprecated?" do
    it "returns false for all versions" do
      expect(language.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    it "returns false for all versions" do
      expect(language.unsupported?).to be false
    end
  end

  describe "#name" do
    it "returns the correct name for the language" do
      expect(language.name).to eq("php")
    end
  end

  describe "#version" do
    context "when version is valid" do
      it "returns the correct version" do
        expect(language.version).to eq(Dependabot::Version.new("7.4.33"))
      end
    end

    context "when version is invalid" do
      let(:version) { "invalid" }

      it "raises an error when parsed as a Dependabot::Version" do
        expect { language.version }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#requirement" do
    context "when no requirement is provided" do
      it "returns nil" do
        expect(language.requirement).to be_nil
      end
    end

    context "when a requirement is provided" do
      let(:requirement) { Dependabot::Composer::Requirement.new([">=7.4", "<8.0"]) }

      it "returns the requirement object" do
        expect(language.requirement.requirements).to eq([
          [">=", Gem::Version.new("7.4")],
          ["<", Gem::Version.new("8.0")]
        ])
      end
    end
  end
end
