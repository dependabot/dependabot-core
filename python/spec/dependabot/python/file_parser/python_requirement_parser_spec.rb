# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/file_parser/python_requirement_parser"

RSpec.describe Dependabot::Python::FileParser::PythonRequirementParser do
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

      context "when that has a version unknown to pyenv" do
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

    context "with a setup.py file" do
      let(:files) { [setup_py] }
      let(:setup_py) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: setup_py_body
        )
      end
      let(:setup_py_body) { fixture("setup_files", fixture_name) }

      context "when that includes a python_requires line" do
        let(:fixture_name) { "impossible_imports.py" }
        it { is_expected.to eq([">=3.7"]) }
      end

      context "when that doesn't include a python_requires line" do
        let(:fixture_name) { "setup.py" }
        it { is_expected.to eq([]) }
      end

      context "when that has a requirement we can't parse" do
        let(:fixture_name) { "unparseable_python_requires.py" }
        it { is_expected.to eq([]) }
      end
    end
  end
end
