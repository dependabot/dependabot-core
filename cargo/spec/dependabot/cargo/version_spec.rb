# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/version"

RSpec.describe Dependabot::Cargo::Version do
  subject(:version) { described_class.new(version_string) }

  let(:version_string) { "1.0.0" }

  describe "#to_s" do
    subject { version.to_s }

    context "with a non-prerelease" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to eq "1.0.0" }
    end

    context "with a normal prerelease" do
      let(:version_string) { "1.0.0.pre1" }

      it { is_expected.to eq "1.0.0.pre1" }
    end

    context "with a PHP-style prerelease" do
      let(:version_string) { "1.0.0-pre1" }

      it { is_expected.to eq "1.0.0-pre1" }
    end

    context "with a build version" do
      let(:version_string) { "1.0.0-pre1+something" }

      it { is_expected.to eq "1.0.0-pre1+something" }
    end

    context "with a build version with hyphens" do
      let(:version_string) { "0.9.0+wasi-snapshot-preview1" }

      it { is_expected.to eq "0.9.0+wasi-snapshot-preview1" }
    end

    context "with a build version with hyphens in multiple identifiers" do
      let(:version_string) { "0.9.0+wasi-snapshot1.alpha-preview" }

      it { is_expected.to eq "0.9.0+wasi-snapshot1.alpha-preview" }
    end

    context "with a blank version" do
      let(:version_string) { "" }

      it { is_expected.to eq "" }
    end

    context "with a version (not a version string)" do
      let(:version_string) { described_class.new("1.0.0") }

      it { is_expected.to eq "1.0.0" }
    end
  end

  describe "compatibility with Gem::Requirement" do
    subject { requirement.satisfied_by?(version) }

    let(:requirement) { Gem::Requirement.new(">= 1.0.0") }

    context "with a valid version" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(true) }
    end

    context "with an invalid version" do
      let(:version_string) { "0.9.0" }

      it { is_expected.to be(false) }
    end

    context "with a valid prerelease version" do
      let(:version_string) { "1.1.0-pre" }

      it { is_expected.to be(true) }
    end
  end

  describe "#correct?" do
    subject { described_class.correct?(version_string) }

    valid = %w(1.0.0 1.0.0.pre1 1.0.0-pre1 1.0.0-pre1+something 0.9.0+wasi-snapshot-preview1
               0.9.0+wasi-snapshot1.alpha-preview)
    valid.each do |version|
      context "with version #{version}" do
        let(:version_string) { version }

        it { is_expected.to be(true) }
      end
    end

    invalid = %w(☃ questionmark?)
    invalid.each do |version|
      context "with version #{version}" do
        let(:version_string) { version }

        it { is_expected.to be(false) }
      end
    end
  end

  describe "Cargo-specific version compatibility" do
    describe "#ignored_patch_versions" do
      subject(:ignored_patch_versions) { version.ignored_patch_versions }

      context "with a standard 1.y.z version" do
        let(:version_string) { "1.2.3" }

        it "uses standard semantic versioning" do
          expect(ignored_patch_versions).to eq(["> 1.2.3, < 1.3"])
        end
      end

      context "with a 0.y.z version (y > 0)" do
        let(:version_string) { "0.2.3" }

        it "uses standard semantic versioning for patch" do
          expect(ignored_patch_versions).to eq(["> 0.2.3, < 0.3"])
        end
      end

      context "with a 0.0.z version" do
        let(:version_string) { "0.0.3" }

        it "treats patch changes as major (breaking)" do
          expect(ignored_patch_versions).to eq([">= 1.a"])
        end
      end
    end

    describe "#ignored_minor_versions" do
      subject(:ignored_minor_versions) { version.ignored_minor_versions }

      context "with a standard 1.y.z version" do
        let(:version_string) { "1.2.3" }

        it "uses standard semantic versioning" do
          expect(ignored_minor_versions).to eq([">= 1.3.a, < 2"])
        end
      end

      context "with a 0.y.z version" do
        let(:version_string) { "0.2.3" }

        it "treats minor changes as major (breaking)" do
          expect(ignored_minor_versions).to eq([">= 1.a"])
        end
      end
    end

    describe ".update_type" do
      context "with standard 1.y.z versions" do
        it "classifies major version increases as major" do
          expect(described_class.update_type("1.2.3", "2.0.0")).to eq("major")
        end

        it "classifies minor version increases as minor" do
          expect(described_class.update_type("1.2.3", "1.3.0")).to eq("minor")
        end

        it "classifies patch version increases as patch" do
          expect(described_class.update_type("1.2.3", "1.2.4")).to eq("patch")
        end
      end

      context "with 0.y.z pre-1.0 versions" do
        it "classifies minor version increases as major (breaking)" do
          expect(described_class.update_type("0.11.5", "0.12.0")).to eq("major")
          expect(described_class.update_type("0.2.3", "0.3.0")).to eq("major")
        end

        it "classifies patch version increases as patch (compatible)" do
          expect(described_class.update_type("0.11.5", "0.11.6")).to eq("patch")
          expect(described_class.update_type("0.2.3", "0.2.4")).to eq("patch")
        end

        it "classifies major version increases as major" do
          expect(described_class.update_type("0.11.5", "1.0.0")).to eq("major")
        end
      end

      context "with 0.0.z pre-1.0 versions" do
        it "classifies patch version increases as major (breaking)" do
          expect(described_class.update_type("0.0.3", "0.0.4")).to eq("major")
        end

        it "classifies minor version increases as major (breaking)" do
          expect(described_class.update_type("0.0.3", "0.1.0")).to eq("major")
        end

        it "classifies major version increases as major" do
          expect(described_class.update_type("0.0.3", "1.0.0")).to eq("major")
        end
      end

      context "with specific real-world examples" do
        it "classifies annotate-snippets 0.11.5 to 0.12.5 as major" do
          expect(described_class.update_type("0.11.5", "0.12.5")).to eq("major")
        end

        it "classifies serde 0.8.0 to 0.9.0 as major" do
          expect(described_class.update_type("0.8.0", "0.9.0")).to eq("major")
        end

        it "classifies tokio 0.2.22 to 0.3.0 as major" do
          expect(described_class.update_type("0.2.22", "0.3.0")).to eq("major")
        end

        it "classifies regex 0.1.80 to 0.1.81 as patch" do
          expect(described_class.update_type("0.1.80", "0.1.81")).to eq("patch")
        end
      end

      context "with edge cases" do
        it "handles versions with different precision" do
          expect(described_class.update_type("0.1", "0.2")).to eq("major")
          expect(described_class.update_type("1.0", "1.1")).to eq("minor")
        end

        it "handles single-digit versions" do
          expect(described_class.update_type("0", "1")).to eq("major")
          expect(described_class.update_type("1", "2")).to eq("major")
        end

        it "handles identical versions" do
          expect(described_class.update_type("0.11.5", "0.11.5")).to eq("patch")
          expect(described_class.update_type("1.2.3", "1.2.3")).to eq("patch")
        end

        it "handles Version objects as input" do
          from_version = described_class.new("0.11.5")
          to_version = described_class.new("0.12.0")
          expect(described_class.update_type(from_version, to_version)).to eq("major")
        end
      end

      context "with dependency grouping scenarios" do
        # These tests verify that our update type classification works correctly
        # for common Cargo dependency update scenarios

        context "when grouping by update type" do
          it "correctly identifies breaking changes in 0.y.z versions" do
            # This should be grouped with other major updates
            expect(described_class.update_type("0.11.5", "0.12.5")).to eq("major")
            expect(described_class.update_type("0.8.0", "0.9.0")).to eq("major")
            expect(described_class.update_type("0.1.0", "0.2.0")).to eq("major")
          end

          it "correctly identifies compatible changes in 0.y.z versions" do
            # These should be grouped with patch updates
            expect(described_class.update_type("0.11.5", "0.11.6")).to eq("patch")
            expect(described_class.update_type("0.8.0", "0.8.1")).to eq("patch")
            expect(described_class.update_type("0.1.0", "0.1.1")).to eq("patch")
          end

          it "correctly identifies all changes in 0.0.z versions as breaking" do
            # All changes in 0.0.z should be treated as major
            expect(described_class.update_type("0.0.1", "0.0.2")).to eq("major")
            expect(described_class.update_type("0.0.5", "0.0.6")).to eq("major")
            expect(described_class.update_type("0.0.1", "0.1.0")).to eq("major")
          end

          it "correctly handles transitions from pre-1.0 to 1.0+" do
            # These are clearly major version bumps
            expect(described_class.update_type("0.11.5", "1.0.0")).to eq("major")
            expect(described_class.update_type("0.0.8", "1.0.0")).to eq("major")
          end

          it "works correctly with different version string formats" do
            # Test with different precision levels
            expect(described_class.update_type("0.1", "0.2")).to eq("major")
            expect(described_class.update_type("0.1.0", "0.2")).to eq("major")
            expect(described_class.update_type("0.1", "0.1.1")).to eq("patch")
          end
        end
      end
    end
  end
end
