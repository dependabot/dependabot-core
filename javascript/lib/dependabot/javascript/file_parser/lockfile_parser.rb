# typed: strong
# frozen_string_literal: true

module Dependabot
  module Javascript
    class FileParser
      class LockfileParser
        extend T::Helpers
        extend T::Sig

        abstract!

        DEFAULT_LOCKFILES = %w(bun.lock).freeze

        LockFile = T.type_alias { Bun::FileParser::BunLock }

        sig { params(dependency_files: T::Array[DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { abstract.returns(Dependabot::FileParsers::Base::DependencySet) }
        def parse_set; end

        sig { returns(T::Array[Dependency]) }
        def parse
          Javascript::FileParser.dependencies_with_all_versions_metadata(parse_set)
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
          possible_lockfile_names = DEFAULT_LOCKFILES.map do |f|
            Pathname.new(File.join(dir_name, f)).cleanpath.to_path
          end + DEFAULT_LOCKFILES

          possible_lockfile_names.uniq
                                 .filter_map { |nm| dependency_files.find { |f| f.name == nm } }
        end

        sig { abstract.params(file: DependencyFile).returns(LockFile) }
        def lockfile_for(file); end

        sig { params(extension: String).returns(T::Array[DependencyFile]) }
        def select_files_by_extension(extension)
          dependency_files.select { |f| f.name.end_with?(extension) }
        end

        sig { abstract.returns(T.class_of(Version)) }
        def version_class; end
      end
    end
  end
end
