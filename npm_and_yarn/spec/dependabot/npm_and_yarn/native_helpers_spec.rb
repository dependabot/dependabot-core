# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-context-only pnpm_version fixture used by the parent hook.

require "spec_helper"
require "dependabot/npm_and_yarn"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/native_helpers"
require_relative "../../support/npm_registry"

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

      it "passes the security bypass through verbatim and keeps it distinguishable in the fingerprint" do
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, options|
          expect(command).to include("--min-release-age=0")
          expect(options[:fingerprint]).to include("--min-release-age=0")
          ""
        end

        described_class.run_npm8_subdependency_update_command(["lodash"], min_release_age_arg: "--min-release-age=0")
      end

      it "passes a cooldown floor through but masks the day count in the fingerprint" do
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, options|
          expect(command).to include("--min-release-age=7")
          expect(options[:fingerprint]).to include("--min-release-age=<days>")
          expect(options[:fingerprint]).not_to include("--min-release-age=7")
          ""
        end

        described_class.run_npm8_subdependency_update_command(["lodash"], min_release_age_arg: "--min-release-age=7")
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

      it "passes the security bypass through verbatim and keeps it distinguishable in the fingerprint" do
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, options|
          expect(command).to start_with("audit fix")
          expect(command).to include("--min-release-age=0")
          expect(options[:fingerprint]).to include("--min-release-age=0")
          ""
        end

        described_class.run_npm_audit_fix_command(min_release_age_arg: "--min-release-age=0")
      end

      it "passes a cooldown floor through but masks the day count in the fingerprint" do
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_npm_command) do |command, options|
          expect(command).to include("--min-release-age=14")
          expect(options[:fingerprint]).to include("--min-release-age=<days>")
          expect(options[:fingerprint]).not_to include("--min-release-age=14")
          ""
        end

        described_class.run_npm_audit_fix_command(min_release_age_arg: "--min-release-age=14")
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

  # Runs the real commands against a loopback registry so that a flag the installed npm rejects (npm 12 throws on
  # unknown or abbreviated flags), or any other unexpected failure, fails the suite without depending on the public
  # registry or live advisory data.
  describe "commands run against the installed npm" do
    let(:registry) { NpmRegistry.new }
    let(:package_json) do
      JSON.pretty_generate("name" => "fixture", "version" => "1.0.0", "dependencies" => { "acorn" => "^5.5.3" })
    end
    let(:package_lock) do
      JSON.pretty_generate(
        "name" => "fixture",
        "version" => "1.0.0",
        "lockfileVersion" => 3,
        "requires" => true,
        "packages" => {
          "" => { "name" => "fixture", "version" => "1.0.0", "dependencies" => { "acorn" => "^5.5.3" } },
          "node_modules/acorn" => {
            "version" => "5.5.3",
            "resolved" => registry.tarball_url("5.5.3"),
            "integrity" => registry.integrity("5.5.3")
          }
        }
      )
    end
    let(:npm_environment) do
      {
        "npm_config_registry" => registry.url,
        "npm_config_userconfig" => File::NULL,
        "npm_config_update_notifier" => "false"
      }
    end

    around do |example|
      previous_selector = Dependabot::NpmAndYarn::Helpers.npm_version_selector
      Dependabot::NpmAndYarn::Helpers.npm_version_selector = nil

      Dir.mktmpdir("npm-cache") do |cache_dir|
        environment = npm_environment.merge("npm_config_cache" => cache_dir)
        previous_environment = environment.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
        environment.each { |key, value| ENV[key] = value }

        Dependabot::SharedHelpers.in_a_temporary_directory do
          File.write("package.json", package_json)
          File.write("package-lock.json", package_lock)
          example.run
        end
      ensure
        previous_environment&.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
        registry.close
        Dependabot::NpmAndYarn::Helpers.npm_version_selector = previous_selector
      end
    end

    def locked_acorn_version
      JSON.parse(File.read("package-lock.json")).dig("packages", "node_modules/acorn", "version")
    end

    context "when updating a subdependency" do
      it "selects the newest version when no release-age gate applies" do
        described_class.run_npm8_subdependency_update_command(["acorn"])

        expect(locked_acorn_version).to eq(NpmRegistry::FRESH_VERSION)
        expect(registry.requests).to include("GET /acorn")
      end

      it "excludes a version published inside a positive release-age gate" do
        described_class.run_npm8_subdependency_update_command(["acorn"], min_release_age_arg: "--min-release-age=7")

        expect(locked_acorn_version).to eq(NpmRegistry::STABLE_VERSION)
      end

      context "when the .npmrc sets a positive release-age gate" do
        before { File.write(".npmrc", "min-release-age=7\n") }

        it "excludes a version published inside that gate" do
          described_class.run_npm8_subdependency_update_command(["acorn"])

          expect(locked_acorn_version).to eq(NpmRegistry::STABLE_VERSION)
        end

        it "admits that version when --min-release-age=0 overrides the gate" do
          described_class.run_npm8_subdependency_update_command(["acorn"], min_release_age_arg: "--min-release-age=0")

          expect(locked_acorn_version).to eq(NpmRegistry::FRESH_VERSION)
        end
      end
    end

    [nil, "--min-release-age=0", "--min-release-age=7"].each do |gate|
      it "runs the audit fix fallback with #{gate || 'no'} release-age gate" do
        described_class.run_npm_audit_fix_command(min_release_age_arg: gate)

        expect(registry.requests).to include("POST /-/npm/v1/security/advisories/bulk")
      end
    end

    it "does not hide a rejected flag" do
      expect do
        described_class.run_npm8_subdependency_update_command(["acorn"], min_release_age_arg: "--not-a-real-npm-flag")
      end.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /EUNKNOWNCONFIG/)
    end
  end
end
