require "excon"
require "toml-rb"

module Dependabot
  module Julia
    class RegistryClient
      GENERAL_REGISTRY = "https://github.com/JuliaRegistries/General"

      def initialize(credentials)
        @credentials = credentials
      end

      def fetch_latest_version(package_name)
        registry_data = fetch_registry_data(package_name)
        versions = registry_data.fetch("versions", {}).keys
        versions.map { |v| Version.new(v) }.max
      end

      private

      attr_reader :credentials

      def fetch_registry_data(package_name)
        registry_path = File.join(
          GENERAL_REGISTRY,
          package_name[0].upcase,
          package_name,
          "Package.toml"
        )
        response = Excon.get(registry_path, headers: auth_headers)
        TomlRB.parse(response.body)
      end

      def auth_headers
        return {} unless token
        { "Authorization" => "token #{token}" }
      end

      def token
        credentials
          .find { |cred| cred["type"] == "git_source" }
          &.fetch("token", nil)
      end
    end
  end
end
