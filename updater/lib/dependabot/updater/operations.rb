# frozen_string_literal: true

require "dependabot/updater/operations/group_update_all_versions"
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
        GroupUpdateAllVersions,
        UpdateAllVersions
      ]

      def self.class_for(job:)
        raise ArgumentError, "Expected Dependabot::Job, got #{job.class}" unless job.is_a?(Dependabot::Job)

        OPERATIONS.find { |op| op.applies_to?(job: job) }
      end
    end
  end
end
