# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/ecosystem"
require "dependabot/version"
require "dependabot/apm/package_manager"

RSpec.describe Dependabot::Apm::PackageManager do
  subject(:package_manager) { described_class.new(version) }

  let(:version) { "0.4.2" }

  describe "#version" do
    it "returns the version" do
      expect(package_manager.version.to_s).to eq(version)
    end
  end

  describe "#name" do
    it "returns the name" do
      expect(package_manager.name).to eq(Dependabot::Apm::PACKAGE_MANAGER)
    end
  end

  describe "#deprecated_versions" do
    it "returns deprecated versions" do
      expect(package_manager.deprecated_versions).to eq(Dependabot::Apm::DEPRECATED_APM_VERSIONS)
    end
  end

  describe "#supported_versions" do
    it "returns supported versions" do
      expect(package_manager.supported_versions).to eq(Dependabot::Apm::SUPPORTED_APM_VERSIONS)
    end
  end

  describe "#deprecated?" do
    it "is not deprecated" do
      expect(package_manager.deprecated?).to be(false)
    end
  end

  describe "#unsupported?" do
    it "is not unsupported" do
      expect(package_manager.unsupported?).to be(false)
    end
  end

  describe ".parse_version" do
    it "parses a strict SemVer apm version" do
      expect(described_class.parse_version("0.4.2").to_s).to eq("0.4.2")
    end

    # The apm CLI reports its own version from Python (PEP 440) packaging
    # metadata, so these pre-release / calendar forms are valid values of the
    # lockfile `apm_version` field and must not raise when parsed.
    ["0.32.0rc1", "0.32.0.dev3", "1.2.3rc1.post2", "2024.01.01"].each do |raw|
      it "parses the PEP 440 apm version #{raw.inspect} without raising" do
        expect { described_class.parse_version(raw) }.not_to raise_error
        expect(described_class.parse_version(raw)).to be_a(Dependabot::Version)
      end
    end

    it "falls back to the default for an unparseable version" do
      expect(described_class.parse_version("not-a-version").to_s)
        .to eq(Dependabot::Apm::DEFAULT_PACKAGE_MANAGER_VERSION)
    end
  end

  context "when built from a PEP 440 apm version" do
    let(:version) { "0.32.0rc1" }

    it "does not raise" do
      expect { package_manager }.not_to raise_error
      expect(package_manager.version).to be_a(Dependabot::Version)
    end
  end
end
