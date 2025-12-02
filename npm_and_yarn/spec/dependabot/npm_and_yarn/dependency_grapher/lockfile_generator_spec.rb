# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/dependency_grapher"
require "dependabot/npm_and_yarn/dependency_grapher/lockfile_generator"

RSpec.describe Dependabot::NpmAndYarn::DependencyGrapher::LockfileGenerator do
  subject(:generator) do
    described_class.new(
      dependency_files: dependency_files,
      package_manager: package_manager,
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

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_corepack_for_npm_and_yarn).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_shared_helpers_command_timeout).and_return(true)
  end

  describe "#generate" do
    context "with npm package manager" do
      let(:package_manager) { "npm" }
      let(:dependency_files) { project_dependency_files("grapher/npm_no_lockfile") }

      it "attempts to generate a package-lock.json" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command).and_return("")

        # Mock file existence check
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("package-lock.json").and_return(false)

        generator.generate

        expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_npm_command)
          .with(
            "install --package-lock-only --ignore-scripts --force --dry-run false",
            fingerprint: "install --package-lock-only --ignore-scripts --force --dry-run false"
          )
      end

      context "when lockfile generation succeeds" do
        let(:lockfile_content) do
          {
            "name" => "test",
            "version" => "1.0.0",
            "lockfileVersion" => 3,
            "packages" => {}
          }.to_json
        end

        it "returns a DependencyFile with the generated lockfile" do
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command)
            .and_return("")
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with("package-lock.json").and_return(true)
          allow(File).to receive(:read).and_call_original
          allow(File).to receive(:read).with("package-lock.json").and_return(lockfile_content)

          result = generator.generate

          expect(result).to be_a(Dependabot::DependencyFile)
          expect(result.name).to eq("package-lock.json")
          expect(result.content).to eq(lockfile_content)
        end
      end

      context "when lockfile generation fails" do
        it "returns nil and logs an error" do
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command)
            .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                         message: "npm ERR! ERESOLVE could not resolve",
                         error_context: {}
                       ))

          expect(Dependabot.logger).to receive(:error).at_least(:once)

          result = generator.generate
          expect(result).to be_nil
        end
      end
    end

    context "with yarn package manager" do
      let(:package_manager) { "yarn" }

      context "with Yarn Classic (no .yarnrc.yml)" do
        let(:dependency_files) { project_dependency_files("grapher/yarn_no_lockfile") }

        it "runs yarn install with appropriate flags" do
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")

          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with("yarn.lock").and_return(false)

          generator.generate

          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
            .with(
              "yarn install --ignore-scripts --frozen-lockfile=false",
              fingerprint: "yarn install --ignore-scripts --frozen-lockfile=false"
            )
        end
      end

      context "with Yarn Berry (.yarnrc.yml present)" do
        let(:dependency_files) { project_dependency_files("grapher/yarn_berry_no_lockfile") }

        it "runs yarn install with update-lockfile mode" do
          # Setup yarn berry first
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:setup_yarn_berry)
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command).and_return("")

          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with("yarn.lock").and_return(false)

          generator.generate

          expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_yarn_command)
            .with("install --mode update-lockfile")
        end
      end
    end

    context "with pnpm package manager" do
      let(:package_manager) { "pnpm" }
      let(:dependency_files) { project_dependency_files("grapher/pnpm_no_lockfile") }

      it "runs pnpm install with lockfile-only flag" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command).and_return("")

        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("pnpm-lock.yaml").and_return(false)

        generator.generate

        expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_pnpm_command)
          .with(
            "install --lockfile-only --ignore-scripts",
            fingerprint: "install --lockfile-only --ignore-scripts"
          )
      end
    end
  end

  describe "#expected_lockfile_name" do
    let(:dependency_files) { [] }

    context "when using npm" do
      let(:package_manager) { "npm" }

      it "returns package-lock.json" do
        expect(generator.send(:expected_lockfile_name)).to eq("package-lock.json")
      end
    end

    context "when using yarn" do
      let(:package_manager) { "yarn" }

      it "returns yarn.lock" do
        expect(generator.send(:expected_lockfile_name)).to eq("yarn.lock")
      end
    end

    context "when using pnpm" do
      let(:package_manager) { "pnpm" }

      it "returns pnpm-lock.yaml" do
        expect(generator.send(:expected_lockfile_name)).to eq("pnpm-lock.yaml")
      end
    end
  end

  describe "error handling" do
    let(:package_manager) { "npm" }
    let(:dependency_files) { project_dependency_files("grapher/npm_no_lockfile") }

    context "with ERESOLVE error" do
      it "logs a helpful error message about peer dependencies" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command)
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "npm ERR! ERESOLVE could not resolve peer dependencies",
                       error_context: {}
                     ))

        expect(Dependabot.logger).to receive(:error)
          .with(/Failed to generate lockfile with npm/)
        expect(Dependabot.logger).to receive(:error)
          .with(/conflicting peer dependencies/)

        generator.generate
      end
    end

    context "with network error" do
      it "logs a helpful error message about network issues" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command)
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "npm ERR! ENOTFOUND registry.npmjs.org",
                       error_context: {}
                     ))

        expect(Dependabot.logger).to receive(:error)
          .with(/Failed to generate lockfile with npm/)
        expect(Dependabot.logger).to receive(:error)
          .with(/Network error/)

        generator.generate
      end
    end

    context "with authentication error" do
      it "logs a helpful error message about credentials" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command)
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "npm ERR! 401 Unauthorized",
                       error_context: {}
                     ))

        expect(Dependabot.logger).to receive(:error)
          .with(/Failed to generate lockfile with npm/)
        expect(Dependabot.logger).to receive(:error)
          .with(/Authentication error/)

        generator.generate
      end
    end
  end

  describe "credential handling" do
    let(:package_manager) { "npm" }
    let(:dependency_files) { project_dependency_files("grapher/npm_no_lockfile") }

    context "with npm registry credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "npm_registry",
              "registry" => "npm.pkg.github.com",
              "token" => "secret-token"
            }
          )
        ]
      end

      it "uses NpmrcBuilder to generate npmrc content" do
        expect(Dependabot::NpmAndYarn::FileUpdater::NpmrcBuilder).to receive(:new)
          .with(credentials: credentials, dependency_files: dependency_files)
          .and_call_original

        # Mock the rest to avoid network calls
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command).and_return("")
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("package-lock.json").and_return(false)

        generator.generate
      end
    end
  end
end
