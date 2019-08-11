# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/puppet/requirement"

module Dependabot
  module Puppet
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      require_relative "update_checker/latest_version_finder"

      def latest_version
        @latest_version ||=
          latest_version_finder.
          latest_version
      end

      def latest_resolvable_version
        latest_version
      end

      def latest_resolvable_version_with_no_unlock
        @latest_resolvable_version_with_no_unlock ||=
          latest_version_finder.
          latest_version_with_no_unlock
      end

      def lowest_resolvable_security_fix_version
        raise "Dependency not vulnerable!" unless vulnerable?

        if defined?(@lowest_resolvable_security_fix_version)
          return @lowest_resolvable_security_fix_version
        end

        @lowest_resolvable_security_fix_version =
          latest_version_finder.
          lowest_security_fix_version
      end

      def updated_requirements
        dependency.requirements.map do |req|
          req.merge(requirement: latest_version)
        end
      end

      private

      def latest_version_resolvable_with_full_unlock?
        # Multi-dependency updates not supported
        false
      end

      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def latest_version_finder
        @latest_version_finder ||= LatestVersionFinder.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          security_advisories: security_advisories
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("puppet", Dependabot::Puppet::UpdateChecker)
