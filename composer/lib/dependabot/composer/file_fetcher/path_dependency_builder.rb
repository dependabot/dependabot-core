# frozen_string_literal: true

require "json"
require "dependabot/dependency_file"
require "dependabot/composer/file_fetcher"
require "dependabot/composer/file_parser"

module Dependabot
  module Composer
    class FileFetcher
      class PathDependencyBuilder
        def initialize(path:, directory:, lockfile:)
          @path = path
          @directory = directory
          @lockfile = lockfile
        end

        def dependency_file
          filename = File.join(path, "composer.json")

          # Current we just return `nil` if a path dependency can't be built.
          # In future we may wish to change that to a raise. (We'll get errors
          # in the UpdateChecker or FileUpdater if we fail to build files.)
          built_content = build_path_dep_content
          return unless built_content

          DependencyFile.new(
            name: Pathname.new(filename).cleanpath.to_path,
            content: built_content,
            directory: directory,
            support_file: true
          )
        end

        private

        attr_reader :path, :lockfile, :directory

        def details_from_lockfile
          keys = FileParser::DEPENDENCY_GROUP_KEYS.
                 map { |h| h.fetch(:lockfile) }

          keys.each do |key|
            next unless parsed_lockfile[key]

            parsed_lockfile[key].each do |details|
              return details if details.dig("dist", "url") == path
            end
          end

          nil
        end

        def build_path_dep_content
          return unless details_from_lockfile

          details_from_lockfile.to_json
        end

        def parsed_lockfile
          return {} unless lockfile

          @parsed_lockfile ||= JSON.parse(lockfile.content)
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
