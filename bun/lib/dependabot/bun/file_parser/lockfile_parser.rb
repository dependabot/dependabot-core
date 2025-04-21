# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/bun/file_parser"
require "dependabot/bun/helpers"
require "sorbet-runtime"

module Dependabot
  module Bun
    class FileParser < Dependabot::FileParsers::Base
      class LockfileParser
        extend T::Sig

        require "dependabot/bun/file_parser/bun_lock"

        DEFAULT_LOCKFILES = %w(package-lock.json yarn.lock pnpm-lock.yaml bun.lock npm-shrinkwrap.json).freeze

        LockFile = T.type_alias { BunLock }

        sig { params(dependency_files: T::Array[DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
          @lockfile_cache = T.let({}, T::Hash[String, LockFile])
          @lockfile_details_cache = T.let({}, T::Hash[[String, T.nilable(String), String], T.nilable(T::Hash[String, T.untyped])])
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def parse_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          # NOTE: The DependencySet will de-dupe our dependencies, so they
          # end up unique by name. That's not a perfect representation of
          # the nested nature of JS resolution, but it makes everything work
          # comparably to other flat-resolution strategies
          bun_locks.each do |file|
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
          cache_key = [dependency_name, requirement, manifest_name]
          return @lockfile_details_cache[cache_key] if @lockfile_details_cache.key?(cache_key)

          details = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
          potential_lockfiles_for_manifest(manifest_name).each do |lockfile|
            details = lockfile_for(lockfile).details(dependency_name, requirement, manifest_name)

            break if details
          end

          @lockfile_details_cache[cache_key] = details
          details
        end

        private

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :dependency_files

        sig { params(manifest_filename: String).returns(T::Array[DependencyFile]) }
        def potential_lockfiles_for_manifest(manifest_filename)
          dir_name = File.dirname(manifest_filename)
          possible_lockfile_names = DEFAULT_LOCKFILES.map do |f|
            Pathname.new(File.join(dir_name, f)).cleanpath.to_path
          end + DEFAULT_LOCKFILES

          possible_lockfile_names.uniq
                                 .filter_map { |nm| dependency_files.find { |f| f.name == nm } }
        end

        sig { params(file: DependencyFile).returns(LockFile) }
        def lockfile_for(file)
          @lockfile_cache[file.name] ||= case file.name
                                         when *bun_locks.map(&:name)
                                           BunLock.new(file)
                                         else
                                           raise "Unexpected lockfile: #{file.name}"
                                         end
        end

        sig { params(extension: String).returns(T::Array[DependencyFile]) }
        def select_files_by_extension(extension)
          dependency_files.select { |f| f.name.end_with?(extension) }
        end

        sig { returns(T::Array[DependencyFile]) }
        def bun_locks
          @bun_locks ||= T.let(select_files_by_extension("bun.lock"), T.nilable(T::Array[DependencyFile]))
        end

        sig { returns(T.class_of(Dependabot::Bun::Version)) }
        def version_class
          Bun::Version
        end
      end
    end
  end
end
