# typed: strict
# frozen_string_literal: true

#######################################################################
# For more details on Dotnet version constraints, see:                #
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning #
#######################################################################

require "sorbet-runtime"

require "dependabot/update_checkers/base"
require "dependabot/nuget/discovery/dependency_details"
require "dependabot/nuget/version"

module Dependabot
  module Nuget
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class RequirementsUpdater
        extend T::Sig

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            dependency_details: T.nilable(Dependabot::Nuget::DependencyDetails)
          )
            .void
        end
        def initialize(requirements:, dependency_details:)
          @requirements = requirements
          @dependency_details = dependency_details
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements
          return requirements unless clean_version

          # NOTE: Order is important here. The FileUpdater needs the updated
          # requirement at index `i` to correspond to the previous requirement
          # at the same index.
          requirements.map do |req|
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
                  clean_version.to_s
                )
              end

            next req if new_req == req.fetch(:requirement)

            new_source = req[:source]&.dup
            unless @dependency_details.nil?
              new_source = {
                type: "nuget_repo",
                source_url: @dependency_details.info_url
              }
            end

            req.merge({ requirement: new_req, source: new_source })
          end
        end

        private

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :requirements

        sig { returns(T.class_of(Dependabot::Nuget::Version)) }
        def version_class
          Dependabot::Nuget::Version
        end

        sig { returns(T.nilable(Dependabot::Nuget::Version))}
        def clean_version
          return unless @dependency_details&.version

          version_class.new(@dependency_details.version)
        end

        sig { params(req_string: String).returns(String) }
        def update_wildcard_requirement(req_string)
          return req_string if req_string == "*-*"

          return req_string if req_string == "*"

          precision = T.must(req_string.split("*").first).split(/\.|\-/).count
          wildcard_section = req_string.partition(/(?=[.\-]\*)/).last

          version_parts = T.must(clean_version).segments.first(precision)
          version = version_parts.join(".")

          version + wildcard_section
        end
      end
    end
  end
end
