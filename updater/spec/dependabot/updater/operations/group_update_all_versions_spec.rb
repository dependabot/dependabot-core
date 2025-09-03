# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dummy_pkg_helpers"
require "support/dependency_file_helpers"

require "dependabot/dependency_change"
require "dependabot/dependency_snapshot"
require "dependabot/service"
require "dependabot/updater/error_handler"
require "dependabot/updater/operations/group_update_all_versions"
require "dependabot/updater/operations/create_group_update_pull_request"
require "dependabot/updater/operations/update_all_versions"
require "dependabot/dependency_change_builder"
require "dependabot/notices"

require "dependabot/bundler"

RSpec.describe Dependabot::Updater::Operations::GroupUpdateAllVersions do
  include DependencyFileHelpers
  include DummyPkgHelpers

  subject(:perform) { group_update_all_versions.perform }

  let(:group_update_all_versions) do
    described_class.new(
      service: mock_service,
      job: job,
      dependency_snapshot: dependency_snapshot,
      error_handler: mock_error_handler
    )
  end

  let(:mock_service) do
    instance_double(
      Dependabot::Service,
      increment_metric: nil,
      record_update_job_error: nil,
      create_pull_request: nil,
      record_update_job_warning: nil,
      record_ecosystem_meta: nil,
      record_cooldown_meta: nil
    )
  end

  let(:mock_error_handler) { instance_double(Dependabot::Updater::ErrorHandler) }

  let(:job_definition) do
    job_definition_fixture("bundler/version_updates/pull_request_simple")
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

  let(:dependency_files) do
    original_bundler_files(fixture: "bundler_simple")
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      version: "4.0.0",
      requirements: [{
        file: "Gemfile",
        requirement: "~> 4.0.0",
        groups: ["default"],
        source: nil
      }],
      package_manager: "bundler",
      metadata: { all_versions: ["4.0.0"] }
    )
  end

  let(:mock_source) do
    instance_double(
      Dependabot::Source,
      directories: nil,
      directory: "/",
      repo: "test/repo"
    )
  end

  let(:mock_source_with_multiple_dirs) do
    instance_double(
      Dependabot::Source,
      directories: ["/", "/subdir"],
      directory: "/",
      repo: "test/repo"
    )
  end

  let(:mock_source_single_dir) do
    instance_double(
      Dependabot::Source,
      directories: nil,
      directory: "/single",
      repo: "test/repo"
    )
  end

  let(:dependency_group) do
    instance_double(
      Dependabot::DependencyGroup,
      name: "dummy-group",
      dependencies: [dependency],
      rules: { "update-types" => ["all"] }
    )
  end

  describe ".applies_to?" do
    context "when job is multi-ecosystem update" do
      before do
        allow(job).to receive(:multi_ecosystem_update?).and_return(true)
      end

      it "returns true" do
        expect(described_class.applies_to?(job: job)).to be true
      end
    end

    context "when job is updating a pull request" do
      before do
        allow(job).to receive_messages(multi_ecosystem_update?: false, updating_a_pull_request?: true)
      end

      it "returns false" do
        expect(described_class.applies_to?(job: job)).to be false
      end
    end

    context "when grouped security updates are disabled and job is security updates only" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?).with(:grouped_security_updates_disabled).and_return(true)
        allow(job).to receive_messages(multi_ecosystem_update?: false, updating_a_pull_request?: false,
                                       security_updates_only?: true)
      end

      it "returns false" do
        expect(described_class.applies_to?(job: job)).to be false
      end
    end

    context "when job is security updates only" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?).with(:grouped_security_updates_disabled).and_return(false)
        allow(job).to receive_messages(multi_ecosystem_update?: false, updating_a_pull_request?: false,
                                       security_updates_only?: true)
      end

      context "with multiple dependencies" do
        before do
          allow(job).to receive(:dependencies).and_return([dependency, dependency])
        end

        it "returns true" do
          expect(described_class.applies_to?(job: job)).to be true
        end
      end

      context "with dependency groups that apply to security updates" do
        before do
          allow(job).to receive_messages(dependencies: [dependency],
                                         dependency_groups: [{ "applies-to" => "security-updates" }])
        end

        it "returns true" do
          expect(described_class.applies_to?(job: job)).to be true
        end
      end

      context "with single dependency and no applicable groups" do
        before do
          allow(job).to receive_messages(dependencies: [dependency],
                                         dependency_groups: [{ "applies-to" => "version-updates" }])
        end

        it "returns false" do
          expect(described_class.applies_to?(job: job)).to be false
        end
      end
    end

    context "when job is not security updates only" do
      before do
        allow(job).to receive_messages(multi_ecosystem_update?: false, updating_a_pull_request?: false,
                                       security_updates_only?: false)
      end

      it "returns true" do
        expect(described_class.applies_to?(job: job)).to be true
      end
    end
  end

  describe ".tag_name" do
    it "returns the correct tag name" do
      expect(described_class.tag_name).to eq(:group_update_all_versions)
    end
  end

  describe "#perform" do
    let(:mock_create_group_update) do
      instance_double(Dependabot::Updater::Operations::CreateGroupUpdatePullRequest)
    end

    let(:mock_update_all_versions) do
      instance_double(Dependabot::Updater::Operations::UpdateAllVersions)
    end

    let(:mock_dependency_change) do
      instance_double(Dependabot::DependencyChange)
    end

    before do
      allow(Dependabot::Updater::Operations::CreateGroupUpdatePullRequest)
        .to receive(:new).and_return(mock_create_group_update)
      allow(Dependabot::Updater::Operations::UpdateAllVersions)
        .to receive(:new).and_return(mock_update_all_versions)
      allow(mock_create_group_update).to receive(:perform).and_return(mock_dependency_change)
      allow(mock_update_all_versions).to receive(:perform)
    end

    context "when there are dependency groups" do
      before do
        allow(dependency_snapshot).to receive(:groups).and_return([dependency_group])
        allow(dependency_snapshot).to receive(:mark_group_handled)
        allow(job).to receive_messages(existing_group_pull_requests: [], multi_ecosystem_update?: false,
                                       source: mock_source)
        allow(dependency_snapshot).to receive(:current_directory=)
        allow(dependency_snapshot).to receive_messages(dependencies: [dependency], ungrouped_dependencies: [dependency])
      end

      it "runs grouped dependency updates" do
        allow(mock_create_group_update).to receive(:perform).and_return(mock_dependency_change)

        perform

        expect(mock_create_group_update).to have_received(:perform)
      end

      context "when PR already exists for dependency group" do
        before do
          allow(job).to receive(:existing_group_pull_requests).and_return([
            { "dependency-group-name" => "dummy-group" }
          ])
        end

        it "skips the group and marks it as handled" do
          expect(mock_create_group_update).not_to receive(:perform)
          expect(dependency_snapshot).to receive(:mark_group_handled).with(dependency_group)
          perform
        end
      end

      context "when group update fails" do
        before do
          allow(mock_create_group_update).to receive(:perform).and_return(nil)
        end

        it "marks the group as handled" do
          expect(dependency_snapshot).to receive(:mark_group_handled).with(dependency_group)
          perform
        end
      end
    end

    context "when there are no dependency groups" do
      before do
        allow(job).to receive_messages(multi_ecosystem_update?: false, source: mock_source)
        allow(dependency_snapshot).to receive(:current_directory=)
        allow(dependency_snapshot).to receive_messages(groups: [], dependencies: [dependency],
                                                       ungrouped_dependencies: [dependency])
      end

      it "runs ungrouped dependency updates" do
        expect(mock_update_all_versions).to receive(:perform)
        perform
      end
    end

    context "when job is multi-ecosystem update" do
      before do
        allow(dependency_snapshot).to receive(:groups).and_return([dependency_group])
        allow(dependency_snapshot).to receive(:mark_group_handled)
        allow(job).to receive_messages(existing_group_pull_requests: [], multi_ecosystem_update?: true)
      end

      it "does not run ungrouped dependency updates" do
        expect(mock_update_all_versions).not_to receive(:perform)
        perform
      end
    end

    context "with multiple directories" do
      before do
        allow(job).to receive_messages(multi_ecosystem_update?: false, source: mock_source_with_multiple_dirs)
        allow(dependency_snapshot).to receive(:current_directory=)
        allow(dependency_snapshot).to receive_messages(groups: [], dependencies: [dependency],
                                                       ungrouped_dependencies: [dependency])
      end

      it "processes each directory" do
        expect(dependency_snapshot).to receive(:current_directory=).with("/")
        expect(dependency_snapshot).to receive(:current_directory=).with("/subdir")
        expect(mock_update_all_versions).to receive(:perform).twice
        perform
      end
    end

    context "when directory has no dependencies" do
      before do
        allow(job).to receive_messages(multi_ecosystem_update?: false, source: mock_source)
        allow(dependency_snapshot).to receive(:current_directory=)
        allow(dependency_snapshot).to receive_messages(groups: [], dependencies: [])
      end

      it "skips the directory" do
        expect(mock_update_all_versions).not_to receive(:perform)
        perform
      end
    end

    context "when directory has no ungrouped dependencies" do
      before do
        allow(job).to receive_messages(multi_ecosystem_update?: false, source: mock_source)
        allow(dependency_snapshot).to receive(:current_directory=)
        allow(dependency_snapshot).to receive_messages(groups: [], dependencies: [dependency],
                                                       ungrouped_dependencies: [])
      end

      it "skips the directory and logs a message" do
        expect(Dependabot.logger).to receive(:info)
          .with("Found no dependencies to update after filtering allowed updates in /")
        expect(mock_update_all_versions).not_to receive(:perform)
        perform
      end
    end
  end

  describe "private methods" do
    describe "#directories" do
      context "when source has directories" do
        it "returns the directories" do
          allow(job).to receive(:source).and_return(mock_source_with_multiple_dirs)

          expect(group_update_all_versions.send(:directories)).to eq(["/", "/subdir"])
        end
      end

      context "when source has no directories" do
        it "returns the single directory" do
          allow(job).to receive(:source).and_return(mock_source_single_dir)

          expect(group_update_all_versions.send(:directories)).to eq(["/single"])
        end
      end
    end
  end
end
