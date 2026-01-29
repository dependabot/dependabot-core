# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    module MessageComponents
      # Base class for message component builders
      # Provides common initialization and interface for all message components
      class Base
        extend T::Sig

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            source: Dependabot::Source,
            credentials: T::Array[Dependabot::Credential],
            options: T::Hash[Symbol, T.untyped]
          ).void
        end
        def initialize(dependencies:, source:, credentials:, **options)
          @dependencies = dependencies
          @source = source
          @credentials = credentials
          @options = options
        end

        sig { returns(String) }
        def build
          raise NotImplementedError, "Subclasses must implement #build"
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(Dependabot::Source) }
        attr_reader :source

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :options
      end
    end
  end
end
