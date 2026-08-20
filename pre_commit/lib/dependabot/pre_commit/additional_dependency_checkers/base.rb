# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_requirement"
require "dependabot/package/release_cooldown_options"

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
            source: Dependabot::DependencyRequirement::ObjectHash,
            credentials: T::Array[Dependabot::Credential],
            requirements: T::Array[Dependabot::DependencyRequirement],
            current_version: T.nilable(String),
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(source:, credentials:, requirements:, current_version:, cooldown_options: nil)
          @source = source
          @credentials = credentials
          @requirements = T.let(
            requirements.map { |requirement| Dependabot::DependencyRequirement.create(requirement) },
            T::Array[Dependabot::DependencyRequirement]
          )
          @current_version = current_version
          @cooldown_options = cooldown_options
        end

        # Find the latest available version for this dependency
        # Should delegate to the appropriate ecosystem UpdateChecker
        # Returns nil if no update is available or if there's an error
        sig { abstract.returns(T.nilable(String)) }
        def latest_version; end

        # Generate updated requirements for the new version
        # Should preserve the original version constraint operator (>=, ~=, etc.)
        # and update the source hash with the new original_string
        sig do
          abstract.params(latest_version: String)
                  .returns(T::Array[Dependabot::DependencyRequirement])
        end
        def updated_requirements(latest_version); end

        private

        sig { returns(Dependabot::DependencyRequirement::ObjectHash) }
        attr_reader :source

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        attr_reader :requirements

        sig { returns(T.nilable(String)) }
        attr_reader :current_version

        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options

        sig { returns(T.nilable(String)) }
        def package_name
          source_string(source, "package_name")
        end

        sig do
          params(requirement: T.nilable(Dependabot::DependencyRequirement))
            .returns(T.nilable(String))
        end
        def requirement_string(requirement)
          requirement&.requirement_string
        end

        sig do
          params(
            requirement: Dependabot::DependencyRequirement
          ).returns(T.nilable(Dependabot::DependencyRequirement::ObjectHash))
        end
        def additional_dependency_source(requirement)
          details = requirement.source_hash
          return unless details
          return unless source_string(details, "type") == "additional_dependency"

          details
        end

        sig do
          params(
            requirement: Dependabot::DependencyRequirement,
            new_requirement: T.nilable(String),
            original_string: String
          ).returns(Dependabot::DependencyRequirement)
        end
        def build_requirement_entry(requirement, new_requirement:, original_string:)
          original_source = T.must(additional_dependency_source(requirement))
          new_source = source_with_value(original_source, "original_string", original_string)

          Dependabot::DependencyRequirement.create(
            requirement.merge(requirement: new_requirement, source: new_source)
          )
        end

        sig do
          params(
            details: Dependabot::DependencyRequirement::ObjectHash,
            key: String
          ).returns(T.nilable(String))
        end
        def source_string(details, key)
          value = details.key?(key.to_sym) ? details[key.to_sym] : details[key]
          return if value.nil?
          return value if value.is_a?(String)

          raise TypeError, "source #{key} must be a string or nil"
        end

        sig do
          params(
            details: Dependabot::DependencyRequirement::ObjectHash,
            key: String,
            value: Object
          ).returns(Dependabot::DependencyRequirement::ObjectHash)
        end
        def source_with_value(details, key, value)
          updated = details.dup
          actual_key = if details.key?(key.to_sym)
                         key.to_sym
                       elsif details.key?(key)
                         key
                       elsif details.keys.any?(Symbol)
                         key.to_sym
                       else
                         key
                       end
          updated[actual_key] = value
          updated
        end
      end
    end
  end
end
