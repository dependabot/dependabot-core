# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions"

RSpec.describe Dependabot::GithubActions::Version do
  semver_version = "v1.2.3"
  semver_without_v = "1.2.3"

  describe "#correct?" do
    it "accepts semver" do
      expect(described_class.correct?(semver_version)).to eq(true)
    end

    it "accepts semver without v" do
      expect(described_class.correct?(semver_without_v)).to eq(true)
    end
  end

  describe "#initialize" do
    it "accepts semver" do
      version = described_class.new(semver_version)
      expect(version.to_s).to eq(semver_without_v)
    end

    it "accepts semver without v" do
      version = described_class.new(semver_without_v)
      expect(version.to_s).to eq(semver_without_v)
    end

    it "normalizes semver v" do
      version = described_class.new(semver_version)
      version_without_v = described_class.new(semver_without_v)
      expect(version).to eq(version_without_v)
    end
  end
end
