# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo"
require "dependabot/security_advisory"

RSpec.describe Dependabot::SecurityAdvisory do
  let(:security_advisory) do
    described_class.new(
      dependency_name: "example",
      package_manager: "cargo",
      vulnerable_versions: ["<0.3.0"],
      safe_versions: safe_versions
    )
  end
  let(:safe_versions) { [] }
  let(:prerelease) { Dependabot::Cargo::Version.new("0.3.0-alpha-1") }

  describe "#vulnerable?" do
    it "matches Cargo prereleases against numeric vulnerable ranges" do
      expect(security_advisory.vulnerable?(prerelease)).to be(true)
    end

    context "when a numeric safe range also matches" do
      let(:safe_versions) { ["<0.3.0"] }

      it "gives the safe range precedence" do
        expect(security_advisory.vulnerable?(prerelease)).to be(false)
      end
    end
  end

  describe "#affects_version?" do
    it "matches Cargo prereleases against numeric vulnerable ranges" do
      expect(security_advisory.affects_version?(prerelease.to_s)).to be(true)
    end

    context "when a numeric safe range also matches" do
      let(:safe_versions) { ["<0.3.0"] }

      it "gives the safe range precedence" do
        expect(security_advisory.affects_version?(prerelease.to_s)).to be(false)
      end
    end
  end
end
