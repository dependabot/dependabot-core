# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/devcontainers/file_parser"
require "dependabot/devcontainers/requirement"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Devcontainers::FileParser do
  let(:dependencies) { parser.parse }
  let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
  let(:files) do
    project_dependency_files(project_name, directory: directory)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "mona/Example",
      directory: directory
    )
  end
  let(:parser) do
    described_class.new(dependency_files: files, source: source, repo_contents_path: repo_contents_path)
  end

  it_behaves_like "a dependency file parser"

  shared_examples_for "parse" do
    it "parses dependencies fine" do
      expect(dependencies.size).to eq(expectations.size)

      expectations.each do |expected|
        version = expected[:version]
        name = expected[:name]
        requirements = expected[:requirements]
        metadata = expected[:metadata]

        dependency = dependencies.find { |dep| dep.name == name }
        expect(dependency).to have_attributes(
          name: name,
          version: version,
          requirements: requirements,
          metadata: metadata
        )
      end
    end
  end

  context "with a .devcontainer.json in repo root" do
    let(:project_name) { "config_in_root" }
    let(:directory) { "/" }

    let(:expectations) do
      [
        {
          name: "ghcr.io/codspace/versioning/foo",
          version: "1.1.0",
          requirements: [
            {
              requirement: "1",
              file: ".devcontainer.json",
              groups: ["feature"],
              source: nil
            }
          ],
          metadata: {}
        },
        {
          name: "ghcr.io/codspace/versioning/bar",
          version: "1.0.0",
          requirements: [
            {
              requirement: "1",
              file: ".devcontainer.json",
              groups: ["feature"],
              source: nil
            }
          ],
          metadata: {}
        }
      ].freeze
    end

    it_behaves_like "parse"
  end

  context "with a devcontainer.json in a .devcontainer folder" do
    let(:project_name) { "config_in_dot_devcontainer_folder" }
    let(:directory) { "/" }

    let(:expectations) do
      [
        {
          name: "ghcr.io/codspace/versioning/foo",
          version: "1.1.0",
          requirements: [
            {
              requirement: "1",
              file: ".devcontainer/devcontainer.json",
              groups: ["feature"],
              source: nil
            }
          ],
          metadata: {}
        },
        {
          name: "ghcr.io/codspace/versioning/bar",
          version: "1.0.0",
          requirements: [
            {
              requirement: "1",
              file: ".devcontainer/devcontainer.json",
              groups: ["feature"],
              source: nil
            }
          ],
          metadata: {}
        },
        {
          name: "ghcr.io/codspace/versioning/baz",
          version: "1.0.0",
          requirements: [
            {
              requirement: "1.0",
              file: ".devcontainer/devcontainer.json",
              groups: ["feature"],
              source: nil
            }
          ],
          metadata: {}
        }
      ].freeze
    end

    it_behaves_like "parse"
  end

  context "with multiple, valid devcontainer.json config files in repo" do
    let(:project_name) { "multiple_configs" }
    let(:directory) { "/" }

    let(:expectations) do
      [
        {
          name: "ghcr.io/codspace/versioning/foo",
          version: "1.1.0",
          requirements: [
            {
              requirement: "1",
              file: ".devcontainer/devcontainer.json",
              groups: ["feature"],
              source: nil
            },
            {
              requirement: "1",
              file: ".devcontainer.json",
              groups: ["feature"],
              source: nil
            }
          ],
          metadata: {}
        },
        {
          name: "ghcr.io/codspace/versioning/bar",
          version: "1.0.0",
          requirements: [
            {
              requirement: "1",
              file: ".devcontainer/devcontainer.json",
              groups: ["feature"],
              source: nil
            },
            {
              requirement: "1",
              file: ".devcontainer.json",
              groups: ["feature"],
              source: nil
            }
          ],
          metadata: {}
        },
        {
          name: "ghcr.io/codspace/versioning/baz",
          version: "1.0.0",
          requirements: [
            {
              requirement: "1.0",
              file: ".devcontainer/devcontainer.json",
              groups: ["feature"],
              source: nil
            }
          ],
          metadata: {}
        }
      ].freeze
    end

    it_behaves_like "parse"
  end

  context "with SHA-pinned features" do
    let(:project_name) { "sha_pinned" }
    let(:directory) { "/" }

    it "ignores them" do
      expect(dependencies).to be_empty
    end
  end

  context "with deprecated features" do
    let(:project_name) { "deprecated" }
    let(:directory) { "/" }

    it "ignores them" do
      expect(dependencies).to be_empty
    end
  end

  describe "#ecosystem" do
    subject(:ecosystem) { parser.ecosystem }

    let(:project_name) { "config_in_root" }
    let(:directory) { "/" }

    it "has the correct name" do
      expect(ecosystem.name).to eq "devcontainers"
    end

    describe "#package_manager" do
      subject(:package_manager) { ecosystem.package_manager }

      it "returns the correct package manager" do
        expect(package_manager.name).to eq "devcontainers"
        expect(package_manager.requirement).to be_nil
        expect(package_manager.version.to_s).to eq "0.72.0"
      end
    end

    describe "#language" do
      subject(:language) { ecosystem.language }

      it "returns the correct language" do
        expect(language.name).to eq "node"
        expect(language.requirement).to be_nil
        expect(language.version.to_s).to eq "18.20.5"
      end
    end
  end
end
