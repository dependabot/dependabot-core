# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      # Abstract base class for language-specific additional_dependency update checkers.
      # Each language implementation should inherit from this class and implement
      # the abstract methods.
      #
      # The checker is responsible for:
      # 1. Finding the latest available version from the language's registry (PyPI, npm, etc.)
      # 2. Generating updated requirements that preserve the original version constraint operators
      #
      # Example implementation for a new language:
      #
      #   class MyLanguage < Base
      #     def latest_version
      #       # Delegate to ecosystem's UpdateChecker
      #       ecosystem_checker = Dependabot::UpdateCheckers
      #         .for_package_manager("my_pm")
      #         .new(dependency: build_ecosystem_dependency, ...)
      #       ecosystem_checker.latest_version&.to_s
      #     end
      #
      #     def updated_requirements(latest_version)
      #       # Build updated requirements preserving operators
      #     end
      #   end
      #
      #   AdditionalDependencyCheckers.register("my_language", MyLanguage)
      #
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

        # Find the latest available version for this dependency
        # Should delegate to the appropriate ecosystem UpdateChecker
        # Returns nil if no update is available or if there's an error
        sig { abstract.returns(T.nilable(String)) }
        def latest_version; end

        # Generate updated requirements for the new version
        # Should preserve the original version constraint operator (>=, ~=, etc.)
        # and update the source hash with the new original_string
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
