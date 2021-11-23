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

        def replace_sources(credentials)
          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object.fetch("tool").fetch("poetry")

          sources = pyproject_sources + config_variable_sources(credentials)
          poetry_object["source"] = sources if sources.any?

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

          Dependabot::Python::FileParser::PoetryFilesParser::POETRY_DEPENDENCY_TYPES.each do |key|
            next unless poetry_object[key]

            poetry_object.fetch(key).each do |dep_name, _|
              next if excluded_names.include?(normalise(dep_name))

              locked_details = locked_details(dep_name)

              next unless (locked_version = locked_details&.fetch("version"))

              next if %w(directory file url).include?(locked_details&.dig("source", "type"))

              if locked_details&.dig("source", "type") == "git"
                poetry_object[key][dep_name] = {
                  "git" => locked_details&.dig("source", "url"),
                  "rev" => locked_details&.dig("source", "reference")
                }
              elsif poetry_object[key][dep_name].is_a?(Hash)
                poetry_object[key][dep_name]["version"] = locked_version
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
            map do |c|
              {
                "url" => AuthedUrlBuilder.authed_url(credential: c),
                "name" => SecureRandom.hex[0..3],
                "default" => c["replaces-base"]
              }.compact
            end
        end

        def parsed_lockfile
          @parsed_lockfile ||= TomlRB.parse(lockfile.content)
        end
      end
    end
  end
end
