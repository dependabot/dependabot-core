# typed: true
# frozen_string_literal: true

module Dependabot
  class Updater
    module Operations
      class Operation
        extend T::Sig
        extend T::Helpers
        abstract!

        module ClassMethods
          extend T::Sig
          extend T::Helpers
          abstract!

          sig { abstract.params(job: Dependabot::Job).void }
          def applies_to?(job:); end

          sig { abstract.returns(Symbol) }
          def tag_name; end
        end

        extend ClassMethods

        sig do
          abstract.params(
            service: Dependabot::Service,
            job: Dependabot::Job,
            dependency_snapshot: Dependabot::DependencySnapshot,
            error_handler: ErrorHandler
          ).void
        end
        def initialize(service:, job:, dependency_snapshot:, error_handler:); end

        sig { abstract.returns(Dependabot::DependencyChange) }
        def perform; end
      end
    end
  end
end
