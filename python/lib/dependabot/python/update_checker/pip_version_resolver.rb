# typed: strong
# frozen_string_literal: true

require "json"
require "toml-rb"
require "sorbet-runtime"
require "excon"
require "dependabot/registry_client"
require "dependabot/python/language_version_manager"
require "dependabot/python/name_normaliser"
require "dependabot/python/package/package_registry_finder"
require "dependabot/python/update_checker"
require "dependabot/python/update_checker/latest_version_finder"
require "dependabot/python/file_parser/python_requirement_parser"

module Dependabot
  module Python
    class UpdateChecker
      class PipVersionResolver
        extend T::Sig

        require_relative "pip_version_resolver/marker_evaluator"

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
          @marker_evaluator = T.let(nil, T.nilable(MarkerEvaluator))
          @pyproject_content = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
          @registry_json_urls = T.let(nil, T.nilable(T::Array[String]))
          @transitive_requirement_cache = T.let({}, T::Hash[String, T.nilable(String)])
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
          candidate = latest_version_finder
                      .lowest_security_fix_version(language_version: language_version_manager.python_version)
          return candidate if candidate.nil?
          return candidate if compatible_with_pinned_pyproject_dependencies?(candidate)

          nil
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

        sig { returns(MarkerEvaluator) }
        def marker_evaluator
          @marker_evaluator ||= MarkerEvaluator.new
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

            requirement_string, marker = split_requirement_and_marker(entry_obj)
            next unless marker_satisfied_for_python?(marker)
            next if requirement_string.nil? || requirement_string.empty?

            parsed = requirement_string.match(
              /\A(?<name>[A-Za-z0-9][A-Za-z0-9._\-]*)(?:\[[^\]]+\])?\s*==\s*(?<version>[^\s]+)\z/
            )
            next unless parsed

            dep_name = NameNormaliser.normalise(T.must(parsed[:name]))
            next if dep_name == NameNormaliser.normalise(dependency.name)

            [dep_name, T.must(parsed[:version])]
          end
        end

        sig { params(name: String, version: String).returns(T.nilable(String)) }
        def transitive_requirement_for(name:, version:)
          cache_key = "#{name}@#{version}"
          return @transitive_requirement_cache[cache_key] if @transitive_requirement_cache.key?(cache_key)

          response = dependency_metadata_response(name: name, version: version)
          requirement = requirement_for_target_dependency(response)

          @transitive_requirement_cache[cache_key] = requirement
        end

        sig { params(name: String, version: String).returns(T.nilable(Excon::Response)) }
        def dependency_metadata_response(name:, version:)
          registry_json_urls.each do |registry_url|
            url = "#{registry_url}#{name}/#{version}/json/"
            response = Dependabot::RegistryClient.get(url: url)
            return response if response.status == 200
          rescue Excon::Error::Timeout, Excon::Error::Socket, URI::InvalidURIError
            Dependabot.logger.warn("Failed to fetch python dependency metadata for #{name}@#{version}")
            next
          end

          nil
        end

        sig { returns(T::Array[String]) }
        def registry_json_urls
          return @registry_json_urls if @registry_json_urls

          package_registry_urls = Package::PackageRegistryFinder.new(
            dependency_files: dependency_files,
            credentials: credentials,
            dependency: dependency
          ).registry_urls

          @registry_json_urls =
            package_registry_urls
            .map { |url| url.sub(%r{/simple/?$}i, "/pypi/") }
            .uniq

          @registry_json_urls
        end

        sig { params(response: T.nilable(Excon::Response)).returns(T.nilable(String)) }
        def requirement_for_target_dependency(response)
          return nil unless response

          requires_dist = requires_dist_from_response(response)
          return nil unless requires_dist

          requires_dist.each do |requirement_string|
            requirement = parse_target_requirement(requirement_string)
            return requirement if requirement
          end

          nil
        rescue JSON::ParserError
          Dependabot.logger.warn("Failed to parse python dependency metadata JSON response")
          nil
        end

        sig { params(response: Excon::Response).returns(T.nilable(T::Array[String])) }
        def requires_dist_from_response(response)
          body = T.cast(JSON.parse(response.body), T::Hash[String, T.untyped])
          info_obj = T.cast(body["info"], T.nilable(Object))
          return nil unless info_obj.is_a?(Hash)

          requires_dist_obj = T.cast(info_obj["requires_dist"], T.nilable(Object))
          return nil unless requires_dist_obj.is_a?(Array)

          requires_dist_obj.filter_map do |entry|
            entry_obj = T.cast(entry, T.nilable(Object))
            entry_obj if entry_obj.is_a?(String)
          end
        end

        sig { params(requirement_string: String).returns(T.nilable(String)) }
        def parse_target_requirement(requirement_string)
          package_requirement, marker = split_requirement_and_marker(requirement_string)
          return nil unless marker_satisfied_for_python?(marker)
          return nil if package_requirement.nil?

          match = package_requirement.match(
            /\A(?<name>[A-Za-z0-9][A-Za-z0-9._\-]*)(?:\[[^\]]+\])?\s*(?:\((?<requirement>[^)]*)\))?\z/
          )
          return nil unless match

          return nil unless NameNormaliser.normalise(T.must(match[:name])) == NameNormaliser.normalise(dependency.name)

          match[:requirement]&.strip
        end

        sig { params(requirement_string: String).returns([T.nilable(String), T.nilable(String)]) }
        def split_requirement_and_marker(requirement_string)
          marker_evaluator.split_requirement_and_marker(requirement_string)
        end

        sig { params(marker: T.nilable(String)).returns(T::Boolean) }
        def marker_satisfied_for_python?(marker)
          return true if marker.nil? || marker.empty?
          return false unless marker.match?(/\bpython(?:_full)?_version\b/)

          marker_satisfied?(marker, language_version_manager.python_version)
        end

        sig { params(marker: String, python_version: String).returns(T::Boolean) }
        def marker_satisfied?(marker, python_version)
          marker_evaluator.marker_satisfied?(marker: marker, python_version: python_version)
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
          @pyproject_content = T.let({}, T.nilable(T::Hash[String, T.untyped]))
          T.must(@pyproject_content)
        end
      end
    end
  end
end
