# typed: false
# Sorbet cannot resolve the child-context updated_lockfile_content fixture. https://srb.help/7003
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/pipenv_runner"
require "dependabot/python/language_version_manager"

RSpec.describe Dependabot::Python::PipenvRunner do
  let(:runner) do
    described_class.new(
      dependency: dependency,
      lockfile: lockfile,
      language_version_manager: language_version_manager,
      dependency_files: dependency_files,
      repo_contents_path: repo_contents_path
    )
  end

  let(:language_version_manager) do
    instance_double(
      Dependabot::Python::LanguageVersionManager,
      python_major_minor: "3.11",
      install_required_python: nil
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "requests",
      version: "2.18.0",
      requirements: requirements,
      package_manager: "pip"
    )
  end

  let(:requirements) do
    [{
      file: "Pipfile",
      requirement: "==2.18.0",
      groups: ["default"],
      source: nil
    }]
  end

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "Pipfile.lock",
      content: lockfile_content
    )
  end

  let(:lockfile_content) do
    JSON.generate(
      {
        "default" => {
          "requests" => { "version" => "==2.18.0" }
        },
        "develop" => {}
      }
    )
  end

  let(:dependency_files) { nil }
  let(:repo_contents_path) { nil }

  describe "#run_upgrade" do
    let(:requirements) { [] }
    let(:lockfile_content) do
      JSON.generate(
        "default" => { "requests" => { "version" => "==2.19.0" } },
        "develop" => { "requests" => { "version" => "==2.18.0" } }
      )
    end

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")
    end

    it "upgrades the section containing the dependency's current version" do
      runner.run_upgrade("==2.19.0")

      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
        .with("pyenv exec pipenv upgrade --verbose requests==2.19.0 --dev", anything)
    end

    context "when the dependency is locked to a non-default index" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "test-mybug",
          version: "0.0.1",
          requirements: [{
            file: "Pipfile",
            requirement: "*",
            groups: ["default"],
            source: nil
          }],
          package_manager: "pip"
        )
      end
      let(:dependency_files) { [pipfile, lockfile] }
      let(:pipfile) do
        Dependabot::DependencyFile.new(
          name: "Pipfile",
          content: <<~PIPFILE
            [[source]]
            url = "https://pypi.org/simple"
            verify_ssl = true
            name = "pypi"

            [[source]]
            url = "https://test.pypi.org/simple/"
            verify_ssl = true
            name = "testpypi"

            [packages]
            django = "*"
            test-mybug = {version = "*", index = "testpypi"}
          PIPFILE
        )
      end
      let(:lockfile_content) do
        JSON.generate(
          {
            "_meta" => {
              "sources" => [
                { "name" => "pypi", "url" => "https://pypi.org/simple", "verify_ssl" => true },
                { "name" => "testpypi", "url" => "https://test.pypi.org/simple/", "verify_ssl" => true }
              ]
            },
            "default" => { "test-mybug" => { "version" => "==0.0.1", "index" => "testpypi" } },
            "develop" => {}
          }
        )
      end

      it "passes the declared index when upgrading the package" do
        runner.run_upgrade("==0.0.2")

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(
            ["pyenv", "exec", "pipenv", "upgrade", "--verbose", "--index", "testpypi", "test-mybug==0.0.2"],
            anything
          )
      end

      context "with a transitive dependency whose lockfile name is normalized" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "python-decouple",
            version: "3.1",
            requirements: [],
            package_manager: "pip",
            metadata: { original_name: "python_decouple" }
          )
        end
        let(:dependency_files) { [pipfile, lockfile] }
        let(:pipfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile",
            content: "[packages]\nrequests = \"*\"\n"
          )
        end
        let(:lockfile_content) do
          JSON.generate(
            "default" => { "python-decouple" => { "version" => "==3.1", "index" => "testpypi" } },
            "develop" => {}
          )
        end

        it "selects the section and index using the normalized name" do
          runner.run_upgrade("==3.2")

          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
            .with(
              ["pyenv", "exec", "pipenv", "upgrade", "--verbose", "--index", "testpypi", "python_decouple==3.2"],
              anything
            )
        end
      end

      context "when the Pipfile entry has no explicit index" do
        let(:pipfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile",
            content: "[packages]\ntest-mybug = \"*\"\n"
          )
        end
        let(:lockfile_content) do
          JSON.generate(
            "default" => { "test-mybug" => { "version" => "==0.0.1", "index" => "stale-index" } },
            "develop" => {}
          )
        end

        it "does not reuse the stale lockfile index" do
          runner.run_upgrade("==0.0.2")

          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
            .with("pyenv exec pipenv upgrade --verbose test-mybug==0.0.2", anything)
        end
      end

      context "without a lockfile" do
        let(:lockfile) { nil }
        let(:dependency_files) { [pipfile] }
        let(:pipfile) do
          Dependabot::DependencyFile.new(
            name: "Pipfile",
            content: <<~PIPFILE
              [[source]]
              url = "https://test.pypi.org/simple/"
              verify_ssl = true
              name = "test pypi"

              [packages]
              test-mybug = {version = "*", index = "test pypi"}
            PIPFILE
          )
        end

        it "preserves the Pipfile index as a single command argument" do
          runner.run_upgrade("==0.0.2")

          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
            .with(
              ["pyenv", "exec", "pipenv", "upgrade", "--verbose", "--index", "test pypi", "test-mybug==0.0.2"],
              anything
            )
        end
      end
    end

    context "when generating updated dependency files" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.19.0",
          previous_version: "2.18.0",
          requirements: [],
          previous_requirements: [],
          package_manager: "pip"
        )
      end

      it "selects the section using the previous version rather than the target version" do
        runner.run_upgrade("==2.19.0")

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with("pyenv exec pipenv upgrade --verbose requests==2.19.0 --dev", anything)
      end
    end

    context "when the pipenv command fails" do
      let(:error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "failed", error_context: {})
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(start_with("pyenv exec pipenv upgrade"), anything)
          .and_raise(error)
      end

      it "attaches the command name and index host without the command line" do
        expect { runner.run_upgrade("==2.19.0") }.to raise_error(error)

        context = Dependabot::ErrorReportContext.build(error: error)
        expect(context).to include("command-name" => "pipenv upgrade", "index-hosts" => ["pypi.org"])
        expect(context.values.flatten.join(" ")).not_to include("requests", "--verbose")
      end

      context "when the index is configured only in the Pipfile" do
        let(:dependency_files) do
          [
            Dependabot::DependencyFile.new(
              name: "Pipfile",
              content: "[[source]]\nname = \"internal\"\nurl = \"https://pipfile.example.com/simple\"\n"
            ),
            lockfile
          ]
        end

        it "reports the Pipfile index host" do
          expect { runner.run_upgrade("==2.19.0") }.to raise_error(error)

          expect(Dependabot::ErrorReportContext.build(error: error))
            .to include("index-hosts" => ["pipfile.example.com"])
        end
      end
    end
  end

  describe "#run_upgrade_and_fetch_version" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("Pipfile.lock").and_return(updated_lockfile_content)
    end

    context "when the lockfile section is a valid Hash" do
      let(:updated_lockfile_content) do
        JSON.generate(
          {
            "default" => {
              "requests" => { "version" => "==2.19.0" }
            }
          }
        )
      end

      it "returns the version" do
        expect(runner.run_upgrade_and_fetch_version(">=2.19.0")).to eq("2.19.0")
      end
    end

    context "when the lockfile section contains a String instead of a Hash" do
      let(:updated_lockfile_content) do
        JSON.generate(
          {
            "default" => "some-string-value",
            "develop" => {}
          }
        )
      end

      it "returns nil instead of raising TypeError" do
        expect(runner.run_upgrade_and_fetch_version(">=2.19.0")).to be_nil
      end
    end

    context "when the lockfile section is nil" do
      let(:updated_lockfile_content) do
        JSON.generate(
          {
            "develop" => {}
          }
        )
      end

      it "returns nil" do
        expect(runner.run_upgrade_and_fetch_version(">=2.19.0")).to be_nil
      end
    end

    context "when the original lockfile section contains a String instead of a Hash" do
      let(:lockfile_content) do
        JSON.generate(
          {
            "default" => "some-string-value",
            "develop" => {}
          }
        )
      end

      let(:updated_lockfile_content) do
        JSON.generate(
          {
            "default" => {
              "requests" => { "version" => "==2.19.0" }
            }
          }
        )
      end

      it "returns the version without trying to read dependency extras from the malformed section" do
        expect(runner.run_upgrade_and_fetch_version(">=2.19.0")).to eq("2.19.0")
      end
    end

    context "when the dependency has no requirements and the original default section is malformed" do
      let(:requirements) { [] }

      let(:lockfile_content) do
        JSON.generate(
          {
            "default" => "some-string-value",
            "develop" => {
              "requests" => { "version" => "==2.18.0" }
            }
          }
        )
      end

      let(:updated_lockfile_content) do
        JSON.generate(
          {
            "default" => "some-string-value",
            "develop" => {
              "requests" => { "version" => "==2.19.0" }
            }
          }
        )
      end

      it "finds the dependency in the valid section" do
        expect(runner.run_upgrade_and_fetch_version(">=2.19.0")).to eq("2.19.0")
      end
    end

    context "when the dependency has no requirements and no valid section contains it" do
      let(:requirements) { [] }

      let(:lockfile_content) do
        JSON.generate(
          {
            "default" => "some-string-value",
            "develop" => []
          }
        )
      end

      let(:updated_lockfile_content) do
        JSON.generate(
          {
            "default" => "some-string-value",
            "develop" => []
          }
        )
      end

      it "returns nil" do
        expect(runner.run_upgrade_and_fetch_version(">=2.19.0")).to be_nil
      end
    end
  end

  describe "#run_pipenv_graph" do
    context "when the repository contains a local path dependency" do
      let(:repo_contents_path) { Dir.mktmpdir }
      let(:commands) { [] }
      let(:python_version) { "3.10" }
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "Pipfile",
            content: "[packages]\nlocal-package = {path = \"./local-package\"}\n",
            directory: "/project"
          ),
          Dependabot::DependencyFile.new(
            name: "Pipfile.lock",
            content: "{}",
            directory: "/project"
          ),
          Dependabot::DependencyFile.new(
            name: ".python-version",
            content: "3.9\n",
            directory: "/project"
          )
        ]
      end

      before do
        FileUtils.mkdir_p(File.join(repo_contents_path, "project", "local-package"))
        File.write(File.join(repo_contents_path, "project", "local-package", "setup.py"), "")
        File.write(File.join(repo_contents_path, "project", ".python-version"), "3.9\n")
        allow(language_version_manager).to receive(:python_major_minor).and_return(python_version)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, **_options|
          commands << [command, Dir.pwd]
          next "" if command.start_with?("git ")

          command.include?("pipenv graph") ? "[]" : ""
        end
      end

      after do
        FileUtils.rm_rf(repo_contents_path)
      end

      it "runs Pipenv from the checked out repository" do
        expect(runner.run_pipenv_graph).to eq("[]")
        pipenv_commands = commands.reject { |command, _directory| command.start_with?("git ") }

        expect(pipenv_commands.map(&:last)).to all(eq(File.join(repo_contents_path, "project")))
        expect(File).to exist(File.join(repo_contents_path, "project", "local-package", "setup.py"))
        expect(File.read(File.join(repo_contents_path, "project", ".python-version"))).to eq(python_version)
      end
    end
  end
end
