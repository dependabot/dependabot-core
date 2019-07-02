# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/file_parser/python_requirement_parser"

RSpec.describe Dependabot::Python::FileParser::PythonRequirementParser do
  let(:parser) { described_class.new(dependency_files: files) }

  describe "#user_specified_requirement" do
    subject(:user_specified_requirement) { parser.user_specified_requirement }

    context "with a .python-version file" do
      let(:files) { [python_version_file] }
      let(:python_version_file) do
        Dependabot::DependencyFile.new(
          name: ".python-version",
          content: python_version_body
        )
      end
      let(:python_version_body) { "3.6.2\n" }

      it { is_expected.to eq("3.6.2") }

      context "that has a version unknown to pyenv" do
        let(:python_version_body) { "personal-3.6.2\n" }
        it { is_expected.to be_nil }
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

      context "that includes a python_requires line" do
        let(:fixture_name) { "impossible_imports.py" }
        it { is_expected.to eq(">=3.7") }
      end

      context "that doesn't include a python_requires line" do
        let(:fixture_name) { "setup.py" }
        it { is_expected.to be_nil }
      end
    end
  end
end
