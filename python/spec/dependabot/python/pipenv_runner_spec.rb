# typed: false
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
