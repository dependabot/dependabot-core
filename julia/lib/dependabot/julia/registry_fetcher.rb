# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module Julia
    class RegistryFetcher
      GENERAL_REGISTRY = "https://github.com/JuliaRegistries/General"

      def self.fetch_latest_version(package_name, credentials)
        registry_path = clone_registry(credentials)
        pkg_path = File.join(registry_path, package_name[0].upcase, package_name)
        versions_file = File.join(pkg_path, "Versions.toml")

        return nil unless File.exist?(versions_file)

        versions = TomlRB.parse(File.read(versions_file))
        versions.keys.map { |v| v.delete_prefix('"').delete_suffix('"') }
                .sort_by { |v| Version.new(v) }
                .last
      end

      private

      def self.clone_registry(credentials)
        SharedHelpers.in_a_temporary_directory do |dir|
          SharedHelpers.with_git_configured(credentials: credentials) do
            SharedHelpers.run_shell_command(
              "git clone --depth 1 #{GENERAL_REGISTRY} registry"
            )
          end
          return File.join(dir, "registry")
        end
      end
    end
  end
end
