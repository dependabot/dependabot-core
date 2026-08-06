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
            fingerprint: "mix run check_update.exs plug",
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
      let(:authentication_error) do
        helper_failure("** (Mix) No authenticated organization found for dependabot.")
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
        project_directory = T.let(nil, T.nilable(String))

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including("lib/configure_credentials.exs"), anything) do |_command, options|
            hex_homes << options.fetch(:env).fetch("HEX_HOME")
            ""
          end
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs")), anything) do |_command, options|
            hex_homes << options.fetch(:env).fetch("HEX_HOME")
            project_directory = Dir.pwd
            File.write(".dependabot-result", "1.3.6")

            ""
          end

        expect(latest_resolvable_version).to eq(Dependabot::Hex::Version.new("1.3.6"))
        expect(hex_homes.length).to eq(2)
        expect(hex_homes.uniq.length).to eq(1)
        expect(project_directory).not_to be_nil
        expect(hex_homes.first).not_to start_with(project_directory.to_s)
        expect(File.exist?(hex_homes.first)).to be(false)
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

    context "with Hex 2.5.4's malformed requirement diagnostic" do
      let(:invalid_requirement_error) do
        helper_failure(
          "** (Mix) Required version >= nope for package jason is incorrectly specified (from: mix.exs)"
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

    def stub_resolution_failure(error)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(array_including(end_with("/check_update.exs"), dependency_name), anything)
        .and_wrap_original do
          mix_attempts << :resolution
          raise error
        end
    end
  end
end
