# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/python/file_parser"
require "dependabot/python/file_updater"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"
require "securerandom"

module Dependabot
  module Python
    class FileUpdater
      class PyprojectPreparer
        def initialize(pyproject_content:, lockfile: nil)
          @pyproject_content = pyproject_content
          @lockfile = lockfile
        end

        # For hosted Dependabot token will be nil since the credentials aren't present.
        # This is for those running Dependabot themselves and for dry-run.
        def add_auth_env_vars(credentials)
          TomlRB.parse(@pyproject_content).dig("tool", "poetry", "source")&.each do |source|
            cred = credentials&.find { |c| c["index-url"] == source["url"] }
            next unless cred

            token = cred.fetch("token", nil)
            next unless token && token.count(":") == 1

            arr = token.split(":")
            # https://python-poetry.org/docs/configuration/#using-environment-variables
            name = source["name"]&.upcase&.gsub(/\W/, "_")
            ENV["POETRY_HTTP_BASIC_#{name}_USERNAME"] = arr[0]
            ENV["POETRY_HTTP_BASIC_#{name}_PASSWORD"] = arr[1]
          end
        end

        def update_python_requirement(requirement)
          pyproject_object = TomlRB.parse(@pyproject_content)
          if (python_specification = pyproject_object.dig("tool", "poetry", "dependencies", "python"))
            python_req = Python::Requirement.new(python_specification)
            unless python_req.satisfied_by?(requirement)
              pyproject_object["tool"]["poetry"]["dependencies"]["python"] = "~#{requirement}"
            end
          end
          TomlRB.dump(pyproject_object)
        end

        def sanitize
          # {{ name }} syntax not allowed
          pyproject_content.
            gsub(/\{\{.*?\}\}/, "something").
            gsub('#{', "{")
        end

        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/AbcSize
        def freeze_top_level_dependencies_except(dependencies)
          return pyproject_content unless lockfile

          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object["tool"]["poetry"]
          excluded_names = dependencies.map(&:name) + ["python"]

          Dependabot::Python::FileParser::PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |key|
            next unless poetry_object[key]

            source_types = %w(directory file url)
            poetry_object.fetch(key).each do |dep_name, _|
              next if excluded_names.include?(normalise(dep_name))

              locked_details = locked_details(dep_name)

              next unless (locked_version = locked_details&.fetch("version"))

              next if source_types.include?(locked_details&.dig("source", "type"))

              if locked_details&.dig("source", "type") == "git"
                poetry_object[key][dep_name] = {
                  "git" => locked_details&.dig("source", "url"),
                  "rev" => locked_details&.dig("source", "reference")
                }
              elsif poetry_object[key][dep_name].is_a?(Hash)
                poetry_object[key][dep_name]["version"] = locked_version
              elsif poetry_object[key][dep_name].is_a?(Array)
                # if it has multiple-constraints, locking to a single version is
                # going to result in a bad lockfile, ignore
                next
              else
                poetry_object[key][dep_name] = locked_version
              end
            end
          end

          TomlRB.dump(pyproject_object)
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity

        private

        attr_reader :pyproject_content, :lockfile

        def locked_details(dep_name)
          parsed_lockfile.fetch("package").
            find { |d| d["name"] == normalise(dep_name) }
        end

        def normalise(name)
          NameNormaliser.normalise(name)
        end

        def parsed_lockfile
          @parsed_lockfile ||= TomlRB.parse(lockfile.content)
        end
      end
    end
  end
end
