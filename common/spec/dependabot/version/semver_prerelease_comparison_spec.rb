# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/version/semver_prerelease_comparison"

RSpec.describe Dependabot::Version::SemverPrereleaseComparison do
  let(:test_class) do
    Class.new do
      include Dependabot::Version::SemverPrereleaseComparison
    end
  end
  let(:instance) { test_class.new }

  describe "#compare_semver_prerelease" do
    it "returns 0 when both are nil (stable releases)" do
      expect(instance.compare_semver_prerelease(nil, nil)).to eq(0)
    end

    it "returns 1 when left is nil (stable > pre-release)" do
      expect(instance.compare_semver_prerelease(nil, "alpha")).to eq(1)
    end

    it "returns -1 when right is nil (pre-release < stable)" do
      expect(instance.compare_semver_prerelease("alpha", nil)).to eq(-1)
    end

    it "compares numeric identifiers as integers" do
      expect(instance.compare_semver_prerelease("2", "11")).to eq(-1)
      expect(instance.compare_semver_prerelease("11", "2")).to eq(1)
      expect(instance.compare_semver_prerelease("5", "5")).to eq(0)
    end

    it "compares alphanumeric identifiers lexically" do
      expect(instance.compare_semver_prerelease("alpha", "beta")).to eq(-1)
      expect(instance.compare_semver_prerelease("beta", "alpha")).to eq(1)
      expect(instance.compare_semver_prerelease("rc", "rc")).to eq(0)
    end

    it "orders numeric identifiers before alphanumeric" do
      expect(instance.compare_semver_prerelease("1", "alpha")).to eq(-1)
      expect(instance.compare_semver_prerelease("alpha", "1")).to eq(1)
    end

    it "orders fewer fields before more fields when preceding match" do
      expect(instance.compare_semver_prerelease("alpha", "alpha.1")).to eq(-1)
      expect(instance.compare_semver_prerelease("alpha.1", "alpha")).to eq(1)
    end

    it "returns 0 for identical prereleases" do
      expect(instance.compare_semver_prerelease("alpha.1", "alpha.1")).to eq(0)
      expect(instance.compare_semver_prerelease("rc.1", "rc.1")).to eq(0)
    end

    it "handles hyphenated identifiers as single alphanumeric tokens" do
      # "alpha-1" is one identifier (hyphens are valid in identifiers)
      expect(instance.compare_semver_prerelease("alpha-1", "alpha-2")).to eq(-1)
      expect(instance.compare_semver_prerelease("alpha-1", "beta")).to eq(-1)
    end

    it "follows the full SemVer §11 example ordering" do
      prereleases = %w(
        alpha
        alpha.1
        alpha.beta
        beta
        beta.2
        beta.11
        rc.1
      )

      prereleases.each_cons(2) do |left, right|
        expect(instance.compare_semver_prerelease(left, right)).to(
          eq(-1), "Expected #{left} < #{right}"
        )
      end
    end
  end
end
