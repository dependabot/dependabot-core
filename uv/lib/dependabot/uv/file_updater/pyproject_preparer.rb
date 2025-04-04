# typed: true
# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/uv/file_parser"
require "dependabot/uv/file_updater"
require "dependabot/uv/authed_url_builder"
require "dependabot/uv/name_normaliser"
require "securerandom"

module Dependabot
  module Uv
    class FileUpdater
      class PyprojectPreparer
        def initialize(pyproject_content:, lockfile: nil)
          @pyproject_content = pyproject_content
          @lockfile = lockfile
        end

        def freeze_top_level_dependencies_except(dependencies_to_update)
          return @pyproject_content unless lockfile

          pyproject_object = TomlRB.parse(@pyproject_content)
          deps_to_update_names = dependencies_to_update.map(&:name)

          if pyproject_object["project"]&.key?("dependencies")
            locked_deps = parsed_lockfile_dependencies || {}

            pyproject_object["project"]["dependencies"] =
              pyproject_object["project"]["dependencies"].map do |dep_string|
                freeze_dependency(dep_string, deps_to_update_names, locked_deps)
              end
          end

          TomlRB.dump(pyproject_object)
        end

        def update_python_requirement(python_version)
          return @pyproject_content unless python_version

          pyproject_object = TomlRB.parse(@pyproject_content)

          if pyproject_object["project"]&.key?("requires-python")
            pyproject_object["project"]["requires-python"] = ">=#{python_version}"
          end

          TomlRB.dump(pyproject_object)
        end

        def add_auth_env_vars(credentials)
          return unless credentials

          credentials.each do |credential|
            next unless credential["type"] == "python_index"

            token = credential["token"]
            index_url = credential["index-url"]

            next unless token && index_url

            # Set environment variables for uv auth
            ENV["UV_INDEX_URL_TOKEN_#{sanitize_env_name(index_url)}"] = token

            # Also set pip-style credentials for compatibility
            ENV["PIP_INDEX_URL"] ||= "https://#{token}@#{index_url.gsub(%r{^https?://}, '')}"
          end
        end

        def sanitize
          # No special sanitization needed for UV files at this point
          @pyproject_content
        end

        private

        attr_reader :lockfile

        def parsed_lockfile
          @parsed_lockfile ||= lockfile ? parse_lockfile(lockfile.content) : {}
        end

        def parse_lockfile(content)
          TomlRB.parse(content)
        rescue TomlRB::ParseError
          {} # Return empty hash if parsing fails
        end

        def parsed_lockfile_dependencies
          return {} unless lockfile

          deps = {}
          parsed = parsed_lockfile

          # Handle UV lock format (version 1)
          if parsed["version"] == 1 && parsed["package"].is_a?(Array)
            parsed["package"].each do |pkg|
              next unless pkg["name"] && pkg["version"]

              deps[pkg["name"]] = { "version" => pkg["version"] }
            end
          # Handle traditional Poetry-style lock format
          elsif parsed["dependencies"]
            deps = parsed["dependencies"]
          end

          deps
        end

        def locked_version_for_dep(locked_deps, dep_name)
          locked_deps.each do |name, details|
            next unless Uv::FileParser.normalize_dependency_name(name) == dep_name
            return details["version"] if details.is_a?(Hash) && details["version"]
          end
          nil
        end

        def sanitize_env_name(url)
          url.gsub(%r{^https?://}, "").gsub(/[^a-zA-Z0-9]/, "_").upcase
        end

        def freeze_dependency(dep_string, deps_to_update_names, locked_deps)
          package_name = dep_string.split(/[=>~<\[]/).first.strip
          normalized_name = Uv::FileParser.normalize_dependency_name(package_name)

          return dep_string if deps_to_update_names.include?(normalized_name)

          version = locked_version_for_dep(locked_deps, normalized_name)
          return dep_string unless version

          if dep_string.include?("=") || dep_string.include?(">") ||
             dep_string.include?("<") || dep_string.include?("~")
            # Replace version constraint with exact version
            dep_string.sub(/[=>~<\[].*$/, "==#{version}")
          else
            # Simple dependency, just append version
            "#{dep_string}==#{version}"
          end
        end
      end
    end
  end
end
