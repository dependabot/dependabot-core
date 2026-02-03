# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/update_checker/requirements_updater"
require "dependabot/requirements_update_strategy"

module Dependabot
  module PreCommit
    # Extends Python's RequirementsUpdater to support pre-commit config files.
    # This allows reusing all the Python version parsing and update logic
    # (precision preservation, operator handling, etc.) for pre-commit's
    # additional_dependencies.
    class PythonRequirementsUpdater < Dependabot::Python::UpdateChecker::RequirementsUpdater
      extend T::Sig

      # Override to add support for pre-commit config files
      sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def updated_requirements
        return requirements if update_strategy.lockfile_only?

        requirements.map do |req|
          case req[:file]
          when /\.pre-commit-config\.ya?ml$/, /pre-commit-config\.ya?ml$/
            updated_precommit_requirement(req)
          else
            # Fall back to parent class for standard Python files
            super
          end
        end
      end

      private

      sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def updated_precommit_requirement(req)
        # Pre-commit additional_dependencies use standard Python requirement syntax
        # We always use BumpVersions strategy (no widening for pre-commit deps)
        return req unless latest_resolvable_version
        return req unless req.fetch(:requirement)

        update_precommit_version(req)
      rescue UnfixableRequirement
        req.merge(requirement: :unfixable)
      end

      sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
      def update_precommit_version(req)
        requirement_strings = req[:requirement].split(",").map(&:strip)

        new_requirement = compute_new_precommit_requirement(requirement_strings, req)
        req.merge(requirement: new_requirement)
      end

      sig do
        params(
          requirement_strings: T::Array[String],
          req: T::Hash[Symbol, T.untyped]
        ).returns(String)
      end
      def compute_new_precommit_requirement(requirement_strings, req)
        if requirement_strings.any? { |r| r.match?(/^[=\d]/) }
          # Exact pins (==1.0.0) or bare versions
          find_and_update_equality_match(requirement_strings)
        elsif requirement_strings.any? { |r| r.start_with?("~=", ">=") }
          # Compatible release (~=1.0) or minimum version (>=1.0)
          versioned_req = T.must(requirement_strings.find { |r| r.start_with?("~=", ">=") })
          bump_version(versioned_req, T.must(latest_resolvable_version).to_s)
        elsif new_version_satisfies?(req)
          req.fetch(:requirement)
        else
          update_requirements_range(requirement_strings)
        end
      end
    end
  end
end
