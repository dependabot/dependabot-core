# typed: false
# frozen_string_literal: true

require "dependabot/npm_and_yarn/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::NpmAndYarn::Bun do
  let(:package_manager) { described_class.new(version) }

  describe "#initialize" do
    context "when version is a String" do
      let(:version) { "1" }

      it "sets the version correctly" do
        expect(package_manager.version).to eq(Dependabot::Version.new(version))
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::NpmAndYarn::Bun::NAME)
      end

      it "sets the deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(
          Dependabot::NpmAndYarn::Bun::DEPRECATED_VERSIONS
        )
      end

      it "sets the supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::NpmAndYarn::Bun::SUPPORTED_VERSIONS)
      end
    end
  end

  describe "#deprecated?" do
    let(:version) { "1" }

    it "returns false" do
      expect(package_manager.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    context "when version is the minimum supported version" do
      let(:version) { Dependabot::NpmAndYarn::Bun::MIN_SUPPORTED_VERSION.to_s }

      it "returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end

    context "when version is unsupported" do
      let(:version) { "1.1.38" }

      it "returns true" do
        expect(package_manager.unsupported?).to be true
      end
    end
  end
end
