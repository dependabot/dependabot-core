# frozen_string_literal: true

require "excon"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/puppet/requirement"

module Dependabot
  module Puppet
    # Update checkers check whether a given dependency is up-to-date. If it
    # isn't, they augment it with details of the version to update to.
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      # The latest version of the dependency, ignoring resolvability. This is
      # used to short-circuit update checking when the dependency is already
      # at the latest version (since checking resolvability is typically slow)
      def latest_version
        @latest_version ||= get_latest_version
      end

      # The latest version of the dependency that will still allow the full
      # dependency set to resolve.
      def latest_resolvable_version
        latest_version
      end

      # The latest version of the dependency that satisfies the dependency's
      # current version constraints and will still allow the full dependency
      # set to resolve.
      def latest_resolvable_version_with_no_unlock
        # not supported
        nil
      end

      # An updated set of requirements for the dependency that should replace
      # the existing requirements in the manifest file. Used by the file updater
      # class when updating the manifest file.
      def updated_requirements
        dependency.requirements.map do |req|
          req.merge(requirement: latest_version)
        end
      end

      private

      # A boolean for whether the latest version can be resolved if all other
      # dependencies are unlocked in the manifest file. Can be set to always
      # return false if multi-dependency updates aren't yet supported
      def latest_version_resolvable_with_full_unlock?
        # not supported
        false
      end

      # An updated set of dependencies after a full unlock and update has taken
      # place. Not required if latest_version_resolvable_with_full_unlock?
      # always returns false
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      def get_latest_version
        begin
          response = Excon.get(
            "https://forgeapi.puppet.com/v3/modules/#{dependency.name}?exclude_fields=readme,license",
            idempotent: true,
            **SharedHelpers.excon_defaults
          )
          j = JSON.parse(response.body)
          Dependabot::Puppet::Version.new(j['current_release']['version'])
        rescue JSON::ParserError, Excon::Error::Timeout
          nil
        end
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("puppet", Dependabot::Puppet::UpdateChecker)

# "https://forgeapi.puppet.com/v3/modules/puppetlabs/dsc?exclude_fields=readme,license"
