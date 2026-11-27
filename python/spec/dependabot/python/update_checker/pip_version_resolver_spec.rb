# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/requirement"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/python/file_parser"
require "dependabot/python/requirements_file_parser"
require "dependabot/python/update_checker/pip_version_resolver"
require_relative "shared_examples_for_pip_pyproject_reads"

RSpec.describe Dependabot::Python::UpdateChecker::PipVersionResolver do
  before do
    stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
    allow(Dependabot::Python::RequirementsFileParser).to receive(:new).and_return(requirements_parser)
  end

  let(:pypi_url) { "https://pypi.org/simple/luigi/" }
  let(:pypi_response) { fixture("pypi/pypi_simple_response.html") }
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
    )
  end
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
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:requirements_parser) { instance_double(Dependabot::Python::RequirementsFileParser, parse: helper_result) }
  let(:helper_result) do
    Dependabot::Python::RequirementsFileParser.from_helper_result(
      "schema_version" => 1,
      "declarations" => helper_declarations,
      "files" => helper_files,
      "edges" => helper_edges,
      "roots" => helper_roots,
      "components" => [
        {
          "id" => "component-0",
          "files" => helper_files.map { |file| file.fetch("path") },
          "roots" => helper_roots,
          "status" => helper_component_status,
          "reasons" => helper_component_reasons,
          "has_index_options" => helper_component_has_index_options,
          "source_spans_applicable" => helper_component_source_spans_applicable?
        }
      ]
    )
  end
  let(:helper_declarations) do
    [
      {
        "name" => dependency_name,
        "version" => dependency_version,
        "markers" => nil,
        "file" => "requirements.txt",
        "requirement" => dependency_requirements.first.fetch(:requirement),
        "source_requirement" => "#{dependency_name}#{dependency_requirements.first.fetch(:requirement)}",
        "extras" => [],
        "constraint" => false,
        "editable" => false,
        "local" => false,
        "hashes" => [],
        "source" => { "start_line" => 1, "end_line" => 1 }
      }
    ]
  end
  let(:helper_files) { [{ "path" => "requirements.txt", "component_id" => "component-0" }] }
  let(:helper_edges) { [] }
  let(:helper_roots) { ["requirements.txt"] }
  let(:helper_component_status) { "partial" }
  let(:helper_component_reasons) { ["remote_reference"] }
  let(:helper_component_has_index_options) { false }
  let(:dependency_files) { [requirements_file, python_version_file] }
  let(:requirements_file) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: fixture("requirements/#{requirements_fixture_name}")
    )
  end
  let(:requirements_fixture_name) { "version_specified.txt" }
  let(:python_version_file) do
    Dependabot::DependencyFile.new(
      name: ".python-version",
      content: python_version_content
    )
  end
  let(:python_version_content) { "3.11.0\n" }
  let(:pypi_response) { fixture("pypi/pypi_simple_response_django.html") }
  let(:pypi_url) { "https://pypi.org/simple/django/" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: package_manager
    )
  end
  let(:package_manager) { "pip" }
  let(:dependency_name) { "django" }
  let(:dependency_version) { "1.2.4" }
  let(:dependency_requirements) do
    [{
      file: "requirements.txt",
      requirement: "==1.2.4",
      groups: [],
      source: nil
    }]
  end

  def helper_component_source_spans_applicable?
    true
  end

  it_behaves_like "a pip resolver reading pyproject constraints"

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    context "with a complete native-resolution component" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:pip_report_install) do
        [{ "metadata" => { "name" => "Django", "version" => resolved_version } }]
      end
      let(:resolved_version) { "3.2.3" }
      let(:pip_invocations) { [] }
      let(:rewritten_files) { {} }

      before do
        allow(resolver.send(:language_version_manager)).to receive(:install_required_python)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_wrap_original do |method, command, **args|
          next method.call(command, **args) unless command.include?("pip install")

          pip_invocations << { command: command, args: args }
          helper_files.each do |file|
            path = file.fetch("path")
            rewritten_files[path] = File.read(path)
          end
          File.write(
            "dependabot-pip-report.json",
            JSON.dump("install" => pip_report_install)
          )
          ""
        end
      end

      it "uses pip's compatible version and rewrites the helper source span" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.3"))
        expect(rewritten_files.fetch("requirements.txt"))
          .to include("django>=1.2.4,<=3.2.4,!=1.2.4")
        expect(pip_invocations.map { |invocation| invocation.fetch(:command) })
          .to contain_exactly(include("-r requirements.txt"))
        expect(Dependabot::Python::RequirementsFileParser).to have_received(:new).with(
          dependency_files: dependency_files,
          requirement_files: ["requirements.txt"]
        )
      end

      it "stops policy admission at the highest eligible candidate" do
        allow(resolver).to receive(:candidate_admitted_by_requirement?).and_call_original

        latest_resolvable_version

        expect(resolver).to have_received(:candidate_admitted_by_requirement?).once
      end

      context "when pip serializes an absent marker as None" do
        let(:helper_declarations) { [super().first.merge("markers" => "None")] }

        it "does not write a marker" do
          latest_resolvable_version

          expect(rewritten_files.fetch("requirements.txt"))
            .to include("django>=1.2.4,<=3.2.4,!=1.2.4\n")
        end
      end

      context "when an unrelated text file has an invalid reference" do
        let(:dependency_files) do
          [
            requirements_file,
            python_version_file,
            Dependabot::DependencyFile.new(
              name: "docs/notes.txt",
              content: "--constraint missing.txt\n",
              support_file: true
            )
          ]
        end

        it "does not make the bystander a helper entry file" do
          latest_resolvable_version

          expect(Dependabot::Python::RequirementsFileParser).to have_received(:new).with(
            dependency_files: dependency_files,
            requirement_files: ["requirements.txt"]
          )
        end
      end

      context "when the target declaration spans physical lines" do
        let(:requirements_file) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: "django==1.2.4 \\\n  ; python_version >= '3.10'\nrequests==2.31.0\n"
          )
        end
        let(:helper_declarations) do
          [
            super().first.merge(
              "markers" => "python_version >= \"3.10\"",
              "source" => { "start_line" => 1, "end_line" => 2 }
            ),
            {
              "name" => "requests",
              "version" => "2.31.0",
              "markers" => nil,
              "file" => "requirements.txt",
              "requirement" => "==2.31.0",
              "source_requirement" => "requests==2.31.0",
              "extras" => [],
              "constraint" => false,
              "editable" => false,
              "local" => false,
              "hashes" => [],
              "source" => { "start_line" => 3, "end_line" => 3 }
            }
          ]
        end

        it "replaces only the declared span" do
          latest_resolvable_version

          expect(rewritten_files.fetch("requirements.txt")).to eq(
            "django>=1.2.4,<=3.2.4,!=1.2.4; python_version >= \"3.10\"\nrequests==2.31.0\n"
          )
        end
      end

      context "when the target follows a peer in a CR-only file" do
        let(:requirements_file) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: "requests==2.31.0\rdjango==1.2.4\r"
          )
        end
        let(:helper_declarations) do
          target = super().first.merge("source" => { "start_line" => 2, "end_line" => 2 })
          [
            {
              "name" => "requests",
              "version" => "2.31.0",
              "markers" => nil,
              "file" => "requirements.txt",
              "requirement" => "==2.31.0",
              "source_requirement" => "requests==2.31.0",
              "extras" => [],
              "constraint" => false,
              "editable" => false,
              "local" => false,
              "hashes" => [],
              "source" => { "start_line" => 1, "end_line" => 1 }
            },
            target
          ]
        end

        it "preserves the peer and CR terminators" do
          latest_resolvable_version

          expect(rewritten_files.fetch("requirements.txt")).to eq(
            "requests==2.31.0\rdjango>=1.2.4,<=3.2.4,!=1.2.4\r"
          )
        end
      end

      context "when the declaration uses CRLF terminators" do
        let(:requirements_file) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: "django==1.2.4\r\nrequests==2.31.0\r\n"
          )
        end

        it "preserves CRLF terminators" do
          latest_resolvable_version

          expect(rewritten_files.fetch("requirements.txt")).to eq(
            "django>=1.2.4,<=3.2.4,!=1.2.4\r\nrequests==2.31.0\r\n"
          )
        end
      end

      context "when the target uses a form-feed terminator" do
        let(:requirements_file) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: "django==1.2.4\frequests==2.31.0\n"
          )
        end
        let(:helper_declarations) do
          [
            super().first,
            {
              "name" => "requests",
              "version" => "2.31.0",
              "markers" => nil,
              "file" => "requirements.txt",
              "requirement" => "==2.31.0",
              "source_requirement" => "requests==2.31.0",
              "extras" => [],
              "constraint" => false,
              "editable" => false,
              "local" => false,
              "hashes" => [],
              "source" => { "start_line" => 2, "end_line" => 2 }
            }
          ]
        end

        it "preserves the peer and form-feed terminator" do
          latest_resolvable_version

          expect(rewritten_files.fetch("requirements.txt")).to eq(
            "django>=1.2.4,<=3.2.4,!=1.2.4\frequests==2.31.0\n"
          )
        end
      end

      context "when the target is declared in a referenced file" do
        let(:dependency_requirements) do
          [{ file: "constraints.txt", requirement: "==1.2.4", groups: [], source: nil }]
        end
        let(:requirements_file) do
          Dependabot::DependencyFile.new(name: "requirements.txt", content: "-c constraints.txt\n")
        end
        let(:constraints_file) do
          Dependabot::DependencyFile.new(name: "constraints.txt", content: "django==1.2.4\n")
        end
        let(:dependency_files) { [requirements_file, constraints_file, python_version_file] }
        let(:helper_files) do
          [
            { "path" => "constraints.txt", "component_id" => "component-0" },
            { "path" => "requirements.txt", "component_id" => "component-0" }
          ]
        end
        let(:helper_edges) do
          [
            {
              "from" => "requirements.txt",
              "to" => "constraints.txt",
              "type" => "constraint",
              "remote" => false,
              "source" => { "start_line" => 1, "end_line" => 1 }
            }
          ]
        end
        let(:helper_declarations) do
          [
            super().first.merge(
              "file" => "constraints.txt",
              "constraint" => true
            )
          ]
        end

        it "runs the component root and edits the referenced declaration" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.3"))
          expect(rewritten_files.fetch("constraints.txt"))
            .to include("django>=1.2.4,<=3.2.4,!=1.2.4")
          expect(pip_invocations.first.fetch(:command)).to include("-r requirements.txt")
        end

        context "when pip omits the dormant constraint target" do
          let(:pip_report_install) { [] }

          it "uses the policy candidate" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
          end

          context "when the source requirement excludes the policy ceiling" do
            let(:dependency_requirements) do
              [{ file: "constraints.txt", requirement: ">=1.0,!=3.2.4,<4.0", groups: [], source: nil }]
            end
            let(:constraints_file) do
              Dependabot::DependencyFile.new(
                name: "constraints.txt",
                content: "django>=1.0,!=3.2.4,<4.0\n"
              )
            end
            let(:helper_declarations) do
              [
                super().first.merge(
                  "requirement" => ">=1.0,!=3.2.4,<4.0",
                  "source_requirement" => "django>=1.0,!=3.2.4,<4.0"
                )
              ]
            end

            it "uses the newest eligible candidate admitted by the temporary requirement" do
              expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.3"))
            end
          end
        end

        context "when the report contains malformed metadata for the dormant target" do
          let(:pip_report_install) { [{ "metadata" => { "name" => "django" } }] }

          it "raises an invalid report error" do
            expect { latest_resolvable_version }
              .to raise_error(
                Dependabot::Python::UpdateChecker::PipVersionResolver::InvalidPipReport,
                /name and version/
              )
          end
        end

        context "when an input file owns the component" do
          let(:requirements_file) do
            Dependabot::DependencyFile.new(name: "requirements.in", content: "-c constraints.txt\n")
          end
          let(:helper_files) do
            [
              { "path" => "constraints.txt", "component_id" => "component-0" },
              { "path" => "requirements.in", "component_id" => "component-0" }
            ]
          end
          let(:helper_edges) do
            [
              {
                "from" => "requirements.in",
                "to" => "constraints.txt",
                "type" => "constraint",
                "remote" => false,
                "source" => { "start_line" => 1, "end_line" => 1 }
              }
            ]
          end
          let(:helper_roots) { ["requirements.in"] }

          it "runs the helper-defined input root" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.3"))
            expect(pip_invocations.first.fetch(:command)).to include("-r requirements.in")
            expect(Dependabot::Python::RequirementsFileParser).to have_received(:new).with(
              dependency_files: dependency_files,
              requirement_files: ["requirements.in", "constraints.txt"]
            )
          end
        end

        context "when a differently named input file owns the component" do
          let(:requirements_file) do
            Dependabot::DependencyFile.new(name: "development.in", content: "-c constraints.txt\n")
          end
          let(:helper_files) do
            [
              { "path" => "constraints.txt", "component_id" => "component-0" },
              { "path" => "development.in", "component_id" => "component-0" }
            ]
          end
          let(:helper_edges) do
            [
              {
                "from" => "development.in",
                "to" => "constraints.txt",
                "type" => "constraint",
                "remote" => false,
                "source" => { "start_line" => 1, "end_line" => 1 }
              }
            ]
          end
          let(:helper_roots) { ["development.in"] }

          it "runs the helper-defined input root" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.3"))
            expect(pip_invocations.first.fetch(:command)).to include("-r development.in")
            expect(Dependabot::Python::RequirementsFileParser).to have_received(:new).with(
              dependency_files: dependency_files,
              requirement_files: ["development.in", "constraints.txt"]
            )
          end
        end
      end

      context "when another file constrains the target" do
        let(:requirements_file) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: "django==1.2.4\n-c constraints.txt\n"
          )
        end
        let(:constraints_file) do
          Dependabot::DependencyFile.new(name: "constraints.txt", content: "django<2\n")
        end
        let(:dependency_files) { [requirements_file, constraints_file, python_version_file] }
        let(:helper_files) do
          [
            { "path" => "constraints.txt", "component_id" => "component-0" },
            { "path" => "requirements.txt", "component_id" => "component-0" }
          ]
        end
        let(:helper_edges) do
          [
            {
              "from" => "requirements.txt",
              "to" => "constraints.txt",
              "type" => "constraint",
              "remote" => false,
              "source" => { "start_line" => 2, "end_line" => 2 }
            }
          ]
        end
        let(:helper_declarations) do
          primary_declaration = super().first
          [
            primary_declaration,
            primary_declaration.merge(
              "file" => "constraints.txt",
              "requirement" => "<2",
              "source_requirement" => "django<2",
              "constraint" => true
            )
          ]
        end
        let(:resolved_version) { "1.11.29" }

        it "rewrites only the declaration the updater will change" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("1.11.29"))
          expect(rewritten_files.fetch("requirements.txt"))
            .to include("django>=1.2.4,<=3.2.4,!=1.2.4")
          expect(rewritten_files.fetch("constraints.txt")).to eq("django<2\n")
        end
      end

      context "when pip omits an active target" do
        let(:pip_report_install) { [] }

        it "raises an invalid report error" do
          expect { latest_resolvable_version }
            .to raise_error(
              Dependabot::Python::UpdateChecker::PipVersionResolver::InvalidPipReport,
              /exactly one version/
            )
        end
      end

      context "when lower bounds have equal versions" do
        let(:dependency_version) { nil }
        let(:dependency_requirements) do
          [{ file: "requirements.txt", requirement: ">=2.0,>2.0,<3.0", groups: [], source: nil }]
        end
        let(:requirements_file) do
          Dependabot::DependencyFile.new(name: "requirements.txt", content: "django>=2.0,>2.0,<3.0\n")
        end

        it "keeps the strict lower bound" do
          latest_resolvable_version

          expect(rewritten_files.fetch("requirements.txt")).to include("django>2.0,<=3.2.4")
        end
      end

      context "when a prerelease is policy eligible" do
        before do
          allow(resolver.send(:latest_version_finder)).to receive_messages(
            eligible_versions: [
              Dependabot::Python::Version.new("2.5rc1"),
              Dependabot::Python::Version.new("3.0")
            ],
            resolver_excluded_versions: []
          )
        end

        it "opts in only the target requirement" do
          latest_resolvable_version

          expect(rewritten_files.fetch("requirements.txt")).to include(">=0.0.dev0")
          expect(pip_invocations.first.fetch(:command)).not_to include(" --pre ")
        end
      end

      context "when a prerelease is rejected by policy" do
        before do
          allow(resolver.send(:latest_version_finder)).to receive_messages(
            eligible_versions: [
              Dependabot::Python::Version.new("2.0"),
              Dependabot::Python::Version.new("3.0")
            ],
            resolver_excluded_versions: [Dependabot::Python::Version.new("2.5rc1")]
          )
        end

        it "excludes the prerelease from pip's candidate solve" do
          latest_resolvable_version

          expect(rewritten_files.fetch("requirements.txt")).to include("!=2.5rc1")
        end
      end

      context "when a post-release is policy eligible" do
        let(:dependency_version) { "1.0" }
        let(:dependency_requirements) do
          [{ file: "requirements.txt", requirement: "==1.0", groups: [], source: nil }]
        end
        let(:requirements_file) do
          Dependabot::DependencyFile.new(name: "requirements.txt", content: "django==1.0\n")
        end
        let(:resolved_version) { "1.0.post1" }

        before do
          allow(resolver.send(:latest_version_finder)).to receive_messages(
            eligible_versions: [Dependabot::Python::Version.new("1.0.post1")],
            resolver_excluded_versions: []
          )
        end

        it "uses an inclusive floor and excludes only the current release" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("1.0.post1"))
          expect(rewritten_files.fetch("requirements.txt"))
            .to include("django>=1.0,<=1.0.post1,!=1.0")
        end
      end

      context "with authenticated Python indexes" do
        let(:credentials) do
          [
            Dependabot::Credential.new(
              {
                "type" => "python_index",
                "index-url" => "https://private.example.com/simple",
                "token" => "private-user:private-password",
                "replaces-base" => true
              }
            ),
            Dependabot::Credential.new(
              {
                "type" => "python_index",
                "index-url" => "https://extra.example.com/simple",
                "token" => "extra-user:extra-password"
              }
            )
          ]
        end

        before do
          %w(private extra).each do |index|
            stub_request(:get, %r{https://#{index}\.example\.com/(?:pypi/django/json|simple/django/)})
              .to_return(status: 200, body: pypi_response)
          end
        end

        it "passes credentials outside the logged command" do
          latest_resolvable_version

          invocation = pip_invocations.first
          expect(invocation.fetch(:command)).not_to include("private-user", "private-password")
          expect(invocation.fetch(:args).fetch(:env)).to include(
            "PIP_INDEX_URL" => "https://private-user:private-password@private.example.com/simple",
            "PIP_EXTRA_INDEX_URL" => "https://extra-user:extra-password@extra.example.com/simple"
          )
        end

        context "when the component declares an index option that overrides the environment" do
          let(:requirements_file) do
            Dependabot::DependencyFile.new(
              name: "requirements.txt",
              content: "--trusted-host private.example.com --index-url https://private.example.com/simple\n" \
                       "django==1.2.4\n"
            )
          end
          let(:helper_component_has_index_options) { true }
          let(:helper_declarations) do
            [super().first.merge("source" => { "start_line" => 2, "end_line" => 2 })]
          end

          it "uses static candidate selection instead of unauthenticated native resolution" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
            expect(pip_invocations).to be_empty
          end
        end

        context "when pip.conf and credentials both add extra indexes" do
          before do
            stub_request(:get, %r{https://configured\.example\.com/(?:pypi/django/json|simple/django/)})
              .to_return(status: 200, body: pypi_response)
          end

          let(:dependency_files) do
            [
              requirements_file,
              python_version_file,
              Dependabot::DependencyFile.new(
                name: "pip.conf",
                content: "[global]\nextra-index-url = https://configured.example.com/simple\n",
                support_file: true
              )
            ]
          end

          it "uses static candidate selection instead of dropping an extra index" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
            expect(pip_invocations).to be_empty
          end
        end
      end

      context "when Pipfile changes the effective registry list" do
        before do
          stub_request(:get, "https://private.example.com/simple/django/")
            .to_return(status: 200, body: pypi_response)
        end

        let(:dependency_files) do
          [
            requirements_file,
            python_version_file,
            Dependabot::DependencyFile.new(
              name: "Pipfile",
              content: <<~PIPFILE
                [[source]]
                name = "private"
                url = "https://private.example.com/simple"
                verify_ssl = true
              PIPFILE
            )
          ]
        end

        it "uses static candidate selection" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
          expect(pip_invocations).to be_empty
        end
      end

      context "when Poetry changes the effective registry list" do
        before do
          stub_request(:get, "https://private.example.com/simple/django/")
            .to_return(status: 200, body: pypi_response)
        end

        let(:dependency_files) do
          [
            requirements_file,
            python_version_file,
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: <<~PYPROJECT
                [tool.poetry]
                name = "example"
                version = "0.1.0"

                [[tool.poetry.source]]
                name = "private"
                url = "https://private.example.com/simple"
                default = true
              PYPROJECT
            )
          ]
        end

        it "uses static candidate selection" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
          expect(pip_invocations).to be_empty
        end
      end

      context "when pip cannot resolve any eligible version" do
        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
            .with(a_string_including("pip install"), any_args)
            .and_raise(
              Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "ERROR: ResolutionImpossible",
                error_context: {}
              )
            )
        end

        it { is_expected.to be_nil }
      end

      context "when pip cannot inspect legacy build metadata" do
        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
            .with(a_string_including("pip install"), any_args)
            .and_raise(
              Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "ERROR: Failed to build 'numpy' when getting requirements to build wheel",
                error_context: {}
              )
            )
        end

        it "uses static candidate selection" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        end
      end

      context "when pip cannot load a legacy setuptools backend" do
        before do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
            .with(a_string_including("pip install"), any_args)
            .and_raise(
              Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "BackendUnavailable: Cannot import 'setuptools.build_meta'",
                error_context: {}
              )
            )
        end

        it "uses static candidate selection" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        end
      end
    end

    context "with local wheel fixtures that require pip to backtrack" do
      let(:dependency_name) { "resolver-target" }
      let(:dependency_version) { "1.0.0" }
      let(:dependency_requirements) do
        [{ file: "requirements.txt", requirement: "==1.0.0", groups: [], source: nil }]
      end
      let(:python_version_content) do
        "#{Dependabot::Python::Language::PRE_INSTALLED_HIGHEST_VERSION}\n"
      end
      let(:wheel_fixture_path) do
        File.expand_path("../../../fixtures/pip_resolver/wheels", __dir__)
      end
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: <<~REQUIREMENTS
            --no-index
            --find-links #{wheel_fixture_path}
            resolver-target==1.0.0
            resolver-peer==1.0.0
          REQUIREMENTS
        )
      end
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:helper_declarations) do
        target = super().first.merge(
          "source" => { "start_line" => 3, "end_line" => 3 }
        )
        [
          target,
          {
            "name" => "resolver-peer",
            "version" => "1.0.0",
            "markers" => nil,
            "file" => "requirements.txt",
            "requirement" => "==1.0.0",
            "source_requirement" => "resolver-peer==1.0.0",
            "extras" => [],
            "constraint" => false,
            "editable" => false,
            "local" => false,
            "hashes" => [],
            "source" => { "start_line" => 4, "end_line" => 4 }
          }
        ]
      end

      before do
        allow(resolver.send(:latest_version_finder)).to receive_messages(
          eligible_versions: [
            Dependabot::Python::Version.new("2.0.0"),
            Dependabot::Python::Version.new("3.0.0")
          ],
          resolver_excluded_versions: []
        )
        allow(resolver.send(:language_version_manager)).to receive(:install_required_python)
      end

      it "selects the older eligible target required by the peer wheel" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("2.0.0"))
      end
    end

    context "when the helper marks the component partial for an attached editable" do
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4\n-e./local-package\n"
        )
      end

      let(:helper_component_reasons) { ["local_path"] }

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when a target-only constraint would become an artificial root" do
      let(:dependency_requirements) do
        [{ file: "constraints.txt", requirement: "==1.2.4", groups: [], source: nil }]
      end
      let(:requirements_file) do
        Dependabot::DependencyFile.new(name: "constraints.txt", content: "django==1.2.4\n")
      end
      let(:helper_declarations) do
        [super().first.merge("file" => "constraints.txt", "constraint" => true)]
      end
      let(:helper_files) { [{ "path" => "constraints.txt", "component_id" => "component-0" }] }
      let(:helper_roots) { ["constraints.txt"] }
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when the complete component contains hashes" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:helper_declarations) do
        [
          super().first.merge("hashes" => ["sha256:abc123"])
        ]
      end

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when the complete component contains a non-Python marker" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:helper_declarations) do
        [
          super().first.merge("markers" => "sys_platform == \"win32\"")
        ]
      end

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when pip decoding changes the component's source-span layout" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:helper_component_source_spans_applicable?) { false }

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when the parser retains a Python membership marker" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4; python_version in \"3.10\"\n"
        )
      end
      let(:helper_declarations) do
        [
          super().first.merge(
            "markers" => "python_version in \"3.10\"",
            "source_requirement" => "django==1.2.4; python_version in \"3.10\""
          )
        ]
      end
      let(:dependency) do
        Dependabot::Python::FileParser.new(
          dependency_files: dependency_files,
          source: Dependabot::Source.new(provider: "github", repo: "dependabot/dependabot-core", directory: "/"),
          reject_external_code: false
        ).parse.fetch(0)
      end

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when the parser retains a reversed Python comparison" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4; \"3.10\" > python_version\n"
        )
      end
      let(:helper_declarations) do
        [
          super().first.merge(
            "markers" => "\"3.10\" > python_version",
            "source_requirement" => "django==1.2.4; \"3.10\" > python_version"
          )
        ]
      end
      let(:dependency) do
        Dependabot::Python::FileParser.new(
          dependency_files: dependency_files,
          source: Dependabot::Source.new(provider: "github", repo: "dependabot/dependabot-core", directory: "/"),
          reject_external_code: false
        ).parse.fetch(0)
      end

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when the parser retains a variable-to-variable Python comparison" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4; python_version == python_full_version\n"
        )
      end
      let(:helper_declarations) do
        [
          super().first.merge(
            "markers" => "python_version == python_full_version",
            "source_requirement" => "django==1.2.4; python_version == python_full_version"
          )
        ]
      end
      let(:dependency) do
        Dependabot::Python::FileParser.new(
          dependency_files: dependency_files,
          source: Dependabot::Source.new(provider: "github", repo: "dependabot/dependabot-core", directory: "/"),
          reject_external_code: false
        ).parse.fetch(0)
      end

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when the parser retains an unsupported Python comparison operator" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4; python_version ~= \"3.10.0\"\n"
        )
      end
      let(:helper_declarations) do
        [
          super().first.merge(
            "markers" => "python_version ~= \"3.10.0\"",
            "source_requirement" => "django==1.2.4; python_version ~= \"3.10.0\""
          )
        ]
      end
      let(:dependency) do
        Dependabot::Python::FileParser.new(
          dependency_files: dependency_files,
          source: Dependabot::Source.new(provider: "github", repo: "dependabot/dependabot-core", directory: "/"),
          reject_external_code: false
        ).parse.fetch(0)
      end

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when the parser retains a wildcard Python comparison" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4; python_version != \"3.11.*\"\n"
        )
      end
      let(:helper_declarations) do
        [
          super().first.merge(
            "markers" => "python_version != \"3.11.*\"",
            "source_requirement" => "django==1.2.4; python_version != \"3.11.*\""
          )
        ]
      end
      let(:dependency) do
        Dependabot::Python::FileParser.new(
          dependency_files: dependency_files,
          source: Dependabot::Source.new(provider: "github", repo: "dependabot/dependabot-core", directory: "/"),
          reject_external_code: false
        ).parse.fetch(0)
      end

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when the complete component contains an extra marker" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:helper_declarations) do
        [
          super().first.merge("markers" => "extra == \"web\"")
        ]
      end

      it "uses static candidate selection" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command).with(a_string_including("pip install"), any_args)
      end
    end

    context "when the current version has a local label" do
      let(:dependency_version) { "1.2.4+gc.1" }
      let(:dependency_requirements) do
        [{ file: "requirements.txt", requirement: "==1.2.4+gc.1", groups: [], source: nil }]
      end

      it "uses static candidate selection before invoking the helper" do
        expect(Dependabot::Python::RequirementsFileParser).not_to receive(:new)

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
      end
    end

    context "when a fetched file path escapes the temporary directory" do
      let(:dependency_files) do
        [
          requirements_file,
          Dependabot::DependencyFile.new(
            name: "../local-project/setup.py",
            content: "from setuptools import setup\nsetup()\n",
            support_file: true
          )
        ]
      end

      it "uses static candidate selection before invoking the helper" do
        expect(Dependabot::Python::RequirementsFileParser).not_to receive(:new)

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
      end
    end

    context "when the target requirement file was not fetched" do
      let(:dependency_files) { [python_version_file] }

      it "uses static candidate selection before invoking the helper" do
        expect(Dependabot::Python::RequirementsFileParser).not_to receive(:new)

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
      end
    end

    context "when the package manager is not pip" do
      before do
        allow(dependency).to receive_messages(
          package_manager: "uv",
          numeric_version: Dependabot::Python::Version.new("1.2.4")
        )
        allow(resolver.send(:latest_version_finder)).to receive_messages(
          eligible_versions: [Dependabot::Python::Version.new("3.2.4")],
          resolver_excluded_versions: []
        )
      end

      it "does not invoke native pip resolution" do
        expect(Dependabot::Python::RequirementsFileParser).not_to receive(:new)

        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
      end
    end

    context "when the requirements helper fails unexpectedly" do
      let(:helper_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Unexpected helper failure",
          error_context: {}
        )
      end

      before { allow(requirements_parser).to receive(:parse).and_raise(helper_error) }

      it "preserves the helper error" do
        expect { latest_resolvable_version }.to raise_error(helper_error)
      end
    end

    context "with no indication of the Python version" do
      let(:dependency_files) { [requirements_file] }

      it { is_expected.to eq(Gem::Version.new("3.2.4")) }
    end

    context "with a .python-version file" do
      let(:dependency_files) { [requirements_file, python_version_file] }
      let(:python_version_content) { "3.11.0\n" }

      it { is_expected.to eq(Gem::Version.new("3.2.4")) }

      context "when the version is set to the oldest version of python supported by Dependabot" do
        let(:python_version_content) { "3.10.0\n" }

        it { is_expected.to eq(Gem::Version.new("3.2.4")) }
      end

      context "when the version is set to a python version no longer supported by Dependabot" do
        let(:python_version_content) { "3.9.0\n" }

        it "raises a helpful error" do
          expect { latest_resolvable_version }.to raise_error(Dependabot::ToolVersionNotSupported) do |err|
            expect(err.message).to start_with(
              "Dependabot detected the following Python requirement for your project: '3.9.0'."
            )
          end
        end
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { resolver.latest_resolvable_version_with_no_unlock }

    it { is_expected.to eq(Gem::Version.new("1.2.4")) }
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject(:lowest_resolvable_security_fix_version) { resolver.lowest_resolvable_security_fix_version }

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "pip",
          vulnerable_versions: [Dependabot::Python::Requirement.new("<= 2.1.0")]
        )
      ]
    end

    it { is_expected.to eq(Gem::Version.new("2.1.1")) }

    context "when a peer requires a higher safe version" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:attempted_requirements) { [] }

      before do
        allow(resolver.send(:latest_version_finder)).to receive(:eligible_security_fix_versions).and_return(
          [
            Dependabot::Python::Version.new("2.1.1"),
            Dependabot::Python::Version.new("2.2.0"),
            Dependabot::Python::Version.new("2.2.1")
          ]
        )
        allow(resolver.send(:language_version_manager)).to receive(:install_required_python)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_wrap_original do |method, command, **args|
          next method.call(command, **args) unless command.include?("pip install")

          requirement = File.read("requirements.txt")
          attempted_requirements << requirement
          if requirement.include?("==2.1.1")
            raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "ERROR: ResolutionImpossible",
              error_context: {}
            )
          end

          File.write(
            "dependabot-pip-report.json",
            JSON.dump("install" => [{ "metadata" => { "name" => "Django", "version" => "2.2.0" } }])
          )
          ""
        end
      end

      context "when the source requirement excludes the minimum safe version" do
        let(:helper_component_status) { "complete" }
        let(:helper_component_reasons) { [] }
        let(:dependency_requirements) do
          [{ file: "requirements.txt", requirement: ">=1.0,!=2.1.1,<3.0", groups: [], source: nil }]
        end
        let(:requirements_file) do
          Dependabot::DependencyFile.new(
            name: "requirements.txt",
            content: "django>=1.0,!=2.1.1,<3.0\n"
          )
        end
        let(:attempted_requirements) { [] }

        before do
          allow(resolver.send(:latest_version_finder)).to receive(:eligible_security_fix_versions).and_return(
            [
              Dependabot::Python::Version.new("2.1.1"),
              Dependabot::Python::Version.new("2.2.0")
            ]
          )
          allow(resolver.send(:language_version_manager)).to receive(:install_required_python)
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_wrap_original do |method, command, **args|
            next method.call(command, **args) unless command.include?("pip install")

            requirement = File.read("requirements.txt")
            attempted_requirements << requirement
            if requirement.include?("==2.1.1")
              raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "ERROR: ResolutionImpossible",
                error_context: {}
              )
            end

            File.write(
              "dependabot-pip-report.json",
              JSON.dump("install" => [{ "metadata" => { "name" => "Django", "version" => "2.2.0" } }])
            )
            ""
          end
        end

        it "retains the exclusion while trying exact candidates" do
          expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.2.0"))
          expect(attempted_requirements.first).to include("django==2.1.1,!=2.1.1")
          expect(attempted_requirements[1]).to include("django==2.2.0,!=2.1.1")
        end
      end

      it "tries non-vulnerable releases in ascending order until one resolves" do
        expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.2.0"))
        expect(attempted_requirements.length).to eq(2)
        expect(attempted_requirements.first).to include("django==2.1.1")
        expect(attempted_requirements[1]).to include("django==2.2.0")
      end
    end

    context "when an unchanged peer is unavailable for the selected Python" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:peer_marker) { nil }
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4\nnumpy==1.0\n"
        )
      end
      let(:helper_declarations) do
        [
          super().first,
          {
            "name" => "numpy",
            "version" => "1.0",
            "markers" => peer_marker,
            "file" => "requirements.txt",
            "requirement" => "==1.0",
            "source_requirement" => "numpy==1.0",
            "extras" => [],
            "constraint" => false,
            "editable" => false,
            "local" => false,
            "hashes" => [],
            "source" => { "start_line" => 2, "end_line" => 2 }
          }
        ]
      end

      before do
        allow(resolver.send(:latest_version_finder)).to receive(:eligible_security_fix_versions).and_return(
          [
            Dependabot::Python::Version.new("2.1.1"),
            Dependabot::Python::Version.new("2.2.0")
          ]
        )
        allow(resolver.send(:language_version_manager)).to receive(:install_required_python)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(a_string_including("pip install"), any_args)
          .and_raise(
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "ERROR: No matching distribution found for numpy==1.0",
              error_context: {}
            )
          )
      end

      it "keeps the minimum safe static candidate" do
        expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.1.1"))
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command).with(a_string_including("pip install"), any_args).once
      end

      context "when the helper serializes the absent peer marker as None" do
        let(:peer_marker) { "None" }

        it "keeps the minimum safe static candidate" do
          expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.1.1"))
          expect(Dependabot::SharedHelpers)
            .to have_received(:run_shell_command).with(a_string_including("pip install"), any_args).once
        end
      end
    end

    context "when a security candidate introduces an unavailable dependency" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:attempted_requirements) { [] }
      let(:missing_requirement) { "candidate-only-package>=1.0" }
      let(:peer_declarations) { [] }
      let(:helper_declarations) { super() + peer_declarations }
      let(:peer_requirement_line) { nil }
      let(:requirements_file) do
        content = ["django==1.2.4", peer_requirement_line].compact.join("\n")
        Dependabot::DependencyFile.new(name: "requirements.txt", content: "#{content}\n")
      end

      before do
        allow(resolver.send(:latest_version_finder)).to receive(:eligible_security_fix_versions).and_return(
          [
            Dependabot::Python::Version.new("2.1.1"),
            Dependabot::Python::Version.new("2.2.0")
          ]
        )
        allow(resolver.send(:language_version_manager)).to receive(:install_required_python)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_wrap_original do |method, command, **args|
          next method.call(command, **args) unless command.include?("pip install")

          requirement = File.read("requirements.txt")
          attempted_requirements << requirement
          if requirement.include?("==2.1.1")
            raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "ERROR: No matching distribution found for #{missing_requirement}",
              error_context: {}
            )
          end

          File.write(
            "dependabot-pip-report.json",
            JSON.dump("install" => [{ "metadata" => { "name" => "Django", "version" => "2.2.0" } }])
          )
          ""
        end
      end

      it "tries the next safe candidate" do
        expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.2.0"))
        expect(attempted_requirements.length).to eq(2)
      end

      context "when an active unchanged peer has a different requirement" do
        let(:missing_requirement) { "peer>=9" }
        let(:peer_requirement_line) { "peer>=1" }
        let(:peer_declarations) do
          [
            {
              "name" => "peer",
              "version" => nil,
              "markers" => nil,
              "file" => "requirements.txt",
              "requirement" => ">=1",
              "source_requirement" => "peer>=1",
              "extras" => [],
              "constraint" => false,
              "editable" => false,
              "local" => false,
              "hashes" => [],
              "source" => { "start_line" => 2, "end_line" => 2 }
            }
          ]
        end

        it "does not attribute the candidate requirement to the unchanged peer" do
          expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.2.0"))
          expect(attempted_requirements.length).to eq(2)
        end
      end

      context "when the matching unchanged declaration is a constraint" do
        let(:missing_requirement) { "peer>=9" }
        let(:requirements_file) do
          Dependabot::DependencyFile.new(name: "requirements.txt", content: "django==1.2.4\n-c constraints.txt\n")
        end
        let(:constraints_file) do
          Dependabot::DependencyFile.new(name: "constraints.txt", content: "peer>=9\n")
        end
        let(:dependency_files) { [requirements_file, constraints_file, python_version_file] }
        let(:helper_files) do
          [
            { "path" => "constraints.txt", "component_id" => "component-0" },
            { "path" => "requirements.txt", "component_id" => "component-0" }
          ]
        end
        let(:helper_edges) do
          [
            {
              "from" => "requirements.txt",
              "to" => "constraints.txt",
              "type" => "constraint",
              "remote" => false,
              "source" => { "start_line" => 2, "end_line" => 2 }
            }
          ]
        end
        let(:peer_declarations) do
          [
            {
              "name" => "peer",
              "version" => nil,
              "markers" => nil,
              "file" => "constraints.txt",
              "requirement" => ">=9",
              "source_requirement" => "peer>=9",
              "extras" => [],
              "constraint" => true,
              "editable" => false,
              "local" => false,
              "hashes" => [],
              "source" => { "start_line" => 1, "end_line" => 1 }
            }
          ]
        end

        it "tries the next safe candidate" do
          expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.2.0"))
          expect(attempted_requirements.length).to eq(2)
        end
      end

      context "when the matching unchanged install requirement has an inactive marker" do
        let(:missing_requirement) { "peer>=9" }
        let(:peer_requirement_line) { "peer>=9; python_version < \"3.0\"" }
        let(:peer_declarations) do
          [
            {
              "name" => "peer",
              "version" => nil,
              "markers" => "python_version < \"3.0\"",
              "file" => "requirements.txt",
              "requirement" => ">=9",
              "source_requirement" => "peer>=9; python_version < \"3.0\"",
              "extras" => [],
              "constraint" => false,
              "editable" => false,
              "local" => false,
              "hashes" => [],
              "source" => { "start_line" => 2, "end_line" => 2 }
            }
          ]
        end

        it "tries the next safe candidate" do
          expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.2.0"))
          expect(attempted_requirements.length).to eq(2)
        end
      end
    end

    context "when a dormant constraint excludes the minimum safe version" do
      let(:helper_component_status) { "complete" }
      let(:helper_component_reasons) { [] }
      let(:dependency_requirements) do
        [{ file: "constraints.txt", requirement: ">=1.0,!=2.1.0.*,<3.0", groups: [], source: nil }]
      end
      let(:requirements_file) do
        Dependabot::DependencyFile.new(name: "requirements.txt", content: "-c constraints.txt\n")
      end
      let(:constraints_file) do
        Dependabot::DependencyFile.new(
          name: "constraints.txt",
          content: "django>=1.0,!=2.1.0.*,<3.0\n"
        )
      end
      let(:dependency_files) { [requirements_file, constraints_file, python_version_file] }
      let(:helper_declarations) do
        [
          super().first.merge(
            "file" => "constraints.txt",
            "requirement" => ">=1.0,!=2.1.0.*,<3.0",
            "source_requirement" => "django>=1.0,!=2.1.0.*,<3.0",
            "constraint" => true
          )
        ]
      end
      let(:helper_files) do
        [
          { "path" => "constraints.txt", "component_id" => "component-0" },
          { "path" => "requirements.txt", "component_id" => "component-0" }
        ]
      end
      let(:helper_edges) do
        [
          {
            "from" => "requirements.txt",
            "to" => "constraints.txt",
            "type" => "constraint",
            "remote" => false,
            "source" => { "start_line" => 1, "end_line" => 1 }
          }
        ]
      end
      let(:helper_roots) { ["requirements.txt"] }
      let(:attempted_requirements) { [] }

      before do
        allow(resolver.send(:latest_version_finder)).to receive(:eligible_security_fix_versions).and_return(
          [
            Dependabot::Python::Version.new("2.1"),
            Dependabot::Python::Version.new("2.2.0")
          ]
        )
        allow(resolver.send(:language_version_manager)).to receive(:install_required_python)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_wrap_original do |method, command, **args|
          next method.call(command, **args) unless command.include?("pip install")

          attempted_requirements << File.read("constraints.txt")
          File.write("dependabot-pip-report.json", JSON.dump("install" => []))
          ""
        end
      end

      it "continues to the first candidate admitted by the source requirement" do
        expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.2.0"))
        expect(attempted_requirements).to contain_exactly(
          include("django==2.1,!=2.1.0.*"),
          include("django==2.2.0,!=2.1.0.*")
        )
      end
    end

    context "with a .python-version file" do
      let(:dependency_files) { [requirements_file, python_version_file] }
      let(:python_version_content) { "3.11.0\n" }

      it { is_expected.to eq(Gem::Version.new("2.1.1")) }

      context "when the version is set to the oldest version of python supported by Dependabot" do
        let(:python_version_content) { "3.10.0\n" }

        it { is_expected.to eq(Gem::Version.new("2.1.1")) }
      end

      context "when version is set to a python version no longer supported by Dependabot" do
        let(:python_version_content) { "3.9.0\n" }

        it "raises a helpful error" do
          expect { lowest_resolvable_security_fix_version }.to raise_error(Dependabot::ToolVersionNotSupported) do |err|
            expect(err.message).to start_with(
              "Dependabot detected the following Python requirement for your project: '3.9.0'."
            )
          end
        end
      end
    end
  end
end
