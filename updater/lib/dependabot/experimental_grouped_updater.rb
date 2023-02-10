# frozen_string_literal: true

# This class is a variation on the Strangler Pattern which the Updater#run
# method delegates to when the `prototype_grouped_updates` experiment is
# enabled.
#
# The goal of this is to allow us to use the existing Updater code that is
# shared but re-implement the methods that need to change _without_ jeopardising
# the Updater implementation for current users.
#
# This class is not expected to be long-lived once we have a better idea of how
# to pull apart the existing Updater into Single- and Grouped-strategy classes.
module Dependabot
  # Let's use SimpleDelegator so this class behaves like Dependabot::Updater
  # unless we override it.
  class ExperimentalGroupedUpdater < SimpleDelegator
    def run_grouped
      raise Dependabot::NotImplemented, "Grouped updates do not currently support rebasing." if job.updating_a_pull_request?

      # Nothing new implemented yet, let's just shake loose the Dependabot::Updater tests
      # which relate to top-level error handling and update/rebase jobs
      run_fresh
    end
    alias run run_grouped

    private

    # We should allow the rescue in Dependabot::Updater#run to handle errors and avoid trapping them ourselves in case
    # it results in deviating from shared behaviour. This is a safety-catch to stop that happening by accident and fail
    # tests if we override something without thinking carefully about how it should raise.
    def handle_dependabot_error(_error:, _dependency:)
      raise NoMethodError, "#{__method__} is not implemented by the delegator, call __getobj__.#{__method__} instead."
    end
  end
end
