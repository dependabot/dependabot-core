# typed: strict
# frozen_string_literal: true

require "excon"
require "toml-rb"
require "open3"
require "uri"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/python/file_parser"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/file_updater/pyproject_preparer"
require "dependabot/python/update_checker"
require "dependabot/python/version"
require "dependabot/python/requirement"
require "dependabot/python/native_helpers"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"
require "dependabot/python/language_version_manager"

module Dependabot
  module Python
    class UpdateChecker
      # This class does version resolution for PDM pyproject.toml files.
      class PdmVersionResolver
        extend T::Sig

        GIT_REFERENCE_NOT_FOUND_REGEX = /
          (Failed\sto\scheckout
          (?<tag>.+?)
          (?<url>.+?)\.git\sat\s'(?<tag>.+?)'
          |
          Failed\sto\sclone
          (?<url>.+?)\.git\sat\s'(?<tag>.+?)',
          verify\sref\sexists\son\sremote)
        /x
        GIT_DEPENDENCY_UNREACHABLE_REGEX = /
          \s+Failed\sto\sclone
          \s+(?<url>.+?),
          \s+check\syour\sgit\sconfiguration
        /mx

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            repo_contents_path: T.nilable(String)
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:, repo_contents_path:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @repo_contents_path = repo_contents_path
          @resolvable = T.let({}, T::Hash[String, T::Boolean])
          @latest_resolvable_version_string = T.let({}, T::Hash[T.nilable(String), T.nilable(String)])
          @language_version_manager = T.let(nil, T.nilable(Dependabot::Python::LanguageVersionManager))
          @python_requirement_parser = T.let(nil, T.nilable(Dependabot::Python::FileParser::PythonRequirementParser))
          @pyproject = T.let(nil, T.nilable(Dependabot::DependencyFile))
        end

        sig { params(requirement: T.nilable(String)).returns(T.nilable(Python::Version)) }
        def latest_resolvable_version(requirement: nil)
          version_string =
            fetch_latest_resolvable_version_string(requirement: requirement)

          version_string.nil? ? nil : Python::Version.new(version_string)
        end

        sig { params(version: String).returns(T::Boolean) }
        def resolvable?(version:)
          return T.must(@resolvable[version]) if @resolvable.key?(version)

          @resolvable[version] = if fetch_latest_resolvable_version_string(requirement: "==#{version}")
                                   true
                                 else
                                   false
                                 end
        rescue SharedHelpers::HelperSubprocessFailed => e
          raise unless e.message.include?("Resolution failed") ||
                       e.message.include?("No solution found")

          @resolvable[version] = false
        end

        private

        sig { params(requirement: T.nilable(String)).returns(T.nilable(String)) }
        def fetch_latest_resolvable_version_string(requirement:)
          return @latest_resolvable_version_string[requirement] if @latest_resolvable_version_string.key?(requirement)

          @latest_resolvable_version_string[requirement] ||=
            SharedHelpers.in_a_temporary_directory do
              SharedHelpers.with_git_configured(credentials: credentials) do
                write_temporary_dependency_files(updated_req: requirement)

                language_version_manager.install_required_python
                # Shell out to PDM, which handles everything for us.
                run_pdm_update_command

                updated_lockfile = File.read("pdm.lock")
                parsed_lockfile = TomlRB.parse(updated_lockfile)

                fetch_version_from_parsed_lockfile(parsed_lockfile)
              rescue SharedHelpers::HelperSubprocessFailed => e
                handle_pdm_errors(e)
                nil
              end
            end
        end

        sig { params(updated_lockfile: T.untyped).returns(T.nilable(String)) }
        def fetch_version_from_parsed_lockfile(updated_lockfile)
          # PDM lock file structure has packages under ["package"] key
          version =
            updated_lockfile.fetch("package", [])
                            .find { |d| d["name"] && normalise(d["name"]) == dependency.name }
                            &.fetch("version")

          return version unless version.nil? && dependency.top_level?

          raise "No version in lockfile!"
        end

        sig { params(error: T.untyped).void }
        def handle_pdm_errors(error)
          if error.message.gsub(/\s/, "").match?(GIT_REFERENCE_NOT_FOUND_REGEX)
            message = error.message.gsub(/\s/, "")
            match = message.match(GIT_REFERENCE_NOT_FOUND_REGEX)
            name = if (url = match.named_captures.fetch("url"))
                     File.basename(T.must(URI.parse(url).path))
                   else
                     message.match(GIT_REFERENCE_NOT_FOUND_REGEX)
                            .named_captures.fetch("name")
                   end
            raise GitDependencyReferenceNotFound, name
          end

          if error.message.match?(GIT_DEPENDENCY_UNREACHABLE_REGEX)
            url = error.message.match(GIT_DEPENDENCY_UNREACHABLE_REGEX)
                       .named_captures.fetch("url")
            raise GitDependenciesNotReachable, url
          end

          raise unless error.message.include?("Resolution failed") ||
                       error.message.include?("No solution found") ||
                       error.message.include?("not found")

          nil
        end

        sig { void }
        def run_pdm_update_command
          Dependabot.logger.info("Checking update for #{dependency.name}")
          command = "pyenv exec pdm --non-interactive update --no-sync --update-reuse #{dependency.name}"
          if dependency.requirements.any?
            groups = T.let(T.must(dependency.requirements.first)[:groups], T::Array[String])
            command << " --group #{groups.first}" unless groups.empty?
          end
          fingerprint = command.sub(dependency.name, "<dependency_name>")

          SharedHelpers.run_shell_command(
            command,
            fingerprint: fingerprint
          )
        end

        sig { params(updated_req: T.nilable(String)).void }
        def write_temporary_dependency_files(updated_req:)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          # Update the pyproject.toml with the new requirement if provided
          return unless updated_req && pyproject

          update_pyproject_requirement(updated_req)
        end

        sig { params(updated_req: String).void }
        def update_pyproject_requirement(updated_req)
          content = T.must(pyproject).content
          parsed_content = TomlRB.parse(content)
          group = (T.must(dependency.requirements.first)[:groups].first if dependency.requirements.any?)

          # Update dependencies in the appropriate section
          if group.nil? && parsed_content.dig("project", "dependencies")
            update_pep621_dependencies!(parsed_content, updated_req)
          end
          if parsed_content.dig("tool", "pdm", "dev-dependencies", group)
            update_pdm_dev_dependencies!(parsed_content, group, updated_req)
          end
          update_dependency_group!(parsed_content, group, updated_req) if parsed_content.dig("dependency-groups", group)

          File.write("pyproject.toml", TomlRB.dump(parsed_content))
        end

        sig { params(parsed_content: T.untyped, updated_req: String).void }
        def update_pep621_dependencies!(parsed_content, updated_req)
          dependencies = parsed_content["project"]["dependencies"]
          update_dependency_array!(dependencies, updated_req)
        end

        sig { params(parsed_content: T.untyped, group: String, updated_req: String).void }
        def update_pdm_dev_dependencies!(parsed_content, group, updated_req)
          dependencies = parsed_content.dig("tool", "pdm", "dev-dependencies", group)
          update_dependency_array!(dependencies, updated_req)
        end

        sig { params(parsed_content: T.untyped, group: String, updated_req: String).void }
        def update_dependency_group!(parsed_content, group, updated_req)
          dependencies = parsed_content.dig("dependency-groups", group)
          update_dependency_array!(dependencies, updated_req)
        end

        sig { params(dependencies: T.untyped, updated_req: String).void }
        def update_dependency_array!(dependencies, updated_req)
          return unless dependencies.is_a?(Array)

          dependencies.map! do |dep|
            unless dep.is_a?(String) && normalise(dep).start_with?(normalise(dependency.name)) && !dep.include?("@")
              return dep
            end

            reqs = dep.split(";", 1)
            result = "#{dependency.name}#{updated_req}"
            result << " ;#{reqs.last}" if reqs.length > 1
            result
          end
        end

        sig { returns(Dependabot::Python::LanguageVersionManager) }
        def language_version_manager
          @language_version_manager ||= LanguageVersionManager.new(
            python_requirement_parser: python_requirement_parser
          )
        end

        sig { returns(Dependabot::Python::FileParser::PythonRequirementParser) }
        def python_requirement_parser
          @python_requirement_parser ||= FileParser::PythonRequirementParser.new(
            dependency_files: dependency_files
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pyproject
          @pyproject ||= dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
        end
      end
    end
  end
end
