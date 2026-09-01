# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/config"
require "dependabot/config/file"
require "dependabot/config/update_config"

RSpec.describe Dependabot::Config::File do
  describe "#parse" do
    it "parses the config file" do
      cfg = described_class.parse(fixture("configfile", "bundler-daily.yml"))
      expect(cfg.updates.size).to eq(1)
    end

    it "rejects version:1 config file" do
      expect { described_class.parse("version: 1\n") }
        .to raise_error(Dependabot::Config::InvalidConfigError)
    end
  end

  describe "File" do
    let(:config) { described_class.parse(fixture("configfile", "npm-weekly.yml")) }

    describe "#update_config" do
      it "maps package_manager to package-ecosystem" do
        update_config = config.update_config("npm_and_yarn")
        expect(update_config).to be_a(Dependabot::Config::UpdateConfig)
        expect(update_config.commit_message_options.prefix).to eq("no directory")
      end

      it "matches directory" do
        update_config = config.update_config("npm_and_yarn", directory: "/target")
        expect(update_config).to be_a(Dependabot::Config::UpdateConfig)
        expect(update_config.commit_message_options.prefix).to eq("with directory")
      end

      it "matches target-branch" do
        update_config = config.update_config("npm_and_yarn", directory: "/target", target_branch: "the-awesome-branch")
        expect(update_config).to be_a(Dependabot::Config::UpdateConfig)
        expect(update_config.commit_message_options.prefix).to eq("with directory and branch")
      end

      it "returns empty when not found" do
        update_config = config.update_config("bundler")
        expect(update_config).to be_a(Dependabot::Config::UpdateConfig)
        expect(update_config.commit_message_options.prefix).to be_nil
      end

      it "uses codeql as the canonical package-ecosystem spelling" do
        config = described_class.parse(<<~YAML)
          version: 2
          updates:
            - package-ecosystem: codeql
              directory: /
              ignore:
                - dependency-name: codeql/java-all
                  versions: ["1.2.3"]
              commit-message:
                prefix: codeql
              exclude-paths:
                - excluded
        YAML

        update_config = config.update_config("codeql")

        expect(update_config.ignore_conditions.map(&:dependency_name)).to eq(["codeql/java-all"])
        expect(update_config.commit_message_options.prefix).to eq("codeql")
        expect(update_config.exclude_paths).to eq(["excluded"])
      end
    end

    describe "#parse" do
      let(:config) { described_class.parse(fixture("configfile", "ignore-conditions.yml")) }
      let(:update_config) { config.update_config("npm_and_yarn") }

      it "loads ignore conditions" do
        expect(update_config.ignore_conditions.length).to eq(3)
      end

      it "passes update-types" do
        types_ignore = update_config.ignore_conditions.find { |ic| ic.dependency_name == "@types/node" }
        expect(types_ignore.update_types).to eq(["version-update:semver-patch"])
      end
    end
  end
end
