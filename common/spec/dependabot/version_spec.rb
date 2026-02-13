# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/version"

RSpec.describe Dependabot::Version do
  subject(:version) { described_class.new(version_string) }

  describe "#lowest_prerelease_suffix" do
    subject(:ignored_versions) { version.lowest_prerelease_suffix }

    let(:version_string) { "1.2.3-alpha.1" }

    it { is_expected.to eq "a" }
  end

  describe "#ignored_major_versions" do
    subject(:ignored_versions) { version.ignored_major_versions }

    let(:version_string) { "1.2.3-alpha.1" }

    it { is_expected.to eq([">= 2.a"]) }
  end

  describe "#ignored_minor_versions" do
    subject(:ignored_versions) { version.ignored_minor_versions }

    let(:version_string) { "1.2.3-alpha.1" }

    it { is_expected.to eq([">= 1.3.a, < 2"]) }
  end

  describe "#ignored_patch_versions" do
    subject(:ignored_versions) { version.ignored_patch_versions }

    let(:version_string) { "1.2.3-alpha.1" }

    it { is_expected.to eq(["> #{version_string}, < 1.3"]) }
  end

  describe "#ignored_patch_versions_for_mode" do
    let(:version_string) { "0.2.3" }

    context "with relaxed mode (default)" do
      subject(:ignored_versions) { version.ignored_patch_versions_for_mode("relaxed") }

      it "uses standard semver" do
        expect(ignored_versions).to eq(["> 0.2.3, < 0.3"])
      end
    end

    context "with strict mode" do
      subject(:ignored_versions) { version.ignored_patch_versions_for_mode("strict") }

      context "with 0.y.z versions (y > 0)" do
        let(:version_string) { "0.2.3" }

        it "uses standard semver for patch changes (patch is still patch)" do
          expect(ignored_versions).to eq(["> 0.2.3, < 0.3"])
        end
      end

      context "with 0.0.z versions" do
        let(:version_string) { "0.0.3" }

        it "treats patch changes as major (breaking)" do
          expect(ignored_versions).to eq([">= 0.0.4.a"])
        end
      end
    end
  end

  describe "#ignored_minor_versions_for_mode" do
    let(:version_string) { "0.2.3" }

    context "with relaxed mode (default)" do
      subject(:ignored_versions) { version.ignored_minor_versions_for_mode("relaxed") }

      it "uses standard semver" do
        expect(ignored_versions).to eq([">= 0.3.a, < 1"])
      end
    end

    context "with strict mode" do
      subject(:ignored_versions) { version.ignored_minor_versions_for_mode("strict") }

      context "with 1.y.z versions" do
        let(:version_string) { "1.2.3" }

        it "uses standard semver" do
          expect(ignored_versions).to eq([">= 1.3.a, < 2"])
        end
      end

      context "with 0.y.z versions" do
        let(:version_string) { "0.2.3" }

        it "treats minor changes as major (breaking)" do
          expect(ignored_versions).to eq([">= 0.3.a"])
        end
      end
    end
  end

  describe "#ignored_major_versions_for_mode" do
    let(:version_string) { "0.2.3" }

    context "with relaxed mode (default)" do
      subject(:ignored_versions) { version.ignored_major_versions_for_mode("relaxed") }

      it "uses standard semver (ignores 1.0.0+)" do
        expect(ignored_versions).to eq([">= 1.a"])
      end
    end

    context "with strict mode" do
      subject(:ignored_versions) { version.ignored_major_versions_for_mode("strict") }

      context "with 1.y.z versions" do
        let(:version_string) { "1.2.3" }

        it "uses standard semver" do
          expect(ignored_versions).to eq([">= 2.a"])
        end
      end

      context "with 0.y.z versions (y > 0)" do
        let(:version_string) { "0.2.3" }

        it "treats minor changes as major (breaking)" do
          expect(ignored_versions).to eq([">= 0.3.a"])
        end
      end

      context "with 0.0.z versions" do
        let(:version_string) { "0.0.3" }

        it "treats patch changes as major (breaking)" do
          expect(ignored_versions).to eq([">= 0.0.4.a"])
        end
      end
    end
  end

  describe "strict mode integration with ignore conditions" do
    # These tests verify that the *_for_mode methods work correctly
    # when used by Dependabot::Config::IgnoreCondition for filtering

    context "with strict mode for 0.y.z packages" do
      let(:version_string) { "0.15.5" }

      it "correctly ignores breaking minor version bumps" do
        ignored = version.ignored_major_versions_for_mode("strict")
        req = Gem::Requirement.new(ignored.first)

        expect(req.satisfied_by?(described_class.new("0.15.6"))).to be(false) # patch is allowed
        expect(req.satisfied_by?(described_class.new("0.16.0"))).to be(true)  # minor bump is ignored
        expect(req.satisfied_by?(described_class.new("1.0.0"))).to be(true)   # major bump is ignored
      end
    end

    context "with relaxed mode for 0.y.z packages" do
      let(:version_string) { "0.15.5" }

      it "treats minor changes as minor, not major" do
        ignored = version.ignored_major_versions_for_mode("relaxed")
        req = Gem::Requirement.new(ignored.first)

        expect(req.satisfied_by?(described_class.new("0.15.6"))).to be(false) # patch is allowed
        expect(req.satisfied_by?(described_class.new("0.16.0"))).to be(false) # minor is allowed
        expect(req.satisfied_by?(described_class.new("1.0.0"))).to be(true)   # only actual major is ignored
      end
    end
  end
end
