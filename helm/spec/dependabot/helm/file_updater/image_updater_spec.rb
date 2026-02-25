# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/helm/file_updater/image_updater"

RSpec.describe Dependabot::Helm::FileUpdater::ImageUpdater do
  let(:updater) { described_class.new(dependency: dependency, dependency_files: dependency_files) }

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

  let(:dependency_name) { "nginx" }
  let(:dependency_version) { "1.21.0" }
  let(:dependency_previous_version) { "1.20.0" }
  let(:dependency_requirements) do
    [{
      file: "values.yaml",
      requirement: dependency_version,
      groups: [],
      source: {
        type: "docker_registry",
        registry: "docker.io",
        repository: "nginx",
        tag: dependency_previous_version
      },
      metadata: { type: :docker_image }
    }]
  end
  let(:dependency_previous_requirements) do
    [{
      file: "values.yaml",
      requirement: dependency_previous_version,
      groups: [],
      source: {
        type: "docker_registry",
        registry: "docker.io",
        repository: "nginx",
        tag: dependency_previous_version
      },
      metadata: { type: :docker_image }
    }]
  end

  let(:dependency_files) do
    [values_yaml_file]
  end

  let(:values_yaml_file) do
    Dependabot::DependencyFile.new(
      name: "values.yaml",
      content: fixture_content
    )
  end

  describe "#updated_values_yaml_content" do
    context "with standard image reference" do
      let(:fixture_content) do
        <<~YAML
          replicaCount: 1

          image:
            repository: nginx
            tag: 1.20.0
            pullPolicy: IfNotPresent

          service:
            type: ClusterIP
            port: 80
        YAML
      end

      it "updates the image tag" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to include("tag: 1.21.0")
        expect(updated_content).not_to include("tag: 1.20.0")
      end

      it "maintains the rest of the content unchanged" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to include("repository: nginx")
        expect(updated_content).to include("pullPolicy: IfNotPresent")
        expect(updated_content).to include("service:")
      end
    end

    context "with multiple documents in the YAML file" do
      let(:fixture_content) do
        <<~YAML
          image:
            repository: nginx
            tag: 1.20.0
          ---
          image:
            repository: nginx
            tag: 1.20.0
        YAML
      end

      it "updates the image tag in all documents" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content.scan("tag: 1.21.0").count).to eq(2)
        expect(updated_content).not_to include("tag: 1.20.0")
      end
    end

    context "with nested image references" do
      let(:fixture_content) do
        <<~YAML
          components:
            frontend:
              image:
                repository: nginx
                tag: 1.20.0
            backend:
              image:
                repository: another-image
                tag: 2.3.4
        YAML
      end

      it "updates only the relevant image tag" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to include("repository: nginx\n      tag: 1.21.0")
        expect(updated_content).to include("repository: another-image\n      tag: 2.3.4")
      end
    end

    context "with image references in a list" do
      let(:fixture_content) do
        <<~YAML
          deployments:
            - name: frontend
              image:
                repository: nginx
                tag: 1.20.0
            - name: backend
              image:
                repository: another-image
                tag: 2.3.4
        YAML
      end

      it "updates only the relevant image tag" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to include("repository: nginx\n      tag: 1.21.0")
        expect(updated_content).to include("repository: another-image\n      tag: 2.3.4")
      end
    end

    context "with complex nested structure" do
      let(:fixture_content) do
        <<~YAML
          global:
            settings:
              deployments:
                - name: frontend
                  containers:
                    - image:
                        repository: nginx
                        tag: 1.20.0
                - name: admin
                  containers:
                    - image:
                        repository: nginx
                        tag: 1.20.0
                    - image:
                        repository: another-image
                        tag: 2.3.4
        YAML
      end

      it "updates all relevant image tags" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content.scan("tag: 1.21.0").count).to eq(2)
        expect(updated_content).to include("repository: another-image\n              tag: 2.3.4")
        expect(updated_content).not_to include("tag: 1.20.0")
      end
    end

    context "with different file name" do
      let(:values_yaml_file) do
        Dependabot::DependencyFile.new(
          name: "custom-values.yaml",
          content: fixture_content
        )
      end

      let(:fixture_content) do
        <<~YAML
          image:
            repository: nginx
            tag: 1.20.0
        YAML
      end

      it "updates the image tag when file name matches" do
        updated_content = updater.updated_values_yaml_content("custom-values.yaml")
        expect(updated_content).to include("tag: 1.21.0")
        expect(updated_content).not_to include("tag: 1.20.0")
      end
    end

    context "when tag does not match" do
      let(:dependency_requirements) do
        [{
          file: "values.yaml",
          requirement: nil,
          groups: [],
          source: {
            type: "docker_registry",
            registry: "docker.io",
            repository: "nginx",
            tag: "wrong-tag"
          },
          metadata: { type: :docker_image }
        }]
      end

      let(:fixture_content) { "image:\n  repository: nginx\n  tag: 1.20.0" }

      it "raises an error because content should change" do
        expect { updater.updated_values_yaml_content("values.yaml") }
          .to raise_error("Expected content to change!")
      end
    end

    context "when dependency name does not match" do
      let(:dependency_name) { "different-image" }

      let(:fixture_content) { "image:\n  repository: nginx\n  tag: 1.20.0" }

      it "raises an error because content should change" do
        expect { updater.updated_values_yaml_content("values.yaml") }
          .to raise_error("Expected content to change!")
      end
    end

    context "when dependency metadata type is not docker_image" do
      let(:dependency_requirements) do
        [{
          file: "values.yaml",
          requirement: nil,
          groups: [],
          source: {
            type: "docker_registry",
            registry: "docker.io",
            repository: "nginx",
            tag: "1.21.0"
          },
          metadata: { type: :other_type }
        }]
      end
      let(:fixture_content) { "image:\n  repository: nginx\n  tag: 1.20.0" }

      it "raises an error because content should change" do
        expect { updater.updated_values_yaml_content("values.yaml") }
          .to raise_error("Expected content to change!")
      end
    end

    context "with quoted tags" do
      let(:fixture_content) do
        <<~YAML
          image:
            repository: nginx
            tag: "1.20.0"
        YAML
      end

      it "updates the tag and preserves the quotes" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to include('tag: "1.21.0"')
        expect(updated_content).not_to include('tag: "1.20.0"')
      end
    end

    context "with different indentation" do
      let(:fixture_content) do
        <<~YAML
          services:
              frontend:
                  image:
                      repository: nginx
                      tag: 1.20.0
        YAML
      end

      it "preserves the indentation" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to include("      tag: 1.21.0")
        expect(updated_content).not_to include("      tag: 1.20.0")
      end
    end

    context "with no file match" do
      let(:values_yaml_file) do
        Dependabot::DependencyFile.new(
          name: "different.yaml",
          content: "image:\n    repository: nginx\n      tag: 1.20.0"
        )
      end

      it "raises an error because content should change" do
        expect { updater.updated_values_yaml_content("values.yaml") }
          .to raise_error("Expected a values.yaml file to exist!")
      end
    end

    context "with complex YAML structure containing arrays and maps" do
      let(:fixture_content) do
        <<~YAML
          image:
            repository: nginx
            tag:
              - 1.20.0
        YAML
      end

      it "processes the image tag and preserving complex structures" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to include("- 1.20.0")
      end
    end

    context "with v-prefixed version tags" do
      let(:dependency_version) { "v1.21.0" }
      let(:dependency_previous_version) { "v1.20.0" }
      let(:dependency_requirements) do
        [{
          file: "values.yaml",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "docker_registry",
            registry: "docker.io",
            repository: "nginx",
            tag: dependency_previous_version
          },
          metadata: { type: :docker_image }
        }]
      end
      let(:dependency_previous_requirements) do
        [{
          file: "values.yaml",
          requirement: dependency_previous_version,
          groups: [],
          source: {
            type: "docker_registry",
            registry: "docker.io",
            repository: "nginx",
            tag: dependency_previous_version
          },
          metadata: { type: :docker_image }
        }]
      end

      let(:fixture_content) do
        <<~YAML
          image:
            repository: nginx
            tag: v1.20.0
            pullPolicy: IfNotPresent
        YAML
      end

      it "preserves the v prefix when updating the tag" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to include("tag: v1.21.0")
        expect(updated_content).not_to include("tag: v1.20.0")
        expect(updated_content).not_to include("tag: 1.21.0") # should not drop the v prefix
      end
    end

    context "with various v-prefixed tag formats" do
      let(:dependency_name) { "ghcr.io/llm-d/llm-d-inference-sim" }
      let(:dependency_version) { "v0.1.2" }
      let(:dependency_previous_version) { "v0.1.1" }
      let(:dependency_requirements) do
        [{
          file: "values.yaml",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "docker_registry",
            registry: "ghcr.io",
            repository: "ghcr.io/llm-d/llm-d-inference-sim",
            tag: dependency_previous_version
          },
          metadata: { type: :docker_image }
        }]
      end
      let(:dependency_previous_requirements) do
        [{
          file: "values.yaml",
          requirement: dependency_previous_version,
          groups: [],
          source: {
            type: "docker_registry",
            registry: "ghcr.io",
            repository: "ghcr.io/llm-d/llm-d-inference-sim",
            tag: dependency_previous_version
          },
          metadata: { type: :docker_image }
        }]
      end

      let(:fixture_content) do
        <<~YAML
          test:
            image:
              repository: ghcr.io/llm-d/llm-d-inference-sim
              tag: v0.1.1
        YAML
      end

      it "preserves the v prefix for complex version tags" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to include("tag: v0.1.2")
        expect(updated_content).not_to include("tag: v0.1.1")
        expect(updated_content).not_to include("tag: 0.1.2") # should not drop the v prefix
      end
    end
    context "when dependency version lacks v-prefix but YAML tag has it" do
      let(:dependency_name) { "ghcr.io/llm-d/llm-d-inference-sim" }
      let(:dependency_version) { "0.1.2" } # No v prefix
      let(:dependency_previous_version) { "0.1.1" } # No v prefix
      let(:dependency_requirements) do
        [{
          file: "values.yaml",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "docker_registry",
            registry: "ghcr.io",
            repository: "ghcr.io/llm-d/llm-d-inference-sim",
            tag: "v0.1.1"  # Tag has v prefix
          },
          metadata: { type: :docker_image }
        }]
      end
      let(:dependency_previous_requirements) do
        [{
          file: "values.yaml",
          requirement: dependency_previous_version,
          groups: [],
          source: {
            type: "docker_registry",
            registry: "ghcr.io",
            repository: "ghcr.io/llm-d/llm-d-inference-sim",
            tag: "v0.1.1"  # Tag has v prefix
          },
          metadata: { type: :docker_image }
        }]
      end

      let(:fixture_content) do
        <<~YAML
          test:
            image:
              repository: ghcr.io/llm-d/llm-d-inference-sim
              tag: v0.1.1
        YAML
      end

      it "should preserve the v prefix from the original tag format" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        # The expectation is that it should preserve the v prefix from the original format
        expect(updated_content).to include("tag: v0.1.2")
        expect(updated_content).not_to include("tag: v0.1.1")
        expect(updated_content).not_to include("tag: 0.1.2") # should not drop the v prefix
      end
    end
    context "when dependency version has v-prefix but YAML tag lacks it" do
      let(:dependency_name) { "nginx" }
      let(:dependency_version) { "v1.21.0" } # Has v prefix
      let(:dependency_previous_version) { "v1.20.0" } # Has v prefix
      let(:dependency_requirements) do
        [{
          file: "values.yaml",
          requirement: dependency_version,
          groups: [],
          source: {
            type: "docker_registry",
            registry: "docker.io",
            repository: "nginx",
            tag: "1.20.0"  # Tag lacks v prefix
          },
          metadata: { type: :docker_image }
        }]
      end
      let(:dependency_previous_requirements) do
        [{
          file: "values.yaml",
          requirement: dependency_previous_version,
          groups: [],
          source: {
            type: "docker_registry",
            registry: "docker.io",
            repository: "nginx",
            tag: "1.20.0"  # Tag lacks v prefix
          },
          metadata: { type: :docker_image }
        }]
      end

      let(:fixture_content) do
        <<~YAML
          image:
            repository: nginx
            tag: 1.20.0
            pullPolicy: IfNotPresent
        YAML
      end

      it "should preserve the lack of v prefix from the original tag format" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        # The expectation is that it should preserve the lack of v prefix from the original format
        expect(updated_content).to include("tag: 1.21.0")
        expect(updated_content).not_to include("tag: 1.20.0")
        expect(updated_content).not_to include("tag: v1.21.0") # should not add v prefix
      end
    end
  end
end
