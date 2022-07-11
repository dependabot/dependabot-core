# frozen_string_literal: true

require "spec_helper"
require "dependabot/security_advisory"

RSpec.describe Dependabot::SecurityAdvisory do
  let(:security_advisory) do
    described_class.new(
      dependency_name: "rails",
      package_manager: "dummy",
      vulnerable_versions: vulnerable_versions,
      safe_versions: safe_versions
    )
  end
  let(:safe_versions) { [] }
  let(:vulnerable_versions) { [Gem::Requirement.new(">= 1")] }

  describe ".new" do
    subject(:security_advisory) { described_class.new(**args) }

    let(:args) do
      {
        dependency_name: "rails",
        package_manager: "dummy",
        vulnerable_versions: vulnerable_versions,
        safe_versions: safe_versions
      }
    end
    let(:safe_versions) { [] }
    let(:vulnerable_versions) { [] }

    context "with an invalid safe_versions array" do
      let(:safe_versions) { [1] }

      it "raises a helpful error" do
        expect { security_advisory }.to raise_error(/safe_versions must be/)
      end
    end

    context "with an invalid vulnerable_versions array" do
      let(:vulnerable_versions) { [1] }
      it "raises a helpful error" do
        expect { security_advisory }.to raise_error(/vulnerable_versions must/)
      end
    end

    context "with a string safe_versions array" do
      let(:safe_versions) { [">= 1"] }

      its(:safe_versions) { is_expected.to eq([Gem::Requirement.new(">= 1")]) }
    end

    context "with a string vulnerable_versions array" do
      let(:vulnerable_versions) { [">= 1"] }

      its(:vulnerable_versions) do
        is_expected.to eq([Gem::Requirement.new(">= 1")])
      end
    end

    context "with valid version arrays" do
      let(:vulnerable_versions) { [Gem::Requirement.new(">= 1")] }

      specify { expect { security_advisory }.to_not raise_error }
    end
  end

  describe "#vulnerable?" do
    subject { security_advisory.vulnerable?(version) }

    let(:safe_versions) { [Gem::Requirement.new("> 1.5.1")] }
    let(:vulnerable_versions) do
      [Gem::Requirement.new("~> 0.5"), Gem::Requirement.new("~> 1.0")]
    end
    let(:version) { DummyPackageManager::Version.new("1.5.1") }

    context "with a safe version" do
      let(:version) { DummyPackageManager::Version.new("1.5.2") }
      it { is_expected.to eq(false) }
    end

    context "with a vulnerable version" do
      let(:version) { DummyPackageManager::Version.new("1.5.1") }
      it { is_expected.to eq(true) }
    end

    context "with only safe versions specified" do
      let(:vulnerable_versions) { [] }
      let(:safe_versions) { [Gem::Requirement.new("> 1.5.1")] }

      context "with a vulnerable version" do
        let(:version) { DummyPackageManager::Version.new("1.5.1") }
        it { is_expected.to eq(true) }
      end

      context "with a safe version" do
        let(:version) { DummyPackageManager::Version.new("1.5.2") }
        it { is_expected.to eq(false) }
      end
    end

    context "with only vulnerable versions specified" do
      let(:safe_versions) { [] }
      let(:vulnerable_versions) { [Gem::Requirement.new("<= 1.5.1")] }

      context "with a vulnerable version" do
        let(:version) { DummyPackageManager::Version.new("1.5.1") }
        it { is_expected.to eq(true) }
      end

      context "with a safe version" do
        let(:version) { DummyPackageManager::Version.new("1.5.2") }
        it { is_expected.to eq(false) }
      end
    end

    context "with no details" do
      let(:safe_versions) { [] }
      let(:vulnerable_versions) { [] }
      it { is_expected.to eq(false) }
    end
  end

  describe "#fixed_by?" do
    subject { security_advisory.fixed_by?(dependency) }

    let(:dependency) do
      Dependabot::Dependency.new(
        package_manager: package_manager,
        name: dependency_name,
        version: dependency_version,
        previous_version: dependency_previous_version,
        requirements: [],
        previous_requirements: []
      )
    end
    let(:package_manager) { "dummy" }
    let(:dependency_name) { "rails" }
    let(:vulnerable_versions) { [] }
    let(:safe_versions) { [Gem::Requirement.new("~> 1.11.0")] }
    let(:dependency_version) { "1.11.1" }
    let(:dependency_previous_version) { "0.7.1" }

    it { is_expected.to eq(true) }

    context "for a different package manager" do
      let(:package_manager) { "npm_and_yarn" }
      it { is_expected.to eq(false) }
    end

    context "for a different dependency" do
      let(:dependency_name) { "gemcutter" }
      it { is_expected.to eq(false) }
    end

    context "when the name has a different case" do
      let(:dependency_name) { "Rails" }
      it { is_expected.to eq(true) }
    end

    context "with a dependency that has already been patched" do
      let(:dependency_previous_version) { "1.11.2" }
      it { is_expected.to eq(false) }
    end

    context "updating to a version that isn't fixed" do
      let(:dependency_version) { "1.10.1" }
      it { is_expected.to eq(false) }
    end

    context "with no fixed versions" do
      let(:safe_versions) { [] }
      it { is_expected.to eq(false) }
    end

    context "with affected_versions specified" do
      let(:safe_versions) { [] }
      let(:vulnerable_versions) { ["~> 0.7.0"] }
      it { is_expected.to eq(true) }

      context "that don't match the old version" do
        let(:vulnerable_versions) { ["~> 0.8.0"] }
        it { is_expected.to eq(false) }
      end
    end

    context "with a removed dependency" do
      let(:dependency_version) { "" }
      it { is_expected.to eq(true) }
    end
  end

  describe "#affects_version?" do
    subject { security_advisory.affects_version?(version_string) }

    let(:version_string) { "0.7.1" }
    let(:vulnerable_versions) { [] }
    let(:safe_versions) { ["~> 1.11.0"] }

    it { is_expected.to eq(true) }

    context "with several requirements" do
      let(:safe_versions) { ["~> 1.11.0", ">= 1.11.0.1"] }
      it { is_expected.to eq(true) }
    end

    context "with a version that has already been patched" do
      let(:version_string) { "1.11.2" }
      it { is_expected.to eq(false) }
    end

    context "with a git SHA" do
      let(:version_string) { "d7a42dcd7cf631ba94b01231f535bda061f6af92" }
      it { is_expected.to eq(false) }
    end

    context "with no vulnerable or fixed versions" do
      let(:safe_versions) { [] }
      it { is_expected.to eq(false) }
    end

    context "with vulnerable_versions specified" do
      let(:safe_versions) { [] }
      let(:vulnerable_versions) { ["~> 0.7.0"] }

      it { is_expected.to eq(true) }

      context "and some other versions are patched" do
        let(:safe_versions) { [">= 0.7.2"] }
        it { is_expected.to eq(true) }
      end

      context "but this version is patched" do
        let(:safe_versions) { [">= 0.7.1"] }
        it { is_expected.to eq(false) }
      end

      context "that don't match this version" do
        let(:vulnerable_versions) { ["~> 0.8.0"] }
        it { is_expected.to eq(false) }
      end
    end
  end
end
