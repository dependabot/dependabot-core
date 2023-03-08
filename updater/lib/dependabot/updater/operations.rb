# frozen_string_literal: true

# This module is responsible for determining which Operation a Job is requesting
# the Updater to perform.
#
# The design goal for this module is to make these classes easy to understand,
# maintain and extend so we can eventually support community-contributed
# alternatives or ecosystem-specific implementations.
#
# Consider the following guidelines when working on Operation classes:
#
# - Operations act on the principal of least knowledge prefering to cherry pick
#   arguments from the Dependabot::Job so their contract is explicit.
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
      def self.operation_for(_job:)
        nil
      end
    end
  end
end
