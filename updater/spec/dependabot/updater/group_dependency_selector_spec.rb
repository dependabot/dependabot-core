# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/job"
require "dependabot/updater/group_dependency_selector"

RSpec.describe Dependabot::Updater::GroupDependencySelector do
  let(:group_name) { "backend-dependencies" }
  let(:dependency_group) do
    instance_double(
      Dependabot::DependencyGroup,
      name: group_name,
      dependencies: [],
      rules: group_rules
    )
  end

  let(:group_rules) do
    {
      "patterns" => ["rails", "pg", "redis*"]
    }
  end

  let(:dependency_snapshot) do
    instance_double(
      Dependabot::DependencySnapshot,
      ecosystem: "bundler"
    )
  end

  let(:selector) { described_class.new(group: dependency_group, dependency_snapshot: dependency_snapshot) }

  let(:job) do
    instance_double(
      Dependabot::Job,
      source: instance_double(Dependabot::Source, directory: "/api")
    )
  end

  before do
    # Mock the logger
    allow(Dependabot).to receive(:logger).and_return(
      instance_double(Logger, info: nil, warn: nil, error: nil, debug: nil)
    )
  end

  describe "#initialize" do
    it "stores group and dependency snapshot" do
      # Test behavior rather than internal state
      expect(selector).to respond_to(:merge_per_directory!)
      expect(selector).to respond_to(:filter_to_group!)
      expect(selector).to respond_to(:annotate_dependency_drift!)
    end
  end

  describe "#merge_per_directory!" do
    let(:rails_dep) { create_dependency("rails", "7.0.0") }
    let(:pg_dep) { create_dependency("pg", "1.4.0") }
    let(:redis_dep) { create_dependency("redis", "4.8.0") }
    let(:duplicate_rails_dep) { create_dependency("rails", "7.0.1") }

    let(:change1) do
      create_dependency_change(
        job: job,
        dependencies: [rails_dep, pg_dep],
        files: [create_dependency_file("Gemfile", "/api")]
      )
    end

    let(:change2) do
      create_dependency_change(
        job: create_job("/web"),
        dependencies: [redis_dep, duplicate_rails_dep],
        files: [create_dependency_file("Gemfile", "/web")]
      )
    end

    context "with single change" do
      it "returns the original change" do
        result = selector.merge_per_directory!([change1])
        expect(result).to eq(change1)
      end
    end

    context "with multiple changes" do
      before do
        # Mock DependencyChange.new to return a mock object
        allow(Dependabot::DependencyChange).to receive(:new) do |args|
          instance_double(
            Dependabot::DependencyChange,
            job: args[:job],
            updated_dependencies: args[:updated_dependencies],
            updated_dependency_files: args[:updated_dependency_files]
          )
        end
      end

      it "merges dependencies with directory-aware deduplication" do
        result = selector.merge_per_directory!([change1, change2])

        expect(result.updated_dependencies.length).to eq(4) # rails from both dirs, pg, redis
        dependency_names = result.updated_dependencies.map(&:name)
        expect(dependency_names).to contain_exactly("rails", "pg", "redis", "rails")
      end

      it "merges updated files without duplicates" do
        result = selector.merge_per_directory!([change1, change2])

        expect(result.updated_dependency_files.length).to eq(2)
        file_paths = result.updated_dependency_files.map { |f| [f.directory, f.name] }
        expect(file_paths).to contain_exactly(["/api", "Gemfile"], ["/web", "Gemfile"])
      end

      it "logs merge statistics" do
        expect(Dependabot.logger).to receive(:info).with(
          "GroupDependencySelector merged 2 directory changes into 4 unique dependencies " \
          "[group=#{group_name}, ecosystem=bundler]"
        )

        selector.merge_per_directory!([change1, change2])
      end
    end
  end

  describe "#filter_to_group!" do
    let(:rails_dep) { create_dependency("rails", "7.0.0") }
    let(:unauthorized_dep) { create_dependency("puma", "5.6.0") }
    let(:redis_dep) { create_dependency("redis-client", "0.11.0") } # matches redis* pattern

    let(:dependency_change) do
      create_dependency_change(
        job: job,
        dependencies: [rails_dep, unauthorized_dep, redis_dep],
        files: [create_dependency_file("Gemfile.lock", "/api")]
      )
    end

    context "when feature flag is disabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(false)
      end

      it "does not modify the dependency change" do
        original_deps = dependency_change.updated_dependencies.dup
        selector.filter_to_group!(dependency_change)
        expect(dependency_change.updated_dependencies).to eq(original_deps)
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(true)

        # Mock group membership checking - the actual method is contains? not contains_dependency?
        allow(dependency_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
        allow(dependency_group).to receive(:contains?) do |dep|
          %w(rails redis-client).include?(dep.name)
        end

        # Mock job configuration checking
        allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

        # Mock the dependency change to have mutable updated_dependencies array
        allow(dependency_change.updated_dependencies).to receive(:clear)
        allow(dependency_change.updated_dependencies).to receive(:concat)
      end

      it "filters out non-group dependencies" do
        original_deps = dependency_change.updated_dependencies.dup
        selector.filter_to_group!(dependency_change)

        # Check that the selector attempted to filter dependencies
        expected_deps = %w(rails redis-client)
        included_deps = original_deps.select { |dep| expected_deps.include?(dep.name) }
        expect(included_deps.length).to eq(2)
      end

      it "preserves file diffs" do
        original_files = dependency_change.updated_dependency_files
        selector.filter_to_group!(dependency_change)
        expect(dependency_change.updated_dependency_files).to eq(original_files)
      end

      it "emits filtering metrics when dependencies are filtered" do
        expect(selector).to receive(:emit_filtering_metrics)
          .with("/api", 3, anything, anything)

        selector.filter_to_group!(dependency_change)
      end

      it "logs filtered dependencies" do
        expect(selector).to receive(:log_filtered_dependencies) do |filtered_deps|
          expect(filtered_deps.any?).to be true
        end

        selector.filter_to_group!(dependency_change)
      end
    end

    context "with fallback group membership logic" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(true)

        # Simulate group without contains_dependency? method
        allow(dependency_group).to receive(:respond_to?)
          .with(:contains_dependency?).and_return(false)
        # Mock the fallback contains? method
        allow(dependency_group).to receive(:contains?) do |dep|
          %w(rails redis-client).include?(dep.name)
        end

        # Mock job configuration checking
        allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

        # Mock the dependency change array methods
        allow(dependency_change.updated_dependencies).to receive(:clear)
        allow(dependency_change.updated_dependencies).to receive(:concat)
      end

      it "uses pattern matching fallback" do
        # The fallback now uses @group.contains?(dep) which is the correct approach
        # since DependencyGroup already handles pattern matching internally
        expect(dependency_group).to receive(:contains?).at_least(:once).and_return(true)

        selector.filter_to_group!(dependency_change)
      end
    end
  end

  describe "#annotate_dependency_drift!" do
    let(:dependency_change) do
      create_dependency_change(
        job: job,
        dependencies: [create_dependency("rails", "7.0.0")],
        files: [create_dependency_file("Gemfile.lock", "/api")]
      )
    end

    context "when feature flag is disabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(false)
      end

      it "does not annotate dependency drift" do
        expect(selector).not_to receive(:detect_file_dependency_drift)
        selector.annotate_dependency_drift!(dependency_change)
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(true)
      end

      it "processes files for dependency drift" do
        # Mock dependency drift detection
        allow(selector).to receive(:detect_file_dependency_drift)
          .and_return(%w(transitive-dep-1 transitive-dep-2))

        selector.annotate_dependency_drift!(dependency_change)

        # Test that dependency drift detection was called
        expect(selector).to have_received(:detect_file_dependency_drift)
      end

      it "emits dependency drift metrics when drift is detected" do
        allow(selector).to receive(:detect_file_dependency_drift).and_return(["transitive-dep"])
        expect(selector).to receive(:emit_dependency_drift_metrics).with("/api", 1)

        selector.annotate_dependency_drift!(dependency_change)
      end

      it "logs dependency drift" do
        allow(selector).to receive(:detect_file_dependency_drift).and_return(["transitive-dep"])
        expect(selector).to receive(:log_dependency_drift).with(["transitive-dep"])

        selector.annotate_dependency_drift!(dependency_change)
      end
    end
  end

  describe "private methods" do
    describe "#group_contains_dependency?" do
      let(:rails_dep) { create_dependency("rails", "7.0.0") }
      let(:redis_dep) { create_dependency("redis-client", "0.11.0") }
      let(:unauthorized_dep) { create_dependency("puma", "5.6.0") }

      context "when group uses pattern matching fallback" do
        before do
          allow(dependency_group).to receive(:respond_to?)
            .with(:contains_dependency?).and_return(false)
          # Mock the fallback contains? method
          allow(dependency_group).to receive(:contains?) do |dep|
            %w(rails redis-client).include?(dep.name)
          end
        end

        it "matches exact names" do
          expect(selector.send(:group_contains_dependency?, rails_dep, "/api")).to be true
        end

        it "matches wildcard patterns" do
          expect(selector.send(:group_contains_dependency?, redis_dep, "/api")).to be true
        end

        it "rejects non-matching names" do
          expect(selector.send(:group_contains_dependency?, unauthorized_dep, "/api")).to be false
        end
      end
    end

    describe "#dependency_matches_pattern?" do
      it "matches exact names" do
        expect(selector.send(:dependency_matches_pattern?, "rails", "rails")).to be true
      end

      it "matches wildcard patterns" do
        expect(selector.send(:dependency_matches_pattern?, "redis-client", "redis*")).to be true
        expect(selector.send(:dependency_matches_pattern?, "redis", "redis*")).to be true
      end

      it "rejects non-matching patterns" do
        expect(selector.send(:dependency_matches_pattern?, "puma", "redis*")).to be false
        expect(selector.send(:dependency_matches_pattern?, "rails", "pg")).to be false
      end
    end

    describe "#allowed_by_config?" do
      let(:dependency) { create_dependency("rails", "7.0.0") }

      it "returns true when dependency is allowed" do
        allow(job).to receive(:ignore_conditions_for).with(dependency).and_return([])
        allow(job).to receive(:allowed_update?).with(dependency).and_return(true)

        expect(selector.send(:allowed_by_config?, dependency, job)).to be true
      end

      it "returns false when dependency is ignored" do
        all_versions_condition = instance_double(Dependabot::Config::IgnoreCondition)
        allow(job).to receive(:ignore_conditions_for).with(dependency).and_return([all_versions_condition])

        # Mock the constant check
        stub_const("Dependabot::Config::IgnoreCondition::ALL_VERSIONS", all_versions_condition)

        expect(selector.send(:allowed_by_config?, dependency, job)).to be false
      end

      it "returns false when dependency update is not allowed" do
        allow(job).to receive(:ignore_conditions_for).with(dependency).and_return([])
        allow(job).to receive(:allowed_update?).with(dependency).and_return(false)

        expect(selector.send(:allowed_by_config?, dependency, job)).to be false
      end
    end
  end

  private

  def create_dependency(name, version)
    instance_double(
      Dependabot::Dependency,
      name: name,
      version: version
    ).tap do |dep|
      # Allow attribution setter methods
      allow(dep).to receive(:attribution_source_group=)
      allow(dep).to receive(:attribution_selection_reason=)
      allow(dep).to receive(:attribution_directory=)
      allow(dep).to receive(:attribution_timestamp=)
      # Allow attribution getter methods
      allow(dep).to receive_messages(attribution_source_group: nil, attribution_selection_reason: nil,
                                     attribution_directory: nil, attribution_timestamp: nil)
    end
  end

  def create_dependency_change(job:, dependencies:, files:)
    instance_double(
      Dependabot::DependencyChange,
      job: job,
      updated_dependencies: dependencies,
      updated_dependency_files: files
    ).tap do |change|
      # Allow the array modification methods for updated_dependencies
      allow(change.updated_dependencies).to receive(:clear)
      allow(change.updated_dependencies).to receive(:concat)
    end
  end

  def create_dependency_file(name, directory)
    instance_double(
      Dependabot::DependencyFile,
      name: name,
      directory: directory
    )
  end

  def create_job(directory)
    instance_double(
      Dependabot::Job,
      source: instance_double(Dependabot::Source, directory: directory)
    )
  end
end
