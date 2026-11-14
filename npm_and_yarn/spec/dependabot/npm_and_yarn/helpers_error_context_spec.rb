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
  sig { returns(Dependabot::DependencyFile) }
  let(:npmrc) do
    Dependabot::DependencyFile.new(
      name: ".npmrc",
      content: "registry=https://registry.example.com/private\n_authToken=secret\n"
    )
  end

  sig { returns(T::Hash[String, String]) }
  let(:env) { {} }

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
    described_class.dependency_files = [npmrc]
    described_class.credentials = []
  end

  after { described_class.npm_version_selector = nil }

  # The registry is resolved from .npmrc/.yarnrc(.yml) (see Helpers.configured_registry), never probed,
  # so only the version probe (when the version isn't already known precisely) needs stubbing. A
  # Corepack-pinned probe runs with the already-merged Corepack env (needed to resolve the right
  # binary), not the bare `env` fixture, so the expected probe env is configurable.
  sig { params(executable: String, version: String, probes_version: T::Boolean, probe_env: T.anything).void }
  def stub_command_failure(executable, version, probes_version:, probe_env: env)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("#{executable} #{command}", any_args).and_raise(error)
    return unless probes_version

    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("#{executable} --version", hash_including(env: probe_env, timeout: 10)).and_return("#{version}\n")
  end

  sig do
    params(
      manager: String, executable: String, version: String, probes_version: T::Boolean, probe_env: T.anything
    ).void
  end
  def expect_safe_context(manager, executable, version, probes_version: true, probe_env: env)
    stub_command_failure(executable, version, probes_version: probes_version, probe_env: probe_env)

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

    return if probes_version

    expect(Dependabot::SharedHelpers)
      .not_to have_received(:run_shell_command).with("#{executable} --version", any_args)
  end

  it "reports safe context for local npm, probing for its version" do
    expect_safe_context("npm", "npm", "12.0.0")
  end

  it "uses the exact version Corepack selected, without probing the binary" do
    described_class.npm_version_selector = "10.9.0"

    expect_safe_context("npm", "corepack npm@10.9.0", "10.9.0", probes_version: false)
  end

  it "probes for the precise version when Corepack only has a cached major selected" do
    described_class.npm_version_selector = "10"

    # The Corepack-pinned path always runs with the already-merged Corepack env (see
    # Helpers.merge_corepack_env), which carries the registry resolved from .npmrc.
    expect_safe_context(
      "npm",
      "corepack npm@10",
      "10.9.3",
      probe_env: hash_including("npm_config_registry" => "https://registry.example.com/private")
    )
  end

  it "reports safe context for default pnpm, probing for its version" do
    expect_safe_context("pnpm", "pnpm", "10.0.0")
  end

  it "probes for the precise version when Corepack selected a major for an older lockfile" do
    described_class.dependency_files = [
      npmrc, Dependabot::DependencyFile.new(name: "pnpm-lock.yaml", content: "lockfileVersion: '6.0'")
    ]

    expect_safe_context(
      "pnpm",
      "corepack pnpm@8",
      "8.15.9",
      probe_env: hash_including("npm_config_registry" => "https://registry.example.com/private")
    )
  end

  it "reports safe context for Yarn Berry YN0001 errors, probing for its version" do
    allow(described_class).to receive(:setup_yarn_berry)

    expect_safe_context("yarn", "yarn", "4.0.0")
  end

  it "reports safe context for Yarn 1, probing for its version" do
    allow(described_class).to receive(:setup_yarn_berry)

    expect_safe_context("yarn", "yarn", "1.22.22")
  end

  it "falls back to the default public registry when none is configured" do
    described_class.dependency_files = []

    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm --version", any_args).and_return("12.0.0")

    expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
      expect(Dependabot::ErrorReportContext.build(error: raised)).to include("host" => "registry.npmjs.org")
    end
  end

  it "never fetches Corepack integrity keys while resolving the registry for error context" do
    # A replaces-base registry would otherwise trigger a network fetch for signing keys (see
    # RegistryHelper#corepack_integrity_keys); error-context resolution must never do that, since it
    # would reintroduce the exact "could hang while reporting a failure" risk this class exists to avoid.
    allow(Dependabot::NpmAndYarn::RegistryHelper).to receive(:corepack_integrity_keys)
      .and_raise("must not fetch integrity keys while reporting an error")
    allow(described_class).to receive(:credentials).and_return(
      [
        Dependabot::Credential.new(
          { "type" => "npm_registry", "registry" => "registry.example.com", "replaces-base" => true }
        )
      ]
    )
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm --version", any_args).and_return("12.0.0")

    expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
      expect(Dependabot::ErrorReportContext.build(error: raised)).to include("host" => "registry.example.com")
    end
    expect(Dependabot::NpmAndYarn::RegistryHelper).not_to have_received(:corepack_integrity_keys)
  end

  it "does not report the .npmrc auth token" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm --version", any_args).and_return("12.0.0")

    expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
      expect(Dependabot::ErrorReportContext.build(error: raised).to_s).not_to include("secret")
    end
  end

  it "does not probe successful commands" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("updated")

    expect(described_class.run_npm_command("update", env: env)).to eq("updated")
    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
  end

  it "enforces a wall-clock deadline for diagnostic probes even if output keeps arriving" do
    version_probe_observer = T.let(nil, Dependabot::CommandHelpers::OutputObserver)

    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm --version", hash_including(env: env, timeout: 10)) do |*_args, **kwargs|
        version_probe_observer = kwargs[:output_observer]
        "12.0.0\n"
      end

    expect { described_class.run_npm_command(command, env: env) }
      .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)

    # Output keeps arriving, which would reset `run_shell_command`'s own inactivity timeout, but the
    # observer must still signal a stop once the wall-clock deadline has elapsed regardless.
    expect(T.must(version_probe_observer).call("still printing output...")).to eq({})

    allow(Time).to receive(:now).and_return(Time.now + 11)
    expect(T.must(version_probe_observer).call("still printing output...")).to include(gracefully_stop: true)
  end

  context "when collecting diagnostics fails" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm #{command}", any_args).and_raise(error)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm --version", any_args).and_return("12.0.0")
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

    it "does not replace the error when a diagnostic process cannot be started" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm --version", any_args).and_raise(Errno::ENOENT)

      expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
        expect(raised).to equal(error)
        expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("package-manager-version")
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
