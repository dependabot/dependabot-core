# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Dependabot::Updater::GroupDependencySelector do
  let(:group_name) { "backend-dependencies" }
  let(:dependency_group) do
    instance_double(
      Dependabot::DependencyGroup,
      name: group_name,
      dependencies: %w(rails pg redis*)
    )
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
      instance_double(Logger, info: nil, warn: nil, error: nil)
    )
  end

  describe "#initialize" do
    it "stores group and dependency snapshot" do
      expect(selector.instance_variable_get(:@group)).to eq(dependency_group)
      expect(selector.instance_variable_get(:@snapshot)).to eq(dependency_snapshot)
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
      it "merges dependencies with directory-aware deduplication" do
        result = selector.merge_per_directory!([change1, change2])

        expect(result.updated_dependencies.length).to eq(4) # rails from both dirs, pg, redis
        dependency_names = result.updated_dependencies.map(&:name)
        expect(dependency_names).to contain_exactly("rails", "pg", "redis", "rails")
      end

      it "annotates dependencies with source directory" do
        result = selector.merge_per_directory!([change1, change2])

        rails_deps = result.updated_dependencies.select { |d| d.name == "rails" }
        expect(rails_deps.length).to eq(2)

        # Check that dependencies are annotated with their source directories
        source_dirs = rails_deps.map { |d| d.instance_variable_get(:@source_directory) }
        expect(source_dirs).to contain_exactly("/api", "/web")
      end

      it "merges updated files without duplicates" do
        result = selector.merge_per_directory!([change1, change2])

        expect(result.updated_dependency_files.length).to eq(2)
        file_paths = result.updated_dependency_files.map { |f| [f.directory, f.name] }
        expect(file_paths).to contain_exactly(["/api", "Gemfile"], ["/web", "Gemfile"])
      end

      it "logs merge statistics" do
        expect(Dependabot.logger).to receive(:info).with(
          "GroupDependencySelector merged 2 directory changes into 4 unique dependencies",
          group: group_name,
          ecosystem: "bundler"
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

        # Mock group membership checking
        allow(dependency_group).to receive(:contains_dependency?) do |dep, directory:|
          case dep.name
          when "rails", "pg"
            true
          when /redis.*/
            true
          else
            false
          end
        end
      end

      it "filters out non-group dependencies" do
        selector.filter_to_group!(dependency_change)

        dependency_names = dependency_change.updated_dependencies.map(&:name)
        expect(dependency_names).to contain_exactly("rails", "redis-client")
        expect(dependency_names).not_to include("puma")
      end

      it "preserves file diffs" do
        original_files = dependency_change.updated_dependency_files
        selector.filter_to_group!(dependency_change)
        expect(dependency_change.updated_dependency_files).to eq(original_files)
      end

      it "annotates included dependencies with selection metadata" do
        selector.filter_to_group!(dependency_change)

        rails_dep_after = dependency_change.updated_dependencies.find { |d| d.name == "rails" }
        expect(rails_dep_after.instance_variable_get(:@source_group)).to eq(group_name)
        expect(rails_dep_after.instance_variable_get(:@selection_reason)).to eq(:direct)
      end

      it "stores filtered dependencies for observability" do
        selector.filter_to_group!(dependency_change)

        filtered_deps = dependency_change.instance_variable_get(:@filtered_dependencies)
        expect(filtered_deps).to be_present
        expect(filtered_deps.map(&:name)).to contain_exactly("puma")
      end

      it "emits filtering metrics when dependencies are filtered" do
        expect(selector).to receive(:emit_filtering_metrics)
                              .with("/api", 3, 2, 1)

        selector.filter_to_group!(dependency_change)
      end

      it "logs filtered dependencies" do
        expect(Dependabot.logger).to receive(:info).with(
          "Filtered non-group dependencies: puma",
          group: group_name,
          ecosystem: "bundler",
          filtered_count: 1
        )

        selector.filter_to_group!(dependency_change)
      end

      context "with many filtered dependencies" do
        let(:many_deps) do
          (1..15).map { |i| create_dependency("unauthorized-dep-#{i}", "1.0.0") }
        end

        let(:dependency_change_with_many) do
          create_dependency_change(
            job: job,
            dependencies: [rails_dep] + many_deps,
            files: []
          )
        end

        it "caps logged dependency names" do
          expect(Dependabot.logger).to receive(:info).with(
            a_string_matching(/Filtered non-group dependencies: .*\(and 5 more\)/),
            group: group_name,
            ecosystem: "bundler",
            filtered_count: 15
          )

          selector.filter_to_group!(dependency_change_with_many)
        end
      end
    end

    context "with fallback group membership logic" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
                                            .with(:group_membership_enforcement).and_return(true)

        # Simulate group without contains_dependency? method
        allow(dependency_group).to receive(:respond_to?)
                                     .with(:contains_dependency?).and_return(false)
      end

      it "uses pattern matching fallback" do
        selector.filter_to_group!(dependency_change)

        dependency_names = dependency_change.updated_dependencies.map(&:name)
        expect(dependency_names).to contain_exactly("rails", "redis-client")
      end
    end
  end

  describe "#annotate_side_effects!" do
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

      it "does not annotate side effects" do
        selector.annotate_side_effects!(dependency_change)
        expect(dependency_change.instance_variable_get(:@side_effects)).to be_nil
      end
    end

    context "when feature flag is enabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
                                            .with(:group_membership_enforcement).and_return(true)
      end

      it "processes files for side effects" do
        # Mock side effect detection
        allow(selector).to receive(:detect_file_side_effects)
                             .and_return(%w(transitive-dep-1 transitive-dep-2))

        selector.annotate_side_effects!(dependency_change)

        side_effects = dependency_change.instance_variable_get(:@side_effects)
        expect(side_effects).to contain_exactly("transitive-dep-1", "transitive-dep-2")
      end

      it "emits side effect metrics when side effects are detected" do
        allow(selector).to receive(:detect_file_side_effects).and_return(["transitive-dep"])
        expect(selector).to receive(:emit_side_effect_metrics).with("/api", 1)

        selector.annotate_side_effects!(dependency_change)
      end

      it "logs side effects" do
        allow(selector).to receive(:detect_file_side_effects).and_return(["transitive-dep"])
        expect(Dependabot.logger).to receive(:info).with(
          "Side effects detected: transitive-dep",
          group: group_name,
          ecosystem: "bundler",
          side_effect_count: 1
        )

        selector.annotate_side_effects!(dependency_change)
      end
    end
  end

  describe "private methods" do
    describe "#group_contains_dependency?" do
      let(:rails_dep) { create_dependency("rails", "7.0.0") }
      let(:redis_dep) { create_dependency("redis-client", "0.11.0") }
      let(:unauthorized_dep) { create_dependency("puma", "5.6.0") }

      context "when group has contains_dependency? method" do
        before do
          allow(dependency_group).to receive(:respond_to?)
                                       .with(:contains_dependency?).and_return(true)
          allow(dependency_group).to receive(:contains_dependency?) do |dep, directory:|
            %w(rails pg).include?(dep.name)
          end
        end

        it "uses the group's method" do
          expect(selector.send(:group_contains_dependency?, rails_dep, "/api")).to be true
          expect(selector.send(:group_contains_dependency?, unauthorized_dep, "/api")).to be false
        end
      end

      context "when group uses pattern matching fallback" do
        before do
          allow(dependency_group).to receive(:respond_to?)
                                       .with(:contains_dependency?).and_return(false)
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
  end

  private

  def create_dependency(name, version)
    instance_double(
      Dependabot::Dependency,
      name: name,
      version: version
    ).tap do |dep|
      allow(dep).to receive(:respond_to?).with(:instance_variable_set).and_return(true)
      allow(dep).to receive(:instance_variable_set)
      allow(dep).to receive(:instance_variable_get).and_return(nil)
    end
  end

  def create_dependency_change(job:, dependencies:, files:)
    instance_double(
      Dependabot::DependencyChange,
      job: job,
      updated_dependencies: dependencies,
      updated_dependency_files: files
    ).tap do |change|
      allow(change).to receive(:instance_variable_set)
      allow(change).to receive(:instance_variable_get).and_return(nil)
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
