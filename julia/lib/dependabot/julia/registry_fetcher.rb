# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/julia/version"

module Dependabot
  module Julia
    class RegistryFetcher
      GENERAL_REGISTRY = "https://github.com/JuliaRegistries/General.git"

      extend T::Sig

      sig do
        params(package_name: String, credentials: T::Array[Dependabot::Credential])
          .returns(T.nilable(Dependabot::Julia::Version))
      end
      def self.fetch_latest_version(package_name, credentials)
        registry_path = clone_registry(credentials)
        pkg_path = File.join(registry_path, T.must(package_name[0]).upcase, package_name)
        versions_file = File.join(pkg_path, "Versions.toml")

        return nil unless File.exist?(versions_file)

        versions = TomlRB.parse(File.read(versions_file))
        versions.keys.map { |v| v.delete_prefix('"').delete_suffix('"') }
                .sort_by { |v| Version.new(v) }
                .max_by { |v| Version.new(v) }
      end

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(String) }
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

      sig { params(registry_path: String, package_name: String).returns(T::Hash[String, T.untyped]) }
      def fetch_package_details(registry_path, package_name)
        pkg_path = File.join(registry_path, T.must(package_name[0]).upcase, package_name)

        # Check if package exists in registry
        raise "Package not found: #{package_name}" unless File.directory?(pkg_path)

        # Read package info and versions
        versions = Dir.glob(File.join(pkg_path, "Versions", "*")).map do |version_dir|
          version = File.basename(version_dir)
          {
            "version" => version,
            "sha" => File.read(File.join(version_dir, "sha")).strip
          }
        end

        {
          "name" => package_name,
          "path" => pkg_path,
          "versions" => versions
        }
      end
    end
  end
end
