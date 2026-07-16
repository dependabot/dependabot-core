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
  let(:requirements_txt) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: "flask==3.1.3\n",
      directory: "/"
    )
  end
  let(:dev_requirements_txt) do
    Dependabot::DependencyFile.new(
      name: "dev-requirements.txt",
      content: "ruff==0.15.4\n",
      directory: "/"
    )
  end
  let(:support_txt) do
    Dependabot::DependencyFile.new(
      name: "README.txt",
      content: "This is a support file\n",
      directory: "/",
      support_file: true
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

    context "when uv.lock exists in a nested path" do
      let(:nested_uv_lock_file) do
        Dependabot::DependencyFile.new(
          name: "projects/manufacturing/ops-assistant/uv.lock",
          content: uv_lock_content,
          directory: "/"
        )
      end
      let(:dependency_files) { [pyproject_toml, nested_uv_lock_file] }

      it "returns the nested uv.lock" do
        expect(grapher.relevant_dependency_file).to eql(nested_uv_lock_file)
      end
    end

    context "when uv.lock is missing" do
      let(:dependency_files) { [pyproject_toml] }

      it "falls back to pyproject.toml" do
        expect(grapher.relevant_dependency_file).to eql(pyproject_toml)
      end
    end

    context "when uv.lock is missing and requirements manifests are present" do
      let(:dependency_files) { [pyproject_toml, requirements_txt, support_txt] }

      it "prefers requirements.txt over pyproject.toml" do
        expect(grapher.relevant_dependency_file).to eql(requirements_txt)
      end
    end

    context "when uv.lock and pyproject.toml are missing" do
      let(:dependency_files) { [dev_requirements_txt, support_txt] }

      it "uses non-support requirements files as fallback" do
        expect(grapher.relevant_dependency_file).to eql(dev_requirements_txt)
      end
    end
  end

  describe "#resolved_dependencies" do
    context "when uv.lock is missing" do
      let(:dependency_files) { [pyproject_toml] }

      it "falls back to parser-based dependency extraction" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies).to include("pkg:pypi/flask")
        expect(resolved_dependencies.fetch("pkg:pypi/flask").dependencies).to eq([])
      end
    end

    context "when uv.lock and pyproject.toml are missing" do
      let(:dependency_files) { [dev_requirements_txt] }

      it "parses requirements-only inputs" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies).to include("pkg:pypi/ruff@0.15.4")
      end
    end

    context "when no supported manifest files are present" do
      let(:dependency_files) { [support_txt] }

      it "raises a DependabotError" do
        expect { grapher.resolved_dependencies }
          .to raise_error(Dependabot::DependabotError, /No supported dependency files present/)
      end
    end

    context "when uv.lock exists in a nested path" do
      let(:nested_uv_lock_file) do
        Dependabot::DependencyFile.new(
          name: "projects/manufacturing/ops-assistant/uv.lock",
          content: uv_lock_content,
          directory: "/"
        )
      end
      let(:dependency_files) { [pyproject_toml, nested_uv_lock_file] }

      it "extracts dependencies from the nested uv.lock" do
        resolved_dependencies = grapher.resolved_dependencies

        expect(resolved_dependencies).to include("pkg:pypi/flask@3.1.3")
      end
    end

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

    it "includes the root project package as an indirect entry (preserving prior behaviour)" do
      # The fixture's root package is `name = "test"` with `source = { virtual = "." }`.
      resolved_dependencies = grapher.resolved_dependencies

      root = resolved_dependencies.fetch("pkg:pypi/test@0.1.0")
      expect(root.direct).to be(false)
      expect(root.runtime).to be(true)
      # Mirrors uv's `create_dependencies` in cyclonedx_json.rs (chains
      # `dependencies` + `optional-dependencies` + `dev-dependencies` into one
      # edge list).
      expect(root.dependencies).to contain_exactly(
        "pkg:pypi/flask@3.1.3",
        "pkg:pypi/requests@2.32.5",
        "pkg:pypi/ruff@0.15.4",
        "pkg:pypi/ty@0.0.19"
      )
    end

    context "when the root has `[package.optional-dependencies]` (extras)" do
      # Mirrors uv's `ExportableRequirements::from_lock` --all-extras behaviour:
      # extras-declared deps are direct-from-root, since `uv sync --all-extras`
      # would install them. The dependency graph reports what *could* be
      # installed, not what's selected for a particular sync.
      let(:uv_lock_content) do
        <<~LOCK
          version = 1
          requires-python = ">=3.12"

          [[package]]
          name = "project"
          version = "0.1.0"
          source = { virtual = "." }
          dependencies = [
              { name = "requests" },
          ]

          [package.optional-dependencies]
          aws = [
              { name = "boto3" },
          ]
          vertex = [
              { name = "google-auth" },
          ]

          [[package]]
          name = "requests"
          version = "2.32.5"
          source = { registry = "https://pypi.org/simple" }

          [[package]]
          name = "boto3"
          version = "1.42.69"
          source = { registry = "https://pypi.org/simple" }

          [[package]]
          name = "google-auth"
          version = "2.49.1"
          source = { registry = "https://pypi.org/simple" }
        LOCK
      end

      it "treats optional-dependencies on the root as direct/runtime" do
        resolved = grapher.resolved_dependencies

        boto3 = resolved.fetch("pkg:pypi/boto3@1.42.69")
        expect(boto3.direct).to be(true)
        expect(boto3.runtime).to be(true)

        google_auth = resolved.fetch("pkg:pypi/google-auth@2.49.1")
        expect(google_auth.direct).to be(true)
        expect(google_auth.runtime).to be(true)
      end
    end

    context "when a transitive package has optional-dependencies or dev-dependencies" do
      # Mirrors uv's `create_dependencies` which chains a package's
      # `dependencies`, `optional-dependencies`, and `dev-dependencies` when
      # building the SBOM dependency graph edges.
      let(:uv_lock_content) do
        <<~LOCK
          version = 1
          requires-python = ">=3.12"

          [[package]]
          name = "project"
          version = "0.1.0"
          source = { virtual = "." }
          dependencies = [
              { name = "django" },
          ]

          [[package]]
          name = "django"
          version = "5.0.0"
          source = { registry = "https://pypi.org/simple" }
          dependencies = [
              { name = "sqlparse" },
          ]

          [package.optional-dependencies]
          argon2 = [
              { name = "argon2-cffi" },
          ]

          [package.dev-dependencies]
          test = [
              { name = "pytest" },
          ]

          [[package]]
          name = "sqlparse"
          version = "0.5.0"
          source = { registry = "https://pypi.org/simple" }

          [[package]]
          name = "argon2-cffi"
          version = "23.1.0"
          source = { registry = "https://pypi.org/simple" }

          [[package]]
          name = "pytest"
          version = "8.0.0"
          source = { registry = "https://pypi.org/simple" }
        LOCK
      end

      it "records optional and dev edges from the transitive package" do
        resolved = grapher.resolved_dependencies

        django = resolved.fetch("pkg:pypi/django@5.0.0")
        expect(django.dependencies).to contain_exactly(
          "pkg:pypi/sqlparse@0.5.0",
          "pkg:pypi/argon2-cffi@23.1.0",
          "pkg:pypi/pytest@8.0.0"
        )
      end
    end

    context "when [manifest] members lists workspace members explicitly" do
      let(:uv_lock_content) do
        <<~LOCK
          version = 1
          requires-python = ">=3.12"

          [manifest]
          members = ["alpha", "beta"]

          [[package]]
          name = "alpha"
          version = "0.1.0"
          source = { editable = "packages/alpha" }
          dependencies = [
              { name = "requests" },
          ]

          [[package]]
          name = "beta"
          version = "0.2.0"
          source = { editable = "packages/beta" }
          dependencies = [
              { name = "requests" },
          ]

          [[package]]
          name = "requests"
          version = "2.32.5"
          source = { registry = "https://pypi.org/simple" }

          [[package]]
          name = "not-a-member"
          version = "0.3.0"
          source = { virtual = "." }
          dependencies = [
              { name = "requests" },
          ]
        LOCK
      end

      it "treats only the declared members as roots (ignoring local-source heuristic)" do
        resolved = grapher.resolved_dependencies

        # `requests` is a direct dep of both alpha and beta — it's direct/runtime.
        expect(resolved.fetch("pkg:pypi/requests@2.32.5").direct).to be(true)
        expect(resolved.fetch("pkg:pypi/requests@2.32.5").runtime).to be(true)

        # `not-a-member` has a virtual source but isn't in `[manifest] members`,
        # so it's treated as an ordinary (indirect) package rather than a root.
        expect(resolved.fetch("pkg:pypi/not-a-member@0.3.0").direct).to be(false)
      end
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
