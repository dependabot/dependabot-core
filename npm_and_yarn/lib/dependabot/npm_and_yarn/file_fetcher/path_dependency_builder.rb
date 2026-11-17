# typed: strong
# frozen_string_literal: true

require "json"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/npm_and_yarn/file_fetcher"
require "dependabot/npm_and_yarn/file_parser/json_lock"
require "dependabot/npm_and_yarn/file_parser/yarn_lock"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class FileFetcher
      class PathDependencyBuilder
        extend T::Sig

        sig do
          params(
            dependency_name: String,
            path: String,
            directory: String,
            package_lock: T.nilable(DependencyFile),
            yarn_lock: T.nilable(DependencyFile)
          )
            .void
        end
        def initialize(
          dependency_name:,
          path:,
          directory:,
          package_lock:,
          yarn_lock:
        )
          @dependency_name = dependency_name
          @path = path
          @directory = directory
          @package_lock = package_lock
          @yarn_lock = yarn_lock
          @parsed_yarn_lock = T.let(nil, T.nilable(T::Hash[String, FileParser::YarnLock::Record]))
        end

        sig { returns(DependencyFile) }
        def dependency_file
          filename = File.join(path, "package.json")

          DependencyFile.new(
            name: Pathname.new(filename).cleanpath.to_path,
            content: build_path_dep_content,
            directory: directory,
            support_file: true
          )
        end

        private

        sig { returns(String) }
        attr_reader :dependency_name

        sig { returns(String) }
        attr_reader :path

        sig { returns(T.nilable(DependencyFile)) }
        attr_reader :package_lock

        sig { returns(T.nilable(DependencyFile)) }
        attr_reader :yarn_lock

        sig { returns(String) }
        attr_reader :directory

        sig { params(name: String).returns(T.nilable([String, FileParser::YarnLock::Record])) }
        def yarn_entry_for(name)
          parsed_yarn_lock.each do |descriptor, record|
            parts = descriptor.split(/(?<=\w)\@/)
            next unless parts.first == name

            requirement = T.must(parts.last)
            next unless requirement.start_with?(*FileFetcher::PATH_DEPENDENCY_STARTS)

            return [requirement, record]
          end

          nil
        end

        sig { returns(T.nilable(FileParser::JsonLock::Record)) }
        def details_from_npm_lock
          path_starts = FileFetcher::NPM_PATH_DEPENDENCY_STARTS
          path_deps = parsed_package_lock.select do |_, record|
            record.version&.start_with?(*path_starts)
          end
          path_deps.find { |n, _| n == dependency_name }&.last
        end

        sig { returns(String) }
        def build_path_dep_content
          if (yarn_entry = yarn_entry_for(dependency_name))
            yarn_details = yarn_entry.last
            {
              name: dependency_name,
              version: yarn_details.version || "0.0.1",
              dependencies: replace_yarn_lockfile_paths(yarn_details.dependency_requirements),
              optionalDependencies: replace_yarn_lockfile_paths(yarn_details.optional_dependencies)
            }.compact.to_json
          elsif (npm_details = details_from_npm_lock)
            {
              name: dependency_name,
              version: "0.0.1",
              dependencies: npm_details.requires
            }.compact.to_json
          else
            raise Dependabot::PathDependenciesNotReachable, [dependency_name]
          end
        end

        # If an unfetchable path dependency itself has path dependencies
        # then the paths in the yarn.lock for them will be absolute, not
        # relative. Worse, they may point to the user's local cache.
        # We work around this by constructing a relative path to the
        # (second-level) path dependencies.
        sig do
          params(dependencies_hash: T.nilable(T::Hash[String, String])).returns(T.nilable(T::Hash[String, String]))
        end
        def replace_yarn_lockfile_paths(dependencies_hash)
          return unless dependencies_hash

          dependencies_hash.each_with_object({}) do |(name, value), obj|
            obj[name] = value
            next unless value.start_with?(*FileFetcher::PATH_DEPENDENCY_STARTS)

            path_from_base = yarn_entry_for(name)&.first
            next unless path_from_base

            cleaned_path = path_from_base
                           .gsub(FileFetcher::PATH_DEPENDENCY_CLEAN_REGEX, "")
            obj[name] = "file:" + File.join(inverted_path, cleaned_path)
          end
        end

        sig { returns(T::Hash[String, FileParser::JsonLock::Record]) }
        def parsed_package_lock
          file = package_lock
          return {} unless file

          FileParser::JsonLock.new(file).legacy_dependencies
        rescue Dependabot::DependencyFileNotParseable => e
          raise unless e.cause.is_a?(JSON::ParserError)

          {}
        end

        sig { returns(T::Hash[String, FileParser::YarnLock::Record]) }
        def parsed_yarn_lock
          return @parsed_yarn_lock if @parsed_yarn_lock

          file = yarn_lock
          @parsed_yarn_lock = file ? FileParser::YarnLock.new(file).parsed : {}
        end

        # The path back to the root lockfile
        sig { returns(String) }
        def inverted_path
          path.split("/").map do |part|
            next part if part == "."
            next "tmp" if part == ".."

            ".."
          end.join("/")
        end
      end
    end
  end
end
