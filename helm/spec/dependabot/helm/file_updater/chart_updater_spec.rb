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

      it "returns the content unchanged" do
        expect(updater.updated_chart_yaml_content(chart_yaml_file)).to eq(chart_yaml_file.content)
      end
    end

    context "when the file doesn't contain the dependency" do
      let(:fixture_name) { "chart_without_dependencies.yaml" }

      it "returns the content unchanged" do
        expect(updater.updated_chart_yaml_content(chart_yaml_file)).to eq(chart_yaml_file.content)
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

      it "returns the content unchanged" do
        expect(updater.updated_chart_yaml_content(chart_yaml_file)).to eq(chart_yaml_file.content)
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

      it "returns the content unchanged" do
        expect(updater.updated_chart_yaml_content(chart_yaml_file)).to eq(chart_yaml_file.content)
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

    context "when preserving a range requirement (versioning-strategy)" do
      let(:fixture_name) { "chart_with_range_dependency.yaml" }
      let(:dependency_version) { "2.0.0" }
      let(:dependency_previous_version) { "1.0.0" }
      let(:dependency_requirements) do
        [{ file: "Chart.yaml", requirement: "^2.0.0", groups: [],
           source: { tag: "^1.0.0" }, metadata: { type: :helm_chart } }]
      end
      let(:dependency_previous_requirements) do
        [{ file: "Chart.yaml", requirement: "^1.0.0", groups: [],
           source: { tag: "1.0.0" }, metadata: { type: :helm_chart } }]
      end

      it "writes the new requirement string, not the bare resolved version" do
        updated_content = updater.updated_chart_yaml_content(chart_yaml_file)
        expect(updated_content).to include("- name: mysql\n    version: ^2.0.0")
        expect(updated_content).not_to include("version: ^1.0.0")
      end
    end

    context "when widening an explicit range requirement" do
      let(:fixture_name) { "chart_with_explicit_range.yaml" }
      let(:dependency_version) { "2.5.0" }
      let(:dependency_previous_version) { "1.0.0" }
      let(:dependency_requirements) do
        [{ file: "Chart.yaml", requirement: ">=1.0.0 <3.0.0", groups: [],
           source: { tag: ">=1.0.0 <2.0.0" }, metadata: { type: :helm_chart } }]
      end
      let(:dependency_previous_requirements) do
        [{ file: "Chart.yaml", requirement: ">=1.0.0 <2.0.0", groups: [],
           source: { tag: "1.0.0" }, metadata: { type: :helm_chart } }]
      end

      it "quotes the range so the YAML stays valid" do
        updated_content = updater.updated_chart_yaml_content(chart_yaml_file)
        expect(updated_content).to include('version: ">=1.0.0 <3.0.0"')
        expect(YAML.safe_load(updated_content)).to be_a(Hash)
      end
    end

    context "when the same chart appears twice with different constraints" do
      let(:fixture_name) { "chart_with_duplicate_dependency.yaml" }
      let(:dependency_name) { "common" }
      let(:dependency_version) { "1.5.0" }
      let(:dependency_previous_version) { "1.0.0" }
      let(:dependency_requirements) do
        [
          { file: "Chart.yaml", requirement: "^1.5.0", groups: [],
            source: { tag: "^1.0.0" }, metadata: { type: :helm_chart } },
          { file: "Chart.yaml", requirement: "1.5.0", groups: [],
            source: { tag: "1.2.0" }, metadata: { type: :helm_chart } }
        ]
      end
      let(:dependency_previous_requirements) do
        [
          { file: "Chart.yaml", requirement: "^1.0.0", groups: [],
            source: { tag: "^1.0.0" }, metadata: { type: :helm_chart } },
          { file: "Chart.yaml", requirement: "1.2.0", groups: [],
            source: { tag: "1.2.0" }, metadata: { type: :helm_chart } }
        ]
      end

      it "updates each entry by its own authored constraint" do
        updated_content = updater.updated_chart_yaml_content(chart_yaml_file)
        expect(updated_content).to include("version: ^1.5.0")
        expect(updated_content).to include("version: 1.5.0")
        expect(updated_content).not_to include("version: ^1.0.0")
        expect(updated_content).not_to include("version: 1.2.0")
      end
    end

    context "when one entry's new version equals another duplicate entry's old version" do
      # Regression: a per-entry whole-file gsub would alias — rewriting the first
      # entry to 2.0.0 then re-matching it when updating the second (old 2.0.0).
      let(:fixture_name) { "chart_with_aliasing_dependency.yaml" }
      let(:dependency_name) { "common" }
      let(:dependency_version) { "2.5.0" }
      let(:dependency_previous_version) { "1.0.0" }
      let(:dependency_requirements) do
        [
          { file: "Chart.yaml", requirement: "2.0.0", groups: [],
            source: { tag: "1.0.0" }, metadata: { type: :helm_chart } },
          { file: "Chart.yaml", requirement: "2.5.0", groups: [],
            source: { tag: "2.0.0" }, metadata: { type: :helm_chart } }
        ]
      end
      let(:dependency_previous_requirements) do
        [
          { file: "Chart.yaml", requirement: nil, groups: [],
            source: { tag: "1.0.0" }, metadata: { type: :helm_chart } },
          { file: "Chart.yaml", requirement: nil, groups: [],
            source: { tag: "2.0.0" }, metadata: { type: :helm_chart } }
        ]
      end

      it "rewrites each entry independently without aliasing" do
        updated_content = updater.updated_chart_yaml_content(chart_yaml_file)
        expect(updated_content).to include("- name: common\n    version: 2.0.0")
        expect(updated_content).to include("- name: common\n    version: 2.5.0")
      end
    end

    context "when the dependency name is quoted" do
      let(:dependency_name) { "mysql" }
      let(:dependency_version) { "8.2.0" }
      let(:dependency_previous_version) { "8.1.0" }
      let(:chart_yaml_file) do
        Dependabot::DependencyFile.new(
          name: "Chart.yaml",
          content: "apiVersion: v2\ndependencies:\n  - name: \"mysql\"\n    version: 8.1.0\n"
        )
      end

      it "still updates the entry" do
        expect(updater.updated_chart_yaml_content(chart_yaml_file))
          .to include("version: 8.2.0")
      end
    end

    context "when a changed constraint has no matching entry layout" do
      # A changed requirement that the writer can't locate (here, version listed
      # before name) must be surfaced, not silently dropped into a partial PR.
      let(:dependency_name) { "mysql" }
      let(:dependency_version) { "8.2.0" }
      let(:dependency_previous_version) { "8.1.0" }
      let(:chart_yaml_file) do
        Dependabot::DependencyFile.new(
          name: "Chart.yaml",
          content: "apiVersion: v2\ndependencies:\n  - version: 8.1.0\n    name: mysql\n"
        )
      end

      it "raises rather than emitting a partial update" do
        expect { updater.updated_chart_yaml_content(chart_yaml_file) }
          .to raise_error(/Expected to update mysql/)
      end
    end
  end
end
