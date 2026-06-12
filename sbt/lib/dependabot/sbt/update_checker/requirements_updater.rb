# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirements_updater/base"
require "dependabot/sbt/update_checker"
require "dependabot/sbt/version"
require "dependabot/sbt/requirement"

module Dependabot
  module Sbt
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RequirementsUpdater
        extend T::Sig
        extend T::Generic

        Version = type_member { { fixed: Dependabot::Sbt::Version } }
        Requirement = type_member { { fixed: Dependabot::Sbt::Requirement } }

        include Dependabot::RequirementsUpdater::Base

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            latest_version: T.nilable(T.any(Version, String)),
            source_url: T.nilable(String),
            properties_to_update: T::Array[String]
          ).void
        end
        def initialize(
          requirements:,
          latest_version:,
          source_url:,
          properties_to_update:
        )
          @requirements = requirements
          @source_url = source_url
          @properties_to_update = properties_to_update
          return unless latest_version

          @latest_version = T.let(version_class.new(latest_version), Version)
        end

        sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          return requirements unless latest_version

          requirements.map do |req|
            next req if req.fetch(:requirement).nil?
            next req if req.fetch(:requirement).include?(",")

            property_name = req.dig(:metadata, :property_name)
            next req if property_name && !properties_to_update.include?(property_name)

            new_req = update_requirement(req[:requirement])
            req.merge(requirement: new_req, source: updated_source)
          end
        end

        private

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :requirements

        sig { returns(T.nilable(Version)) }
        attr_reader :latest_version

        sig { returns(T.nilable(String)) }
        attr_reader :source_url

        sig { returns(T::Array[String]) }
        attr_reader :properties_to_update

        sig { params(req_string: String).returns(String) }
        def update_requirement(req_string)
          old_version = requirement_class.new(req_string)
                                         .requirements.first.last
          req_string.gsub(old_version.to_s, T.must(latest_version).to_s)
        end

        sig { override.returns(T::Class[Version]) }
        def version_class
          Sbt::Version
        end

        sig { override.returns(T::Class[Requirement]) }
        def requirement_class
          Sbt::Requirement
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def updated_source
          { type: "maven_repo", url: source_url }
        end
      end
    end
  end
end
