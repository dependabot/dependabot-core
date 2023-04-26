# frozen_string_literal: true

require "spec_helper"
require "support/dependency_file_helpers"

require "dependabot/dependency_group_engine"
require "dependabot/dependency_snapshot"
require "dependabot/job"

# The DependencyGroupEngine is not accessed directly, but though a DependencySnapshot.
# So these tests use DependencySnapshot methods to check the DependencyGroupEngine works as expected
RSpec.describe Dependabot::DependencyGroupEngine do
  include DependencyFileHelpers

  let(:dependency_group_engine) { described_class }

  let(:job_json) { fixture("jobs/job_with_dependency_groups.json") }

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Gemfile",
        content: fixture("bundler_grouped/original/Gemfile"),
        directory: "/"
      ),
      Dependabot::DependencyFile.new(
        name: "Gemfile.lock",
        content: fixture("bundler_grouped/original/Gemfile.lock"),
        directory: "/"
      )
    ]
  end

  let(:base_commit_sha) do
    "mock-sha"
  end

  let(:job_definition) do
    {
      "base_commit_sha" => base_commit_sha,
      "base64_dependency_files" => encode_dependency_files(dependency_files)
    }
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot-fixtures/dependabot-test-ruby-package",
      directory: "/",
      branch: nil,
      api_endpoint: "https://api.github.com/",
      hostname: "github.com"
    )
  end

  let(:job) do
    Dependabot::Job.new_update_job(
      job_id: anything,
      job_definition: JSON.parse(job_json),
      repo_contents_path: anything
    )
  end

  def create_dependency_snapshot
    Dependabot::DependencySnapshot.create_from_job_definition(
      job: job,
      job_definition: job_definition
    )
  end

  describe "#register" do
    after do
      Dependabot::Experiments.reset!
      Dependabot::DependencyGroupEngine.reset!
    end

    it "registers the dependency groups" do
      expect(dependency_group_engine.instance_variable_get(:@registered_groups)).to eq([])

      # We have to call the original here for the DependencyGroupEngine to actually register the groups
      expect(dependency_group_engine).to receive(:register).with("group-a", ["dummy-pkg-*"]).and_call_original
      expect(dependency_group_engine).to receive(:register).with("group-b", ["dummy-pkg-b"]).and_call_original

      # Groups are registered by the job when a DependencySnapshot is created
      create_dependency_snapshot

      expect(dependency_group_engine.instance_variable_get(:@registered_groups)).not_to eq([])
    end
  end

  describe "#groups_for" do
    after do
      Dependabot::Experiments.reset!
      Dependabot::DependencyGroupEngine.reset!
    end

    it "returns the expected groups" do
      snapshot = create_dependency_snapshot

      expect(dependency_group_engine.send(:groups_for, snapshot.dependencies[0]).count).to eq(1)
      expect(dependency_group_engine.send(:groups_for, snapshot.dependencies[1]).count).to eq(2)
      expect(dependency_group_engine.send(:groups_for, snapshot.dependencies[2]).count).to eq(0)
    end
  end

  describe "#dependency_groups" do
    after do
      Dependabot::Experiments.reset!
      Dependabot::DependencyGroupEngine.reset!
    end

    it "returns the dependency groups" do
      snapshot = create_dependency_snapshot
      allowed_dependencies = snapshot.allowed_dependencies

      expect(dependency_group_engine).to receive(:dependency_groups).
        with(allowed_dependencies).at_least(:once).and_call_original
      expect(dependency_group_engine).to receive(:calculate_dependency_groups!).
        with(allowed_dependencies).once.and_call_original

      groups = snapshot.groups

      expect(groups.key?(:"group-a")).to be_truthy
      expect(groups.key?(:"group-b")).to be_truthy
      expect(groups[:"group-a"]).to be_a(Dependabot::DependencyGroup)
    end

    it "does not call calculate_dependency_groups! again after groups are initially calculated" do
      snapshot = create_dependency_snapshot
      allowed_dependencies = snapshot.allowed_dependencies

      expect(dependency_group_engine.instance_variable_get(:@groups_calculated)).to be_falsey
      expect(dependency_group_engine).to receive(:calculate_dependency_groups!).
        with(allowed_dependencies).once.and_call_original

      snapshot.groups
      snapshot.ungrouped_dependencies

      expect(dependency_group_engine.instance_variable_get(:@groups_calculated)).to be_truthy
    end
  end

  describe "#ungrouped_dependencies" do
    after do
      Dependabot::Experiments.reset!
      Dependabot::DependencyGroupEngine.reset!
    end

    it "returns the ungrouped dependencies" do
      snapshot = create_dependency_snapshot
      allowed_dependencies = snapshot.allowed_dependencies

      expect(dependency_group_engine).to receive(:calculate_dependency_groups!).
        with(allowed_dependencies).once.and_call_original
      expect(dependency_group_engine).to receive(:ungrouped_dependencies).
        with(allowed_dependencies).at_least(:once).and_call_original

      ungrouped_dependencies = snapshot.ungrouped_dependencies

      expect(ungrouped_dependencies.first).to be_a(Dependabot::Dependency)
    end

    it "does not call calculate_dependency_groups! again after ungrouped_dependencies are initially calculated" do
      snapshot = create_dependency_snapshot
      allowed_dependencies = snapshot.allowed_dependencies

      expect(dependency_group_engine.instance_variable_get(:@groups_calculated)).to be_falsey
      expect(dependency_group_engine).to receive(:calculate_dependency_groups!).
        with(allowed_dependencies).once.and_call_original

      snapshot.ungrouped_dependencies
      snapshot.groups

      expect(dependency_group_engine.instance_variable_get(:@groups_calculated)).to be_truthy
    end
  end

  describe "#reset!" do
    after do
      Dependabot::Experiments.reset!
      Dependabot::DependencyGroupEngine.reset!
    end

    it "resets the dependency group engine" do
      snapshot = create_dependency_snapshot
      snapshot.groups

      expect(dependency_group_engine.instance_variable_get(:@groups_calculated)).to be_truthy
      expect(dependency_group_engine.instance_variable_get(:@registered_groups)).not_to eq([])
      expect(dependency_group_engine.instance_variable_get(:@dependency_groups)).not_to eq({})
      expect(dependency_group_engine.instance_variable_get(:@ungrouped_dependencies)).not_to eq([])

      dependency_group_engine.reset!

      expect(dependency_group_engine.instance_variable_get(:@groups_calculated)).to be_falsey
      expect(dependency_group_engine.instance_variable_get(:@registered_groups)).to eq([])
      expect(dependency_group_engine.instance_variable_get(:@dependency_groups)).to eq({})
      expect(dependency_group_engine.instance_variable_get(:@ungrouped_dependencies)).to eq([])
    end
  end

  describe "#calculate_dependency_groups!" do
    after do
      Dependabot::Experiments.reset!
      Dependabot::DependencyGroupEngine.reset!
    end

    it "runs once" do
      snapshot = create_dependency_snapshot
      allowed_dependencies = snapshot.allowed_dependencies

      expect(dependency_group_engine).to receive(:calculate_dependency_groups!).
        with(allowed_dependencies).once.and_call_original

      snapshot.groups
      snapshot.groups
    end

    it "returns true" do
      snapshot = create_dependency_snapshot
      allowed_dependencies = snapshot.allowed_dependencies

      expect(dependency_group_engine.calculate_dependency_groups!(allowed_dependencies)).to be_truthy
    end
  end
end
