# typed: strong
# frozen_string_literal: true

require "json"
require "toml-rb"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/python/language_version_manager"
require "dependabot/python/name_normaliser"
require "dependabot/python/update_checker"
require "dependabot/python/update_checker/latest_version_finder"
require "dependabot/python/file_parser/python_requirement_parser"

module Dependabot
  module Python
    class UpdateChecker
      class PipVersionResolver
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            update_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          update_cooldown: nil,
          raise_on_ignored: false
        )
          @dependency          = T.let(dependency, Dependabot::Dependency)
          @dependency_files    = T.let(dependency_files, T::Array[Dependabot::DependencyFile])
          @credentials         = T.let(credentials, T::Array[Dependabot::Credential])
          @ignored_versions    = T.let(ignored_versions, T::Array[String])
          @security_advisories = T.let(security_advisories, T::Array[Dependabot::SecurityAdvisory])
          @update_cooldown = T.let(update_cooldown, T.nilable(Dependabot::Package::ReleaseCooldownOptions))
          @raise_on_ignored = T.let(raise_on_ignored, T::Boolean)
          @latest_version_finder = T.let(nil, T.nilable(LatestVersionFinder))
          @python_requirement_parser = T.let(nil, T.nilable(FileParser::PythonRequirementParser))
          @language_version_manager = T.let(nil, T.nilable(LanguageVersionManager))
          @pyproject_content = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_resolvable_version
          candidate = latest_version_finder.latest_version(language_version: language_version_manager.python_version)
          return candidate if candidate.nil?
          return candidate if compatible_with_pinned_pyproject_dependencies?(candidate)

          nil
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_resolvable_version_with_no_unlock
          latest_version_finder
            .latest_version_with_no_unlock(language_version: language_version_manager.python_version)
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def lowest_resolvable_security_fix_version
          latest_version_finder
            .lowest_security_fix_version(language_version: language_version_manager.python_version)
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(LatestVersionFinder) }
        def latest_version_finder
          @latest_version_finder ||= LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: @raise_on_ignored,
            cooldown_options: @update_cooldown,
            security_advisories: security_advisories
          )
          @latest_version_finder
        end

        sig { returns(FileParser::PythonRequirementParser) }
        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        sig { returns(LanguageVersionManager) }
        def language_version_manager
          @language_version_manager ||=
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            )
        end

        sig { params(candidate: Dependabot::Version).returns(T::Boolean) }
        def compatible_with_pinned_pyproject_dependencies?(candidate)
          return true unless constraints_dependency?
          return true if pinned_pyproject_dependencies.none?

          pinned_pyproject_dependencies.all? do |name, version|
            requirement = transitive_requirement_for(name: name, version: version)
            next true unless requirement

            Python::Requirement.new(requirement).satisfied_by?(candidate)
          rescue Gem::Requirement::BadRequirementError
            # If metadata has an unsupported requirement format, don't block updates.
            true
          end
        end

        sig { returns(T::Boolean) }
        def constraints_dependency?
          dependency.requirements.any? do |req|
            file = T.cast(req.fetch(:file), String)
            File.basename(file).start_with?("constraints")
          end
        end

        sig { returns(T::Array[[String, String]]) }
        def pinned_pyproject_dependencies
          project_obj = T.cast(pyproject_content["project"], T.nilable(Object))
          return [] unless project_obj.is_a?(Hash)

          project_hash = project_obj
          dependencies_obj = T.cast(project_hash["dependencies"], T.nilable(Object))
          return [] unless dependencies_obj.is_a?(Array)

          dependencies_obj.filter_map do |entry|
            entry_obj = T.cast(entry, T.nilable(Object))
            next unless entry_obj.is_a?(String)

            # Strip environment markers, e.g. '; python_version > "3.10"'
            requirement_string = entry_obj.split(";").first&.strip
            next if requirement_string.nil? || requirement_string.empty?

            parsed = requirement_string.match(/\A(?<name>[A-Za-z0-9][A-Za-z0-9._\-]*)\s*==\s*(?<version>[^\s]+)\z/)
            next unless parsed

            dep_name = NameNormaliser.normalise(T.must(parsed[:name]))
            next if dep_name == NameNormaliser.normalise(dependency.name)

            [dep_name, T.must(parsed[:version])]
          end
        end

        sig { params(name: String, version: String).returns(T.nilable(String)) }
        def transitive_requirement_for(name:, version:)
          url = "https://pypi.org/pypi/#{name}/#{version}/json/"
          response = Dependabot::RegistryClient.get(url: url)
          return nil unless response.status == 200

          body = T.cast(JSON.parse(response.body), T::Hash[String, T.untyped])
          info_obj = T.cast(body["info"], T.nilable(Object))
          return nil unless info_obj.is_a?(Hash)

          info_hash = info_obj
          requires_dist_obj = T.cast(info_hash["requires_dist"], T.nilable(Object))
          return nil unless requires_dist_obj.is_a?(Array)

          requires_dist_obj.each do |dist_requirement|
            dist_requirement_obj = T.cast(dist_requirement, T.nilable(Object))
            next unless dist_requirement_obj.is_a?(String)

            # Example: "urllib3 (<1.27,>=1.25.4); python_version >= '3.10'"
            normalized = dist_requirement_obj.split(";").first&.strip
            next if normalized.nil?

            match = normalized.match(/\A(?<name>[A-Za-z0-9][A-Za-z0-9._\-]*)\s*(?:\((?<requirement>[^)]*)\))?\z/)
            next unless match

            next unless NameNormaliser.normalise(T.must(match[:name])) == NameNormaliser.normalise(dependency.name)

            return match[:requirement]&.strip
          end

          nil
        rescue StandardError
          nil
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def pyproject_content
          return @pyproject_content if @pyproject_content

          pyproject = dependency_files.find { |file| file.name == "pyproject.toml" }
          @pyproject_content =
            if pyproject
              T.let(TomlRB.parse(pyproject.content), T.nilable(T::Hash[String, T.untyped]))
            else
              T.let({}, T.nilable(T::Hash[String, T.untyped]))
            end

          T.must(@pyproject_content)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          {}
        end
      end
    end
  end
end
