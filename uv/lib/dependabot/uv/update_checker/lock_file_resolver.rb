# typed: true
# frozen_string_literal: true

require "dependabot/uv/version"
require "dependabot/uv/requirement"
require "dependabot/uv/update_checker"

module Dependabot
  module Uv
    class UpdateChecker
      class LockFileResolver
        def initialize(dependency:, dependency_files:, credentials:, repo_contents_path: nil)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @repo_contents_path = repo_contents_path
        end

        def latest_resolvable_version(requirement:)
          return nil unless requirement

          req = Uv::Requirement.new(requirement)

          # Get the version from the dependency if available
          version_from_dependency = dependency.version && Uv::Version.new(dependency.version)
          return version_from_dependency if version_from_dependency && req.satisfied_by?(version_from_dependency)

          nil
        end

        def resolvable?(*)
          true
        end

        def lowest_resolvable_security_fix_version
          nil
        end

        private

        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :credentials
        attr_reader :repo_contents_path
      end
    end
  end
end
