# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker/tag"

RSpec.describe Dependabot::Docker::Tag do
  describe "#same_but_more_precise?" do
    it "returns true when receiver is the same version as the parameter, just less precise, false otherwise" do
      expect(described_class.new("2.4").same_but_less_precise?(described_class.new("2.4.2"))).to be true
      expect(described_class.new("2.4").same_but_less_precise?(described_class.new("2.42"))).to be false
    end
  end

  describe "#looks_like_prerelease?" do
    context "with prerelease tags" do
      it "detects alpha versions" do
        expect(described_class.new("3.15.0a2").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-alpha").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-alpha.1").looks_like_prerelease?).to be true
        expect(described_class.new("2.0-ALPHA").looks_like_prerelease?).to be true
      end

      it "detects beta versions" do
        expect(described_class.new("3.5.0b3").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-beta").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-beta.1").looks_like_prerelease?).to be true
        expect(described_class.new("2.0-BETA").looks_like_prerelease?).to be true
      end

      it "detects release candidate versions" do
        expect(described_class.new("3.6.0rc1").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-rc").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-rc.1").looks_like_prerelease?).to be true
        expect(described_class.new("2.0-RC").looks_like_prerelease?).to be true
      end

      it "detects dev versions" do
        expect(described_class.new("1.0-dev").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-DEV").looks_like_prerelease?).to be true
      end

      it "detects preview versions" do
        expect(described_class.new("1.0-preview").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-PREVIEW").looks_like_prerelease?).to be true
      end

      it "detects pre versions" do
        expect(described_class.new("1.0-pre").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-PRE").looks_like_prerelease?).to be true
      end

      it "detects nightly versions" do
        expect(described_class.new("1.0-nightly").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-NIGHTLY").looks_like_prerelease?).to be true
      end

      it "detects snapshot versions" do
        expect(described_class.new("1.0-snapshot").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-SNAPSHOT").looks_like_prerelease?).to be true
      end

      it "detects canary versions" do
        expect(described_class.new("1.0-canary").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-CANARY").looks_like_prerelease?).to be true
      end

      it "detects unstable versions" do
        expect(described_class.new("1.0-unstable").looks_like_prerelease?).to be true
        expect(described_class.new("1.0.0-UNSTABLE").looks_like_prerelease?).to be true
      end

      it "detects Python PEP 440 pre-release formats" do
        # Pre-release segment: {a|b|rc}N
        expect(described_class.new("1.0.0a1").looks_like_prerelease?).to be true
        expect(described_class.new("2.1.0b2").looks_like_prerelease?).to be true
        expect(described_class.new("3.2.0rc3").looks_like_prerelease?).to be true
      end

      it "detects Python PEP 440 post-release formats" do
        # Post-release segment: .postN
        expect(described_class.new("1.0.0.post1").looks_like_prerelease?).to be true
        expect(described_class.new("2.1.0.POST2").looks_like_prerelease?).to be true
      end

      it "detects Python PEP 440 development release formats" do
        # Development release segment: .devN
        expect(described_class.new("1.0.0.dev0").looks_like_prerelease?).to be true
        expect(described_class.new("2.1.0.DEV1").looks_like_prerelease?).to be true
      end
    end

    context "with stable tags" do
      it "does not detect stable versions as prereleases" do
        expect(described_class.new("3.14.1").looks_like_prerelease?).to be false
        expect(described_class.new("1.0.0").looks_like_prerelease?).to be false
        expect(described_class.new("2.4.2").looks_like_prerelease?).to be false
      end

      it "does not detect tags with suffix as prereleases" do
        expect(described_class.new("3.14.1-slim-trixie").looks_like_prerelease?).to be false
        expect(described_class.new("3.6.3-alpine").looks_like_prerelease?).to be false
        expect(described_class.new("2.7.14-stretch").looks_like_prerelease?).to be false
      end
    end
  end

  describe "#dated_version?" do
    context "with dated versions" do
      it "detects 8-digit date components in the version" do
        expect(described_class.new("4.8-20250909-windowsservercore-ltsc2022").dated_version?).to be true
        expect(described_class.new("4.8.1-20251014-windowsservercore-ltsc2022").dated_version?).to be true
        expect(described_class.new("3.3-20220922").dated_version?).to be true
      end
    end

    context "with non-dated versions" do
      it "does not detect standard versions as dated" do
        expect(described_class.new("4.8.1-windowsservercore-ltsc2022").dated_version?).to be false
        expect(described_class.new("4.8-windowsservercore-ltsc2022").dated_version?).to be false
        expect(described_class.new("17.10").dated_version?).to be false
        expect(described_class.new("2.4.0-slim").dated_version?).to be false
        expect(described_class.new("1.27.0-alpine3.23").dated_version?).to be false
      end

      it "does not detect short numeric segments as dates" do
        expect(described_class.new("1803-KB4487017").dated_version?).to be false
        expect(described_class.new("22-ea-7").dated_version?).to be false
      end
    end

    context "with non-comparable versions" do
      it "returns false" do
        expect(described_class.new("latest").dated_version?).to be false
        expect(described_class.new("artful").dated_version?).to be false
      end
    end
  end

  describe "#comparable_to?" do
    context "when timestamp validation is disabled" do
      it "treats dated and non-dated versions with same suffix as comparable" do
        dated = described_class.new("4.8-20250909-windowsservercore-ltsc2022")
        non_dated = described_class.new("4.8.1-windowsservercore-ltsc2022")

        expect(dated.comparable_to?(non_dated)).to be true
        expect(non_dated.comparable_to?(dated)).to be true
      end
    end

    context "when timestamp validation is enabled" do
      before { Dependabot::Experiments.register(:docker_created_timestamp_validation, true) }
      after { Dependabot::Experiments.reset! }

      it "treats dated and non-dated versions as incomparable" do
        dated = described_class.new("4.8-20250909-windowsservercore-ltsc2022")
        non_dated = described_class.new("4.8.1-windowsservercore-ltsc2022")

        expect(dated.comparable_to?(non_dated)).to be false
        expect(non_dated.comparable_to?(dated)).to be false
      end
    end

    it "treats two dated versions with the same suffix as comparable" do
      tag1 = described_class.new("4.8-20250909-windowsservercore-ltsc2022")
      tag2 = described_class.new("4.8.1-20251014-windowsservercore-ltsc2022")

      expect(tag1.comparable_to?(tag2)).to be true
      expect(tag2.comparable_to?(tag1)).to be true
    end

    it "treats two non-dated versions with the same suffix as comparable" do
      tag1 = described_class.new("4.8-windowsservercore-ltsc2022")
      tag2 = described_class.new("4.8.1-windowsservercore-ltsc2022")

      expect(tag1.comparable_to?(tag2)).to be true
      expect(tag2.comparable_to?(tag1)).to be true
    end
  end

  describe "#numeric_version" do
    context "when timestamp validation is disabled" do
      it "includes date components in the numeric version" do
        expect(described_class.new("4.8-20250909-windowsservercore-ltsc2022").numeric_version).to eq("4.8-20250909")
        expect(described_class.new("4.8.1-20251014-windowsservercore-ltsc2022").numeric_version).to eq("4.8.1-20251014")
      end
    end

    context "when timestamp validation is enabled" do
      before { Dependabot::Experiments.register(:docker_created_timestamp_validation, true) }
      after { Dependabot::Experiments.reset! }

      it "strips date components so they don't inflate semver" do
        expect(described_class.new("4.8-20250909-windowsservercore-ltsc2022").numeric_version).to eq("4.8")
        expect(described_class.new("4.8.1-20251014-windowsservercore-ltsc2022").numeric_version).to eq("4.8.1")
        expect(described_class.new("4.8.1-20260301-windowsservercore-ltsc2022").numeric_version).to eq("4.8.1")
      end

      it "ensures dated and non-dated tags with same base version compare equal" do
        tag_dated = described_class.new("4.8.1-20251014-windowsservercore-ltsc2022")
        tag_non_dated = described_class.new("4.8.1-windowsservercore-ltsc2022")

        expect(tag_dated.numeric_version).to eq(tag_non_dated.numeric_version)
      end
    end

    it "preserves non-dated version numbers unchanged" do
      expect(described_class.new("4.8.1-windowsservercore-ltsc2022").numeric_version).to eq("4.8.1")
      expect(described_class.new("4.8-windowsservercore-ltsc2022").numeric_version).to eq("4.8")
      expect(described_class.new("17.10").numeric_version).to eq("17.10")
      expect(described_class.new("2.4.0-slim").numeric_version).to eq("2.4.0")
    end
  end
end
