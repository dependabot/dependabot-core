# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions"

RSpec.describe Dependabot::GithubActions::Version do
  let(:semver_version) { "v1.2.3" }
  let(:semver_without_v) { "1.2.3" }
  let(:path_based_sem_version) { "dummy/v1.2.3" }
  let(:path_based_sem_without_v) { "dummy/1.2.3" }
  let(:name_prefixed_version) { "resolve-gh-token-v2.1.0" }
  let(:name_prefixed_prerelease) { "resolve-gh-token-v2.1.0-beta.1" }

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

    it "accepts monorepo action-name prefixed tags" do
      expect(described_class.correct?(name_prefixed_version)).to be(true)
    end

    it "rejects non-version refs" do
      expect(described_class.correct?("main")).to be(false)
    end

    it "does not mangle hyphenated date-style version tags" do
      # Regression guard: greedy prefix-stripping must not turn "2021-01-01" into "01".
      expect(described_class.new("2021-01-01").segments.first).to eq(2021)
    end

    it "does not strip a '-v' that is part of the version itself" do
      # Regression guard: name-prefix stripping must not turn "1.0.0-v2" into "2".
      expect(described_class.new("1.0.0-v2")).not_to eq(described_class.new("2"))
      expect(described_class.new("1.0.0-v2").segments.first).to eq(1)
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

    it "strips action-name prefix from monorepo tags" do
      version = described_class.new(name_prefixed_version)
      expect(version.to_s).to eq("2.1.0")
    end

    it "preserves prerelease suffixes on name prefixed tags" do
      version = described_class.new(name_prefixed_prerelease)
      expect(version).to eq(described_class.new("2.1.0-beta.1"))
      expect(version.prerelease?).to be(true)
    end

    it "strips only the action-name prefix, not a '-v' inside the version" do
      # Regression guard: "action-v1.0.0-v2" must become "1.0.0-v2", not "2".
      version = described_class.new("action-v1.0.0-v2")
      expect(version).to eq(described_class.new("1.0.0-v2"))
      expect(version.segments.first).to eq(1)
    end

    it "handles action names that themselves contain '-v<digit>'" do
      # "cache-v2-helper-v1.0.0" must normalize to 1.0.0, not "2-helper-v1.0.0".
      expect(described_class.new("cache-v2-helper-v1.0.0")).to eq(described_class.new("1.0.0"))
      expect(described_class.new("cache-v2-helper-v2")).to eq(described_class.new("2"))
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
end
