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

  sig { params(manager: String, executable: String, version: T.nilable(String)).void }
  def expect_safe_context(manager, executable, version: nil)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("#{executable} #{command}", any_args).and_raise(error)

    expected_context = {
      "helper-error-class" => "HelperSubprocessFailed",
      "command-name" => "#{manager} update",
      "host" => "registry.example.com",
      "package-manager-version" => version
    }.compact

    expect { described_class.public_send("run_#{manager}_command", command, env: env) }.to raise_error do |raised|
      expect(raised).to equal(error)
      expect(Dependabot::ErrorReportContext.build(error: raised)).to eq(expected_context)
      expect(error.sentry_context[:fingerprint]).to eq(["unchanged"])
    end

    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
  end

  sig { params(lookup_error_class: String).void }
  def expect_preserved_yarn_error(lookup_error_class)
    expect { described_class.run_yarn_command(command, env: env) }.to raise_error do |raised|
      expect(raised).to equal(error)
      expect(error.sentry_context[:fingerprint]).to eq(["unchanged"])
      expect(Dependabot::ErrorReportContext.build(error: raised)).to include(
        "helper-error-class" => "HelperSubprocessFailed", "command-name" => "yarn update"
      )
    end
    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
    expect(Dependabot.logger).to have_received(:warn)
      .with("Could not resolve registry for error context (#{lookup_error_class})")
  end

  it "omits the unknown local npm version without running another command" do
    expect_safe_context("npm", "npm")
  end

  it "uses the exact version Corepack selected without running another command" do
    described_class.npm_version_selector = "10.9.0"

    expect_safe_context("npm", "corepack npm@10.9.0", version: "10.9.0")
  end

  it "omits the version when Corepack only has a cached major selected" do
    described_class.npm_version_selector = "10"

    expect_safe_context("npm", "corepack npm@10")
  end

  it "omits the unknown default pnpm version without running another command" do
    expect_safe_context("pnpm", "pnpm")
  end

  it "omits the version when Corepack selected a pnpm major for an older lockfile" do
    described_class.dependency_files = [
      npmrc, Dependabot::DependencyFile.new(name: "pnpm-lock.yaml", content: "lockfileVersion: '6.0'")
    ]

    expect_safe_context("pnpm", "corepack pnpm@8")
  end

  it "omits the unknown Yarn version without running another command" do
    allow(described_class).to receive(:setup_yarn_berry)

    expect_safe_context("yarn", "yarn")
  end

  it "preserves a complete prerelease version selected by Corepack" do
    described_class.npm_version_selector = "11.0.0-rc.1+build.2"

    expect_safe_context("npm", "corepack npm@11.0.0-rc.1+build.2", version: "11.0.0-rc.1+build.2")
  end

  it "omits a malformed version selector without running another command" do
    described_class.npm_version_selector = "invalid-secret"

    expect_safe_context("npm", "corepack npm@invalid-secret")
  end

  it "falls back to the default public registry when none is configured" do
    described_class.dependency_files = []

    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)

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

    expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
      expect(Dependabot::ErrorReportContext.build(error: raised)).to include("host" => "registry.example.com")
    end
    expect(Dependabot::NpmAndYarn::RegistryHelper).not_to have_received(:corepack_integrity_keys)
  end

  it "does not report the .npmrc auth token" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)

    expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
      expect(Dependabot::ErrorReportContext.build(error: raised).to_s).not_to include("secret")
    end
  end

  context "when Yarn registry configuration is malformed" do
    sig { returns(String) }
    let(:content) { "npmScopes: null\n" }

    before do
      described_class.dependency_files = [Dependabot::DependencyFile.new(name: ".yarnrc.yml", content: content)]
      allow(described_class).to receive(:setup_yarn_berry)
      allow(Dependabot.logger).to receive(:warn)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("yarn #{command}", any_args).and_raise(error)
    end

    it "preserves the original Yarn error when npmScopes is null" do
      expect_preserved_yarn_error("NoMethodError")
    end

    context "with a non-string registry" do
      sig { returns(String) }
      let(:content) { "npmRegistryServer: 123\n" }

      it "preserves the original Yarn error" do
        expect_preserved_yarn_error("TypeError")
      end
    end

    context "with a disallowed YAML type" do
      sig { returns(String) }
      let(:content) { "npmScopes: !ruby/object:Object {}\n" }

      it "preserves the original Yarn error" do
        expect_preserved_yarn_error("Psych::DisallowedClass")
      end
    end
  end

  it "does not run diagnostic commands after successful commands" do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("updated")

    expect(described_class.run_npm_command("update", env: env)).to eq("updated")
    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
  end

  context "when the failed command is a version check" do
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

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("npm #{command}", any_args).and_raise(error)
    end

    it "reports the manager without forwarding the command" do
      expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
        expect(Dependabot::ErrorReportContext.build(error: raised)).to include("command-name" => "npm")
        expect(Dependabot::ErrorReportContext.build(error: raised).to_s).not_to include("secret")
      end
    end
  end
end
