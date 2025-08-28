# typed: false
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/dependency_snapshot"
require "dependabot/job"
require "dependabot/source"
require "dependabot/updater/dependency_group_change_batch"

require "spec_helper"

RSpec.describe Dependabot::Updater::DependencyGroupChangeBatch do
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-gemfile", directory: "/"),
      Dependabot::DependencyFile.new(name: "Gemfile.lock", content: "mock-gemfile-lock", directory: "/hello/.."),
      Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "/elsewhere"),
      Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "unknown"),
      Dependabot::DependencyFile.new(name: "Gemfile", content: "mock-package-json", directory: "../../oob")
    ]
  end

  let(:dependency_snapshot) do
    instance_double(
      Dependabot::DependencySnapshot,
      dependency_files: dependency_files,
      ecosystem: "bundler"
    )
  end

  let(:dependency_group) do
    Dependabot::DependencyGroup.new(
      name: "backend",
      rules: { "patterns" => ["rails*", "pg"] }
    )
  end

  let(:job) do
    instance_double(Dependabot::Job, source: source, package_manager: "bundler")
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directory: directory)
  end

  let(:directory) { "/" }

  describe "#initialize" do
    context "with job context" do
      it "initializes with group dependency selector support" do
        batch = described_class.new(
          dependency_snapshot: dependency_snapshot,
          group: dependency_group,
          job: job
        )

        expect(batch.updated_dependencies).to eq([])
        # Test behavior rather than internal state
        expect(batch).to respond_to(:current_dependency_files)
        expect(batch).to respond_to(:merge_dependency_changes)
      end
    end

    context "without job context (backward compatibility)" do
      it "initializes without job context" do
        batch = described_class.new(
          dependency_snapshot: dependency_snapshot,
          group: dependency_group
        )

        expect(batch.updated_dependencies).to eq([])
        # Test behavior rather than internal state
        expect(batch).to respond_to(:current_dependency_files)
      end
    end
  end

  describe "#current_dependency_files" do
    let(:batch) do
      described_class.new(
        dependency_snapshot: dependency_snapshot,
        group: dependency_group,
        job: job
      )
    end

    it "returns the current dependency files filtered by directory" do
      expect(batch.current_dependency_files(job).map(&:name)).to eq(%w(Gemfile Gemfile.lock))
    end

    context "when the directory has a dot" do
      let(:directory) { "/." }

      it "normalizes the directory" do
        expect(batch.current_dependency_files(job).map(&:name)).to eq(%w(Gemfile Gemfile.lock))
      end
    end

    context "when the directory has a dot dot" do
      let(:directory) { "/hello/.." }

      it "normalizes the directory" do
        expect(batch.current_dependency_files(job).map(&:name)).to eq(%w(Gemfile Gemfile.lock))
      end
    end
  end

  describe "#merge_dependency_changes" do
    let(:batch) do
      described_class.new(
        dependency_snapshot: dependency_snapshot,
        group: dependency_group,
        job: job
      )
    end

    let(:rails_dep) do
      Dependabot::Dependency.new(
        name: "rails",
        version: "7.0.0",
        requirements: [],
        package_manager: "bundler"
      )
    end

    let(:pg_dep) do
      Dependabot::Dependency.new(
        name: "pg",
        version: "1.4.0",
        requirements: [],
        package_manager: "bundler"
      )
    end

    let(:unauthorized_dep) do
      Dependabot::Dependency.new(
        name: "unauthorized",
        version: "1.0.0",
        requirements: [],
        package_manager: "bundler"
      )
    end

    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:group_membership_enforcement).and_return(group_enforcement_enabled)
    end

    after do
      Dependabot::Experiments.reset!
    end

    context "when group membership enforcement is enabled" do
      let(:group_enforcement_enabled) { true }

      before do
        # Mock the group dependency selector
        selector = instance_double(Dependabot::Updater::GroupDependencySelector)
        allow(batch).to receive(:group_dependency_selector).and_return(selector)

        # Mock the selector filtering behavior
        allow(selector).to receive(:filter_to_group!) do |change|
          # Simulate filtering out unauthorized dependencies
          change.updated_dependencies.reject! { |dep| dep.name == "unauthorized" }
        end

        allow(Dependabot::DependencyChange).to receive(:new).and_call_original
      end

      it "routes filtering through the GroupDependencySelector" do
        dependencies = [rails_dep, pg_dep, unauthorized_dep]

        expect(batch).to receive(:apply_group_dependency_filtering)
          .with(dependencies)
          .and_call_original

        batch.send(:merge_dependency_changes, dependencies)

        # Should have filtered out unauthorized dependency
        expect(batch.updated_dependencies.map(&:name)).to contain_exactly("rails", "pg")
      end

      it "uses job context for selector filtering when available" do
        dependencies = [rails_dep, pg_dep]

        expect(batch).to receive(:apply_selector_filtering)
          .with(dependencies)
          .and_call_original

        batch.send(:merge_dependency_changes, dependencies)
      end
    end

    context "when group membership enforcement is disabled" do
      let(:group_enforcement_enabled) { false }

      it "adds all dependencies without filtering" do
        dependencies = [rails_dep, pg_dep, unauthorized_dep]

        batch.send(:merge_dependency_changes, dependencies)

        expect(batch.updated_dependencies.map(&:name)).to contain_exactly("rails", "pg", "unauthorized")
      end
    end
  end

  describe "#should_enforce_group_membership?" do
    let(:batch) do
      described_class.new(
        dependency_snapshot: dependency_snapshot,
        group: dependency_group,
        job: job
      )
    end

    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:group_membership_enforcement).and_return(group_enforcement_enabled)
    end

    after do
      Dependabot::Experiments.reset!
    end

    context "when feature flag is enabled and group/snapshot are present" do
      let(:group_enforcement_enabled) { true }

      it "returns true" do
        expect(batch.send(:should_enforce_group_membership?)).to be true
      end
    end

    context "when feature flag is disabled" do
      let(:group_enforcement_enabled) { false }

      it "returns false" do
        expect(batch.send(:should_enforce_group_membership?)).to be false
      end
    end

    context "when group is nil" do
      let(:dependency_group) { nil }
      let(:group_enforcement_enabled) { true }

      it "returns false" do
        expect(batch.send(:should_enforce_group_membership?)).to be false
      end
    end
  end

  describe "#emit_batch_filtering_metrics" do
    let(:batch) do
      described_class.new(
        dependency_snapshot: dependency_snapshot,
        group: dependency_group,
        job: job
      )
    end

    context "when metrics are available" do
      before do
        # Mock the Metrics constant
        stub_const("Dependabot::Metrics", double)
      end

      it "emits filtering metrics when dependencies are removed" do
        expect(Dependabot::Metrics).to receive(:increment)
          .with(
            "dependabot.batch.filtered_out_count",
            2,
            tags: {
              group: "backend",
              ecosystem: "bundler",
              original_count: 5,
              filtered_count: 3
            }
          )

        batch.send(:emit_batch_filtering_metrics, 5, 3, 2)
      end

      it "does not emit metrics when no dependencies are removed" do
        expect(Dependabot::Metrics).not_to receive(:increment)

        batch.send(:emit_batch_filtering_metrics, 5, 5, 0)
      end
    end

    context "when metrics are not available" do
      it "handles missing Metrics constant gracefully" do
        expect { batch.send(:emit_batch_filtering_metrics, 5, 3, 2) }.not_to raise_error
      end
    end
  end
end
