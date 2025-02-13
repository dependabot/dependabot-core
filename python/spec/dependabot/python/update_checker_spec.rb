# typed: false
# frozen_string_literal: true

require "spec_helper"

require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/python/update_checker"
require "dependabot/requirements_update_strategy"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Python::UpdateChecker do
  let(:dependency) { requirements_dependency }
  let(:dependency_requirements) do
    [{
      file: "requirements.txt",
      requirement: "==2.0.0",
      groups: [],
      source: nil
    }]
  end
  let(:dependency_version) { "2.0.0" }
  let(:dependency_name) { "luigi" }
  let(:requirements_dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip"
    )
  end
  let(:requirements_fixture_name) { "version_specified.txt" }
  let(:requirements_file) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: fixture("requirements", requirements_fixture_name)
    )
  end
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("pyproject_files", pyproject_fixture_name)
    )
  end
  let(:pipfile_fixture_name) { "exact_version" }
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("pipfile_files", pipfile_fixture_name)
    )
  end
  let(:dependency_files) { [requirements_file] }
  let(:requirements_update_strategy) { nil }
  let(:security_advisories) { [] }
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      requirements_update_strategy: requirements_update_strategy
    )
  end
  let(:pypi_response) { fixture("pypi", "pypi_simple_response.html") }
  let(:pypi_url) { "https://pypi.org/simple/luigi/" }

  before do
    stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
  end

  it_behaves_like "an update checker"

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "when the dependency is outdated" do
      it { is_expected.to be_truthy }
    end

    context "when the dependency is up-to-date" do
      let(:dependency_version) { "2.6.0" }
      let(:dependency_requirements) do
        [{
          file: "requirements.txt",
          requirement: "==2.6.0",
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to be_falsey }
    end

    context "when a dependency in a poetry-based Python library and also in an additional requirements file" do
      let(:dependency_files) { [pyproject, requirements_file] }
      let(:pyproject_fixture_name) { "tilde_version.toml" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "1.2.3",
          requirements: [{
            file: "pyproject.toml",
            requirement: "^1.0.0",
            groups: [],
            source: nil
          }, {
            file: "requirements.txt",
            requirement: "==1.2.8",
            groups: [],
            source: nil
          }],
          package_manager: "pip"
        )
      end

      let(:pypi_url) { "https://pypi.org/simple/requests/" }
      let(:pypi_response) do
        fixture("pypi", "pypi_simple_response_requests.html")
      end

      before do
        stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
          .to_return(
            status: 200,
            body: fixture("pypi", "pypi_response_pendulum.json")
          )
      end

      it { is_expected.to be_truthy }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    it "delegates to LatestVersionFinder" do
      expect(described_class::LatestVersionFinder)
        .to receive(:new)
        .with(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: raise_on_ignored,
          security_advisories: security_advisories
        ).and_call_original
      expect(checker.latest_version).to eq(Gem::Version.new("2.6.0"))
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_fix_version) { checker.lowest_security_fix_version }

    it "finds the lowest available non-vulnerable version" do
      expect(lowest_fix_version).to eq(Gem::Version.new("2.0.1"))
    end

    context "with a security vulnerability" do
      let(:dependency_version) { "2.0.0" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "pip",
            vulnerable_versions: ["<= 2.1.0"]
          )
        ]
      end

      it { is_expected.to eq(Gem::Version.new("2.1.1")) }
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    context "with a requirements file only" do
      let(:dependency_files) { [requirements_file] }

      it { is_expected.to eq(Gem::Version.new("2.6.0")) }

      context "when the user is ignoring the latest version" do
        let(:ignored_versions) { [">= 2.0.0.a, < 3.0"] }

        it { is_expected.to eq(Gem::Version.new("1.3.0")) }
      end

      context "when including a .python-version file" do
        let(:dependency_files) { [requirements_file, python_version_file] }
        let(:python_version_file) do
          Dependabot::DependencyFile.new(
            name: ".python-version",
            content: python_version_content
          )
        end
        let(:python_version_content) { "3.11.0\n" }
        let(:pypi_response) do
          fixture("pypi", "pypi_simple_response_django.html")
        end
        let(:pypi_url) { "https://pypi.org/simple/django/" }
        let(:dependency_name) { "django" }
        let(:dependency_version) { "2.2.0" }
        let(:dependency_requirements) do
          [{
            file: "requirements.txt",
            requirement: "==2.2.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to eq(Gem::Version.new("3.2.4")) }

        context "when the version is set to the oldest version of python supported by Dependabot" do
          let(:python_version_content) { "3.9.0\n" }

          it { is_expected.to eq(Gem::Version.new("3.2.4")) }
        end

        context "when the version is set to a python version no longer supported by Dependabot" do
          let(:python_version_content) { "3.8.0\n" }

          it "raises a helpful error" do
            expect { latest_resolvable_version }.to raise_error(Dependabot::ToolVersionNotSupported) do |err|
              expect(err.message).to start_with(
                "Dependabot detected the following Python requirement for your project: '3.8.0'."
              )
            end
          end
        end
      end
    end

    context "with a pip-compile file" do
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
      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: nil,
          groups: [],
          source: nil
        }]
      end

      it "delegates to PipCompileVersionResolver" do
        dummy_resolver =
          instance_double(described_class::PipCompileVersionResolver)
        allow(described_class::PipCompileVersionResolver).to receive(:new)
          .and_return(dummy_resolver)
        expect(dummy_resolver)
          .to receive(:resolvable?)
          .and_return(false)
        expect(dummy_resolver)
          .to receive(:latest_resolvable_version)
          .and_return(Gem::Version.new("2.5.0"))
        expect(checker.latest_resolvable_version)
          .to eq(Gem::Version.new("2.5.0"))
      end

      context "when a requirements.txt that specifies a subdependency" do
        let(:dependency_files) do
          [manifest_file, generated_file, requirements_file]
        end
        let(:manifest_fixture_name) { "requests.in" }
        let(:generated_fixture_name) { "pip_compile_requests.txt" }
        let(:requirements_fixture_name) { "urllib.txt" }
        let(:pypi_url) { "https://pypi.org/simple/urllib3/" }
        let(:pypi_response) do
          fixture("pypi", "pypi_simple_response_urllib3.html")
        end

        let(:dependency_name) { "urllib3" }
        let(:dependency_version) { "1.22" }
        let(:dependency_requirements) do
          [{
            file: "requirements.txt",
            requirement: nil,
            groups: [],
            source: nil
          }]
        end

        let(:dummy_resolver) { instance_double(described_class::PipCompileVersionResolver) }

        before do
          allow(described_class::PipCompileVersionResolver).to receive(:new)
            .and_return(dummy_resolver)
        end

        context "when the latest version is not resolvable" do
          it "delegates to PipCompileVersionResolver" do
            expect(dummy_resolver)
              .to receive(:resolvable?)
              .and_return(false)

            expect(dummy_resolver)
              .to receive(:latest_resolvable_version)
              .with(requirement: ">=1.22,<=1.24.2")
              .and_return(Gem::Version.new("1.24.2"))
            expect(checker.latest_resolvable_version)
              .to eq(Gem::Version.new("1.24.2"))
          end
        end

        context "when the latest version is resolvable" do
          it "returns the latest version" do
            expect(dummy_resolver)
              .to receive(:resolvable?)
              .and_return(true)

            expect(checker.latest_resolvable_version)
              .to eq(Gem::Version.new("1.24.2"))
          end
        end
      end
    end

    context "with a Pipfile" do
      let(:dependency_files) { [pipfile] }
      let(:dependency_requirements) do
        [{
          file: "Pipfile",
          requirement: "==2.18.0",
          groups: [],
          source: nil
        }]
      end

      it "delegates to PipenvVersionResolver" do
        dummy_resolver =
          instance_double(described_class::PipenvVersionResolver)
        allow(described_class::PipenvVersionResolver).to receive(:new)
          .and_return(dummy_resolver)
        expect(dummy_resolver)
          .to receive(:latest_resolvable_version)
          .with(requirement: ">=2.0.0,<=2.6.0")
          .and_return(Gem::Version.new("2.5.0"))
        expect(checker.latest_resolvable_version)
          .to eq(Gem::Version.new("2.5.0"))
      end
    end

    context "with a pyproject.toml" do
      let(:dependency_files) { [pyproject] }
      let(:dependency_requirements) do
        [{
          file: "pyproject.toml",
          requirement: "2.18.0",
          groups: [],
          source: nil
        }]
      end

      let(:dependency_files) { [pyproject] }
      let(:dependency_requirements) do
        [{
          file: "pyproject.toml",
          requirement: "2.18.0",
          groups: [],
          source: nil
        }]
      end

      context "when including poetry dependencies" do
        let(:pyproject_fixture_name) { "poetry_exact_requirement.toml" }

        it "delegates to PoetryVersionResolver" do
          dummy_resolver =
            instance_double(described_class::PoetryVersionResolver)
          allow(described_class::PoetryVersionResolver).to receive(:new)
            .and_return(dummy_resolver)
          expect(dummy_resolver)
            .to receive(:latest_resolvable_version)
            .with(requirement: ">=2.0.0,<=2.6.0")
            .and_return(Gem::Version.new("2.5.0"))
          expect(checker.latest_resolvable_version)
            .to eq(Gem::Version.new("2.5.0"))
        end
      end

      context "when including pep621 dependencies" do
        let(:pyproject_fixture_name) { "pep621_exact_requirement.toml" }

        it "delegates to PipVersionResolver" do
          dummy_resolver =
            instance_double(described_class::PipVersionResolver)
          allow(described_class::PipVersionResolver).to receive(:new)
            .and_return(dummy_resolver)
          expect(dummy_resolver)
            .to receive(:latest_resolvable_version)
            .and_return(Gem::Version.new("2.5.0"))
          expect(checker.latest_resolvable_version)
            .to eq(Gem::Version.new("2.5.0"))
        end
      end
    end
  end

  describe "#preferred_resolvable_version" do
    subject { checker.preferred_resolvable_version }

    it { is_expected.to eq(Gem::Version.new("2.6.0")) }

    context "with an insecure version" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "pip",
            vulnerable_versions: ["<= 2.1.0"]
          )
        ]
      end

      it { is_expected.to eq(Gem::Version.new("2.1.1")) }

      context "with a pip-compile file" do
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
        let(:pypi_url) { "https://pypi.org/simple/attrs/" }
        let(:pypi_response) do
          fixture("pypi", "pypi_simple_response_attrs.html")
        end

        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: dependency_name,
              package_manager: "pip",
              vulnerable_versions: ["< 17.4.0"]
            )
          ]
        end

        it { is_expected.to eq(Gem::Version.new("17.4.0")) }
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { checker.send(:latest_resolvable_version_with_no_unlock) }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "luigi",
        version: version,
        requirements: requirements,
        package_manager: "pip"
      )
    end

    context "when dealing with a requirements.txt dependency" do
      let(:requirements) do
        [{ file: "req.txt", requirement: req_string, groups: [], source: nil }]
      end
      let(:req_string) { ">=2.0.0" }
      let(:version) { nil }

      it "delegates to LatestVersionFinder" do
        expect(described_class::LatestVersionFinder)
          .to receive(:new)
          .with(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          ).and_call_original
        expect(checker.latest_resolvable_version_with_no_unlock)
          .to eq(Gem::Version.new("2.6.0"))
      end
    end

    context "with a Pipfile" do
      let(:dependency_files) { [pipfile, lockfile] }
      let(:version) { "2.18.0" }
      let(:requirements) do
        [{
          file: "Pipfile",
          requirement: "==2.18.0",
          groups: [],
          source: nil
        }]
      end
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "Pipfile.lock",
          content: fixture("pipfile_files", "exact_version.lock")
        )
      end

      it "delegates to PipenvVersionResolver" do
        dummy_resolver =
          instance_double(described_class::PipenvVersionResolver)
        allow(described_class::PipenvVersionResolver).to receive(:new)
          .and_return(dummy_resolver)
        expect(dummy_resolver)
          .to receive(:latest_resolvable_version)
          .with(requirement: "==2.18.0")
          .and_return(Gem::Version.new("2.18.0"))
        expect(checker.latest_resolvable_version_with_no_unlock)
          .to eq(Gem::Version.new("2.18.0"))
      end

      context "with a requirement from a setup.py" do
        let(:requirements) do
          [{
            file: "setup.py",
            requirement: nil,
            groups: ["install_requires"],
            source: nil
          }]
        end

        it "delegates to PipenvVersionResolver" do
          dummy_resolver =
            instance_double(described_class::PipenvVersionResolver)
          allow(described_class::PipenvVersionResolver).to receive(:new)
            .and_return(dummy_resolver)
          expect(dummy_resolver)
            .to receive(:latest_resolvable_version)
            .with(requirement: nil)
            .and_return(Gem::Version.new("2.18.0"))
          expect(checker.latest_resolvable_version_with_no_unlock)
            .to eq(Gem::Version.new("2.18.0"))
        end
      end
    end
  end

  describe "#updated_requirements" do
    subject(:first_updated_requirements) { checker.updated_requirements.first }

    its([:requirement]) { is_expected.to eq("==2.6.0") }

    context "when the requirement was in a constraint file" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "luigi",
          version: "2.0.0",
          requirements: [{
            file: "constraints.txt",
            requirement: "==2.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "pip"
        )
      end

      its([:file]) { is_expected.to eq("constraints.txt") }
    end

    context "when the requirement had a lower precision" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "luigi",
          version: "2.0",
          requirements: [{
            file: "requirements.txt",
            requirement: "==2.0",
            groups: [],
            source: nil
          }],
          package_manager: "pip"
        )
      end

      its([:requirement]) { is_expected.to eq("==2.6.0") }
    end

    context "when there is a pyproject.toml file with poetry dependencies" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "tilde_version.toml" }

      context "when updating a dependency inside" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "requests",
            version: "1.2.3",
            requirements: [{
              file: "pyproject.toml",
              requirement: "~1.0.0",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        let(:pypi_url) { "https://pypi.org/simple/requests/" }
        let(:pypi_response) do
          fixture("pypi", "pypi_simple_response_requests.html")
        end

        context "when dealing with a library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(
                status: 200,
                body: fixture("pypi", "pypi_response_pendulum.json")
              )
          end

          its([:requirement]) { is_expected.to eq(">=1.0,<2.20") }
        end

        context "when dealing with a non-library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(status: 404)
          end

          its([:requirement]) { is_expected.to eq("~2.19.1") }
        end

        context "when dealing with a poetry in non-package mode" do
          let(:pyproject_fixture_name) { "poetry_non_package_mode.toml" }

          its([:requirement]) { is_expected.to eq("~2.19.1") }
        end
      end

      context "when updating a dependency in an additional requirements file" do
        let(:dependency_files) { super().append(requirements_file) }

        let(:dependency) { requirements_dependency }

        it "does not get affected by whether it's a library or not and updates using the :increase strategy" do
          expect(first_updated_requirements[:requirement]).to eq("==2.6.0")
        end
      end
    end

    context "when there is a pyproject.toml file with standard python dependencies" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "standard_python_tilde_version.toml" }

      context "when updating a dependency inside" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "requests",
            version: "1.2.3",
            requirements: [{
              file: "pyproject.toml",
              requirement: "~=1.0.0",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        let(:pypi_url) { "https://pypi.org/simple/requests/" }
        let(:pypi_response) do
          fixture("pypi", "pypi_simple_response_requests.html")
        end

        context "when dealing with a library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(
                status: 200,
                body: fixture("pypi", "pypi_response_pendulum.json")
              )
          end

          its([:requirement]) { is_expected.to eq(">=1.0,<2.20") }
        end

        context "when dealing with a non-library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(status: 404)
          end

          its([:requirement]) { is_expected.to eq("~=2.19.1") }
        end
      end

      context "when updating a dependency in an additional requirements file" do
        let(:dependency_files) { super().append(requirements_file) }

        let(:dependency) { requirements_dependency }

        it "does not get affected by whether it's a library or not and updates using the :increase strategy" do
          expect(first_updated_requirements[:requirement]).to eq("==2.6.0")
        end
      end
    end

    context "when there is a pyproject.toml file with build system require dependencies" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "table_build_system_requires.toml" }

      context "when updating a dependency inside" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "requests",
            version: "1.2.3",
            requirements: [{
              file: "pyproject.toml",
              requirement: "~=1.0.0",
              groups: [],
              source: nil
            }],
            package_manager: "pip"
          )
        end

        let(:pypi_url) { "https://pypi.org/simple/requests/" }
        let(:pypi_response) do
          fixture("pypi", "pypi_simple_response_requests.html")
        end

        context "when dealing with a library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(
                status: 200,
                body: fixture("pypi", "pypi_response_pendulum.json")
              )
          end

          its([:requirement]) { is_expected.to eq(">=1.0,<2.20") }
        end

        context "when dealing with a non-library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(status: 404)
          end

          its([:requirement]) { is_expected.to eq("~=2.19.1") }
        end
      end

      context "when updating a dependency in an additional requirements file" do
        let(:dependency_files) { super().append(requirements_file) }

        let(:dependency) { requirements_dependency }

        it "does not get affected by whether it's a library or not and updates using the :increase strategy" do
          expect(first_updated_requirements[:requirement]).to eq("==2.6.0")
        end
      end
    end

    context "when there were multiple requirements" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "luigi",
          version: "2.0.0",
          requirements: [{
            file: "constraints.txt",
            requirement: "==2.0.0",
            groups: [],
            source: nil
          }, {
            file: "requirements.txt",
            requirement: "==2.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "pip"
        )
      end

      it "updates both requirements" do
        expect(checker.updated_requirements).to contain_exactly({
          file: "constraints.txt",
          requirement: "==2.6.0",
          groups: [],
          source: nil
        }, {
          file: "requirements.txt",
          requirement: "==2.6.0",
          groups: [],
          source: nil
        })
      end
    end
  end

  describe "#requirements_unlocked_or_can_be?" do
    subject { checker.requirements_unlocked_or_can_be? }

    it { is_expected.to be(true) }

    context "with the lockfile-only requirements update strategy set" do
      let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }

      it { is_expected.to be(false) }
    end
  end
end
