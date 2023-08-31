# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"

module Dependabot
  module NpmAndYarn
    class FileParser
      class LockfileParser
        require "dependabot/npm_and_yarn/file_parser/yarn_lock"
        require "dependabot/npm_and_yarn/file_parser/pnpm_lock"
        require "dependabot/npm_and_yarn/file_parser/json_lock"

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def parse_set
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new

          # NOTE: The DependencySet will de-dupe our dependencies, so they
          # end up unique by name. That's not a perfect representation of
          # the nested nature of JS resolution, but it makes everything work
          # comparably to other flat-resolution strategies
          (yarn_locks + pnpm_locks + package_locks + shrinkwraps).each do |file|
            dependency_set += lockfile_for(file).dependencies
          end

          dependency_set
        end

        def parse
          Helpers.dependencies_with_all_versions_metadata(parse_set)
        end

        def lockfile_details(dependency_name:, requirement:, manifest_name:)
          potential_lockfiles_for_manifest(manifest_name).each do |lockfile|
            details = lockfile_for(lockfile).details(dependency_name, requirement, manifest_name)

            return details if details
          end

          nil
        end

        private

        attr_reader :dependency_files

        def potential_lockfiles_for_manifest(manifest_filename)
          dir_name = File.dirname(manifest_filename)
          possible_lockfile_names =
            %w(package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock).map do |f|
              Pathname.new(File.join(dir_name, f)).cleanpath.to_path
            end +
            %w(yarn.lock pnpm-lock.yaml package-lock.json npm-shrinkwrap.json)

          possible_lockfile_names.uniq.
            filter_map { |nm| dependency_files.find { |f| f.name == nm } }
        end

        def parsed_lockfile(file)
          lockfile_for(file).parsed
        end

        def lockfile_for(file)
          @lockfiles ||= {}
          @lockfiles[file.name] ||= if [*package_locks, *shrinkwraps].include?(file)
                                      JsonLock.new(file)
                                    elsif yarn_locks.include?(file)
                                      YarnLock.new(file)
                                    else
                                      PnpmLock.new(file)
                                    end
        end

        def package_locks
          @package_locks ||=
            dependency_files.
            select { |f| f.name.end_with?("package-lock.json") }
        end

        def pnpm_locks
          @pnpm_locks ||=
            dependency_files.
            select { |f| f.name.end_with?("pnpm-lock.yaml") }
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
