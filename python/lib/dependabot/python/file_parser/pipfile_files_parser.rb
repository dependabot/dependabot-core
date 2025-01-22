# typed: strict
# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/python/file_parser"
require "dependabot/errors"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileParser
      class PipfileFilesParser
        extend T::Sig
        DEPENDENCY_GROUP_KEYS = T.let([
          {
            pipfile: "packages",
            lockfile: "default"
          },
          {
            pipfile: "dev-packages",
            lockfile: "develop"
          }
        ].freeze, T::Array[T::Hash[Symbol, String]])

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
            next unless parsed_pipfile[T.must(keys[:pipfile])]

            parsed_pipfile[T.must(keys[:pipfile])].map do |dep_name, req|
              group = keys[:lockfile]
              next unless specifies_version?(req)
              next if git_or_path_requirement?(req)
              next if pipfile_lock && !dependency_version(dep_name, req, T.must(group))

              # Empty requirements are not allowed in Dependabot::Dependency and
              # equivalent to "*" (latest available version)
              req = "*" if req == ""

              dependencies <<
                Dependency.new(
                  name: normalised_name(dep_name),
                  version: dependency_version(dep_name, req, T.must(group)),
                  requirements: [{
                    requirement: req.is_a?(String) ? req : req["version"],
                    file: T.must(pipfile).name,
                    source: nil,
                    groups: [group]
                  }],
                  package_manager: "pip",
                  metadata: { original_name: dep_name }
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
            next unless parsed_pipfile_lock[key]

            parsed_pipfile_lock[key].each do |dep_name, details|
              version = case details
                        when String then details
                        when Hash then details["version"]
                        end
              next unless version
              next if git_or_path_requirement?(details)

              dependencies <<
                Dependency.new(
                  name: dep_name,
                  version: version&.gsub(/^===?/, ""),
                  requirements: [],
                  package_manager: "pip",
                  subdependency_metadata: [{ production: key != "develop" }]
                )
            end
          end

          dependencies
        end

        sig do
          params(dep_name: String, requirement: T.any(String, T::Hash[String, T.untyped]),
                 group: String).returns(T.nilable(String))
        end
        def dependency_version(dep_name, requirement, group)
          req = version_from_hash_or_string(requirement)

          if pipfile_lock
            details = parsed_pipfile_lock
                      .dig(group, normalised_name(dep_name))

            version = version_from_hash_or_string(details)
            version&.gsub(/^===?/, "")
          elsif T.must(req).start_with?("==") && !T.must(req).include?("*")
            T.must(req).strip.gsub(/^===?/, "")
          end
        end

        sig { params(obj: T.any(String, T::Hash[String, T.untyped])).returns(T.nilable(String)) }
        def version_from_hash_or_string(obj)
          case obj
          when String then obj.strip
          when Hash then obj["version"]
          end
        end

        sig { params(req: T.any(String, T::Hash[String, T.untyped])).returns(T.any(T::Boolean, String)) }
        def specifies_version?(req)
          return true if req.is_a?(String)

          req["version"]
        end

        sig { params(req: T.any(String, T::Hash[String, T.untyped])).returns(T::Boolean) }
        def git_or_path_requirement?(req)
          return false unless req.is_a?(Hash)

          %w(git path).any? { |k| req.key?(k) }
        end

        sig { params(name: String, extras: T::Array[String]).returns(String) }
        def normalised_name(name, extras = [])
          NameNormaliser.normalise_including_extras(name, extras)
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_pipfile
          @parsed_pipfile ||= T.let(TomlRB.parse(T.must(pipfile).content), T.nilable(T::Hash[String, T.untyped]))
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, T.must(pipfile).path
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_pipfile_lock
          @parsed_pipfile_lock ||= T.let(JSON.parse(T.must(T.must(pipfile_lock).content)),
                                         T.nilable(T::Hash[String, T.untyped]))
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, T.must(pipfile_lock).path
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pipfile
          @pipfile ||= T.let(dependency_files.find { |f| f.name == "Pipfile" }, T.nilable(Dependabot::DependencyFile))
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pipfile_lock
          @pipfile_lock ||= T.let(dependency_files.find { |f| f.name == "Pipfile.lock" },
                                  T.nilable(Dependabot::DependencyFile))
        end
      end
    end
  end
end
