# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/hex/native_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Hex
    module CredentialHelpers
      extend T::Sig

      CREDENTIAL_TOKEN_ENV = "DEPENDABOT_HEX_CREDENTIAL_TOKEN"
      PUBLIC_KEY_ENV = "DEPENDABOT_HEX_PUBLIC_KEY"
      REPOSITORY_URL_ENV = "DEPENDABOT_HEX_REPOSITORY_URL_TOKEN"
      ORGANIZATION_AUTHENTICATION_FAILURE =
        "Failed to authenticate against organization repository with given key"
      PUBLIC_KEY_AUTHENTICATION_FAILURES = [
        'Downloading public key failed with code "401"',
        'Downloading public key failed with code "403"'
      ].freeze
      AUTHENTICATION_SOURCE = %r{[A-Za-z0-9_:.\-/]+}
      UNAUTHENTICATED_ORGANIZATION = /
        (?:\A|\n)
        (?:\*\*[ ]\(Mix\)[ ])?
        No[ ]authenticated[ ]organization[ ]found[ ]for[ ]
        (?<source>#{AUTHENTICATION_SOURCE})\.
        (?:[ ]Do[ ]you[ ]want[ ]to[ ]authenticate[ ]it[ ]now\?(?:[ ]\[Yn\])?)?
        [ ]*
        (?=\n|\z)
      /x
      MISSING_CREDENTIALS = /\AMissing credentials for "(?<source>#{AUTHENTICATION_SOURCE})"\z/
      PUBLIC_KEY_DOWNLOAD_AUTHENTICATION_FAILURE = /
        (?:\A|\n)
        Downloading[ ]public[ ]key[ ]for[ ]repo[ ]"(?<source>#{AUTHENTICATION_SOURCE})"
        [ ]failed[ ]with[ ]code:[ ]401
        [ ]*
        (?=\n|\z)
      /x

      sig do
        params(
          credentials: T::Array[Dependabot::Credential],
          env: T::Hash[String, String]
        ).void
      end
      def self.configure(credentials:, env:)
        organizations, others = credentials.partition { |credential| credential["type"] == "hex_organization" }
        (organizations + others).each do |credential|
          case credential["type"]
          when "hex_organization"
            configure_organization(credential, env)
          when "hex_repository"
            configure_repository(credential, env)
          end
        end
      rescue SharedHelpers::HelperSubprocessFailed => e
        sanitized_error = sanitize_error(error: e, credentials: credentials)
        raise if sanitized_error.equal?(e)

        raise sanitized_error, cause: nil
      end

      sig do
        params(
          error: SharedHelpers::HelperSubprocessFailed,
          credentials: T::Array[Dependabot::Credential]
        ).returns(SharedHelpers::HelperSubprocessFailed)
      end
      def self.sanitize_error(error:, credentials:)
        redactions = credential_redactions(credentials)
        pattern = Regexp.union(redactions.keys.sort_by { |value| -value.length })
        message = error.message.gsub(pattern) { |match| redactions.fetch(match) }
        error_context = redact_value(error.error_context, redactions, pattern)
        trace = redact_value(error.trace, redactions, pattern)
        return error if message == error.message && error_context == error.error_context && trace == error.trace

        SharedHelpers::HelperSubprocessFailed.new(
          message: message,
          error_context: T.cast(error_context, SharedHelpers::ErrorContext),
          error_class: error.error_class,
          trace: T.cast(trace, T.nilable(T::Array[String]))
        )
      end

      sig { params(message: String).returns(T.nilable(String)) }
      def self.authentication_source(message)
        match =
          message.match(UNAUTHENTICATED_ORGANIZATION) ||
          message.match(MISSING_CREDENTIALS) ||
          message.match(PUBLIC_KEY_DOWNLOAD_AUTHENTICATION_FAILURE)
        match&.[](:source)
      end

      sig do
        params(
          original_error: StandardError,
          error: StandardError
        ).returns(T.noreturn)
      end
      def self.raise_translated_error(original_error:, error:)
        raise if error.equal?(original_error)

        raise error, cause: nil
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
        token = credential["token"]
        return unless token.is_a?(String) && !token.empty?

        organization = required_value(credential, "organization", source: credential["type"])
        begin
          run_mix_command(
            mix_run_command("lib/configure_credentials.exs", "organization", organization),
            fingerprint: "mix run configure_credentials.exs organization <organization>",
            env: env.merge(CREDENTIAL_TOKEN_ENV => token)
          )
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise unless e.message.include?(ORGANIZATION_AUTHENTICATION_FAILURE)

          raise Dependabot::PrivateSourceAuthenticationFailure.new(organization), cause: nil
        end
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
        if public_key_fingerprint.empty? && public_key.empty?
          raise Dependabot::DependencyFileNotResolvable,
                "Hex repository \"#{repo}\" must provide either `public-key` or " \
                "`public-key-fingerprint` in dependabot.yml"
        end

        run_mix_command(
          mix_run_command("lib/configure_credentials.exs", "repository", repo, public_key_fingerprint),
          fingerprint: "mix run configure_credentials.exs repository <repository>",
          env: env.merge(
            CREDENTIAL_TOKEN_ENV => auth_key,
            PUBLIC_KEY_ENV => public_key,
            REPOSITORY_URL_ENV => url
          )
        )
      rescue SharedHelpers::HelperSubprocessFailed => e
        raise unless e.message.lines.any? { |line| PUBLIC_KEY_AUTHENTICATION_FAILURES.include?(line.strip) }

        raise Dependabot::PrivateSourceAuthenticationFailure.new(repo), cause: nil
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
          fingerprint: String,
          env: T::Hash[String, String]
        ).void
      end
      def self.run_mix_command(command, fingerprint:, env:)
        build_path = File.join(env.fetch("HEX_HOME"), "build")
        SharedHelpers.run_shell_command(
          command,
          cwd: NativeHelpers.hex_helpers_dir,
          env: env.merge("MIX_BUILD_PATH" => build_path),
          fingerprint: fingerprint
        )
      end
      private_class_method :run_mix_command

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(T::Hash[String, String]) }
      def self.credential_redactions(credentials)
        credentials.each_with_object({}) do |credential, redactions|
          case credential["type"]
          when "hex_organization"
            add_credential_redaction(redactions, credential["token"])
          when "hex_repository"
            add_credential_redaction(redactions, credential["auth_key"] || credential["auth-key"])
            url = credential["url"]
            redactions.merge!(repository_url_query_redactions(url)) if url.is_a?(String) && !url.empty?
          when "git_source"
            add_credential_redaction(redactions, credential["password"])
          end
        end
      end
      private_class_method :credential_redactions

      sig { params(redactions: T::Hash[String, String], value: T.untyped).void }
      def self.add_credential_redaction(redactions, value)
        redactions[value] = "***" if value.is_a?(String) && !value.empty?
      end
      private_class_method :add_credential_redaction

      sig { params(url: String).returns(T::Hash[String, String]) }
      def self.repository_url_query_redactions(url)
        query = url.split("?", 2)[1]&.split("#", 2)&.first
        return {} unless query

        query.split("&").each_with_object({}) do |pair, redactions|
          name, value = pair.split("=", 2)
          next if value.nil? || value.empty?

          redactions[pair] = "#{name}=***"
        end
      end
      private_class_method :repository_url_query_redactions

      sig do
        params(
          value: T.untyped,
          redactions: T::Hash[String, String],
          pattern: Regexp
        ).returns(T.untyped)
      end
      def self.redact_value(value, redactions, pattern)
        case value
        when String
          value.gsub(pattern) { |match| redactions.fetch(match) }
        when Array
          value.map { |item| redact_value(item, redactions, pattern) }
        when Hash
          value.transform_values { |item| redact_value(item, redactions, pattern) }
        else
          value
        end
      end
      private_class_method :redact_value

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
