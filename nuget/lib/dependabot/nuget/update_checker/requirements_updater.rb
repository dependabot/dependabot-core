# typed: strict
# frozen_string_literal: true

#######################################################################
# For more details on Dotnet version constraints, see:                #
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning #
#######################################################################

require "sorbet-runtime"

require "dependabot/update_checkers/base"
require "dependabot/nuget/version"

module Dependabot
  module Nuget
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RequirementsUpdater
        extend T::Sig

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            latest_version: T.nilable(T.any(String, Dependabot::Nuget::Version)),
            source_details: T.nilable(T::Hash[Symbol, T.untyped])
          )
            .void
        end
        def initialize(requirements:, latest_version:, source_details:)
          @requirements = requirements
          @source_details = source_details
          return unless latest_version

          @latest_version = T.let(version_class.new(latest_version), Dependabot::Nuget::Version)
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          return requirements unless latest_version

          requirements.map do |req|
            req[:metadata] ||= {}
            req[:metadata][:is_transitive] = false
            req[:metadata][:previous_requirement] = req[:requirement]

            next req if req.fetch(:requirement).nil?
            next req if req.fetch(:requirement).include?(",")

            new_req =
              if req.fetch(:requirement).include?("*")
                update_wildcard_requirement(req.fetch(:requirement))
              else
                # Since range requirements are excluded by the line above we can
                # replace anything that looks like a version with the new
                # version
                req[:requirement].sub(
                  /#{Nuget::Version::VERSION_PATTERN}/o,
                  latest_version.to_s
                )
              end
            next req if new_req == req.fetch(:requirement)

            req.merge(requirement: new_req, source: updated_source)
          end
        end

        private

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :requirements

        sig { returns(T.nilable(Dependabot::Nuget::Version)) }
        attr_reader :latest_version

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        attr_reader :source_details

        sig { returns(T.class_of(Dependabot::Nuget::Version)) }
        def version_class
          Dependabot::Nuget::Version
        end

        sig { params(req_string: String).returns(String) }
        def update_wildcard_requirement(req_string)
          return req_string if req_string == "*-*"

          return req_string if req_string == "*"

          precision = T.must(req_string.split("*").first).split(/\.|\-/).count
          wildcard_section = req_string.partition(/(?=[.\-]\*)/).last

          version_parts = T.must(latest_version).segments.first(precision)
          version = version_parts.join(".")

          version + wildcard_section
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def updated_source
          {
            type: "nuget_repo",
            url: source_details&.fetch(:repo_url),
            nuspec_url: source_details&.fetch(:nuspec_url),
            source_url: source_details&.fetch(:source_url)
          }
        end
      end
    end
  end
end
