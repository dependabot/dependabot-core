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

  it "reports configured npm scoped registries as possible hosts, not a confirmed failing host" do
    described_class.dependency_files = [
      Dependabot::DependencyFile.new(
        name: ".npmrc",
        content: "registry=https://public.example.com/\n" \
                 "@private:registry=https://user:secret@private.example.com/token-secret\n"
      )
    ]
    described_class.credentials = [
      Dependabot::Credential.new(
        { "type" => "npm_registry", "registry" => "credential.example.com", "scope" => "@other", "token" => "secret" }
      )
    ]
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)

    expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
      context = Dependabot::ErrorReportContext.build(error: raised)
      expect(context).not_to have_key("host")
      expect(context).to include(
        "configured-registry-hosts" => contain_exactly(
          "public.example.com", "private.example.com", "credential.example.com"
        )
      )
      expect(context.to_s).not_to include("secret", "@private", "@other")
      expect(raised).to equal(error)
      expect(error.sentry_context[:fingerprint]).to eq(["unchanged"])
    end
    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
  end

  it "reports Yarn Berry's global and scoped registries as possible hosts" do
    described_class.dependency_files = [
      npmrc,
      Dependabot::DependencyFile.new(
        name: ".yarnrc.yml",
        content: "npmRegistryServer: https://berry.example.com\n" \
                 "npmScopes:\n  private:\n    npmRegistryServer: https://private.example.com/secret\n"
      )
    ]
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("YARN_NPM_REGISTRY_SERVER", nil).and_return(nil)
    allow(ENV).to receive(:fetch).with("YARN_RC_FILENAME", nil).and_return(nil)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("corepack yarn@4.9.2 #{command}", any_args).and_raise(error)

    expect { described_class.package_manager_run_command("yarn@4.9.2", command, env: env) }
      .to raise_error do |raised|
        context = Dependabot::ErrorReportContext.build(error: raised)
        expect(context).not_to have_key("host")
        expect(context).to include(
          "configured-registry-hosts" => contain_exactly("berry.example.com", "private.example.com")
        )
        expect(context.to_s).not_to include("secret", "registry.example.com")
        expect(raised).to equal(error)
      end
    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
  end

  it "reports pnpm's overridden and scoped registries without claiming which one failed" do
    described_class.dependency_files = [
      Dependabot::DependencyFile.new(
        name: ".npmrc",
        content: "registry=https://unused.example.com\n@private:registry=https://private.example.com/a\n"
      )
    ]
    env["npm_config_registry"] = "https://override.example.com"
    env["npm_config_@other:registry"] = "https://other.example.com/secret"
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("pnpm #{command}", any_args).and_raise(error)

    expect { described_class.run_pnpm_command(command, env: env) }.to raise_error do |raised|
      context = Dependabot::ErrorReportContext.build(error: raised)
      expect(context).not_to have_key("host")
      expect(context).to include(
        "configured-registry-hosts" => contain_exactly(
          "private.example.com", "other.example.com", "override.example.com"
        )
      )
      expect(context.to_s).not_to include("secret", "unused.example.com")
    end
  end

  it "deduplicates and limits configured registry hosts" do
    entries = (1..55).map { |i| "@scope#{i}:registry=https://registry#{i}.example.com/private" }
    entries << "@duplicate:registry=https://registry1.example.com/another"
    described_class.dependency_files = [Dependabot::DependencyFile.new(name: ".npmrc", content: entries.join("\n"))]
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)

    expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
      context = T.must(Dependabot::ErrorReportContext.build(error: raised))
      hosts = context["configured-registry-hosts"]
      expect(hosts).to eq((1..50).map { |i| "registry#{i}.example.com" })
      expect(context).not_to have_key("host")
    end
  end

  it "includes both explicit and inherited npm registry overrides" do
    env["NPM_CONFIG_REGISTRY"] = "https://explicit.example.com"
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("npm_config_registry", nil).and_return("https://inherited.example.com")
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)

    expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
      expect(Dependabot::ErrorReportContext.build(error: raised)).to include(
        "configured-registry-hosts" => contain_exactly("explicit.example.com", "inherited.example.com")
      )
    end
  end

  it "includes Yarn Classic scoped configuration without treating it as the failing host" do
    described_class.dependency_files = [
      npmrc,
      Dependabot::DependencyFile.new(
        name: ".yarnrc", content: %("@private:registry" "https://classic.example.com/private"\n)
      )
    ]
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("corepack yarn@1.22.22 #{command}", any_args).and_raise(error)

    expect { described_class.package_manager_run_command("yarn@1.22.22", command, env: env) }
      .to raise_error do |raised|
        context = Dependabot::ErrorReportContext.build(error: raised)
        expect(context).not_to have_key("host")
        expect(context).to include(
          "configured-registry-hosts" => contain_exactly("registry.example.com", "classic.example.com")
        )
      end
  end

  sig { params(manager: String, executable: String, version: T.nilable(String), host: T.nilable(String)).void }
  def expect_safe_context(manager, executable, version: nil, host: "registry.example.com")
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("#{executable} #{command}", any_args).and_raise(error)

    expected_context = {
      "helper-error-class" => "HelperSubprocessFailed",
      "command-name" => "#{manager} update",
      "configured-registry-hosts" => host && [host],
      "selected-package-manager-version" => version
    }.compact

    expect { described_class.public_send("run_#{manager}_command", command, env: env) }.to raise_error do |raised|
      expect(raised).to equal(error)
      expect(Dependabot::ErrorReportContext.build(error: raised)).to eq(expected_context)
      expect(error.sentry_context[:fingerprint]).to eq(["unchanged"])
    end

    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
  end

  sig { params(lookup_error_class: T.nilable(String)).void }
  def expect_preserved_yarn_error(lookup_error_class = nil)
    expect { described_class.run_yarn_command(command, env: env) }.to raise_error do |raised|
      expect(raised).to equal(error)
      expect(error.sentry_context[:fingerprint]).to eq(["unchanged"])
      expect(Dependabot::ErrorReportContext.build(error: raised)).to include(
        "helper-error-class" => "HelperSubprocessFailed", "command-name" => "yarn update"
      )
    end
    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
    return unless lookup_error_class

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

  it "does not claim the selected Yarn version was observed when yarnPath can delegate to another binary" do
    described_class.dependency_files = [
      Dependabot::DependencyFile.new(name: ".yarnrc.yml", content: "yarnPath: .yarn/releases/yarn-4.8.0.cjs\n")
    ]
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("corepack yarn@4.9.2 #{command}", any_args).and_raise(error)

    expect { described_class.package_manager_run_command("yarn@4.9.2", command, env: env) }
      .to raise_error do |raised|
        context = Dependabot::ErrorReportContext.build(error: raised)
        expect(context).to include("selected-package-manager-version" => "4.9.2")
        expect(context).not_to have_key("package-manager-version")
        expect(context).not_to have_key("observed-package-manager-version")
        expect(raised).to equal(error)
      end
    expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
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

    expect_safe_context("yarn", "yarn", host: nil)
  end

  context "when a Yarn Berry command fails" do
    before do
      described_class.dependency_files = [
        npmrc,
        Dependabot::DependencyFile.new(
          name: ".yarnrc.yml",
          content: "npmRegistryServer: https://berry.example.com/private\n"
        )
      ]
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("YARN_NPM_REGISTRY_SERVER", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("YARN_RC_FILENAME", nil).and_return(nil)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("corepack yarn@4.9.2 #{command}", any_args).and_raise(error)
    end

    it "reports Yarn's configured registry instead of the npmrc registry" do
      expect { described_class.package_manager_run_command("yarn@4.9.2", command, env: env) }
        .to raise_error do |raised|
          expect(raised).to equal(error)
          expect(Dependabot::ErrorReportContext.build(error: raised))
            .to include("configured-registry-hosts" => ["berry.example.com"])
          expect(error.sentry_context[:fingerprint]).to eq(["unchanged"])
        end
      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
    end

    it "uses the command's Yarn registry environment override" do
      env["YARN_NPM_REGISTRY_SERVER"] = "https://user:secret@override.example.com/private"

      expect { described_class.package_manager_run_command("yarn@4.9.2", command, env: env) }
        .to raise_error do |raised|
          context = Dependabot::ErrorReportContext.build(error: raised)
          expect(context).to include("configured-registry-hosts" => ["override.example.com"])
          expect(context.to_s).not_to include("secret")
        end
      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
    end

    it "retains scoped registries when the global Yarn registry is overridden" do
      described_class.dependency_files = [
        npmrc, Dependabot::DependencyFile.new(
          name: ".yarnrc.yml",
          content: "npmRegistryServer: https://unused.example.com\n" \
                   "npmScopes:\n  private:\n    npmRegistryServer: https://private.example.com\n"
        )
      ]
      env["YARN_NPM_REGISTRY_SERVER"] = "https://override.example.com"

      expect { described_class.package_manager_run_command("yarn@4.9.2", command, env: env) }
        .to raise_error do |raised|
          context = Dependabot::ErrorReportContext.build(error: raised)
          expect(context).to include(
            "configured-registry-hosts" => contain_exactly("override.example.com", "private.example.com")
          )
          expect(context.to_s).not_to include("unused.example.com", "registry.example.com")
        end
    end

    it "uses an inherited Yarn registry environment override" do
      allow(ENV).to receive(:fetch).with("YARN_NPM_REGISTRY_SERVER", nil).and_return("https://inherited.example.com")

      expect { described_class.package_manager_run_command("yarn@4.9.2", command, env: env) }
        .to raise_error do |raised|
          expect(Dependabot::ErrorReportContext.build(error: raised))
            .to include("configured-registry-hosts" => ["inherited.example.com"])
        end
    end

    it "omits the registry when only npmrc is available" do
      described_class.dependency_files = [npmrc]

      expect { described_class.package_manager_run_command("yarn@4.9.2", command, env: env) }
        .to raise_error do |raised|
          expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("configured-registry-hosts")
        end
    end

    it "uses the Yarn Berry registry for a bare Yarn command with a Berry packageManager pin" do
      described_class.dependency_files = T.must(described_class.dependency_files) + [
        Dependabot::DependencyFile.new(name: "package.json", content: '{"packageManager":"yarn@4.9.2"}')
      ]
      allow(described_class).to receive(:setup_yarn_berry)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("yarn #{command}", any_args).and_raise(error)

      expect { described_class.run_yarn_command(command, env: env) }.to raise_error do |raised|
        expect(Dependabot::ErrorReportContext.build(error: raised))
          .to include("configured-registry-hosts" => ["berry.example.com"])
      end
      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).once
    end

    it "omits an interpolated registry that cannot be resolved safely" do
      described_class.dependency_files = [
        npmrc, Dependabot::DependencyFile.new(name: ".yarnrc.yml", content: 'npmRegistryServer: "${REGISTRY}"')
      ]

      expect { described_class.package_manager_run_command("yarn@4.9.2", command, env: env) }
        .to raise_error do |raised|
          expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("configured-registry-hosts")
        end
    end

    it "omits the registry when Yarn uses a different config filename" do
      env["YARN_RC_FILENAME"] = ".custom-yarnrc.yml"

      expect { described_class.package_manager_run_command("yarn@4.9.2", command, env: env) }
        .to raise_error do |raised|
          expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("configured-registry-hosts")
        end
    end

    it "does not use a nested project's Yarn configuration as the root registry" do
      described_class.dependency_files = [
        npmrc, Dependabot::DependencyFile.new(
          name: "nested/.yarnrc.yml", content: "npmRegistryServer: https://nested.example.com\n"
        )
      ]

      expect { described_class.package_manager_run_command("yarn@4.9.2", command, env: env) }
        .to raise_error do |raised|
          expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("configured-registry-hosts")
        end
    end
  end

  it "preserves a complete prerelease version selected by Corepack" do
    described_class.npm_version_selector = "11.0.0-rc.1+build.2"

    expect_safe_context("npm", "corepack npm@11.0.0-rc.1+build.2", version: "11.0.0-rc.1+build.2")
  end

  it "omits a malformed version selector without running another command" do
    described_class.npm_version_selector = "invalid-secret"

    expect_safe_context("npm", "corepack npm@invalid-secret")
  end

  it "omits registry hosts when none are configured" do
    described_class.dependency_files = []

    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)

    expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
      expect(Dependabot::ErrorReportContext.build(error: raised)).not_to have_key("configured-registry-hosts")
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
      expect(Dependabot::ErrorReportContext.build(error: raised))
        .to include("configured-registry-hosts" => ["registry.example.com"])
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
      described_class.dependency_files = [
        Dependabot::DependencyFile.new(name: ".yarnrc.yml", content: content),
        Dependabot::DependencyFile.new(name: "package.json", content: '{"packageManager":"yarn@4.9.2"}')
      ]
      allow(described_class).to receive(:setup_yarn_berry)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("YARN_NPM_REGISTRY_SERVER", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("YARN_RC_FILENAME", nil).and_return(nil)
      allow(Dependabot.logger).to receive(:warn)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with("yarn #{command}", any_args).and_raise(error)
    end

    it "preserves the original Yarn error when npmScopes is null" do
      expect_preserved_yarn_error
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

    context "with an invalid YAML numeric value" do
      sig { returns(String) }
      let(:content) { "npmRegistryServer: !!float not-a-number\n" }

      it "preserves the original Yarn error" do
        expect_preserved_yarn_error("ArgumentError")
      end
    end
  end

  it "preserves the original npm error without parsing unrelated Yarn configuration" do
    described_class.dependency_files = [
      Dependabot::DependencyFile.new(name: ".yarnrc.yml", content: "npmRegistryServer: !!float not-a-number\n")
    ]
    allow(Dependabot.logger).to receive(:warn)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("npm #{command}", any_args).and_raise(error)

    expect { described_class.run_npm_command(command, env: env) }.to raise_error do |raised|
      expect(raised).to equal(error)
      expect(error.sentry_context[:fingerprint]).to eq(["unchanged"])
    end
    expect(Dependabot.logger).not_to have_received(:warn)
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
