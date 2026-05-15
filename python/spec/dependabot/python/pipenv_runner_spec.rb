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
      language_version_manager: language_version_manager
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
      requirements: [{
        file: "Pipfile",
        requirement: "==2.18.0",
        groups: ["default"],
        source: nil
      }],
      package_manager: "pip"
    )
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
  end
end
