# frozen_string_literal: true

require "spec_helper"
require "dependabot/job"
require "dependabot/dependency"
require "dependabot/bundler"

RSpec.describe Dependabot::Job do
  subject(:job) { described_class.new(attributes) }

  let(:attributes) do
    {
      token: "token",
      dependencies: dependencies,
      allowed_updates: allowed_updates,
      existing_pull_requests: [],
      ignore_conditions: [],
      security_advisories: security_advisories,
      package_manager: package_manager,
      source: {
        "provider" => "github",
        "repo" => "dependabot-fixtures/dependabot-test-ruby-package",
        "directory" => "/",
        "api-endpoint" => "https://api.github.com/",
        "hostname" => "github.com",
        "branch" => nil
      },
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "github-token"
      }],
      lockfile_only: false,
      requirements_update_strategy: nil,
      update_subdependencies: false,
      updating_a_pull_request: false,
      vendor_dependencies: vendor_dependencies,
      experiments: experiments,
      commit_message_options: commit_message_options,
      security_updates_only: security_updates_only
    }
  end

  let(:dependencies) { nil }
  let(:security_advisories) { [] }
  let(:package_manager) { "bundler" }
  let(:security_updates_only) { false }
  let(:allowed_updates) do
    [
      {
        "dependency-type" => "direct",
        "update-type" => "all"
      },
      {
        "dependency-type" => "indirect",
        "update-type" => "security"
      }
    ]
  end
  let(:experiments) { nil }
  let(:commit_message_options) { nil }
  let(:vendor_dependencies) { false }

  describe "#allowed_update?" do
    subject { job.allowed_update?(dependency) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        package_manager: "bundler",
        version: "1.8.0",
        requirements: requirements
      )
    end
    let(:dependency_name) { "business" }
    let(:requirements) do
      [{ file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }]
    end

    context "with default allowed updates on a dependency with no requirements" do
      let(:allowed_updates) do
        [
          {
            "dependency-type" => "direct",
            "update-type" => "all"
          }
        ]
      end
      let(:security_advisories) do
        [
          {
            "dependency-name" => dependency_name,
            "affected-versions" => [],
            "patched-versions" => ["~> 1.11.0"],
            "unaffected-versions" => []
          }
        ]
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          package_manager: "bundler",
          version: "1.8.0",
          requirements: []
        )
      end
      it { is_expected.to eq(false) }

      context "for a security update" do
        let(:security_updates_only) { true }
        it { is_expected.to eq(true) }
      end
    end

    context "with a top-level dependency" do
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }]
      end

      it { is_expected.to eq(true) }
    end

    context "with a sub-dependency" do
      let(:requirements) { [] }
      it { is_expected.to eq(false) }

      context "that is insecure" do
        let(:security_advisories) do
          [
            {
              "dependency-name" => "business",
              "affected-versions" => [],
              "patched-versions" => ["~> 1.11.0"],
              "unaffected-versions" => []
            }
          ]
        end

        it { is_expected.to eq(true) }
      end
    end

    context "when only security fixes are allowed" do
      let(:security_updates_only) { true }
      it { is_expected.to eq(false) }

      context "for a security fix" do
        let(:security_advisories) do
          [
            {
              "dependency-name" => "business",
              "affected-versions" => [],
              "patched-versions" => ["~> 1.11.0"],
              "unaffected-versions" => []
            }
          ]
        end

        it { is_expected.to eq(true) }
      end

      context "for a security fix that doesn't apply" do
        let(:security_advisories) do
          [
            {
              "dependency-name" => "business",
              "affected-versions" => ["> 1.8.0"],
              "patched-versions" => [],
              "unaffected-versions" => []
            }
          ]
        end

        it { is_expected.to eq(false) }
      end

      context "for a security fix that doesn't apply to some versions" do
        let(:security_advisories) do
          [
            {
              "dependency-name" => "business",
              "affected-versions" => ["> 1.8.0"],
              "patched-versions" => [],
              "unaffected-versions" => []
            }
          ]
        end

        it "should be allowed" do
          dependency.metadata[:all_versions] = [
            Dependabot::Dependency.new(
              name: dependency_name,
              package_manager: "bundler",
              version: "1.8.0",
              requirements: []
            ),
            Dependabot::Dependency.new(
              name: dependency_name,
              package_manager: "bundler",
              version: "1.9.0",
              requirements: []
            )
          ]

          is_expected.to eq(true)
        end
      end
    end

    context "and a dependency whitelist that includes the dependency" do
      let(:allowed_updates) { [{ "dependency-name" => "business" }] }
      it { is_expected.to eq(true) }

      context "with a dependency whitelist that uses a wildcard" do
        let(:allowed_updates) { [{ "dependency-name" => "bus*" }] }
        it { is_expected.to eq(true) }
      end
    end

    context "and a dependency whitelist that excludes the dependency" do
      let(:allowed_updates) { [{ "dependency-name" => "rails" }] }
      it { is_expected.to eq(false) }

      context "that would match if we were sloppy about substrings" do
        let(:allowed_updates) { [{ "dependency-name" => "bus" }] }
        it { is_expected.to eq(false) }
      end

      context "with a dependency whitelist that uses a wildcard" do
        let(:allowed_updates) { [{ "dependency-name" => "b.ness*" }] }
        it { is_expected.to eq(false) }
      end

      context "when security fixes are also allowed" do
        let(:allowed_updates) do
          [
            { "dependency-name" => "rails" },
            { "update-type" => "security" }
          ]
        end

        it { is_expected.to eq(false) }

        context "for a security fix" do
          let(:security_advisories) do
            [
              {
                "dependency-name" => "business",
                "affected-versions" => [],
                "patched-versions" => ["~> 1.11.0"],
                "unaffected-versions" => []
              }
            ]
          end

          it { is_expected.to eq(true) }
        end
      end
    end

    context "with dev dependencies during a security update while allowed: production is in effect" do
      let(:package_manager) { "npm_and_yarn" }
      let(:security_updates_only) { true }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ansi-regex",
          package_manager: "npm_and_yarn",
          version: "6.0.0",
          requirements: [
            {
              file: "package.json",
              requirement: "^6.0.0",
              groups: ["devDependencies"],
              source: {
                type: "registry",
                url: "https://registry.npmjs.org"
              }
            }
          ]
        )
      end
      let(:security_advisories) do
        [
          {
            "dependency-name" => "ansi-regex",
            "affected-versions" => [
              ">= 3.0.0 < 3.0.1",
              ">= 4.0.0 < 4.1.1",
              ">= 5.0.0 < 5.0.1",
              ">= 6.0.0 < 6.0.1"
            ],
            "patched-versions" => [],
            "unaffected-versions" => []
          }
        ]
      end
      let(:allowed_updates) do
        [{ "dependency-type" => "production" }]
      end
      it { is_expected.to eq(false) }
    end
  end

  describe "#security_updates_only?" do
    subject { job.security_updates_only? }

    it { is_expected.to eq(false) }

    context "with security only allowed updates" do
      let(:security_updates_only) { true }

      it { is_expected.to eq(true) }
    end
  end

  describe "#experiments" do
    it "handles nil values" do
      expect(job.experiments).to eq({})
    end

    context "with experiments" do
      let(:experiments) { { "simple" => false, "kebab-case" => true } }

      it "transforms the keys" do
        expect(job.experiments).to eq(simple: false, kebab_case: true)
      end

      it "registers the experiments with Dependabot::Experiments" do
        job
        expect(Dependabot::Experiments.enabled?(:kebab_case)).to be_truthy
        expect(Dependabot::Experiments.enabled?(:simpe)).to be_falsey
      end
    end

    context "with experimental values" do
      let(:experiments) { { "timeout_per_operation_seconds" => 600 } }

      it "preserves the values" do
        expect(job.experiments).to eq(timeout_per_operation_seconds: 600)
      end
    end
  end

  describe "#commit_message_options" do
    it "handles nil values" do
      expect(job.commit_message_options).to eq({})
    end

    context "with commit_message_options" do
      let(:commit_message_options) do
        {
          "prefix" => "[dev]",
          "prefix-development" => "[bump-dev]",
          "include-scope" => true
        }
      end

      it "transforms the keys" do
        expect(job.commit_message_options[:prefix]).to eq("[dev]")
        expect(job.commit_message_options[:prefix_development]).to eq("[bump-dev]")
        expect(job.commit_message_options[:include_scope]).to eq(true)
      end
    end

    context "with partial commit_message_options" do
      let(:commit_message_options) do
        {
          "prefix" => "[dev]"
        }
      end

      it "transforms the keys" do
        expect(job.commit_message_options[:prefix]).to eq("[dev]")
        expect(job.commit_message_options).not_to have_key(:prefix_development)
        expect(job.commit_message_options).not_to have_key(:include_scope)
      end
    end
  end

  describe "#clone?" do
    subject { job.clone? }

    it { is_expected.to eq(false) }

    context "with vendoring configuration enabled" do
      let(:vendor_dependencies) { true }

      it { is_expected.to eq(true) }
    end

    context "for ecosystems that always clone" do
      let(:vendor_dependencies) { false }
      let(:dependencies) do
        [
          Dependabot::Dependency.new(
            name: "github.com/pkg/errors",
            package_manager: "go_modules",
            version: "v1.8.0",
            requirements: [
              {
                file: "go.mod",
                requirement: "v1.8.0",
                groups: [],
                source: nil
              }
            ]
          )
        ]
      end
      let(:package_manager) { "go_modules" }

      it { is_expected.to eq(true) }
    end
  end

  describe "#security_fix?" do
    subject { job.security_fix?(dependency) }

    let(:dependency) do
      Dependabot::Dependency.new(
        package_manager: "bundler",
        name: "business",
        version: dependency_version,
        previous_version: dependency_previous_version,
        requirements: [],
        previous_requirements: []
      )
    end
    let(:dependency_version) { "1.11.1" }
    let(:dependency_previous_version) { "0.7.1" }
    let(:security_advisories) do
      [
        {
          "dependency-name" => "business",
          "affected-versions" => [],
          "patched-versions" => ["~> 1.11.0"],
          "unaffected-versions" => []
        }
      ]
    end

    it { is_expected.to eq(true) }

    context "when the update hasn't been patched" do
      let(:dependency_version) { "1.10.0" }

      it { is_expected.to eq(false) }
    end
  end

  describe "#reject_external_code?" do
    it "defaults to false" do
      expect(job.reject_external_code?).to eq(false)
    end

    it "can be enabled by job attributes" do
      attrs = attributes
      attrs[:reject_external_code] = true
      job = Dependabot::Job.new(attrs)
      expect(job.reject_external_code?).to eq(true)
    end
  end
end
