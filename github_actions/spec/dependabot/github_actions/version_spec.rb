# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions"

RSpec.describe Dependabot::GithubActions::Version do
  let(:semver_version) { "v1.2.3" }
  let(:semver_without_v) { "1.2.3" }
  let(:path_based_sem_version) { "dummy/v1.2.3" }
  let(:path_based_sem_without_v) { "dummy/1.2.3" }

  describe "#correct?" do
    it "rejects nil" do
      expect(described_class.correct?(nil)).to be(false)
    end

    it "accepts semver" do
      expect(described_class.correct?(semver_version)).to be(true)
    end

    it "accepts semver without v" do
      expect(described_class.correct?(semver_without_v)).to be(true)
    end

    it "accepts path based sem version" do
      expect(described_class.correct?(path_based_sem_version)).to be(true)
    end

    it "accepts path based sem version without v" do
      expect(described_class.correct?(path_based_sem_without_v)).to be(true)
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

    it "accepts path based sem version" do
      version = described_class.new(path_based_sem_version)
      expect(version.to_s).to eq(semver_without_v)
    end

    it "accepts path based sem version without v" do
      version = described_class.new(path_based_sem_without_v)
      expect(version.to_s).to eq(semver_without_v)
    end

    it "normalizes path based semver v" do
      version = described_class.new(path_based_sem_version)
      version_without_v = described_class.new(path_based_sem_without_v)
      expect(version).to eq(version_without_v)
    end
  end

  describe "#path_based" do
    it "rejects nil" do
      expect(described_class.path_based?(nil)).to be(false)
    end

    it "accepts when tag structure like path based with semver" do
      expect(described_class.path_based?(path_based_sem_version)).to be(true)
    end

    it "accepts when tag structure like path based without semver" do
      expect(described_class.path_based?(path_based_sem_without_v)).to be(true)
    end

    it "reject when tag structure not like path based with semver" do
      expect(described_class.path_based?(semver_version)).to be(false)
    end

    it "reject when tag structure not like path based without semver" do
      expect(described_class.path_based?(semver_without_v)).to be(false)
    end
  end

  describe ".remove_leading_v" do
    it "strips prefixed semver tags" do
      expect(described_class.remove_leading_v("action-v1.2.3")).to eq("1.2.3")
    end

    it "uses the semver boundary when action names include -v digits" do
      expect(described_class.remove_leading_v("cache-v2-helper-v1.0.0")).to eq("1.0.0")
    end

    it "preserves prerelease suffixes" do
      expect(described_class.remove_leading_v("action-v1.0.0-v2")).to eq("1.0.0-v2")
      expect(described_class.remove_leading_v("1.0.0-v2")).to eq("1.0.0-v2")
    end

    it "preserves date-like tags" do
      expect(described_class.remove_leading_v("2021-01-01")).to eq("2021-01-01")
    end

    it "falls back to moving-major tags" do
      expect(described_class.remove_leading_v("action-v2")).to eq("2")
    end
  end
end
