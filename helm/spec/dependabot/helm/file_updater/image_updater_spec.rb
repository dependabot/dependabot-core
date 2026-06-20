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
  let(:dependency_new_digest) { nil }
  let(:dependency_old_digest) { nil }
  let(:dependency_requirements) do
    [{
      file: "values.yaml",
      requirement: dependency_version,
      groups: [],
      source: {
        type: "docker_registry",
        registry: "docker.io",
        repository: "nginx",
        tag: dependency_version,
        digest: dependency_new_digest
      }.compact,
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
        tag: dependency_previous_version,
        digest: dependency_old_digest
      }.compact,
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

    context "when the recorded previous tag is not present in the YAML" do
      # The file updater matches the YAML scalar against the OLD tag
      # (previous_requirements), so a previous tag that doesn't appear in the
      # values file should produce no change and trigger the guard.
      let(:dependency_previous_requirements) do
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

      # Arrays of tags aren't a real Helm pattern -- there's no scalar tag to
      # update -- so the updater should fail loudly rather than silently
      # producing a no-op diff (which the trailing-newline guard previously
      # allowed through as a spurious newline-only PR).
      it "raises rather than producing a no-op diff" do
        expect { updater.updated_values_yaml_content("values.yaml") }
          .to raise_error("Expected content to change!")
      end
    end

    context "when the input ends with a trailing newline and no tag matches" do
      # Regression test: previously the split("\n").join("\n") round-trip
      # silently dropped the trailing newline, producing a non-empty diff
      # even when no tag scalar matched. The guard would then fail to fire
      # and dependabot would open a spurious newline-only PR.
      let(:dependency_previous_requirements) do
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

      let(:fixture_content) do
        <<~YAML
          image:
            repository: nginx
            tag: 1.20.0
        YAML
      end

      it "raises rather than producing a no-op diff" do
        expect { updater.updated_values_yaml_content("values.yaml") }
          .to raise_error("Expected content to change!")
      end
    end

    context "with a digest-pinned tag (tag@sha256:...)" do
      let(:dependency_old_digest) { "sha256:ef895fdef7a8ea2a12cf421cd56b13c3bb65c806a09ea75a8284a78736ae5da5" }
      let(:dependency_new_digest) { "sha256:abc123aaaa00000000000000000000000000000000000000000000000000000a" }

      let(:fixture_content) do
        <<~YAML
          image:
            repository: nginx
            tag: "1.20.0@#{dependency_old_digest}"
            pullPolicy: IfNotPresent
        YAML
      end

      it "updates the tag and replaces the old digest with the new one" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to include(%(tag: "1.21.0@#{dependency_new_digest}"))
        expect(updated_content).not_to include("1.20.0@")
        expect(updated_content).not_to include(dependency_old_digest)
      end

      it "preserves the trailing newline" do
        updated_content = updater.updated_values_yaml_content("values.yaml")
        expect(updated_content).to end_with("\n")
      end

      context "when the tag is unquoted" do
        let(:fixture_content) do
          <<~YAML
            image:
              repository: nginx
              tag: 1.20.0@#{dependency_old_digest}
          YAML
        end

        it "updates the tag and the digest" do
          updated_content = updater.updated_values_yaml_content("values.yaml")
          expect(updated_content).to include("tag: 1.21.0@#{dependency_new_digest}")
          expect(updated_content).not_to include("1.20.0@")
          expect(updated_content).not_to include(dependency_old_digest)
        end
      end

      context "when the tag line has a trailing comment" do
        let(:fixture_content) do
          <<~YAML
            image:
              repository: nginx
              tag: "1.20.0@#{dependency_old_digest}"  # keep in lockstep with upstream
          YAML
        end

        it "updates the tag and digest while preserving the trailing comment" do
          updated_content = updater.updated_values_yaml_content("values.yaml")
          expect(updated_content)
            .to include(%(tag: "1.21.0@#{dependency_new_digest}"  # keep in lockstep with upstream))
          expect(updated_content).not_to include("1.20.0@")
          expect(updated_content).not_to include(dependency_old_digest)
        end
      end
    end
  end
end
