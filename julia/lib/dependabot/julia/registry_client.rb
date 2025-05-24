# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "dependabot/credential"
require "dependabot/julia/version"
require "dependabot/shared_helpers"

module Dependabot
  module Julia
    class RegistryClient
      GENERAL_REGISTRY = T.let("https://github.com/JuliaRegistries/General.git", String)

      extend T::Sig

      sig { params(credentials: T::Array[Dependabot::Credential]).void }
      def initialize(credentials)
        @credentials = credentials
      end

      sig { params(package_name: String).returns(T.nilable(Dependabot::Julia::Version)) }
      def fetch_latest_version(package_name)
        registry_path = clone_registry
        registry_toml = File.join(registry_path, "Registry.toml")
        pkg_path = package_path_in_registry(package_name, File.read(registry_toml))
        versions_file = File.join(registry_path, pkg_path, "Versions.toml")

        return nil unless File.exist?(versions_file)

        versions = TomlRB.parse(File.read(versions_file))
        versions.keys.map { |v| v.delete_prefix('"').delete_suffix('"') }
                .map { |v| Version.new(v) }
                .max
      end

      sig { params(package_name: String).returns(T::Hash[String, T.untyped]) }
      def fetch_package_info(package_name)
        registry_path = clone_registry
        registry_toml = File.join(registry_path, "Registry.toml")
        pkg_path = package_path_in_registry(package_name, File.read(registry_toml))
        pkg_dir = File.join(registry_path, pkg_path)

        return {} unless File.directory?(pkg_dir)

        package_file = File.join(pkg_dir, "Package.toml")
        return {} unless File.exist?(package_file)

        package_data = TomlRB.parse(File.read(package_file))

        versions_file = File.join(pkg_dir, "Versions.toml")
        versions = File.exist?(versions_file) ? TomlRB.parse(File.read(versions_file)) : {}

        {
          "name" => package_name,
          "repo" => package_data["repo"],
          "uuid" => package_data["uuid"],
          "versions" => versions
        }
      end

      private

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(String) }
      def clone_registry
        SharedHelpers.in_a_temporary_directory do |dir|
          SharedHelpers.with_git_configured(credentials: credentials) do
            SharedHelpers.run_shell_command(
              "git clone --depth 1 #{GENERAL_REGISTRY} registry"
            )
          end
          return File.join(dir, "registry")
        end
      end

      sig { params(package_name: String, registry_toml_content: String).returns(String) }
      def package_path_in_registry(package_name, registry_toml_content)
        # Parse the Registry.toml content
        registry_data = TomlRB.parse(registry_toml_content)

        # Look up the package by name in the packages map
        package_entry = nil
        registry_data["packages"].each do |uuid, details|
          if details["name"] == package_name
            package_entry = details
            break
          end
        end

        # Return the path if found, otherwise use the fallback convention
        if package_entry && package_entry["path"]
          package_entry["path"]
        else
          # Fallback to old convention if not found in registry
          "#{package_name[0].upcase}/#{package_name}"
        end
      end
    end
  end
end
