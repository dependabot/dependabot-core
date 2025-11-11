# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bazel/version"

RSpec.describe Dependabot::Bazel::Version do
  subject(:version) { described_class.new(version_string) }

  describe "#to_s" do
    context "with a standard semantic version" do
      let(:version_string) { "1.2.3" }

      it "returns the original version string" do
        expect(version.to_s).to eq("1.2.3")
      end
    end

    context "with a pre-release version using hyphen" do
      let(:version_string) { "1.7.0-rc4" }

      it "preserves the hyphen format (not Gem::Version's .pre. format)" do
        expect(version.to_s).to eq("1.7.0-rc4")
      end

      it "does not transform to .pre.rc format" do
        expect(version.to_s).not_to eq("1.7.0.pre.rc4")
      end
    end

    context "with a pre-release version using alpha" do
      let(:version_string) { "2.0.0-alpha.1" }

      it "preserves the original format" do
        expect(version.to_s).to eq("2.0.0-alpha.1")
      end
    end

    context "with a pre-release version using beta" do
      let(:version_string) { "3.1.0-beta.2" }

      it "preserves the original format" do
        expect(version.to_s).to eq("3.1.0-beta.2")
      end
    end
  end

  describe "#to_semver" do
    context "with a pre-release version" do
      let(:version_string) { "1.7.0-rc4" }

      it "returns the original version string" do
        expect(version.to_semver).to eq("1.7.0-rc4")
      end
    end
  end

  describe "version comparison" do
    it "correctly compares pre-release versions" do
      v1 = described_class.new("1.7.0-rc3")
      v2 = described_class.new("1.7.0-rc4")
      v3 = described_class.new("1.7.0")

      expect(v1).to be < v2
      expect(v2).to be < v3
    end

    it "correctly compares versions with different pre-release identifiers" do
      alpha = described_class.new("2.0.0-alpha.1")
      beta = described_class.new("2.0.0-beta.1")
      rc = described_class.new("2.0.0-rc.1")
      release = described_class.new("2.0.0")

      expect(alpha).to be < beta
      expect(beta).to be < rc
      expect(rc).to be < release
    end
  end
end
