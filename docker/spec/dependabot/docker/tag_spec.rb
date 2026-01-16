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
end
