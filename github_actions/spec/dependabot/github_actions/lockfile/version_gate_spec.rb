# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions/lockfile"

RSpec.describe Dependabot::GithubActions::Lockfile::VersionGate do
  describe ".compatible?" do
    it "accepts the supported version" do
      expect(described_class.compatible?("v0.0.2")).to be(true)
    end

    it "rejects the previous schema" do
      expect(described_class.compatible?("v0.0.1")).to be(false)
    end

    it "rejects a newer schema" do
      expect(described_class.compatible?("v0.0.3")).to be(false)
    end

    it "rejects blank input" do
      expect(described_class.compatible?("")).to be(false)
    end
  end

  describe ".assert_supported!" do
    it "does not raise for a supported version" do
      expect { described_class.assert_supported!("v0.0.2") }.not_to raise_error
    end

    it "raises UnsupportedLockfileVersion for an unsupported version" do
      expect { described_class.assert_supported!("v2.0.0") }
        .to raise_error(Dependabot::GithubActions::Lockfile::UnsupportedLockfileVersion, /v2.0.0/)
    end
  end
end
