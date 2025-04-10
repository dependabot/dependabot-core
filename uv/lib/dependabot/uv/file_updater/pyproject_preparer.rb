# typed: true
# frozen_string_literal: true

require "toml-rb"
require "citrus"

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
          @lines = pyproject_content.split("\n")
        end

        def freeze_top_level_dependencies_except(dependencies_to_update)
          return @pyproject_content unless lockfile

          deps_to_update_names = dependencies_to_update.map(&:name).map { |n| Uv::FileParser.normalize_dependency_name(n) }
          locked_deps = parsed_lockfile_dependencies || {}
          in_dependencies = false
          in_dependencies_array = false

          updated_lines = @lines.map do |line|
            if line.match?(/^\[project\]/)
              in_dependencies = true
              in_dependencies_array = false
              line
            elsif line.match?(/^dependencies\s*=\s*\[/)
              in_dependencies_array = true
              line
            elsif in_dependencies && in_dependencies_array && line.strip.start_with?('"')
              # Extract the full dependency string without quotes and trailing comma
              dep_string = line.strip.gsub(/^"|"(?:,\s*)?$/, '')
              parsed = parse_dependency(dep_string)

              if parsed[:name]
                normalized_name = Uv::FileParser.normalize_dependency_name(parsed[:name])

                if deps_to_update_names.include?(normalized_name)
                  line
                else
                  version = locked_version_for_dep(locked_deps, normalized_name)
                  if version
                    prefix = " " * line[/^\s*/].length
                    suffix = line.end_with?(",") ? "," : ""
                    dep_str = parsed[:extras] ? "#{parsed[:name]}[#{parsed[:extras]}]" : parsed[:name]
                    %Q(#{prefix}"#{dep_str}==#{version}"#{suffix})
                  else
                    line
                  end
                end
              else
                line
              end
            else
              line
            end
          end

          @pyproject_content = updated_lines.join("\n")
        end

        def update_python_requirement(python_version)
          return @pyproject_content unless python_version

          in_project_table = false
          updated_lines = @lines.map.with_index do |line, _i|
            if line.match?(/^\[project\]/)
              in_project_table = true
              line
            elsif in_project_table && line.match?(/^requires-python\s*=/)
              "requires-python = \">=#{python_version}\""
            else
              line
            end
          end

          @pyproject_content = updated_lines.join("\n")
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
          dep_match = dep_string.match(/^([^\[\]=<>!]+)(?:\[([^\]]+)\])?/)
          return dep_string unless dep_match

          dep_name = dep_match[1].strip
          dep_extra = dep_match[2]

          normalized_name = Uv::FileParser.normalize_dependency_name(dep_name)

          return dep_string if deps_to_update_names.include?(normalized_name)

          version = locked_version_for_dep(locked_deps, normalized_name)
          return dep_string unless version

          dep_extra ? "#{dep_name}[#{dep_extra}]==#{version}" : "#{dep_name}==#{version}"
        end

        def parse_dependency(dep_string)
          # Split by common version operators
          parts = dep_string.split(/(?=[<>=~!])/)
          name_part = parts.first.strip
          version_part = parts[1..]&.join&.strip

          # Handle extras in name
          if name_part.include?("[")
            name, extras = name_part.split("[", 2)
            extras = extras.chomp("]")
          else
            name = name_part
          end

          {
            name: name.strip,
            extras: extras,
            version_spec: version_part
          }
        end
      end
    end
  end
end
