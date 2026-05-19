# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python"
require "dependabot/python/dependency_grapher/lockfile_generator"

RSpec.describe Dependabot::Python::DependencyGrapher::LockfileGenerator do
  subject(:generator) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:credentials) { [] }

  let(:pyproject_toml) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("pyproject_files", "poetry_dependency_grapher.toml"),
      directory: "/"
    )
  end

  let(:dependency_files) { [pyproject_toml] }

  describe "#generate" do
    context "when poetry lock succeeds" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield
        allow(Dependabot::SharedHelpers).to receive(:with_git_configured).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")

        language_version_manager = instance_double(
          Dependabot::Python::LanguageVersionManager,
          install_required_python: nil,
          python_major_minor: "3.12"
        )
        allow(Dependabot::Python::LanguageVersionManager)
          .to receive(:new).and_return(language_version_manager)

        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("poetry.lock").and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with("poetry.lock").and_return("[metadata]\npython-versions = \"^3.10\"\n")
        allow(File).to receive(:write).and_return(nil)
        allow(FileUtils).to receive(:mkdir_p).and_return(nil)
      end

      it "returns a DependencyFile for the generated lockfile" do
        result = generator.generate
        expect(result).to be_a(Dependabot::DependencyFile)
        expect(result.name).to eq("poetry.lock")
        expect(result.content).to include("[metadata]")
      end

      it "uses the directory from the pyproject.toml" do
        result = generator.generate
        expect(result.directory).to eq(pyproject_toml.directory)
      end

      context "when pyproject.toml has a subdirectory" do
        let(:pyproject_toml) do
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: fixture("pyproject_files", "poetry_dependency_grapher.toml"),
            directory: "/tests/utils/fixtures"
          )
        end

        it "uses the subdirectory on the generated lockfile" do
          result = generator.generate
          expect(result.directory).to eq("/tests/utils/fixtures")
        end
      end

      it "writes dependency files to the temporary directory" do
        generator.generate
        expect(File).to have_received(:write).with("pyproject.toml", pyproject_toml.content)
      end

      it "writes the .python-version file" do
        generator.generate
        expect(File).to have_received(:write).with(".python-version", "3.12")
      end

      it "runs poetry config and poetry lock commands" do
        generator.generate
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with("pyenv exec poetry config system-git-client true",
                fingerprint: "pyenv exec poetry config system-git-client true")
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with("pyenv exec poetry lock --no-interaction",
                fingerprint: "pyenv exec poetry lock --no-interaction")
      end

      it "invokes the poetry plugin installer" do
        plugin_installer = instance_double(
          Dependabot::Python::PoetryPluginInstaller,
          install_required_plugins: nil
        )
        allow(Dependabot::Python::PoetryPluginInstaller)
          .to receive(:from_dependency_files).and_return(plugin_installer)

        generator.generate

        expect(plugin_installer).to have_received(:install_required_plugins)
      end
    end

    context "when poetry lock fails" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield
        allow(Dependabot::SharedHelpers).to receive(:with_git_configured).and_yield

        language_version_manager = instance_double(
          Dependabot::Python::LanguageVersionManager,
          install_required_python: nil,
          python_major_minor: "3.12"
        )
        allow(Dependabot::Python::LanguageVersionManager)
          .to receive(:new).and_return(language_version_manager)

        allow(File).to receive(:write).and_return(nil)
        allow(FileUtils).to receive(:mkdir_p).and_return(nil)

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "poetry lock failed",
                       error_context: {}
                     ))
      end

      it "propagates the error" do
        expect { generator.generate }.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
      end

      it "logs the error" do
        allow(Dependabot.logger).to receive(:error)

        begin
          generator.generate
        rescue StandardError
          nil
        end

        expect(Dependabot.logger).to have_received(:error).with(/Failed to generate poetry\.lock/)
      end
    end

    context "when lockfile is not generated" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:in_a_temporary_directory).and_yield
        allow(Dependabot::SharedHelpers).to receive(:with_git_configured).and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")

        language_version_manager = instance_double(
          Dependabot::Python::LanguageVersionManager,
          install_required_python: nil,
          python_major_minor: "3.12"
        )
        allow(Dependabot::Python::LanguageVersionManager)
          .to receive(:new).and_return(language_version_manager)

        allow(File).to receive(:write).and_return(nil)
        allow(FileUtils).to receive(:mkdir_p).and_return(nil)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("poetry.lock").and_return(false)
      end

      it "raises Dependabot::DependencyFileNotEvaluatable" do
        expect { generator.generate }.to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end

      it "logs an error" do
        allow(Dependabot.logger).to receive(:error)

        begin
          generator.generate
        rescue Dependabot::DependencyFileNotEvaluatable
          nil
        end

        expect(Dependabot.logger).to have_received(:error).with("poetry.lock was not generated")
      end
    end
  end
end
