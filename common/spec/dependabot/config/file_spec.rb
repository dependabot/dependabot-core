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

      context "with advanced target-branch patterns" do
        let(:yaml) do
          <<~YAML
            version: 2
            updates:
              - package-ecosystem: "npm"
                directory: "/target"
                target-branch: ["branch-a", "branch-b"]
                commit-message:
                  prefix: "array match"
              - package-ecosystem: "npm"
                directory: "/target"
                target-branch: "features/*"
                commit-message:
                  prefix: "glob match"
              - package-ecosystem: "npm"
                directory: "/target"
                target-branch: "${{ github.event.repository.default_branch }}"
                commit-message:
                  prefix: "variable match"
          YAML
        end
        let(:advanced_config) { described_class.parse(yaml) }

        it "matches an array of branches" do
          update_config = advanced_config.update_config("npm_and_yarn", directory: "/target", target_branch: "branch-b")
          expect(update_config.commit_message_options.prefix).to eq("array match")
        end

        it "matches a glob pattern" do
          update_config = advanced_config.update_config(
            "npm_and_yarn",
            directory: "/target",
            target_branch: "features/new-thing"
          )
          expect(update_config.commit_message_options.prefix).to eq("glob match")
        end

        it "matches a gh variable automatically" do
          update_config = advanced_config.update_config(
            "npm_and_yarn",
            directory: "/target",
            target_branch: "any-branch-at-all"
          )
          expect(update_config.commit_message_options.prefix).to eq("variable match")
        end
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
