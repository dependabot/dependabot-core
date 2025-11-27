# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/crystal_shards/package_manager"

RSpec.describe Dependabot::CrystalShards::PackageManager do
  describe "#initialize" do
    subject(:package_manager) { described_class.new(version) }

    let(:version) { "0.18.0" }

    it "sets the correct name" do
      expect(package_manager.name).to eq("shards")
    end

    it "sets the correct version" do
      expect(package_manager.version).to eq(Dependabot::CrystalShards::Version.new("0.18.0"))
    end
  end

  describe "#deprecated?" do
    subject(:package_manager) { described_class.new("0.18.0") }

    it "returns false" do
      expect(package_manager.deprecated?).to be false
    end
  end

  describe "#unsupported?" do
    subject(:package_manager) { described_class.new("0.18.0") }

    it "returns false" do
      expect(package_manager.unsupported?).to be false
    end
  end

  describe "constants" do
    it "defines ECOSYSTEM" do
      expect(Dependabot::CrystalShards::ECOSYSTEM).to eq("crystal_shards")
    end

    it "defines PACKAGE_MANAGER" do
      expect(Dependabot::CrystalShards::PACKAGE_MANAGER).to eq("shards")
    end

    it "defines MANIFEST_FILE" do
      expect(Dependabot::CrystalShards::MANIFEST_FILE).to eq("shard.yml")
    end

    it "defines LOCKFILE" do
      expect(Dependabot::CrystalShards::LOCKFILE).to eq("shard.lock")
    end

    it "defines DEFAULT_SHARDS_VERSION" do
      expect(Dependabot::CrystalShards::DEFAULT_SHARDS_VERSION).to eq("0.18.0")
    end
  end
end
