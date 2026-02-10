# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      class Base
        extend T::Sig
        extend T::Helpers

        abstract!

        sig do
          params(
            source: T::Hash[Symbol, T.untyped],
            credentials: T::Array[Dependabot::Credential],
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            current_version: T.nilable(String)
          ).void
        end
        def initialize(source:, credentials:, requirements:, current_version:)
          @source = source
          @credentials = credentials
          @requirements = requirements
          @current_version = current_version
        end

        sig { abstract.returns(T.nilable(String)) }
        def latest_version; end

        sig { abstract.params(latest_version: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements(latest_version); end

        private

        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :source

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :requirements

        sig { returns(T.nilable(String)) }
        attr_reader :current_version

        sig { returns(T.nilable(String)) }
        def package_name
          source[:package_name]&.to_s
        end
      end
    end
  end
end
