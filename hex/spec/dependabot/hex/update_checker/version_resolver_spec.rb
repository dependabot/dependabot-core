# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/hex/update_checker/version_resolver"

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

      it "raises a file error with the solver explanation" do
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /version solving failed/)
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
      before { stub_resolution_success(result: "1.3.6", stdout: "warning from mix.exs") }

      it "reads the version from the filesystem using an isolated Hex home" do
        expect(latest_resolvable_version).to eq(Dependabot::Hex::Version.new("1.3.6"))
        expect(Dependabot::CommandHelpers).to have_received(:capture3_with_timeout).with(
          array_including(
            hash_including("HEX_HOME" => end_with("/.hex")),
            %w(mix mix),
            "run",
            end_with("/check_update.exs"),
            "--",
            "plug"
          ),
          timeout: 30
        )
      end
    end

    context "when the update helper returns a git SHA" do
      let(:git_sha) { "a" * 40 }

      before { stub_resolution_success(result: git_sha) }

      it "returns the SHA without parsing it as a version" do
        expect(latest_resolvable_version).to eq(git_sha)
      end
    end

    context "when the update helper does not write a result" do
      before { stub_resolution_success }

      it "preserves the missing result as an internal error" do
        expect { latest_resolvable_version }.to raise_error(Errno::ENOENT, /\.dependabot-result/)
      end
    end

    context "when the update helper writes an invalid result" do
      before { stub_resolution_success(result: "not a version") }

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

    context "when a qualified private source fails authentication" do
      let(:authentication_error) do
        helper_failure(
          <<~ERROR
            Failed to fetch record for private_repo/plug from registry
            Authentication failed (401)
            ** (Mix) Hex dependency resolution failed
          ERROR
        )
      end

      before { stub_resolution_failure(authentication_error) }

      it "reports the qualified repository after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("private_repo")
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when a qualified organization source fails authentication" do
      let(:authentication_error) do
        helper_failure(
          <<~ERROR
            Failed to fetch record for hexpm:dependabot/plug from registry
            No authenticated user found. Run `mix hex.user auth` to authenticate
            ** (Mix) Hex dependency resolution failed
          ERROR
        )
      end

      before { stub_resolution_failure(authentication_error) }

      it "reports the organization name after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("dependabot")
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when a qualified private source times out" do
      let(:source_timeout_error) do
        helper_failure(
          <<~ERROR
            Failed to fetch record for private_repo/plug from registry
            :timeout
            ** (Mix) Hex dependency resolution failed
          ERROR
        )
      end

      before { stub_resolution_failure(source_timeout_error) }

      it "reports the qualified repository after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceTimedOut) do |error|
            expect(error.source).to eq("private_repo")
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when a qualified private source refuses the connection" do
      let(:bad_response_error) do
        helper_failure(
          <<~ERROR
            Failed to fetch record for private_repo/plug from registry
            https://user:super-secret@private.example
            :econnrefused
            ** (Mix) Hex dependency resolution failed
          ERROR
        )
      end

      before { stub_resolution_failure(bad_response_error) }

      it "reports a sanitized private-source response after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceBadResponse) do |error|
            expect(error.source).to eq("private_repo")
            expect(error.message).to include(":econnrefused")
            expect(error.message).not_to include("super-secret")
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when a qualified private source returns a server error" do
      let(:bad_response_error) do
        helper_failure(
          <<~ERROR
            Failed to fetch record for private_repo/plug from registry
            https://user:super-secret@private.example
            HTTP status code: 503
            ** (Mix) Hex dependency resolution failed
          ERROR
        )
      end

      before { stub_resolution_failure(bad_response_error) }

      it "reports a sanitized private-source response after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceBadResponse) do |error|
            expect(error.source).to eq("private_repo")
            expect(error.message).to include("HTTP status code: 503")
            expect(error.message).not_to include("super-secret")
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with Hex's ambiguous private-package access diagnostic" do
      let(:ambiguous_access_error) do
        helper_failure(
          <<~ERROR
            Failed to fetch record for private_repo/plug from registry
            This could be because the package does not exist, it was spelled incorrectly or you don't have permissions to it
            ** (Mix) Hex dependency resolution failed
          ERROR
        )
      end

      before { stub_resolution_failure(ambiguous_access_error) }

      it "reports an honest file error without claiming authentication after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include('package "plug"')
            expect(error.message).to include('source "private_repo"')
            expect(error.message).not_to include("authentication")
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with Hex's ambiguous public-package access diagnostic" do
      let(:ambiguous_access_error) do
        helper_failure(
          <<~ERROR
            Failed to fetch record for plug from registry
            This could be because the package does not exist, it was spelled incorrectly or you don't have permissions to it
            ** (Mix) Hex dependency resolution failed
          ERROR
        )
      end

      before { stub_resolution_failure(ambiguous_access_error) }

      it "reports the package without inventing a source after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include('package "plug"')
            expect(error.message).not_to include("source")
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when the second private source fails authentication" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "first_repo",
              "url" => "https://first.example.com"
            }
          ),
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "second_repo",
              "url" => "https://second.example.com"
            }
          )
        ]
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including("lib/configure_credentials.exs", "first_repo"), anything)
          .and_return("")
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including("lib/configure_credentials.exs", "second_repo"), anything)
          .and_raise(
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "credential configuration failed",
              error_context: {}
            )
          )
      end

      it "reports the source being configured rather than the first credential" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("second_repo")
          end
      end
    end

    context "with a deps.update alias" do
      let(:mixfile_fixture_name) { "deps_update_alias" }

      it "resolves without invoking the project alias" do
        expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
      end
    end

    context "when the environments for another dependency diverge" do
      let(:divergence_error) { helper_failure("Dependencies have diverged") }

      before { stub_resolution_failure(divergence_error) }

      it "returns no update after one attempt" do
        # In an ideal world, Dependabot would update the environment specified
        # in the Mixfile. In the meantime, we treat this as impossible to update.
        expect(resolver.latest_resolvable_version).to be_nil
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with an invalid requirement diagnostic" do
      let(:invalid_requirement_error) do
        helper_failure("** (Version.InvalidRequirementError) invalid requirement: >= nope")
      end

      before { stub_resolution_failure(invalid_requirement_error) }

      it "reports a user-facing file error after one attempt" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::DependencyFileNotResolvable)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with Hex dependency resolution failure" do
      let(:resolution_error) { helper_failure("** (Mix) Hex dependency resolution failed") }

      before { stub_resolution_failure(resolution_error) }

      it "reports a user-facing file error after one attempt" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::DependencyFileNotResolvable)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with a PubGrub conflict explanation" do
      before do
        stub_resolution_output(
          stdout: "#{fixture('resolver_errors/pubgrub_conflict_stdout')}\nunrelated warning",
          stderr: fixture("resolver_errors/pubgrub_conflict_stderr")
        )
      end

      it "surfaces the sanitized solver explanation after classifying stderr" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("Because \"your app\" depends on \"ecto\"")
            expect(error.message).to include("version solving failed")
            expect(error.message).not_to include("unrelated warning")
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with a dependency-policy rejection" do
      before do
        stub_resolution_output(
          stdout: fixture("resolver_errors/policy_rejection_stdout"),
          stderr: fixture("resolver_errors/policy_rejection_stderr")
        )
      end

      it "surfaces policy details without recommending a policy bypass" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include("Note: active policy hides 1 version")
            expect(error.message).to include("Active policy: enforceorg/strict-prod")
            expect(error.message).not_to include("HEX_POLICY")
            expect(error.message).not_to include("run without the policy")
          end
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when stdout resembles a solver conflict but stderr is unexpected" do
      before do
        stub_resolution_output(
          stdout: fixture("resolver_errors/pubgrub_conflict_stdout"),
          stderr: "** (RuntimeError) unexpected helper failure"
        )
      end

      it "keeps the failure internal because stdout is not a classifier" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /unexpected helper failure/)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with the target missing from the active environment" do
      let(:unknown_dependency_error) do
        helper_failure("** (Mix) Unknown dependency plug for environment prod")
      end

      before { stub_resolution_failure(unknown_dependency_error) }

      it "reports a user-facing file error after one attempt" do
        expect { latest_resolvable_version }.to raise_error(Dependabot::DependencyFileNotResolvable)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when a source-less OAuth token exchange fails" do
      let(:credentials) { [organization_credential("dependabot")] }
      let(:oauth_error) { helper_failure("Failed to exchange API key for OAuth token") }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including("lib/configure_credentials.exs", "organization", "dependabot"), anything)
          .and_return("")
        stub_resolution_failure(oauth_error)
      end

      it "does not guess the organization from the available credential" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, oauth_error.message)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "when public Hex.pm has a transient network failure" do
      let(:public_timeout_error) do
        helper_failure(
          <<~ERROR
            Failed to fetch record for plug from registry
            :timeout
            ** (Mix) Hex dependency resolution failed
          ERROR
        )
      end

      before { stub_resolution_failure(public_timeout_error) }

      it "keeps the failure internal after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, public_timeout_error.message)
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

    def organization_credential(organization, token: "token")
      Dependabot::Credential.new(
        {
          "type" => "hex_organization",
          "organization" => organization,
          "token" => token
        }
      )
    end

    def helper_failure(message, error_context = {})
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(
        message: message,
        error_context: error_context
      )
    end

    def stub_resolution_failure(error)
      exit_status = error.error_context[:process_exit_value].to_s.include?("exit 124") ? 124 : 1
      stub_resolution_output(stdout: "", stderr: error.message, exit_status: exit_status)
    end

    def stub_resolution_success(result: nil, stdout: "")
      stub_resolution_output(stdout: stdout, stderr: "", exit_status: 0) do
        File.write(".dependabot-result", result) if result
      end
    end

    def stub_resolution_output(stdout:, stderr:, exit_status: 1, &block)
      allow(Dependabot::CommandHelpers).to receive(:capture3_with_timeout).and_call_original
      allow(Dependabot::CommandHelpers).to receive(:capture3_with_timeout)
        .with(
          array_including(end_with("/check_update.exs"), dependency_name),
          timeout: 30
        ) do
          mix_attempts << :resolution
          block&.call
          [stdout, stderr, Dependabot::CommandHelpers::ProcessStatus.new(nil, exit_status), 0.1]
        end
    end
  end
end
