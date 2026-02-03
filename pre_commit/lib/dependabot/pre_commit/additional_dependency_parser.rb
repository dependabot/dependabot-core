# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/python/requirement_parser"
require "dependabot/python/requirement"
require "dependabot/python/name_normaliser"
require "dependabot/python/version"

module Dependabot
  module PreCommit
    # Parser for additional_dependencies in pre-commit hooks.
    # Currently supports Python dependencies with plans to add other ecosystems.
    class AdditionalDependencyParser
      extend T::Sig

      # Supported languages for additional_dependencies
      SUPPORTED_LANGUAGES = T.let(%w(python node golang rust ruby).freeze, T::Array[String])

      # Default language when not explicitly specified in hook config
      DEFAULT_LANGUAGE = T.let("python", String)

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

      sig do
        params(
          dep_string: String,
          hook_id: String,
          repo_url: String,
          language: String,
          file_name: String
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def self.parse(dep_string:, hook_id:, repo_url:, language:, file_name:)
        new.parse(
          dep_string: dep_string,
          hook_id: hook_id,
          repo_url: repo_url,
          language: language,
          file_name: file_name
        )
      end

      sig do
        params(
          dep_string: String,
          hook_id: String,
          repo_url: String,
          language: String,
          file_name: String
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def parse(dep_string:, hook_id:, repo_url:, language:, file_name:)
        case language.downcase
        when "python"
          parse_python_dependency(dep_string, hook_id, repo_url, file_name)
        when "node"
          # TODO: Implement Node.js parsing in Phase 2
          Dependabot.logger.debug("Node.js additional_dependencies not yet supported")
          nil
        when "golang"
          # TODO: Implement Go parsing in Phase 2
          Dependabot.logger.debug("Go additional_dependencies not yet supported")
          nil
        when "rust"
          # TODO: Implement Rust parsing in Phase 3+
          Dependabot.logger.debug("Rust additional_dependencies not yet supported")
          nil
        when "ruby"
          # TODO: Implement Ruby parsing in Phase 3+
          Dependabot.logger.debug("Ruby additional_dependencies not yet supported")
          nil
        else
          Dependabot.logger.debug("Unsupported language for additional_dependencies: #{language}")
          nil
        end
      end

      sig { params(language: String).returns(T::Boolean) }
      def self.supported_language?(language)
        SUPPORTED_LANGUAGES.include?(language.downcase)
      end

      private

      sig do
        params(
          dep_string: String,
          hook_id: String,
          repo_url: String,
          file_name: String
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def parse_python_dependency(dep_string, hook_id, repo_url, file_name)
        match = dep_string.strip.match(PYTHON_DEP_PATTERN)
        return nil unless match

        package_name = T.must(match[:name])
        normalised_name = Dependabot::Python::NameNormaliser.normalise(package_name)
        requirements_string = match[:requirements]
        extras = match[:extras]

        # Skip dependencies without any version constraint
        return nil if requirements_string.nil? || requirements_string.strip.empty?

        # Use Python's Requirement class to parse the version constraint
        version = extract_version_from_requirement(requirements_string)
        return nil unless version

        # Extract the operator to preserve the version format when updating
        operator = extract_operator_from_requirement(requirements_string)

        # Create a unique dependency name that includes context
        # Format: repo_url::hook_id::package_name
        dependency_name = build_dependency_name(repo_url, hook_id, normalised_name)

        Dependabot::Dependency.new(
          name: dependency_name,
          version: version,
          requirements: [{
            requirement: requirements_string,
            groups: ["additional_dependencies"],
            file: file_name,
            source: build_python_source(
              package_name: normalised_name,
              original_name: package_name,
              hook_id: hook_id,
              hook_repo: repo_url,
              extras: extras,
              original_string: dep_string,
              operator: operator
            )
          }],
          package_manager: "pre_commit"
        )
      end

      sig { params(requirements_string: T.nilable(String)).returns(T.nilable(String)) }
      def extract_version_from_requirement(requirements_string)
        return nil unless requirements_string

        requirement = Dependabot::Python::Requirement.new(requirements_string)

        # Extract version from the requirement constraints
        # For exact pins (==), use that version directly
        # For ranges (>=, ~=, etc.), extract the lower bound
        extract_version_from_constraints(requirement)
      rescue Gem::Requirement::BadRequirementError, Dependabot::BadRequirementError
        # If we can't parse the requirement, try simple regex extraction
        # requirements_string is guaranteed non-nil here due to early return
        extract_version_fallback(T.must(requirements_string))
      end

      sig { params(requirement: Dependabot::Python::Requirement).returns(T.nilable(String)) }
      def extract_version_from_constraints(requirement)
        # requirement.requirements returns array of [operator, version] pairs
        constraints = requirement.requirements

        # Look for exact pin first (==)
        exact_pin = constraints.find { |op, _| op == "==" || op == "=" }
        return exact_pin[1].to_s if exact_pin

        # For ranges, find the lower bound (>=, >, ~>)
        # Note: Python's ~= is converted to Ruby's ~> internally
        lower_bound = constraints.find { |op, _| LOWER_BOUND_OPERATORS.include?(op) }
        return lower_bound[1].to_s if lower_bound

        # If only upper bounds exist, we can't determine a "current" version
        nil
      end

      sig { params(requirements_string: String).returns(T.nilable(String)) }
      def extract_version_fallback(requirements_string)
        # Fallback: try to extract version using simple patterns
        # Match ==X.Y.Z or >=X.Y.Z or ~=X.Y.Z
        match = requirements_string.match(/(?:==|>=|~=)\s*(?<version>[^\s,<>!=]+)/)
        return nil unless match

        version_string = T.must(match[:version])
        return nil unless Dependabot::Python::Version.correct?(version_string)

        version_string
      end

      sig { params(requirements_string: T.nilable(String)).returns(String) }
      def extract_operator_from_requirement(requirements_string)
        return "==" unless requirements_string

        begin
          requirement = Dependabot::Python::Requirement.new(requirements_string)
          constraints = requirement.requirements

          # Look for exact pin first (==)
          exact_pin = constraints.find { |op, _| op == "==" || op == "=" }
          return "==" if exact_pin

          # For ranges, find the operator
          # Note: Python's ~= is converted to Ruby's ~> internally, convert back
          lower_bound = constraints.find { |op, _| LOWER_BOUND_OPERATORS.include?(op) }
          if lower_bound
            op = lower_bound[0]
            # Convert Ruby's ~> back to Python's ~=
            return op == "~>" ? "~=" : op
          end

          # Default to exact pin
          "=="
        rescue Gem::Requirement::BadRequirementError, Dependabot::BadRequirementError
          # Fallback: try to extract operator using regex
          match = requirements_string.match(/^(?<op>==|>=|>|~=|<=|<|!=)/)
          match ? T.must(match[:op]) : "=="
        end
      end

      sig do
        params(
          repo_url: String,
          hook_id: String,
          package_name: String
        ).returns(String)
      end
      def build_dependency_name(repo_url, hook_id, package_name)
        "#{repo_url}::#{hook_id}::#{package_name}"
      end

      sig do
        params(
          package_name: String,
          original_name: String,
          hook_id: String,
          hook_repo: String,
          extras: T.nilable(String),
          original_string: String,
          operator: String
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def build_python_source(package_name:, original_name:, hook_id:, hook_repo:, extras:, original_string:, operator:)
        {
          type: "additional_dependency",
          language: "python",
          registry: "pypi",
          package_name: package_name,
          original_name: original_name,
          hook_id: hook_id,
          hook_repo: hook_repo,
          extras: extras,
          original_string: original_string,
          operator: operator
        }
      end
    end
  end
end
