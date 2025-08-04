# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Conda
    class UpdateChecker
      class RequirementTranslator
        extend T::Sig

        # Convert conda-style requirements to pip-compatible requirements
        sig { params(conda_requirement: T.nilable(String)).returns(T.nilable(String)) }
        def self.conda_to_pip(conda_requirement)
          return nil unless conda_requirement

          # Handle different conda requirement patterns
          case conda_requirement
          when /^=([0-9]+(?:\.[0-9]+)*)\.\*$/
            # Handle wildcards: =1.21.* -> >=1.21.0,<1.22.0
            convert_wildcard_requirement(conda_requirement)
          when /^=([0-9]+(?:\.[0-9]+)*)$/
            # Handle exact equality: =1.2.3 -> ==1.2.3
            conda_requirement.gsub(/^=/, "==")
          when /^(>=|>|<=|<|!=)(.+)$/
            # Handle comparison operators: >=1.2.0 -> >=1.2.0 (no change)
            conda_requirement
          when /^([0-9]+(?:\.[0-9]+)*)$/
            # Handle bare version: 1.2.3 -> ==1.2.3
            "==#{conda_requirement}"
          else
            # Handle complex constraints: >=3.8,<3.11 -> >=3.8,<3.11 (no change)
            conda_requirement
          end
        end

        sig { params(wildcard_requirement: String).returns(String) }
        def self.convert_wildcard_requirement(wildcard_requirement)
          # Extract version pattern: =1.21.* -> 1.21
          version_match = wildcard_requirement.match(/^=([0-9]+(?:\.[0-9]+)*)\.\*$/)
          return wildcard_requirement unless version_match

          base_version = version_match[1]
          version_parts = T.must(base_version).split(".")

          # Calculate next version for upper bound
          next_version_parts = version_parts.dup
          next_version_parts[-1] = (next_version_parts[-1].to_i + 1).to_s
          next_version = next_version_parts.join(".")

          # Return range: >=1.21.0,<1.22.0
          ">=#{base_version}.0,<#{next_version}.0"
        end
      end
    end
  end
end
