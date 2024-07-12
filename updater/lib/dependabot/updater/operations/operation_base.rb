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

      sig { returns(Service) }
      attr_reader :service
      sig { returns(Job) }
      attr_reader :job
      sig { returns(DependencySnapshot) }
      attr_reader :dependency_snapshot
      sig { returns(ErrorHandler) }
      attr_reader :error_handler

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
