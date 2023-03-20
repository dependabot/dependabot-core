# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Python::UpdateChecker do
  it_behaves_like "an update checker"

  before do
    stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
  end
  let(:pypi_url) { "https://pypi.org/simple/luigi/" }
  let(:pypi_response) { fixture("pypi", "pypi_simple_response.html") }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories
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
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }
  let(:dependency_files) { [requirements_file] }
  let(:pipfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile",
      content: fixture("pipfiles", pipfile_fixture_name)
    )
  end
  let(:pipfile_fixture_name) { "exact_version" }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("pyproject_files", pyproject_fixture_name)
    )
  end
  let(:requirements_file) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: fixture("requirements", requirements_fixture_name)
    )
  end
  let(:requirements_fixture_name) { "version_specified.txt" }
  let(:requirements_dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "luigi" }
  let(:dependency_version) { "2.0.0" }
  let(:dependency_requirements) do
    [{
      file: "requirements.txt",
      requirement: "==2.0.0",
      groups: [],
      source: nil
    }]
  end

  let(:dependency) { requirements_dependency }

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
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

    context "given a dependency in a poetry-based Python library, that's also in an additional requirements file" do
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
        stub_request(:get, "https://pypi.org/pypi/pendulum/json/").
          to_return(
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
      expect(described_class::LatestVersionFinder).
        to receive(:new).
        with(
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
    subject { checker.lowest_security_fix_version }

    it "finds the lowest available non-vulnerable version" do
      is_expected.to eq(Gem::Version.new("2.0.1"))
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
    subject { checker.latest_resolvable_version }

    context "with a requirements file only" do
      let(:dependency_files) { [requirements_file] }
      it { is_expected.to eq(Gem::Version.new("2.6.0")) }

      context "when the user is ignoring the latest version" do
        let(:ignored_versions) { [">= 2.0.0.a, < 3.0"] }
        it { is_expected.to eq(Gem::Version.new("1.3.0")) }
      end

      context "and a .python-version file" do
        let(:dependency_files) { [requirements_file, python_version_file] }
        let(:python_version_file) do
          Dependabot::DependencyFile.new(
            name: ".python-version",
            content: python_version_content
          )
        end
        let(:python_version_content) { "3.7.0\n" }
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

        context "that disallows the latest version" do
          let(:python_version_content) { "3.5.3\n" }
          it { is_expected.to eq(Gem::Version.new("2.2.24")) }
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
        allow(described_class::PipCompileVersionResolver).to receive(:new).
          and_return(dummy_resolver)
        expect(dummy_resolver).
          to receive(:resolvable?).
          and_return(false)
        expect(dummy_resolver).
          to receive(:latest_resolvable_version).
          and_return(Gem::Version.new("2.5.0"))
        expect(checker.latest_resolvable_version).
          to eq(Gem::Version.new("2.5.0"))
      end

      context "and a requirements.txt that specifies a subdependency" do
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
          allow(described_class::PipCompileVersionResolver).to receive(:new).
            and_return(dummy_resolver)
        end

        context "when the latest version is not resolvable" do
          before do
            expect(dummy_resolver).
              to receive(:resolvable?).
              and_return(false)
          end

          it "delegates to PipCompileVersionResolver" do
            expect(dummy_resolver).
              to receive(:latest_resolvable_version).
              with(requirement: ">= 1.22, <= 1.24.2").
              and_return(Gem::Version.new("1.24.2"))
            expect(checker.latest_resolvable_version).
              to eq(Gem::Version.new("1.24.2"))
          end
        end

        context "when the latest version is resolvable" do
          before do
            expect(dummy_resolver).
              to receive(:resolvable?).
              and_return(true)
          end

          it "returns the latest version" do
            expect(checker.latest_resolvable_version).
              to eq(Gem::Version.new("1.24.2"))
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
        allow(described_class::PipenvVersionResolver).to receive(:new).
          and_return(dummy_resolver)
        expect(dummy_resolver).
          to receive(:latest_resolvable_version).
          with(requirement: ">= 2.0.0, <= 2.6.0").
          and_return(Gem::Version.new("2.5.0"))
        expect(checker.latest_resolvable_version).
          to eq(Gem::Version.new("2.5.0"))
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

      context "including poetry dependencies" do
        let(:pyproject_fixture_name) { "poetry_exact_requirement.toml" }

        it "delegates to PoetryVersionResolver" do
          dummy_resolver =
            instance_double(described_class::PoetryVersionResolver)
          allow(described_class::PoetryVersionResolver).to receive(:new).
            and_return(dummy_resolver)
          expect(dummy_resolver).
            to receive(:latest_resolvable_version).
            with(requirement: ">= 2.0.0, <= 2.6.0").
            and_return(Gem::Version.new("2.5.0"))
          expect(checker.latest_resolvable_version).
            to eq(Gem::Version.new("2.5.0"))
        end
      end

      context "including pep621 dependencies" do
        let(:pyproject_fixture_name) { "pep621_exact_requirement.toml" }

        it "delegates to PipVersionResolver" do
          dummy_resolver =
            instance_double(described_class::PipVersionResolver)
          allow(described_class::PipVersionResolver).to receive(:new).
            and_return(dummy_resolver)
          expect(dummy_resolver).
            to receive(:latest_resolvable_version).
            and_return(Gem::Version.new("2.5.0"))
          expect(checker.latest_resolvable_version).
            to eq(Gem::Version.new("2.5.0"))
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

    context "for a requirements.txt dependency" do
      let(:requirements) do
        [{ file: "req.txt", requirement: req_string, groups: [], source: nil }]
      end
      let(:req_string) { ">=2.0.0" }
      let(:version) { nil }

      it "delegates to LatestVersionFinder" do
        expect(described_class::LatestVersionFinder).
          to receive(:new).
          with(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: raise_on_ignored,
            security_advisories: security_advisories
          ).and_call_original
        expect(checker.latest_resolvable_version_with_no_unlock).
          to eq(Gem::Version.new("2.6.0"))
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
          content: fixture("lockfiles", "exact_version.lock")
        )
      end

      it "delegates to PipenvVersionResolver" do
        dummy_resolver =
          instance_double(described_class::PipenvVersionResolver)
        allow(described_class::PipenvVersionResolver).to receive(:new).
          and_return(dummy_resolver)
        expect(dummy_resolver).
          to receive(:latest_resolvable_version).
          with(requirement: "==2.18.0").
          and_return(Gem::Version.new("2.18.0"))
        expect(checker.latest_resolvable_version_with_no_unlock).
          to eq(Gem::Version.new("2.18.0"))
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
          allow(described_class::PipenvVersionResolver).to receive(:new).
            and_return(dummy_resolver)
          expect(dummy_resolver).
            to receive(:latest_resolvable_version).
            with(requirement: nil).
            and_return(Gem::Version.new("2.18.0"))
          expect(checker.latest_resolvable_version_with_no_unlock).
            to eq(Gem::Version.new("2.18.0"))
        end
      end
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }
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

      context "and updating a dependency inside" do
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

        context "for a library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/").
              to_return(
                status: 200,
                body: fixture("pypi", "pypi_response_pendulum.json")
              )
          end

          its([:requirement]) { is_expected.to eq(">=1.0,<2.20") }
        end

        context "for a non-library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/").
              to_return(status: 404)
          end

          its([:requirement]) { is_expected.to eq("~2.19.1") }
        end
      end

      context "and updating a dependency in an additional requirements file" do
        let(:dependency_files) { super().append(requirements_file) }

        let(:dependency) { requirements_dependency }

        it "does not get affected by whether it's a library or not and updates using the :increase strategy" do
          expect(subject[:requirement]).to eq("==2.6.0")
        end
      end
    end

    context "when there is a pyproject.toml file with standard python dependencies" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "standard_python_tilde_version.toml" }

      context "and updating a dependency inside" do
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

        context "for a library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/").
              to_return(
                status: 200,
                body: fixture("pypi", "pypi_response_pendulum.json")
              )
          end

          its([:requirement]) { is_expected.to eq(">=1.0,<2.20") }
        end

        context "for a non-library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/").
              to_return(status: 404)
          end

          its([:requirement]) { is_expected.to eq("~=2.19.1") }
        end
      end

      context "and updating a dependency in an additional requirements file" do
        let(:dependency_files) { super().append(requirements_file) }

        let(:dependency) { requirements_dependency }

        it "does not get affected by whether it's a library or not and updates using the :increase strategy" do
          expect(subject[:requirement]).to eq("==2.6.0")
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
        expect(checker.updated_requirements).to match_array(
          [{
            file: "constraints.txt",
            requirement: "==2.6.0",
            groups: [],
            source: nil
          }, {
            file: "requirements.txt",
            requirement: "==2.6.0",
            groups: [],
            source: nil
          }]
        )
      end
    end
  end
end
