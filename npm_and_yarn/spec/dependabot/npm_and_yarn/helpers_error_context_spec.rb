# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/error_report_context"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"

RSpec.describe Dependabot::NpmAndYarn::Helpers do
  extend T::Sig

  # Keep signatures attached to their corresponding fixtures.
  # rubocop:disable RSpec/ScatteredLet
  sig { returns(T::Hash[String, String]) }
  let(:env) { { "npm_config_registry" => "https://user:secret@registry.example.com/private?token=secret" } }

  sig { returns(String) }
  let(:command) { "update private-package --token=secret" }

  sig { returns(Dependabot::SharedHelpers::HelperSubprocessFailed) }
  let(:error) do
    Dependabot::SharedHelpers::HelperSubprocessFailed.new(
      message: "YN0001: private failure secret",
      error_context: { command: command, args: ["secret"], stderr_output: "secret", fingerprint: "unchanged" }
    )
  end
  # rubocop:enable RSpec/ScatteredLet

  before do
    described_class.npm_version_selector = nil
    described_class.dependency_files = []
    described_class.credentials = []
  end

  after { described_class.npm_version_selector = nil }

  sig { params(manager: String, executable: String, version: String).void }
  def stub_command_failure(manager, executable, version)
    registry_key = manager == "yarn" && !version.start_with?("1.") ? "npmRegistryServer" : "registry"
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("#{executable} #{command}", any_args).and_raise(error)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("#{executable} --version", hash_including(env: env, timeout: 10)).and_return("#{version}\n")
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("#{executable} config get #{registry_key}", hash_including(env: env, timeout: 10))
      .and_return("#{env.fetch('npm_config_registry')}\n")
  end

  sig { params(manager: String, executable: String, version: String).void }
  def expect_safe_context(manager, executable, version)
    stub_command_failure(manager, executable, version)

    expect { described_class.public_send("run_#{manager}_command", command, env: env) }.to raise_error do |raised|
      expect(raised).to equal(error)
      expect(Dependabot::ErrorReportContext.build(error: raised)).to eq(
        "helper-error-class" => "HelperSubprocessFailed",
        "command-name" => "#{manager} update",
        "package-manager-version" => version,
        "host" => "registry.example.com"
      )
      expect(error.sentry_context[:fingerprint]).to eq(["unchanged"])
    end
  end

  it "reports safe context for local npm" do
    expect_safe_context("npm", "npm", "12.0.0")
  end

  it "probes the selected npm rather than the local binary" do
    described_class.npm_version_selector = "10"

    expect_safe_context("npm", "corepack npm@10", "10.9.0")
  end

  it "reports safe context for default pnpm" do
    expect_safe_context("pnpm", "pnpm", "10.0.0")
  end

  it "probes the pnpm selected for an older lockfile" do
    described_class.dependency_files = [
      Dependabot::DependencyFile.new(name: "pnpm-lock.yaml", content: "lockfileVersion: '6.0'")
    ]

    expect_safe_context("pnpm", "corepack pnpm@8", "8.15.9")
  end

  it "reports safe context for Yarn Berry YN0001 errors" do
    allow(described_class).to receive(:setup_yarn_berry)

    expect_safe_context("yarn", "yarn", "4.0.0")
  end

  it "uses the Classic registry setting for Yarn 1" do
    allow(described_class).to receive(:setup_yarn_berry)

    expect_safe_context("yarn", "yarn", "1.22.22")
  end

  it "does not probe successful commands" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("updated")

    expect(described_class.run_npm_command("update", env: env)).to eq("updated")
    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
  end

  it "enforces a wall-clock deadline for diagnostic probes even if output keeps arriving" do
    version_probe_observer = T.let(nil, T.untyped)

    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm --version", hash_including(env: env, timeout: 10)) do |*, **kwargs|
        version_probe_observer = kwargs[:output_observer]
        "12.0.0\n"
      end
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm config get registry", any_args).and_return("#{env.fetch('npm_config_registry')}\n")

    expect { described_class.run_npm_command(command, env: env) }
      .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)

    # Output keeps arriving, which would reset `run_shell_command`'s own inactivity timeout, but the
    # observer must still signal a stop once the wall-clock deadline has elapsed regardless.
    expect(version_probe_observer.call("still printing output...")).to eq({})

    allow(Time).to receive(:now).and_return(Time.now + 11)
    expect(version_probe_observer.call("still printing output...")).to include(gracefully_stop: true)
  end

  context "when collecting diagnostics fails" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm #{command}", any_args).and_raise(error)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm --version", any_args).and_return("12.0.0")
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm config get registry", any_args).and_return(env.fetch("npm_config_registry"))
    end

    it "does not replace the error when version detection fails" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm --version", any_args).and_raise(error)

      expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
        expect(raised).to equal(error)
        expect(Dependabot::ErrorReportContext.build(error: raised)).to include("command-name" => "npm update")
        expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("package-manager-version")
      end
    end

    it "does not report malformed version output" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm --version", any_args).and_return("private error with secret")

      expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
        expect(raised).to equal(error)
        expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("package-manager-version")
      end
    end

    it "does not replace the error when registry detection fails" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm config get registry", any_args).and_raise(error)

      expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
        expect(raised).to equal(error)
        expect(Dependabot::ErrorReportContext.build(error: raised)).to include("package-manager-version" => "12.0.0")
        expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("host")
      end
    end

    it "does not replace the error when a diagnostic process cannot be started" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm --version", any_args).and_raise(Errno::ENOENT)

      expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
        expect(raised).to equal(error)
        expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("package-manager-version")
      end
    end

    it "redacts malformed registry URLs" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm config get registry", any_args).and_return("https://registry.example.com/private secret")

      expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
        expect(Dependabot::ErrorReportContext.build(error: raised)).to include("host" => "<redacted>")
      end
    end

    it "omits unexpected registry output" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm config get registry", any_args).and_return("secret")

      expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
        expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("host")
      end
    end

    context "when the failed command is a version probe" do
      sig { returns(String) }
      let(:command) { "--version" }

      it "does not retry or recurse while collecting context" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_raise(error)

        expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
          expect(raised).to equal(error)
          expect(Dependabot::ErrorReportContext.build(error: raised)).to eq(
            "helper-error-class" => "HelperSubprocessFailed", "command-name" => "npm"
          )
        end
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
      end
    end

    context "when the command is not allowlisted" do
      sig { returns(String) }
      let(:command) { "secret-command --token=secret" }

      it "reports the manager without forwarding the command" do
        expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
          expect(Dependabot::ErrorReportContext.build(error: raised)).to include("command-name" => "npm")
          expect(Dependabot::ErrorReportContext.build(error: raised).to_s).not_to include("secret")
        end
      end
    end
  end
end
