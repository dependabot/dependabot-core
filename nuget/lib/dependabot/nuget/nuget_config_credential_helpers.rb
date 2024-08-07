# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Nuget
    module NuGetConfigCredentialHelpers
      extend T::Sig

      sig { returns(String) }
      def self.user_nuget_config_path
        home_directory = Dir.home
        File.join(home_directory, ".nuget", "NuGet", "NuGet.Config")
      end

      sig { returns(String) }
      def self.temporary_nuget_config_path
        user_nuget_config_path + "_ORIGINAL"
      end

      sig { params(credentials: T::Array[Dependabot::Credential]).void }
      def self.add_credentials_to_nuget_config(credentials)
        return unless File.exist?(user_nuget_config_path)

        nuget_credentials = credentials.select { |cred| cred["type"] == "nuget_feed" }
        return if nuget_credentials.empty?

        File.rename(user_nuget_config_path, temporary_nuget_config_path)
        File.write(
          user_nuget_config_path,
          <<~NUGET_XML
            <?xml version="1.0" encoding="utf-8"?>
            <configuration>
              <packageSources>
                #{nuget_config_package_source_xml_lines(nuget_credentials).join("\n    ").strip}
              </packageSources>
              <packageSourceCredentials>
                #{nuget_config_package_source_credential_xml_lines(nuget_credentials).join("\n    ").strip}
              </packageSourceCredentials>
            </configuration>
          NUGET_XML
        )
      end

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(T::Array[String]) }
      def self.nuget_config_package_source_xml_lines(credentials)
        credentials.each_with_index.filter_map do |c, i|
          source_key = "nuget_source_#{i + 1}"
          "<add key=\"#{source_key}\" value=\"#{c['url']}\" />"
        end
      end

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(T::Array[String]) }
      def self.nuget_config_package_source_credential_xml_lines(credentials)
        credentials.each_with_index.flat_map do |c, i|
          source_key = "nuget_source_#{i + 1}"

          # Ignore public sources, as they don't require credentials
          next unless c["token"] || c["password"]

          # Extract username and password from the token. If the username is empty, assume it's not significant
          # e.g. token "PAT:12345" --> { username: "PAT", password: "12345" }
          #            ":12345"    --> { username: "unused", password: "12345" }
          #            "12345"     --> { username: "unused", password: "12345" }
          source_token_parts = extract_token_parts_from_credential(c)
          source_username = source_token_parts.count > 1 ? source_token_parts.first : "unused"
          source_password = source_token_parts.last
          [
            "<#{source_key}>",
            "  <add key=\"Username\" value=\"#{source_username}\" />",
            "  <add key=\"ClearTextPassword\" value=\"#{source_password}\" />",
            "</#{source_key}>"
          ]
        end
      end

      sig { params(credential: T::Hash[String, T.untyped]).returns(T::Array[String]) }
      def self.extract_token_parts_from_credential(credential)
        # Private NuGet repository credentials could be any of:
        #  - `token` only (e.g. access token or basic access auth)
        #  - `password` only (e.g. GitHub PAT or Azure DevOps PAT, username is not significant)
        #  - `username` and `password` (e.g. MyGet, Artifactory, https://nuget.telerik.com, etc)
        # The raw token should always take priority over username/password, if both are provided for some reason
        # When only username/password is provided, convert them to a basic access auth token
        token = credential["token"] || "#{credential['username']}:#{credential['password']}"
        # If token is base64 encoded basic access auth, decode it so that we can extract the username/password
        token = Base64.decode64(token) if Base64.decode64(token).ascii_only? && Base64.decode64(token).include?(":")
        token&.split(":", 2)&.reject(&:empty?) || []
      end

      sig { void }
      def self.restore_user_nuget_config
        return unless File.exist?(temporary_nuget_config_path)

        File.delete(user_nuget_config_path)
        File.rename(temporary_nuget_config_path, user_nuget_config_path)
      end

      sig { params(credentials: T::Array[Dependabot::Credential], _block: T.proc.void).void }
      def self.patch_nuget_config_for_action(credentials, &_block)
        add_credentials_to_nuget_config(credentials)
        begin
          yield
        rescue DependabotError
          # forward these
          raise
        rescue StandardError => e
          log_message =
            <<~LOG_MESSAGE
              Block argument of NuGetConfigCredentialHelpers::patch_nuget_config_for_action causes an exception #{e}:
              #{e.message}
            LOG_MESSAGE
          Dependabot.logger.error(log_message)
          puts log_message
        ensure
          restore_user_nuget_config
        end
      end
    end
  end
end
