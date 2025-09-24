# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/composer/file_fetcher"
require "dependabot/composer/file_parser"

module Dependabot
  module Composer
    class FileFetcher
      class PathDependencyBuilder
        extend T::Sig

        sig { params(path: String, directory: String, lockfile: T.untyped).void }
        def initialize(path:, directory:, lockfile:)
          @path = T.let(path, String)
          @directory = T.let(directory, String)
          @lockfile = T.let(lockfile, T.untyped)
          @parsed_lockfile = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        end

        sig { returns(T.nilable(DependencyFile)) }
        def dependency_file
          filename = File.join(path, PackageManager::MANIFEST_FILENAME)

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

        sig { returns(String) }
        attr_reader :path

        sig { returns(T.untyped) }
        attr_reader :lockfile

        sig { returns(String) }
        attr_reader :directory

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def details_from_lockfile
          keys = FileParser::DEPENDENCY_GROUP_KEYS
                 .map { |h| h.fetch(:lockfile) }

          keys.each do |key|
            next unless parsed_lockfile[key]

            parsed_lockfile[key].each do |details|
              return details if details.dig("dist", "url") == path
            end
          end

          nil
        end

        sig { returns(T.nilable(String)) }
        def build_path_dep_content
          return unless details_from_lockfile

          details_from_lockfile.to_json
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_lockfile
          return {} unless lockfile

          @parsed_lockfile ||= T.let(JSON.parse(lockfile.content), T.nilable(T::Hash[String, T.untyped]))
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
