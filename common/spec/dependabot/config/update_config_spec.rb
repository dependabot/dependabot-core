# frozen_string_literal: true

require "spec_helper"
require "dependabot/config"
require "dependabot/config/file"
require "dependabot/config/update_config"

RSpec.describe Dependabot::Config::UpdateConfig do
  describe "#ignored_versions_for" do
    subject(:ignored_versions) { config.ignored_versions_for(dependency, security_updates_only: security_updates_only) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "@types/node",
        requirements: [],
        version: "12.12.6",
        package_manager: "dummy"
      )
    end
    let(:ignore_conditions) { [] }
    let(:config) { described_class.new(ignore_conditions: ignore_conditions) }
    let(:security_updates_only) { false }

    it "returns empty when not defined" do
      expect(ignored_versions).to eq([])
    end

    context "with ignored versions" do
      let(:ignore_conditions) do
        [Dependabot::Config::IgnoreCondition.new(dependency_name: "@types/node",
                                                 versions: [">= 14.14.x, < 15"])]
      end

      it "returns versions" do
        expect(ignored_versions).to eq([">= 14.14.x, < 15"])
      end
    end

    context "with a wildcard dependency name" do
      let(:ignore_conditions) do
        [
          Dependabot::Config::IgnoreCondition.new(
            dependency_name: "@types/*",
            versions: [">= 14.14.x, < 15"]
          ),
          Dependabot::Config::IgnoreCondition.new(
            dependency_name: "@types/node",
            versions: [">= 15, < 16"]
          ),
          Dependabot::Config::IgnoreCondition.new(
            dependency_name: "eslint",
            versions: [">= 2.9.0, < 3"]
          )
        ]
      end

      it "returns matched versions" do
        expect(ignored_versions).to eq([">= 14.14.x, < 15", ">= 15, < 16"])
      end
    end

    context "with update_types and versions" do
      let(:ignore_conditions) do
        [Dependabot::Config::IgnoreCondition.new(dependency_name: "@types/node",
                                                 versions: [">= 14.14.x, < 15"],
                                                 update_types: ["version-update:semver-minor"])]
      end

      it "returns versions" do
        expect(ignored_versions).to eq([">= 12.13.a, < 13", ">= 14.14.x, < 15"])
      end
    end

    context "with duplicate update_types" do
      let(:ignore_conditions) do
        [
          Dependabot::Config::IgnoreCondition.new(
            dependency_name: "@types/node",
            update_types: ["version-update:semver-minor"]
          ),
          Dependabot::Config::IgnoreCondition.new(
            dependency_name: "@types/node",
            update_types: ["version-update:semver-minor"]
          )
        ]
      end

      it "returns versions" do
        expect(ignored_versions).to eq([">= 12.13.a, < 13"])
      end
    end

    context "with multiple update_types" do
      let(:ignore_conditions) do
        [
          Dependabot::Config::IgnoreCondition.new(
            dependency_name: "@types/*",
            update_types: ["version-update:semver-major"]
          ),
          Dependabot::Config::IgnoreCondition.new(
            dependency_name: "@types/node",
            update_types: ["version-update:semver-minor"]
          )
        ]
      end

      it "returns versions" do
        expect(ignored_versions).to eq([">= 13.a", ">= 12.13.a, < 13"])
      end

      context "with security_updates_only" do
        let(:security_updates_only) { true }
        it "does not expand versions" do
          expect(ignored_versions).to eq([])
        end
      end
    end

    context "with an dependency that must be name normalized" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "VERY_COOL_PACKAGE",
          requirements: [],
          version: "1.2.3",
          package_manager: "fake-package-manager"
        )
      end
      before do
        Dependabot::Dependency.register_name_normaliser("fake-package-manager", lambda { |name|
                                                                                  name.downcase.gsub(/[_=]/, "-")
                                                                                })
      end

      let(:ignore_conditions) do
        [Dependabot::Config::IgnoreCondition.new(dependency_name: "very-cool-package", versions: [">= 0"])]
      end

      it "normalizes the dependency name to match" do
        expect(ignored_versions).to eq([">= 0"])
      end

      context "and ignore condition that must be normalized" do
        let(:ignore_conditions) do
          [Dependabot::Config::IgnoreCondition.new(dependency_name: "very=cool=package", versions: [">= 1"])]
        end

        it "normalizes the condition dependency_name to match" do
          expect(ignored_versions).to eq([">= 1"])
        end
      end
    end

    context "when the dependency version isn't known" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "actions/checkout",
          requirements: [],
          version: nil,
          package_manager: "github_actions"
        )
      end

      let(:ignore_conditions) do
        [Dependabot::Config::IgnoreCondition.new(dependency_name: "actions/checkout",
                                                 versions: [], update_types: ["version-update:semver-major"])]
      end

      it "returns no ignored versions" do
        expect(ignored_versions).to eq([])
      end
    end
  end

  describe "#commit_message_options" do
    let(:config) { Dependabot::Config::File.parse(fixture("configfile", "commit-message-options.yml")) }

    it "parses prefix" do
      expect(config.update_config("npm_and_yarn").commit_message_options.prefix).to eq("npm")
    end

    it "parses prefix-development" do
      expect(config.update_config("pip").commit_message_options.prefix_development).to eq("pip dev")
    end

    it "includes scope" do
      expect(config.update_config("composer").commit_message_options.include_scope?).to eq(true)
    end

    it "does not include scope" do
      expect(config.update_config("npm_and_yarn").commit_message_options.include_scope?).to eq(false)
    end
  end

  describe ".wildcard_match?" do
    def wildcard_match?(wildcard_string, candidate_string)
      described_class.wildcard_match?(wildcard_string, candidate_string)
    end

    context "without a wildcard" do
      it "with a matching string" do
        expect(wildcard_match?("bus", "bus")).to eq(true)
      end

      it "with different capitalisation" do
        expect(wildcard_match?("bus", "Bus")).to eq(true)
      end

      it "with a superstring" do
        expect(wildcard_match?("bus", "Business")).to eq(false)
      end

      it "with a substring" do
        expect(wildcard_match?("bus", "bu")).to eq(false)
      end

      it "with a string that ends in the same way" do
        expect(wildcard_match?("bus", "blunderbus")).to eq(false)
      end

      it "with a regex character and matching string" do
        expect(wildcard_match?("bus.", "bus.")).to eq(true)
      end

      it "with a regex character and superstring" do
        expect(wildcard_match?("bus.", "bus.iness")).to eq(false)
      end
    end

    context "with a wildcard" do
      it "at the start with a matching string" do
        expect(wildcard_match?("*bus", "*bus")).to eq(true)
      end

      it "at the start with a matching string (except the wildcard)" do
        expect(wildcard_match?("*bus", "bus")).to eq(true)
      end

      it "at the start with a string that ends in the same way" do
        expect(wildcard_match?("*bus", "blunderbus")).to eq(true)
      end

      it "at the start with a superstring" do
        expect(wildcard_match?("*bus", "*business")).to eq(false)
      end

      it "at the start with a substring" do
        expect(wildcard_match?("*bus", "bu")).to eq(false)
      end

      it "at the end with a matching string" do
        expect(wildcard_match?("bus*", "bus*")).to eq(true)
      end

      it "at the end with a matching string (except the wildcard)" do
        expect(wildcard_match?("bus*", "bus")).to eq(true)
      end

      it "at the end with a string that ends in the same way" do
        expect(wildcard_match?("bus*", "blunderbus")).to eq(false)
      end

      it "at the end with a superstring" do
        expect(wildcard_match?("bus*", "bus*iness")).to eq(true)
      end

      it "at the end with a substring" do
        expect(wildcard_match?("bus*", "bu")).to eq(false)
      end

      it "in the middle with a matching string" do
        expect(wildcard_match?("bu*s", "bu*s")).to eq(true)
      end

      it "in the middle with a matching string (except the wildcard)" do
        expect(wildcard_match?("bu*s", "bus")).to eq(true)
      end

      it "in the middle with a string that ends in the same way" do
        expect(wildcard_match?("bu*s", "blunderbus")).to eq(false)
      end

      it "in the middle with a superstring" do
        expect(wildcard_match?("bu*s", "bu*sy")).to eq(false)
      end

      it "in the middle with a substring" do
        expect(wildcard_match?("bu*s", "bu")).to eq(false)
      end

      it "in the middle with a string that starts and ends in the right way" do
        expect(wildcard_match?("bu*s", "business")).to eq(true)
      end

      it "as the only character with a matching string" do
        expect(wildcard_match?("*", "*")).to eq(true)
      end

      it "as the only character with any string" do
        expect(wildcard_match?("*", "bus")).to eq(true)
      end

      it "with multiple wildcards and a string that fits" do
        expect(wildcard_match?("bu*in*ss", "business")).to eq(true)
      end

      it "with multiple wildcards and a string that doesn't" do
        expect(wildcard_match?("bu*in*ss", "buspass")).to eq(false)
      end
    end
  end
end
