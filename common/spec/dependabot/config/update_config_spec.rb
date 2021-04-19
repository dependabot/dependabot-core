# frozen_string_literal: true

require "spec_helper"
require "dependabot/config"
require "dependabot/config/file"
require "dependabot/config/update_config"

RSpec.describe Dependabot::Config::UpdateConfig do
  let(:config) { Dependabot::Config::File.parse(fixture("configfile", "npm-weekly.yml")) }

  describe "#interval" do
    it "returns normalized value" do
      update_config = Dependabot::Config::UpdateConfig.new({ schedule: { interval: "WeeKLY" } })
      expect(update_config.interval).
        to eq(Dependabot::Config::UpdateConfig::Interval::WEEKLY)
    end

    it "raises on invalid value" do
      update_config = Dependabot::Config::UpdateConfig.new({ schedule: { interval: "gibbous moon" } })
      expect { update_config.interval }.
        to raise_error(Dependabot::Config::InvalidConfigError)
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
    let(:config) { Dependabot::Config::File.parse(fixture("configfile", "commit-message-options.yml")) }

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
