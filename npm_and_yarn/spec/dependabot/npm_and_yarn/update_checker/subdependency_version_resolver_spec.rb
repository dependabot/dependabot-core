# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the dynamic describe constant or its child-context-only dependency fixture.

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

    context "with a yarn berry lockfile where the vulnerable copy is not the lowest copy" do
      let(:dependency_files) { project_dependency_files("yarn_berry/subdependency_not_lowest_copy") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "brace-expansion",
          version: "2.0.2",
          requirements: [],
          package_manager: "npm_and_yarn"
        )
      end
      # The lockfile has brace-expansion 1.1.21 (^1.1.7), 2.0.2 (^2.0.1) and 5.0.12 (^5.0.2), and the latest
      # release overall is 5.x, which is what a security update is allowed to move to.
      let(:latest_allowable_version) { "5.0.12" }

      it "returns the version the vulnerable copy moves to, not the lowest or the highest copy" do
        expect(latest_resolvable_version.to_s).to start_with("2.")
        expect(latest_resolvable_version).to be > Gem::Version.new("2.0.2")
      end

      context "when the audit fix experiment is disabled" do
        before do
          allow(Dependabot::Experiments).to receive(:enabled?)
            .with(:enable_audit_fix_fallback).and_return(false)
        end

        it "returns the version the vulnerable copy moves to, not the lowest copy" do
          expect(latest_resolvable_version.to_s).to start_with("2.")
          expect(latest_resolvable_version).to be > Gem::Version.new("2.0.2")
        end
      end

      context "when the lockfile after the update has the replaced copy and unrelated copies" do
        let(:parsed_dep) do
          Dependabot::Dependency.new(
            name: "brace-expansion",
            version: "1.1.21",
            requirements: [],
            package_manager: "npm_and_yarn",
            metadata: {
              all_versions: %w(1.1.21 2.1.7 5.0.12).map do |version|
                Dependabot::Dependency.new(
                  name: "brace-expansion", version: version, requirements: [], package_manager: "npm_and_yarn"
                )
              end
            }
          )
        end

        before do
          allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command).and_return("")
          allow(Dependabot::NpmAndYarn::NativeHelpers).to receive(:run_yarn_audit_fix_command).and_return("")
          parser = instance_double(Dependabot::NpmAndYarn::FileParser, parse: [parsed_dep])
          allow(Dependabot::NpmAndYarn::FileParser).to receive(:new).and_return(parser)
        end

        it { is_expected.to eq(Gem::Version.new("2.1.7")) }

        context "when the vulnerable copy is still in the lockfile" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "brace-expansion",
              version: "1.1.21",
              requirements: [],
              package_manager: "npm_and_yarn"
            )
          end

          before do
            allow(Dependabot::Experiments).to receive(:enabled?)
              .with(:enable_audit_fix_fallback).and_return(false)
          end

          it "keeps the existing result, the version of the lowest copy" do
            expect(latest_resolvable_version).to eq(Gem::Version.new("1.1.21"))
          end
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
      # pnpm refuses the pin on a transitive package, and the retry resolves acorn to the newest version
      # the dependents' ranges allow (5.7.4), whatever the bound is. That resolution is proposed when it
      # is within the bound.
      let(:latest_allowable_version) { "5.7.4" }

      it { is_expected.to eq(Gem::Version.new("5.7.4")) }

      context "when the resolution is above the allowable version" do
        let(:latest_allowable_version) { "5.5.0" }

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

      it "tries a deep pnpm update before pnpm audit --fix" do
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

      context "when a cooldown applies and the newer release is old enough" do
        let(:resolver) do
          described_class.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            latest_allowable_version: latest_allowable_version,
            repo_contents_path: nil,
            update_cooldown: Dependabot::Package::ReleaseCooldownOptions.new(default_days: 3)
          )
        end

        it "still resolves the update" do
          expect(latest_resolvable_version).to eq(Gem::Version.new("5.7.4"))
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

      # The file updater gates the same npm command with the cooldown, so an ungated resolution can propose a
      # version that the update then refuses (NoChangeError)
      context "when a cooldown applies" do
        let(:update_cooldown) { Dependabot::Package::ReleaseCooldownOptions.new(default_days: 3) }
        let(:resolver) do
          described_class.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            latest_allowable_version: latest_allowable_version,
            repo_contents_path: nil,
            update_cooldown: update_cooldown
          )
        end
        let(:npm_supports_min_release_age) { true }

        before do
          allow(Dependabot::NpmAndYarn::Helpers)
            .to receive(:npm_supports_min_release_age?).and_return(npm_supports_min_release_age)
          allow(Dependabot::NpmAndYarn::NativeHelpers)
            .to receive_messages(run_npm8_subdependency_update_command: "", run_npm_audit_fix_command: "")
        end

        it "resolves under the same release-age gate as the update" do
          latest_resolvable_version

          expect(Dependabot::NpmAndYarn::NativeHelpers)
            .to have_received(:run_npm8_subdependency_update_command)
            .with(["acorn"], min_release_age_arg: "--min-release-age=3")
          expect(Dependabot::NpmAndYarn::NativeHelpers)
            .to have_received(:run_npm_audit_fix_command).with(min_release_age_arg: "--min-release-age=3")
        end

        context "with a shorter semver-specific cooldown" do
          # The update's gate is at most `default_days`, so a version old enough for it is never refused
          let(:update_cooldown) do
            Dependabot::Package::ReleaseCooldownOptions.new(default_days: 3, semver_patch_days: 1)
          end

          it "uses the default cooldown" do
            latest_resolvable_version

            expect(Dependabot::NpmAndYarn::NativeHelpers)
              .to have_received(:run_npm8_subdependency_update_command)
              .with(["acorn"], min_release_age_arg: "--min-release-age=3")
          end
        end

        context "when the cooldown excludes the dependency" do
          let(:update_cooldown) do
            Dependabot::Package::ReleaseCooldownOptions.new(default_days: 3, exclude: ["acorn"])
          end

          it "does not gate the resolution" do
            latest_resolvable_version

            expect(Dependabot::NpmAndYarn::NativeHelpers)
              .to have_received(:run_npm8_subdependency_update_command).with(["acorn"], min_release_age_arg: nil)
          end
        end

        context "when the running npm does not support --min-release-age" do
          let(:npm_supports_min_release_age) { false }

          it "does not gate the resolution" do
            latest_resolvable_version

            expect(Dependabot::NpmAndYarn::NativeHelpers)
              .to have_received(:run_npm8_subdependency_update_command).with(["acorn"], min_release_age_arg: nil)
          end
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
  block = T.must(content[%r{^  /lodash@3\.10\.1:\n(?:    .*\n)+}])
  content = content.gsub("/lodash@3.10.1:", "/lodash@#{version}:").gsub("lodash: 3.10.1", "lodash: #{version}")
  if extra
    content += block.gsub("3.10.1", extra)
    es6_promise = "  /es6-promise@3.3.1:\n    resolution: {integrity: sha512-fakehash1==}\n"
    content = content.sub(es6_promise, "#{es6_promise}    dependencies:\n      lodash: #{extra}\n")
  end
  File.write("pnpm-lock.yaml", content)
  ""
end
