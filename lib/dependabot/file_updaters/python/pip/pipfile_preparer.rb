# frozen_string_literal: true

require "toml-rb"

require "dependabot/file_parsers/python/pip"
require "dependabot/file_updaters/python/pip"

module Dependabot
  module FileUpdaters
    module Python
      class Pip
        class PipfilePreparer
          def initialize(pipfile_content:)
            @pipfile_content = pipfile_content
          end

          def replace_sources(credentials)
            pipfile_object = TomlRB.parse(pipfile_content)

            pipfile_object["source"] =
              pipfile_sources.reject { |h| h["url"].include?("${") } +
              config_variable_sources(credentials)

            TomlRB.dump(pipfile_object)
          end

          def freeze_top_level_dependencies_except(dependencies, lockfile)
            return pipfile_content unless lockfile

            pipfile_object = TomlRB.parse(pipfile_content)
            excluded_names = dependencies.map(&:name)

            FileParsers::Python::Pip::DEPENDENCY_GROUP_KEYS.each do |keys|
              next unless pipfile_object[keys[:pipfile]]

              pipfile_object.fetch(keys[:pipfile]).each do |dep_name, _|
                next if excluded_names.include?(normalise(dep_name))

                freeze_dependency(dep_name, pipfile_object, lockfile, keys)
              end
            end

            TomlRB.dump(pipfile_object)
          end

          # rubocop:disable Metrics/PerceivedComplexity
          def freeze_dependency(dep_name, pipfile_object, lockfile, keys)
            locked_version = version_from_lockfile(
              lockfile,
              keys[:lockfile],
              normalise(dep_name)
            )
            locked_ref = ref_from_lockfile(
              lockfile,
              keys[:lockfile],
              normalise(dep_name)
            )

            pipfile_req = pipfile_object[keys[:pipfile]][dep_name]
            if pipfile_req.is_a?(Hash) && locked_version
              pipfile_req["version"] = "==#{locked_version}"
            elsif pipfile_req.is_a?(Hash) && locked_ref && !pipfile_req["ref"]
              pipfile_req["ref"] = locked_ref
            elsif locked_version
              pipfile_object[keys[:pipfile]][dep_name] = "==#{locked_version}"
            end
          end
          # rubocop:enable Metrics/PerceivedComplexity

          def update_python_requirement(requirement)
            pipfile_object = TomlRB.parse(pipfile_content)

            pipfile_object["requires"] ||= {}
            pipfile_object["requires"].delete("python_full_version")
            pipfile_object["requires"].delete("python_version")
            pipfile_object["requires"]["python_full_version"] = requirement

            TomlRB.dump(pipfile_object)
          end

          private

          attr_reader :pipfile_content

          def version_from_lockfile(lockfile, dep_type, dep_name)
            details = JSON.parse(lockfile.content).
                      dig(dep_type, normalise(dep_name))

            case details
            when String then details.gsub(/^==/, "")
            when Hash then details["version"]&.gsub(/^==/, "")
            end
          end

          def ref_from_lockfile(lockfile, dep_type, dep_name)
            details = JSON.parse(lockfile.content).
                      dig(dep_type, normalise(dep_name))

            case details
            when Hash then details["ref"]
            end
          end

          # See https://www.python.org/dev/peps/pep-0503/#normalized-names
          def normalise(name)
            name.downcase.gsub(/[-_.]+/, "-")
          end

          def pipfile_sources
            @pipfile_sources ||=
              TomlRB.parse(pipfile_content).fetch("source", []).
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
