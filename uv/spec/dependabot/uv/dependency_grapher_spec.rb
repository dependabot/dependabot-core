# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/uv"

RSpec.describe Dependabot::Uv::DependencyGrapher do
  subject(:grapher) do
    Dependabot::DependencyGraphers.for_package_manager("uv").new(
      file_parser: parser
    )
  end

  let(:pyproject_toml) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("pyproject_files", "uv_dependency_grapher.toml"),
      directory: "/"
    )
  end

  let(:dependency_files) { [pyproject_toml] }

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("uv").new(
      dependency_files: dependency_files,
      source: nil,
      credentials: [],
      reject_external_code: false
    )
  end

  let(:uv_tree_output) { fixture("dependency_grapher", "uv_tree_output.txt") }

  describe "#relevant_dependency_file" do
    it "specifies the pyproject.toml as the relevant dependency file" do
      expect(grapher.relevant_dependency_file).to eql(pyproject_toml)
    end
  end

  describe "#resolved_dependencies" do
    context "when uv.lock is present" do
      let(:uv_lock_file) do
        Dependabot::DependencyFile.new(
          name: "uv.lock",
          content: uv_lock_content,
          directory: "/"
        )
      end

      let(:dependency_files) { [pyproject_toml, uv_lock_file] }

      let(:uv_lock_content) { fixture("dependency_grapher", "uv_lock_with_relationships.lock") }

      it "prefers lockfile relationships and does not call uv tree" do
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
    end

    context "when uv.lock is missing" do
      let(:generated_uv_lock) { fixture("dependency_grapher", "generated_uv.lock") }

      before do
        allow(parser).to receive(:run_in_parsed_context)
          .with("pyenv exec uv lock --color never --no-progress && cat uv.lock")
          .and_return(generated_uv_lock)
      end

      it "generates an ephemeral lockfile for relationship extraction" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(parser).not_to have_received(:run_in_parsed_context)
          .with("pyenv exec uv tree -q --color never --no-progress --frozen")
        expect(resolved_dependencies.keys).to include("pkg:pypi/flask")
      end
    end

    context "when lockfile graph extraction fails" do
      before do
        allow(parser).to receive(:run_in_parsed_context)
          .with("pyenv exec uv lock --color never --no-progress && cat uv.lock")
          .and_raise(StandardError.new("lock failed"))

        allow(parser).to receive(:run_in_parsed_context)
          .with("pyenv exec uv tree -q --color never --no-progress --frozen")
          .and_return(uv_tree_output)
      end

      it "falls back to parsing uv tree output" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(parser).to have_received(:run_in_parsed_context)
          .with("pyenv exec uv tree -q --color never --no-progress --frozen")
        expect(resolved_dependencies.keys).to include("pkg:pypi/flask")
      end
    end

    context "when serializing lockfile-backed dependencies" do
      let(:uv_lock_file) do
        Dependabot::DependencyFile.new(
          name: "uv.lock",
          content: uv_lock_content,
          directory: "/"
        )
      end

      let(:dependency_files) { [pyproject_toml, uv_lock_file] }

      let(:uv_lock_content) { fixture("dependency_grapher", "uv_lock_with_relationships.lock") }

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
        expect(flask.dependencies).to eq(
          [
            "pkg:pypi/blinker@1.9.0",
            "pkg:pypi/click@8.3.1",
            "pkg:pypi/itsdangerous@2.2.0",
            "pkg:pypi/jinja2@3.1.6",
            "pkg:pypi/markupsafe@3.0.3",
            "pkg:pypi/werkzeug@3.1.6"
          ]
        )

        requests = resolved_dependencies.fetch("pkg:pypi/requests@2.32.5")
        expect(requests.dependencies).to eq(
          [
            "pkg:pypi/certifi@2026.2.25",
            "pkg:pypi/charset-normalizer@3.4.4",
            "pkg:pypi/idna@3.11",
            "pkg:pypi/urllib3@2.6.3"
          ]
        )

        markupsafe = resolved_dependencies.fetch("pkg:pypi/markupsafe@3.0.3")
        expect(markupsafe.direct).to be(false)
        expect(markupsafe.dependencies).to eq([])
      end
    end
  end
end
