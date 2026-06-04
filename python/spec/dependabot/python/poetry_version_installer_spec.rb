# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/poetry_version_installer"

RSpec.describe Dependabot::Python::PoetryVersionInstaller do
  subject(:installer) { described_class.new(pyproject_content: pyproject_content) }

  let(:pyproject_content) do
    <<~TOML
      [tool.poetry]
      name = "demo"
      version = "0.0.1"
      requires-poetry = ">=2.1.3"
    TOML
  end

  before do
    Dependabot::Experiments.reset!
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe ".from_dependency_files" do
    it "extracts pyproject.toml content from dependency files" do
      pyproject = Dependabot::DependencyFile.new(name: "pyproject.toml", content: pyproject_content)
      other_file = Dependabot::DependencyFile.new(name: "poetry.lock", content: "")

      Dependabot::Experiments.register(:enable_poetry_version_install, true)

      installer = described_class.from_dependency_files([pyproject, other_file])

      expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "pyenv exec poetry self update 2.1.3",
        fingerprint: "pyenv exec poetry self update <version>"
      )
      installer.install_required_version
    end

    it "handles missing pyproject.toml gracefully" do
      Dependabot::Experiments.register(:enable_poetry_version_install, true)
      other_file = Dependabot::DependencyFile.new(name: "requirements.txt", content: "")
      installer = described_class.from_dependency_files([other_file])

      expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)
      installer.install_required_version
    end
  end

  describe "#install_required_version" do
    context "when the feature flag is disabled" do
      it "does not install anything" do
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)
        installer.install_required_version
      end
    end

    context "when the feature flag is enabled" do
      before { Dependabot::Experiments.register(:enable_poetry_version_install, true) }

      context "with a >= constraint" do
        it "installs the lower-bound version" do
          expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
            "pyenv exec poetry self update 2.1.3",
            fingerprint: "pyenv exec poetry self update <version>"
          )

          installer.install_required_version
        end

        it "only installs once across repeated calls" do
          expect(Dependabot::SharedHelpers).to receive(:run_shell_command).once
          installer.install_required_version
          installer.install_required_version
        end
      end

      context "with an == pinned constraint" do
        let(:pyproject_content) do
          <<~TOML
            [tool.poetry]
            requires-poetry = "==2.0.1"
          TOML
        end

        it "installs the pinned version" do
          expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
            "pyenv exec poetry self update 2.0.1",
            fingerprint: "pyenv exec poetry self update <version>"
          )

          installer.install_required_version
        end
      end

      context "with a complex multi-clause constraint" do
        let(:pyproject_content) do
          <<~TOML
            [tool.poetry]
            requires-poetry = ">=2.0,<3.0"
          TOML
        end

        it "installs the first concrete version found" do
          expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
            "pyenv exec poetry self update 2.0",
            fingerprint: "pyenv exec poetry self update <version>"
          )

          installer.install_required_version
        end
      end

      context "with no requires-poetry section" do
        let(:pyproject_content) do
          <<~TOML
            [tool.poetry]
            name = "demo"
          TOML
        end

        it "does not run any commands" do
          expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)
          installer.install_required_version
        end
      end

      context "with nil pyproject content" do
        let(:pyproject_content) { nil }

        it "does not run any commands" do
          expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)
          installer.install_required_version
        end
      end

      context "with invalid TOML content" do
        let(:pyproject_content) { "this is not valid toml {{{" }

        it "does not run any commands" do
          expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)
          installer.install_required_version
        end
      end

      context "with a constraint missing any concrete version" do
        let(:pyproject_content) do
          <<~TOML
            [tool.poetry]
            requires-poetry = "*"
          TOML
        end

        it "does not run any commands" do
          expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)
          installer.install_required_version
        end
      end

      context "with a constraint containing shell injection characters" do
        let(:pyproject_content) do
          <<~TOML
            [tool.poetry]
            requires-poetry = '>=2.0; rm -rf /'
          TOML
        end

        it "extracts only the safe numeric version" do
          expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
            "pyenv exec poetry self update 2.0",
            fingerprint: "pyenv exec poetry self update <version>"
          )

          installer.install_required_version
        end

        it "does not execute the injected command" do
          expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command).with(
            /rm -rf/,
            anything
          )

          allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          installer.install_required_version
        end
      end

      context "when poetry self update fails" do
        it "logs a warning and continues without raising" do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_raise(
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "Could not find a matching version of poetry",
              error_context: {}
            )
          )

          expect(Dependabot.logger).to receive(:warn).with(
            /Failed to install Poetry version 2.1.3/
          )

          expect { installer.install_required_version }.not_to raise_error
        end
      end
    end
  end
end
