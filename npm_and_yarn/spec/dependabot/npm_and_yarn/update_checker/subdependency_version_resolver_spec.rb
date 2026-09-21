# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/update_checker/version_resolver"

namespace = Dependabot::NpmAndYarn::UpdateChecker
RSpec.describe namespace::SubdependencyVersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      latest_allowable_version: latest_allowable_version,
      repo_contents_path: nil
    )
  end

  let(:latest_allowable_version) { dependency.version }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:ignored_versions) { [] }

  before do
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_audit_fix_fallback).and_return(true)
  end

  after do
    Dependabot::Experiments.reset!
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    context "without a lockfile" do
      let(:dependency_files) { project_dependency_files("npm6/no_lockfile") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "etag",
          version: "1.0.0",
          requirements: [{
            file: "package.json",
            requirement: "^1.0.0",
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "npm_and_yarn"
        )
      end

      it "raises a helpful error" do
        expect { latest_resolvable_version }
          .to raise_error("Not a subdependency!")
      end
    end

    context "with an invalid package.json" do
      let(:dependency_files) { project_dependency_files("npm6/nonexistent_dependency") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.5.3",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it "gracefully handles package not found exception" do
        expect(latest_resolvable_version).to be_nil
      end
    end

    context "with a yarn.lock" do
      let(:dependency_files) { project_dependency_files("yarn/no_lockfile_change") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.1.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      # NOTE: The latest version is 6.0.2, but we can't reach it as other
      # dependencies constrain us
      it { is_expected.to eq(Gem::Version.new("5.7.4")) }
    end

    context "with a yarn berry workspace subdependency" do
      let(:dependency_files) { project_dependency_files("yarn_berry/workspace_subdependency_update") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "lodash",
          version: "3.10.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "3.10.2" }

      it "falls back to yarn npm audit --fix when yarn up -R is a no-op" do
        # Stub yarn up -R to be a no-op (returns unchanged lockfile)
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command).and_return("")
        allow(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive(:run_yarn_audit_fix_command).and_return("")

        expect(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive(:run_yarn_audit_fix_command).once

        latest_resolvable_version
      end

      context "when yarn npm audit --fix fails" do
        it "logs and continues without raising" do
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command).and_return("")
          allow(Dependabot::NpmAndYarn::NativeHelpers)
            .to receive(:run_yarn_audit_fix_command)
            .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                         message: "audit failed",
                         error_context: {}
                       ))
          allow(Dependabot.logger).to receive(:info)

          expect { latest_resolvable_version }.not_to raise_error
          expect(Dependabot.logger).to have_received(:info)
            .with("yarn npm audit --fix failed or partially fixed \u2014 continuing with any changes made")
        end
      end

      context "when enable_audit_fix_fallback experiment is disabled" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:enable_audit_fix_fallback).and_return(false)
        end

        it "does not call yarn npm audit --fix" do
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command).and_return("")

          expect(Dependabot::NpmAndYarn::NativeHelpers)
            .not_to receive(:run_yarn_audit_fix_command)

          latest_resolvable_version
        end
      end
    end

    context "with a pnpm-lock.yaml" do
      let(:dependency_files) { project_dependency_files("pnpm/no_lockfile_change") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.1.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      # pnpm refuses the pin on a transitive package, and the retry resolves
      # acorn to 5.7.4 and 6.4.2 at the depths the dependents' ranges allow,
      # whatever the bound is. The best resolution within the bound is proposed.
      let(:latest_allowable_version) { "6.4.2" }

      it { is_expected.to eq(Gem::Version.new("6.4.2")) }

      context "when an occurrence resolves above the allowable version" do
        let(:latest_allowable_version) { "6.0.2" }

        it { is_expected.to be_nil }
      end
    end

    context "with a pnpm workspace subdependency" do
      let(:dependency_files) { project_dependency_files("pnpm/workspace_subdependency_update") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "lodash",
          version: "3.10.1",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "3.10.2" }

      it "pins pnpm update to the latest allowable version" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command).and_return("")
        allow(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive_messages(run_pnpm_deep_update_command: "", run_pnpm_audit_fix_command: "")

        expect(Dependabot::NpmAndYarn::Helpers)
          .to receive(:run_pnpm_command)
          .with(
            "update lodash@3.10.2 --lockfile-only --no-save -r",
            { fingerprint: "update <dependency_name>@<latest_allowable_version> --lockfile-only --no-save -r" }
          )
        expect(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive(:run_pnpm_deep_update_command).once
        expect(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive(:run_pnpm_audit_fix_command).once

        latest_resolvable_version
      end

      it "retries without the version when pnpm refuses to pin the subdependency" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command).and_return("")
        allow(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive_messages(run_pnpm_deep_update_command: "", run_pnpm_audit_fix_command: "")

        expect(Dependabot::NpmAndYarn::Helpers)
          .to receive(:run_pnpm_command)
          .with(
            "update lodash@3.10.2 --lockfile-only --no-save -r",
            { fingerprint: "update <dependency_name>@<latest_allowable_version> --lockfile-only --no-save -r" }
          )
          .ordered
          .and_raise(
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "ERR_PNPM_UPDATE_VERSION_ON_INDIRECT_DEP  \"lodash\" (requested \"3.10.2\") is not a " \
                       "direct dependency, so the requested version cannot be recorded.",
              error_context: {}
            )
          )
        expect(Dependabot::NpmAndYarn::Helpers)
          .to receive(:run_pnpm_command)
          .with(
            "update lodash --lockfile-only --no-save -r",
            { fingerprint: "update <dependency_name> --lockfile-only --no-save -r" }
          )
          .ordered

        latest_resolvable_version
      end

      context "when the retry resolves the package at every depth" do
        let(:pinned_update) { "update lodash@3.10.2 --lockfile-only --no-save -r" }
        let(:unpinned_update) { "update lodash --lockfile-only --no-save -r" }

        before do
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command).and_return("")
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command)
            .with(pinned_update, anything)
            .and_raise(
              Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "ERR_PNPM_UPDATE_VERSION_ON_INDIRECT_DEP  \"lodash\" (requested \"3.10.2\") is not a " \
                         "direct dependency, so the requested version cannot be recorded.",
                error_context: {}
              )
            )
        end

        it "returns the resolved version when every new resolution is within the bound" do
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command)
            .with(unpinned_update, anything) { rewrite_lockfile_lodash("3.10.2") }

          expect(latest_resolvable_version).to eq(Gem::Version.new("3.10.2"))
        end

        it "returns no update when another occurrence resolves above the bound" do
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command)
            .with(unpinned_update, anything) { rewrite_lockfile_lodash("3.10.2", extra: "3.10.3") }

          expect(latest_resolvable_version).to be_nil
        end
      end

      it "falls back to pnpm audit --fix when pnpm update is a no-op" do
        # Stub pnpm update to be a no-op (returns unchanged lockfile)
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command).and_return("")
        allow(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive(:run_pnpm_audit_fix_command).and_return("")

        expect(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive(:run_pnpm_audit_fix_command).once

        latest_resolvable_version
      end

      it "tries pnpm update --depth Infinity before pnpm audit --fix" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command).and_return("")
        allow(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive_messages(run_pnpm_deep_update_command: "", run_pnpm_audit_fix_command: "")

        expect(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive(:run_pnpm_deep_update_command).once.ordered
        expect(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive(:run_pnpm_audit_fix_command).once.ordered

        latest_resolvable_version
      end

      context "when pnpm audit --fix fails" do
        it "logs and continues without raising" do
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command).and_return("")
          allow(Dependabot::NpmAndYarn::NativeHelpers)
            .to receive(:run_pnpm_audit_fix_command)
            .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                         message: "audit failed",
                         error_context: {}
                       ))
          allow(Dependabot.logger).to receive(:info)

          expect { latest_resolvable_version }.not_to raise_error
          expect(Dependabot.logger).to have_received(:info)
            .with("pnpm audit --fix failed or partially fixed \u2014 continuing with any changes made")
        end
      end

      context "when enable_audit_fix_fallback experiment is disabled" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:enable_audit_fix_fallback).and_return(false)
        end

        it "does not call pnpm audit --fix" do
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_pnpm_command).and_return("")

          expect(Dependabot::NpmAndYarn::NativeHelpers)
            .not_to receive(:run_pnpm_audit_fix_command)

          latest_resolvable_version
        end
      end
    end

    context "with a npm8 package-lock.json" do
      let(:dependency_files) { project_dependency_files("npm8/subdependency_update") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.5.3",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      it "calls run_npm_updater" do
        expect(resolver).to receive(:run_npm_updater).and_call_original
        expect(latest_resolvable_version).to eq(Gem::Version.new("5.7.4"))
      end

      context "with a directory-specific npm version and private registry" do
        let(:dependency_files) do
          project_dependency_files("npm8/subdependency_update").map do |file|
            file.dup.tap { |dependency_file| dependency_file.directory = "/frontend" }
          end
        end
        let(:credentials) do
          [Dependabot::Credential.new(
            {
              "type" => "npm_registry",
              "registry" => "https://artifactory.example.com/artifactory/api/npm/npm/",
              "replaces-base" => true,
              "token" => "auth-token"
            }
          )]
        end
        let(:corepack_env) do
          {
            "COREPACK_NPM_REGISTRY" => "https://artifactory.example.com/artifactory/api/npm/npm",
            "npm_config_registry" => "https://artifactory.example.com/artifactory/api/npm/npm",
            "COREPACK_NPM_TOKEN" => "auth-token",
            "registry" => "https://artifactory.example.com/artifactory/api/npm/npm"
          }
        end

        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:enable_audit_fix_fallback).and_return(false)
          Dependabot::NpmAndYarn::Helpers.set_effective_package_manager_version(
            "npm",
            "10.9.2",
            directory: "/frontend"
          )
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
            "corepack prepare npm@10.9.2 --activate",
            fingerprint: "corepack prepare <name>@<version> --activate",
            env: corepack_env
          ).and_return("Preparing npm@10.9.2 for immediate activation...")
          allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
            "corepack npm@10.9.2 update acorn --force --ignore-scripts --package-lock-only",
            fingerprint: "corepack npm update <dependency_names> --force --ignore-scripts --package-lock-only",
            output_observer: kind_of(Proc),
            env: corepack_env
          ).and_return("")
        end

        it "reactivates the selected npm version and uses the private registry" do
          latest_resolvable_version

          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
            "corepack prepare npm@10.9.2 --activate",
            fingerprint: "corepack prepare <name>@<version> --activate",
            env: corepack_env
          )
          expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
            "corepack npm@10.9.2 update acorn --force --ignore-scripts --package-lock-only",
            fingerprint: "corepack npm update <dependency_names> --force --ignore-scripts --package-lock-only",
            output_observer: kind_of(Proc),
            env: corepack_env
          )
        end
      end

      context "when resolving a security update" do
        let(:resolver) do
          described_class.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            latest_allowable_version: latest_allowable_version,
            repo_contents_path: nil,
            security_advisories: [
              Dependabot::SecurityAdvisory.new(
                dependency_name: "acorn",
                package_manager: "npm_and_yarn",
                vulnerable_versions: ["< 5.7.4"]
              )
            ]
          )
        end

        it "passes --min-release-age=0 so the .npmrc cooldown is bypassed" do
          allow(Dependabot::NpmAndYarn::NativeHelpers)
            .to receive_messages(run_npm8_subdependency_update_command: "", run_npm_audit_fix_command: "")

          latest_resolvable_version

          expect(Dependabot::NpmAndYarn::NativeHelpers)
            .to have_received(:run_npm8_subdependency_update_command)
            .with(["acorn"], min_release_age_arg: "--min-release-age=0")
        end
      end

      it "calls npm audit fix as a fallback" do
        allow(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive_messages(run_npm8_subdependency_update_command: "", run_npm_audit_fix_command: "")

        expect(Dependabot::NpmAndYarn::NativeHelpers)
          .to receive(:run_npm_audit_fix_command).once

        latest_resolvable_version
      end

      context "when npm audit fix fails" do
        it "logs and continues without raising" do
          allow(Dependabot::NpmAndYarn::NativeHelpers)
            .to receive(:run_npm8_subdependency_update_command).and_return("")
          allow(Dependabot::NpmAndYarn::NativeHelpers)
            .to receive(:run_npm_audit_fix_command)
            .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                         message: "audit failed",
                         error_context: {}
                       ))
          allow(Dependabot.logger).to receive(:info)

          expect { latest_resolvable_version }.not_to raise_error
          expect(Dependabot.logger).to have_received(:info)
            .with("npm audit fix failed or partially fixed \u2014 continuing with any changes made")
        end
      end

      context "when enable_audit_fix_fallback experiment is disabled" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:enable_audit_fix_fallback).and_return(false)
        end

        it "does not call npm audit fix" do
          expect(Dependabot::NpmAndYarn::NativeHelpers)
            .not_to receive(:run_npm_audit_fix_command)

          latest_resolvable_version
        end
      end

      context "when all_versions metadata is present" do
        let(:all_version_deps) do
          [
            Dependabot::Dependency.new(
              name: "acorn",
              version: "5.5.3",
              requirements: [],
              package_manager: "npm_and_yarn"
            ),
            Dependabot::Dependency.new(
              name: "acorn",
              version: "5.6.0",
              requirements: [],
              package_manager: "npm_and_yarn"
            ),
            Dependabot::Dependency.new(
              name: "acorn",
              version: "5.7.4",
              requirements: [],
              package_manager: "npm_and_yarn"
            )
          ]
        end

        let(:parsed_dep) do
          Dependabot::Dependency.new(
            name: "acorn",
            version: "5.7.4",
            requirements: [],
            package_manager: "npm_and_yarn",
            metadata: { all_versions: all_version_deps }
          )
        end

        before do
          parser = instance_double(Dependabot::NpmAndYarn::FileParser)
          allow(Dependabot::NpmAndYarn::FileParser).to receive(:new).and_return(parser)
          allow(parser).to receive(:parse).and_return([parsed_dep])
        end

        it "returns the highest version from all_versions within the allowable range" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("5.7.4"))
        end

        context "when latest_allowable_version caps the result" do
          let(:latest_allowable_version) { "5.6.0" }

          it "returns the highest version at or below the allowable version" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("5.6.0"))
          end
        end

        context "when no all_versions candidate is above the current version" do
          let(:all_version_deps) do
            [
              Dependabot::Dependency.new(
                name: "acorn",
                version: "5.5.3",
                requirements: [],
                package_manager: "npm_and_yarn"
              )
            ]
          end

          it "falls back to the combined parsed version" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("5.7.4"))
          end
        end

        context "when all_versions metadata is empty" do
          let(:parsed_dep) do
            Dependabot::Dependency.new(
              name: "acorn",
              version: "5.7.4",
              requirements: [],
              package_manager: "npm_and_yarn",
              metadata: { all_versions: [] }
            )
          end

          it "falls back to the combined parsed version" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("5.7.4"))
          end
        end

        context "when the experiment is disabled" do
          before do
            allow(Dependabot::Experiments).to receive(:enabled?)
              .with(:enable_audit_fix_fallback).and_return(false)
          end

          it "returns the combined parsed version without checking all_versions" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("5.7.4"))
          end
        end
      end
    end

    context "with a npm6 package-lock.json" do
      let(:dependency_files) { project_dependency_files("npm6/subdependency_update") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.5.3",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      # NOTE: The latest vision is 6.0.2, but we can't reach it as other
      # dependencies constrain us
      it { is_expected.to eq(Gem::Version.new("5.7.4")) }

      context "when the manifest explicitly selects modern npm" do
        before do
          directory = dependency_files.find { |file| file.name == "package.json" }&.directory
          Dependabot::NpmAndYarn::Helpers.set_effective_package_manager_version(
            "npm",
            "10.9.2",
            directory: directory,
            explicit: true
          )
        end

        after do
          Thread.current[:dependabot_corepack_effective_versions] = nil
        end

        it "rejects the incompatible lockfile without invoking the npm6 helper" do
          expect(Dependabot::SharedHelpers).not_to receive(:run_helper_subprocess)

          expect { latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /npm 10\.9\.2.*v1 lockfile/i)
        end
      end
    end

    context "when sub-dependency is bundled" do
      let(:dependency_files) { project_dependency_files("npm6/bundled_sub_dependency") }

      let(:dependency_name) { "tar" }
      let(:version) { "4.4.10" }
      let(:previous_version) { "4.4.1" }
      let(:requirements) { [] }
      let(:previous_requirements) { [] }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "tar",
          version: "4.4.1",
          requirements: [],
          package_manager: "npm_and_yarn",
          subdependency_metadata: [{ npm_bundled: true }]
        )
      end

      it { is_expected.to be_nil }
    end

    context "with a yarn.lock and a package-lock.json" do
      let(:dependency_files) { project_dependency_files("npm6_and_yarn/npm_subdependency_update") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "acorn",
          version: "5.5.3",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      let(:latest_allowable_version) { "6.0.2" }

      it { is_expected.to eq(Gem::Version.new("5.7.4")) }
    end

    context "when updating a sub-dependency across both yarn and npm lockfiles" do
      let(:dependency_files) { project_dependency_files("npm6_and_yarn/nested_sub_dependency_update") }

      let(:latest_allowable_version) { "2.0.2" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "extend",
          version: "2.0.2",
          previous_version: nil,
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end

      it { is_expected.to eq(Gem::Version.new("2.0.2")) }

      context "when out of range version" do
        let(:dependency_files) do
          project_dependency_files("npm6_and_yarn/nested_sub_dependency_update_npm_out_of_range")
        end

        it "updates out of range to latest resolvable version" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("1.3.0"))
        end
      end
    end
  end
end

# Stands in for pnpm in the temporary directory the update runs in: moves the
# fixture's lodash to `version`, and gives es6-promise its own edge to lodash
# at `extra` when given.
def rewrite_lockfile_lodash(version, extra: nil)
  content = File.read("pnpm-lock.yaml")
  block = content[%r{^  /lodash@3\.10\.1:\n(?:    .*\n)+}]
  content = content.gsub("/lodash@3.10.1:", "/lodash@#{version}:").gsub("lodash: 3.10.1", "lodash: #{version}")
  if extra
    content += block.gsub("3.10.1", extra)
    es6_promise = "  /es6-promise@3.3.1:\n    resolution: {integrity: sha512-fakehash1==}\n"
    content = content.sub(es6_promise, "#{es6_promise}    dependencies:\n      lodash: #{extra}\n")
  end
  File.write("pnpm-lock.yaml", content)
  ""
end
