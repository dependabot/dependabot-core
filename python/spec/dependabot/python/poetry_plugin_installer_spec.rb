# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/poetry_plugin_installer"

RSpec.describe Dependabot::Python::PoetryPluginInstaller do
  subject(:installer) { described_class.new(pyproject_content: pyproject_content) }

  describe ".from_dependency_files" do
    it "extracts pyproject.toml content from dependency files" do
      pyproject = Dependabot::DependencyFile.new(
        name: "pyproject.toml",
        content: fixture("pyproject_files", "requires_plugins.toml")
      )
      other_file = Dependabot::DependencyFile.new(
        name: "poetry.lock",
        content: ""
      )

      installer = described_class.from_dependency_files([pyproject, other_file])

      expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        /poetry self add/,
        fingerprint: anything
      )
      installer.install_required_plugins
    end

    it "handles missing pyproject.toml gracefully" do
      other_file = Dependabot::DependencyFile.new(
        name: "requirements.txt",
        content: "requests==2.28"
      )

      installer = described_class.from_dependency_files([other_file])

      expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)
      installer.install_required_plugins
    end
  end

  describe "#install_required_plugins" do
    context "with a single required plugin" do
      let(:pyproject_content) do
        fixture("pyproject_files", "requires_plugins.toml")
      end

      it "installs the declared plugin" do
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "pyenv exec poetry self add poetry-plugin-export@\\>\\=1.0",
          fingerprint: "pyenv exec poetry self add <plugin_name>@<constraint>"
        )

        installer.install_required_plugins
      end

      it "only installs plugins once" do
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command).once

        installer.install_required_plugins
        installer.install_required_plugins
      end
    end

    context "with multiple required plugins" do
      let(:pyproject_content) do
        fixture("pyproject_files", "requires_plugins_multiple.toml")
      end

      it "installs all declared plugins" do
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "pyenv exec poetry self add poetry-plugin-export@\\>\\=1.0",
          fingerprint: "pyenv exec poetry self add <plugin_name>@<constraint>"
        )
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "pyenv exec poetry self add poetry-plugin-shell@\\>\\=1.0,\\<2.0",
          fingerprint: "pyenv exec poetry self add <plugin_name>@<constraint>"
        )

        installer.install_required_plugins
      end
    end

    context "with no requires-plugins section" do
      let(:pyproject_content) do
        fixture("pyproject_files", "requires_plugins_none.toml")
      end

      it "does not run any commands" do
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)

        installer.install_required_plugins
      end
    end

    context "with nil pyproject content" do
      let(:pyproject_content) { nil }

      it "does not run any commands" do
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)

        installer.install_required_plugins
      end
    end

    context "with invalid TOML content" do
      let(:pyproject_content) { "this is not valid toml {{{" }

      it "does not run any commands" do
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)

        installer.install_required_plugins
      end
    end

    context "when plugin installation fails" do
      let(:pyproject_content) do
        fixture("pyproject_files", "requires_plugins.toml")
      end

      it "logs a warning and continues without raising" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "Could not find a matching version of package poetry-plugin-export",
            error_context: {}
          )
        )

        expect(Dependabot.logger).to receive(:warn).with(
          /Failed to install Poetry plugin poetry-plugin-export/
        )

        expect { installer.install_required_plugins }.not_to raise_error
      end
    end

    context "with a plugin name containing injection characters" do
      let(:pyproject_content) do
        <<~TOML
          [tool.poetry.requires-plugins]
          "valid-plugin" = ">=1.0"
          "foo; rm -rf /" = ">=1.0"
          "another.valid_plugin2" = ">=2.0"
        TOML
      end

      it "skips the invalid plugin name and installs valid ones" do
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "pyenv exec poetry self add valid-plugin@\\>\\=1.0",
          fingerprint: "pyenv exec poetry self add <plugin_name>@<constraint>"
        )
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "pyenv exec poetry self add another.valid_plugin2@\\>\\=2.0",
          fingerprint: "pyenv exec poetry self add <plugin_name>@<constraint>"
        )

        installer.install_required_plugins
      end

      it "does not install a plugin with shell metacharacters" do
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command).with(
          /rm -rf/,
          anything
        )

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        installer.install_required_plugins
      end
    end

    context "with a single-character plugin name" do
      let(:pyproject_content) do
        <<~TOML
          [tool.poetry.requires-plugins]
          "x" = ">=1.0"
        TOML
      end

      it "installs single-character names (valid PyPI names)" do
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "pyenv exec poetry self add x@\\>\\=1.0",
          fingerprint: "pyenv exec poetry self add <plugin_name>@<constraint>"
        )

        installer.install_required_plugins
      end
    end

    context "with a constraint containing shell injection characters" do
      let(:pyproject_content) do
        <<~TOML
          [tool.poetry.requires-plugins]
          "valid-plugin" = ">=1.0"
          "evil-plugin" = '>=1.0"; rm -rf /; echo "'
        TOML
      end

      it "skips the plugin with the malicious constraint" do
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          "pyenv exec poetry self add valid-plugin@\\>\\=1.0",
          fingerprint: "pyenv exec poetry self add <plugin_name>@<constraint>"
        )

        installer.install_required_plugins
      end

      it "does not execute the injected command" do
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command).with(
          /rm -rf/,
          anything
        )

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        installer.install_required_plugins
      end
    end
  end
end
