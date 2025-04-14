# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/uv/file_parser/python_requirement_parser"

RSpec.describe Dependabot::Uv::FileParser::PythonRequirementParser do
  let(:parser) { described_class.new(dependency_files: files) }

  describe "#user_specified_requirements" do
    subject(:user_specified_requirements) { parser.user_specified_requirements }

    context "with pip compile files" do
      let(:files) { [in_file, txt_file] }
      let(:in_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.in",
          content: fixture("pip_compile_files", "python_header.in")
        )
      end
      let(:txt_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: fixture("requirements", fixture_name)
        )
      end
      let(:fixture_name) { "python_header.txt" }

      it { is_expected.to eq(["3.8"]) }

      context "with lowercase header" do
        let(:fixture_name) { "python_header_lower.txt" }

        it { is_expected.to eq(["3.8"]) }
      end
    end

    context "with a .python-version file" do
      let(:files) { [python_version_file] }
      let(:python_version_file) do
        Dependabot::DependencyFile.new(
          name: ".python-version",
          content: python_version_body
        )
      end
      let(:python_version_body) { "3.6.2\n" }

      it { is_expected.to eq(["3.6.2"]) }

      context "when having a version unknown to pyenv" do
        let(:python_version_body) { "personal-3.6.2\n" }

        it { is_expected.to eq([]) }
      end

      context "when the file contains comments" do
        let(:python_version_body) { "# this is a comment\n3.6.2" }

        it { is_expected.to eq(["3.6.2"]) }
      end

      context "when the file contains inline comments" do
        let(:python_version_body) { "3.6.2 # this is a comment" }

        it { is_expected.to eq(["3.6.2"]) }
      end
    end

    context "with a pyproject.toml file" do
      context "with a dependency-groups array containing objects and strings" do
        let(:files) { [pyproject_file] }
        let(:pyproject_file) do
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: pyproject_body
          )
        end
        let(:pyproject_body) do
          <<~PYPROJECT
            [project]
            name = "spam-eggs"
            version = "2020.0.0"
            requires-python = ">=3.8"
            [dependency-groups]
            dev = [
                {"include-group" = "docs"},
                {"include-group" = "testing"},
                {"include-group" = "typing"},
                "deptry>=0.15.0",
            ]
          PYPROJECT
        end

        it { is_expected.to eq([">=3.8"]) }
      end
    end
  end
end
