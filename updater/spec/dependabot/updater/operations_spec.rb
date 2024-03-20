# typed: false
# frozen_string_literal: true

require "dependabot/job"
require "dependabot/updater/operations"

require "spec_helper"

RSpec.describe Dependabot::Updater::Operations do
  describe "::class_for" do
    after do
      Dependabot::Experiments.reset!
    end

    it "returns nil if no operation matches" do
      # We always expect jobs that update a pull request to specify their
      # existing dependency changes, a job with this set of conditions
      # should never exist.
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            security_updates_only?: false,
                            updating_a_pull_request?: true,
                            dependencies: [],
                            dependency_groups: [],
                            is_a?: true)

      expect(described_class.class_for(job: job)).to be_nil
    end

    it "returns the UpdateAllVersions class when the Job is for a fresh, non-security update with no dependencies" do
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            security_updates_only?: false,
                            updating_a_pull_request?: false,
                            dependencies: [],
                            dependency_groups: [],
                            is_a?: true)

      expect(described_class.class_for(job: job)).to be(Dependabot::Updater::Operations::UpdateAllVersions)
    end

    it "returns the GroupUpdateAllVersions class when the Job is for a fresh, version update with no dependencies" do
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            security_updates_only?: false,
                            updating_a_pull_request?: false,
                            dependencies: [],
                            dependency_groups: [anything],
                            is_a?: true)

      expect(described_class.class_for(job: job)).to be(Dependabot::Updater::Operations::GroupUpdateAllVersions)

      Dependabot::Experiments.reset!
    end

    it "returns the RefreshGroupUpdatePullRequest class when the Job is for an existing group update" do
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            security_updates_only?: false,
                            updating_a_pull_request?: true,
                            dependencies: [anything],
                            dependency_group_to_refresh: anything,
                            dependency_groups: [anything],
                            is_a?: true)

      expect(described_class.class_for(job: job))
        .to be(Dependabot::Updater::Operations::RefreshGroupUpdatePullRequest)

      Dependabot::Experiments.reset!
    end

    it "returns the RefreshVersionUpdatePullRequest class when the Job is for an existing dependency version update" do
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            security_updates_only?: false,
                            updating_a_pull_request?: true,
                            dependencies: [anything],
                            dependency_group_to_refresh: nil,
                            dependency_groups: [anything],
                            is_a?: true)

      expect(described_class.class_for(job: job))
        .to be(Dependabot::Updater::Operations::RefreshVersionUpdatePullRequest)
    end

    it "returns the CreateSecurityUpdatePullRequest class when the Job is for a new security update for a dependency" do
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            dependency_group_to_refresh: nil,
                            security_updates_only?: true,
                            updating_a_pull_request?: false,
                            dependencies: [anything],
                            dependency_groups: [],
                            is_a?: true)

      expect(described_class.class_for(job: job))
        .to be(Dependabot::Updater::Operations::CreateSecurityUpdatePullRequest)
    end

    it "returns the GroupUpdateAllVersions class when Experiment flag is not provided" do
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            security_updates_only?: true,
                            updating_a_pull_request?: false,
                            dependencies: [anything, anything],
                            dependency_groups: [anything],
                            is_a?: true)

      expect(described_class.class_for(job: job))
        .to be(Dependabot::Updater::Operations::GroupUpdateAllVersions)
    end

    it "returns the GroupUpdateAllVersions class when Experiment flag is off" do
      Dependabot::Experiments.register(:grouped_security_updates_disabled, false)
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            security_updates_only?: true,
                            updating_a_pull_request?: false,
                            dependencies: [anything, anything],
                            dependency_groups: [anything],
                            is_a?: true)

      expect(described_class.class_for(job: job))
        .to be(Dependabot::Updater::Operations::GroupUpdateAllVersions)
    end

    it "returns the CreateSecurityUpdatePullRequest class when Experiment flag is true" do
      Dependabot::Experiments.register(:grouped_security_updates_disabled, true)
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            dependency_group_to_refresh: nil,
                            security_updates_only?: true,
                            updating_a_pull_request?: false,
                            dependencies: [anything, anything],
                            dependency_groups: [anything],
                            is_a?: true)

      expect(described_class.class_for(job: job))
        .to be(Dependabot::Updater::Operations::CreateSecurityUpdatePullRequest)
    end

    it "returns the RefreshGroupSecurityUpdatePullRequest class when the Job is for an existing security update for" \
       " multiple dependencies" do
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            security_updates_only?: true,
                            updating_a_pull_request?: true,
                            dependencies: [anything, anything],
                            dependency_group_to_refresh: anything,
                            dependency_groups: [anything],
                            is_a?: true)

      expect(described_class.class_for(job: job))
        .to be(Dependabot::Updater::Operations::RefreshGroupUpdatePullRequest)
    end

    it "returns the RefreshSecurityUpdatePullRequest class when the Job is for an existing security update" do
      source = instance_double(Dependabot::Source, directory: "/.", directories: nil)
      job = instance_double(Dependabot::Job,
                            source: source,
                            dependency_group_to_refresh: nil,
                            security_updates_only?: true,
                            updating_a_pull_request?: true,
                            dependencies: [anything],
                            dependency_groups: [anything],
                            is_a?: true)

      expect(described_class.class_for(job: job))
        .to be(Dependabot::Updater::Operations::RefreshSecurityUpdatePullRequest)
    end

    it "raises an argument error with anything other than a Dependabot::Job" do
      expect { described_class.class_for(job: Object.new) }.to raise_error(ArgumentError)
    end
  end
end
