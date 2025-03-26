# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/credential"
require "dependabot/helm/file_updater/lock_file_generator"
require "dependabot/helm/helpers"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::Helm::FileUpdater::LockFileGenerator do
  let(:generator) do
    described_class.new(
      dependencies: dependencies,
      dependency_files: dependency_files,
      repo_contents_path: repo_contents_path,
      credentials: credentials
    )
  end

  let(:dependencies) do
    [
      Dependabot::Dependency.new(
        name: "mysql",
        version: "8.2.0",
        requirements: [{
          file: "Chart.yaml",
          requirement: "8.2.0",
          groups: [],
          source: nil,
          metadata: { type: :helm_chart }
        }],
        previous_version: "8.1.0",
        previous_requirements: [{
          file: "Chart.yaml",
          requirement: "8.1.0",
          groups: [],
          source: nil,
          metadata: { type: :helm_chart }
        }],
        package_manager: "helm"
      )
    ]
  end

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Chart.yaml",
        content: chart_yaml_content,
        directory: "/"
      ),
      Dependabot::DependencyFile.new(
        name: "Chart.lock",
        content: chart_lock_content,
        directory: "/"
      )
    ]
  end

  let(:chart_yaml_content) do
    <<~YAML
      apiVersion: v2
      name: example-app
      version: 1.0.0
      description: Example Helm chart
      type: application
      dependencies:
      - name: mysql
        version: 8.1.0
        repository: https://charts.bitnami.com/bitnami
    YAML
  end

  let(:chart_lock_content) do
    <<~YAML
      dependencies:
      - name: mysql
        repository: https://charts.bitnami.com/bitnami
        version: 8.1.0
      digest: sha256:abc123def456
      generated: "2023-01-01T12:00:00Z"
    YAML
  end

  let(:updated_chart_yaml_content) do
    <<~YAML
      apiVersion: v2
      name: example-app
      version: 1.0.0
      description: Example Helm chart
      type: application
      dependencies:
      - name: mysql
        version: 8.2.0
        repository: https://charts.bitnami.com/bitnami
    YAML
  end

  let(:updated_chart_lock_content) do
    <<~YAML
      dependencies:
      - name: mysql
        repository: https://charts.bitnami.com/bitnami
        version: 8.2.0
      digest: sha256:def456abc789
      generated: "2023-01-02T12:00:00Z"
    YAML
  end

  let(:repo_contents_path) { "/tmp/dependabot/repo" }
  let(:credentials) { [] }

  let(:chart_lock) { dependency_files.find { |f| f.name == "Chart.lock" } }

  describe "#updated_chart_lock" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_repo_directory).and_yield
      allow(Dependabot::SharedHelpers).to receive(:with_git_configured).and_yield
      allow(File).to receive(:write)
      allow(File).to receive(:read).with("Chart.lock").and_return(updated_chart_lock_content)
      allow(Dependabot::Helm::Helpers).to receive(:update_lock)
    end

    it "creates a temporary repo directory" do
      generator.updated_chart_lock(chart_lock, updated_chart_yaml_content)
      expect(Dependabot::SharedHelpers).to have_received(:in_a_temporary_repo_directory).with("/", repo_contents_path)
    end

    it "configures git with credentials" do
      generator.updated_chart_lock(chart_lock, updated_chart_yaml_content)
      expect(Dependabot::SharedHelpers).to have_received(:with_git_configured).with(credentials: credentials)
    end

    it "writes the updated Chart.yaml content to a file" do
      generator.updated_chart_lock(chart_lock, updated_chart_yaml_content)
      expect(File).to have_received(:write).with("Chart.yaml", updated_chart_yaml_content)
    end

    it "calls update_lock helper" do
      generator.updated_chart_lock(chart_lock, updated_chart_yaml_content)
      expect(Dependabot::Helm::Helpers).to have_received(:update_lock)
    end

    it "reads and returns the updated Chart.lock content" do
      result = generator.updated_chart_lock(chart_lock, updated_chart_yaml_content)
      expect(File).to have_received(:read).with("Chart.lock")
      expect(result).to eq(updated_chart_lock_content)
    end

    context "with a different directory" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "Chart.yaml",
            content: chart_yaml_content,
            directory: "/charts/myapp"
          ),
          Dependabot::DependencyFile.new(
            name: "Chart.lock",
            content: chart_lock_content,
            directory: "/charts/myapp"
          )
        ]
      end

      it "uses the correct base directory" do
        generator.updated_chart_lock(chart_lock, updated_chart_yaml_content)
        expect(Dependabot::SharedHelpers).to have_received(:in_a_temporary_repo_directory).with("/charts/myapp",
                                                                                                repo_contents_path)
      end
    end

    context "with credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          )
        ]
      end

      it "passes credentials to git configuration" do
        generator.updated_chart_lock(chart_lock, updated_chart_yaml_content)
        expect(Dependabot::SharedHelpers).to have_received(:with_git_configured).with(credentials: credentials)
      end
    end
  end
end
