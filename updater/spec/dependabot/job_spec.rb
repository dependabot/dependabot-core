# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/job"
require "dependabot/dependency"
require "support/dummy_package_manager/dummy"

require "dependabot/bundler"

RSpec.describe Dependabot::Job do
  subject(:job) { described_class.new(attributes) }

  let(:attributes) do
    {
      id: "1",
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
        "directory" => directory,
        "directories" => directories,
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
      lockfile_only: lockfile_only,
      requirements_update_strategy: nil,
      update_subdependencies: false,
      updating_a_pull_request: false,
      vendor_dependencies: vendor_dependencies,
      experiments: experiments,
      commit_message_options: commit_message_options,
      security_updates_only: security_updates_only,
      dependency_groups: dependency_groups,
      repo_private: repo_private
    }
  end

  let(:directory) { "/" }
  let(:directories) { nil }
  let(:dependencies) { nil }
  let(:security_advisories) { [] }
  let(:package_manager) { "bundler" }
  let(:lockfile_only) { false }
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
  let(:dependency_groups) { [] }
  let(:repo_private) { false }

  describe "::new_update_job" do
    let(:job_json) { fixture("jobs/job_with_credentials.json") }

    let(:new_update_job) do
      described_class.new_update_job(
        job_id: "1",
        job_definition: JSON.parse(job_json),
        repo_contents_path: "repo"
      )
    end

    it "correctly replaces the credentials with the credential-metadata" do
      expect(new_update_job.credentials.length).to be(2)

      git_credential = new_update_job.credentials.find { |creds| creds["type"] == "git_source" }
      expect(git_credential["host"]).to eql("github.com")
      expect(git_credential.keys).not_to include("username", "password")

      ruby_credential = new_update_job.credentials.find { |creds| creds["type"] == "rubygems_index" }
      expect(ruby_credential["host"]).to eql("my.rubygems-host.org")
      expect(ruby_credential.keys).not_to include("token")
    end

    context "when the directory does not start with a slash" do
      let(:directory) { "hello" }

      it "adds a slash to the directory" do
        expect(job.source.directory).to eq("/hello")
      end
    end

    context "when the directory uses relative path notation" do
      let(:directory) { "hello/world/.." }

      it "cleans the path" do
        expect(job.source.directory).to eq("/hello")
      end
    end

    context "when the directory is nil because it's a grouped security update" do
      let(:directory) { nil }
      let(:directories) { %w(/hello /world) }

      it "doesn't raise an error" do
        expect(job.source.directory).to be_nil
      end
    end

    context "when neither directory nor directories are provided" do
      let(:directory) { nil }
      let(:directories) { nil }

      it "raises a helpful error" do
        expect { job.source.directory }.to raise_error
      end
    end

    context "when both directory and directories are provided" do
      let(:directory) { "hello" }
      let(:directories) { %w(/hello /world) }

      it "raises a helpful error" do
        expect { job.source.directory }.to raise_error
      end
    end
  end

  context "when lockfile_only is passed as true" do
    let(:lockfile_only) { true }

    it "infers a lockfile_only requirements_update_strategy" do
      expect(job.requirements_update_strategy).to eq(Dependabot::RequirementsUpdateStrategy::LockfileOnly)
    end
  end

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

      it { is_expected.to be(false) }

      context "when dealing with a security update" do
        let(:security_updates_only) { true }

        it { is_expected.to be(true) }
      end
    end

    context "with a top-level dependency" do
      let(:requirements) do
        [{ file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }]
      end

      it { is_expected.to be(true) }
    end

    context "with a sub-dependency" do
      let(:requirements) { [] }

      it { is_expected.to be(false) }

      context "when insecure" do
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

        it { is_expected.to be(true) }
      end
    end

    context "when only security fixes are allowed" do
      let(:security_updates_only) { true }

      it { is_expected.to be(false) }

      context "when dealing with a security fix" do
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

        it { is_expected.to be(true) }
      end

      context "when dealing with a security fix that doesn't apply" do
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

        it { is_expected.to be(false) }
      end

      context "when dealing with a security fix that doesn't apply to some versions" do
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

          is_expected.to be(true)
        end
      end
    end

    context "when a dependency whitelist that includes the dependency" do
      let(:allowed_updates) { [{ "dependency-name" => "business" }] }

      it { is_expected.to be(true) }

      context "with a dependency whitelist that uses a wildcard" do
        let(:allowed_updates) { [{ "dependency-name" => "bus*" }] }

        it { is_expected.to be(true) }
      end
    end

    context "when dependency whitelist that excludes the dependency" do
      let(:allowed_updates) { [{ "dependency-name" => "rails" }] }

      it { is_expected.to be(false) }

      context "when matching with potential sloppiness about substrings" do
        let(:allowed_updates) { [{ "dependency-name" => "bus" }] }

        it { is_expected.to be(false) }
      end

      context "with a dependency whitelist that uses a wildcard" do
        let(:allowed_updates) { [{ "dependency-name" => "b.ness*" }] }

        it { is_expected.to be(false) }
      end

      context "when security fixes are also allowed" do
        let(:allowed_updates) do
          [
            { "dependency-name" => "rails" },
            { "update-type" => "security" }
          ]
        end

        it { is_expected.to be(false) }

        context "when dealing with a security fix" do
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

          it { is_expected.to be(true) }
        end
      end
    end

    context "with dev dependencies during a security update while allowed: production is in effect" do
      let(:package_manager) { "dummy" }
      let(:security_updates_only) { true }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ansi-regex",
          package_manager: "dummy",
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

      it { is_expected.to be(false) }
    end
  end

  describe "#security_updates_only?" do
    subject { job.security_updates_only? }

    it { is_expected.to be(false) }

    context "with security only allowed updates" do
      let(:security_updates_only) { true }

      it { is_expected.to be(true) }
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
        expect(job.commit_message_options[:include_scope]).to be(true)
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

    it { is_expected.to be(true) }

    context "when the update hasn't been patched" do
      let(:dependency_version) { "1.10.0" }

      it { is_expected.to be(false) }
    end
  end

  describe "#reject_external_code?" do
    it "defaults to false" do
      expect(job.reject_external_code?).to be(false)
    end

    it "can be enabled by job attributes" do
      attrs = attributes
      attrs[:reject_external_code] = true
      job = described_class.new(attrs)
      expect(job.reject_external_code?).to be(true)
    end
  end
end
