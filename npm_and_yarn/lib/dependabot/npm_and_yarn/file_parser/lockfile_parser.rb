# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"

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

        def lockfile_details(dependency_name:, requirement:, manifest_name:)
          potential_lockfiles_for_manifest(manifest_name).each do |lockfile|
            details =
              if [*package_locks, *shrinkwraps].include?(lockfile)
                npm_lockfile_details(lockfile, dependency_name, manifest_name)
              else
                yarn_lockfile_details(lockfile, dependency_name, requirement, manifest_name)
              end

            return details if details
          end

          nil
        end

        private

        attr_reader :dependency_files

        def potential_lockfiles_for_manifest(manifest_filename)
          dir_name = File.dirname(manifest_filename)
          possible_lockfile_names =
            %w(package-lock.json npm-shrinkwrap.json yarn.lock).map do |f|
              Pathname.new(File.join(dir_name, f)).cleanpath.to_path
            end +
            %w(yarn.lock package-lock.json npm-shrinkwrap.json)

          possible_lockfile_names.uniq.
            filter_map { |nm| dependency_files.find { |f| f.name == nm } }
            
        end

        def npm_lockfile_details(lockfile, dependency_name, manifest_name)
          parsed_lockfile = parse_package_lock(lockfile)

          if Helpers.npm_version(lockfile.content) == "npm8"
            # NOTE: npm 8 sometimes doesn't install workspace dependencies in the
            # workspace folder so we need to fallback to checking top-level
            nested_details = parsed_lockfile.dig("packages", node_modules_path(manifest_name, dependency_name))
            details = nested_details || parsed_lockfile.dig("packages", "node_modules/#{dependency_name}")
            details&.slice("version", "resolved", "integrity", "dev")
          else
            parsed_lockfile.dig("dependencies", dependency_name)
          end
        end

        def yarn_lockfile_details(lockfile, dependency_name, requirement, _manifest_name)
          parsed_yarn_lock = parse_yarn_lock(lockfile)
          details_candidates =
            parsed_yarn_lock.
            select { |k, _| k.split(/(?<=\w)\@/)[0] == dependency_name }

          # If there's only one entry for this dependency, use it, even if
          # the requirement in the lockfile doesn't match
          if details_candidates.one?
            details_candidates.first.last
          else
            details_candidates.find do |k, _|
              k.split(/(?<=\w)\@/)[1..-1].join("@") == requirement
            end&.last
          end
        end

        def node_modules_path(manifest_name, dependency_name)
          return "node_modules/#{dependency_name}" if manifest_name == "package.json"

          workspace_path = manifest_name.gsub("/package.json", "")
          File.join(workspace_path, "node_modules", dependency_name)
        end

        def yarn_lock_dependencies
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new

          yarn_locks.each do |yarn_lock|
            parse_yarn_lock(yarn_lock).each do |req, details|
              next unless semver_version_for(details["version"])
              next if alias_package?(req)

              # NOTE: The DependencySet will de-dupe our dependencies, so they
              # end up unique by name. That's not a perfect representation of
              # the nested nature of JS resolution, but it makes everything work
              # comparably to other flat-resolution strategies
              dependency_set << Dependency.new(
                name: req.split(/(?<=\w)\@/).first,
                version: semver_version_for(details["version"]),
                package_manager: "npm_and_yarn",
                requirements: []
              )
            end
          end

          dependency_set
        end

        def package_lock_dependencies
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new

          # NOTE: The DependencySet will de-dupe our dependencies, so they
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

          # NOTE: The DependencySet will de-dupe our dependencies, so they
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
              next unless semver_version_for(details["version"])

              dependency_args = {
                name: name,
                version: semver_version_for(details["version"]),
                package_manager: "npm_and_yarn",
                requirements: []
              }

              if details["bundled"]
                dependency_args[:subdependency_metadata] =
                  [{ npm_bundled: details["bundled"] }]
              end

              if details["dev"]
                dependency_args[:subdependency_metadata] =
                  [{ production: !details["dev"] }]
              end

              dependency_set << Dependency.new(**dependency_args)
              dependency_set += recursively_fetch_npm_lock_dependencies(details)
            end

          dependency_set
        end

        def semver_version_for(version_string)
          # The next two lines are to guard against improperly formatted
          # versions in a lockfile, such as an empty string or additional
          # characters. NPM/yarn fixes these when running an update, so we can
          # safely ignore these versions.
          return if version_string == ""
          return unless version_class.correct?(version_string)

          version_string
        end

        def alias_package?(requirement)
          requirement.include?("@npm:")
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
                command: NativeHelpers.helper_path,
                function: "yarn:parseLockfile",
                args: [Dir.pwd]
              )
            rescue SharedHelpers::HelperSubprocessFailed
              raise Dependabot::DependencyFileNotParseable, yarn_lock.path
            end
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

        def version_class
          NpmAndYarn::Version
        end
      end
    end
  end
end
