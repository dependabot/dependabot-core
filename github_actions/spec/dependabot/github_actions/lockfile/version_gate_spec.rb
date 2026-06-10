# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions/lockfile"

RSpec.describe Dependabot::GithubActions::Lockfile::VersionGate do
  describe ".compatible?" do
    it "accepts the supported version" do
      expect(described_class.compatible?("v0.0.1")).to be(true)
    end

    it "accepts a newer patch within the same v0 minor" do
      expect(described_class.compatible?("v0.0.9")).to be(true)
    end

    it "rejects a different v0 minor (0.x is treated as unstable)" do
      expect(described_class.compatible?("v0.4.9")).to be(false)
    end

    it "rejects a different major" do
      expect(described_class.compatible?("v1.0.0")).to be(false)
    end

    it "rejects blank input" do
      expect(described_class.compatible?("")).to be(false)
    end
  end

  describe ".assert_supported!" do
    it "does not raise for a supported version" do
      expect { described_class.assert_supported!("v0.0.1") }.not_to raise_error
    end

    it "raises UnsupportedLockfileVersion for an unknown major" do
      expect { described_class.assert_supported!("v2.0.0") }
        .to raise_error(Dependabot::GithubActions::Lockfile::UnsupportedLockfileVersion, /v2.0.0/)
    end
  end
end
