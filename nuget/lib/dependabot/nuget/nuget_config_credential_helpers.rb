# typed: true
# frozen_string_literal: true

module Dependabot
  module Nuget
    module NuGetConfigCredentialHelpers
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
          source_name = "credentialed_source_#{i + 1}"
          package_sources << "    <add key=\"#{source_name}\" value=\"#{c.fetch('url')}\" />"
          package_source_credentials << "    <#{source_name}>"
          package_source_credentials << "      <add key=\"Username\" value=\"user\" />"
          package_source_credentials << "      <add key=\"ClearTextPassword\" value=\"#{c.fetch('token')}\" />"
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

      def self.restore_user_nuget_config
        return unless File.exist?(temporary_nuget_config_path)

        File.delete(user_nuget_config_path)
        File.rename(temporary_nuget_config_path, user_nuget_config_path)
      end

      # rubocop:disable Lint/SuppressedException
      def self.patch_nuget_config_for_action(credentials, &_block)
        add_credentials_to_nuget_config(credentials)
        begin
          yield
        rescue StandardError
        ensure
          restore_user_nuget_config
        end
      end
      # rubocop:enable Lint/SuppressedException
    end
  end
end
