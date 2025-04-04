# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/helm/file_parser"

require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Helm::FileParser do
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:helmfile_fixture_name) { "single.yaml" }
  let(:helmfile_body) do
    fixture("helm", "v3", helmfile_fixture_name)
  end
  let(:helmfile) do
    Dependabot::DependencyFile.new(
      name: "Chart.yaml",
      content: helmfile_body
    )
  end
  let(:files) { [helmfile] }

  it_behaves_like "a dependency file parser"

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(1) }

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }

      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          metadata: { type: :helm_chart },
          file: "Chart.yaml",
          source: { registry: "https://charts.bitnami.com/bitnami", tag: "17.11.3" }
        }]
      end

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("redis")
        expect(dependency.version).to eq("17.11.3")
        expect(dependency.requirements).to eq(expected_requirements)
      end
    end

    context "with no tag or digest" do
      let(:helmfile_fixture_name) { "bare.yaml" }

      its(:length) { is_expected.to eq(0) }
    end

    context "with multiple services" do
      let(:helmfile_fixture_name) { "basic.yaml" }

      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            metadata: { type: :helm_chart },
            file: "Chart.yaml",
            source: { registry: "https://charts.bitnami.com/bitnami", tag: "17.11.3" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("redis")
          expect(dependency.version).to eq("17.11.3")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end

      describe "the second dependency" do
        subject(:dependency) { dependencies.last }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            metadata: { type: :helm_chart },
            file: "Chart.yaml",
            source: { registry: "https://charts.bitnami.com/bitnami", tag: "13.9.1" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("mongodb")
          expect(dependency.version).to eq("13.9.1")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    context "with a non-numeric version" do
      let(:helmfile_fixture_name) { "non_numeric.yaml" }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        let(:expected_requirements) do
          [{
            requirement: nil,
            groups: [],
            metadata: { type: :helm_chart },
            file: "Chart.yaml",
            source: { registry: "https://charts.bitnami.com/bitnami", tag: "17.11.3-dev" }
          }]
        end

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("redis")
          expect(dependency.version).to eq("17.11.3-dev")
          expect(dependency.requirements).to eq(expected_requirements)
        end
      end
    end

    describe "YAML.safe_load with permitted_classes" do
      context "with Chart.yaml" do
        subject(:dependency) { dependencies.first }

        let(:helmfile_fixture_name) { "chart_permitted_classes.yaml" }

        it "is able to parse yaml with date, time, and symbol" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("redis")
          expect(dependency.version).to eq("17.11.3")
        end
      end

      context "with values.yaml" do
        subject(:dependency) { dependencies.first }

        let(:helmfile_fixture_name) { "values_permitted_classes.yaml" }
        let(:helmfile) do
          Dependabot::DependencyFile.new(
            name: "values.yaml",
            content: helmfile_body
          )
        end

        it "is able to parse yaml with date, time, and symbol" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("nginx")
          expect(dependency.version).to eq("1.25.3")
        end
      end
    end
  end

  describe "version_from with environment variables" do
    context "with a parameterized tag" do
      let(:helmfile) do
        Dependabot::DependencyFile.new(
          name: "Chart.yaml",
          content: <<~YAML
            dependencies:
          YAML
        )
      end

      it "returns no dependencies" do
        expect(parser.parse).to be_empty
      end
    end
  end
end
