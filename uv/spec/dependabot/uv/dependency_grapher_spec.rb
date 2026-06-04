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

  let(:uv_lock_content) { fixture("dependency_grapher", "uv_lock_with_relationships.lock") }
  let(:uv_lock_file) do
    Dependabot::DependencyFile.new(
      name: "uv.lock",
      content: uv_lock_content,
      directory: "/"
    )
  end

  # The grapher itself doesn't read pyproject.toml, but FileParser requires
  # a manifest to instantiate so we include one to satisfy that constraint.
  let(:pyproject_toml) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("pyproject_files", "uv_dependency_grapher.toml"),
      directory: "/"
    )
  end

  let(:dependency_files) { [pyproject_toml, uv_lock_file] }

  let(:parser) do
    Dependabot::FileParsers.for_package_manager("uv").new(
      dependency_files: dependency_files,
      source: nil,
      credentials: [],
      reject_external_code: false
    )
  end

  describe "#relevant_dependency_file" do
    it "returns the uv.lock" do
      expect(grapher.relevant_dependency_file).to eql(uv_lock_file)
    end

    context "when uv.lock is missing" do
      let(:dependency_files) { [pyproject_toml] }

      it "raises a DependabotError on prepare!" do
        expect { grapher.resolved_dependencies }
          .to raise_error(Dependabot::DependabotError, /No uv.lock present/)
      end
    end
  end

  describe "#resolved_dependencies" do
    it "extracts relationships from uv.lock without shelling out" do
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

    it "marks runtime direct dependencies (root `dependencies`) as direct + runtime" do
      resolved_dependencies = grapher.resolved_dependencies

      flask = resolved_dependencies.fetch("pkg:pypi/flask@3.1.3")
      expect(flask.direct).to be(true)
      expect(flask.runtime).to be(true)

      requests = resolved_dependencies.fetch("pkg:pypi/requests@2.32.5")
      expect(requests.direct).to be(true)
      expect(requests.runtime).to be(true)
    end

    it "marks dev direct dependencies (`[package.dev-dependencies]`) as direct + non-runtime" do
      resolved_dependencies = grapher.resolved_dependencies

      ruff = resolved_dependencies.fetch("pkg:pypi/ruff@0.15.4")
      expect(ruff.direct).to be(true)
      expect(ruff.runtime).to be(false)

      ty = resolved_dependencies.fetch("pkg:pypi/ty@0.0.19")
      expect(ty.direct).to be(true)
      expect(ty.runtime).to be(false)
    end

    it "marks transitive dependencies as not direct" do
      resolved_dependencies = grapher.resolved_dependencies

      markupsafe = resolved_dependencies.fetch("pkg:pypi/markupsafe@3.0.3")
      expect(markupsafe.direct).to be(false)
      expect(markupsafe.dependencies).to eq([])
    end

    it "excludes the root project package from the graph" do
      # The fixture's root package is `name = "test"` with `source = { virtual = "." }`.
      resolved_dependencies = grapher.resolved_dependencies

      expect(resolved_dependencies.keys).not_to include(a_string_matching(%r{^pkg:pypi/test@}))
    end

    context "when uv.lock is invalid TOML" do
      let(:uv_lock_content) { "not valid toml {{{" }

      it "marks subdependency fetching as errored without raising" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies).to eq({})
        expect(grapher.errored_fetching_subdependencies).to be(true)
        expect(grapher.subdependency_error).to be_a(StandardError)
      end
    end
  end
end
