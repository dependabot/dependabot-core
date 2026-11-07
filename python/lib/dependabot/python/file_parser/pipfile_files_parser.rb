# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/python/file_parser"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base
      class PipfileFilesParser
        extend T::Sig

        DEPENDENCY_GROUP_KEYS = T.let(
          [
            {
              pipfile: "packages",
              lockfile: "default"
            },
            {
              pipfile: "dev-packages",
              lockfile: "develop"
            }
          ].freeze,
          T::Array[T::Hash[Symbol, String]]
        )

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          dependency_set += pipfile_dependencies
          dependency_set += pipfile_lock_dependencies

          dependency_set
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def pipfile_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          DEPENDENCY_GROUP_KEYS.each do |keys|
            pipfile_document.entries(keys.fetch(:pipfile)).each do |entry|
              group = keys.fetch(:lockfile)
              next unless entry.specifies_version?
              next if entry.git_or_path?
              next if pipfile_lock && !dependency_version(entry, group)

              dependencies <<
                Dependency.new(
                  name: normalised_name(entry.name),
                  version: dependency_version(entry, group),
                  requirements: [{
                    requirement: entry.requirement,
                    file: T.must(pipfile).name,
                    source: nil,
                    groups: [group]
                  }],
                  package_manager: "pip",
                  metadata: { original_name: entry.name }
                )
            end
          end

          dependencies
        end

        # Create a DependencySet where each element has no requirement. Any
        # requirements will be added when combining the DependencySet with
        # other DependencySets.
        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def pipfile_lock_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new
          return dependencies unless pipfile_lock

          DEPENDENCY_GROUP_KEYS.map { |h| h.fetch(:lockfile) }.each do |key|
            pipfile_lock_document.entries(key).each do |entry|
              version = entry.lockfile_version
              next unless version

              dependencies <<
                Dependency.new(
                  name: entry.name,
                  version: version.gsub(/^===?/, ""),
                  requirements: [],
                  package_manager: "pip",
                  subdependency_metadata: [{ production: key != "develop" }]
                )
            end
          end

          dependencies
        end

        sig { params(entry: PipfileDocument::Entry, group: String).returns(T.nilable(String)) }
        def dependency_version(entry, group)
          req = entry.lookup_version

          if pipfile_lock
            version = pipfile_lock_document.version_for(group, normalised_name(entry.name))
            version&.gsub(/^===?/, "")
          elsif T.must(req).start_with?("==") && !T.must(req).include?("*")
            T.must(req).strip.gsub(/^===?/, "")
          end
        end

        sig { params(name: String, extras: T::Array[String]).returns(String) }
        def normalised_name(name, extras = [])
          NameNormaliser.normalise_including_extras(name, extras)
        end

        sig { returns(PipfileDocument) }
        def pipfile_document
          @pipfile_document ||= T.let(PipfileDocument.from_file(T.must(pipfile)), T.nilable(PipfileDocument))
        end

        sig { returns(PipfileLockDocument) }
        def pipfile_lock_document
          @pipfile_lock_document ||= T.let(
            PipfileLockDocument.from_file(T.must(pipfile_lock)),
            T.nilable(PipfileLockDocument)
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pipfile
          @pipfile ||= T.let(dependency_files.find { |f| f.name == "Pipfile" }, T.nilable(Dependabot::DependencyFile))
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pipfile_lock
          @pipfile_lock ||= T.let(
            dependency_files.find { |f| f.name == "Pipfile.lock" },
            T.nilable(Dependabot::DependencyFile)
          )
        end
      end
    end
  end
end
