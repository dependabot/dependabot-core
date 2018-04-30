# frozen_string_literal: true

require "toml-rb"

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
            parsed_lockfile = JSON.parse(lockfile.content)
            excluded_names = dependencies.map(&:name)

            FileParsers::Python::Pip::DEPENDENCY_GROUP_KEYS.each do |keys|
              next unless pipfile_object[keys[:pipfile]]

              pipfile_object.fetch(keys[:pipfile]).each do |dep_name, _|
                next if excluded_names.include?(dep_name)
                locked_version = parsed_lockfile.
                                 dig(keys[:lockfile], dep_name, "version")&.
                                 gsub(/^==/, "")
                next unless locked_version

                if pipfile_object[keys[:pipfile]][dep_name].is_a?(Hash)
                  pipfile_object[keys[:pipfile]][dep_name]["version"] =
                    "==#{locked_version}"
                else
                  pipfile_object[keys[:pipfile]][dep_name] =
                    "==#{locked_version}"
                end
              end
            end

            TomlRB.dump(pipfile_object)
          end

          private

          attr_reader :pipfile_content

          def pipfile_sources
            @pipfile_sources ||=
              TomlRB.parse(pipfile_content).fetch("source", []).
              map { |h| h.dup.merge("url" => h["url"].gsub(%r{/*$}, "") + "/") }
          end

          def config_variable_sources(credentials)
            @config_variable_sources ||=
              credentials.
              select { |cred| cred["index-url"] }.
              map { |cred| { "url" => cred["index-url"] } }
          end
        end
      end
    end
  end
end
