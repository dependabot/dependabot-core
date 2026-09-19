# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/update_checker/pip_version_resolver"

RSpec.describe Dependabot::Python::UpdateChecker::PipVersionResolver do
  before do
    stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
  end

  let(:pypi_url) { "https://pypi.org/simple/luigi/" }
  let(:pypi_response) { fixture("pypi", "pypi_simple_response.html") }
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
  let(:dependency_files) { [requirements_file, python_version_file] }
  let(:requirements_file) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: fixture("requirements", requirements_fixture_name)
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
  let(:pypi_response) { fixture("pypi", "pypi_simple_response_django.html") }
  let(:pypi_url) { "https://pypi.org/simple/django/" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip"
    )
  end
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

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    context "when the latest version conflicts with another requirement" do
      let(:rewritten_requirements) { [] }
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4\ndjango-filter==23.5\n"
        )
      end

      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command) do |command, **_args|
          next "" unless command.include?("pip install")

          rewritten_requirements << File.read("requirements.txt")
          File.write(
            "dependabot-pip-report.json",
            JSON.dump(
              "install" => [{ "metadata" => { "name" => "Django", "version" => "3.2.3" } }]
            )
          )
          ""
        end
      end

      it "returns the newest version selected by pip" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.3"))
        expect(rewritten_requirements).to contain_exactly(include("django>1.2.4,<=3.2.4"))
      end
    end

    context "when a version below the policy ceiling is ignored" do
      let(:ignored_versions) { ["==3.2.3"] }
      let(:rewritten_requirements) { [] }
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4\ndjango-filter==23.5\n"
        )
      end

      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command) do |command, **_args|
          next "" unless command.include?("pip install")

          rewritten_requirements << File.read("requirements.txt")
          File.write(
            "dependabot-pip-report.json",
            JSON.dump(
              "install" => [{ "metadata" => { "name" => "Django", "version" => "3.2.2" } }]
            )
          )
          ""
        end
      end

      it "excludes the ignored version from pip's candidate range" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.2"))
        expect(rewritten_requirements).to contain_exactly(include("!=3.2.3"))
      end
    end

    context "when the existing requirement has a lower bound" do
      let(:dependency_version) { nil }
      let(:dependency_requirements) do
        [{
          file: "requirements.txt",
          requirement: ">=2.0,<3.0",
          groups: [],
          source: nil
        }]
      end
      let(:rewritten_requirements) { [] }
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django>=2.0,<3.0\ndjango-filter==23.5\n"
        )
      end

      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command) do |command, **_args|
          next "" unless command.include?("pip install")

          rewritten_requirements << File.read("requirements.txt")
          File.write(
            "dependabot-pip-report.json",
            JSON.dump(
              "install" => [{ "metadata" => { "name" => "Django", "version" => "3.2.3" } }]
            )
          )
          ""
        end
      end

      it "does not allow pip to select a downgrade" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.3"))
        expect(rewritten_requirements).to contain_exactly(include("django>=2.0,<=3.2.4"))
      end
    end

    context "when no policy-eligible version resolves" do
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4\ndjango-filter==23.5\n"
        )
      end

      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command) do |command, **_args|
          next "" unless command.include?("pip install")

          raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "ERROR: ResolutionImpossible",
            error_context: {}
          )
        end
      end

      it { is_expected.to be_nil }
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
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4\n"
        )
      end
      let(:pip_commands) { [] }
      let(:pip_environments) { [] }

      before do
        %w(private extra).each do |index|
          stub_request(:get, %r{https://#{index}\.example\.com/(?:pypi/django/json|simple/django/)})
            .to_return(status: 200, body: pypi_response)
        end
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command) do |command, **args|
          next "" unless command.include?("pip install")

          pip_commands << command
          pip_environments << args.fetch(:env)
          File.write(
            "dependabot-pip-report.json",
            JSON.dump(
              "install" => [{ "metadata" => { "name" => "Django", "version" => "3.2.4" } }]
            )
          )
          ""
        end
      end

      it "passes index credentials outside the logged command" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(pip_commands.length).to eq(1)
        expect(pip_commands.first).not_to include("private-user", "private-password")
        expect(pip_environments).to contain_exactly(
          include(
            "PIP_INDEX_URL" => "https://private-user:private-password@private.example.com/simple",
            "PIP_EXTRA_INDEX_URL" => "https://extra-user:extra-password@extra.example.com/simple"
          )
        )
      end
    end

    context "when the requirement file contains hashes" do
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: <<~REQUIREMENTS
            --require-hashes
            -r requirements/base.txt
            django==1.2.4 \\
                --hash=sha256:django-wheel \\
                --hash=sha256:django-sdist
          REQUIREMENTS
        )
      end
      let(:dependency_files) { [requirements_file, base_requirements_file, python_version_file] }
      let(:base_requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements/base.txt",
          content: "urllib3==1.26.20 --hash=sha256:urllib3-wheel\n"
        )
      end
      let(:resolver_files) { [] }

      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command) do |command, **_args|
          next "" unless command.include?("pip install")

          resolver_files << {
            requirements: File.read("requirements.txt"),
            base: File.read("requirements/base.txt")
          }
          File.write(
            "dependabot-pip-report.json",
            JSON.dump(
              "install" => [{ "metadata" => { "name" => "Django", "version" => "3.2.3" } }]
            )
          )
          ""
        end
      end

      it "resolves with hash-free temporary requirement files" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.3"))
        expect(resolver_files).to contain_exactly(
          {
            requirements: "-r requirements/base.txt\ndjango>1.2.4,<=3.2.4\n",
            base: "urllib3==1.26.20\n"
          }
        )
      end
    end

    context "when the dependency has declarations in multiple files" do
      let(:dependency_requirements) do
        [
          { file: "requirements.txt", requirement: "==1.2.4", groups: [], source: nil },
          { file: "constraints.txt", requirement: "==1.2.4", groups: [], source: nil }
        ]
      end
      let(:dependency_files) do
        [
          requirements_file,
          Dependabot::DependencyFile.new(name: "constraints.txt", content: "django==1.2.4\n")
        ]
      end

      before { allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original }

      it "uses the policy candidate without invoking pip" do
        expect(latest_resolvable_version).to eq(Gem::Version.new("3.2.4"))
        expect(Dependabot::SharedHelpers)
          .not_to have_received(:run_shell_command)
          .with(a_string_matching(/pip install/), any_args)
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
          vulnerable_versions: ["<= 2.1.0"]
        )
      ]
    end

    context "when the lowest safe version is resolvable" do
      let(:rewritten_requirements) { [] }
      let(:requirements_file) do
        Dependabot::DependencyFile.new(
          name: "requirements.txt",
          content: "django==1.2.4\n"
        )
      end

      before do
        allow(Dependabot::SharedHelpers)
          .to receive(:run_shell_command) do |command, **_args|
          next "" unless command.include?("pip install")

          rewritten_requirements << File.read("requirements.txt")
          File.write(
            "dependabot-pip-report.json",
            JSON.dump(
              "install" => [{ "metadata" => { "name" => "Django", "version" => "2.1.1" } }]
            )
          )
          ""
        end
      end

      it "checks the exact lowest safe version" do
        expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("2.1.1"))
        expect(rewritten_requirements).to contain_exactly(include("django==2.1.1"))
      end
    end

    it { is_expected.to eq(Gem::Version.new("2.1.1")) }

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
