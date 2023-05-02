# frozen_string_literal: true

require "dependabot/updater/operations/create_security_update_pull_request"
require "dependabot/updater/operations/group_update_all_versions"
require "dependabot/updater/operations/refresh_group_update_pull_request"
require "dependabot/updater/operations/refresh_security_update_pull_request"
require "dependabot/updater/operations/refresh_version_update_pull_request"
require "dependabot/updater/operations/update_all_versions"

# This module is responsible for determining which Operation a Job is requesting
# the Updater to perform.
#
# The design goal for this module is to make these classes easy to understand,
# maintain and extend so we can eventually support community-contributed
# alternatives or ecosystem-specific implementations.
#
# Consider the following guidelines when working on Operation classes:
#
# - Operations *should not have optional parameters*, prefer to create a new
#   class instead of adding branching to an existing one.
#
# - Operations should prefer to share logic by composition, there is no base
#   class. We want to avoid implicit or indirect behaviour as much as possible.
#
module Dependabot
  class Updater
    module Operations
      # We check if each operation ::applies_to? a given job, returning the first
      # that does, so these Operations should be ordered so that those with most
      # specific preconditions go before those with more permissive checks.
      OPERATIONS = [
        CreateSecurityUpdatePullRequest,
        RefreshSecurityUpdatePullRequest,
        RefreshGroupUpdatePullRequest,
        RefreshVersionUpdatePullRequest,
        GroupUpdateAllVersions,
        UpdateAllVersions
      ]

      def self.class_for(job:)
        # Let's not bother generating the string if debug is disabled
        if Dependabot.logger.debug?
          update_type = job.security_updates_only? ? "security" : "version"
          update_verb = job.updating_a_pull_request? ? "refresh" : "create"
          update_deps = job.dependencies&.any? ? job.dependencies.count : "all"

          Dependabot.logger.debug(
            "Finding operation for a #{update_type} to #{update_verb} a Pull Request for #{update_deps} dependencies"
          )
        end

        raise ArgumentError, "Expected Dependabot::Job, got #{job.class}" unless job.is_a?(Dependabot::Job)

        OPERATIONS.find { |op| op.applies_to?(job: job) }
      end
    end
  end
end
