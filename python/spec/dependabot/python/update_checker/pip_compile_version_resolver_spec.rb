# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/update_checker/pip_compile_version_resolver"

namespace = Dependabot::Python::UpdateChecker
RSpec.describe namespace::PipCompileVersionResolver do
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
  let(:dependency_files) { [manifest_file, generated_file] }
  let(:manifest_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.in",
      content: fixture("pip_compile_files", manifest_fixture_name)
    )
  end
  let(:generated_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.txt",
      content: fixture("requirements", generated_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "unpinned.in" }
  let(:generated_fixture_name) { "pip_compile_unpinned.txt" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "attrs" }
  let(:dependency_version) { "17.3.0" }
  let(:dependency_requirements) do
    [{
      file: "requirements/test.in",
      requirement: nil,
      groups: [],
      source: nil
    }]
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) do
      resolver.latest_resolvable_version(requirement: updated_requirement)
    end

    let(:updated_requirement) { ">=17.3.0,<=18.1.0" }

    it { is_expected.to eq(Gem::Version.new("18.1.0")) }

    context "with a mismatch in filename" do
      let(:generated_fixture_name) { "pip_compile_unpinned_renamed.txt" }
      let(:generated_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/test-funky.txt",
          content: fixture("requirements", generated_fixture_name)
        )
      end

      it { is_expected.to eq(Gem::Version.new("18.1.0")) }
    end

    context "with an upper bound" do
      let(:manifest_fixture_name) { "bounded.in" }
      let(:generated_fixture_name) { "pip_compile_bounded.txt" }
      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=17.4.0",
          groups: [],
          source: nil
        }]
      end

      context "when originally unpinned" do
        let(:updated_requirement) { "<=18.1.0" }

        it { is_expected.to eq(Gem::Version.new("18.1.0")) }
      end

      context "when not unlocking requirements" do
        let(:updated_requirement) { "<=17.4.0" }

        it { is_expected.to eq(Gem::Version.new("17.4.0")) }
      end

      context "when the latest version isn't allowed (doesn't exist)" do
        let(:updated_requirement) { "<=18.0.0" }

        it { is_expected.to eq(Gem::Version.new("17.4.0")) }
      end

      context "when the latest version is nil" do
        let(:updated_requirement) { ">=0" }

        it { is_expected.to be >= Gem::Version.new("18.1.0") }
      end

      context "when updating is blocked" do
        let(:dependency_name) { "python-dateutil" }
        let(:dependency_version) { "2.6.1" }
        let(:dependency_requirements) do
          [{
            file: "requirements/shared.in",
            requirement: "==2.6.0",
            groups: [],
            source: nil
          }]
        end
        let(:updated_requirement) { ">=2.6.1,<= 2.7.5" }

        context "when only in an imported file" do
          let(:dependency_files) do
            [shared_file, manifest_file, generated_file]
          end
          let(:shared_file) do
            Dependabot::DependencyFile.new(
              name: "requirements/shared.in",
              content:
                fixture("pip_compile_files", "python_dateutil.in")
            )
          end
          let(:manifest_fixture_name) { "imports_shared.in" }
          let(:generated_fixture_name) { "pip_compile_imports_shared.txt" }

          it { is_expected.to be >= Gem::Version.new("2.6.1") }
        end
      end

      context "with multiple requirement.in files" do
        let(:dependency_files) do
          [manifest_file, second_manifest_file, generated_file, second_generated_file2]
        end

        let(:second_manifest_file) do
          Dependabot::DependencyFile.new(
            name: "requirements/dev.in",
            content:
              fixture("pip_compile_files", manifest_fixture_name2)
          )
        end
        let(:second_generated_file2) do
          Dependabot::DependencyFile.new(
            name: "requirements/dev.txt",
            content: fixture("requirements", generated_fixture_name2)
          )
        end
        let(:manifest_fixture_name2) { manifest_fixture_name }
        let(:generated_fixture_name2) { generated_fixture_name }

        let(:dependency_requirements) do
          [{
            file: "requirements/test.in",
            requirement: "<=17.4.0",
            groups: [],
            source: nil
          }, {
            file: "requirements/dev.in",
            requirement: "<=17.4.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be >= Gem::Version.new("18.1.0") }

        context "when a requirement is not resolvable" do
          let(:manifest_fixture_name2) { "unresolvable.in" }

          it "raises a helpful error" do
            expect { latest_resolvable_version }
              .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
                expect(error.message)
                  .to include("Cannot install -r requirements/dev.in (line 1) and botocore==1.10.84 because these " \
                              "package versions have conflicting dependencies.")
              end
          end
        end
      end
    end

    context "with an unresolvable project" do
      let(:dependency_files) { project_dependency_files("unresolvable") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "jupyter-server",
          version: "0.1.1",
          requirements: dependency_requirements,
          package_manager: "pip"
        )
      end
      let(:dependency_requirements) do
        [{
          file: "requirements.in",
          requirement: nil,
          groups: [],
          source: nil
        }]
      end

      it "raises a helpful error", :slow do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message)
              .to include("Cannot install jupyter-server<=18.1.0 and >=17.3.0 because these package versions have " \
                          "conflicting dependencies.")
          end
      end
    end

    context "with a git source" do
      context "when dealing with a dependency that can't be reached" do
        let(:manifest_fixture_name) { "git_source_unreachable.in" }
        let(:dependency_files) { [manifest_file] }
        let(:dependency_version) { nil }

        it "raises a helpful error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
              expect(error.dependency_urls)
                .to eq(["https://github.com/greysteil/unreachable"])
            end
        end
      end

      context "when dealing with a dependency that has a bad ref" do
        let(:manifest_fixture_name) { "git_source_bad_ref.in" }
        let(:dependency_files) { [manifest_file] }
        let(:dependency_version) { nil }

        it "raises a helpful error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::GitDependencyReferenceNotFound) do |err|
              expect(err.dependency).to eq("pythonfinder")
            end
        end
      end
    end

    context "with a subdependency" do
      let(:dependency_name) { "pbr" }
      let(:dependency_version) { "4.0.2" }
      let(:dependency_requirements) { [] }
      let(:updated_requirement) { ">=4.0.2,<=4.3.0" }

      it { is_expected.to eq(Gem::Version.new("4.3.0")) }

      context "when the requirement is superfluous" do
        let(:dependency_name) { "requests" }
        let(:dependency_version) { "2.18.0" }
        let(:dependency_requirements) { [] }
        let(:updated_requirement) { ">=2.18.0,<=2.18.4" }
        let(:generated_fixture_name) { "pip_compile_unpinned_rogue.txt" }

        it { is_expected.to be_nil }
      end
    end

    context "with a dependency that is 'unsafe' to lock" do
      let(:manifest_fixture_name) { "setuptools.in" }
      let(:generated_fixture_name) { "pip_compile_setuptools.txt" }
      let(:dependency_name) { "setuptools" }
      let(:dependency_version) { "40.4.1" }
      let(:dependency_requirements) { [] }
      let(:updated_requirement) { ">=40.4.1" }

      it { is_expected.to be >= Gem::Version.new("40.6.2") }
    end

    context "with an import of the setup.py", :slow do
      let(:dependency_files) do
        [manifest_file, generated_file, setup_file, pyproject]
      end
      let(:setup_file) do
        Dependabot::DependencyFile.new(
          name: "setup.py",
          content: fixture("setup_files", setup_fixture_name)
        )
      end
      let(:pyproject) do
        Dependabot::DependencyFile.new(
          name: "pyproject.toml",
          content: fixture("pyproject_files", "black_configuration.toml")
        )
      end
      let(:manifest_fixture_name) { "imports_setup.in" }
      let(:generated_fixture_name) { "pip_compile_imports_setup.txt" }
      let(:setup_fixture_name) { "small.py" }
      let(:dependency_name) { "attrs" }
      let(:dependency_version) { nil }
      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: nil,
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to be >= Gem::Version.new("18.1.0") }

      context "when dependency needs sanitizing" do
        let(:setup_fixture_name) { "small_needs_sanitizing.py" }

        it { is_expected.to be >= Gem::Version.new("18.1.0") }
      end
    end

    context "with native dependencies that are not pre-built", :slow do
      let(:manifest_fixture_name) { "native_dependencies.in" }
      let(:generated_fixture_name) { "pip_compile_native_dependencies.txt" }
      let(:dependency_name) { "cryptography" }
      let(:dependency_version) { "2.2.2" }
      let(:updated_requirement) { ">3.0.0,<3.3" }

      it { is_expected.to eq(Gem::Version.new("3.2.1")) }
    end
  end

  describe "#resolvable?" do
    subject(:resolvable) { resolver.resolvable?(version: version) }

    let(:version) { Gem::Version.new("18.1.0") }

    context "when the version is resolvable" do
      let(:version) { Gem::Version.new("18.1.0") }

      it { is_expected.to be(true) }

      context "with a subdependency" do
        let(:dependency_name) { "pbr" }
        let(:dependency_version) { "4.0.2" }
        let(:dependency_requirements) { [] }
        let(:version) { Gem::Version.new("5.1.3") }

        it { is_expected.to be(true) }
      end
    end

    context "when the version is not resolvable" do
      let(:version) { Gem::Version.new("99.18.4") }

      it { is_expected.to be(false) }

      context "with a subdependency" do
        let(:manifest_fixture_name) { "requests.in" }
        let(:generated_fixture_name) { "pip_compile_requests.txt" }
        let(:dependency_name) { "urllib3" }
        let(:dependency_version) { "1.22" }
        let(:dependency_requirements) { [] }
        let(:version) { Gem::Version.new("1.23") }

        it { is_expected.to be(false) }
      end

      context "when the original manifest isn't resolvable" do
        let(:manifest_fixture_name) { "unresolvable.in" }
        let(:dependency_files) { [manifest_file] }
        let(:dependency_name) { "boto3" }
        let(:dependency_version) { nil }
        let(:version) { "1.9.28" }
        let(:dependency_requirements) do
          [{
            file: "requirements/test.in",
            requirement: "==1.9.27",
            groups: [],
            source: nil
          }]
        end

        it "raises a helpful error" do
          expect { resolvable }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message)
                .to include("Cannot install -r requirements/test.in (line 1) and botocore==1.10.84 because these " \
                            "package versions have conflicting dependencies.")
            end
        end
      end
    end

    context "when failing to resolve due to resource limits" do
      context "when dealing with running out of disk space" do
        before do
          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command)
          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command).with("pyenv versions").and_return("3.11.5")
          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command).with(a_string_matching(/pyenv exec pip-compile/), *any_args)
            .and_raise(
              Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "OSError: [Errno 28] No space left on device",
                error_context: {}
              )
            )
        end

        it "raises a helpful error" do
          expect { resolvable }
            .to raise_error(Dependabot::OutOfDisk)
        end
      end

      context "when dealing with running out of memory" do
        before do
          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command)
          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command).with("pyenv versions").and_return("3.11.5")
          allow(Dependabot::SharedHelpers)
            .to receive(:run_shell_command).with(a_string_matching(/pyenv exec pip-compile/), *any_args)
            .and_raise(
              Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "MemoryError",
                error_context: {}
              )
            )
        end

        it "raises a helpful error" do
          expect { resolvable }
            .to raise_error(Dependabot::OutOfMemory)
        end
      end
    end
  end
end
