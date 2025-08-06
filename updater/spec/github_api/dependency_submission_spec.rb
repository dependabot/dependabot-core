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
      job: job,
      snapshot: dependabot_snapshot
    )
  end

  let(:repo) { "dependabot-fixtures/dependabot-test-ruby-package" }
  let(:branch) { "main" }
  let(:sha) { "fake-sha" }

  let(:directory) { "/" }
  let(:directories) { nil }

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: repo,
      directory: "/",
      branch: branch
    )
  end

  let(:job) do
    instance_double(
      Dependabot::Job,
      id: 9999,
      source: source,
      package_manager: "bundler",
      repo_contents_path: nil,
      credentials: [],
      reject_external_code?: false,
      experiments: {},
      dependency_groups: [],
      security_updates_only?: false,
      allowed_update?: true
    )
  end

  let(:job_definition) do
    {
      "base_commit_sha" => sha,
      "base64_dependency_files" => encode_dependency_files(dependency_files)
    }
  end

  let(:dependabot_snapshot) do
    Dependabot::DependencySnapshot.create_from_job_definition(
      job: job,
      job_definition: job_definition
    )
  end

  context "with a basic Gemfile project" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: directory
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler/original/Gemfile.lock"),
          directory: directory
        )
      ]
    end

    it "generates submission metadata correctly" do
      payload = dependency_submission.payload

      # Check metadata
      expect(payload[:version]).to eq(described_class::SNAPSHOT_VERSION)
      expect(payload[:detector][:name]).to eq(described_class::SNAPSHOT_DETECTOR_NAME)
      expect(payload[:detector][:url]).to eq(described_class::SNAPSHOT_DETECTOR_URL)
      expect(payload[:detector][:version]).to eq(Dependabot::VERSION)
      expect(payload[:job][:correlator]).to eq("dependabot-experimental")
      expect(payload[:job][:id]).to eq("9999")

      # And check we have an iso8601 timestamp
      expect(payload[:scanned]).to match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/)
    end

    it "generates a valid manifest list" do # rubocop:disable RSpec/MultipleExpectations
      payload = dependency_submission.payload

      expect(payload[:manifests].length).to eq(2)

      # Gemfile data is correct
      gemfile = payload[:manifests].fetch("/Gemfile")
      expect(gemfile[:name]).to eq("/Gemfile")
      expect(gemfile[:file][:source_location]).to eq("Gemfile")

      # Lockfile data is correct
      lockfile = payload[:manifests].fetch("/Gemfile.lock")
      expect(lockfile[:name]).to eq("/Gemfile.lock")
      expect(lockfile[:file][:source_location]).to eq("Gemfile.lock")

      # Resolved dependencies are correct
      expect(gemfile[:resolved].length).to eq(2)
      expect(lockfile[:resolved].length).to eq(2)

      dependency1 = gemfile[:resolved]["dummy-pkg-a"]
      dependency2 = gemfile[:resolved]["dummy-pkg-b"]

      [gemfile, lockfile].each do |depfile|
        depfile[:resolved].each do |pkg_name, resolved_dep|
          expect(resolved_dep).not_to be_empty
          expect(resolved_dep[:relationship]).to eq("direct")

          case pkg_name
          when "dummy-pkg-a"
            expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a@2.0.0")
          when "dummy-pkg-b"
            expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b@1.1.0")
          end
        end
      end
    end
  end

  context "with a small sinatra app" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler_sinatra_app/original/Gemfile"),
          directory: directory
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler_sinatra_app/original/Gemfile.lock"),
          directory: directory
        )
      ]
    end

    it "generates a valid manifest list" do
      payload = dependency_submission.payload

      expect(payload[:manifests].length).to eq(2)

      # Manifest data is correct
      gemfile = payload[:manifests].fetch("/Gemfile")
      expect(gemfile[:name]).to eq("/Gemfile")
      expect(gemfile[:file][:source_location]).to eq("Gemfile")

      # Lockfile data is correct
      lockfile = payload[:manifests].fetch("/Gemfile.lock")
      expect(lockfile[:name]).to eq("/Gemfile.lock")
      expect(lockfile[:file][:source_location]).to eq("Gemfile.lock")

      # Resolved dependencies are correct:
      expect(gemfile[:resolved].length).to eq(4)
      expect(lockfile[:resolved].length).to eq(28)

      # the following top-level packages should exist in both files with
      # the same data
      %w(sinatra pry rspec capybara).each do |pkg_name|
        [gemfile, lockfile].each do |depfile|
          resolved_dep = depfile[:resolved][pkg_name]

          expect(resolved_dep).not_to be_empty
          expect(resolved_dep[:relationship]).to eq("direct")

          case pkg_name
          when "sinatra"
            expect(resolved_dep[:package_url]).to eql("pkg:gem/sinatra@4.1.1")
            expect(resolved_dep[:scope]).to eq("runtime")
          when "pry"
            expect(resolved_dep[:package_url]).to eql("pkg:gem/pry@0.15.2")
            expect(resolved_dep[:scope]).to eq("development")
          when "rspec"
            expect(resolved_dep[:package_url]).to eql("pkg:gem/rspec@3.13.1")
            expect(resolved_dep[:scope]).to eq("development")
          when "capybara"
            expect(resolved_dep[:package_url]).to eql("pkg:gem/capybara@3.40.0")
            expect(resolved_dep[:scope]).to eq("development")
          end
        end
      end

      # the lockfile should be reporting 4 direct dependencies and 24 indirect ones
      expect(lockfile[:resolved].values.count { |dep| dep[:relationship] == "direct" }).to eq(4)
      expect(lockfile[:resolved].values.count { |dep| dep[:relationship] == "indirect" }).to eq(24)

      # the direct ones were verified above.
      # let's pull out a few indirect dependencies to check
      rack = lockfile[:resolved]["rack"]
      expect(rack[:package_url]).to eql("pkg:gem/rack@3.1.16")
      expect(rack[:relationship]).to eq("indirect")
      expect(rack[:scope]).to eq("runtime")

      addressable = lockfile[:resolved]["addressable"]
      expect(addressable[:package_url]).to eql("pkg:gem/addressable@2.8.7")
      expect(addressable[:relationship]).to eq("indirect")
      expect(addressable[:scope]).to eq("development")
    end
  end
end
