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

    context "without a lockfile" do
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
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
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
    end

    context "with a required python version" do
      let(:pipfile_fixture_name) { "required_python" }
      let(:lockfile_fixture_name) { "required_python.lock" }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
    end

    context "with an unfetchable requirement" do
      let(:dependency_files) { [pipfile] }
      let(:pipfile_fixture_name) { "bad_requirement" }

      it "raises a helpful error" do
        expect { subject }.
          to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to eq(
              "Could not find a version that matches pytest3.4.0\n"\
              "Tried: (no version found at all)\n"\
              "Was <redacted> reachable?"
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
        stub_request(:get, "https://some.internal.registry.com/pypi/requests/").
          to_raise(Excon::Error::Timeout)
      end

      it "raises a helpful error" do
        expect { subject }.
          to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
            expect(error.source).
              to eq("https://some.internal.registry.com/pypi/")
          end
      end

      context "from credentials" do
        let(:pipfile_fixture_name) { "exact_version" }
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "type" => "python_index",
              "index-url" => "https://user:pass@pypi.gemfury.com/secret_codes/"
            }
          ]
        end

        before do
          stub_request(:get, "https://pypi.gemfury.com/secret_codes/requests/").
            to_raise(Excon::Error::Timeout)
        end

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
              expect(error.source).
                to eq("https://redacted@pypi.gemfury.com/secret_codes/")
            end
        end
      end
    end

    context "with an environment variable source" do
      let(:pipfile_fixture_name) { "environment_variable_source" }
      let(:lockfile_fixture_name) { "environment_variable_source.lock" }

      context "with no credentials" do
        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
              expect(error.source).to eq("https://pypi.python.org/${ENV_VAR}/")
            end
        end
      end

      context "with a non-matching credential" do
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "type" => "python_index",
              "index-url" => "https://pypi.gemfury.com/secret_codes/"
            }
          ]
        end
        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
              expect(error.source).to eq("https://pypi.python.org/${ENV_VAR}/")
            end
        end
      end

      context "with a matching credential" do
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "type" => "python_index",
              "index-url" => "https://pypi.python.org/simple"
            }
          ]
        end

        it { is_expected.to eq(Gem::Version.new("2.18.4")) }
      end
    end

    context "with a `nil` requirement" do
      let(:dependency_files) { [pipfile] }
      let(:dependency_version) { nil }
      let(:dependency_requirements) do
        [
          {
            file: "Pipfile",
            requirement: "==2.18.0",
            groups: ["default"],
            source: nil
          },
          {
            file: "requirements.txt",
            requirement: nil,
            groups: ["default"],
            source: nil
          }
        ]
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
  end
end
