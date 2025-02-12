# typed: strict
# frozen_string_literal: true

require "json"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/npm_and_yarn/file_fetcher"
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
        def initialize(dependency_name:, path:, directory:, package_lock:,
                       yarn_lock:)
          @dependency_name = dependency_name
          @path = path
          @directory = directory
          @package_lock = package_lock
          @yarn_lock = yarn_lock
        end

        sig { returns(DependencyFile) }
        def dependency_file
          filename = File.join(path, "package.json")

          DependencyFile.new(
            name: Pathname.new(filename).cleanpath.to_path,
            content: build_path_dep_content(dependency_name),
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

        sig { returns(T.untyped) }
        def details_from_yarn_lock
          path_starts = FileFetcher::PATH_DEPENDENCY_STARTS
          parsed_yarn_lock.to_a
                          .find do |n, _|
            next false unless n.split(/(?<=\w)\@/).first == dependency_name

            T.must(n.split(/(?<=\w)\@/).last).start_with?(*path_starts)
          end&.last
        end

        sig { returns(T.untyped) }
        def details_from_npm_lock
          path_starts = FileFetcher::NPM_PATH_DEPENDENCY_STARTS
          path_deps = parsed_package_lock.fetch("dependencies", []).to_a
                                         .select do |_, v|
            v.fetch("version", "").start_with?(*path_starts)
          end
          path_deps.find { |n, _| n == dependency_name }&.last
        end

        sig { params(dependency_name: String).returns(String) }
        def build_path_dep_content(dependency_name)
          unless details_from_yarn_lock || details_from_npm_lock
            raise Dependabot::PathDependenciesNotReachable, [dependency_name]
          end

          if details_from_yarn_lock
            {
              name: dependency_name,
              version: details_from_yarn_lock["version"] || "0.0.1",
              dependencies:
                replace_yarn_lockfile_paths(
                  details_from_yarn_lock["dependencies"]
                ),
              optionalDependencies:
                replace_yarn_lockfile_paths(
                  details_from_yarn_lock["optionalDependencies"]
                )
            }.compact.to_json
          else
            {
              name: dependency_name,
              version: "0.0.1",
              dependencies: details_from_npm_lock["requires"]
            }.compact.to_json
          end
        end

        # If an unfetchable path dependency itself has path dependencies
        # then the paths in the yarn.lock for them will be absolute, not
        # relative. Worse, they may point to the user's local cache.
        # We work around this by constructing a relative path to the
        # (second-level) path dependencies.
        sig { params(dependencies_hash: T.nilable(T::Hash[String, T.untyped])).returns(T.untyped) }
        def replace_yarn_lockfile_paths(dependencies_hash)
          return unless dependencies_hash

          dependencies_hash.each_with_object({}) do |(name, value), obj|
            obj[name] = value
            next unless value.start_with?(*FileFetcher::PATH_DEPENDENCY_STARTS)

            path_from_base =
              parsed_yarn_lock.to_a
                              .find do |n, _|
                next false unless n.split(/(?<=\w)\@/).first == name

                T.must(n.split(/(?<=\w)\@/).last)
                 .start_with?(*FileFetcher::PATH_DEPENDENCY_STARTS)
              end&.first&.split(/(?<=\w)\@/)&.last

            next unless path_from_base

            cleaned_path = path_from_base
                           .gsub(FileFetcher::PATH_DEPENDENCY_CLEAN_REGEX, "")
            obj[name] = "file:" + File.join(inverted_path, cleaned_path)
          end
        end

        sig { returns(T.untyped) }
        def parsed_package_lock
          return {} unless package_lock

          JSON.parse(T.must(T.must(package_lock).content))
        rescue JSON::ParserError
          {}
        end

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def parsed_yarn_lock
          return unless yarn_lock
          return @parsed_yarn_lock if defined?(@parsed_yarn_lock)

          parsed = T.cast(SharedHelpers.in_a_temporary_directory do
            File.write("yarn.lock", T.must(yarn_lock).content)

            SharedHelpers.run_helper_subprocess(
              command: NativeHelpers.helper_path,
              function: "yarn:parseLockfile",
              args: [Dir.pwd]
            )
          rescue SharedHelpers::HelperSubprocessFailed
            raise Dependabot::DependencyFileNotParseable, T.must(yarn_lock).path
          end, T::Hash[String, T.untyped])
          @parsed_yarn_lock = T.let(parsed, T.nilable(T::Hash[String, T.untyped]))
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
