# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/dependency_grapher"
require "dependabot/bun/dependency_grapher/lockfile_generator"

RSpec.describe Dependabot::Bun::DependencyGrapher::LockfileGenerator do
  subject(:generator) do
    described_class.new(
      dependency_files: dependency_files,
      credentials: credentials
    )
  end

  let(:credentials) do
    [
      Dependabot::Credential.new(
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      )
    ]
  end

  let(:dependency_files) { project_dependency_files("javascript/exact_version_requirements_no_lockfile") }

  describe "#generate" do
    context "when lockfile generation succeeds" do
      let(:lockfile_content) do
        fixture("projects", "bun", "grapher_with_lockfile", "bun.lock")
      end

      it "runs bun install with --ignore-scripts" do
        allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_return("")
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("bun.lock").and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with("bun.lock").and_return(lockfile_content)

        generator.generate

        expect(Dependabot::Bun::Helpers).to have_received(:run_bun_command)
          .with("install --ignore-scripts", fingerprint: "install --ignore-scripts")
      end

      it "returns a DependencyFile with the generated lockfile" do
        allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_return("")
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("bun.lock").and_return(true)
        allow(File).to receive(:read).and_call_original
        allow(File).to receive(:read).with("bun.lock").and_return(lockfile_content)

        result = generator.generate

        expect(result).to be_a(Dependabot::DependencyFile)
        expect(result.name).to eq("bun.lock")
        expect(result.content).to eq(lockfile_content)
      end
    end

    context "when lockfile generation fails" do
      it "re-raises the error after logging" do
        allow(Dependabot::Bun::Helpers).to receive(:run_bun_command)
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "bun install failed: authentication required",
                       error_context: {}
                     ))

        expect(Dependabot.logger).to receive(:error).with(/Failed to generate bun.lock/)

        expect { generator.generate }.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
      end
    end

    context "when bun.lock is not generated" do
      it "raises DependencyFileNotEvaluatable" do
        allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_return("")
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("bun.lock").and_return(false)

        expect { generator.generate }.to raise_error(
          Dependabot::DependencyFileNotEvaluatable,
          /bun.lock was not generated/
        )
      end
    end
  end

  describe "file writing" do
    it "writes package.json and .npmrc files to the temporary directory" do
      npmrc_file = Dependabot::DependencyFile.new(
        name: ".npmrc",
        content: "registry=https://npm.pkg.github.com",
        directory: "/"
      )
      files_with_npmrc = dependency_files + [npmrc_file]

      generator_with_npmrc = described_class.new(
        dependency_files: files_with_npmrc,
        credentials: credentials
      )

      allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_return("")
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("bun.lock").and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("bun.lock").and_return("{}")

      # Verify files are written during generation
      expect(File).to receive(:write).with("package.json", anything)
      expect(File).to receive(:write).with(".npmrc", "registry=https://npm.pkg.github.com")

      generator_with_npmrc.generate
    end

    it "does not write lockfiles or other non-manifest files" do
      lockfile = Dependabot::DependencyFile.new(
        name: "bun.lock",
        content: "{}",
        directory: "/"
      )
      files_with_lock = dependency_files + [lockfile]

      generator_with_lock = described_class.new(
        dependency_files: files_with_lock,
        credentials: credentials
      )

      allow(Dependabot::Bun::Helpers).to receive(:run_bun_command).and_return("")
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("bun.lock").and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("bun.lock").and_return("{}")

      expect(File).to receive(:write).with("package.json", anything)
      expect(File).not_to receive(:write).with("bun.lock", anything)

      generator_with_lock.generate
    end
  end
end
