# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python"

RSpec.describe Dependabot::Python::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("pip").new(
      file_parser: parser
    )
  end

  let(:pyproject_toml) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("pyproject_files", "poetry_dependency_grapher.toml"),
      directory: "/"
    )
  end

  let(:dependency_files) { [pyproject_toml] }

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("pip").new(
      dependency_files: dependency_files,
      source: nil,
      credentials: [],
      reject_external_code: false
    )
  end

  let(:poetry_tree_output) { fixture("dependency_grapher", "poetry_show_tree_output.txt") }

  describe "#relevant_dependency_file" do
    it "specifies the pyproject.toml as the relevant dependency file" do
      expect(grapher.relevant_dependency_file).to eql(pyproject_toml)
    end
  end

  describe "#resolved_dependencies" do
    context "when poetry.lock is present" do
      let(:poetry_lock_file) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: poetry_lock_content,
          directory: "/"
        )
      end

      let(:dependency_files) { [pyproject_toml, poetry_lock_file] }

      let(:poetry_lock_content) { fixture("dependency_grapher", "poetry_lock_with_relationships.lock") }

      it "prefers lockfile relationships and does not call poetry show --tree" do
        expect(parser).not_to receive(:run_in_parsed_context)

        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.fetch("pkg:pypi/flask@3.1.3").dependencies).to eq(
          [
            "pkg:pypi/blinker@1.9.0",
            "pkg:pypi/click@8.3.1",
            "pkg:pypi/itsdangerous@2.2.0",
            "pkg:pypi/jinja2@3.1.6",
            "pkg:pypi/markupsafe@3.0.3",
            "pkg:pypi/werkzeug@3.1.6"
          ]
        )
      end

      it "parses lockfile relationships for requests" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.fetch("pkg:pypi/requests@2.32.5").dependencies).to eq(
          [
            "pkg:pypi/certifi@2026.2.25",
            "pkg:pypi/charset-normalizer@3.4.4",
            "pkg:pypi/idna@3.11",
            "pkg:pypi/urllib3@2.6.3"
          ]
        )
      end

      it "serializes dependencies with relationship data" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.keys).to include(
          "pkg:pypi/flask@3.1.3",
          "pkg:pypi/requests@2.32.5",
          "pkg:pypi/ruff@0.15.4",
          "pkg:pypi/markupsafe@3.0.3"
        )

        flask = resolved_dependencies.fetch("pkg:pypi/flask@3.1.3")
        expect(flask.direct).to be(true)
        expect(flask.runtime).to be(true)

        markupsafe = resolved_dependencies.fetch("pkg:pypi/markupsafe@3.0.3")
        expect(markupsafe.direct).to be(false)
        expect(markupsafe.dependencies).to eq([])
      end
    end

    context "when poetry.lock is missing but project uses Poetry" do
      before do
        allow(parser).to receive(:run_in_parsed_context)
          .with("pyenv exec poetry show --tree --no-ansi --no-interaction")
          .and_return(poetry_tree_output)
      end

      it "falls back to parsing poetry show --tree output" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(parser).to have_received(:run_in_parsed_context)
          .with("pyenv exec poetry show --tree --no-ansi --no-interaction")
        expect(resolved_dependencies.keys).to include("pkg:pypi/flask")
      end
    end

    context "when this is not a Poetry project" do
      let(:pyproject_toml) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "pep621_exact_requirement.toml"),
          directory: "/"
        )
      end

      it "returns dependencies without relationship data and does not call poetry show --tree" do
        expect(parser).not_to receive(:run_in_parsed_context)

        resolved_dependencies = grapher.resolved_dependencies

        resolved_dependencies.each_value do |dep|
          expect(dep.dependencies).to eq([])
        end
      end
    end

    context "when lockfile graph extraction fails" do
      let(:poetry_lock_file) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: "invalid toml content {{{",
          directory: "/"
        )
      end

      let(:dependency_files) { [pyproject_toml, poetry_lock_file] }

      before do
        allow(parser).to receive(:run_in_parsed_context)
          .with("pyenv exec poetry show --tree --no-ansi --no-interaction")
          .and_return(poetry_tree_output)
      end

      it "falls back to parsing poetry show --tree output" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(parser).to have_received(:run_in_parsed_context)
          .with("pyenv exec poetry show --tree --no-ansi --no-interaction")
        expect(resolved_dependencies.keys).to include("pkg:pypi/flask")
      end
    end
  end
end
