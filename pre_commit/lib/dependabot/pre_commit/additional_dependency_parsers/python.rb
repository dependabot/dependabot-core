# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/python/requirement_parser"
require "dependabot/python/requirement"
require "dependabot/python/name_normaliser"
require "dependabot/python/version"
require "dependabot/pre_commit/additional_dependency_parsers"
require "dependabot/pre_commit/additional_dependency_parsers/base"

module Dependabot
  module PreCommit
    module AdditionalDependencyParsers
      class Python < Base
        extend T::Sig

        # PEP 440 pattern for Python packages
        # Matches: package==1.0.0, package>=1.0,<2.0, package[extras]==1.0.0
        PYTHON_DEP_PATTERN = T.let(
          /^
            (?<name>#{Dependabot::Python::RequirementParser::NAME})
            (?:\[(?<extras>#{Dependabot::Python::RequirementParser::EXTRA}
            (?:\s*,\s*#{Dependabot::Python::RequirementParser::EXTRA})*)\])?
            \s*(?<requirements>#{Dependabot::Python::RequirementParser::REQUIREMENTS})?
          $/x,
          Regexp
        )

        # Operators that indicate a lower version bound
        # Note: Python's ~= is converted to Ruby's ~> internally by Dependabot::Python::Requirement
        LOWER_BOUND_OPERATORS = T.let(%w(>= > ~>).freeze, T::Array[String])

        sig { override.returns(T.nilable(Dependabot::Dependency)) }
        def parse
          match = dep_string.strip.match(PYTHON_DEP_PATTERN)
          return nil unless match

          package_name = T.must(match[:name])
          normalised_name = Dependabot::Python::NameNormaliser.normalise(package_name)
          requirements_string = match[:requirements]
          extras = match[:extras]

          return nil if requirements_string.nil? || requirements_string.strip.empty?

          version = extract_version_from_requirement(requirements_string)
          return nil unless version

          operator = extract_operator_from_requirement(requirements_string)

          dependency_name = build_dependency_name(normalised_name)

          Dependabot::Dependency.new(
            name: dependency_name,
            version: version,
            requirements: [{
              requirement: requirements_string,
              groups: ["additional_dependencies"],
              file: file_name,
              source: build_source(
                package_name: normalised_name,
                original_name: package_name,
                extras: extras,
                operator: operator
              )
            }],
            package_manager: "pre_commit"
          )
        end

        private

        sig { params(requirements_string: T.nilable(String)).returns(T.nilable(String)) }
        def extract_version_from_requirement(requirements_string)
          return nil unless requirements_string

          requirement = Dependabot::Python::Requirement.new(requirements_string)

          # Extract version from the requirement constraints
          # For exact pins (==), use that version directly
          # For ranges (>=, ~=, etc.), extract the lower bound
          extract_version_from_constraints(requirement)
        rescue Gem::Requirement::BadRequirementError, Dependabot::BadRequirementError
          extract_version_fallback(T.must(requirements_string))
        end

        sig { params(requirement: Dependabot::Python::Requirement).returns(T.nilable(String)) }
        def extract_version_from_constraints(requirement)
          constraints = requirement.requirements

          exact_pin = constraints.find { |op, _| op == "==" || op == "=" }
          return exact_pin[1].to_s if exact_pin

          lower_bound = constraints.find { |op, _| LOWER_BOUND_OPERATORS.include?(op) }
          return lower_bound[1].to_s if lower_bound

          # If only upper bounds exist, we can't determine a "current" version
          nil
        end

        sig { params(requirements_string: String).returns(T.nilable(String)) }
        def extract_version_fallback(requirements_string)
          match = requirements_string.match(/(?:==|>=|~=)\s*(?<version>[^\s,<>!=]+)/)
          return nil unless match

          version_string = T.must(match[:version])
          return nil unless Dependabot::Python::Version.correct?(version_string)

          version_string
        end

        sig { params(requirements_string: T.nilable(String)).returns(String) }
        def extract_operator_from_requirement(requirements_string)
          return "==" unless requirements_string

          requirement = Dependabot::Python::Requirement.new(requirements_string)
          constraints = requirement.requirements

          exact_pin = constraints.find { |op, _| op == "==" || op == "=" }
          return "==" if exact_pin

          lower_bound = constraints.find { |op, _| LOWER_BOUND_OPERATORS.include?(op) }
          if lower_bound
            op = lower_bound[0]
            # Convert Ruby's ~> back to Python's ~=
            return op == "~>" ? "~=" : op
          end

          # Default to exact pin
          "=="
        rescue Gem::Requirement::BadRequirementError, Dependabot::BadRequirementError
          match = T.must(requirements_string).match(/^(?<op>==|>=|>|~=|<=|<|!=)/)
          match ? match[:op].to_s : "=="
        end

        sig do
          params(
            package_name: String,
            original_name: String,
            extras: T.nilable(String),
            operator: String
          ).returns(T::Hash[Symbol, T.untyped])
        end
        def build_source(package_name:, original_name:, extras:, operator:)
          {
            type: "additional_dependency",
            language: "python",
            registry: "pypi",
            package_name: package_name,
            original_name: original_name,
            hook_id: hook_id,
            hook_repo: repo_url,
            extras: extras,
            original_string: dep_string,
            operator: operator
          }
        end
      end
    end
  end
end

Dependabot::PreCommit::AdditionalDependencyParsers.register(
  "python",
  Dependabot::PreCommit::AdditionalDependencyParsers::Python
)
