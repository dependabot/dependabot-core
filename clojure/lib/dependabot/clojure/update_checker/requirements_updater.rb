# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_requirement"
require "dependabot/requirements_updater/base"
require "dependabot/clojure/update_checker"
require "dependabot/clojure/version"
require "dependabot/clojure/requirement"

module Dependabot
  module Clojure
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RequirementsUpdater
        extend T::Sig
        extend T::Generic

        Version = type_member { { fixed: Dependabot::Clojure::Version } }
        Requirement = type_member { { fixed: Dependabot::Clojure::Requirement } }

        include Dependabot::RequirementsUpdater::Base

        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
            latest_version: T.nilable(T.any(Version, String)),
            source_url: T.nilable(String)
          ).void
        end
        def initialize(requirements:, latest_version:, source_url:)
          @requirements = requirements
          @source_url = source_url
          return unless latest_version

          @latest_version = T.let(version_class.new(latest_version), Version)
        end

        # Maven ranges such as "[1.0,2.0)" are left as they are.
        sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
        def updated_requirements
          return requirements unless latest_version

          requirements.map do |req|
            requirement = req.requirement_string
            next req if requirement.nil? || requirement.include?(",")

            Dependabot::DependencyRequirement.create(
              req.merge(requirement: T.must(latest_version).to_s, source: updated_source)
            )
          end
        end

        private

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        attr_reader :requirements

        sig { returns(T.nilable(Version)) }
        attr_reader :latest_version

        sig { returns(T.nilable(String)) }
        attr_reader :source_url

        sig { override.returns(T::Class[Version]) }
        def version_class
          Clojure::Version
        end

        sig { override.returns(T::Class[Requirement]) }
        def requirement_class
          Clojure::Requirement
        end

        sig { returns(T::Hash[Symbol, T.nilable(String)]) }
        def updated_source
          { type: "maven_repo", url: source_url }
        end
      end
    end
  end
end
