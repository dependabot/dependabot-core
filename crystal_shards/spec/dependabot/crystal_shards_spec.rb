# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/crystal_shards"

RSpec.describe Dependabot::CrystalShards do
  describe "registration" do
    it "registers the file fetcher" do
      expect(Dependabot::FileFetchers.for_package_manager("crystal_shards"))
        .to eq(Dependabot::CrystalShards::FileFetcher)
    end

    it "registers the file parser" do
      expect(Dependabot::FileParsers.for_package_manager("crystal_shards"))
        .to eq(Dependabot::CrystalShards::FileParser)
    end

    it "registers the update checker" do
      expect(Dependabot::UpdateCheckers.for_package_manager("crystal_shards"))
        .to eq(Dependabot::CrystalShards::UpdateChecker)
    end

    it "registers the file updater" do
      expect(Dependabot::FileUpdaters.for_package_manager("crystal_shards"))
        .to eq(Dependabot::CrystalShards::FileUpdater)
    end

    it "registers the metadata finder" do
      expect(Dependabot::MetadataFinders.for_package_manager("crystal_shards"))
        .to eq(Dependabot::CrystalShards::MetadataFinder)
    end

    it "registers the version class" do
      expect(Dependabot::Utils.version_class_for_package_manager("crystal_shards"))
        .to eq(Dependabot::CrystalShards::Version)
    end

    it "registers the requirement class" do
      expect(Dependabot::Utils.requirement_class_for_package_manager("crystal_shards"))
        .to eq(Dependabot::CrystalShards::Requirement)
    end
  end

  describe "label details" do
    it "registers PR label details" do
      label_details = Dependabot::PullRequestCreator::Labeler
                      .label_details_for_package_manager("crystal_shards")
      expect(label_details[:name]).to eq("crystal")
      expect(label_details[:colour]).to eq("000000")
    end
  end

  describe "production check" do
    it "treats dependencies group as production" do
      dependency = Dependabot::Dependency.new(
        name: "kemal",
        version: "1.0.0",
        requirements: [{
          file: "shard.yml",
          requirement: "~> 1.0.0",
          groups: ["dependencies"],
          source: nil
        }],
        package_manager: "crystal_shards"
      )
      expect(dependency.production?).to be true
    end

    it "treats development_dependencies group as not production" do
      dependency = Dependabot::Dependency.new(
        name: "webmock",
        version: "0.14.0",
        requirements: [{
          file: "shard.yml",
          requirement: "~> 0.14.0",
          groups: ["development_dependencies"],
          source: nil
        }],
        package_manager: "crystal_shards"
      )
      expect(dependency.production?).to be false
    end

    it "treats empty groups as production" do
      dependency = Dependabot::Dependency.new(
        name: "kemal",
        version: "1.0.0",
        requirements: [{
          file: "shard.yml",
          requirement: "~> 1.0.0",
          groups: [],
          source: nil
        }],
        package_manager: "crystal_shards"
      )
      expect(dependency.production?).to be true
    end
  end
end
