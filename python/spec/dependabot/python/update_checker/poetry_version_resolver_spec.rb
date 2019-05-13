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
      credentials: credentials
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_files) { [pyproject, lockfile] }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("pyproject_files", pyproject_fixture_name)
    )
  end
  let(:pyproject_fixture_name) { "exact_version.toml" }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "pyproject.lock",
      content: fixture("pyproject_locks", lockfile_fixture_name)
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
    subject do
      resolver.latest_resolvable_version(requirement: updated_requirement)
    end
    let(:updated_requirement) { ">= 2.18.0, <= 2.18.4" }

    context "without a lockfile (but with a latest version)" do
      let(:dependency_files) { [pyproject] }
      let(:dependency_version) { nil }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
    end

    context "with a lockfile" do
      let(:dependency_files) { [pyproject, lockfile] }
      let(:dependency_version) { "2.18.0" }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }

      context "when not unlocking the requirement" do
        let(:updated_requirement) { "== 2.18.0" }
        it { is_expected.to eq(Gem::Version.new("2.18.0")) }
      end

      context "when the lockfile is named poetry.lock" do
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "poetry.lock",
            content: fixture("pyproject_locks", lockfile_fixture_name)
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
      let(:updated_requirement) { ">= 2.18.0, <= 2.18.3" }
      it { is_expected.to eq(Gem::Version.new("2.18.3")) }
    end

    context "when the latest version is nil" do
      let(:updated_requirement) { ">= 2.18.0" }
      it { is_expected.to be >= Gem::Version.new("2.19.0") }
    end

    context "with a subdependency" do
      let(:dependency_name) { "idna" }
      let(:dependency_version) { "2.5" }
      let(:dependency_requirements) { [] }
      let(:updated_requirement) { ">= 2.5, <= 2.7" }

      # Resolution blocked by requests
      it { is_expected.to eq(Gem::Version.new("2.5")) }

      context "that can be updated, but not to the latest version" do
        let(:pyproject_fixture_name) { "latest_subdep_blocked.toml" }
        let(:lockfile_fixture_name) { "latest_subdep_blocked.lock" }

        it { is_expected.to eq(Gem::Version.new("2.6")) }
      end

      context "that shouldn't be in the lockfile at all" do
        let(:dependency_name) { "cryptography" }
        let(:dependency_version) { "2.4.2" }
        let(:dependency_requirements) { [] }
        let(:updated_requirement) { ">= 2.4.2, <= 2.5" }
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

      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
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
      let(:updated_requirement) { ">= 3.7.4, <= 3.9.0" }

      it { is_expected.to eq(Gem::Version.new("3.8.2")) }

      context "that has a bad reference" do
        let(:pyproject_fixture_name) { "git_dependency_bad_ref.toml" }
        let(:lockfile_fixture_name) { "git_dependency_bad_ref.lock" }

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::GitDependencyReferenceNotFound) do |err|
              expect(err.dependency).to eq("toml")
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
      let(:updated_requirement) { ">= 2.6.0, <= 2.18.4" }

      # Conflict with chardet is introduced in v2.16.0
      it { is_expected.to eq(Gem::Version.new("2.15.1")) }
    end

    context "resolvable only if git references are preserved" do
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
      let(:updated_requirement) { ">= 1.4.2, <= 1.4.3" }

      it { is_expected.to be >= Gem::Version.new("1.4.3") }
    end

    context "not resolvable" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "solver_problem.toml" }

      it "raises a helpful error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).
              to include("depends on black (^18) which doesn't match any")
          end
      end

      context "because of a yanked dependency" do
        let(:dependency_files) { [pyproject, lockfile] }
        let(:pyproject_fixture_name) { "yanked_version.toml" }
        let(:lockfile_fixture_name) { "yanked_version.lock" }

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).
                to include("Package croniter (0.3.26) not found")
            end
        end
      end
    end
  end

  describe "#resolvable?" do
    subject { resolver.resolvable?(version: version) }
    let(:version) { Gem::Version.new("2.18.4") }

    context "that is resolvable" do
      let(:version) { Gem::Version.new("2.18.4") }
      it { is_expected.to eq(true) }

      context "with a subdependency" do
        let(:dependency_name) { "idna" }
        let(:dependency_version) { "2.5" }
        let(:dependency_requirements) { [] }
        let(:pyproject_fixture_name) { "latest_subdep_blocked.toml" }
        let(:lockfile_fixture_name) { "latest_subdep_blocked.lock" }
        let(:version) { Gem::Version.new("2.6") }

        it { is_expected.to eq(true) }
      end
    end

    context "that is not resolvable" do
      let(:version) { Gem::Version.new("99.18.4") }
      it { is_expected.to eq(false) }

      context "with a subdependency" do
        let(:dependency_name) { "idna" }
        let(:dependency_version) { "2.5" }
        let(:dependency_requirements) { [] }
        let(:pyproject_fixture_name) { "latest_subdep_blocked.toml" }
        let(:lockfile_fixture_name) { "latest_subdep_blocked.lock" }
        let(:version) { Gem::Version.new("2.7") }

        it { is_expected.to eq(false) }
      end

      context "because the original manifest isn't resolvable" do
        let(:dependency_files) { [pyproject] }
        let(:pyproject_fixture_name) { "solver_problem.toml" }

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).
                to include("depends on black (^18) which doesn't match any")
            end
        end
      end
    end
  end
end
