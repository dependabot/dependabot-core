# frozen_string_literal: true

module Dependabot
  class Updater
    module Operations
      class UpdateAllVersions
        attr_reader :job, :updater

        def self.applies_to?(job:)
          return false if job.security_updates_only?
          return false if job.updating_a_pull_request?
          return false if job.dependencies.any?

          true
        end

        def initialize(job:, service:, dependency_snapshot:)
          @job = job
          @service = service
          @dependency_snapshot = dependency_snapshot
        end

        def perform; end
      end
    end
  end
end
