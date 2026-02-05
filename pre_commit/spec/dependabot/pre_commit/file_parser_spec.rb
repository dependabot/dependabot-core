# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/pre_commit/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::PreCommit::FileParser do
  let(:files) { [pre_commit_config] }
  let(:pre_commit_config) do
    Dependabot::DependencyFile.new(
      name: ".pre-commit-config.yaml",
      content: fixture("pre_commit_configs", "basic.yaml")
    )
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "example/repo",
      directory: "/"
    )
  end
  let(:parser) do
    described_class.new(
      dependency_files: files,
      source: source
    )
  end

  it_behaves_like "a dependency file parser"

  describe "#parse" do
    subject(:dependencies) { parser.parse }

    it "returns the correct number of dependencies" do
      expect(dependencies.length).to eq(2)
    end

    it "parses the first dependency correctly" do
      dep = dependencies.find { |d| d.name.include?("pre-commit-hooks") }
      expect(dep).not_to be_nil
      expect(dep.name).to eq("https://github.com/pre-commit/pre-commit-hooks")
      expect(dep.version).to eq("v4.4.0")
      expect(dep.requirements).to eq(
        [{
          requirement: nil,
          groups: [],
          file: ".pre-commit-config.yaml",
          source: {
            type: "git",
            url: "https://github.com/pre-commit/pre-commit-hooks",
            ref: "v4.4.0",
            branch: nil
          }
        }]
      )
    end

    it "parses the second dependency correctly" do
      dep = dependencies.find { |d| d.name.include?("black") }
      expect(dep).not_to be_nil
      expect(dep.name).to eq("https://github.com/psf/black")
      expect(dep.version).to eq("23.12.1")
    end

    context "with hashes and tags" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_hashes_and_tags.yaml")
        )
      end

      it "returns the correct number of dependencies" do
        expect(dependencies.length).to eq(4)
      end

      it "parses a semver tag correctly" do
        dep = dependencies.find { |d| d.name.include?("pre-commit-hooks") }
        expect(dep.version).to eq("v4.4.0")
        expect(dep.requirements.first[:source][:ref]).to eq("v4.4.0")
      end

      it "parses a numeric version correctly" do
        dep = dependencies.find { |d| d.name.include?("black") }
        expect(dep.version).to eq("23.12.1")
        expect(dep.requirements.first[:source][:ref]).to eq("23.12.1")
      end

      it "parses a full commit SHA correctly" do
        dep = dependencies.find { |d| d.name.include?("flake8") }
        expect(dep.version).to eq("6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e")
        expect(dep.requirements.first[:source][:ref]).to eq("6f6a02c2c85a1b45e39c1aa5e6cc40f7a3d6df5e")
      end

      it "parses a short commit SHA correctly" do
        dep = dependencies.find { |d| d.name.include?("mypy") }
        expect(dep.version).to eq("a1b2c3d")
        expect(dep.requirements.first[:source][:ref]).to eq("a1b2c3d")
      end
    end

    context "with local repos" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_local_repo.yaml")
        )
      end

      it "skips local repos" do
        expect(dependencies.length).to eq(1)
        expect(dependencies.first.name).to eq("https://github.com/pre-commit/pre-commit-hooks")
      end
    end

    context "with invalid YAML" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "invalid.yaml")
        )
      end

      it "raises a DependencyFileNotParseable error" do
        expect { dependencies }
          .to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "with empty config" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "empty.yaml")
        )
      end

      it "returns an empty array" do
        expect(dependencies).to eq([])
      end
    end

    context "with repos missing rev" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "missing_rev.yaml")
        )
      end

      it "skips repos without rev" do
        expect(dependencies).to eq([])
      end
    end

    context "with Python additional_dependencies" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_python_additional_deps.yaml")
        )
      end

      it "returns both repo dependencies and additional_dependencies" do
        # 3 repos + 4 Python additional dependencies
        expect(dependencies.length).to eq(7)
      end

      it "parses repo dependencies correctly" do
        repo_deps = dependencies.select do |d|
          d.requirements.first.dig(:source, :type) == "git"
        end
        expect(repo_deps.length).to eq(3)
      end

      it "parses additional_dependencies correctly" do
        add_deps = dependencies.select do |d|
          d.requirements.first.dig(:source, :type) == "additional_dependency"
        end
        expect(add_deps.length).to eq(4)
      end

      it "parses types-requests dependency correctly" do
        dep = dependencies.find { |d| d.name.include?("types-requests") }
        expect(dep).not_to be_nil
        expect(dep.name).to eq("https://github.com/pre-commit/mirrors-mypy::mypy::types-requests")
        expect(dep.version).to eq("2.28.11.5")

        source = dep.requirements.first[:source]
        expect(source[:type]).to eq("additional_dependency")
        expect(source[:language]).to eq("python")
        expect(source[:package_name]).to eq("types-requests")
        expect(source[:hook_id]).to eq("mypy")
      end

      it "parses dependency with extras correctly" do
        dep = dependencies.find { |d| d.name.include?("click") }
        expect(dep).not_to be_nil
        expect(dep.version).to eq("8.1.3")

        source = dep.requirements.first[:source]
        expect(source[:extras]).to eq("testing")
      end

      it "groups additional_dependencies correctly" do
        dep = dependencies.find { |d| d.name.include?("types-requests") }
        expect(dep.requirements.first[:groups]).to eq(["additional_dependencies"])
      end
    end

    context "with Node.js additional_dependencies (language specified)" do
      let(:pre_commit_config) do
        Dependabot::DependencyFile.new(
          name: ".pre-commit-config.yaml",
          content: fixture("pre_commit_configs", "with_node_additional_deps.yaml")
        )
      end

      it "parses repo dependencies but skips Node.js additional_deps (not yet implemented)" do
        # 2 repos only (Node.js additional deps not yet supported)
        repo_deps = dependencies.select do |d|
          d.requirements.first.dig(:source, :type) == "git"
        end
        expect(repo_deps.length).to eq(2)
      end
    end
  end
end
