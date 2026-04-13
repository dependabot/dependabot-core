# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/credential"
require "dependabot/errors"
require "dependabot/dependency_file"
require "dependabot/composer/package_manager"

module Dependabot
  module Composer
    # Provides shared helper methods for handling auth.json credentials in
    # both VersionResolver and LockfileUpdater.
    module CredentialHelpers
      extend T::Sig

      # Extracts http-basic credentials from an auth.json dependency file.
      sig do
        params(auth_json_file: T.nilable(Dependabot::DependencyFile))
          .returns(T::Array[Dependabot::Credential])
      end
      def self.auth_json_credentials(auth_json_file)
        return [] unless auth_json_file

        parsed = parse_auth_json(auth_json_file)
        parsed.fetch("http-basic", {}).map do |reg, details|
          Dependabot::Credential.new(
            {
              "registry" => reg,
              "username" => details["username"],
              "password" => details["password"]
            }
          )
        end
      end

      # Returns merged auth.json content combining the repo's auth.json with
      # http-basic credentials from dependabot.yml composer_repository entries.
      sig do
        params(
          auth_json_file: T.nilable(Dependabot::DependencyFile),
          credentials: T::Array[Dependabot::Credential]
        ).returns(T::Hash[String, T.untyped])
      end
      def self.merged_auth_json_content(auth_json_file, credentials)
        base = auth_json_file ? parse_auth_json(auth_json_file) : {}

        http_basic = credentials
                     .select { |cred| cred["type"] == PackageManager::REPOSITORY_KEY }
                     .select { |cred| cred["password"] }
                     .to_h do |cred|
                       [cred["registry"], {
                         "username" => cred["username"],
                         "password" => cred["password"]
                       }]
                     end

        if http_basic.any?
          base["http-basic"] ||= {}
          base["http-basic"].merge!(http_basic)
        end

        base
      end

      # Parses the content of an auth.json dependency file, raising a
      # DependencyFileNotParseable error if the content is not valid JSON.
      sig do
        params(auth_json_file: Dependabot::DependencyFile)
          .returns(T::Hash[String, T.untyped])
      end
      def self.parse_auth_json(auth_json_file)
        JSON.parse(T.must(auth_json_file.content))
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, auth_json_file.path
      end

      private_class_method :parse_auth_json
    end
  end
end
