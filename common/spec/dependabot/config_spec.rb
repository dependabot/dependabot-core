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
end
