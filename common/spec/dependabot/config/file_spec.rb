# frozen_string_literal: true

require "spec_helper"
require "dependabot/config"
require "dependabot/config/file"
require "dependabot/config/update_config"

RSpec.describe Dependabot::Config::File do
  describe "#parse" do
    it "parses the config file" do
      cfg = Dependabot::Config::File.parse(fixture("configfile", "bundler-daily.yml"))
      expect(cfg.updates.size).to eq(1)
    end

    it "rejects version:1 config file" do
      expect { Dependabot::Config::File.parse("version: 1\n") }.
        to raise_error(Dependabot::Config::InvalidConfigError)
    end
  end

  describe "File" do
    let(:config) { Dependabot::Config::File.parse(fixture("configfile", "npm-weekly.yml")) }

    describe "#update_config" do
      it "maps package_manager to package-ecosystem" do
        update_config = config.update_config("npm_and_yarn")
        expect(update_config).to be_a(Dependabot::Config::UpdateConfig)
        expect(update_config.interval).to eq("weekly")
      end

      it "matches directory" do
        update_config = config.update_config("npm_and_yarn", directory: "/monthly")
        expect(update_config).to be_a(Dependabot::Config::UpdateConfig)
        expect(update_config.interval).to eq("monthly")
      end

      it "returns empty when not found" do
        update_config = config.update_config("bundler")
        expect(update_config).to be_a(Dependabot::Config::UpdateConfig)
        expect(update_config.interval).to be_nil
      end
    end
  end
end
