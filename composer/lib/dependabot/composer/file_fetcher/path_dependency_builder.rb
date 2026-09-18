# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/composer/file_fetcher"
require "dependabot/composer/file_parser"
require "dependabot/composer/lockfile_document"

module Dependabot
  module Composer
    class FileFetcher
      class PathDependencyBuilder
        extend T::Sig

        sig { params(path: String, directory: String, lockfile: T.nilable(Dependabot::DependencyFile)).void }
        def initialize(path:, directory:, lockfile:)
          @path = path
          @directory = directory
          @lockfile = lockfile
          @lockfile_document = T.let(nil, T.nilable(LockfileDocument))
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

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :lockfile

        sig { returns(String) }
        attr_reader :directory

        sig { returns(T.nilable(LockfileDocument::PackageRecord)) }
        def details_from_lockfile
          keys = FileParser::DEPENDENCY_GROUP_KEYS
                 .map { |h| h.fetch(:lockfile) }

          keys.each do |key|
            package = lockfile_document&.find_path_package(key, path)
            return package if package
          end

          nil
        end

        sig { returns(T.nilable(String)) }
        def build_path_dep_content
          details_from_lockfile&.to_manifest_json
        end

        sig { returns(T.nilable(LockfileDocument)) }
        def lockfile_document
          return unless lockfile

          @lockfile_document ||= LockfileDocument.from_file(T.must(lockfile))
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
