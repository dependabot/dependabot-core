# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-context-only pnpm_version fixture used by the parent hook.

require "spec_helper"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/native_helpers"

RSpec.describe Dependabot::NpmAndYarn::NativeHelpers do
  after { Dependabot::NpmAndYarn::Helpers.dependency_files = nil }

  describe ".run_pnpm_audit_fix_command" do
    before do
      allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command) do |command, **|
        command == "-v" ? pnpm_version : ""
      end
    end

    context "with pnpm 11" do
      let(:pnpm_version) { "Corepack warning\n11.25.0\n" }

      it "uses the lockfile update fix method" do
        described_class.run_pnpm_audit_fix_command

        expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_pnpm_command)
          .with("audit --fix=update", fingerprint: "audit --fix=update")
      end
    end

    context "with pnpm 10" do
      let(:pnpm_version) { "10.16.0" }

      it "uses the compatible override fix method" do
        described_class.run_pnpm_audit_fix_command

        expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_pnpm_command)
          .with("audit --fix", fingerprint: "audit --fix")
      end
    end
  end

  describe ".run_npm8_subdependency_update_command" do
    context "when running on npm 12" do
      before do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:npm_version)
          .and_return(Dependabot::NpmAndYarn::Version.new("12.2.0"))
      end

      it "includes --allow-git=all and --allow-remote=all flags and fingerprints" do
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, options|
          expect(command).to include("--allow-git=all")
          expect(command).to include("--allow-remote=all")
          expect(command).to include("--ignore-scripts")
          expect(options[:fingerprint]).to include("--allow-git=all")
          expect(options[:fingerprint]).to include("--allow-remote=all")
          ""
        end

        described_class.run_npm8_subdependency_update_command(["lodash"])
      end

      it "respects explicit deny in .npmrc by omitting the denied flag" do
        Dependabot::NpmAndYarn::Helpers.dependency_files = [
          Dependabot::DependencyFile.new(name: ".npmrc", content: "allow-git=none\n")
        ]

        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, options|
          expect(command).not_to include("--allow-git")
          expect(command).to include("--allow-remote=all")
          expect(options[:fingerprint]).not_to include("--allow-git")
          expect(options[:fingerprint]).to include("--allow-remote=all")
          ""
        end

        described_class.run_npm8_subdependency_update_command(["lodash"])
      ensure
        Dependabot::NpmAndYarn::Helpers.dependency_files = nil
      end
    end

    context "when running on npm 11" do
      before do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:npm_version)
          .and_return(Dependabot::NpmAndYarn::Version.new("11.17.0"))
      end

      it "does not include allow flags" do
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, options|
          expect(command).not_to include("--allow-git")
          expect(command).not_to include("--allow-remote")
          expect(options[:fingerprint]).not_to include("--allow-git")
          expect(options[:fingerprint]).not_to include("--allow-remote")
          ""
        end

        described_class.run_npm8_subdependency_update_command(["lodash"])
      end
    end
  end

  describe ".run_npm_audit_fix_command" do
    context "when running on npm 12" do
      before do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:npm_version)
          .and_return(Dependabot::NpmAndYarn::Version.new("12.2.0"))
      end

      it "includes --allow-git=all and --allow-remote=all flags and fingerprints" do
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, options|
          expect(command).to include("--allow-git=all")
          expect(command).to include("--allow-remote=all")
          expect(command).to include("--ignore-scripts")
          expect(options[:fingerprint]).to include("--allow-git=all")
          expect(options[:fingerprint]).to include("--allow-remote=all")
          ""
        end

        described_class.run_npm_audit_fix_command
      end
    end

    context "when running on npm 11" do
      before do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:npm_version)
          .and_return(Dependabot::NpmAndYarn::Version.new("11.17.0"))
      end

      it "does not include allow flags" do
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, options|
          expect(command).not_to include("--allow-git")
          expect(command).not_to include("--allow-remote")
          expect(options[:fingerprint]).not_to include("--allow-git")
          expect(options[:fingerprint]).not_to include("--allow-remote")
          ""
        end

        described_class.run_npm_audit_fix_command
      end
    end
  end
end
