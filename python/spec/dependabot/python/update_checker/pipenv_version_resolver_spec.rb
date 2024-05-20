# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/update_checker/pipenv_version_resolver"

RSpec.describe Dependabot::Python::UpdateChecker::PipenvVersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      repo_contents_path: repo_contents_path
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
  let(:dependency_files) { [pipfile, lockfile] }
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("pipfile_files", pipfile_fixture_name)
    )
  end
  let(:pipfile_fixture_name) { "exact_version" }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile.lock",
      content: fixture("pipfile_files", lockfile_fixture_name)
    )
  end
  let(:lockfile_fixture_name) { "exact_version.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip",
      metadata: dependency_metadata
    )
  end
  let(:dependency_name) { "requests" }
  let(:dependency_version) { "2.18.0" }
  let(:dependency_requirements) do
    [{
      file: "Pipfile",
      requirement: "==2.18.0",
      groups: ["default"],
      source: nil
    }]
  end
  let(:dependency_metadata) { {} }
  let(:repo_contents_path) { nil }

  describe "#latest_resolvable_version" do
    subject do
      resolver.latest_resolvable_version(requirement: updated_requirement)
    end
    let(:updated_requirement) { ">=2.18.0,<=2.18.4" }

    context "with a lockfile" do
      let(:dependency_files) { [pipfile, lockfile] }
      let(:dependency_version) { "2.18.0" }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }

      context "when not unlocking the requirement" do
        let(:updated_requirement) { "==2.18.0" }
        it { is_expected.to be >= Gem::Version.new("2.18.0") }
      end
    end

    context "with a star requirement" do
      let(:pipfile_fixture_name) { "star" }
      let(:lockfile_fixture_name) { "star.lock" }
      let(:dependency_name) { "boto3" }
      let(:dependency_version) { "1.28.50" }
      let(:dependency_requirements) do
        [{
          file: "Pipfile",
          requirement: "*",
          groups: ["default"],
          source: nil
        }]
      end
      let(:updated_requirement) { "*" }

      it { is_expected.to be >= Gem::Version.new("1.29.6") }
    end

    context "without a lockfile (but with a latest version)" do
      let(:dependency_files) { [pipfile] }
      let(:dependency_version) { nil }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
    end

    context "when the latest version isn't allowed" do
      let(:updated_requirement) { ">=2.18.0,<=2.18.3" }
      it { is_expected.to eq(Gem::Version.new("2.18.3")) }
    end

    context "when the latest version is nil" do
      let(:updated_requirement) { ">=2.18.0" }
      it { is_expected.to be >= Gem::Version.new("2.19.0") }
    end

    context "with a dependency with a hard name" do
      let(:pipfile_fixture_name) { "hard_names" }
      let(:lockfile_fixture_name) { "hard_names.lock" }
      let(:dependency_name) { "discord-py" }
      let(:dependency_metadata) { { original_name: "discord.py" } }
      let(:dependency_version) { "0.16.1" }
      let(:dependency_requirements) do
        [{
          file: "Pipfile",
          requirement: "==0.16.1",
          groups: ["default"],
          source: nil
        }]
      end
      let(:updated_requirement) { ">=0.16.1,<=1.0.0" }

      it { is_expected.to be >= Gem::Version.new("0.16.12") }
    end

    context "when another dependency has been yanked" do
      let(:pipfile_fixture_name) { "yanked" }
      let(:lockfile_fixture_name) { "yanked.lock" }

      it "assumes the lockfile resolve is valid and upgrades the dependency just fine" do
        expect(subject).to eq(Gem::Version.new("2.18.4"))
      end
    end

    context "with a subdependency" do
      let(:dependency_name) { "py" }
      let(:dependency_version) { "1.5.3" }
      let(:dependency_requirements) { [] }
      let(:updated_requirement) { ">=1.5.3,<=1.7.0" }

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "with a path dependency" do
      let(:dependency_files) { [pipfile, lockfile, setupfile] }
      let(:setupfile) do
        Dependabot::DependencyFile.new(
          name: "mydep/setup.py",
          content: fixture("setup_files", setupfile_fixture_name)
        )
      end
      let(:setupfile_fixture_name) { "small.py" }
      let(:pipfile_fixture_name) { "path_dependency_not_self" }
      let(:lockfile_fixture_name) { "path_dependency_not_self.lock" }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }

      context "that needs to be sanitized" do
        let(:setupfile_fixture_name) { "small_needs_sanitizing.py" }
        it { is_expected.to eq(Gem::Version.new("2.18.4")) }
      end

      context "that imports a setup.cfg" do
        let(:dependency_files) { [pipfile, lockfile, setupfile, setup_cfg] }
        let(:setupfile_fixture_name) { "with_pbr.py" }
        let(:setup_cfg) do
          Dependabot::DependencyFile.new(
            name: "mydep/setup.cfg",
            content: fixture("setup_files", "setup.cfg")
          )
        end

        it { is_expected.to eq(Gem::Version.new("2.18.4")) }
      end
    end

    context "with a required python version" do
      let(:pipfile_fixture_name) { "required_python" }
      let(:lockfile_fixture_name) { "required_python.lock" }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }

      context "that comes from a Poetry file and includes || logic" do
        let(:pipfile_fixture_name) { "exact_version" }
        let(:dependency_files) { [pipfile, pyproject] }
        let(:pyproject) do
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: fixture("pyproject_files", "basic_poetry_dependencies.toml")
          )
        end

        it { is_expected.to eq(Gem::Version.new("2.18.4")) }
      end

      context "that is invalid" do
        let(:pipfile_fixture_name) { "required_python_invalid" }

        it "raises a helpful error" do
          expect { subject }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).to start_with(
                "Pipenv does not support specifying Python ranges"
              )
            end
        end
      end

      context "that is set to a python version no longer supported by Dependabot" do
        let(:pipfile_fixture_name) { "required_python_unsupported" }

        it "raises a helpful error" do
          expect { subject }.to raise_error(Dependabot::ToolVersionNotSupported) do |err|
            expect(err.message).to start_with(
              "Dependabot detected the following Python requirement for your project: '3.4.*'."
            )
          end
        end
      end

      context "that is implicit, and happens on another dependency" do
        let(:pipfile_fixture_name) { "required_python_implicit" }
        let(:lockfile_fixture_name) { "required_python_implicit.lock" }
        let(:dependency_name) { "pytest" }
        let(:dependency_version) { "3.4.0" }
        let(:dependency_requirements) do
          [{
            file: "Pipfile",
            requirement: "==3.4.0",
            groups: ["develop"],
            source: nil
          }]
        end
        let(:updated_requirement) { ">=3.4.0,<=3.8.2" }

        it "assumes the lockfile resolve is valid and upgrades the dependency just fine" do
          expect(subject).to eq(Gem::Version.new("3.8.2"))
        end
      end

      context "for a resolution that has caused trouble in the past" do
        let(:dependency_files) { [pipfile] }
        let(:pipfile_fixture_name) { "problematic_resolution" }
        let(:dependency_name) { "twilio" }
        let(:dependency_version) { nil }
        let(:dependency_requirements) do
          [{
            file: "Pipfile",
            requirement: "*",
            groups: ["default"],
            source: nil
          }]
        end
        let(:updated_requirement) { ">=3.4.0,<=6.14.6" }
        it { is_expected.to eq(Gem::Version.new("6.14.6")) }
      end
    end

    context "with extra requirements" do
      let(:dependency_name) { "raven" }
      let(:dependency_version) { "5.27.1" }
      let(:updated_requirement) { ">=5.27.1,<=7.0.0" }
      let(:pipfile_fixture_name) { "extra_subdependency" }
      let(:lockfile_fixture_name) { "extra_subdependency.lock" }

      it { is_expected.to be >= Gem::Version.new("6.7.0") }
    end

    context "with a git source" do
      context "for another dependency, that can't be reached" do
        let(:pipfile_fixture_name) { "git_source_unreachable" }
        let(:lockfile_fixture_name) { "git_source_unreachable.lock" }

        it "raises a helpful error" do
          expect { subject }
            .to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
              expect(error.dependency_urls)
                .to eq(["https://github.com/user/django.git"])
            end
        end
      end

      context "for another dependency, that has a bad ref" do
        let(:pipfile_fixture_name) { "git_source_bad_ref" }
        let(:lockfile_fixture_name) { "git_source_bad_ref.lock" }

        it "raises a helpful error" do
          expect { subject }
            .to raise_error(Dependabot::GitDependencyReferenceNotFound) do |err|
              expect(err.message).to eq(
                "The branch or reference specified for (unknown package at v15.1.2) could not be retrieved"
              )
            end
        end
      end
    end

    context "with an environment variable source" do
      let(:pipfile_fixture_name) { "environment_variable_source" }
      let(:lockfile_fixture_name) { "environment_variable_source.lock" }

      context "with a matching credential" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }), Dependabot::Credential.new({
            "type" => "python_index",
            "index-url" => "https://pypi.org/simple"
          })]
        end

        it { is_expected.to eq(Gem::Version.new("2.18.4")) }
      end
    end

    context "with a `nil` requirement" do
      let(:dependency_files) { [pipfile] }
      let(:dependency_version) { nil }
      let(:dependency_requirements) do
        [{
          file: "Pipfile",
          requirement: "==2.18.0",
          groups: ["default"],
          source: nil
        }, {
          file: "requirements.txt",
          requirement: nil,
          groups: ["default"],
          source: nil
        }]
      end
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
    end

    context "with a conflict at the latest version" do
      let(:pipfile_fixture_name) { "conflict_at_latest" }
      let(:lockfile_fixture_name) { "conflict_at_latest.lock" }
      let(:dependency_version) { "2.6.0" }
      let(:dependency_requirements) do
        [{
          file: "Pipfile",
          requirement: "==2.6.0",
          groups: ["default"],
          source: nil
        }]
      end

      it { is_expected.to be_nil }
    end

    context "with a conflict at the current version" do
      let(:pipfile_fixture_name) { "conflict_at_current" }
      let(:lockfile_fixture_name) { "conflict_at_current.lock" }
      let(:dependency_version) { "2.18.0" }
      let(:dependency_requirements) do
        [{
          file: "Pipfile",
          requirement: "==2.18.0",
          groups: ["default"],
          source: nil
        }]
      end

      it "raises a helpful error" do
        expect { subject }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to match(
              "Cannot install -r .* because these package versions have conflicting dependencies"
            )
          end
      end
    end

    context "with a missing system library" do
      # NOTE: Attempt to update an unrelated dependency (requests) to cause
      # resolution to fail for rtree which has a system dependency on
      # libspatialindex which isn't installed in dependabot-core's Dockerfile.
      let(:dependency_files) do
        project_dependency_files("pipenv/missing-system-library")
      end

      it "raises a helpful error" do
        expect { subject }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include(
              "ERROR:pip.subprocessor:Getting requirements to build wheel exited with 1"
            )
          end
      end
    end

    context "with a missing system library, and when running python older than 3.12" do
      # NOTE: Attempt to update an unrelated dependency (requests) to cause
      # resolution to fail for rtree which has a system dependency on
      # libspatialindex which isn't installed in dependabot-core's Dockerfile.
      let(:dependency_files) do
        project_dependency_files("pipenv/missing-system-library-old-python")
      end

      it "raises a helpful error" do
        expect { subject }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include(
              "ERROR:pip.subprocessor:python setup.py egg_info exited with 1"
            )
          end
      end
    end

    context "with a python library setup as an editable dependency that needs extra files" do
      let(:project_name) { "pipenv/editable-package" }
      let(:repo_contents_path) { build_tmp_repo(project_name, path: "projects") }
      let(:dependency_name) { "cryptography" }
      let(:dependency_version) { "40.0.1" }
      let(:dependency_requirements) do
        [{
          file: "Pipfile",
          requirement: "==40.0.1",
          groups: ["develop"],
          source: nil
        }]
      end
      let(:updated_requirement) { ">=40.0.1,<=41.0.5" }

      let(:dependency_files) do
        %w(Pipfile Pipfile.lock pyproject.toml).map do |name|
          Dependabot::DependencyFile.new(
            name: name,
            content: fixture("projects", project_name, name)
          )
        end
      end

      it { is_expected.to eq(Gem::Version.new("41.0.5")) }
    end
  end

  describe "#resolvable?" do
    subject { resolver.resolvable?(version: version) }
    let(:version) { Gem::Version.new("2.18.4") }

    context "that is resolvable" do
      let(:version) { Gem::Version.new("2.18.4") }
      it { is_expected.to be(true) }

      context "with a subdependency" do
        let(:dependency_name) { "py" }
        let(:dependency_version) { "1.5.3" }
        let(:dependency_requirements) { [] }
        let(:version) { Gem::Version.new("1.7.0") }

        it { is_expected.to be(true) }
      end
    end

    context "that is not resolvable" do
      let(:version) { Gem::Version.new("99.18.4") }
      it { is_expected.to be(false) }

      context "with a subdependency" do
        let(:dependency_name) { "py" }
        let(:dependency_version) { "1.5.3" }
        let(:dependency_requirements) { [] }

        it { is_expected.to be(false) }
      end

      context "because the original manifest isn't resolvable" do
        let(:pipfile_fixture_name) { "conflict_at_current" }
        let(:lockfile_fixture_name) { "conflict_at_current.lock" }
        let(:version) { Gem::Version.new("99.18.4") }
        let(:dependency_requirements) do
          [{
            file: "Pipfile",
            requirement: "==2.18.0",
            groups: ["default"],
            source: nil
          }]
        end

        it "raises a helpful error" do
          expect { subject }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).to match(
                "Cannot install -r .* because these package versions have conflicting dependencies"
              )
            end
        end
      end
    end
  end
end
