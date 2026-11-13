# typed: strict
# frozen_string_literal: true

require "dependabot/npm_and_yarn/package_manager"
require "dependabot/ecosystem"
require "spec_helper"

RSpec.describe Dependabot::NpmAndYarn::YarnPackageManager do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::NpmAndYarn::YarnPackageManager) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:package_manager) do
    described_class.new(
      detected_version: detected_version,
      raw_version: raw_version
    )
  end

  sig { returns(String) }
  let(:detected_version) { "3" }
  sig { returns(String) }
  let(:raw_version) { "3.5.0" }

  describe "#initialize" do
    context "when version is a String" do
      sig { returns(String) }
      let(:detected_version) { "2" }
      sig { returns(String) }
      let(:raw_version) { "2.8.0" }

      it "sets the version correctly" do
        expect(package_manager.detected_version).to eq(Dependabot::Version.new(detected_version))
        expect(package_manager.version).to eq(Dependabot::Version.new(raw_version))
      end

      it "sets the name correctly" do
        expect(package_manager.name).to eq(Dependabot::NpmAndYarn::YarnPackageManager::NAME)
      end

      it "sets the deprecated_versions correctly" do
        expect(package_manager.deprecated_versions).to eq(
          Dependabot::NpmAndYarn::YarnPackageManager::DEPRECATED_VERSIONS
        )
      end

      it "sets the supported_versions correctly" do
        expect(package_manager.supported_versions).to eq(Dependabot::NpmAndYarn::YarnPackageManager::SUPPORTED_VERSIONS)
      end
    end
  end

  describe "#deprecated?" do
    sig { returns(String) }
    let(:detected_version) { "1" }
    sig { returns(String) }
    let(:raw_version) { "1.22.10" }

    it "always returns false" do
      expect(package_manager.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    sig { returns(String) }
    let(:detected_version) { "4" }
    sig { returns(String) }
    let(:raw_version) { "4.0.0" }

    it "always returns false" do
      expect(package_manager.unsupported?).to be false
    end

    context "with supported versions" do
      sig { returns(String) }
      let(:detected_version) { "2" }
      sig { returns(String) }
      let(:raw_version) { "2.8.0" }

      it "still returns false" do
        expect(package_manager.unsupported?).to be false
      end
    end
  end

  describe "#raise_if_unsupported!" do
    sig { returns(String) }
    let(:detected_version) { "1" }

    it "does not raise an error" do
      expect { package_manager.raise_if_unsupported! }.not_to raise_error
    end
  end
  # rubocop:enable RSpec/ScatteredLet
end
