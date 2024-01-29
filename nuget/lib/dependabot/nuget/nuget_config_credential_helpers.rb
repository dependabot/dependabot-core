# typed: true
# frozen_string_literal: true

module Dependabot
  module Nuget
    module NuGetConfigCredentialHelpers
      extend T::Sig

      def self.user_nuget_config_path
        home_directory = Dir.home
        File.join(home_directory, ".nuget", "NuGet", "NuGet.Config")
      end

      def self.temporary_nuget_config_path
        user_nuget_config_path + "_ORIGINAL"
      end

      def self.add_credentials_to_nuget_config(credentials)
        return unless File.exist?(user_nuget_config_path)

        nuget_credentials = credentials.select { |cred| cred["type"] == "nuget_feed" }
        return if nuget_credentials.empty?

        File.rename(user_nuget_config_path, temporary_nuget_config_path)

        package_sources = []
        package_source_credentials = []
        nuget_credentials.each_with_index do |c, i|
          source_name = "nuget_source_#{i + 1}"
          package_sources << "    <add key=\"#{source_name}\" value=\"#{c['url']}\" />"
          next unless c["token"]

          package_source_credentials << "    <#{source_name}>"
          package_source_credentials << "      <add key=\"Username\" value=\"user\" />"
          package_source_credentials << "      <add key=\"ClearTextPassword\" value=\"#{c['token']}\" />"
          package_source_credentials << "    </#{source_name}>"
        end

        nuget_config = <<~NUGET_XML
          <?xml version="1.0" encoding="utf-8"?>
          <configuration>
            <packageSources>
          #{package_sources.join("\n")}
            </packageSources>
            <packageSourceCredentials>
          #{package_source_credentials.join("\n")}
            </packageSourceCredentials>
          </configuration>
        NUGET_XML
        File.write(user_nuget_config_path, nuget_config)
      end

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(T::Hash[String, String]) }
      def self.get_credentials_to_credential_helper_env(credentials)
        env = {}

        nuget_credentials = credentials.select { |cred| cred["type"] == "nuget_feed" }

        if nuget_credentials.any?
          endpoint_credentials = []

          nuget_credentials.each do |c|
            next unless c["token"]

            exploded_token = T.must(c["token"]).split(":", 2)

            next unless exploded_token.length == 2

            username = exploded_token[0]
            password = exploded_token[1]

            endpoint_credentials << <<~NUGET_ENDPOINT_CREDENTIAL
              {"endpoint":"#{c['url']}", "username":"#{username}", "password":"#{password}"}
            NUGET_ENDPOINT_CREDENTIAL
          end

          env["VSS_NUGET_EXTERNAL_FEED_ENDPOINTS"] = "{\"endpointCredentials\": [#{endpoint_credentials.join(',')}]}"
        end

        env
      end

      def self.restore_user_nuget_config
        return unless File.exist?(temporary_nuget_config_path)

        File.delete(user_nuget_config_path)
        File.rename(temporary_nuget_config_path, user_nuget_config_path)
      end

      def self.patch_nuget_config_for_action(credentials, &_block)
        add_credentials_to_nuget_config(credentials)
        begin
          yield
        rescue StandardError => e
          Dependabot.logger.error(
            <<~LOG_MESSAGE
              Block argument of NuGetConfigCredentialHelpers::patch_nuget_config_for_action causes an exception #{e}:
              #{e.message}
            LOG_MESSAGE
          )
        ensure
          restore_user_nuget_config
        end
      end
    end
  end
end
