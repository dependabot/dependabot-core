# frozen_string_literal: true

require "dependabot/update_checkers/java_script/npm_and_yarn"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn
        class SubdependencyVersionResolver
          def initialize(dependency:, credentials:, dependency_files:,
                         ignored_versions:)
            @dependency       = dependency
            @credentials      = credentials
            @dependency_files = dependency_files
            @ignored_versions = ignored_versions
          end

          def latest_resolvable_version
            # TODO: Update subdependencies for npm lockfiles
            return if package_locks.any? || shrinkwraps.any?

            # TODO: Write me!
            nil
          end

          private

          attr_reader :dependency, :credentials, :dependency_files,
                      :ignored_versions

          def package_locks
            @package_locks ||=
              dependency_files.
              select { |f| f.name.end_with?("package-lock.json") }
          end

          def yarn_locks
            @yarn_locks ||=
              dependency_files.
              select { |f| f.name.end_with?("yarn.lock") }
          end

          def shrinkwraps
            @shrinkwraps ||=
              dependency_files.
              select { |f| f.name.end_with?("npm-shrinkwrap.json") }
          end
        end
      end
    end
  end
end
