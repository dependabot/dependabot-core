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
    subject(:security_advisory) { described_class.new(args) }

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
end
