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

      it "accepts exclude_paths parameter and merges with config file exclude_paths" do
        update_config = config.update_config("npm_and_yarn", exclude_paths: ["vendor/*"])
        expect(update_config).to be_a(Dependabot::Config::UpdateConfig)
        expect(update_config.exclude_paths).to eq(["vendor/*"])
      end

      context "when config file has exclude_paths" do
        let(:config_with_excludes) do
          described_class.parse(<<~YAML)
            version: 2
            updates:
              - package-ecosystem: "npm"
                directory: "/"
                schedule:
                  interval: "weekly"
                exclude-paths:
                  - "build/*"
                  - "dist/*"
          YAML
        end

        it "merges parameter exclude_paths with config file exclude_paths" do
          update_config = config_with_excludes.update_config(
            "npm_and_yarn",
            exclude_paths: ["vendor/*", "temp/*"]
          )
          expect(update_config.exclude_paths).to contain_exactly(
            "build/*", "dist/*", "vendor/*", "temp/*"
          )
        end

        it "deduplicates exclude_paths when there are overlaps" do
          update_config = config_with_excludes.update_config(
            "npm_and_yarn",
            exclude_paths: ["build/*", "vendor/*"]
          )
          expect(update_config.exclude_paths).to contain_exactly(
            "build/*", "dist/*", "vendor/*"
          )
        end

        it "works when no parameter exclude_paths provided" do
          update_config = config_with_excludes.update_config("npm_and_yarn")
          expect(update_config.exclude_paths).to contain_exactly(
            "build/*", "dist/*"
          )
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
