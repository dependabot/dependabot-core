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
      PUBLIC_KEY_ENV = "DEPENDABOT_HEX_PUBLIC_KEY"
      LEGACY_AUTHENTICATION_SOURCE =
        /^No authenticated organization found for (?<source>[A-Za-z0-9_.-]+)\.$/

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

      sig { params(error: SharedHelpers::HelperSubprocessFailed).returns(T.nilable(String)) }
      def self.authentication_source(error)
        source = error.error_context[:source]
        return source if source.is_a?(String) && !source.empty?

        error.message.match(LEGACY_AUTHENTICATION_SOURCE)&.[](:source)
      end

      # Job credentials use the dependabot.yml spelling of keys (e.g. `public-key-fingerprint`).
      sig { params(credential: Dependabot::Credential).returns(Dependabot::Credential) }
      def self.underscore_keys(credential)
        Dependabot::Credential.new(credential.to_h.transform_keys { |key| key.tr("-", "_") })
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
          mix_run_command("lib/configure_credentials.exs", "organization", organization),
          source: organization,
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
        credential = underscore_keys(credential)
        repo = required_value(credential, "repo", source: credential["type"])
        url = required_value(credential, "url", source: repo)
        auth_key = credential["auth_key"] || ""
        public_key_fingerprint = credential["public_key_fingerprint"] || ""
        public_key = credential["public_key"] || ""

        run_mix_command(
          mix_run_command("lib/configure_credentials.exs", "repository", repo, url, public_key_fingerprint),
          source: repo,
          fingerprint: "mix run configure_credentials.exs repository #{repo}",
          env: env.merge(CREDENTIAL_TOKEN_ENV => auth_key, PUBLIC_KEY_ENV => public_key)
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
          error_context: { source: source }
        )
      end
      private_class_method :required_value

      sig do
        params(
          command: T::Array[String],
          source: String,
          fingerprint: String,
          env: T::Hash[String, String]
        ).void
      end
      def self.run_mix_command(command, source:, fingerprint:, env:)
        SharedHelpers.run_shell_command(
          command,
          cwd: NativeHelpers.hex_helpers_dir,
          env: env,
          fingerprint: fingerprint
        )
      rescue SharedHelpers::HelperSubprocessFailed => e
        raise SharedHelpers::HelperSubprocessFailed.new(
          message: e.message,
          error_context: e.error_context.merge(source: source),
          error_class: e.error_class,
          trace: e.trace
        )
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
