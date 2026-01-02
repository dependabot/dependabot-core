# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/uv/uv_version_manager"

RSpec.describe Dependabot::Uv::UvVersionManager do
  let(:manager) { described_class.new(dependency_files: dependency_files) }

  let(:pyproject_content) { fixture("pyproject_files", "uv_required_version.toml") }
  let(:pyproject_file) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: pyproject_content
    )
  end
  let(:dependency_files) { [pyproject_file] }

  describe "#ensure_correct_version" do
    subject(:ensure_correct_version) { manager.ensure_correct_version }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("pyenv exec uv --version")
        .and_return("uv 0.9.11")
    end

    context "when current version does not match required version" do
      before do
        # Override the default mock to return different versions on successive calls
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("pyenv exec uv --version")
          .and_return("uv 0.9.11", "uv 0.8.22")
      end

      it "updates uv to the required version" do
        expect(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("pyenv exec pip install --force-reinstall --no-deps uv==0.8.22")
        allow(Dependabot.logger).to receive(:info) # Allow intermediate log calls
        expect(Dependabot.logger).to receive(:info)
          .with(/Current uv version \(0.9.11\) does not match required version \(0.8.22\)/)
        expect(Dependabot.logger).to receive(:info)
          .with("Successfully updated uv to version 0.8.22")

        ensure_correct_version
      end
    end

    context "when current version matches required version" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("pyenv exec uv --version")
          .and_return("uv 0.8.22")
      end

      it "does not update uv" do
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)
          .with(/pip install/)
        allow(Dependabot.logger).to receive(:info) # Allow intermediate log calls
        expect(Dependabot.logger).to receive(:info)
          .with("Using uv version 0.8.22")

        ensure_correct_version
      end
    end

    context "when no required version is specified" do
      let(:pyproject_content) { fixture("pyproject_files", "uv_simple.toml") }

      it "does not update uv" do
        expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)
          .with(/pip install/)
        expect(Dependabot.logger).to receive(:info)
          .with("Using pre-installed uv package")

        ensure_correct_version
      end
    end

    context "when update fails" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("pyenv exec pip install --force-reinstall --no-deps uv==0.8.22")
          .and_raise(StandardError.new("Update failed"))
      end

      it "logs error and re-raises" do
        expect(Dependabot.logger).to receive(:error)
          .with(/Failed to update uv to version 0.8.22/)

        expect { ensure_correct_version }.to raise_error(StandardError, "Update failed")
      end
    end

    context "when version verification fails after update" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("pyenv exec pip install --force-reinstall --no-deps uv==0.8.22")
        # Mock verification returning wrong version
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with("pyenv exec uv --version")
          .and_return("uv 0.9.11", "uv 0.9.11")
      end

      it "raises an error about version mismatch" do
        expect(Dependabot.logger).to receive(:error)
          .with(/Failed to update uv to version 0.8.22/)

        expect { ensure_correct_version }.to raise_error(/expected version 0.8.22, but got 0.9.11/)
      end
    end
  end
end
