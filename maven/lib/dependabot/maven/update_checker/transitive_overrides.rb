# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_requirement"
require "dependabot/maven/update_checker"

module Dependabot
  module Maven
    class UpdateChecker
      # Rules for keeping transitive overrides (tagged by the file parser) out of version updates.
      module TransitiveOverrides
        extend T::Sig

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T::Boolean) }
        def self.override?(requirement)
          requirement.metadata_boolean("transitive_override") == true
        end

        # The file updater rewrites every XML entry that matches a declaration's file, literal version,
        # packaging type, scope (ignored for plugins) and classifier. A declaration that matches a kept
        # override that way can't change on its own, so it's held too.
        sig do
          params(
            requirement: Dependabot::DependencyRequirement,
            requirements: T::Array[Dependabot::DependencyRequirement]
          ).returns(T::Boolean)
        end
        def self.rewrites_an_override?(requirement, requirements)
          return false if override?(requirement) || property?(requirement)

          requirements.any? { |other| override?(other) && rewrites?(requirement, other) }
        end

        # Outside a security update an override follows a version property only when a declaration
        # also uses it. A property only overrides use is never raised, so it can't drive an update.
        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
            security_update: T::Boolean,
            dependencies: T.proc.returns(T::Array[Dependabot::Dependency])
          ).returns(T::Array[Dependabot::DependencyRequirement])
        end
        def self.raisable_property_requirements(requirements, security_update:, &dependencies)
          with_property = requirements.select { |req| property?(req) }
          return with_property if security_update || with_property.none? { |req| override?(req) }

          declared = (requirements + yield.flat_map(&:requirements)).reject { |req| override?(req) }
          with_property.select do |req|
            !override?(req) || declared.any? { |other| same_property?(other, req) }
          end
        end

        sig do
          params(
            declaration: Dependabot::DependencyRequirement,
            override: Dependabot::DependencyRequirement
          ).returns(T::Boolean)
        end
        def self.rewrites?(declaration, override)
          return false if property?(override)
          return false unless declaration.file == override.file
          return false unless declaration.requirement_string == override.requirement_string
          return false unless %w(packaging_type classifier).all? do |key|
            declaration.metadata_string(key) == override.metadata_string(key)
          end

          declaration.groups == ["plugin"] || declaration.groups == override.groups
        end
        private_class_method :rewrites?

        sig { params(one: Dependabot::DependencyRequirement, other: Dependabot::DependencyRequirement).returns(T::Boolean) }
        def self.same_property?(one, other)
          one.metadata_string("property_name") == other.metadata_string("property_name") &&
            one.metadata_string("property_source") == other.metadata_string("property_source")
        end
        private_class_method :same_property?

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T::Boolean) }
        def self.property?(requirement)
          !requirement.metadata_string("property_name").nil?
        end
        private_class_method :property?
      end
    end
  end
end
