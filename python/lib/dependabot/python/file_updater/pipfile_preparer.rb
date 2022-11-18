# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/python/file_parser"
require "dependabot/python/file_updater"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileUpdater
      class PipfilePreparer
        def initialize(pipfile_content:, lockfile: nil)
          @pipfile_content = pipfile_content
          @lockfile = lockfile
        end

        def replace_sources(credentials)
          pipfile_object = TomlRB.parse(pipfile_content)

          pipfile_object["source"] =
            pipfile_sources.reject { |h| h["url"].include?("${") } +
            config_variable_sources(credentials)

          TomlRB.dump(pipfile_object)
        end

        def freeze_top_level_dependencies_except(dependencies)
          return pipfile_content unless lockfile

          pipfile_object = TomlRB.parse(pipfile_content)
          excluded_names = dependencies.map(&:name)

          Python::FileParser::DEPENDENCY_GROUP_KEYS.each do |keys|
            next unless pipfile_object[keys[:pipfile]]

            pipfile_object.fetch(keys[:pipfile]).each do |dep_name, _|
              next if excluded_names.include?(normalise(dep_name))

              freeze_dependency(dep_name, pipfile_object, keys)
            end
          end

          TomlRB.dump(pipfile_object)
        end

        def freeze_dependency(dep_name, pipfile_object, keys)
          locked_version = version_from_lockfile(
            keys[:lockfile],
            normalise(dep_name)
          )
          locked_ref = ref_from_lockfile(
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

        def update_python_requirement(requirement)
          pipfile_object = TomlRB.parse(pipfile_content)

          pipfile_object["requires"] ||= {}
          if pipfile_object.dig("requires", "python_full_version") && pipfile_object.dig("requires", "python_version")
            pipfile_object["requires"].delete("python_full_version")
          elsif pipfile_object.dig("requires", "python_full_version")
            pipfile_object["requires"].delete("python_full_version")
            pipfile_object["requires"]["python_version"] = requirement
          end
          TomlRB.dump(pipfile_object)
        end

        private

        attr_reader :pipfile_content, :lockfile

        def version_from_lockfile(dep_type, dep_name)
          details = parsed_lockfile.dig(dep_type, normalise(dep_name))

          case details
          when String then details.gsub(/^==/, "")
          when Hash then details["version"]&.gsub(/^==/, "")
          end
        end

        def ref_from_lockfile(dep_type, dep_name)
          details = parsed_lockfile.dig(dep_type, normalise(dep_name))

          case details
          when Hash then details["ref"]
          end
        end

        def parsed_lockfile
          @parsed_lockfile ||= JSON.parse(lockfile.content)
        end

        def normalise(name)
          NameNormaliser.normalise(name)
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
            map { |c| { "url" => AuthedUrlBuilder.authed_url(credential: c) } }
        end
      end
    end
  end
end
