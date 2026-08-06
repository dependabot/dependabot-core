# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/hex/update_checker/version_resolver"
require "tmpdir"

RSpec.describe Dependabot::Hex::UpdateChecker::VersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      prepared_dependency_files: prepared_files,
      credentials: credentials
    )
  end

  let(:mix_attempts) { [] }
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

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: dependency_requirements,
      package_manager: "hex"
    )
  end

  let(:dependency_name) { "plug" }
  let(:version) { "1.3.0" }
  let(:dependency_requirements) do
    [{ file: "mix.exs", requirement: "~> 1.3.0", groups: [], source: nil }]
  end

  let(:prepared_files) { [sanitized_mixfile, lockfile] }
  let(:mixfile) do
    Dependabot::DependencyFile.new(
      name: "mix.exs",
      content: mixfile_fixture_body
    )
  end
  let(:sanitized_mixfile) do
    sanitized_content =
      Dependabot::Hex::FileUpdater::MixfileSanitizer
      .new(mixfile_content: mixfile_fixture_body)
      .sanitized_content
    Dependabot::DependencyFile.new(
      name: "mix.exs",
      content: sanitized_content
    )
  end
  let(:mixfile_fixture_body) { fixture("mixfiles", mixfile_fixture_name) }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "mix.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
    )
  end

  let(:mixfile_fixture_name) { "minor_version" }
  let(:lockfile_fixture_name) { "minor_version" }

  # Prepare the mixfile in the same way the FilePreparer would
  before { mixfile_fixture_body.gsub!("~> 1.3.0", ">= 1.3.0") }

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    it "returns a non-normalized version, following semver" do
      expect(latest_resolvable_version.segments.count).to eq(3)
    end

    it "respects the resolvability of the mix.exs" do
      expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
      expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
    end

    context "when an unchanged Git dependency constrains the target" do
      let(:mixfile_fixture_name) { "git_source_shared_constraint" }
      let(:lockfile_fixture_name) { "git_source" }
      let(:dependency_name) { "poison" }
      let(:version) { "2.2.0" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: ">= 2.2.0", groups: [], source: nil }]
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      end

      it "includes the Git dependency's child requirements" do
        expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including("mix", "run", end_with("/fetch_git_dependencies.exs"), "--", "poison"),
          hash_including(
            env: hash_including("HEX_HOME" => a_string_matching(%r{/dependabot-hex-home})),
            fingerprint: "mix run fetch_git_dependencies.exs <dependency_name>",
            timeout: 120
          )
        )
      end

      context "when the Git dependency is scoped to another environment" do
        before do
          mixfile_fixture_body.sub!(
            'ref: "v1.2.0"',
            'ref: "v1.2.0", only: :test'
          )
        end

        it "includes its child requirements" do
          expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
        end
      end

      context "when the locked target checksum is invalid" do
        let(:dependency_name) { "plug" }
        let(:version) { "1.2.0" }
        let(:dependency_requirements) do
          [{ file: "mix.exs", requirement: ">= 1.2.0", groups: [], source: nil }]
        end
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "mix.lock",
            content: fixture("lockfiles", "git_source").sub(
              "496bef96634a49d7803ab2671482f0c5ce9ce0b7b9bc25bc0ae8e09859dd2004",
              "0" * 64
            )
          )
        end

        before { mixfile_fixture_body.sub!('{:plug, "1.2.0"}', '{:plug, ">= 1.2.0"}') }

        it "bootstraps the Git dependency before replacing the target lock" do
          expect(latest_resolvable_version).to be > Gem::Version.new("1.2.0")
        end
      end
    end

    context "when an unchanged Git dependency has a locked Git child" do
      let(:mixfile_fixture_name) { "git_source_shared_constraint" }
      let(:lockfile_fixture_name) { "git_source" }
      let(:dependency_name) { "poison" }
      let(:version) { "2.2.0" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: ">= 2.2.0", groups: [], source: nil }]
      end
      let(:outer_git_repo) { Dir.mktmpdir("dependabot-hex-outer-git") }
      let(:outer_git_url) { "file://#{outer_git_repo}" }
      let(:outer_git_revision) do
        File.write(
          File.join(outer_git_repo, "mix.exs"),
          <<~ELIXIR
            defmodule OuterGit.MixProject do
              use Mix.Project

              def project do
                [
                  app: :outer_git,
                  version: "0.1.0",
                  deps: [{:phoenix, github: "dependabot-fixtures/phoenix", ref: "v1.2.0"}]
                ]
              end
            end
          ELIXIR
        )
        Dependabot::SharedHelpers.run_shell_command(["git", "-C", outer_git_repo, "init", "--quiet"])
        Dependabot::SharedHelpers.run_shell_command(["git", "-C", outer_git_repo, "add", "mix.exs"])
        Dependabot::SharedHelpers.run_shell_command(
          [
            "git", "-C", outer_git_repo,
            "-c", "user.name=Dependabot",
            "-c", "user.email=support@dependabot.com",
            "commit", "--quiet", "-m", "Add nested Git dependency"
          ]
        )
        Dependabot::SharedHelpers.run_shell_command(
          ["git", "-C", outer_git_repo, "rev-parse", "HEAD"]
        ).strip
      end
      let(:mixfile_fixture_body) do
        fixture("mixfiles", mixfile_fixture_name).sub(
          '{:phoenix, github: "dependabot-fixtures/phoenix", ref: "v1.2.0"}',
          %({:outer_git, git: "#{outer_git_url}", ref: "#{outer_git_revision}"})
        )
      end
      let(:lockfile) do
        outer_lock = <<~LOCK
          %{"outer_git": {:git, "#{outer_git_url}", "#{outer_git_revision}",
            [ref: "#{outer_git_revision}"]},
        LOCK
        content = fixture("lockfiles", lockfile_fixture_name).sub(
          "%{",
          "#{outer_lock}  "
        )
        Dependabot::DependencyFile.new(name: "mix.lock", content: content)
      end

      after { FileUtils.remove_entry(outer_git_repo) }

      it "recursively fetches both Git dependencies before updating" do
        expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
      end
    end

    context "when the locked target release is unavailable" do
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "mix.lock",
          content: fixture("lockfiles", "minor_version").sub(
            "141058cca1fa800128391ece7f442f71a7b42a7411e6eaa56dc8f85283c8dde7",
            "0" * 64
          )
        )
      end

      it "updates without fetching the obsolete target artifact" do
        expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
      end
    end

    context "with a legacy lock entry whose child must update" do
      let(:mixfile_fixture_name) { "old_elixir" }
      let(:lockfile_fixture_name) { "old_elixir" }
      let(:dependency_name) { "phoenix" }
      let(:version) { "1.2.5" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: "~> 1.2.1", groups: [], source: nil }]
      end

      before { mixfile_fixture_body.gsub!("~> 1.2.1", ">= 1.2.1") }

      it "updates the target's children across legacy tuple sizes" do
        expect(latest_resolvable_version).to be >= Gem::Version.new("1.3.0")
      end
    end

    context "when Hex needs the installed target lock for cooldown decisions" do
      let(:lockfiles_seen_by_update) { [] }

      before do
        allow(resolver).to receive(:run_elixir_update_checker) do
          lockfiles_seen_by_update << File.read("mix.lock")
          "1.3.6"
        end
      end

      it "keeps the original target entry on disk for the update task" do
        expect(latest_resolvable_version).to eq(Dependabot::Hex::Version.new("1.3.6"))
        expect(lockfiles_seen_by_update).to contain_exactly(a_string_including(%("plug": {:hex, :plug, "1.3.5")))
      end
    end

    context "with a call to read a version file in a support file" do
      let(:mixfile_fixture_name) { "loads_file_with_require" }
      let(:prepared_files) { [sanitized_mixfile, lockfile, support_file] }
      let(:support_file) do
        Dependabot::DependencyFile.new(
          name: "module_version.ex",
          content: fixture("support_files", "module_version"),
          support_file: true
        )
      end

      it "still finds a resolvable version" do
        expect(latest_resolvable_version).not_to be_nil
      end
    end

    context "with a dependency with a bad specification" do
      let(:mixfile_fixture_name) { "bad_spec" }

      it "raises a DependencyFileNotResolvable error", :skip_ci do
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with an unresolvable mixfile" do
      let(:mixfile_fixture_name) { "unresolvable" }

      it "preserves Hex's generic resolution failure" do
        expect { resolver.latest_resolvable_version }
          .to raise_error(
            Dependabot::SharedHelpers::HelperSubprocessFailed,
            "** (Mix) Hex dependency resolution failed"
          )
      end
    end

    context "with a mix.exs that generates a deps warnings" do
      let(:mixfile_fixture_name) { "deps_warning" }

      it "respects the resolvability of the mix.exs" do
        expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
      end
    end

    context "when the update helper writes a result alongside stdout output" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including("mix", "run", end_with("/check_update.exs"), "plug"), anything) do
            File.write(".dependabot-result", "1.3.6")
            "warning from mix.exs"
          end
      end

      it "reads the version from the filesystem using an isolated Hex home" do
        expect(latest_resolvable_version).to eq(Dependabot::Hex::Version.new("1.3.6"))
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including("mix", "run", end_with("/check_update.exs"), "--", "plug"),
          hash_including(
            env: hash_including("HEX_HOME" => a_string_matching(%r{/dependabot-hex-home})),
            fingerprint: "mix run check_update.exs <dependency_name>",
            timeout: 30
          )
        )
      end
    end

    context "when the update helper returns a git SHA" do
      let(:git_sha) { "a" * 40 }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs"), "plug"), anything) do
            File.write(".dependabot-result", git_sha)
            ""
          end
      end

      it "returns the SHA without parsing it as a version" do
        expect(latest_resolvable_version).to eq(git_sha)
      end
    end

    context "when the update helper does not write a result" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs"), "plug"), anything)
          .and_return("")
      end

      it "preserves the missing result as an internal error" do
        expect { latest_resolvable_version }.to raise_error(Errno::ENOENT, /\.dependabot-result/)
      end
    end

    context "when the update helper writes an invalid result" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs"), "plug"), anything) do
            File.write(".dependabot-result", "not a version")
            ""
          end
      end

      it "preserves the invalid result as an internal error" do
        expect { latest_resolvable_version }.to raise_error(ArgumentError, /Malformed version number string/)
      end
    end

    context "when dependency resolution times out" do
      let(:timeout_error) do
        helper_failure(
          "Timed out due to inactivity after 30 seconds",
          process_exit_value: "pid 123 exit 124"
        )
      end

      before do
        stub_resolution_failure(timeout_error)
      end

      it "preserves the inactivity timeout as an internal helper failure after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /30 seconds/)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when Hex names the unauthenticated source" do
      let(:original_cause) { RuntimeError.new("raw helper details") }
      let(:authentication_error) do
        helper_failure(
          "** (Mix) No authenticated organization found for dependabot. " \
          "Do you want to authenticate it now? [Yn] "
        )
      end

      before { stub_resolution_failure(authentication_error, cause: original_cause) }

      it "reports that source after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("dependabot")
            expect(error.cause).to be_nil
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when Hex includes the prompt after the unauthenticated source" do
      let(:authentication_error) do
        helper_failure(
          "** (Mix) No authenticated organization found for dependabot. Do you want to authenticate it now?"
        )
      end

      before { stub_resolution_failure(authentication_error) }

      it "reports that source after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("dependabot")
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when repository credentials omit the URL" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "acme/private"
            }
          )
        ]
      end

      it "reports the repository name" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("acme/private")
          end
      end
    end

    context "with credentials configured for resolution" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "private_repo",
              "url" => "https://private.example",
              "public_key" => "public key"
            }
          )
        ]
      end

      it "shares one external temporary Hex home and removes it afterwards" do
        hex_homes = []
        mix_exs_values = []
        project_directory = T.let(nil, T.nilable(String))
        original_mix_exs = ENV.fetch("MIX_EXS", nil)

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including("lib/configure_credentials.exs"), anything) do |_command, options|
            hex_homes << options.fetch(:env).fetch("HEX_HOME")
            mix_exs_values << options.fetch(:env).fetch("MIX_EXS")
            ""
          end
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs")), anything) do |_command, options|
            hex_homes << options.fetch(:env).fetch("HEX_HOME")
            mix_exs_values << options.fetch(:env).fetch("MIX_EXS")
            project_directory = Dir.pwd
            File.write(".dependabot-result", "1.3.6")

            ""
          end

        ENV["MIX_EXS"] = "inherited/mix.exs"
        expect(latest_resolvable_version).to eq(Dependabot::Hex::Version.new("1.3.6"))
        expect(hex_homes.length).to eq(2)
        expect(hex_homes.uniq.length).to eq(1)
        expect(mix_exs_values.uniq).to eq(["mix.exs"])
        expect(project_directory).not_to be_nil
        expect(hex_homes.first).not_to start_with(project_directory.to_s)
        expect(File.exist?(hex_homes.first)).to be(false)
      ensure
        ENV["MIX_EXS"] = original_mix_exs
      end
    end

    context "with dependency task aliases" do
      let(:mixfile_fixture_name) { "dependency_task_aliases" }

      it "resolves without invoking the project aliases" do
        expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
      end
    end

    context "when the environments for another dependency diverge" do
      # Updating `credo` adds its `poison` subdependency to `dev`, while the
      # Mixfile explicitly limits `poison` to `test`.
      let(:mixfile_fixture_name) { "diverging_environments" }
      let(:lockfile_fixture_name) { "diverging_environments" }
      let(:dependency_name) { "credo" }
      let(:version) { "0.6.0" }
      let(:dependency_requirements) do
        [{
          file: "mix.exs",
          requirement: "~> 0.6",
          groups: %w(dev test),
          source: nil
        }]
      end

      it "returns no update from the real Mix diagnostic" do
        # In an ideal world, Dependabot would update the environment specified
        # in the Mixfile. In the meantime, we treat this as impossible to update.
        expect(resolver.latest_resolvable_version).to be_nil
      end
    end

    context "with an invalid requirement diagnostic" do
      let(:diagnostic) { "** (Version.InvalidRequirementError) invalid requirement: >= nope" }
      let(:invalid_requirement_error) do
        helper_failure("warning: project output\n#{diagnostic}\n    stack trace")
      end

      before { stub_resolution_failure(invalid_requirement_error) }

      it "reports a user-facing file error after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable, diagnostic)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with Hex 2.5.4's malformed requirement diagnostic" do
      let(:diagnostic) do
        "** (Mix) Required version >= nope for package jason is incorrectly specified (from: mix.exs)"
      end
      let(:invalid_requirement_error) do
        helper_failure("warning: project output\n#{diagnostic}\n    stack trace")
      end

      before { stub_resolution_failure(invalid_requirement_error) }

      it "reports a user-facing file error after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable, diagnostic)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with Hex 2.5.4's malformed requirement diagnostic in an umbrella app" do
      let(:invalid_requirement_error) do
        helper_failure(
          "** (Mix) Required version >= nope for package jason is incorrectly specified " \
          "(from: apps/dependabot_business/mix.exs)"
        )
      end

      before { stub_resolution_failure(invalid_requirement_error) }

      it "reports a user-facing file error after one attempt" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::DependencyFileNotResolvable)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with Hex 2.5.4's malformed requirement diagnostic in an umbrella path containing spaces" do
      let(:invalid_requirement_error) do
        helper_failure(
          "** (Mix) Required version >= nope for package jason is incorrectly specified " \
          "(from: umbrella apps/business/mix.exs)"
        )
      end

      before { stub_resolution_failure(invalid_requirement_error) }

      it "reports a user-facing file error after one attempt" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::DependencyFileNotResolvable)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with Hex 2.5.4's malformed requirement diagnostic in a Unicode umbrella path" do
      let(:invalid_requirement_error) do
        helper_failure(
          "** (Mix) Required version >= nope for package jason is incorrectly specified " \
          "(from: apps/geschäft/mix.exs)"
        )
      end

      before { stub_resolution_failure(invalid_requirement_error) }

      it "reports a user-facing file error after one attempt" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::DependencyFileNotResolvable)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with a generic Hex dependency resolution failure" do
      let(:resolution_error) { helper_failure("** (Mix) Hex dependency resolution failed") }

      before { stub_resolution_failure(resolution_error) }

      it "preserves the original helper failure after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, resolution_error.message)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when a resolution error contains a raw repository URL query pair" do
      let(:repository_url) { "https://private.example?access_token=secret%2Bvalue" }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "private_repo",
              "url" => repository_url
            }
          )
        ]
      end
      let(:resolution_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Could not fetch #{repository_url}",
          error_context: { "url" => repository_url },
          trace: ["Fetching #{repository_url}"]
        )
      end
      let(:cause) { RuntimeError.new("cause contains secret%2Bvalue") }

      before do
        allow(Dependabot::Hex::CredentialHelpers).to receive(:configure)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs"), dependency_name), anything) do
            mix_attempts << :resolution
            raise resolution_error, cause: cause
          end
      end

      it "sanitizes the error and detaches the original cause" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
            expect(error.message).to include("access_token=***")
            expect(error.full_message).not_to include("secret%2Bvalue")
            expect(error.error_context.to_s).not_to include("secret%2Bvalue")
            expect(error.trace.to_s).not_to include("secret%2Bvalue")
            expect(error.cause).to be_nil
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with the target missing from the active environment" do
      let(:diagnostic) { "** (Mix) Unknown dependency plug for environment prod" }
      let(:unknown_dependency_error) do
        helper_failure("warning: project output\n#{diagnostic}\n    stack trace")
      end

      before { stub_resolution_failure(unknown_dependency_error) }

      it "reports a user-facing file error after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable, diagnostic)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with a qualified fetch failure and ambiguous access diagnostic" do
      let(:fetch_error) do
        helper_failure(
          <<~ERROR
            Failed to fetch record for private_repo/plug from registry
            This could be because the package does not exist, it was spelled incorrectly or you don't have permissions to it
            ** (Mix) Hex dependency resolution failed
          ERROR
        )
      end

      before { stub_resolution_failure(fetch_error) }

      it "preserves the original helper failure after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, fetch_error.message)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when diagnostics mention multiple private sources" do
      let(:mixed_source_error) do
        helper_failure(
          <<~ERROR
            Failed to fetch record for first_repo/plug from registry
            :timeout
            Failed to fetch record for second_repo/jason from registry
            Authentication failed (401)
            ** (Mix) Hex dependency resolution failed
          ERROR
        )
      end

      before { stub_resolution_failure(mixed_source_error) }

      it "preserves the original helper failure instead of correlating diagnostics" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, mixed_source_error.message)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with an unknown package in the lockfile" do
      let(:lockfile_error) { helper_failure("Unknown package version plug 9.9.9 in lockfile") }

      before { stub_resolution_failure(lockfile_error) }

      it "keeps the failure internal after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, lockfile_error.message)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with an unexpected helper exception" do
      let(:unexpected_error) { helper_failure("** (RuntimeError) unexpected helper failure") }

      before { stub_resolution_failure(unexpected_error) }

      it "keeps the original failure internal after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, unexpected_error.message)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "without a lockfile" do
      let(:prepared_files) { [sanitized_mixfile] }

      it "respects the resolvability of the mix.exs" do
        expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
      end

      context "with a mix.exs that has caused trouble in the past" do
        let(:mixfile_fixture_name) { "coxir" }
        let(:dependency_name) { "kcl" }
        let(:version) { nil }
        let(:dependency_requirements) do
          [{ file: "mix.exs", requirement: "~> 1.1", groups: [], source: nil }]
        end

        it "resolves without issue" do
          expect(latest_resolvable_version).to be >= Gem::Version.new("1.1.0")
        end
      end
    end

    def helper_failure(message, error_context = {})
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(
        message: message,
        error_context: error_context
      )
    end

    def stub_resolution_failure(error, cause: nil)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(array_including(end_with("/check_update.exs"), dependency_name), anything)
        .and_wrap_original do
          mix_attempts << :resolution
          raise error, cause: cause
        end
    end
  end
end
