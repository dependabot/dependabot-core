# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"

module Dependabot
  module NpmAndYarn
    class FileParser
      class LockfileParser
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def parse
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new
          dependency_set += yarn_lock_dependencies if yarn_locks.any?
          dependency_set += package_lock_dependencies if package_locks.any?
          dependency_set += shrinkwrap_dependencies if shrinkwraps.any?
          dependency_set.dependencies
        end

        def lockfile_details(dependency_name:, requirement:)
          [*package_locks, *shrinkwraps].each do |package_lock|
            parsed_package_lock_json = parse_package_lock(package_lock)
            next unless parsed_package_lock_json.dig("dependencies",
                                                     dependency_name)

            return parsed_package_lock_json.dig("dependencies", dependency_name)
          end

          yarn_locks.each do |yarn_lock|
            parsed_yarn_lock = parse_yarn_lock(yarn_lock)

            details_candidates =
              parsed_yarn_lock.
              select { |k, _| k.split(/(?<=\w)\@/).first == dependency_name }

            # If there's only one entry for this dependency, use it, even if
            # the requirement in the lockfile doesn't match
            details = details_candidates.first.last if details_candidates.one?

            details ||=
              details_candidates.
              find do |k, _|
                k.split(/(?<=\w)\@/)[1..-1].join("@") == requirement
              end&.
              last

            return details if details
          end

          nil
        end

        private

        attr_reader :dependency_files

        def yarn_lock_dependencies
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new

          yarn_locks.each do |yarn_lock|
            parse_yarn_lock(yarn_lock).each do |req, details|
              next unless details["version"] && details["version"] != ""

              # Note: The DependencySet will de-dupe our dependencies, so they
              # end up unique by name. That's not a perfect representation of
              # the nested nature of JS resolution, but it makes everything work
              # comparably to other flat-resolution strategies
              dependency_set << Dependency.new(
                name: req.split(/(?<=\w)\@/).first,
                version: details["version"],
                package_manager: "npm_and_yarn",
                requirements: []
              )
            end
          end

          dependency_set
        end

        def package_lock_dependencies
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new

          # Note: The DependencySet will de-dupe our dependencies, so they
          # end up unique by name. That's not a perfect representation of
          # the nested nature of JS resolution, but it makes everything work
          # comparably to other flat-resolution strategies
          package_locks.each do |package_lock|
            parsed_lockfile = parse_package_lock(package_lock)
            deps = recursively_fetch_npm_lock_dependencies(parsed_lockfile)
            dependency_set += deps
          end

          dependency_set
        end

        def shrinkwrap_dependencies
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new

          # Note: The DependencySet will de-dupe our dependencies, so they
          # end up unique by name. That's not a perfect representation of
          # the nested nature of JS resolution, but it makes everything work
          # comparably to other flat-resolution strategies
          shrinkwraps.each do |shrinkwrap|
            parsed_lockfile = parse_shrinkwrap(shrinkwrap)
            deps = recursively_fetch_npm_lock_dependencies(parsed_lockfile)
            dependency_set += deps
          end

          dependency_set
        end

        def recursively_fetch_npm_lock_dependencies(object_with_dependencies)
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new

          object_with_dependencies.
            fetch("dependencies", {}).each do |name, details|
              next unless details["version"] && details["version"] != ""

              dependency_set << Dependency.new(
                name: name,
                version: details["version"],
                package_manager: "npm_and_yarn",
                requirements: []
              )

              dependency_set += recursively_fetch_npm_lock_dependencies(details)
            end

          dependency_set
        end

        def parse_package_lock(package_lock)
          @parse_package_lock ||= {}
          @parse_package_lock[package_lock.name] ||=
            JSON.parse(package_lock.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, package_lock.path
        end

        def parse_shrinkwrap(shrinkwrap)
          @parse_shrinkwrap ||= {}
          @parse_shrinkwrap[shrinkwrap.name] ||=
            JSON.parse(shrinkwrap.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, shrinkwrap.path
        end

        def parse_yarn_lock(yarn_lock)
          @parsed_yarn_lock ||= {}
          @parsed_yarn_lock[yarn_lock.name] ||=
            SharedHelpers.in_a_temporary_directory do
              File.write("yarn.lock", yarn_lock.content)

              SharedHelpers.run_helper_subprocess(
                command: "node #{yarn_helper_path}",
                function: "parseLockfile",
                args: [Dir.pwd]
              )
            rescue SharedHelpers::HelperSubprocessFailed
              raise Dependabot::DependencyFileNotParseable, yarn_lock.path
            end
        end

        def yarn_helper_path
          NativeHelpers.yarn_helper_path
        end

        def package_locks
          @package_locks ||=
            dependency_files.
            select { |f| f.name.end_with?("package-lock.json") }
        end

        def yarn_locks
          @yarn_locks ||=
            dependency_files.
            select { |f| f.name.end_with?("yarn.lock") }
        end

        def shrinkwraps
          @shrinkwraps ||=
            dependency_files.
            select { |f| f.name.end_with?("npm-shrinkwrap.json") }
        end
      end
    end
  end
end
