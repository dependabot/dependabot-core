# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/python/pip/pipfile_version_resolver"

namespace = Dependabot::UpdateCheckers::Python::Pip
RSpec.describe namespace::PipfileVersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      unlock_requirement: unlock_requirement,
      latest_allowable_version: latest_version
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
  let(:unlock_requirement) { true }
  let(:dependency_files) { [pipfile, lockfile] }
  let(:latest_version) { Gem::Version.new("2.18.4") }
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("python", "pipfiles", pipfile_fixture_name)
    )
  end
  let(:pipfile_fixture_name) { "exact_version" }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile.lock",
      content: fixture("python", "lockfiles", lockfile_fixture_name)
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
      file: "Pipfile",
      requirement: "==2.18.0",
      groups: ["default"],
      source: nil
    }]
  end

  describe "#latest_resolvable_version" do
    subject { resolver.latest_resolvable_version }

    context "with a lockfile" do
      let(:dependency_files) { [pipfile, lockfile] }
      let(:dependency_version) { "2.18.0" }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }

      context "when not unlocking the requirement" do
        let(:unlock_requirement) { false }
        it { is_expected.to be >= Gem::Version.new("2.18.0") }
      end
    end

    context "without a lockfile (but with a latest version)" do
      let(:dependency_files) { [pipfile] }
      let(:dependency_version) { nil }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
    end

    context "when the latest version isn't allowed" do
      let(:latest_version) { Gem::Version.new("2.18.3") }
      it { is_expected.to eq(Gem::Version.new("2.18.3")) }
    end

    context "when the latest version is nil" do
      let(:latest_version) { nil }
      it { is_expected.to be >= Gem::Version.new("2.19.0") }
    end

    context "with a dependency with a hard name" do
      let(:pipfile_fixture_name) { "hard_names" }
      let(:lockfile_fixture_name) { "hard_names.lock" }
      let(:dependency_name) { "discord-py" }
      let(:dependency_version) { "0.16.1" }
      let(:dependency_requirements) do
        [{
          file: "Pipfile",
          requirement: "==0.16.1",
          groups: ["default"],
          source: nil
        }]
      end

      it { is_expected.to be >= Gem::Version.new("0.16.12") }
    end

    context "when another dependency has been yanked" do
      let(:pipfile_fixture_name) { "yanked" }
      let(:lockfile_fixture_name) { "yanked.lock" }

      it "raises a helpful error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to start_with(
              "CRITICAL:pipenv.patched.notpip._internal.index:"\
              "Could not find a version that satisfies the requirement "\
              "pytest==10.4.0"
            )
          end
      end
    end

    context "with a subdependency" do
      let(:dependency_name) { "py" }
      let(:dependency_version) { "1.5.3" }
      let(:dependency_requirements) { [] }
      let(:latest_version) { Gem::Version.new("1.7.0") }

      it { is_expected.to eq(Gem::Version.new("1.7.0")) }
    end

    context "with a path dependency" do
      let(:dependency_files) { [pipfile, lockfile, setupfile] }
      let(:setupfile) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: fixture("python", "setup_files", setupfile_fixture_name)
        )
      end
      let(:setupfile_fixture_name) { "small.py" }
      let(:pipfile_fixture_name) { "path_dependency" }
      let(:lockfile_fixture_name) { "path_dependency.lock" }
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
            name: "setup.cfg",
            content: fixture("python", "setup_files", "setup.cfg")
          )
        end

        it { is_expected.to eq(Gem::Version.new("2.18.4")) }
      end
    end

    context "with a required python version" do
      let(:pipfile_fixture_name) { "required_python" }
      let(:lockfile_fixture_name) { "required_python.lock" }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }

      context "that is invalid" do
        let(:pipfile_fixture_name) { "required_python_invalid" }

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).to start_with(
                "Pipenv does not support specifying Python ranges"
              )
            end
        end
      end

      context "that is implicit" do
        let(:pipfile_fixture_name) { "required_python_implicit" }
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
        let(:latest_version) { Gem::Version.new("3.8.1") }

        it { is_expected.to eq(Gem::Version.new("3.8.1")) }
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
        let(:latest_version) { Gem::Version.new("6.14.6") }
        it { is_expected.to eq(Gem::Version.new("6.14.6")) }
      end
    end

    context "with an unfetchable requirement" do
      let(:dependency_files) { [pipfile] }
      let(:pipfile_fixture_name) { "bad_requirement" }

      it "raises a helpful error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to eq(
              "packaging.specifiers.InvalidSpecifier: "\
              "Invalid specifier: '3.4.0'"
            )
          end
      end
    end

    context "with extra requirements" do
      let(:dependency_name) { "raven" }
      let(:dependency_version) { "5.27.1" }
      let(:latest_version) { Gem::Version.new("7.0.0") }
      let(:pipfile_fixture_name) { "extra_subdependency" }
      let(:lockfile_fixture_name) { "extra_subdependency.lock" }
      it { is_expected.to be >= Gem::Version.new("6.7.0") }
    end

    context "with an unreachable private source" do
      let(:pipfile_fixture_name) { "private_source" }
      let(:lockfile_fixture_name) { "exact_version.lock" }

      before do
        stub_request(:get, "https://some.internal.registry.com/pypi/").
          to_raise(Excon::Error::Timeout)
      end

      it "raises a helpful error" do
        expect { subject }.
          to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
            expect(error.source).
              to eq("https://some.internal.registry.com/pypi/")
          end
      end

      context "from credentials" do
        let(:pipfile_fixture_name) { "exact_version" }
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "python_index",
            "index-url" => "https://user:pass@pypi.gemfury.com/secret_codes/"
          }]
        end

        before do
          stub_request(:get, "https://pypi.gemfury.com/secret_codes/").
            to_raise(Excon::Error::Timeout)
        end

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
              expect(error.source).
                to eq("https://redacted@pypi.gemfury.com/secret_codes/")
            end
        end
      end
    end

    context "with a git source" do
      context "for another dependency, that can't be reached" do
        let(:pipfile_fixture_name) { "git_source_unreachable" }
        let(:lockfile_fixture_name) { "git_source_unreachable.lock" }

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
              expect(error.dependency_urls).
                to eq(["https://github.com/greysteil/django.git"])
            end
        end
      end

      context "for another dependency, that has a bad ref" do
        let(:pipfile_fixture_name) { "git_source_bad_ref" }
        let(:lockfile_fixture_name) { "git_source_bad_ref.lock" }

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::GitDependencyReferenceNotFound) do |err|
              expect(err.dependency).to eq("django")
            end
        end
      end
    end

    context "with an environment variable source" do
      let(:pipfile_fixture_name) { "environment_variable_source" }
      let(:lockfile_fixture_name) { "environment_variable_source.lock" }

      context "with no credentials" do
        it "raises a helpful error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { subject }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("https://pypi.python.org/${ENV_VAR}/")
            end
        end
      end

      context "with a non-matching credential" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "python_index",
            "index-url" => "https://pypi.gemfury.com/secret_codes/"
          }]
        end
        it "raises a helpful error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { subject }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("https://pypi.python.org/${ENV_VAR}/")
            end
        end
      end

      context "with a matching credential" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "python_index",
            "index-url" => "https://pypi.python.org/simple"
          }]
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
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include(
              "Could not find a version that matches "\
              "chardet<3.1.0,==3.0.0,>=3.0.2\n"
            )
          end
      end
    end
  end
end
