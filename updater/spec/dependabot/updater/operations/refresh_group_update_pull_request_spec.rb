# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/refresh_group_update_pull_request"

require "dependabot/bundler"

RSpec.describe Dependabot::Updater::Operations::RefreshGroupUpdatePullRequest do
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
  end

  describe "#perform" do
    context "when the same dependencies need to be updated to the same target versions" do
      let(:job_definition) do
        job_definition_fixture("bundler/version_updates/group_update_refresh")
      end

      let(:dependency_files) do
        original_bundler_files
      end

      before do
        stub_rubygems_calls
      end

      it "updates the existing pull request without errors" do
        expect(mock_service).to receive(:update_pull_request) do |dependency_change|
          expect(dependency_change.dependency_group.name).to eql("everything-everywhere-all-at-once")
          expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
        end

        group_update_all.perform
      end
    end

    context "when the dependencies have been since been updated by someone else and there's nothing to do" do
      let(:job_definition) do
        job_definition_fixture("bundler/version_updates/group_update_refresh")
      end

      let(:dependency_files) do
        updated_bundler_files
      end

      before do
        stub_rubygems_calls
      end

      it "closes the pull request" do
        expect(mock_service).to receive(:close_pull_request).with(["dummy-pkg-b"], :update_no_longer_possible)

        group_update_all.perform
      end
    end

    context "when the dependencies that need to be updated have changed" do
      let(:job_definition) do
        job_definition_fixture("bundler/version_updates/group_update_refresh_dependencies_changed")
      end

      let(:dependency_files) do
        original_bundler_files
      end

      before do
        stub_rubygems_calls
      end

      it "closes the existing pull request and creates a new one" do
        expect(mock_service).to receive(:close_pull_request).with(%w(dummy-pkg-b dummy-pkg-c), :dependencies_changed)

        expect(mock_service).to receive(:create_pull_request) do |dependency_change|
          expect(dependency_change.dependency_group.name).to eql("everything-everywhere-all-at-once")
          expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
        end

        group_update_all.perform
      end
    end

    context "when a dependency needs to be updated to a different version" do
      let(:job_definition) do
        job_definition_fixture("bundler/version_updates/group_update_refresh_versions_changed")
      end

      let(:dependency_files) do
        original_bundler_files
      end

      before do
        stub_rubygems_calls
      end

      it "creates a new pull request to supersede the existing one" do
        expect(mock_service).to receive(:create_pull_request) do |dependency_change|
          expect(dependency_change.dependency_group.name).to eql("everything-everywhere-all-at-once")
          expect(dependency_change.updated_dependency_files_hash).to eql(updated_bundler_files_hash)
        end

        group_update_all.perform
      end
    end

    # This shouldn't be possible as the grouped update shouldn't put a dependency in more than one group.
    # But it's useful to test what will happen on refresh if it does get in this state.
    context "when there is a pull request for an overlapping group" do
      let(:job_definition) do
        job_definition_fixture("bundler/version_updates/group_update_refresh_similar_pr")
      end

      let(:dependency_files) do
        original_bundler_files
      end

      before do
        stub_rubygems_calls
      end

      it "considers the dependencies in the other PRs as handled, and closes the duplicate PR" do
        expect(mock_service).to receive(:close_pull_request).with(["dummy-pkg-b"], :update_no_longer_possible)

        group_update_all.perform

        # It added all of the other existing grouped PRs to the handled list
        expect(dependency_snapshot.handled_dependencies).to match_array(%w(dummy-pkg-a dummy-pkg-b dummy-pkg-c
                                                                           dummy-pkg-d))
      end
    end

    context "when the target dependency group is no longer present in the project's config" do
      let(:job_definition) do
        job_definition_fixture("bundler/version_updates/group_update_refresh_missing_group")
      end

      let(:dependency_files) do
        original_bundler_files
      end

      before do
        stub_rubygems_calls
      end

      it "does nothing, logs a warning and notices an error" do
        # Our mocks will fail due to unexpected messages if any errors or PRs are dispatched

        expect(Dependabot.logger).to receive(:warn).with(
          "The 'everything-everywhere-all-at-once' group has been removed from the update config."
        )

        expect(mock_service).to receive(:capture_exception).with(
          error: an_instance_of(Dependabot::DependabotError),
          job: job
        )

        group_update_all.perform
      end
    end

    context "when the target dependency group no longer matches any dependencies in the project" do
      let(:job_definition) do
        job_definition_fixture("bundler/version_updates/group_update_refresh_empty_group")
      end

      let(:dependency_files) do
        original_bundler_files
      end

      before do
        stub_rubygems_calls
      end

      it "logs a warning and tells the service to close the Pull Request" do
        # Our mocks will fail due to unexpected messages if any errors or PRs are dispatched

        allow(Dependabot.logger).to receive(:warn)
        expect(Dependabot.logger).to receive(:warn).with(
          "Skipping update group for 'everything-everywhere-all-at-once' as it does not match any allowed dependencies."
        )

        expect(mock_service).to receive(:close_pull_request).with(["dummy-pkg-b"], :dependency_group_empty)

        group_update_all.perform
      end
    end
  end

  describe "#deduce_updated_dependency" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_refresh_dependencies_changed")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    before do
      stub_rubygems_calls
    end

    it "returns nil if dependency is nil" do
      dependency = nil
      original_dependency = dependency_snapshot.dependencies.first
      expect(group_update_all.deduce_updated_dependency(dependency, original_dependency)).to be_nil
    end

    it "returns nil if original_dependency is nil" do
      dependency = dependency_snapshot.dependencies.first
      original_dependency = nil
      expect(group_update_all.deduce_updated_dependency(dependency, original_dependency)).to be_nil
    end
  end

  describe "#semver_rules_allow_grouping?" do
    let(:job_definition) do
      job_definition_fixture("bundler/version_updates/group_update_refresh_versions_changed")
    end

    let(:dependency_files) do
      original_bundler_files
    end

    let(:update_types) do
      []
    end

    let(:group) do
      instance_double(Dependabot::DependencyGroup, rules: { "update-types" => update_types })
    end

    let(:dependency) do
      instance_double(Dependabot::Dependency, version: current_version)
    end

    let(:checker) do
      instance_double(Dependabot::UpdateCheckers::Base, latest_version: latest_version)
    end

    before do
      stub_rubygems_calls
    end

    context "when major version component of current and latest versions are not comparable" do
      let(:current_version) { "X.2.3" }
      let(:latest_version) { "1.2.3" }

      it "returns false" do
        expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(false)
      end
    end

    context "when minor version component of current and latest versions are not comparable" do
      let(:current_version) { "1.X.3" }
      let(:latest_version) { "1.2.3" }

      it "returns false" do
        expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(false)
      end
    end

    context "when patch version component of current and latest versions are not comparable" do
      let(:current_version) { "1.2.X" }
      let(:latest_version) { "1.2.3" }

      it "returns false" do
        expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(false)
      end
    end

    context "when latest major version > current major version" do
      let(:current_version) { "1.2.3" }
      let(:latest_version) { "2.0.0" }

      context "when group update-types includes major version" do
        let(:update_types) do
          ["major"]
        end

        it "returns true" do
          expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(true)
        end
      end

      context "when group update-types includes minor version" do
        let(:update_types) do
          ["minor"]
        end

        it "returns false" do
          expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(false)
        end
      end

      context "when group update-types includes patch version" do
        let(:update_types) do
          ["patch"]
        end

        it "returns false" do
          expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(false)
        end
      end
    end

    context "when latest minor version > current minor version" do
      let(:current_version) { "1.2.3" }
      let(:latest_version) { "1.3.0" }

      context "when group update-types includes major version" do
        let(:update_types) do
          ["major"]
        end

        it "returns false" do
          expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(false)
        end
      end

      context "when group update-types includes minor version" do
        let(:update_types) do
          ["minor"]
        end

        it "returns true" do
          expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(true)
        end
      end

      context "when group update-types includes patch version" do
        let(:update_types) do
          ["patch"]
        end

        it "returns false" do
          expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(false)
        end
      end
    end

    context "when latest patch version > current patch version" do
      let(:current_version) { "1.2.3" }
      let(:latest_version) { "1.2.4" }

      context "when group update-types includes major version" do
        let(:update_types) do
          ["major"]
        end

        it "returns false" do
          expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(false)
        end
      end

      context "when group update-types includes minor version" do
        let(:update_types) do
          ["minor"]
        end

        it "returns false" do
          expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(false)
        end
      end

      context "when group update-types includes patch version" do
        let(:update_types) do
          ["patch"]
        end

        it "returns true" do
          expect(group_update_all.semver_rules_allow_grouping?(group, dependency, checker)).to be(true)
        end
      end
    end
  end
end
