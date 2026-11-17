# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex/credential_helpers"
require "openssl"
require "tmpdir"

RSpec.describe Dependabot::Hex::CredentialHelpers do
  extend T::Sig

  describe ".configure" do
    subject(:configure) { described_class.configure(credentials: credentials, env: env) }

    let(:credentials) { [] }
    let(:env) { { "HEX_HOME" => "/tmp/hex-home", "MIX_QUIET" => "1" } }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")
    end

    context "with organization credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_organization",
              "organization" => "dependabot",
              "token" => "organization-secret-token"
            }
          )
        ]
      end

      it "authenticates from the packaged helper project without exposing the token" do
        configure

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including("lib/configure_credentials.exs", "--", "organization", "dependabot"),
          hash_including(
            cwd: Dependabot::Hex::NativeHelpers.hex_helpers_dir,
            env: env.merge("DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "organization-secret-token"),
            fingerprint: "mix run configure_credentials.exs organization dependabot"
          )
        )
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command) do |command, options|
          expect(command).not_to include("organization-secret-token")
          expect(options.fetch(:fingerprint)).not_to include("organization-secret-token")
        end
      end
    end

    context "with repository credentials using dependabot.yml key spellings" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com",
              "auth-key" => "repository-secret-key",
              "public-key-fingerprint" => "SHA256:public-key-fingerprint",
              "public-key" => "public-key"
            }
          )
        ]
      end

      it "passes the normalized values in the isolated environment" do
        configure

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including(
            "lib/configure_credentials.exs",
            "--",
            "repository",
            "dependabot",
            "SHA256:public-key-fingerprint"
          ),
          hash_including(
            cwd: Dependabot::Hex::NativeHelpers.hex_helpers_dir,
            env: env.merge(
              "DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "repository-secret-key",
              "DEPENDABOT_HEX_PUBLIC_KEY" => "public-key",
              "DEPENDABOT_HEX_REPOSITORY_URL_TOKEN" => "https://repo.example.com"
            )
          )
        )
      end
    end

    context "with a secret-bearing repository URL" do
      let(:repository_url) do
        "https://url-user:url-password@repo.example.com/private?access_token=url-query-secret"
      end
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => repository_url
            }
          )
        ]
      end
      let(:invocation) { {} }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, **options|
          invocation[:env] = options.fetch(:env)

          raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "credential configuration failed",
            error_context: {
              command: Shellwords.join(command),
              fingerprint: options.fetch(:fingerprint)
            }
          )
        end
      end

      it "keeps URL credentials out of argv and diagnostic context" do
        expect { configure }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
            diagnostic = [error.message, error.error_context.inspect].join("\n")

            expect(diagnostic).not_to include(repository_url)
            expect(diagnostic).not_to include("url-user")
            expect(diagnostic).not_to include("url-password")
            expect(diagnostic).not_to include("url-query-secret")
          end

        expect(Dependabot::SharedHelpers.sanitize_env_for_logging(invocation.fetch(:env))).to include(
          "DEPENDABOT_HEX_REPOSITORY_URL_TOKEN" => "<redacted>"
        )
      end
    end

    context "with an unauthenticated repository" do
      let(:hex_home) { Dir.mktmpdir("dependabot-hex-home") }
      let(:env) { { "HEX_HOME" => hex_home, "MIX_QUIET" => "1" } }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com"
            }
          )
        ]
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      end

      after do
        FileUtils.rm_rf(hex_home)
      end

      it "delegates repository defaults to the public Hex task" do
        expect { configure }.not_to raise_error
      end

      it "does not require an auth key or public key settings" do
        configure

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including(
            "lib/configure_credentials.exs",
            "--",
            "repository",
            "dependabot",
            ""
          ),
          hash_including(
            env: env.merge(
              "DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "",
              "DEPENDABOT_HEX_PUBLIC_KEY" => "",
              "DEPENDABOT_HEX_REPOSITORY_URL_TOKEN" => "https://repo.example.com"
            )
          )
        )
      end
    end

    context "with repository authentication persisted across Mix processes" do
      let(:hex_home) { Dir.mktmpdir("dependabot-hex-home") }
      let(:env) { { "HEX_HOME" => hex_home, "MIX_QUIET" => "1" } }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com",
              "auth-key" => "repository-secret-key"
            }
          )
        ]
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      end

      after do
        FileUtils.rm_rf(hex_home)
      end

      it "is available to a subsequent real Hex invocation using the same HEX_HOME" do
        configure

        configured_auth_key = Dependabot::SharedHelpers.run_shell_command(
          ["mix", "hex.repo", "show", "dependabot", "--auth-key"],
          cwd: Dependabot::Hex::NativeHelpers.hex_helpers_dir,
          env: { "HEX_HOME" => hex_home }
        )

        expect(configured_auth_key.strip).to eq("repository-secret-key")
      end
    end

    context "with concurrent supplied public keys" do
      let(:public_key) { OpenSSL::PKey::RSA.generate(1024).public_to_pem }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => "https://repo.example.com",
              "public-key" => public_key
            }
          )
        ]
      end
      let(:hex_homes) { Array.new(2) { Dir.mktmpdir("dependabot-hex-home") } }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      end

      after do
        hex_homes.each { |hex_home| FileUtils.rm_rf(hex_home) }
      end

      it "uses isolated exclusive files and removes them after separate BEAM invocations" do
        threads = hex_homes.map do |hex_home|
          Thread.new do
            described_class.configure(
              credentials: credentials,
              env: { "HEX_HOME" => hex_home, "MIX_QUIET" => "1", "TMPDIR" => "/proc" }
            )
          end
        end

        threads.each(&:value)

        hex_homes.each do |hex_home|
          expect(Dir.glob(File.join(hex_home, "**", "*.pem"))).to be_empty
        end
      end
    end

    context "when configuration fails" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "second_repo",
              "url" => "https://repo.example.com"
            }
          )
        ]
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_raise(
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "mix hex.repo add failed",
              error_context: {}
            )
          )
      end

      it "preserves the exact source being configured" do
        expect { configure }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
            expect(error.error_context).to include(source: "second_repo")
          end
      end
    end
  end

  describe ".authentication_source" do
    subject(:authentication_source) { described_class.authentication_source(error) }

    let(:error) do
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(
        message: error_message,
        error_context: error_context
      )
    end
    let(:error_context) { {} }
    let(:error_message) { "unclassified error" }

    context "with an exact source context regardless of message wording" do
      let(:error_context) { { source: "second_repo" } }

      it { is_expected.to eq("second_repo") }
    end

    context "with a legacy organization authentication message" do
      let(:error_message) { "No authenticated organization found for dependabot." }

      it { is_expected.to eq("dependabot") }
    end

    context "with a Mix-prefixed legacy organization authentication message" do
      let(:error_message) { "** (Mix) No authenticated organization found for dependabot." }

      it { is_expected.to eq("dependabot") }
    end

    context "with trailing guidance after the legacy organization authentication message" do
      let(:error_message) do
        "No authenticated organization found for dependabot. Do you want to authenticate it now?"
      end

      it { is_expected.to eq("dependabot") }
    end

    context "with an unqualified fetch failure" do
      let(:error_message) { "Failed to fetch record for private_repo" }

      it { is_expected.to be_nil }
    end

    context "with a qualified fetch failure" do
      let(:error_message) { "Failed to fetch record for private_repo:dependabot" }

      it { is_expected.to be_nil }
    end

    context "with a source-like credential failure without exact context" do
      let(:error_message) { 'Public key fingerprint mismatch for repo "private_repo"' }

      it { is_expected.to be_nil }
    end

    context "with an unrelated error" do
      it { is_expected.to be_nil }
    end
  end
end
