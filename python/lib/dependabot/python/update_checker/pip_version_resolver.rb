# frozen_string_literal: true

require "dependabot/python/helpers"
require "dependabot/python/update_checker"
require "dependabot/python/update_checker/latest_version_finder"
require "dependabot/python/file_parser/python_requirement_parser"

module Dependabot
  module Python
    class UpdateChecker
      class PipVersionResolver
        include Helpers

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, raise_on_ignored: false,
                       security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
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
            raise_on_ignored: @raise_on_ignored,
            security_advisories: security_advisories
          )
        end
      end
    end
  end
end
