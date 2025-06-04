# typed: false
# frozen_string_literal: true

require "dependabot/npm_and_yarn/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::NpmAndYarn::Language do
  let(:language) do
    described_class.new(
      raw_version: raw_version,
      requirement: requirement
    )
  end
  let(:raw_version) { "16.13.1" }
  let(:requirement) { nil }

  describe "#initialize" do
    it "sets the version correctly" do
      expect(language.version).to eq(Dependabot::Version.new(raw_version))
    end

    it "sets the name correctly" do
      expect(language.name).to eq(Dependabot::NpmAndYarn::Language::NAME)
    end

    it "sets the deprecated_versions correctly" do
      expect(language.deprecated_versions).to eq(Dependabot::NpmAndYarn::Language::DEPRECATED_VERSIONS)
    end

    it "sets the supported_versions correctly" do
      expect(language.supported_versions).to eq(Dependabot::NpmAndYarn::Language::SUPPORTED_VERSIONS)
    end

    context "when a requirement is provided" do
      let(:requirement) { Dependabot::NpmAndYarn::Requirement.new([">= 16.0.0", "< 17.0.0"]) }

      it "sets the requirement correctly" do
        expect(language.requirement).to eq(requirement)
      end
    end
  end

  describe "#deprecated?" do
    it "returns false by default" do
      expect(language.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    it "returns false by default" do
      expect(language.unsupported?).to be false
    end
  end
end
