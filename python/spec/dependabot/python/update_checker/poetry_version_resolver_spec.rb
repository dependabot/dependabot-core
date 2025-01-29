# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/update_checker/poetry_version_resolver"

namespace = Dependabot::Python::UpdateChecker
RSpec.describe namespace::PoetryVersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      repo_contents_path: nil
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:dependency_files) { [pyproject, lockfile] }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: pyproject_content
    )
  end
  let(:pyproject_content) { fixture("pyproject_files", pyproject_fixture_name) }
  let(:pyproject_fixture_name) { "poetry_exact_requirement.toml" }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "poetry.lock",
      content: fixture("poetry_locks", lockfile_fixture_name)
    )
  end
  let(:lockfile_fixture_name) { "exact_version.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "requests" }
  let(:dependency_version) { "2.18.0" }
  let(:dependency_requirements) do
    [{
      file: "pyproject.toml",
      requirement: "2.18.0",
      groups: ["dependencies"],
      source: nil
    }]
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version(requirement: updated_requirement) }

    let(:updated_requirement) { ">=2.18.0,<=2.18.4" }

    context "without a lockfile (but with a latest version)" do
      let(:dependency_files) { [pyproject] }
      let(:dependency_version) { nil }

      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
    end

    context "with a dependency defined under dev-dependencies" do
      let(:pyproject_content) do
        super().gsub("[tool.poetry.dependencies]", "[tool.poetry.dev-dependencies]")
      end

      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
    end

    context "with a dependency defined under a group" do
      let(:pyproject_content) do
        super().gsub("[tool.poetry.dependencies]", "[tool.poetry.group.dev.dependencies]")
      end

      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
    end

    context "with a dependency defined under a non-dev group" do
      let(:pyproject_content) do
        super().gsub("[tool.poetry.dependencies]", "[tool.poetry.group.docs.dependencies]")
      end

      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
    end

    context "with a lockfile" do
      let(:dependency_files) { [pyproject, lockfile] }
      let(:dependency_version) { "2.18.0" }

      it { is_expected.to eq(Gem::Version.new("2.18.4")) }

      context "when not unlocking the requirement" do
        let(:updated_requirement) { "==2.18.0" }

        it { is_expected.to eq(Gem::Version.new("2.18.0")) }
      end

      context "when the lockfile is named poetry.lock" do
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "poetry.lock",
            content: fixture("poetry_locks", lockfile_fixture_name)
          )
        end

        it { is_expected.to eq(Gem::Version.new("2.18.4")) }

        context "when the pyproject.toml needs to be sanitized" do
          let(:pyproject_fixture_name) { "needs_sanitization.toml" }

          it { is_expected.to eq(Gem::Version.new("2.18.4")) }
        end
      end
    end

    context "when the latest version isn't allowed" do
      let(:updated_requirement) { ">=2.18.0,<=2.18.3" }

      it { is_expected.to eq(Gem::Version.new("2.18.3")) }
    end

    context "when the latest version is nil" do
      let(:updated_requirement) { ">=2.18.0" }

      it { is_expected.to be >= Gem::Version.new("2.19.0") }
    end

    context "with a subdependency" do
      let(:dependency_name) { "idna" }
      let(:dependency_version) { "2.5" }
      let(:dependency_requirements) { [] }
      let(:updated_requirement) { ">=2.5,<=2.7" }

      # Resolution blocked by requests
      it { is_expected.to eq(Gem::Version.new("2.5")) }

      context "when dependency can be updated, but not to the latest version" do
        let(:pyproject_fixture_name) { "latest_subdep_blocked.toml" }
        let(:lockfile_fixture_name) { "latest_subdep_blocked.lock" }

        it { is_expected.to eq(Gem::Version.new("2.6")) }
      end

      context "when dependency shouldn't be in the lockfile at all" do
        let(:dependency_name) { "cryptography" }
        let(:dependency_version) { "2.4.2" }
        let(:dependency_requirements) { [] }
        let(:updated_requirement) { ">=2.4.2,<=2.5" }
        let(:lockfile_fixture_name) { "extra_dependency.lock" }

        # Ideally we would ignore sub-dependencies that shouldn't be in the
        # lockfile, but determining that is hard. It's fine for us to update
        # them instead - they'll be removed in another (unrelated) PR
        it { is_expected.to eq(Gem::Version.new("2.5")) }
      end
    end

    context "with a legacy Python" do
      let(:pyproject_fixture_name) { "python_2.toml" }
      let(:lockfile_fixture_name) { "python_2.lock" }

      it "raises an error" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::ToolVersionNotSupported)
      end
    end

    context "with a minimum python set that satisfies the running python" do
      let(:pyproject_fixture_name) { "python_lower_bound.toml" }
      let(:lockfile_fixture_name) { "python_lower_bound.toml" }

      let(:pyproject_nested) do
        Dependabot::DependencyFile.new(
          name: "a-dependency/pyproject.toml",
          content: fixture("pyproject_files", "python_lower_bound_nested.toml")
        )
      end

      let(:dependency_name) { "black" }
      let(:dependency_version) { "22.6.0" }
      let(:updated_requirement) { "==23.7.0" }

      let(:dependency_files) { [pyproject, lockfile, pyproject_nested] }

      it { is_expected.to eq(Gem::Version.new("23.7.0")) }
    end

    context "with a dependency file that includes a git dependency" do
      let(:pyproject_fixture_name) { "git_dependency.toml" }
      let(:lockfile_fixture_name) { "git_dependency.lock" }
      let(:dependency_name) { "pytest" }
      let(:dependency_version) { "3.7.4" }
      let(:dependency_requirements) do
        [{
          file: "pyproject.toml",
          requirement: "*",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:updated_requirement) { ">=3.7.4,<=3.9.0" }

      it { is_expected.to eq(Gem::Version.new("3.8.2")) }

      context "when repo has no lockfile" do
        let(:dependency_files) { [pyproject] }

        context "when dependency has a bad reference, and there is no lockfile" do
          let(:pyproject_fixture_name) { "git_dependency_bad_ref.toml" }

          it "raises a helpful error" do
            expect { latest_resolvable_version }
              .to raise_error(Dependabot::GitDependencyReferenceNotFound) do |err|
                expect(err.dependency).to eq("toml")
              end
          end
        end

        context "when dependency is unreachable" do
          let(:pyproject_fixture_name) { "git_dependency_unreachable.toml" }

          it "raises a helpful error" do
            expect { latest_resolvable_version }
              .to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
                expect(error.dependency_urls)
                  .to eq(["https://github.com/greysteil/unreachable.git"])
              end
          end
        end
      end
    end

    context "with a conflict at the latest version" do
      let(:pyproject_fixture_name) { "conflict_at_latest.toml" }
      let(:lockfile_fixture_name) { "conflict_at_latest.lock" }
      let(:dependency_version) { "2.6.0" }
      let(:dependency_requirements) do
        [{
          file: "pyproject.toml",
          requirement: "2.6.0",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:updated_requirement) { ">=2.6.0,<=2.18.4" }

      # Conflict with chardet is introduced in v2.16.0
      it { is_expected.to eq(Gem::Version.new("2.15.1")) }
    end

    context "when version is resolvable only if git references are preserved", :slow do
      let(:pyproject_fixture_name) { "git_conflict.toml" }
      let(:lockfile_fixture_name) { "git_conflict.lock" }
      let(:dependency_name) { "django-widget-tweaks" }
      let(:dependency_version) { "1.4.2" }
      let(:dependency_requirements) do
        [{
          file: "pyproject.toml",
          requirement: "^1.4",
          groups: ["dependencies"],
          source: nil
        }]
      end
      let(:updated_requirement) { ">=1.4.2,<=1.4.3" }

      it { is_expected.to be >= Gem::Version.new("1.4.3") }
    end

    context "when version is not resolvable" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "solver_problem.toml" }

      it "raises a helpful error" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message)
              .to include("depends on black (^18), version solving failed")
          end
      end

      context "when dealing with a yanked dependency" do
        let(:pyproject_fixture_name) { "yanked_version.toml" }
        let(:lockfile_fixture_name) { "yanked_version.lock" }

        context "with a lockfile" do
          let(:dependency_files) { [pyproject, lockfile] }

          it "raises a helpful error" do
            expect { latest_resolvable_version }
              .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
                expect(error.message)
                  .to include("Package croniter (0.3.26) not found")
              end
          end
        end

        context "without a lockfile" do
          let(:dependency_files) { [pyproject] }

          it "raises a helpful error" do
            expect { latest_resolvable_version }
              .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
                expect(error.message)
                  .to include("depends on croniter (0.3.26) which doesn't match any versions")
              end
          end
        end
      end
    end
  end

  describe "#resolvable?" do
    subject(:resolvable) { resolver.resolvable?(version: version) }

    let(:version) { Gem::Version.new("2.18.4") }

    context "when version is resolvable" do
      let(:version) { Gem::Version.new("2.18.4") }

      it { is_expected.to be(true) }

      context "with a subdependency" do
        let(:dependency_name) { "idna" }
        let(:dependency_version) { "2.5" }
        let(:dependency_requirements) { [] }
        let(:pyproject_fixture_name) { "latest_subdep_blocked.toml" }
        let(:lockfile_fixture_name) { "latest_subdep_blocked.lock" }
        let(:version) { Gem::Version.new("2.6") }

        it { is_expected.to be(true) }
      end
    end

    context "when version is not resolvable" do
      let(:version) { Gem::Version.new("99.18.4") }

      it { is_expected.to be(false) }

      context "with a subdependency" do
        let(:dependency_name) { "idna" }
        let(:dependency_version) { "2.5" }
        let(:dependency_requirements) { [] }
        let(:pyproject_fixture_name) { "latest_subdep_blocked.toml" }
        let(:lockfile_fixture_name) { "latest_subdep_blocked.lock" }
        let(:version) { Gem::Version.new("2.7") }

        it { is_expected.to be(false) }
      end

      context "when the original manifest isn't resolvable" do
        let(:dependency_files) { [pyproject] }
        let(:pyproject_fixture_name) { "solver_problem.toml" }

        it "raises a helpful error" do
          expect { resolvable }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message)
                .to include("depends on black (^18), version solving failed")
            end
        end
      end
    end
  end

  describe "handles SharedHelpers::HelperSubprocessFailed errors raised by version resolver" do
    subject(:poetry_error_handler) { error_handler.handle_poetry_error(exception) }

    let(:error_handler) do
      Dependabot::Python::PoetryErrorHandler.new(
        dependencies: dependency,
        dependency_files: dependency_files
      )
    end
    let(:exception) { Exception.new(response) }

    context "with incompatible constraints mentioned in requirements" do
      let(:response) { "Incompatible constraints in requirements of histolab (0.7.0):" }

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include("Incompatible constraints in requirements of histolab (0.7.0):")
        end
      end
    end

    context "with invalid configuration in pyproject.toml file" do
      let(:response) do
        "The Poetry configuration is invalid:
      - data.group.dev.dependencies.h5 must be valid exactly by one definition (0 matches found)"
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include("The Poetry configuration is invalid")
        end
      end
    end

    context "with invalid version for dependency mentioned in pyproject.toml file" do
      let(:response) do
        "Resolving dependencies...
        Could not parse version constraint: <0.2.0app"
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include("Could not parse version constraint: <0.2.0app")
        end
      end
    end

    context "with invalid dependency source link in pyproject.toml file" do
      let(:response) do
        "Updating dependencies
        Resolving dependencies...
        No valid distribution links found for package: \"llama-cpp-python\" version: \"0.2.82\""
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include("No valid distribution links found for package: \"llama-cpp-python\" version: \"0.2.82\"")
        end
      end
    end

    context "with private registry authentication error code 401 file" do
      let(:response) do
        "Creating virtualenv non-package-mode-r7N_A6Jx-py3.11 in /home/dependabot/.cache/pypoetry/virtualenvs
        Updating dependencies
        Resolving dependencies...
        Source (factorypal): Failed to retrieve metadata at https://fp-pypi.sm00p.com/simple/
        401 Client Error: Unauthorized for url: https://fp-pypi.sm00p.com/simple/"
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.message)
            .to include("https://fp-pypi.sm00p.com")
        end
      end
    end

    context "with private registry authentication 403 Client Error" do
      let(:response) do
        "Creating virtualenv reimbursement-coverage-api-fKdRenE--py3.12 in /home/dependabot/.cache/pypoetry/virtualenvs
        Updating dependencies
        Resolving dependencies...
        403 Client Error:  for url: https://fp-pypi.sm00p.com/simple/"
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.message)
            .to include("https://fp-pypi.sm00p.com")
        end
      end
    end

    context "with private registry authentication 404 Client Error" do
      let(:response) do
        "NetworkConnectionError('404 Client Error: Not Found for url: https://raw.example.com/example/flow/" \
          "constraints-$%7BAIRFLOW_VERSION%7D/constraints-3.10.txt'"
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.message)
            .to include("https://raw.example.com")
        end
      end
    end

    context "with private registry authentication 504 Server Error" do
      let(:response) do
        "Creating virtualenv alk-service-import-product-TbrdR40A-py3.8 in /home/dependabot/.cache/pypoetry/virtualenvs
        Updating dependencies
        Resolving dependencies...

        504 Server Error:  for url: https://pypi.com:8443/packages/alk_ci-1.whl#sha256=f9"
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::InconsistentRegistryResponse) do |error|
          expect(error.message)
            .to include("https://pypi.com")
        end
      end
    end

    context "with private index authentication HTTP error 404" do
      let(:response) do
        "HTTP error 404 while getting " \
          "https://<redacted>.com/compute-cloud/8e1a9.zip" \
          "Not Found for URL" \
          " https://example.com/compute-cloud/[FILTERED_REPO]/archive/a5bf58e7a37be7503e1a79febf8b555b9d28e1a9.zip"
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
          expect(error.message)
            .to include("https://example.com")
        end
      end
    end

    context "with dependency spec version not found in package index" do
      let(:response) do
        "Creating virtualenv pyiceberg-xBYdM_d2-py3.12 in /home/dependabot/.cache/pypoetry/virtualenvs
        Updating dependencies
        Resolving dependencies...
        Package docutils (0.21.post1) not found."
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include("Package docutils (0.21.post1) not found.")
        end
      end
    end

    context "with package 'python' specification is incompatible with dependency" do
      let(:response) do
        "Resolving dependencies...
        The current project's supported Python range (>=3.8,<4.0) is not compatible with some of the required " \
        " packages Python requirement: - scipy requires Python <3.13,>=3.9, so it will not be satisfied for" \
        " Python >=3.8,<3.9 || >=3.13,<4.0"
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
          expect(error.message)
            .to include("scipy requires Python <3.13,>=3.9, so it will not be satisfied for")
        end
      end
    end

    context "with a misconfigured pyproject.toml file" do
      let(:response) do
        "Creating virtualenv analysis-nlUUV3qa-py3.13 in pypoetry/virtualenvs
        Updating dependencies
        Resolving dependencies...
        list index out of range"
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a project is listed a dependency" do
      let(:response) do
        "Creating virtualenv kiota-serialization-multipart-GzD6BRdm-py3.13 in " \
          "/home/dependabot/.cache/pypoetry/virtualenvs" \
          "Updating dependencies" \
          "Resolving dependencies..." \
          "Path tmp/20250109-1637-dc4aky/json for kiota-serialization-json does not exist"
      end

      it "raises a helpful error" do
        expect { poetry_error_handler }.to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end
  end
end
