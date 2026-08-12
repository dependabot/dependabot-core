# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/hex/credential_helpers"

RSpec.describe Dependabot::Hex::CredentialHelpers do
  describe ".configure" do
    subject(:configure) { described_class.configure(credentials: credentials, env: env) }

    let(:env) { { "HEX_HOME" => "/tmp/dependabot-hex-home", "MIX_QUIET" => "1" } }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return("")
    end

    context "with organization credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_organization",
              "organization" => "organization",
              "token" => "organization-secret-token"
            }
          )
        ]
      end

      it "uses hex.organization without putting the token in argv or the fingerprint" do
        configure

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including("configure_credentials.exs", "--", "organization", "organization"),
          hash_including(
            env: env.merge("DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "organization-secret-token"),
            fingerprint: "mix run configure_credentials.exs organization organization"
          )
        ) do |command, options|
          expect(command).not_to include("organization-secret-token")
          expect(options.fetch(:fingerprint)).not_to include("organization-secret-token")
        end
      end
    end

    context "with repository credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "private",
              "url" => "https://repo.example.com",
              "auth_key" => "repository-secret-key",
              "public_key_fingerprint" => "SHA256:public-key-fingerprint"
            }
          )
        ]
      end

      it "uses hex.repo without putting the auth key or URL in the fingerprint" do
        configure

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including(
            "configure_credentials.exs",
            "--",
            "repository",
            "private",
            "https://repo.example.com",
            "SHA256:public-key-fingerprint"
          ),
          hash_including(
            env: env.merge("DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "repository-secret-key"),
            fingerprint: "mix run configure_credentials.exs repository private"
          )
        ) do |command, options|
          expect(command).not_to include("repository-secret-key")
          expect(options.fetch(:fingerprint)).not_to include("repository-secret-key", "https://repo.example.com")
        end
      end
    end

    context "with unrelated credentials" do
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

      it "does not run a Hex credential task" do
        configure

        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      end
    end

    context "with incomplete repository credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "private",
              "url" => "https://repo.example.com"
            }
          )
        ]
      end

      it "raises a helper error naming the repository" do
        expect { configure }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, 'Missing credentials for "private"')
      end
    end

    context "with incomplete organization credentials" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_organization",
              "organization" => "organization"
            }
          )
        ]
      end

      it "raises a helper error naming the organization" do
        expect { configure }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, 'Missing credentials for "organization"')
      end
    end

    context "with a missing credential name" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "url" => "https://repo.example.com",
              "auth_key" => "repository-secret-key"
            }
          )
        ]
      end

      it "raises a helper error without exposing another credential value" do
        expect { configure }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, 'Missing credentials for "hex_repository"')
      end
    end
  end

  describe ".configure_credentials_path" do
    it "returns the packaged public task helper" do
      expect(described_class.configure_credentials_path).to eq(
        File.join(Dependabot::Hex::NativeHelpers.hex_helpers_dir, "lib/configure_credentials.exs")
      )
    end
  end
end
