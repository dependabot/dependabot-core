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
      original_dependency_files: original_files,
      credentials: credentials
    )
  end

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

  let(:original_files) { [mixfile, lockfile] }
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
      let(:original_files) { [mixfile, lockfile, support_file] }
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

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a mix.exs that generates a deps warnings" do
      let(:mixfile_fixture_name) { "deps_warning" }

      it "respects the resolvability of the mix.exs" do
        expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
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
      # In this example, updating `credo` would add its sub-dependency,
      # `poison`, to the `dev` environment, but the Mixfile explicitly specifies
      # that `poison` should only be available in the `test` environment.
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

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        # In an ideal world, Dependabot would update the environment specified
        # for `poison` in the Mixfile. In the meantime, though, we just treat
        # this as an impossible-to-update dependency.
        expect(resolver.latest_resolvable_version).to be_nil
      end
    end

    context "when a source-less OAuth token exchange fails" do
      let(:oauth_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Failed to exchange API key for OAuth token",
          error_context: {}
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_raise(oauth_error)
      end

      context "with one organization credential" do
        let(:credentials) { [organization_credential("dependabot")] }

        it "does not attribute the source-less failure to that organization" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end

      context "with duplicate credentials for one organization" do
        let(:credentials) do
          [
            organization_credential("dependabot", token: "first-token"),
            organization_credential("dependabot", token: "second-token")
          ]
        end

        it "does not infer a source from duplicate credentials" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end
    end

    context "when update-check diagnostics include repository query credentials" do
      let(:repository_secret) { "secret%2Bvalue" }
      let(:repository_url) { "https://repo.example.com?access_token=#{repository_secret}" }
      let(:credentials) { [repository_credential(repository_url)] }
      let(:secret_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Request failed for #{repository_url}",
          error_context: {
            stderr_output: "Request failed for #{repository_url}",
            args: [["hex_repository", "dependabot", repository_url]]
          },
          trace: ["Request failed for #{repository_url}"]
        )
      end

      context "when checking the prepared requirements fails" do
        before { stub_update_checks(secret_error, "1.3.6") }

        it "redacts and detaches the helper failure" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
              expect(error.message).to include("access_token=***")
              expect(error.full_message).not_to include(repository_secret)
              expect(error.error_context.inspect).not_to include(repository_secret)
              expect(error.trace&.join).not_to include(repository_secret)
              expect(error.cause).to be_nil
            end
        end
      end

      context "when a sanitized failure is translated to an authentication error" do
        let(:authentication_error) do
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "No authenticated organization found for hexpm:dependabot.\nRequest failed for #{repository_url}",
            error_context: {}
          )
        end

        before { stub_update_checks(authentication_error) }

        it "redacts and detaches the authentication error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
              expect(error.source).to eq("hexpm:dependabot")
              expect(error.full_message).not_to include(repository_secret)
              expect(error.cause).to be_nil
            end
        end
      end

      context "when the original requirements fail without needing redaction" do
        let(:original_requirements_error) do
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "Original requirements failed",
            error_context: {}
          )
        end

        before { stub_update_checks(secret_error, original_requirements_error) }

        it "detaches the not-resolvable error from the sanitized outer failure" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
              expect(error.message).to eq("Original requirements failed")
              expect(error.full_message).not_to include(repository_secret)
              expect(error.cause).to be_nil
            end
        end
      end
    end

    context "when update-check error context contains the legacy credential payload" do
      let(:organization_token) { "organization-secret-token" }
      let(:repository_auth_key) { "repository-secret-auth-key" }
      let(:repository_public_key) { "-----BEGIN PUBLIC KEY-----\nrepository-secret-pem\n-----END PUBLIC KEY-----" }
      let(:truncated_query_pair) { "access_token=query-" }
      let(:truncated_stderr) do
        "#{'x' * (50_001 - truncated_query_pair.length)}#{truncated_query_pair}"
      end
      let(:repository_url) do
        "https://url-user:url-password@repo.example.com/packages?access_token=query-secret"
      end
      let(:credentials) do
        [
          organization_credential("dependabot", token: organization_token),
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => repository_url,
              "auth-key" => repository_auth_key,
              "public-key" => repository_public_key
            }
          )
        ]
      end
      let(:credential_payload_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Update check failed",
          error_context: {
            command: "mix run check_update.exs",
            function: "get_latest_resolvable_version",
            args: ["/tmp/project", dependency_name, Dependabot::Hex::CredentialHelpers.hex_credentials(credentials)],
            stderr_output: truncated_stderr,
            time_taken: 1.25,
            process_exit_value: "exit 1"
          }
        )
      end

      before { stub_update_checks(credential_payload_error, "1.3.6") }

      it "removes credential-bearing arguments and truncated stderr while retaining safe context" do
        expect(truncated_stderr.length).to eq(50_001)
        expect(truncated_stderr).to end_with(truncated_query_pair)

        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
            expect(error.error_context).to include(
              command: "mix run check_update.exs",
              function: "get_latest_resolvable_version",
              time_taken: 1.25,
              process_exit_value: "exit 1"
            )
            expect(error.error_context).not_to include(:args, :stderr_output)
            diagnostic_surface = [error.error_context, error.sentry_context].inspect
            expect(diagnostic_surface).not_to include(
              organization_token,
              repository_auth_key,
              repository_public_key,
              "url-user",
              "url-password",
              "query-secret",
              truncated_query_pair
            )
            expect(error.cause).to be_nil
          end
      end
    end

    context "when the helper reports ambiguous repository diagnostics" do
      let(:diagnostics) do
        [
          'Public key fingerprint mismatch for repo "dependabot"',
          'Downloading public key for repo "dependabot" failed: {:error, :econnrefused}',
          'Failed to decode public key for repo "dependabot"',
          "Failed to fetch record for dependabot"
        ]
      end

      it "re-raises each original failure unchanged" do
        diagnostics.each do |diagnostic|
          ambiguous_error =
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: diagnostic,
              error_context: {}
            )
          stub_update_checks(ambiguous_error, "1.3.6")

          expect { latest_resolvable_version }.to raise_error do |error|
            expect(error).to equal(ambiguous_error)
          end
        end
      end
    end

    context "when an unknown update-check failure has no configured query credentials" do
      let(:unknown_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Unknown update-check failure",
          error_context: {}
        )
      end

      before { stub_update_checks(unknown_error, "1.3.6") }

      it "re-raises the original failure unchanged" do
        expect { latest_resolvable_version }.to raise_error do |error|
          expect(error).to equal(unknown_error)
        end
      end
    end

    context "without a lockfile" do
      let(:original_files) { [mixfile] }
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

    def repository_credential(url)
      Dependabot::Credential.new(
        {
          "type" => "hex_repository",
          "repo" => "dependabot",
          "url" => url,
          "public-key-fingerprint" => "SHA256:fingerprint"
        }
      )
    end

    def stub_update_checks(*results)
      allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess) do
        result = results.shift
        raise result if result.is_a?(StandardError)

        result
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
  end
end
