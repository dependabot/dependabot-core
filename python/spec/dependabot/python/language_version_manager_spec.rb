# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/language_version_manager"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/dependency_file"

RSpec.describe Dependabot::Python::LanguageVersionManager do
  let(:manager) { described_class.new(python_requirement_parser: parser) }
  let(:parser) { Dependabot::Python::FileParser::PythonRequirementParser.new(dependency_files: files) }

  describe "#python_version" do
    subject(:python_version) { manager.python_version }

    context "with pyproject.toml containing requires-python" do
      let(:files) { [pyproject_file] }
      let(:pyproject_file) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: pyproject_content
        )
      end

      context "when requires-python specifies a range" do
        let(:pyproject_content) do
          <<~TOML
            [project]
            name = "test-package"
            requires-python = ">= 3.9, <3.13"
          TOML
        end

        it "selects the lowest compatible Python version" do
          expect(python_version).to eq("3.9.24")
        end
      end

      context "when requires-python specifies minimum only" do
        let(:pyproject_content) do
          <<~TOML
            [project]
            name = "test-package"
            requires-python = ">= 3.10"
          TOML
        end

        it "selects the lowest compatible Python version" do
          expect(python_version).to eq("3.10.19")
        end
      end

      context "when requires-python specifies exact version" do
        let(:pyproject_content) do
          <<~TOML
            [project]
            name = "test-package"
            requires-python = "3.11"
          TOML
        end

        it "selects Python 3.11" do
          expect(python_version).to eq("3.11.14")
        end
      end

      context "with Poetry format python dependency" do
        let(:pyproject_content) do
          <<~TOML
            [tool.poetry.dependencies]
            python = "^3.12"
          TOML
        end

        it "selects the lowest compatible Python version" do
          expect(python_version).to eq("3.12.12")
        end
      end

      context "without Python version specified" do
        let(:pyproject_content) do
          <<~TOML
            [project]
            name = "test-package"
          TOML
        end

        it "defaults to the highest available Python version" do
          expect(python_version).to eq("3.14.0")
        end
      end
    end

    context "with no dependency files" do
      let(:files) { [] }

      it "defaults to the highest available Python version" do
        expect(python_version).to eq("3.14.0")
      end
    end
  end

  describe "#python_requirement_string" do
    subject(:requirement_string) { manager.python_requirement_string }

    context "with pyproject.toml containing requires-python" do
      let(:files) { [pyproject_file] }
      let(:pyproject_file) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: <<~TOML
            [project]
            name = "test-package"
            requires-python = ">= 3.9, <3.13"
          TOML
        )
      end

      it "returns the requirement string" do
        expect(requirement_string).to eq(">= 3.9, <3.13")
      end
    end

    context "without Python version specified" do
      let(:files) { [] }

      it "returns the highest version" do
        expect(requirement_string).to eq("3.14.0")
      end
    end
  end

  describe "#python_major_minor" do
    subject(:major_minor) { manager.python_major_minor }

    context "with requires-python = '>= 3.9, <3.13'" do
      let(:files) do
        [
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: <<~TOML
              [project]
              requires-python = ">= 3.9, <3.13"
            TOML
          )
        ]
      end

      it "returns the major.minor version" do
        expect(major_minor).to eq("3.9")
      end
    end
  end
end
