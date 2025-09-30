# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dependency_file_helpers"

require "dependabot/bundler"
require "dependabot/dependency_file"
require "dependabot/dependency_snapshot"
require "dependabot/job"

require "github_api/dependency_submission"

RSpec.describe GithubApi::DependencySubmission do
  include DependencyFileHelpers

  subject(:dependency_submission) do
    described_class.new(
      job_id: "9999",
      branch: branch,
      sha: sha,
      package_manager: "bundler",
      manifest_file: lockfile,
      resolved_dependencies: resolved_dependencies
    )
  end

  let(:branch) { "main" }
  let(:sha) { "fake-sha" }

  let(:directory) { "/" }

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: fixture("bundler/original/Gemfile.lock"),
      directory: directory
    )
  end

  let(:resolved_dependencies) do
    {
      "dummy-pkg-a" => {
        package_url: "pkg:gem/dummy-pkg-a@2.0.0",
        relationship: "direct",
        scope: "runtime",
        dependencies: [],
        metadata: {}
      },
      "dummy-pkg-b" => {
        package_url: "pkg:gem/dummy-pkg-b@1.1.0",
        relationship: "direct",
        scope: "runtime",
        dependencies: [],
        metadata: {}
      }
    }
  end

  describe "::job_correlator" do
    [
      {
        context: "with a typical RubyGems project in directory root",
        directory: "/",
        expected_correlator: "dependabot-bundler-Gemfile.lock"
      },
      {
        context: "with a RubyGems project in a subdirectory",
        directory: "ruby/backend-api/",
        expected_correlator: "dependabot-bundler-ruby-backend-api-Gemfile.lock"
      },
      {
        context: "with mixed case in the file path",
        directory: "Ruby/backend-api/",
        expected_correlator: "dependabot-bundler-Ruby-backend-api-Gemfile.lock"
      },
      # If we're given something pathologically long, we use a SHA256 to limit length
      {
        context: "with a RubyGems project in a pathological directory tree",
        directory: "lorem/ipsum/dolor/sit/amet/consectetur/adipiscing/elit/nunc/turpis/justo/" \
                   "maximus/ac/eleifend/sit/amet/malesuada/eu/nisi/donec/faucibus/lobortis/" \
                   "augue/vitae/venenatis/nunc/euismod/auctor/suspendisse/eget",
        expected_correlator: /dependabot-bundler-[a-fA-F0-9]{64}-Gemfile.lock/
      }
    ].each do |tc|
      context tc[:context] do
        let(:directory) { tc[:directory] }

        it "uses the expected value for job.correlator" do
          payload = dependency_submission.payload

          expect(payload[:job][:correlator]).to match(tc[:expected_correlator])
        end
      end
    end
  end

  describe "payload" do
    it "generates submission metadata correctly" do
      payload = dependency_submission.payload

      # Check metadata
      expect(payload[:version]).to eq(described_class::SNAPSHOT_VERSION)
      expect(payload[:detector][:name]).to eq(described_class::SNAPSHOT_DETECTOR_NAME)
      expect(payload[:detector][:url]).to eq(described_class::SNAPSHOT_DETECTOR_URL)
      expect(payload[:detector][:version]).to eq(Dependabot::VERSION)
      expect(payload[:job][:correlator]).to eq("dependabot-bundler-Gemfile.lock")
      expect(payload[:job][:id]).to eq("9999")
    end

    it "generates git attributes correctly" do
      payload = dependency_submission.payload

      expect(payload[:sha]).to eq(sha)
      expect(payload[:ref]).to eql("refs/heads/main")
    end

    context "when given a symbolic reference for the job's branch" do
      let(:branch) { "refs/heads/release" }

      it "does not add an additional refs/heads/ prefix" do
        payload = dependency_submission.payload

        expect(payload[:sha]).to eq(sha)
        expect(payload[:ref]).to eql("refs/heads/release")
      end
    end

    context "when given a symbolic reference for the job's branch with a leading /" do
      let(:branch) { "/refs/heads/release" }

      it "removes the leading slash" do
        payload = dependency_submission.payload

        expect(payload[:sha]).to eq(sha)
        expect(payload[:ref]).to eql("refs/heads/release")
      end
    end

    it "generates a valid manifest list" do
      payload = dependency_submission.payload

      # We only expect a lockfile to be returned
      expect(payload[:manifests].length).to eq(1)

      # Lockfile data is correct
      lockfile = payload[:manifests].fetch("/Gemfile.lock")
      expect(lockfile[:name]).to eq("/Gemfile.lock")
      expect(lockfile[:file][:source_location]).to eq("Gemfile.lock")

      # Resolved dependencies are correct
      expect(lockfile[:resolved].length).to eq(2)

      dependency1 = lockfile[:resolved]["dummy-pkg-a"]
      expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a@2.0.0")

      dependency2 = lockfile[:resolved]["dummy-pkg-b"]
      expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b@1.1.0")
    end
  end
end
