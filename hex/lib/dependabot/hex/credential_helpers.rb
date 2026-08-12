# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/hex/native_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Hex
    module CredentialHelpers
      extend T::Sig

      CREDENTIAL_TOKEN_ENV = "DEPENDABOT_HEX_CREDENTIAL_TOKEN"

      sig do
        params(
          credentials: T::Array[Dependabot::Credential],
          env: T::Hash[String, String]
        ).void
      end
      def self.configure(credentials:, env:)
        credentials.each do |credential|
          case credential["type"]
          when "hex_organization"
            configure_organization(credential, env)
          when "hex_repository"
            configure_repository(credential, env)
          end
        end
      end

      sig { returns(String) }
      def self.configure_credentials_path
        File.join(NativeHelpers.hex_helpers_dir, "lib/configure_credentials.exs")
      end

      sig do
        params(
          credential: Dependabot::Credential,
          env: T::Hash[String, String]
        ).void
      end
      def self.configure_organization(credential, env)
        organization = required_value(credential, "organization", source: credential["type"])
        token = required_value(credential, "token", source: organization)

        run_mix_command(
          mix_run_command("configure_credentials.exs", "organization", organization),
          fingerprint: "mix run configure_credentials.exs organization #{organization}",
          env: env.merge(CREDENTIAL_TOKEN_ENV => token)
        )
      end
      private_class_method :configure_organization

      sig do
        params(
          credential: Dependabot::Credential,
          env: T::Hash[String, String]
        ).void
      end
      def self.configure_repository(credential, env)
        repo = required_value(credential, "repo", source: credential["type"])
        url = required_value(credential, "url", source: repo)
        auth_key = required_value(credential, "auth_key", source: repo)
        public_key_fingerprint = credential["public_key_fingerprint"] || ""

        run_mix_command(
          mix_run_command("configure_credentials.exs", "repository", repo, url, public_key_fingerprint),
          fingerprint: "mix run configure_credentials.exs repository #{repo}",
          env: env.merge(CREDENTIAL_TOKEN_ENV => auth_key)
        )
      end
      private_class_method :configure_repository

      sig do
        params(
          credential: Dependabot::Credential,
          key: String,
          source: T.nilable(String)
        ).returns(String)
      end
      def self.required_value(credential, key, source: nil)
        value = credential[key]
        return value if value.is_a?(String) && !value.empty?

        raise SharedHelpers::HelperSubprocessFailed.new(
          message: "Missing credentials for \"#{source}\"",
          error_context: {}
        )
      end
      private_class_method :required_value

      sig do
        params(
          command: T::Array[String],
          fingerprint: String,
          env: T::Hash[String, String]
        ).void
      end
      def self.run_mix_command(command, fingerprint:, env:)
        SharedHelpers.run_shell_command(command, env: env, fingerprint: fingerprint)
      end
      private_class_method :run_mix_command

      sig { params(script: String, args: String).returns(T::Array[String]) }
      def self.mix_run_command(script, *args)
        [
          "mix", "run", "--no-deps-check", "--no-start", "--no-compile",
          "--no-elixir-version-check", script, "--", *args
        ]
      end
      private_class_method :mix_run_command
    end
  end
end
