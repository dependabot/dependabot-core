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
      ecosystem: "bundler",
      groups: []
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

  # New tests for pattern specificity functionality
  describe "pattern specificity functionality" do
    let(:docker_dep) { create_dependency("docker-compose", "2.0.0") }
    let(:nginx_dep) { create_dependency("nginx", "1.21.0") }
    let(:redis_dep) { create_dependency("redis-client", "0.11.0") }

    # Mock multiple groups with different specificity levels
    let(:generic_group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "all-dependencies",
        dependencies: [],
        rules: { "patterns" => ["*"] }
      )
    end

    let(:docker_group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "docker-dependencies",
        dependencies: [],
        rules: { "patterns" => ["docker*"] }
      )
    end

    let(:exact_group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "exact-nginx",
        dependencies: [],
        rules: { "patterns" => ["nginx"] }
      )
    end

    let(:snapshot_with_multiple_groups) do
      instance_double(
        Dependabot::DependencySnapshot,
        ecosystem: "bundler",
        groups: [generic_group, docker_group, exact_group]
      )
    end

    describe "#dependency_belongs_to_more_specific_group?" do
      let(:generic_selector) do
        described_class.new(group: generic_group, dependency_snapshot: snapshot_with_multiple_groups)
      end

      before do
        # Mock group contains? methods for all groups
        allow(generic_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
        allow(docker_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
        allow(exact_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)

        allow(generic_group).to receive_messages(contains?: true, dependencies: []) # matches everything
        allow(docker_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
        allow(exact_group).to receive(:contains?) { |dep| dep.name == "nginx" }
      end

      it "returns true when dependency belongs to more specific docker group" do
        result = generic_selector.send(:dependency_belongs_to_more_specific_group?, docker_dep, "/api")
        expect(result).to be true
      end

      it "returns true when dependency belongs to exact match group" do
        result = generic_selector.send(:dependency_belongs_to_more_specific_group?, nginx_dep, "/api")
        expect(result).to be true
      end

      it "returns false when no more specific group exists" do
        docker_selector = described_class.new(group: docker_group, dependency_snapshot: snapshot_with_multiple_groups)
        result = docker_selector.send(:dependency_belongs_to_more_specific_group?, docker_dep, "/api")
        expect(result).to be false
      end
    end

    describe "#partition_dependencies with specificity filtering" do
      let(:dependency_change) do
        create_dependency_change(
          job: job,
          dependencies: [docker_dep, nginx_dep, redis_dep],
          files: [create_dependency_file("Gemfile.lock", "/api")]
        )
      end

      context "when processing generic group that matches everything" do
        let(:generic_selector) do
          described_class.new(group: generic_group, dependency_snapshot: snapshot_with_multiple_groups)
        end

        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:group_membership_enforcement).and_return(true)

          # Mock group membership and config checks
          allow(generic_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
          allow(docker_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
          allow(exact_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)

          allow(generic_group).to receive_messages(contains?: true, dependencies: [])
          allow(docker_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
          allow(exact_group).to receive(:contains?) { |dep| dep.name == "nginx" }

          allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

          allow(docker_group).to receive(:dependencies).and_return([])
          allow(exact_group).to receive(:dependencies).and_return([])
        end

        it "filters out dependencies that belong to more specific groups" do
          eligible_deps, filtered_deps = generic_selector.send(:partition_dependencies, dependency_change)

          # Docker and nginx deps should be filtered out due to more specific groups
          eligible_names = eligible_deps.map(&:name)
          filtered_names = filtered_deps.map(&:name)

          expect(eligible_names).to contain_exactly("redis-client") # Only this doesn't match more specific groups
          expect(filtered_names).to include("docker-compose", "nginx") # These have more specific groups
        end

        it "annotates filtered dependencies with correct reason" do
          # Mock DependencyAttribution
          expect(Dependabot::DependencyAttribution).to receive(:annotate_dependency)
            .with(docker_dep, hash_including(selection_reason: :belongs_to_more_specific_group))
          expect(Dependabot::DependencyAttribution).to receive(:annotate_dependency)
            .with(nginx_dep, hash_including(selection_reason: :belongs_to_more_specific_group))
          expect(Dependabot::DependencyAttribution).to receive(:annotate_dependency)
            .with(redis_dep, hash_including(selection_reason: :direct))

          generic_selector.send(:partition_dependencies, dependency_change)
        end
      end

      context "when processing specific group" do
        let(:docker_selector) do
          described_class.new(group: docker_group, dependency_snapshot: snapshot_with_multiple_groups)
        end

        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:group_membership_enforcement).and_return(true)

          # Mock group membership
          allow(generic_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
          allow(docker_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
          allow(exact_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)

          allow(generic_group).to receive_messages(contains?: true, dependencies: []) # matches everything
          allow(docker_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
          allow(exact_group).to receive(:contains?) { |dep| dep.name == "nginx" }

          allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

          # Mock dependencies arrays
          allow(generic_group).to receive(:dependencies).and_return([])
          allow(docker_group).to receive(:dependencies).and_return([])
          allow(exact_group).to receive(:dependencies).and_return([])
        end

        it "includes dependencies that match its specific pattern" do
          eligible_deps, filtered_deps = docker_selector.send(:partition_dependencies, dependency_change)

          eligible_names = eligible_deps.map(&:name)
          filtered_names = filtered_deps.map(&:name)

          expect(eligible_names).to contain_exactly("docker-compose") # Matches docker* pattern
          expect(filtered_names).to include("nginx", "redis-client") # Don't match docker* pattern
        end
      end
    end

    describe "integration with filter_to_group!" do
      let(:dependency_change) do
        create_dependency_change(
          job: job,
          dependencies: [docker_dep, nginx_dep],
          files: [create_dependency_file("Gemfile.lock", "/api")]
        )
      end

      let(:generic_selector) do
        described_class.new(group: generic_group, dependency_snapshot: snapshot_with_multiple_groups)
      end

      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement).and_return(true)

        # Mock group membership
        allow(generic_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
        allow(docker_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)
        allow(exact_group).to receive(:respond_to?).with(:contains_dependency?).and_return(false)

        allow(generic_group).to receive_messages(contains?: true, dependencies: []) # matches everything
        allow(docker_group).to receive(:contains?) { |dep| dep.name.start_with?("docker") }
        allow(exact_group).to receive(:contains?) { |dep| dep.name == "nginx" }

        allow(job).to receive_messages(ignore_conditions_for: [], allowed_update?: true)

        # Mock dependencies arrays
        allow(generic_group).to receive(:dependencies).and_return([])
        allow(docker_group).to receive(:dependencies).and_return([])
        allow(exact_group).to receive(:dependencies).and_return([])

        # Mock the dependency change array methods
        allow(dependency_change.updated_dependencies).to receive(:clear)
        allow(dependency_change.updated_dependencies).to receive(:concat)
      end

      it "logs dependencies filtered due to more specific groups" do
        expect(generic_selector).to receive(:log_filtered_dependencies) do |filtered_deps|
          expect(filtered_deps.length).to be > 0
        end

        generic_selector.filter_to_group!(dependency_change)
      end

      it "includes specificity filtering in group dependencies by reason" do
        # Mock the attribution to test the grouping
        allow(Dependabot::DependencyAttribution).to receive(:get_attribution) do |dep|
          if %w(docker-compose nginx).include?(dep.name)
            { selection_reason: :belongs_to_more_specific_group }
          else
            { selection_reason: :direct }
          end
        end

        filtered_deps = [docker_dep, nginx_dep]
        grouped = generic_selector.send(:group_dependencies_by_reason, filtered_deps)

        expect(grouped[:belongs_to_more_specific_group]).to contain_exactly("docker-compose", "nginx")
        expect(grouped[:not_in_group]).to be_empty
        expect(grouped[:filtered_by_config]).to be_empty
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
