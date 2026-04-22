# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/update_checker/requirements_updater"
require "dependabot/uv/update_checker"

module Dependabot
  module Uv
    class UpdateChecker
      class RequirementsUpdater < Dependabot::Python::UpdateChecker::RequirementsUpdater
        extend T::Sig

        sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          return requirements if update_strategy.lockfile_only?

          requirements.map do |req|
            case req[:file]
            when "uv.toml" then updated_uv_toml_requirement(req)
            when "pyproject.toml" then updated_pyproject_requirement(req)
            when /setup\.(?:py|cfg)$/ then updated_setup_requirement(req)
            when "Pipfile" then updated_pipfile_requirement(req)
            when /\.txt$|\.in$/ then updated_requirement(req)
            else raise "Unexpected filename: #{req[:file]}"
            end
          end
        end

        private

        sig { params(req: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def updated_uv_toml_requirement(req)
          return req unless latest_resolvable_version
          return req unless req.fetch(:requirement)
          return req if new_version_satisfies?(req)

          update_pyproject_version(req)
        rescue UnfixableRequirement
          req.merge(requirement: :unfixable)
        end
      end
    end
  end
end
