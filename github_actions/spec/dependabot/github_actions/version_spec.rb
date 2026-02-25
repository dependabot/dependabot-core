# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions"

RSpec.describe Dependabot::GithubActions::Version do
  semver_version = "v1.2.3"
  semver_without_v = "1.2.3"
  path_based_sem_version = "dummy/v1.2.3"
  path_based_sem_without_v = "dummy/1.2.3"

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
end
