# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/group_update_all_versions"

RSpec.describe Dependabot::Updater::Operations::GroupUpdateAllVersions do
  include DependencyFileHelpers
  include DummyPkgHelpers

  subject(:group_update_all) do
    described_class.new(
      service: mock_service,
      job: job,
      dependency_snapshot: dependency_snapshot,
      error_handler: mock_error_handler
    )
  end

  let(:mock_service) do
    instance_double(Dependabot::Service, increment_metric: nil)
  end

  let(:job) do
    Dependabot::Job.new_update_job(
      job_id: "1558782000",
      job_definition: job_definition_with_fetched_files
    )
  end

  let(:dependency_snapshot) do
    Dependabot::DependencySnapshot.create_from_job_definition(
      job: job,
      job_definition: job_definition_with_fetched_files
    )
  end

  let(:job_definition_with_fetched_files) do
    job_definition.merge({
      "base_commit_sha" => "mock-sha",
      "base64_dependency_files" => encode_dependency_files(dependency_files)
    })
  end

  let(:mock_error_handler) do
    instance_double(Dependabot::Updater::ErrorHandler)
  end

  after do
    Dependabot::Experiments.reset!
    Dependabot::DependencyGroupEngine.reset!
  end

  context "when the snapshot has no groups configured" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/update_all_simple")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "injects a placeholder group to update everything in a single request without errors" do
      expect(mock_error_handler).not_to receive(:handle_dependabot_error)
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("all-dependencies")
        expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
      end

      group_update_all.perform
    end
  end

  context "when nothing in the group needs to be updated" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all")
    end

    let(:dependency_files) do
      # Let's use the already up-to-date files
      updated_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "raises no errors and creates no pull requests" do
      expect(mock_error_handler).not_to receive(:handle_dependabot_error)
      expect(mock_service).not_to receive(:create_pull_request)

      group_update_all.perform
    end
  end

  context "when the snapshot is updating a gemspec", :vcr do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_all")
    end

    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(
          name: "Gemfile",
          content: fixture("bundler_gemspec/original/Gemfile"),
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "Gemfile.lock",
          content: fixture("bundler_gemspec/original/Gemfile.lock"),
          directory: "/"
        ),
        Dependabot::DependencyFile.new(
          name: "library.gemspec",
          content: fixture("bundler_gemspec/original/library.gemspec"),
          directory: "/"
        )
      ]
    end

    it "creates a DependencyChange for just the modified files without reporting errors" do
      expect(mock_error_handler).not_to receive(:handle_dependabot_error)
      expect(mock_service).to receive(:create_pull_request) do |dependency_change|
        expect(dependency_change.dependency_group.name).to eql("everything-everywhere-all-at-once")
        expect(dependency_change.updated_dependency_files_hash.length).to eql(2)

        gemfile_lock = dependency_change.updated_dependency_files.find { |file| file.path == "/Gemfile.lock" }
        expect(gemfile_lock.content).to eql(fixture("bundler_gemspec/updated/Gemfile.lock"))

        gemfile_lock = dependency_change.updated_dependency_files.find { |file| file.path == "/library.gemspec" }
        expect(gemfile_lock.content).to eql(fixture("bundler_gemspec/updated/library.gemspec"))

        expect(dependency_change.updated_dependencies.length).to eql(2)
        expect(dependency_change.updated_dependencies.map(&:name)).to eql(%w(rubocop rack))
      end

      group_update_all.perform
    end
  end
end
