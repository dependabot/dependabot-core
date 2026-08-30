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

  describe "BCR .bcr.X suffix handling" do
    describe "#initialize" do
      context "with a .bcr.X suffix" do
        let(:version_string) { "1.6.50.bcr.1" }

        it "parses and stores the bcr suffix" do
          expect(version.bcr_suffix).to eq(1)
        end

        it "preserves the original version string" do
          expect(version.to_s).to eq("1.6.50.bcr.1")
        end
      end

      context "with a higher .bcr.X suffix" do
        let(:version_string) { "1.6.50.bcr.10" }

        it "parses multi-digit bcr suffixes" do
          expect(version.bcr_suffix).to eq(10)
        end
      end

      context "without a .bcr.X suffix" do
        let(:version_string) { "1.6.50" }

        it "has nil bcr_suffix" do
          expect(version.bcr_suffix).to be_nil
        end
      end
    end

    describe "version comparison with .bcr.X suffixes" do
      it "treats .bcr.X versions as newer than base version" do
        base = described_class.new("1.6.50")
        bcr1 = described_class.new("1.6.50.bcr.1")

        expect(bcr1).to be > base
        expect(base).to be < bcr1
      end

      it "correctly orders multiple .bcr.X versions" do
        base = described_class.new("1.6.50")
        bcr1 = described_class.new("1.6.50.bcr.1")
        bcr2 = described_class.new("1.6.50.bcr.2")

        expect(bcr2).to be > bcr1
        expect(bcr1).to be > base
        expect(bcr2).to be > base
      end

      it "correctly sorts mixed versions" do
        versions = [
          described_class.new("1.6.50.bcr.2"),
          described_class.new("1.6.50"),
          described_class.new("1.6.50.bcr.1"),
          described_class.new("1.6.51"),
          described_class.new("1.6.49")
        ]

        sorted = versions.sort
        expect(sorted.map(&:to_s)).to eq(
          [
            "1.6.49",
            "1.6.50",
            "1.6.50.bcr.1",
            "1.6.50.bcr.2",
            "1.6.51"
          ]
        )
      end

      it "handles .bcr.X with higher base versions" do
        v1 = described_class.new("1.6.50.bcr.1")
        v2 = described_class.new("1.6.51")

        expect(v2).to be > v1
      end

      it "handles .bcr.X with lower base versions" do
        v1 = described_class.new("1.6.49.bcr.1")
        v2 = described_class.new("1.6.50")

        expect(v2).to be > v1
      end

      it "correctly compares equal base versions with different .bcr suffixes" do
        bcr1 = described_class.new("2.0.0.bcr.1")
        bcr5 = described_class.new("2.0.0.bcr.5")
        bcr10 = described_class.new("2.0.0.bcr.10")

        expect(bcr5).to be > bcr1
        expect(bcr10).to be > bcr5
        expect(bcr10).to be > bcr1
      end

      it "prevents downgrade from .bcr version to base version" do
        bcr1 = described_class.new("1.6.50.bcr.1")
        base = described_class.new("1.6.50")

        # bcr.1 should be considered newer, so this would be a downgrade
        expect(bcr1).to be > base
        expect(base).not_to be > bcr1
      end
    end

    describe "real-world BCR example scenarios" do
      it "handles libpng version progression correctly" do
        versions = [
          described_class.new("1.6.50"),
          described_class.new("1.6.50.bcr.1")
        ]

        latest = versions.max
        expect(latest.to_s).to eq("1.6.50.bcr.1")
      end

      it "handles progression from base to multiple .bcr patches" do
        v1 = described_class.new("1.6.50")
        v2 = described_class.new("1.6.50.bcr.1")
        v3 = described_class.new("1.6.50.bcr.2")

        expect([v1, v2, v3].max).to eq(v3)
        expect([v3, v1, v2].sort).to eq([v1, v2, v3])
      end
    end
  end

  describe ".correct?" do
    it "accepts standard versions" do
      expect(described_class.correct?("1.2.3")).to be true
    end

    it "accepts v-prefixed versions" do
      expect(described_class.correct?("v1.2.3")).to be true
    end

    it "accepts .bcr.N suffixed versions" do
      expect(described_class.correct?("1.2.3.bcr.1")).to be true
    end

    it "accepts v-prefixed prerelease versions" do
      expect(described_class.correct?("v1.2.3-rc1")).to be true
    end

    it "rejects .bazelversion file content — only version_from_file handles multi-line/wrapper forms" do
      expect(described_class.correct?("buildbuddy-io/5.0.321\n9.1.0\n")).to be false
      expect(described_class.correct?("buildbuddy-io/5.0.321")).to be false
    end

    it "rejects slash-containing strings like git tags, as before BuildBuddy support" do
      expect(described_class.correct?("release/1.2.3")).to be false
      expect(described_class.correct?("refs/tags/v1.2.3")).to be false
    end

    it "rejects malformed strings" do
      expect(described_class.correct?("not_valid!!!")).to be false
    end

    it "rejects nil" do
      expect(described_class.correct?(nil)).to be false
    end
  end

  describe ".extract_bazel_version" do
    it "returns simple version strings untouched" do
      expect(described_class.extract_bazel_version("9.1.0")).to eq("9.1.0")
    end

    it "extracts the Bazel version from a multi-line BuildBuddy wrapper string" do
      content = "buildbuddy-io/5.0.321\n9.1.0\n"
      expect(described_class.extract_bazel_version(content)).to eq("9.1.0")
    end

    it "extracts the Bazel version when comments and wrapper lines are present" do
      content = "# Wrapper definition\nbuildbuddy-io/5.0.321\n\n# Actual Bazel version\n8.4.0-rc2\n"
      expect(described_class.extract_bazel_version(content)).to eq("8.4.0-rc2")
    end

    it "extracts the version number when only a fork reference string is present" do
      expect(described_class.extract_bazel_version("myorg/bazel-fork/8.0.0")).to eq("8.0.0")
    end

    it "returns empty string for a wrapper-only entry rather than the wrapper's own version" do
      expect(described_class.extract_bazel_version("buildbuddy-io/5.0.321")).to eq("")
      expect(described_class.extract_bazel_version("# wrapper\nbuildbuddy-io/5.0.321\n")).to eq("")
    end

    it "matches wrapper orgs case-insensitively (GitHub orgs are case-insensitive)" do
      expect(described_class.extract_bazel_version("BuildBuddy-io/5.0.321")).to eq("")
      expect(described_class.extract_bazel_version("BUILDBUDDY-IO/5.0.321\n9.1.0\n")).to eq("9.1.0")
    end

    it "uses the first surviving line, matching what Bazelisk would execute" do
      expect(described_class.extract_bazel_version("myorg/8.0.0\n9.1.0\n")).to eq("8.0.0")
    end

    it "handles CRLF line endings" do
      expect(described_class.extract_bazel_version("buildbuddy-io/5.0.321\r\n9.1.0\r\n")).to eq("9.1.0")
    end

    it "returns empty string for nil or empty input or slash-only input" do
      expect(described_class.extract_bazel_version(nil)).to eq("")
      expect(described_class.extract_bazel_version("   \n  ")).to eq("")
      expect(described_class.extract_bazel_version("///")).to eq("")
    end
  end

  describe ".bazelisk_target_from_file" do
    def file_with(content)
      Dependabot::DependencyFile.new(name: ".bazelversion", content: content)
    end

    it "returns a plain version untouched" do
      expect(described_class.bazelisk_target_from_file(file_with("9.1.0\n"))).to eq("9.1.0")
    end

    it "preserves a fork target verbatim" do
      expect(described_class.bazelisk_target_from_file(file_with("myorg/8.0.0\n"))).to eq("myorg/8.0.0")
    end

    it "drops BuildBuddy wrapper lines and returns the underlying Bazel entry" do
      content = "buildbuddy-io/5.0.321\n9.1.0\n"
      expect(described_class.bazelisk_target_from_file(file_with(content))).to eq("9.1.0")
    end

    it "preserves Bazelisk-relative values verbatim — Bazelisk understands them" do
      expect(described_class.bazelisk_target_from_file(file_with("latest\n"))).to eq("latest")
      expect(described_class.bazelisk_target_from_file(file_with("buildbuddy-io/5.0.321\nlast_green\n")))
        .to eq("last_green")
    end

    it "returns nil for wrapper-only, comment-only, empty, or nil files" do
      expect(described_class.bazelisk_target_from_file(file_with("buildbuddy-io/5.0.321\n"))).to be_nil
      expect(described_class.bazelisk_target_from_file(file_with("# just a comment\n"))).to be_nil
      expect(described_class.bazelisk_target_from_file(file_with("  \n"))).to be_nil
      expect(described_class.bazelisk_target_from_file(nil)).to be_nil
    end
  end

  describe ".version_from_file" do
    it "extracts and normalizes version from a DependencyFile" do
      file = Dependabot::DependencyFile.new(name: ".bazelversion", content: "buildbuddy-io/5.0.321\nv9.1.0.bcr.1\n")
      expect(described_class.version_from_file(file)).to eq("9.1.0")
    end

    it "returns nil when file is nil or empty" do
      expect(described_class.version_from_file(nil)).to be_nil
      file = Dependabot::DependencyFile.new(name: ".bazelversion", content: "   \n")
      expect(described_class.version_from_file(file)).to be_nil
    end

    it "returns nil for a wrapper-only file so callers apply their own fallbacks" do
      file = Dependabot::DependencyFile.new(name: ".bazelversion", content: "buildbuddy-io/5.0.321\n")
      expect(described_class.version_from_file(file)).to be_nil
    end

    it "returns nil for Bazelisk-relative values that aren't semantic versions" do
      %w(latest last_green last_rc rolling myorg/last_green).each do |content|
        file = Dependabot::DependencyFile.new(name: ".bazelversion", content: content)
        expect(described_class.version_from_file(file)).to be_nil
      end
    end
  end
end
