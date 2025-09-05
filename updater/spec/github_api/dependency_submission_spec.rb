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
      ecosystem: ecosystem,
      dependency_files: dependency_files,
      dependencies: parsed_dependencies
    )
  end

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("bundler").new(
      dependency_files: dependency_files,
      repo_contents_path: nil,
      source: source,
      credentials: [],
      reject_external_code: false
    )
  end

  let(:repo) { "dependabot-fixtures/dependabot-test-ruby-package" }
  let(:branch) { "main" }
  let(:sha) { "fake-sha" }

  let(:ecosystem) do
    parser.ecosystem
  end

  let(:parsed_dependencies) do
    parser.parse
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: repo,
      directory: "/",
      branch: branch
    )
  end

  let(:directory) { "/" }

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
      expect(payload[:job][:correlator]).to eq("dependabot-bundler")
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

    it "generates a valid manifest list" do # rubocop:disable RSpec/MultipleExpectations
      payload = dependency_submission.payload

      # We only expect a lockfile to be returned
      expect(payload[:manifests].length).to eq(1)

      # Lockfile data is correct
      lockfile = payload[:manifests].fetch("/Gemfile.lock")
      expect(lockfile[:name]).to eq("/Gemfile.lock")
      expect(lockfile[:file][:source_location]).to eq("Gemfile.lock")

      # Resolved dependencies are correct:
      expect(lockfile[:resolved].length).to eq(28)

      # the lockfile should be reporting 4 direct dependencies and 24 indirect ones
      expect(lockfile[:resolved].values.count { |dep| dep[:relationship] == "direct" }).to eq(4)
      expect(lockfile[:resolved].values.count { |dep| dep[:relationship] == "indirect" }).to eq(24)

      # the following top-level packages should be defined in the right groups
      %w(sinatra pry rspec capybara).each do |pkg_name|
        resolved_dep = lockfile[:resolved][pkg_name]

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

  context "with vendored files" do
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
        ),
        Dependabot::DependencyFile.new(
          name: "vendor/ruby/3.4.0/cache/addressable-2.8.7.gem",
          content: "stuff",
          directory: directory,
          support_file: true,
          vendored_file: true
        )
      ]
    end

    it "they are not mentioned in the dependency submission payload" do
      payload = dependency_submission.payload

      # We only expect a lockfile to be returned
      expect(payload[:manifests].length).to eq(1)
      expect(payload[:manifests].keys).to eq(%w(/Gemfile.lock))
    end
  end

  context "without a Gemfile.lock" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler/original/Gemfile"),
          directory: directory
        )
      ]
    end

    it "generates a valid manifest list" do
      payload = dependency_submission.payload

      # We only expect a lockfile to be returned
      expect(payload[:manifests].length).to eq(1)

      # Lockfile data is correct
      gemfile = payload[:manifests].fetch("/Gemfile")
      expect(gemfile[:name]).to eq("/Gemfile")
      expect(gemfile[:file][:source_location]).to eq("Gemfile")

      # Resolved dependencies are correct
      expect(gemfile[:resolved].length).to eq(2)

      dependency1 = gemfile[:resolved]["dummy-pkg-a"]
      expect(dependency1[:package_url]).to eql("pkg:gem/dummy-pkg-a")

      dependency2 = gemfile[:resolved]["dummy-pkg-b"]
      expect(dependency2[:package_url]).to eql("pkg:gem/dummy-pkg-b")
    end
  end

  # This is mainly for documentation purposes, an empty snapshot is useful to update a repository when a set of
  # manifests are removed so there will be circumstances when we are generating a graph based on pushes where
  # this probably makes sense but it will need to be fleshed out.
  context "with a set of empty dependency files" do
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: "",
          directory: directory
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: "",
          directory: directory
        )
      ]
    end

    it "generates a snapshot with metadata and an empty manifest list" do
      payload = dependency_submission.payload

      expect(payload[:version]).to eq(described_class::SNAPSHOT_VERSION)
      expect(payload[:detector][:name]).to eq(described_class::SNAPSHOT_DETECTOR_NAME)
      expect(payload[:detector][:url]).to eq(described_class::SNAPSHOT_DETECTOR_URL)
      expect(payload[:detector][:version]).to eq(Dependabot::VERSION)
      expect(payload[:job][:correlator]).to eq("dependabot-bundler")
      expect(payload[:job][:id]).to eq("9999")

      expect(dependency_submission.payload[:manifests]).to be_empty

      expect(payload[:sha]).to eq(sha)
      expect(payload[:ref]).to eql("refs/heads/main")
    end
  end
end
