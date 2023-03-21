# frozen_string_literal: true

module Dependabot
  class Updater
    module Operations
      class GroupUpdateAllVersions
        def self.applies_to?(job:)
          return false if job.security_updates_only?
          return false if job.updating_a_pull_request?
          return false if job.dependencies&.any?

          Dependabot::Experiments.enabled?(:grouped_updates_prototype)
        end

        def initialize(service:, job:, dependency_snapshot:, error_handler:)
          @service = service
          @job = job
          @dependency_snapshot = dependency_snapshot
          @error_handler = error_handler
        end

        def perform
          Dependabot.logger.info("[Experimental] Starting grouped update job for #{job.source.repo}")
          # We should log the rule being executed, let's just hard-code wildcard for now
          # since the prototype makes best-effort to do everything in one pass.
          Dependabot.logger.info("Starting update group for '*'")
          Dependabot.logger.info("NYI!")
        end

        private

        attr_reader :job
      end
    end
  end
end
