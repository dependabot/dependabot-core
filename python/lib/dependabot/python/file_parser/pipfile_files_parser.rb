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

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency_files:, credentials: [])
          @dependency_files = dependency_files
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
          @direct_dependencies = T.let([], T::Array[String])
          @depends_on_dictionary = T.let({}, T::Hash[String, T::Array[String]])
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          dependency_set += pipfile_dependencies
          dependency_set += pipfile_lock_dependencies

          dependency_set
        end

        private

        # NOTE: It might make more sense to generate everything from the structured graph
        #
        # This is purely to get an illustrated example of a Python graph working, I think we should step back and
        # consider how we want to land the responsibility between the parser and any extra commands to fill in blanks
        # in the dependency submission payload before we lock in on this model so I've err'd on the side of least code
        # at the cost of more native commands.
        sig { void }
        def fetch_metadata_for_lockfile
          SharedHelpers.in_a_temporary_repo_directory(T.must(dependency_files.first).directory) do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_dependency_files

              # We would now need credentials to be made available to the parser in order to run this install,
              # I've omitted it for now but this is a significant extra complexity we could avoid if we didn't need
              # the `depends_on` data or fetched it as a post-parser process using a new component.
              SharedHelpers.run_shell_command("pyenv exec pipenv install --dev --ignore-pipfile")
              # This is a lazy way of doing this, but the fact we need to lookup direct/indirect when parsing
              # the Pipfile.lock is a consequence of our decision to look at the dependency list via highest resolution
              # file analysed rather than the existing dependency list in the Dependency Submission POC.
              structured_graph_json = SharedHelpers.run_shell_command("pyenv exec pipenv graph --json-tree")
              @direct_dependencies = JSON.parse(structured_graph_json).map { |dep| dep["key"] }

              # If we were using the dependency list directly instead of maintaining a file-based subset, we would
              # only need to run this native command to get the metadata.
              flat_graph_json = SharedHelpers.run_shell_command("pyenv exec pipenv graph --json")
              @depends_on_dictionary = JSON.parse(flat_graph_json).each_with_object({}) do |dep, depends_on_map|
                depends_on_map[dep["package"]["key"]] = dep["dependencies"].map { |subdep| subdep["key"] }
              end
            end
          end
        end

        sig { void }
        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", language_version_manager.python_major_minor)
          language_version_manager.install_required_python
        end

        sig { returns(FileParser::PythonRequirementParser) }
        def python_requirement_parser
          @python_requirement_parser ||= T.let(
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            ),
            T.nilable(FileParser::PythonRequirementParser)
          )
        end

        sig { returns(LanguageVersionManager) }
        def language_version_manager
          @language_version_manager ||= T.let(
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            ),
            T.nilable(LanguageVersionManager)
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

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

              dependency = Dependency.new(
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

              T.must(pipfile).dependencies << dependency
              dependencies << dependency
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

          # TODO(brrygrdn): This should be gated by the experiment if we were going to merge this iteration
          fetch_metadata_for_lockfile

          DEPENDENCY_GROUP_KEYS.map { |h| h.fetch(:lockfile) }.each do |key|
            next unless parsed_pipfile_lock[key]

            parsed_pipfile_lock[key].each do |dep_name, details|
              version = case details
                        when String then details
                        when Hash then details["version"]
                        end
              next unless version
              next if git_or_path_requirement?(details)

              dependency = Dependency.new(
                name: dep_name,
                version: version&.gsub(/^===?/, ""),
                requirements: [],
                package_manager: "pip",
                subdependency_metadata: [{ production: key != "develop" }],
                direct_relationship: @direct_dependencies.include?(dep_name),
                metadata: {
                  depends_on: @depends_on_dictionary.fetch(dep_name, [])
                }
              )

              T.must(pipfile_lock).dependencies << dependency
              dependencies << dependency
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

        sig do
          params(obj: T.any(String, NilClass, T::Array[String], T::Hash[String, T.untyped])).returns(T.nilable(String))
        end
        def version_from_hash_or_string(obj)
          case obj
          when String then obj.strip
          when Hash then obj["version"]
          end
        end

        sig { params(req: T.any(String, T::Hash[String, T.untyped])).returns(T.any(T::Boolean, NilClass, String)) }
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
          return @pipfile_lock if defined?(@pipfile_lock)

          @pipfile_lock = T.let(dependency_files.find { |f| f.name == "Pipfile.lock" },
                                T.nilable(Dependabot::DependencyFile))

          # Set the lockfile as higher priority so we know to ignore the manifest
          # when producing a graph.
          @pipfile_lock&.tap { |f| f.priority = 1 }
        end
      end
    end
  end
end
