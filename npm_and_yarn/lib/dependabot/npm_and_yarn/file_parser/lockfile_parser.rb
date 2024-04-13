# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class LockfileParser
        extend T::Sig

        require "dependabot/npm_and_yarn/file_parser/yarn_lock"
        require "dependabot/npm_and_yarn/file_parser/pnpm_lock"
        require "dependabot/npm_and_yarn/file_parser/json_lock"

        sig { params(dependency_files: T::Array[DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def parse_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          # NOTE: The DependencySet will de-dupe our dependencies, so they
          # end up unique by name. That's not a perfect representation of
          # the nested nature of JS resolution, but it makes everything work
          # comparably to other flat-resolution strategies
          (yarn_locks + pnpm_locks + package_locks + shrinkwraps).each do |file|
            dependency_set += lockfile_for(file).dependencies
          end

          dependency_set
        end

        sig { returns(T::Array[Dependency]) }
        def parse
          Helpers.dependencies_with_all_versions_metadata(parse_set)
        end

        sig do
          params(dependency_name: String, requirement: T.nilable(String), manifest_name: String)
            .returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def lockfile_details(dependency_name:, requirement:, manifest_name:)
          details = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
          potential_lockfiles_for_manifest(manifest_name).each do |lockfile|
            details = lockfile_for(lockfile).details(dependency_name, requirement, manifest_name)

            break if details
          end

          details
        end

        private

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :dependency_files

        sig { params(manifest_filename: String).returns(T::Array[DependencyFile]) }
        def potential_lockfiles_for_manifest(manifest_filename)
          dir_name = File.dirname(manifest_filename)
          possible_lockfile_names =
            %w(package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock).map do |f|
              Pathname.new(File.join(dir_name, f)).cleanpath.to_path
            end +
            %w(yarn.lock pnpm-lock.yaml package-lock.json npm-shrinkwrap.json)

          possible_lockfile_names.uniq
                                 .filter_map { |nm| dependency_files.find { |f| f.name == nm } }
        end

        sig { params(file: DependencyFile).returns(T.any(JsonLock, YarnLock, PnpmLock)) }
        def lockfile_for(file)
          @lockfiles ||= T.let({}, T.nilable(T::Hash[String, T.any(JsonLock, YarnLock, PnpmLock)]))
          @lockfiles[file.name] ||= if [*package_locks, *shrinkwraps].include?(file)
                                      JsonLock.new(file)
                                    elsif yarn_locks.include?(file)
                                      YarnLock.new(file)
                                    else
                                      PnpmLock.new(file)
                                    end
        end

        sig { returns(T::Array[DependencyFile]) }
        def package_locks
          @package_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("package-lock.json") }, T.nilable(T::Array[DependencyFile])
          )
        end

        sig { returns(T::Array[DependencyFile]) }
        def pnpm_locks
          @pnpm_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("pnpm-lock.yaml") }, T.nilable(T::Array[DependencyFile])
          )
        end

        sig { returns(T::Array[DependencyFile]) }
        def yarn_locks
          @yarn_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("yarn.lock") }, T.nilable(T::Array[DependencyFile])
          )
        end

        sig { returns(T::Array[DependencyFile]) }
        def shrinkwraps
          @shrinkwraps ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("npm-shrinkwrap.json") }, T.nilable(T::Array[DependencyFile])
          )
        end

        sig { returns(T.class_of(Dependabot::NpmAndYarn::Version)) }
        def version_class
          NpmAndYarn::Version
        end
      end
    end
  end
end
