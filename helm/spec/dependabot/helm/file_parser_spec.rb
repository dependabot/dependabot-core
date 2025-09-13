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

  describe "values.yaml Docker image parsing" do
    let(:files) { [values_file] }
    let(:values_file) do
      Dependabot::DependencyFile.new(
        name: "values.yaml",
        content: values_content
      )
    end

    context "with separate registry and repository fields" do
      let(:values_content) do
        <<~YAML
          curl:
            image:
              repository: curl/curl
              tag: 8.12.0
              registry: quay.io

          argocli:
            image:
              repository: quay.io/argoproj/argocli
              tag: v3.6.6
        YAML
      end

      it "correctly handles images with separate registry field" do
        dependencies = parser.parse

        curl_dep = dependencies.find { |d| d.name == "quay.io/curl/curl" }
        expect(curl_dep).to be_a(Dependabot::Dependency)
        expect(curl_dep.version).to eq("8.12.0")
        expect(curl_dep.requirements.first[:source][:registry]).to eq("quay.io")
        expect(curl_dep.requirements.first[:source][:tag]).to eq("8.12.0")
      end

      it "correctly handles images with registry in repository field" do
        dependencies = parser.parse

        argocli_dep = dependencies.find { |d| d.name == "quay.io/argoproj/argocli" }
        expect(argocli_dep).to be_a(Dependabot::Dependency)
        expect(argocli_dep.version).to eq("v3.6.6")
        expect(argocli_dep.requirements.first[:source][:registry]).to eq("quay.io")
        expect(argocli_dep.requirements.first[:source][:tag]).to eq("v3.6.6")
      end

      it "prevents registry doubling when repository already contains registry" do
        # Test case specifically for issue #12207 - prevent registry doubling
        values_content_with_doubling = <<~YAML
          app:
            image:
              repository: quay.io/myorg/myapp
              tag: v1.0.0
              registry: quay.io
        YAML

        values_file = Dependabot::DependencyFile.new(
          name: "values.yaml",
          content: values_content_with_doubling
        )
        parser = described_class.new(dependency_files: [values_file], source: source)
        dependencies = parser.parse

        # Should find the dependency with correct name (no doubling)
        app_dep = dependencies.find { |d| d.name == "quay.io/myorg/myapp" }
        expect(app_dep).to be_a(Dependabot::Dependency)
        expect(app_dep.name).to eq("quay.io/myorg/myapp")
        expect(app_dep.version).to eq("v1.0.0")

        # Should not create a doubled registry version
        doubled_dep = dependencies.find { |d| d.name == "quay.io/quay.io/myorg/myapp" }
        expect(doubled_dep).to be_nil
      end
    end
  end
end
