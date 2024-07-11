# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_change_builder"
require "dependabot/updater/dependency_group_change_batch"
require "dependabot/workspace"

module Dependabot
  class Updater
    class OperationBase
      extend T::Sig
      extend T::Helpers

      sig do
        params(
          service: Service,
          job: Job,
          dependency_snapshot: DependencySnapshot,
          error_handler: ErrorHandler
        ).void
      end
      def initialize(service:, job:, dependency_snapshot:, error_handler:)
        @service = service
        @job = job
        @dependency_snapshot = dependency_snapshot
        @error_handler = error_handler
      end

      sig { returns(T::Array[String]) }
      def job_dependencies
        if @job.dependencies.nil?
          throw ArgumentError, "Dependencies on the job are required"
        else
          T.must(@job.dependencies)
        end
      end

      abstract!
      sig { abstract.params(job: Job).returns(T::Boolean) }
      def self.applies_to?(job:); end

      sig { abstract.returns(Symbol) }
      def self.tag_name; end

      sig { abstract.void }
      def perform; end
    end
  end
end
