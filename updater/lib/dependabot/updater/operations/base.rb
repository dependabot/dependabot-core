# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Updater
    module Operations
      class Base
        extend T::Sig
        extend T::Helpers

        abstract!

        sig { returns(Dependabot::Service) }
        attr_reader :service

        sig { returns(Dependabot::DependencySnapshot) }
        attr_reader :dependency_snapshot

        sig { returns(Dependabot::Job) }
        attr_reader :job

        sig { returns(Dependabot::Updater::ErrorHandler) }
        attr_reader :error_handler

        sig do
          params(
            service: Dependabot::Service,
            job: Dependabot::Job,
            dependency_snapshot: Dependabot::DependencySnapshot,
            error_handler: Dependabot::Updater::ErrorHandler
          )
            .void
        end
        def initialize(service, job, dependency_snapshot, error_handler)
          @service = service
          @dependency_snapshot = dependency_snapshot
          @job = job
          @error_handler = error_handler
        end
      end
    end
  end
end
