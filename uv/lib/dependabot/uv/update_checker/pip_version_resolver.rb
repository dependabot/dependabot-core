# typed: true
# frozen_string_literal: true

require "dependabot/uv/language_version_manager"
require "dependabot/uv/update_checker"
require "dependabot/uv/update_checker/latest_version_finder"
require "dependabot/uv/file_parser/python_requirement_parser"

module Dependabot
  module Uv
    class UpdateChecker
      class PipVersionResolver
        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, update_cooldown: nil, raise_on_ignored: false,
                       security_advisories:)
          @dependency = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @update_cooldown = update_cooldown
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
        end

        def latest_resolvable_version
          latest_version_finder.latest_version(language_version: language_version_manager.python_version)
        end

        def latest_resolvable_version_with_no_unlock
          latest_version_finder
            .latest_version_with_no_unlock(language_version: language_version_manager.python_version)
        end

        def lowest_resolvable_security_fix_version
          latest_version_finder
            .lowest_security_fix_version(language_version: language_version_manager.python_version)
        end

        private

        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :credentials
        attr_reader :ignored_versions
        attr_reader :security_advisories

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
        end

        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        def language_version_manager
          @language_version_manager ||=
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            )
        end
      end
    end
  end
end
