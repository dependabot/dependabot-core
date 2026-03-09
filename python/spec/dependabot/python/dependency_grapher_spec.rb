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

  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("pyproject_files", "pipenv_dependency_grapher.toml"),
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

  describe "#relevant_dependency_file" do
    context "when poetry.lock is not present" do
      it "falls back to pyproject.toml" do
        expect(grapher.relevant_dependency_file).to eql(pyproject_toml)
      end
    end

    context "when poetry.lock is present" do
      let(:poetry_lock_file) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: fixture("dependency_grapher", "poetry_lock_with_relationships.lock"),
          directory: "/"
        )
      end

      let(:dependency_files) { [pyproject_toml, poetry_lock_file] }

      it "specifies the poetry.lock as the relevant dependency file" do
        expect(grapher.relevant_dependency_file).to eql(poetry_lock_file)
      end
    end

    context "when Pipfile is present without Pipfile.lock" do
      let(:dependency_files) { [pipfile] }

      it "falls back to Pipfile" do
        expect(grapher.relevant_dependency_file).to eql(pipfile)
      end
    end

    context "when Pipfile and Pipfile.lock are present" do
      let(:pipfile_lock_file) do
        Dependabot::DependencyFile.new(
          name: "Pipfile.lock",
          content: fixture("dependency_grapher", "pipfile_lock_with_dependencies.json"),
          directory: "/"
        )
      end

      let(:dependency_files) { [pipfile, pipfile_lock_file] }

      it "specifies the Pipfile.lock as the relevant dependency file" do
        expect(grapher.relevant_dependency_file).to eql(pipfile_lock_file)
      end
    end
  end

  describe "#resolved_dependencies" do
    context "when poetry.lock is present" do
      let(:poetry_lock_file) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: fixture("dependency_grapher", "poetry_lock_with_relationships.lock"),
          directory: "/"
        )
      end

      let(:dependency_files) { [pyproject_toml, poetry_lock_file] }

      it "extracts dependency relationships from the lockfile" do
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

    context "when poetry.lock is not present" do
      it "returns dependencies without relationship data" do
        resolved_dependencies = grapher.resolved_dependencies

        resolved_dependencies.each_value do |dep|
          expect(dep.dependencies).to eq([])
        end
      end
    end

    context "when poetry.lock is corrupt" do
      let(:poetry_lock_file) do
        Dependabot::DependencyFile.new(
          name: "poetry.lock",
          content: "invalid toml content {{{",
          directory: "/"
        )
      end

      let(:dependency_files) { [pyproject_toml, poetry_lock_file] }

      it "raises a DependencyFileNotParseable error" do
        expect { grapher.resolved_dependencies }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end

    context "when Pipfile and Pipfile.lock are present" do
      let(:pipfile_lock_file) do
        Dependabot::DependencyFile.new(
          name: "Pipfile.lock",
          content: fixture("dependency_grapher", "pipfile_lock_with_dependencies.json"),
          directory: "/"
        )
      end

      let(:dependency_files) { [pipfile, pipfile_lock_file] }

      it "returns dependencies without relationship data" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.keys).to include(
          "pkg:pypi/requests@2.32.5",
          "pkg:pypi/certifi@2024.2.2",
          "pkg:pypi/ruff@0.15.4"
        )

        resolved_dependencies.each_value do |dep|
          expect(dep.dependencies).to eq([])
        end
      end
    end

    context "when Pipfile is present without Pipfile.lock" do
      let(:dependency_files) { [pipfile] }

      it "returns dependencies without relationship data" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies.keys).to include(
          "pkg:pypi/requests@2.32.5",
          "pkg:pypi/certifi@2024.2.2",
          "pkg:pypi/ruff@0.15.4"
        )

        resolved_dependencies.each_value do |dep|
          expect(dep.dependencies).to eq([])
        end
      end
    end

    context "when Pipfile.lock is corrupt" do
      let(:pipfile_lock_file) do
        Dependabot::DependencyFile.new(
          name: "Pipfile.lock",
          content: "{ invalid json content",
          directory: "/"
        )
      end

      let(:dependency_files) { [pipfile, pipfile_lock_file] }

      it "raises a DependencyFileNotParseable error" do
        expect { grapher.resolved_dependencies }.to raise_error(Dependabot::DependencyFileNotParseable)
      end
    end
  end
end
