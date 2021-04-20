# frozen_string_literal: true

require "spec_helper"
require "dependabot/config"
require "dependabot/config/file"
require "dependabot/config/update_config"

RSpec.describe Dependabot::Config::UpdateConfig do
  let(:data) { nil }
  let(:config) { Dependabot::Config::UpdateConfig.new(data) }

  describe "#interval" do
    subject(:interval) { config.interval }

    it "returns nil if not specified" do
      expect(interval).to be_nil
    end

    context "with denormalized interval" do
      let(:data) { { schedule: { interval: "WeeKLY" } } }

      it "returns normalized value" do
        expect(interval).to eq(Dependabot::Config::UpdateConfig::Interval::WEEKLY)
      end
    end

    context "with invalid interval" do
      let(:data) { { schedule: { interval: "gibbous moon" } } }
      it "raises error" do
        expect { interval }.
          to raise_error(Dependabot::Config::InvalidConfigError)
      end
    end
  end

  describe "#ignored_versions_for" do
    subject(:ignored_versions) { config.ignored_versions_for(dependency) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "@types/node",
        requirements: [],
        version: "12.12.6",
        package_manager: "npm_and_yarn"
      )
    end

    it "returns empty when not defined" do
      expect(ignored_versions).to eq([])
    end

    context "with ignored versions" do
      let(:data) do
        { ignore: [{ "dependency-name": "@types/node", versions: [">= 14.14.x, < 15"] }] }
      end

      it "returns versions" do
        expect(ignored_versions).to eq([">= 14.14.x, < 15"])
      end
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
