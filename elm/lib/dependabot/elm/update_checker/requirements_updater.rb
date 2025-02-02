# typed: strict
# frozen_string_literal: true

require "dependabot/elm/version"
require "dependabot/elm/requirement"
require "dependabot/elm/update_checker"

module Dependabot
  module Elm
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig
        RANGE_REQUIREMENT_REGEX =
          /(\d+\.\d+\.\d+) <= v < (\d+\.\d+\.\d+)/
        SINGLE_VERSION_REGEX = /\A(\d+\.\d+\.\d+)\z/

        sig do
          params(requirements: T::Array[T::Hash[Symbol, T.nilable(String)]],
                 latest_resolvable_version: T.nilable(T.any(String, Integer, Dependabot::Version))).void
        end
        def initialize(requirements:, latest_resolvable_version:)
          @requirements = T.let(requirements, T::Array[T::Hash[Symbol, T.nilable(String)]])

          return unless latest_resolvable_version
          return unless version_class.correct?(latest_resolvable_version)

          @latest_resolvable_version = T.let(
            version_class.new(latest_resolvable_version),
            T.nilable(Dependabot::Version)
          )
        end

        sig { returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
        def updated_requirements
          return requirements unless latest_resolvable_version

          requirements.map do |req|
            updated_req_string = update_requirement(
              req[:requirement],
              latest_resolvable_version
            )

            req.merge(requirement: updated_req_string)
          end
        end

        private

        sig { returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
        attr_reader :requirements
        sig { returns(T.nilable(Dependabot::Version)) }
        attr_reader :latest_resolvable_version

        sig { params(old_req: T.nilable(String), new_version: T.untyped).returns(String) }
        def update_requirement(old_req, new_version)
          if requirement_class.new(old_req).satisfied_by?(new_version)
            old_req
          elsif (match = RANGE_REQUIREMENT_REGEX.match(old_req))
            require_range(match[1], new_version)
          elsif SINGLE_VERSION_REGEX.match?(old_req)
            new_version.to_s
          else
            require_exactly(new_version)
          end
        end

        sig { params(minimum: T.untyped, version: T.untyped).returns(String) }
        def require_range(minimum, version)
          major, _minor, _patch = version.to_s.split(".").map(&:to_i)
          "#{minimum} <= v < #{major + 1}.0.0"
        end

        sig { params(version: Dependabot::Elm::Version).returns(String) }
        def require_exactly(version)
          "#{version} <= v <= #{version}"
        end

        sig { returns(T.class_of(Dependabot::Elm::Version)) }
        def version_class
          Elm::Version
        end

        sig { returns(T.class_of(Dependabot::Elm::Requirement)) }
        def requirement_class
          Elm::Requirement
        end
      end
    end
  end
end
