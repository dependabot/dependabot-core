# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_attribution"

RSpec.describe Dependabot::DependencyAttribution do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "test-dependency",
      requirements: [],
      package_manager: "bundler"
    )
  end

  describe ".annotate_dependency" do
    it "adds attribution metadata to a dependency" do
      described_class.annotate_dependency(
        dependency,
        source_group: "backend",
        selection_reason: :direct,
        directory: "/api"
      )

      # Check that attribution metadata is properly set
      attribution = described_class.get_attribution(dependency)
      expect(attribution).to include(
        source_group: "backend",
        selection_reason: :direct,
        directory: "/api"
      )
      expect(attribution[:timestamp]).to be_a(Time)
    end

    it "validates selection reason" do
      described_class.annotate_dependency(
        dependency,
        source_group: "backend",
        selection_reason: :invalid_reason,
        directory: "/api"
      )

      expect(dependency.attribution_source_group).to be_nil
    end

    it "sets all attribution fields properly" do
      described_class.annotate_dependency(
        dependency,
        source_group: "test-group",
        selection_reason: :direct,
        directory: "/app"
      )

      expect(dependency.attribution_source_group).to eq("test-group")
      expect(dependency.attribution_selection_reason).to eq(:direct)
      expect(dependency.attribution_directory).to eq("/app")
      expect(dependency.attribution_timestamp).to be_a(Time)
    end
  end

  describe ".get_attribution" do
    context "when dependency has attribution" do
      before do
        described_class.annotate_dependency(
          dependency,
          source_group: "backend",
          selection_reason: :direct,
          directory: "/api"
        )
      end

      it "returns attribution hash" do
        attribution = described_class.get_attribution(dependency)
        expect(attribution).to include(
          source_group: "backend",
          selection_reason: :direct,
          directory: "/api"
        )
        expect(attribution[:timestamp]).to be_a(Time)
      end
    end

    context "with empty dependencies array" do
      it "handles empty arrays gracefully" do
        expect(described_class.extract_attribution_data([])).to eq([])

        summary = described_class.telemetry_summary([])
        expect(summary[:total_dependencies]).to eq(0)
        expect(summary[:attributed_dependencies]).to eq(0)
        expect(summary[:attribution_coverage]).to eq(0.0)
      end
    end
  end

  describe ".attributed?" do
    context "when dependency has attribution" do
      before do
        described_class.annotate_dependency(
          dependency,
          source_group: "backend",
          selection_reason: :direct,
          directory: "/api"
        )
      end

      it "returns true" do
        expect(described_class.attributed?(dependency)).to be(true)
      end
    end

    context "when dependency has no attribution" do
      it "returns false" do
        expect(described_class.attributed?(dependency)).to be(false)
      end
    end
  end

  describe ".extract_attribution_data" do
    let(:dependencies) do
      [
        Dependabot::Dependency.new(
          name: "attributed-dep",
          version: "1.0.0",
          previous_version: "0.9.0",
          requirements: [],
          package_manager: "bundler"
        ),
        Dependabot::Dependency.new(
          name: "unattributed-dep",
          version: "2.0.0",
          requirements: [],
          package_manager: "bundler"
        )
      ]
    end

    before do
      described_class.annotate_dependency(
        dependencies[0],
        source_group: "backend",
        selection_reason: :direct,
        directory: "/api"
      )
    end

    it "extracts attribution data from attributed dependencies" do
      data = described_class.extract_attribution_data(dependencies)
      expect(data.length).to eq(1)
      expect(data[0]).to include(
        name: "attributed-dep",
        version: "1.0.0",
        previous_version: "0.9.0",
        source_group: "backend",
        selection_reason: :direct,
        directory: "/api"
      )
    end
  end

  describe ".telemetry_summary" do
    let(:dependencies) do
      [
        Dependabot::Dependency.new(name: "dep1", requirements: [], package_manager: "bundler"),
        Dependabot::Dependency.new(name: "dep2", requirements: [], package_manager: "bundler"),
        Dependabot::Dependency.new(name: "dep3", requirements: [], package_manager: "bundler")
      ]
    end

    before do
      described_class.annotate_dependency(
        dependencies[0],
        source_group: "backend",
        selection_reason: :direct,
        directory: "/api"
      )
      described_class.annotate_dependency(
        dependencies[1],
        source_group: "frontend",
        selection_reason: :already_updated,
        directory: "/web"
      )
      # dependencies[2] remains unattributed
    end

    it "generates telemetry summary" do
      summary = described_class.telemetry_summary(dependencies)
      expect(summary).to include(
        total_dependencies: 3,
        attributed_dependencies: 2,
        attribution_coverage: 2.0 / 3
      )
      expect(summary[:selection_reasons]).to include(
        "direct" => 1,
        "already_updated" => 1
      )
      expect(summary[:source_groups]).to include(
        "backend" => 1,
        "frontend" => 1
      )
      expect(summary[:directories]).to include(
        "/api" => 1,
        "/web" => 1
      )
    end
  end

  describe "SELECTION_REASONS" do
    it "includes expected selection reasons" do
      expect(described_class::SELECTION_REASONS).to include(
        :direct,
        :already_updated,
        :dependency_drift,
        :not_in_group,
        :filtered_by_config,
        :unknown
      )
    end
  end
end
