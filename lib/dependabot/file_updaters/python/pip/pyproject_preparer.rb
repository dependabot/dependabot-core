# frozen_string_literal: true

require "toml-rb"

require "dependabot/file_parsers/python/pip"
require "dependabot/file_updaters/python/pip"

module Dependabot
  module FileUpdaters
    module Python
      class Pip
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

          def freeze_top_level_dependencies_except(dependencies, lockfile)
            return pyproject_content unless lockfile
            pyproject_object = TomlRB.parse(pyproject_content)
            poetry_object = pyproject_object.fetch("tool").fetch("poetry")
            parsed_lockfile = TomlRB.parse(lockfile.content)
            excluded_names = dependencies.map(&:name) + ["python"]

            %w(dependencies dev-dependencies).each do |key|
              next unless poetry_object[key]

              poetry_object.fetch(key).each do |dep_name, _|
                next if excluded_names.include?(normalise(dep_name))
                locked_version =
                  parsed_lockfile.fetch("package").
                  find { |d| d["name"] == normalise(dep_name) }&.
                  fetch("version")
                next unless locked_version

                if poetry_object[dep_name].is_a?(Hash)
                  poetry_object[key][dep_name]["version"] = locked_version
                else
                  poetry_object[key][dep_name] = locked_version
                end
              end
            end

            TomlRB.dump(pyproject_object)
          end

          private

          attr_reader :pyproject_content

          # See https://www.python.org/dev/peps/pep-0503/#normalized-names
          def normalise(name)
            name.downcase.tr("_", "-").tr(".", "-")
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
end
