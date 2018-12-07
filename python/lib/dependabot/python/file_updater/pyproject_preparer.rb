# frozen_string_literal: true

require "toml-rb"

require "dependabot/python/file_parser"
require "dependabot/python/file_updater"

module Dependabot
  module Python
    class FileUpdater
      class PyprojectPreparer
        def initialize(pyproject_content:)
          @pyproject_content = pyproject_content
        end

        def replace_sources(credentials)
          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object.fetch("tool").fetch("poetry")

          poetry_object["source"] = pyproject_sources +
                                    config_variable_sources(credentials)

          TomlRB.dump(pyproject_object)
        end

        def sanitize
          # {{ name }} syntax not allowed
          pyproject_content.gsub(/\{\{.*?\}\}/, "something")
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def freeze_top_level_dependencies_except(dependencies, lockfile)
          return pyproject_content unless lockfile

          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object["tool"]["poetry"]
          excluded_names = dependencies.map(&:name) + ["python"]

          %w(dependencies dev-dependencies).each do |key|
            next unless poetry_object[key]

            poetry_object.fetch(key).each do |dep_name, _|
              next if excluded_names.include?(normalise(dep_name))

              locked_details = locked_details(dep_name, lockfile)

              next unless (locked_version = locked_details&.fetch("version"))

              if locked_details&.dig("source", "type") == "git"
                poetry_object[key][dep_name] = {
                  "git" => locked_details&.dig("source", "url"),
                  "rev" => locked_details&.dig("source", "reference")
                }
              elsif poetry_object[dep_name].is_a?(Hash)
                poetry_object[key][dep_name]["version"] = locked_version
              else
                poetry_object[key][dep_name] = locked_version
              end
            end
          end

          TomlRB.dump(pyproject_object)
        end
        # rubocop:enable Metrics/PerceivedComplexity

        private

        attr_reader :pyproject_content

        def locked_details(dep_name, lockfile)
          parsed_lockfile = TomlRB.parse(lockfile.content)

          parsed_lockfile.fetch("package").
            find { |d| d["name"] == normalise(dep_name) }
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalise(name)
          name.downcase.gsub(/[-_.]+/, "-")
        end

        def pyproject_sources
          return @pyproject_sources if @pyproject_sources

          pyproject_sources ||=
            TomlRB.parse(pyproject_content).
            dig("tool", "poetry", "source")

          @pyproject_sources ||=
            (pyproject_sources || []).
            map { |h| h.dup.merge("url" => h["url"].gsub(%r{/*$}, "") + "/") }
        end

        def config_variable_sources(credentials)
          @config_variable_sources ||=
            credentials.
            select { |cred| cred["type"] == "python_index" }.
            map { |cred| { "url" => cred["index-url"] } }
        end
      end
    end
  end
end
