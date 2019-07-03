# frozen_string_literal: true

require "dependabot/python/update_checker"
require "dependabot/python/update_checker/latest_version_finder"
require "dependabot/python/file_parser/python_requirement_parser"

module Dependabot
  module Python
    class UpdateChecker
      class PipVersionResolver
        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
        end

        def latest_resolvable_version
          latest_version_finder.latest_version(python_version: python_version)
        end

        def latest_resolvable_version_with_no_unlock
          latest_version_finder.
            latest_version_with_no_unlock(python_version: python_version)
        end

        def lowest_resolvable_security_fix_version
          latest_version_finder.
            lowest_security_fix_version(python_version: python_version)
        end

        private

        attr_reader :dependency, :dependency_files, :credentials,
                    :ignored_versions, :security_advisories

        def latest_version_finder
          @latest_version_finder ||= LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories
          )
        end

        def python_version
          @python_version ||=
            user_specified_python_version ||
            python_version_matching_imputed_requirements ||
            PythonVersions::PRE_INSTALLED_PYTHON_VERSIONS.first
        end

        def user_specified_python_version
          return unless python_requirement_parser.user_specified_requirement

          user_specified_requirement =
            Dependabot::Python::Requirement.new(
              python_requirement_parser.user_specified_requirement
            )
          python_version_matching([user_specified_requirement])
        end

        def python_version_matching_imputed_requirements
          compiled_file_python_requirement_markers =
            python_requirement_parser.imputed_requirements.map do |r|
              Dependabot::Python::Requirement.new(r)
            end
          python_version_matching(compiled_file_python_requirement_markers)
        end

        def python_version_matching(requirements)
          PythonVersions::SUPPORTED_VERSIONS_TO_ITERATE.find do |version_string|
            version = Python::Version.new(version_string)
            requirements.all? { |req| req.satisfied_by?(version) }
          end
        end

        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.
            new(dependency_files: dependency_files)
        end
      end
    end
  end
end
