# frozen_string_literal: true

require "dependabot/job"
require "dependabot/updater/operations"

require "spec_helper"

RSpec.describe Dependabot::Updater::Operations do
  describe "::class_for" do
    it "returns nil if no operation matches" do
      # We always expect jobs that update a pull request to specify their
      # existing dependency changes, a job with this set of conditions
      # should never exist.
      job = instance_double(Dependabot::Job,
                            security_updates_only?: false,
                            updating_a_pull_request?: true,
                            dependencies: [],
                            is_a?: true)

      expect(described_class.class_for(job: job)).to be_nil
    end

    it "returns the UpdateAllVersions class when the Job is for a fresh, non-security update with no dependencies" do
      job = instance_double(Dependabot::Job,
                            security_updates_only?: false,
                            updating_a_pull_request?: false,
                            dependencies: [],
                            is_a?: true)

      expect(described_class.class_for(job: job)).to be(Dependabot::Updater::Operations::UpdateAllVersions)
    end

    context "the grouped update experiment is enabled" do
      it "returns the GroupUpdateAllVersions class when the Job is for a fresh, version update with no dependencies" do
        Dependabot::Experiments.register("grouped_updates_prototype", true)

        job = instance_double(Dependabot::Job,
                              security_updates_only?: false,
                              updating_a_pull_request?: false,
                              dependencies: [],
                              is_a?: true)

        expect(described_class.class_for(job: job)).to be(Dependabot::Updater::Operations::GroupUpdateAllVersions)

        Dependabot::Experiments.reset!
      end
    end

    it "returns the RefreshVersionPullRequest class when the Job is for an existing dependency version update" do
      job = instance_double(Dependabot::Job,
                            security_updates_only?: false,
                            updating_a_pull_request?: true,
                            dependencies: [anything],
                            is_a?: true)

      expect(described_class.class_for(job: job)).to be(Dependabot::Updater::Operations::RefreshVersionPullRequest)
    end

    it "raises an argument error with anything other than a Dependabot::Job" do
      expect { described_class.class_for(job: Object.new) }.to raise_error(ArgumentError)
    end
  end
end
