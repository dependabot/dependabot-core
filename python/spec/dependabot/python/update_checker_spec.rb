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
  let(:cooldown_options) { nil }
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      update_cooldown: cooldown_options,
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
          cooldown_options: cooldown_options,
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

    context "with a Poetry project" do
      let(:dependency_files) { [pyproject] }
      let(:pyproject_fixture_name) { "poetry_exact_requirement.toml" }
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
      let(:pypi_url) { "https://pypi.org/simple/requests/" }
      let(:pypi_response) { fixture("pypi", "pypi_simple_response_requests.html") }

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "pip",
            vulnerable_versions: ["<= 2.19.0"]
          )
        ]
      end

      it "finds the lowest non-vulnerable version from the registry" do
        expect(lowest_fix_version).to eq(Gem::Version.new("2.19.1"))
      end
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

      context "when including pep735 dependencies" do
        let(:pyproject_fixture_name) { "pep735_exact_requirement.toml" }

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

      context "when including hybrid Poetry + PEP621 dependencies without lockfile" do
        let(:pyproject_fixture_name) { "pep621_with_poetry.toml" }
        let(:dependency_files) { [pyproject] }

        it "delegates to PipVersionResolver for PEP 621 dependencies" do
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

      context "when including hybrid Poetry + PEP621 dependencies with lockfile" do
        let(:pyproject_fixture_name) { "poetry_exact_requirement.toml" }
        let(:poetry_lock) do
          Dependabot::DependencyFile.new(
            name: "poetry.lock",
            content: fixture("poetry_locks", "exact_version.lock")
          )
        end
        let(:dependency_files) { [pyproject, poetry_lock] }

        it "delegates to PoetryVersionResolver when lockfile exists" do
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

      context "when urllib3 is pinned via constraints and botocore is incompatible" do
        let(:dependency_name) { "urllib3" }
        let(:constraints_pyproject) do
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: <<~TOML
              [project]
              name = "dependabot-test"
              version = "0.1.0"

              dependencies = [
                  "requests==2.31.0",
              ]

              [tool.pip]
              constraints = "constraints.txt"
            TOML
          )
        end
        let(:dependency_version) { "1.26.0" }
        let(:pypi_url) { "https://pypi.org/simple/urllib3/" }
        let(:pypi_response) do
          <<~HTML
            <!DOCTYPE html>
            <html>
              <body>
                <a href="https://files.pythonhosted.org/packages/source/u/urllib3/urllib3-1.26.0.tar.gz">urllib3-1.26.0.tar.gz</a>
                <a href="https://files.pythonhosted.org/packages/source/u/urllib3/urllib3-2.6.3.tar.gz">urllib3-2.6.3.tar.gz</a>
              </body>
            </html>
          HTML
        end
        let(:pyproject) do
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: <<~TOML
              [project]
              name = "dependabot-test"
              version = "0.1.0"

              dependencies = [
                  "requests==2.31.0",
                  "botocore==1.29.0",
              ]

              [tool.pip]
              constraints = "constraints.txt"
            TOML
          )
        end
        let(:constraints_file) do
          Dependabot::DependencyFile.new(
            name: "constraints.txt",
            content: "urllib3==1.26.0\n"
          )
        end
        let(:dependency_files) { [pyproject, constraints_file] }
        let(:botocore_requires_dist) do
          [
            "urllib3 (<1.27,>=1.25.4)",
            "jmespath (<2.0.0,>=0.7.1)"
          ]
        end
        let(:dependency_requirements) do
          [{
            file: "constraints.txt",
            requirement: "==1.26.0",
            groups: [],
            source: nil
          }]
        end

        before do
          stub_request(:get, "https://pypi.org/pypi/botocore/1.29.0/json/")
            .to_return(
              status: 200,
              body: {
                info: {
                  requires_dist: botocore_requires_dist
                }
              }.to_json
            )

          stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
            .to_return(
              status: 200,
              body: {
                info: {
                  requires_dist: [
                    "urllib3 (<3,>=1.21.1)",
                    "idna (<4,>=2.5)"
                  ]
                }
              }.to_json
            )
        end

        it "does not propose an update that is incompatible with pinned botocore" do
          expect(latest_resolvable_version).to be_nil
        end

        context "when pinned direct dependency includes extras" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: <<~TOML
                [project]
                name = "dependabot-test"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore[crt]==1.29.0",
                ]

                [tool.pip]
                constraints = "constraints.txt"
              TOML
            )
          end

          it "still blocks incompatible update candidates" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when constraints file does not start with constraints" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: <<~TOML
                [project]
                name = "dependabot-test"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]

                [tool.pip]
                constraints = "pins.txt"
              TOML
            )
          end
          let(:constraints_file) do
            Dependabot::DependencyFile.new(
              name: "pins.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:dependency_requirements) do
            [{
              file: "pins.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          it "still applies the conflict guard" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when constraints file uses legacy constraints naming without explicit declaration" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: <<~TOML
                [project]
                name = "dependabot-test"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]
              TOML
            )
          end
          let(:constraints_file) do
            Dependabot::DependencyFile.new(
              name: "constraints.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:dependency_requirements) do
            [{
              file: "constraints.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          it "keeps applying the guard for legacy constraints projects" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when constraints file is referenced from requirements file" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: <<~TOML
                [project]
                name = "dependabot-test"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]
              TOML
            )
          end
          let(:constraints_file) do
            Dependabot::DependencyFile.new(
              name: "pins.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:dependency_files) { [pyproject, requirements_file, constraints_file] }
          let(:dependency_requirements) do
            [{
              file: "pins.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          context "when referenced using --constraint" do
            let(:requirements_file) do
              Dependabot::DependencyFile.new(
                name: "requirements.in",
                content: "--constraint pins.txt\nurllib3\n"
              )
            end

            it "discovers constraints file from requirements and applies the guard" do
              expect(latest_resolvable_version).to be_nil
            end
          end

          context "when referenced using --constraint=" do
            let(:requirements_file) do
              Dependabot::DependencyFile.new(
                name: "requirements.in",
                content: "--constraint=pins.txt\nurllib3\n"
              )
            end

            it "discovers constraints file from equals-style syntax" do
              expect(latest_resolvable_version).to be_nil
            end
          end

          context "when referenced using -c" do
            let(:requirements_file) do
              Dependabot::DependencyFile.new(
                name: "requirements.in",
                content: "-c pins.txt\nurllib3\n"
              )
            end

            it "discovers constraints file from short-form syntax" do
              expect(latest_resolvable_version).to be_nil
            end
          end

          context "when referenced using -c=" do
            let(:requirements_file) do
              Dependabot::DependencyFile.new(
                name: "requirements.in",
                content: "-c=pins.txt\nurllib3\n"
              )
            end

            it "discovers constraints file from short-form equals-style syntax" do
              expect(latest_resolvable_version).to be_nil
            end
          end

          context "when referenced with a quoted path containing spaces" do
            let(:constraints_file) do
              Dependabot::DependencyFile.new(
                name: "my pins.txt",
                content: "urllib3==1.26.0\n"
              )
            end
            let(:dependency_requirements) do
              [{
                file: "my pins.txt",
                requirement: "==1.26.0",
                groups: [],
                source: nil
              }]
            end

            context "when referenced using --constraint with double quotes" do
              let(:requirements_file) do
                Dependabot::DependencyFile.new(
                  name: "requirements.in",
                  content: "--constraint \"my pins.txt\"\nurllib3\n"
                )
              end

              it "discovers constraints file from quoted long-form syntax" do
                expect(latest_resolvable_version).to be_nil
              end
            end

            context "when referenced using -c= with single quotes" do
              let(:requirements_file) do
                Dependabot::DependencyFile.new(
                  name: "requirements.in",
                  content: "-c='my pins.txt'\nurllib3\n"
                )
              end

              it "discovers constraints file from quoted short-form equals syntax" do
                expect(latest_resolvable_version).to be_nil
              end
            end
          end
        end

        context "when constraints file is referenced from a non-requirements manifest" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: <<~TOML
                [project]
                name = "dependabot-test"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]
              TOML
            )
          end
          let(:constraints_file) do
            Dependabot::DependencyFile.new(
              name: "pins.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:manifest_file) do
            Dependabot::DependencyFile.new(
              name: "base.in",
              content: "-c pins.txt\nurllib3\n"
            )
          end
          let(:dependency_files) { [pyproject, manifest_file, constraints_file] }
          let(:dependency_requirements) do
            [{
              file: "pins.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          it "does not infer constraints from non-requirements manifests" do
            expect(latest_resolvable_version).to be > Gem::Version.new("1.26.0")
          end
        end

        context "when non-requirements files include constraint-looking content" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: <<~TOML
                [project]
                name = "dependabot-test"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]
              TOML
            )
          end
          let(:constraints_file) do
            Dependabot::DependencyFile.new(
              name: "pins.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:notes_file) do
            Dependabot::DependencyFile.new(
              name: "docs/notes.md",
              content: "--constraint pins.txt\n"
            )
          end
          let(:dependency_files) { [pyproject, constraints_file, notes_file] }
          let(:dependency_requirements) do
            [{
              file: "pins.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          it "does not infer constraints from non-requirements files" do
            expect(latest_resolvable_version).to be > Gem::Version.new("1.26.0")
          end

          context "when a non-requirements txt file includes --constraint" do
            let(:notes_file) do
              Dependabot::DependencyFile.new(
                name: "docs/notes.txt",
                content: "--constraint pins.txt\n"
              )
            end

            it "does not infer constraints from arbitrary txt files" do
              expect(latest_resolvable_version).to be > Gem::Version.new("1.26.0")
            end
          end

          context "when a non-requirements in file includes -c" do
            let(:notes_file) do
              Dependabot::DependencyFile.new(
                name: "docs/notes.in",
                content: "-c pins.txt\n"
              )
            end

            it "does not infer constraints from arbitrary in files" do
              expect(latest_resolvable_version).to be > Gem::Version.new("1.26.0")
            end
          end
        end

        context "when requires_dist uses a python_full_version marker" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<1.27,>=1.25.4) ; python_full_version >= '3.0.0'",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          it "evaluates marker and blocks incompatible candidates" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when requires_dist marker is parenthesized" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<1.27,>=1.25.4) ; (python_version >= '3.0')",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          it "evaluates the marker expression and blocks incompatible candidates" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when requires_dist marker has nested boolean expression" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<1.27,>=1.25.4) ; " \
              "(python_version < '3.0' or python_full_version >= '3.11.0') and extra == 'crt'",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          it "evaluates nested python marker terms and still applies the python constraint" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when requires_dist marker mixes python and non-python terms with or" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<1.27,>=1.25.4) ; python_version < '3.0' or extra == 'crt'",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          it "does not treat non-python markers as satisfying python marker checks" do
            expect(latest_resolvable_version).to be > Gem::Version.new("1.26.0")
          end
        end

        context "when requires_dist marker mixes python and non-python terms with and" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<1.27,>=1.25.4) ; python_version >= '3.0' and extra == 'crt'",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          it "still applies the python constraint" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when requires_dist has an unsupported python marker operator" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<1.27,>=1.25.4) ; python_version ~= '3.0'",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          it "treats the python marker as applicable and blocks incompatible candidates" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when requires_dist has malformed python marker syntax" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<1.27,>=1.25.4) ; python_version >= '3.0",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          it "fails open for python markers and blocks incompatible candidates" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when requires_dist marker uses unary not for python condition" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<1.27,>=1.25.4) ; not python_version < '3.0'",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          it "applies the inverted python condition and blocks incompatible candidates" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when requires_dist marker combines unary not with non-python terms" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<1.27,>=1.25.4) ; not python_version < '3.0' and not extra == 'crt'",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          it "still uses only python marker semantics for compatibility checks" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when requires_dist marker has unary not on non-python term in or expression" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<1.27,>=1.25.4) ; python_version < '3.0' or not extra == 'crt'",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          it "does not treat non-python unary not term as satisfying python marker checks" do
            expect(latest_resolvable_version).to be > Gem::Version.new("1.26.0")
          end
        end

        context "when selecting lowest resolvable security fix" do
          let(:security_advisories) do
            [
              Dependabot::SecurityAdvisory.new(
                dependency_name: dependency_name,
                package_manager: "pip",
                vulnerable_versions: ["<= 2.6.2"]
              )
            ]
          end

          it "does not return an incompatible security fix version" do
            expect(checker.lowest_resolvable_security_fix_version).to be_nil
          end
        end

        context "when metadata for a pinned dependency is unavailable" do
          let(:botocore_requires_dist) do
            [
              "urllib3 (<3,>=1.25.4)",
              "jmespath (<2.0.0,>=0.7.1)"
            ]
          end

          before do
            stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
              .to_raise(Excon::Error::Timeout.new("timeout"))
          end

          it "blocks update candidates when compatibility cannot be fully evaluated" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when metadata endpoint is unavailable but request succeeds" do
          let(:pyproject) { constraints_pyproject }

          before do
            stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
              .to_return(status: 404, body: "")
          end

          it "does not block candidates when endpoint response indicates metadata is unsupported" do
            expect(latest_resolvable_version).to be > Gem::Version.new("1.26.0")
          end
        end

        context "when metadata returns multiple requirements for the same target dependency" do
          let(:pyproject) { constraints_pyproject }

          before do
            stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
              .to_return(
                status: 200,
                body: {
                  info: {
                    requires_dist: [
                      "urllib3 (<3,>=1.21.1)",
                      "urllib3 (<2)",
                      "idna (<4,>=2.5)"
                    ]
                  }
                }.to_json
              )
          end

          it "applies all matching requirements before allowing the candidate" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when metadata includes an invalid requirement with a valid one" do
          let(:pyproject) { constraints_pyproject }

          before do
            stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
              .to_return(
                status: 200,
                body: {
                  info: {
                    requires_dist: [
                      "urllib3 (<2)",
                      "urllib3 (this is not valid)"
                    ]
                  }
                }.to_json
              )
          end

          it "still enforces valid requirements" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when metadata response body is malformed JSON" do
          let(:pyproject) { constraints_pyproject }

          before do
            stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
              .to_return(status: 200, body: "{\"info\":")
          end

          it "blocks update candidates when compatibility cannot be fully evaluated" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when metadata responses differ across multiple registries" do
          let(:requirements_file) do
            Dependabot::DependencyFile.new(
              name: "requirements.txt",
              content: <<~REQS
                --index-url https://pypi.org/simple/
                --extra-index-url https://mirror.example.com/simple/
              REQS
            )
          end
          let(:dependency_files) { [pyproject, constraints_file, requirements_file] }
          let(:pyproject) { constraints_pyproject }

          before do
            stub_request(:get, "https://mirror.example.com/simple/urllib3/")
              .to_return(status: 200, body: pypi_response)
          end

          context "when one registry times out and another returns 404" do
            before do
              stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
                .to_raise(Excon::Error::Timeout.new("timeout"))
              stub_request(:get, "https://mirror.example.com/pypi/requests/2.31.0/json/")
                .to_return(status: 404, body: "")
            end

            it "fails closed because metadata availability is uncertain" do
              expect(latest_resolvable_version).to be_nil
            end
          end

          context "when one registry is unauthorized but another returns metadata" do
            before do
              stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
                .to_return(status: 401, body: "")
              stub_request(:get, "https://mirror.example.com/pypi/requests/2.31.0/json/")
                .to_return(
                  status: 200,
                  body: {
                    info: {
                      requires_dist: [
                        "urllib3 (<3,>=1.21.1)",
                        "idna (<4,>=2.5)"
                      ]
                    }
                  }.to_json
                )
            end

            it "uses successful metadata from another registry" do
              expect(latest_resolvable_version).to be > Gem::Version.new("1.26.0")
            end
          end
        end

        context "when constraints path is a URL" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: <<~TOML
                [project]
                name = "dependabot-test"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]

                [tool.pip]
                constraints = "https://example.com/pins.txt"
              TOML
            )
          end
          let(:dependency_requirements) do
            [{
              file: "https://example.com/pins.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          it "applies the guard when requirements reference URL constraints" do
            expect(latest_resolvable_version).to be_nil
          end

          context "when requirement references a local file with same basename" do
            let(:dependency_requirements) do
              [{
                file: "pins.txt",
                requirement: "==1.26.0",
                groups: [],
                source: nil
              }]
            end

            it "does not apply the guard via basename matching" do
              expect(latest_resolvable_version).to be > Gem::Version.new("1.26.0")
            end
          end
        end

        context "when metadata endpoint returns unauthorized" do
          before do
            stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
              .to_return(status: 401, body: "")
          end

          it "blocks candidates when metadata cannot be trusted" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when metadata endpoint returns a server error" do
          before do
            stub_request(:get, "https://pypi.org/pypi/requests/2.31.0/json/")
              .to_return(status: 500, body: "")
          end

          it "blocks candidates when metadata endpoint is unstable" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when multiple constraints files share the same basename" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "services/api/pyproject.toml",
              content: <<~TOML
                [project]
                name = "dependabot-test"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]

                [tool.pip]
                constraints = "../shared/pins.txt"
              TOML
            )
          end
          let(:constraints_file) do
            Dependabot::DependencyFile.new(
              name: "services/shared/pins.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:other_constraints_file) do
            Dependabot::DependencyFile.new(
              name: "other/pins.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:dependency_files) { [pyproject, constraints_file, other_constraints_file] }
          let(:dependency_requirements) do
            [{
              file: "other/pins.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          it "uses path-aware matching and does not apply guard for unrelated files" do
            expect(latest_resolvable_version).to be > Gem::Version.new("1.26.0")
          end

          context "when requirement file matches the declared nested constraints path" do
            let(:dependency_requirements) do
              [{
                file: "services/shared/pins.txt",
                requirement: "==1.26.0",
                groups: [],
                source: nil
              }]
            end

            it "applies the guard for the pyproject that declared the matching path" do
              expect(latest_resolvable_version).to be_nil
            end
          end
        end

        context "when legacy constraints naming is used in a single nested-pyproject repo" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "services/api/pyproject.toml",
              content: <<~TOML
                [project]
                name = "service-project"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]
              TOML
            )
          end
          let(:constraints_file) do
            Dependabot::DependencyFile.new(
              name: "services/api/constraints.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:dependency_files) { [pyproject, constraints_file] }
          let(:dependency_requirements) do
            [{
              file: "services/api/constraints.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          it "still applies the guard for the only available nested pyproject" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when constraints are inferred in a single nested-pyproject repo" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "services/api/pyproject.toml",
              content: <<~TOML
                [project]
                name = "service-project"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]
              TOML
            )
          end
          let(:manifest_file) do
            Dependabot::DependencyFile.new(
              name: "services/api/requirements.in",
              content: "-c pins.txt\nurllib3\n"
            )
          end
          let(:constraints_file) do
            Dependabot::DependencyFile.new(
              name: "services/api/pins.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:dependency_files) { [pyproject, manifest_file, constraints_file] }
          let(:dependency_requirements) do
            [{
              file: "services/api/pins.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          it "uses the only nested pyproject and blocks incompatible updates" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when constraints apply in a multi-pyproject repo but pyproject ownership is ambiguous" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: <<~TOML
                [project]
                name = "root-project"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]
              TOML
            )
          end
          let(:service_pyproject) do
            Dependabot::DependencyFile.new(
              name: "services/api/pyproject.toml",
              content: <<~TOML
                [project]
                name = "service-project"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]
              TOML
            )
          end
          let(:constraints_file) do
            Dependabot::DependencyFile.new(
              name: "pins.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:manifest_file) do
            Dependabot::DependencyFile.new(
              name: "requirements.in",
              content: "-c pins.txt\nurllib3\n"
            )
          end
          let(:dependency_files) { [pyproject, service_pyproject, manifest_file, constraints_file] }
          let(:dependency_requirements) do
            [{
              file: "pins.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          it "fails closed instead of proposing a potentially conflicting update" do
            expect(latest_resolvable_version).to be_nil
          end
        end

        context "when legacy constraints naming is used in a multi-pyproject repo" do
          let(:pyproject) do
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: <<~TOML
                [project]
                name = "root-project"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]
              TOML
            )
          end
          let(:service_pyproject) do
            Dependabot::DependencyFile.new(
              name: "services/api/pyproject.toml",
              content: <<~TOML
                [project]
                name = "service-project"
                version = "0.1.0"

                dependencies = [
                    "requests==2.31.0",
                    "botocore==1.29.0",
                ]
              TOML
            )
          end
          let(:constraints_file) do
            Dependabot::DependencyFile.new(
              name: "constraints.txt",
              content: "urllib3==1.26.0\n"
            )
          end
          let(:dependency_files) { [pyproject, service_pyproject, constraints_file] }
          let(:dependency_requirements) do
            [{
              file: "constraints.txt",
              requirement: "==1.26.0",
              groups: [],
              source: nil
            }]
          end

          it "fails closed rather than defaulting to the root pyproject" do
            expect(latest_resolvable_version).to be_nil
          end
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

      context "with a Poetry project" do
        let(:dependency_files) { [pyproject, poetry_lock] }
        let(:pyproject_fixture_name) { "poetry_exact_requirement.toml" }
        let(:poetry_lock) do
          Dependabot::DependencyFile.new(
            name: "poetry.lock",
            content: fixture("poetry_locks", "exact_version.lock")
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
        let(:pypi_url) { "https://pypi.org/simple/requests/" }
        let(:pypi_response) { fixture("pypi", "pypi_simple_response_requests.html") }

        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: dependency_name,
              package_manager: "pip",
              vulnerable_versions: ["<= 2.19.0"]
            )
          ]
        end

        it "returns the lowest security fix version via the Poetry resolver" do
          dummy_resolver = instance_double(described_class::PoetryVersionResolver)
          allow(described_class::PoetryVersionResolver).to receive(:new).and_return(dummy_resolver)
          allow(dummy_resolver).to receive(:resolvable?).with(version: Gem::Version.new("2.19.1"))
                                                        .and_return(true)

          expect(checker.preferred_resolvable_version).to eq(Gem::Version.new("2.19.1"))
        end

        context "when the fix version is not resolvable" do
          it "falls back to nil" do
            dummy_resolver = instance_double(described_class::PoetryVersionResolver)
            allow(described_class::PoetryVersionResolver).to receive(:new).and_return(dummy_resolver)
            allow(dummy_resolver).to receive(:resolvable?).and_return(false)

            expect(checker.preferred_resolvable_version).to be_nil
          end
        end
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
            cooldown_options: cooldown_options,
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

        context "when the project is not on PyPI but has library metadata" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(status: 404)
          end

          its([:requirement]) { is_expected.to eq(">=1.0,<2.20") }
        end

        context "when dealing with a non-library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(
                status: 200,
                body: { info: { summary: "A completely different package" } }.to_json
              )
          end

          its([:requirement]) { is_expected.to eq("~2.19.1") }
        end

        context "when dealing with a poetry in non-package mode" do
          let(:pyproject_fixture_name) { "poetry_non_package_mode.toml" }

          its([:requirement]) { is_expected.to eq("~2.19.1") }
        end

        context "when checking library status multiple times" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(status: 404)
          end

          it "caches the PyPI check result to avoid redundant calls" do
            # Call requirements_update_strategy multiple times
            checker.send(:requirements_update_strategy)
            checker.send(:requirements_update_strategy)

            # Verify PyPI was only called once (memoization working)
            expect(a_request(:get, "https://pypi.org/pypi/pendulum/json/"))
              .to have_been_made.once
          end
        end

        context "when PyPI request raises Excon::Error::Timeout" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_raise(Excon::Error::Timeout.new("connection timeout"))
          end

          it "treats the project as a library based on metadata" do
            expect(checker.send(:library?)).to be true
          end
        end

        context "when PyPI request raises Excon::Error::Socket" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_raise(Excon::Error::Socket.new(SocketError.new("getaddrinfo failed")))
          end

          it "treats the project as a library based on metadata" do
            expect(checker.send(:library?)).to be true
          end
        end

        context "when PyPI request raises URI::InvalidURIError" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_raise(URI::InvalidURIError.new("bad URI"))
          end

          it "treats the project as a library based on metadata" do
            expect(checker.send(:library?)).to be true
          end
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

        context "when the project is not on PyPI but has library metadata" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(status: 404)
          end

          its([:requirement]) { is_expected.to eq(">=1.0,<2.20") }
        end

        context "when dealing with a non-library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(
                status: 200,
                body: { info: { summary: "A completely different package" } }.to_json
              )
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

        context "when the project is not on PyPI but has library metadata" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(status: 404)
          end

          its([:requirement]) { is_expected.to eq(">=1.0,<2.20") }
        end

        context "when dealing with a non-library" do
          before do
            stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
              .to_return(
                status: 200,
                body: { info: { summary: "A completely different package" } }.to_json
              )
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
        expect(checker.updated_requirements).to contain_exactly(
          {
            file: "constraints.txt",
            requirement: "==2.6.0",
            groups: [],
            source: nil
          },
          {
            file: "requirements.txt",
            requirement: "==2.6.0",
            groups: [],
            source: nil
          }
        )
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

  describe "with cooldown options" do
    let(:pypi_url) { "https://pypi.org/pypi/luigi/json" }
    let(:pypi_response) { fixture("pypi", "pypi_response_luigi.json") }

    before do
      # Move `stub_request` inside `before` block
      stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)

      # Package Name: luigi
      # Current version: 2.0.0
      # Release Versions:
      # ...
      # 2.0.0 => Date: 2015-10-23, Yanked: false
      # 2.0.1 => Date: 2015-12-05, Yanked: false
      # ...
      # 3.3.0 => Date: 2023-05-04, Yanked: false
      # 3.4.0 => Date: 2023-10-05, Yanked: false
      # 3.5.0 => Date: 2024-01-15, Yanked: false
      # 3.5.1 => Date: 2024-05-20, Yanked: false
      # 3.5.2 => Date: 2024-09-04, Yanked: false
      # 3.6.0 => Date: 2024-12-06, Yanked: false
      allow(Time).to receive(:now).and_return(Time.parse("2024-12-08"))
    end

    describe "#latest_resolvable_version" do
      subject(:latest_resolvable_version) { checker.latest_resolvable_version }

      context "with a requirement file" do
        let(:dependency_files) { [requirements_file] }

        context "when cooldown is not set" do
          let(:cooldown_options) { nil }

          it { is_expected.to eq(Gem::Version.new("3.6.0")) }
        end

        context "when cooldown applies to patch updates" do
          let(:cooldown_options) do
            Dependabot::Package::ReleaseCooldownOptions.new(semver_patch_days: 2)
          end

          it { is_expected.to eq(Gem::Version.new("3.6.0")) }
        end

        context "when cooldown applies to minor updates" do
          let(:cooldown_options) do
            Dependabot::Package::ReleaseCooldownOptions.new(semver_minor_days: 5)
          end

          it { is_expected.to eq(Gem::Version.new("3.6.0")) }
        end

        context "when cooldown applies to major updates" do
          let(:cooldown_options) do
            Dependabot::Package::ReleaseCooldownOptions.new(semver_major_days: 10)
          end

          it { is_expected.to eq(Gem::Version.new("3.5.2")) }
        end

        context "when cooldown applies to all updates" do
          let(:cooldown_options) do
            Dependabot::Package::ReleaseCooldownOptions.new(default_days: 10)
          end

          it { is_expected.to eq(Gem::Version.new("3.5.2")) }
        end
      end
    end
  end

  describe "Git dependencies" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "fastapi",
        version: nil,
        requirements: dependency_requirements,
        package_manager: "pip"
      )
    end
    let(:dependency_requirements) do
      [{
        requirement: nil,
        file: "pyproject.toml",
        groups: ["dependencies"],
        source: {
          type: "git",
          url: "https://github.com/tiangolo/fastapi",
          ref: "0.110.0",
          branch: nil
        }
      }]
    end
    let(:pyproject_fixture_name) { "git_dependency_with_tag.toml" }
    let(:dependency_files) { [pyproject] }

    before do
      git_url = "https://github.com/tiangolo/fastapi.git"
      git_header = {
        "content-type" => "application/x-git-upload-pack-advertisement"
      }
      stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
        .to_return(
          status: 200,
          body: fixture("git", "upload_packs", "fastapi"),
          headers: git_header
        )
    end

    describe "#latest_version" do
      subject(:latest_version) { checker.latest_version }

      it "fetches the latest version tag from the git repository" do
        expect(latest_version).to eq(Gem::Version.new("0.128.0"))
      end
    end

    describe "#latest_resolvable_version" do
      subject(:latest_resolvable_version) { checker.latest_resolvable_version }

      it "returns the latest version for git dependencies" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("0.128.0"))
      end
    end

    describe "#latest_resolvable_version_with_no_unlock" do
      subject(:latest_resolvable_version_with_no_unlock) { checker.latest_resolvable_version_with_no_unlock }

      it "returns nil when pinned to a specific tag" do
        expect(latest_resolvable_version_with_no_unlock).to be_nil
      end
    end

    describe "#updated_requirements" do
      subject(:updated_requirements) { checker.updated_requirements }

      before do
        allow(checker)
          .to receive(:latest_version)
          .and_return(Gem::Version.new("0.128.0"))
      end

      it "updates the git tag in the source" do
        expect(updated_requirements).to eq(
          [{
            requirement: nil,
            file: "pyproject.toml",
            groups: ["dependencies"],
            source: {
              type: "git",
              url: "https://github.com/tiangolo/fastapi",
              ref: "0.128.0",
              branch: nil
            }
          }]
        )
      end
    end

    describe "with cooldown options" do
      let(:tag_details_response) do
        fixture("git", "tag_details", "fastapi")
      end
      let(:git_tag_details) do
        [
          Dependabot::GitTagWithDetail.new(tag: "0.110.0", release_date: "2025-02-01"),
          Dependabot::GitTagWithDetail.new(tag: "0.111.0", release_date: "2025-05-15"),
          Dependabot::GitTagWithDetail.new(tag: "0.120.0", release_date: "2025-10-01"),
          Dependabot::GitTagWithDetail.new(tag: "0.124.0", release_date: "2025-12-06"),
          Dependabot::GitTagWithDetail.new(tag: "0.124.2", release_date: "2025-12-10"),
          Dependabot::GitTagWithDetail.new(tag: "0.125.0", release_date: "2025-12-17"),
          Dependabot::GitTagWithDetail.new(tag: "0.126.0", release_date: "2025-12-20"),
          Dependabot::GitTagWithDetail.new(tag: "0.127.0", release_date: "2025-12-21"),
          Dependabot::GitTagWithDetail.new(tag: "0.128.0", release_date: "2025-12-27")
        ]
      end

      before do
        # Stub the refs_for_tag_with_detail method on GitCommitChecker instances
        allow(Dependabot::GitCommitChecker).to receive(:new).and_wrap_original do |method, *args, **kwargs|
          checker = method.call(*args, **kwargs)
          allow(checker).to receive(:refs_for_tag_with_detail).and_return(git_tag_details)
          checker
        end
        # Freeze time to January 21, 2026
        allow(Time).to receive(:now).and_return(Time.parse("2026-01-21"))
      end

      describe "#latest_version" do
        subject(:latest_version) { checker.latest_version }

        context "when cooldown is not set" do
          let(:cooldown_options) { nil }

          it "returns the latest version without filtering" do
            expect(latest_version).to eq(Gem::Version.new("0.128.0"))
          end
        end

        context "when cooldown applies with 40-day default" do
          let(:cooldown_options) do
            Dependabot::Package::ReleaseCooldownOptions.new(default_days: 40)
          end

          it "returns the latest version outside cooldown period" do
            # 0.128.0 released 2025-12-27 is 25 days old (in cooldown)
            # 0.124.2 released 2025-12-10 is 42 days old (outside cooldown)
            expect(latest_version).to eq(Gem::Version.new("0.124.2"))
          end
        end

        context "when cooldown applies with 10-day default" do
          let(:cooldown_options) do
            Dependabot::Package::ReleaseCooldownOptions.new(default_days: 10)
          end

          it "returns the latest version outside 10-day cooldown" do
            # 0.128.0 released 2025-12-27 is 25 days old (outside 10-day cooldown)
            expect(latest_version).to eq(Gem::Version.new("0.128.0"))
          end
        end

        context "when all versions are in cooldown" do
          let(:cooldown_options) do
            Dependabot::Package::ReleaseCooldownOptions.new(default_days: 365)
          end

          it "falls back to current version" do
            expect(latest_version).to be_nil
          end
        end
      end

      describe "#updated_requirements" do
        subject(:updated_requirements) { checker.updated_requirements }

        context "when cooldown applies with 40-day default" do
          let(:cooldown_options) do
            Dependabot::Package::ReleaseCooldownOptions.new(default_days: 40)
          end

          it "updates the git tag to version outside cooldown" do
            expect(updated_requirements).to eq(
              [{
                requirement: nil,
                file: "pyproject.toml",
                groups: ["dependencies"],
                source: {
                  type: "git",
                  url: "https://github.com/tiangolo/fastapi",
                  ref: "0.124.2",
                  branch: nil
                }
              }]
            )
          end
        end
      end
    end
  end
end
