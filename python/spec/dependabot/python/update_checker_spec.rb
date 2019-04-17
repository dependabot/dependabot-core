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
  let(:pypi_url) { "https://pypi.python.org/simple/luigi/" }
  let(:pypi_response) { fixture("pypi_simple_response.html") }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
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
  let(:pyproject_fixture_name) { "exact_version.toml" }
  let(:requirements_file) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: fixture("requirements", requirements_fixture_name)
    )
  end
  let(:requirements_fixture_name) { "version_specified.txt" }
  let(:dependency) do
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
          security_advisories: security_advisories
        ).and_call_original
      expect(checker.latest_version).to eq(Gem::Version.new("2.6.0"))
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    context "without a Pipfile or pip-compile file" do
      let(:dependency_files) { [requirements_file] }
      it { is_expected.to eq(Gem::Version.new("2.6.0")) }

      context "when the user is ignoring the latest version" do
        let(:ignored_versions) { [">= 2.0.0.a, < 3.0"] }
        it { is_expected.to eq(Gem::Version.new("1.3.0")) }
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
        let(:pypi_url) { "https://pypi.python.org/simple/urllib3/" }
        let(:pypi_response) { fixture("pypi_simple_response_urllib3.html") }

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

        it "delegates to PipCompileVersionResolver" do
          dummy_resolver =
            instance_double(described_class::PipCompileVersionResolver)
          allow(described_class::PipCompileVersionResolver).to receive(:new).
            and_return(dummy_resolver)
          expect(dummy_resolver).
            to receive(:latest_resolvable_version).
            with(requirement: ">= 1.22, <= 1.24.2").
            and_return(Gem::Version.new("1.24.2"))
          expect(checker.latest_resolvable_version).
            to eq(Gem::Version.new("1.24.2"))
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
        let(:pypi_url) { "https://pypi.python.org/simple/attrs/" }
        let(:pypi_response) { fixture("pypi_simple_response_attrs.html") }

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
            security_advisories: security_advisories
          ).and_call_original
        expect(checker.latest_resolvable_version_with_no_unlock).
          to eq(Gem::Version.new("2.6.0"))
      end
    end

    context "with a Pipfile" do
      let(:dependency_files) { [pipfile] }
      let(:version) { nil }
      let(:requirements) do
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
          with(requirement: "==2.18.0").
          and_return(Gem::Version.new("2.18.0"))
        expect(checker.latest_resolvable_version_with_no_unlock).
          to eq(Gem::Version.new("2.18.0"))
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

    context "when there is a pyproject.toml file" do
      let(:dependency_files) { [requirements_file, pyproject] }
      let(:pyproject_fixture_name) { "caret_version.toml" }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "1.2.3",
          requirements: [{
            file: "pyproject.toml",
            requirement: "^1.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "pip"
        )
      end

      let(:pypi_url) { "https://pypi.python.org/simple/requests/" }
      let(:pypi_response) { fixture("pypi_simple_response_requests.html") }

      context "for a library" do
        before do
          stub_request(:get, "https://pypi.org/pypi/pendulum/json").
            to_return(
              status: 200,
              body: fixture("pypi_response_pendulum.json")
            )
        end

        its([:requirement]) { is_expected.to eq(">=1,<3") }
      end

      context "for a non-library" do
        before do
          stub_request(:get, "https://pypi.org/pypi/pendulum/json").
            to_return(status: 404)
        end

        its([:requirement]) { is_expected.to eq("^2.19.1") }
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
