# frozen_string_literal: true

require "spec_helper"
require "dependabot/config"

RSpec.describe Dependabot::ConfigFile do
  describe "#parse" do
    it "parses the config file" do
      cfg = Dependabot::ConfigFile.parse(fixture("configfile", "bundler-daily.yml"))
      expect(cfg.updates.size).to eq(1)
    end

    it "rejects version:1 config file" do
      expect { Dependabot::ConfigFile.parse("version: 1\n") }.
        to raise_error(Dependabot::ConfigFile::InvalidConfigError)
    end
  end

  describe "Config" do
    let(:config) { Dependabot::ConfigFile.parse(fixture("configfile", "npm-weekly.yml")) }

    describe "#update_config" do
      it "maps package_manager to package-ecosystem" do
        update_config = config.update_config("npm_and_yarn")
        expect(update_config).to be_a(Dependabot::ConfigFile::UpdateConfig)
        expect(update_config.interval).to eq("weekly")
      end

      it "matches directory" do
        update_config = config.update_config("npm_and_yarn", directory: "/monthly")
        expect(update_config).to be_a(Dependabot::ConfigFile::UpdateConfig)
        expect(update_config.interval).to eq("monthly")
      end

      it "returns empty when not found" do
        update_config = config.update_config("bundler")
        expect(update_config).to be_a(Dependabot::ConfigFile::UpdateConfig)
        expect(update_config.interval).to be_nil
      end
    end
  end

  describe "UpdateConfig" do
    let(:config) { Dependabot::ConfigFile.parse(fixture("configfile", "npm-weekly.yml")) }

    describe "#interval" do
      it "returns normalized value" do
        update_config = Dependabot::ConfigFile::UpdateConfig.new({ schedule: { interval: "WeeKLY" } })
        expect(update_config.interval).
          to eq(Dependabot::ConfigFile::Interval::WEEKLY)
      end

      it "raises on invalid value" do
        update_config = Dependabot::ConfigFile::UpdateConfig.new({ schedule: { interval: "gibbous moon" } })
        expect { update_config.interval }.
          to raise_error(Dependabot::ConfigFile::InvalidConfigError)
      end
    end

    describe "#ignored_versions_for" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "@types/node",
          requirements: [],
          version: "12.12.6",
          package_manager: "npm_and_yarn"
        )
      end

      it "returns versions when not defined" do
        update_config = config.update_config("npm_and_yarn")
        expect(update_config.ignored_versions_for(dependency)).to eq([">= 14.14.x, < 15.x.x"])
      end

      it "returns empty when not defined" do
        update_config = config.update_config("npm_and_yarn", directory: "/monthly")
        expect(update_config.ignored_versions_for(dependency)).to eq([])
      end
    end

    describe "#commit_message_options" do
      let(:config) { Dependabot::ConfigFile.parse(fixture("configfile", "commit-message-options.yml")) }

      it "parses prefix" do
        expect(config.update_config("npm_and_yarn").commit_message_options[:prefix]).to eq("npm")
      end

      it "parses prefix-development" do
        expect(config.update_config("pip").commit_message_options[:prefix_development]).to eq("pip dev")
      end

      it "includes scope" do
        expect(config.update_config("composer").commit_message_options[:include_scope]).to eq(true)
      end

      it "does not include scope" do
        expect(config.update_config("npm_and_yarn").commit_message_options[:include_scope]).to eq(false)
      end
    end
  end
end
