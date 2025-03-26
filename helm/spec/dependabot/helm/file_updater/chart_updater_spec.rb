# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/helm/file_updater/chart_updater"

RSpec.describe Dependabot::Helm::FileUpdater::ChartUpdater do
  let(:updater) { described_class.new(dependency: dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      previous_version: dependency_previous_version,
      previous_requirements: dependency_previous_requirements,
      package_manager: "helm"
    )
  end

  let(:dependency_name) { "mysql" }
  let(:dependency_version) { "8.2.0" }
  let(:dependency_previous_version) { "8.1.0" }
  let(:dependency_requirements) do
    [{
      file: "Chart.yaml",
      requirement: "8.2.0",
      groups: [],
      source: { tag: "8.2.0" },
      metadata: { type: :helm_chart }
    }]
  end
  let(:dependency_previous_requirements) do
    [{
      file: "Chart.yaml",
      requirement: "8.1.0",
      groups: [],
      source: { tag: "8.1.0" },
      metadata: { type: :helm_chart }
    }]
  end

  let(:chart_yaml_file) do
    Dependabot::DependencyFile.new(
      name: "Chart.yaml",
      content: fixture("helm", "charts", fixture_name)
    )
  end

  let(:fixture_name) { "chart_with_dependencies.yaml" }

  describe "#updated_chart_yaml_content" do
    context "when the dependency is in the chart dependencies" do
      it "updates the dependency version" do
        updated_content = updater.updated_chart_yaml_content(chart_yaml_file)
        expect(updated_content).to include("- name: mysql\n    version: 8.2.0")
      end

      context "with single quotes" do
        let(:fixture_name) { "chart_with_single_quotes.yaml" }

        it "preserves quote style while updating version" do
          updated_content = updater.updated_chart_yaml_content(chart_yaml_file)
          expect(updated_content).to include("- name: mysql\n    version: 8.2.0")
          expect(updated_content).not_to include("version: '8.1.0'")
        end
      end

      context "with double quotes" do
        let(:fixture_name) { "chart_with_double_quotes.yaml" }

        it "preserves quote style while updating version" do
          updated_content = updater.updated_chart_yaml_content(chart_yaml_file)
          expect(updated_content).to include("- name: mysql\n    version: 8.2.0")
          expect(updated_content).not_to include('version: "8.1.0"')
        end
      end
    end

    context "when the dependency is not in the chart dependencies" do
      let(:dependency_name) { "postgresql" }

      it "raises an error because content should change" do
        expect { updater.updated_chart_yaml_content(chart_yaml_file) }
          .to raise_error("Expected content to change!")
      end
    end

    context "when the file doesn't contain the dependency" do
      let(:fixture_name) { "chart_without_dependencies.yaml" }

      it "raises an error because content should change" do
        expect { updater.updated_chart_yaml_content(chart_yaml_file) }
          .to raise_error("Expected content to change!")
      end
    end

    context "when the dependency metadata type is not helm_chart" do
      let(:dependency_requirements) do
        [{
          file: "Chart.yaml",
          requirement: "8.2.0",
          groups: [],
          source: nil,
          metadata: { type: :other_type }
        }]
      end

      it "raises an error because content should change" do
        expect { updater.updated_chart_yaml_content(chart_yaml_file) }
          .to raise_error("Expected content to change!")
      end
    end

    context "when the file is for a different dependency" do
      let(:dependency_requirements) do
        [{
          file: "another_chart.yaml",
          requirement: "8.2.0",
          groups: [],
          source: nil,
          metadata: { type: :helm_chart }
        }]
      end

      it "raises an error because content should change" do
        expect { updater.updated_chart_yaml_content(chart_yaml_file) }
          .to raise_error("Expected content to change!")
      end
    end

    context "with multiple dependencies" do
      let(:fixture_name) { "chart_with_multiple_dependencies.yaml" }

      it "updates only the specified dependency" do
        updated_content = updater.updated_chart_yaml_content(chart_yaml_file)
        expect(updated_content).to include("- name: mysql\n    version: 8.2.0")
        expect(updated_content).to include("- name: redis\n    version: 6.0.0")
        expect(updated_content).not_to include("version: 8.1.0")
      end
    end

    context "with unusual spacing" do
      let(:fixture_name) { "chart_with_unusual_spacing.yaml" }

      it "preserves spacing while updating version" do
        updated_content = updater.updated_chart_yaml_content(chart_yaml_file)
        expect(updated_content).to include("-   name: mysql\n      version: 8.2.0")
        expect(updated_content).not_to include("version: 8.1.0")
      end
    end
  end
end
