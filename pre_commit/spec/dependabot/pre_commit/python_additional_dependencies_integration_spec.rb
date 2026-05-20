# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/pre_commit/file_parser"
require "dependabot/pre_commit/update_checker"
require "dependabot/pre_commit/file_updater"
require "dependabot/python"
require "dependabot/python/update_checker"
require "dependabot/python/version"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Python additional_dependencies integration" do
  let(:file) do
    Dependabot::DependencyFile.new(
      name: ".pre-commit-config.yaml",
      content: fixture("pre_commit_configs", "with_python_additional_dependencies.yaml")
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dependabot/dependabot-core"
    )
  end

  describe "FileParser" do
    let(:parser) do
      Dependabot::PreCommit::FileParser.new(
        dependency_files: [file],
        source: source,
        credentials: credentials
      )
    end

    it "parses Python additional_dependencies" do
      dependencies = parser.parse

      # Find additional_dependency dependencies
      additional_deps = dependencies.select do |dep|
        dep.requirements.any? { |req| req[:source]&.dig(:type) == "additional_dependency" }
      end

      # We have 12 parseable additional_dependencies in the fixture (those with versions)
      expect(additional_deps.length).to eq(12)

      # Verify types-requests
      types_requests = additional_deps.find do |dep|
        dep.requirements.first[:source][:package_name] == "types-requests"
      end
      expect(types_requests).not_to be_nil
      expect(types_requests.name).to eq("types-requests")
      expect(types_requests.version).to eq("2.31.0.1")
      expect(types_requests.requirements.first[:requirement]).to eq("==2.31.0.1")
      expect(types_requests.requirements.first[:source][:language]).to eq("python")
      expect(types_requests.requirements.first[:source][:hook_id]).to eq("mypy")

      # Verify types-PyYAML (normalized to types-pyyaml)
      types_pyyaml = additional_deps.find do |dep|
        dep.requirements.first[:source][:package_name] == "types-pyyaml"
      end
      expect(types_pyyaml).not_to be_nil
      expect(types_pyyaml.version).to eq("6.0.0")
      expect(types_pyyaml.requirements.first[:requirement]).to eq(">=6.0.0")

      # Verify black[d]
      black = additional_deps.find do |dep|
        dep.requirements.first[:source][:package_name] == "black"
      end
      expect(black).not_to be_nil
      expect(black.version).to eq("23.0.0")
      expect(black.requirements.first[:requirement]).to eq(">=23.0.0")
      expect(black.requirements.first[:source][:original_name]).to eq("black")
      expect(black.requirements.first[:source][:hook_id]).to eq("black")

      # Verify flake8-docstrings
      flake8_docstrings = additional_deps.find do |dep|
        dep.requirements.first[:source][:package_name] == "flake8-docstrings"
      end
      expect(flake8_docstrings).not_to be_nil
      expect(flake8_docstrings.version).to eq("1.7.0")
      expect(flake8_docstrings.requirements.first[:requirement]).to eq("~=1.7.0")
      expect(flake8_docstrings.requirements.first[:source][:hook_id]).to eq("flake8")
    end

    it "creates unique dependency names for same package in different hooks" do
      dependencies = parser.parse
      dep_names = dependencies.map(&:name)

      # If the same package appears in multiple hooks, each should have a unique name
      expect(dep_names.uniq.length).to eq(dep_names.length)
    end
  end

  describe "UpdateChecker" do
    let(:parser) do
      Dependabot::PreCommit::FileParser.new(
        dependency_files: [file],
        source: source,
        credentials: credentials
      )
    end

    let(:dependencies) { parser.parse }

    let(:dependency) do
      dependencies.find do |dep|
        dep.requirements.first[:source]&.dig(:package_name) == "types-requests"
      end
    end

    let(:update_checker) do
      Dependabot::PreCommit::UpdateChecker.new(
        dependency: dependency,
        dependency_files: [file],
        credentials: credentials,
        ignored_versions: [],
        security_advisories: [],
        raise_on_ignored: false
      )
    end

    let(:pip_checker) { instance_double(Dependabot::Python::UpdateChecker) }
    let(:latest_version_obj) { Dependabot::Python::Version.new("2.31.0.20") }

    before do
      allow(Dependabot::Python::UpdateChecker).to receive(:new).and_return(pip_checker)
      allow(pip_checker).to receive(:latest_version).and_return(latest_version_obj)
    end

    it "identifies the dependency as an additional_dependency" do
      expect(update_checker.send(:additional_dependency?)).to be true
    end

    it "delegates to Python::UpdateChecker for latest_version" do
      allow(Dependabot::Python::UpdateChecker).to receive(:new).with(
        hash_including(
          dependency: an_instance_of(Dependabot::Dependency),
          credentials: credentials
        )
      ).and_return(pip_checker)

      latest = update_checker.latest_version
      expect(latest).to eq("2.31.0.20")
    end

    it "generates updated requirements with correct format" do
      updated_reqs = update_checker.updated_requirements
      expect(updated_reqs.first[:requirement]).to eq("==2.31.0.20")
      expect(updated_reqs.first[:source][:original_string]).to eq("types-requests==2.31.0.20")
    end

    it "detects when update is available" do
      allow(update_checker).to receive(:latest_version).and_return("2.31.0.20")
      expect(update_checker.up_to_date?).to be false
      expect(update_checker.can_update?(requirements_to_unlock: :own)).to be true
    end
  end

  describe "FileUpdater" do
    let(:parser) do
      Dependabot::PreCommit::FileParser.new(
        dependency_files: [file],
        source: source,
        credentials: credentials
      )
    end

    let(:dependencies) { parser.parse }

    let(:dependency) do
      dependencies.find do |dep|
        dep.requirements.first[:source]&.dig(:package_name) == "types-requests"
      end
    end

    let(:updated_dependency) do
      Dependabot::Dependency.new(
        name: dependency.name,
        version: "2.31.0.20",
        previous_version: dependency.version,
        requirements: [{
          requirement: "==2.31.0.20",
          groups: ["additional_dependencies"],
          file: ".pre-commit-config.yaml",
          source: dependency.requirements.first[:source].merge(
            original_string: "types-requests==2.31.0.20"
          )
        }],
        previous_requirements: dependency.requirements,
        package_manager: "pre_commit"
      )
    end

    let(:file_updater) do
      Dependabot::PreCommit::FileUpdater.new(
        dependencies: [updated_dependency],
        dependency_files: [file],
        credentials: credentials
      )
    end

    it "updates the additional_dependency in the config file" do
      updated_files = file_updater.updated_dependency_files
      expect(updated_files.length).to eq(1)

      updated_content = updated_files.first.content
      expect(updated_content).to include("types-requests==2.31.0.20")
      expect(updated_content).not_to include("types-requests==2.31.0.1")

      # Verify other dependencies are unchanged
      expect(updated_content).to include("types-PyYAML>=6.0.0")
      expect(updated_content).to include("black[d]>=23.0.0")
      expect(updated_content).to include("flake8-docstrings~=1.7.0")
    end

    context "when updating dependency with extras" do
      let(:dependency) do
        dependencies.find do |dep|
          dep.requirements.first[:source]&.dig(:package_name) == "black"
        end
      end

      let(:updated_dependency) do
        Dependabot::Dependency.new(
          name: dependency.name,
          version: "24.0.0",
          previous_version: dependency.version,
          requirements: [{
            requirement: ">=24.0.0",
            groups: ["additional_dependencies"],
            file: ".pre-commit-config.yaml",
            source: dependency.requirements.first[:source].merge(
              original_string: "black[d]>=24.0.0"
            )
          }],
          previous_requirements: dependency.requirements,
          package_manager: "pre_commit"
        )
      end

      it "preserves extras in the update" do
        updated_files = file_updater.updated_dependency_files
        updated_content = updated_files.first.content

        expect(updated_content).to include("black[d]>=24.0.0")
        expect(updated_content).not_to include("black[d]>=23.0.0")
      end
    end

    context "when updating dependency with ~= operator" do
      let(:dependency) do
        dependencies.find do |dep|
          dep.requirements.first[:source]&.dig(:package_name) == "flake8-docstrings"
        end
      end

      let(:updated_dependency) do
        Dependabot::Dependency.new(
          name: dependency.name,
          version: "1.8.0",
          previous_version: dependency.version,
          requirements: [{
            requirement: "~=1.8.0",
            groups: ["additional_dependencies"],
            file: ".pre-commit-config.yaml",
            source: dependency.requirements.first[:source].merge(
              original_string: "flake8-docstrings~=1.8.0"
            )
          }],
          previous_requirements: dependency.requirements,
          package_manager: "pre_commit"
        )
      end

      it "preserves the ~= operator" do
        updated_files = file_updater.updated_dependency_files
        updated_content = updated_files.first.content

        expect(updated_content).to include("flake8-docstrings~=1.8.0")
        expect(updated_content).not_to include("flake8-docstrings~=1.7.0")
      end
    end
  end

  describe "Full workflow" do
    it "can parse, check, and update Python additional_dependencies" do
      # Step 1: Parse dependencies
      parser = Dependabot::PreCommit::FileParser.new(
        dependency_files: [file],
        source: source,
        credentials: credentials
      )
      dependencies = parser.parse

      additional_dep = dependencies.find do |dep|
        dep.requirements.first[:source]&.dig(:package_name) == "types-requests"
      end
      expect(additional_dep).not_to be_nil

      # Step 2: Check for updates (mocked)
      pip_checker = instance_double(Dependabot::Python::UpdateChecker)
      latest_version_obj = Dependabot::Python::Version.new("2.31.0.20")
      allow(Dependabot::Python::UpdateChecker).to receive(:new).and_return(pip_checker)
      allow(pip_checker).to receive(:latest_version).and_return(latest_version_obj)

      update_checker = Dependabot::PreCommit::UpdateChecker.new(
        dependency: additional_dep,
        dependency_files: [file],
        credentials: credentials,
        ignored_versions: [],
        security_advisories: [],
        raise_on_ignored: false
      )

      latest = update_checker.latest_version
      expect(latest).to eq("2.31.0.20")

      updated_reqs = update_checker.updated_requirements
      expect(updated_reqs.first[:requirement]).to eq("==2.31.0.20")

      # Step 3: Update the file
      updated_dep = Dependabot::Dependency.new(
        name: additional_dep.name,
        version: latest,
        previous_version: additional_dep.version,
        requirements: updated_reqs,
        previous_requirements: additional_dep.requirements,
        package_manager: "pre_commit"
      )

      file_updater = Dependabot::PreCommit::FileUpdater.new(
        dependencies: [updated_dep],
        dependency_files: [file],
        credentials: credentials
      )

      updated_files = file_updater.updated_dependency_files
      expect(updated_files.first.content).to include("types-requests==2.31.0.20")
    end
  end
end
# rubocop:enable RSpec/DescribeClass
