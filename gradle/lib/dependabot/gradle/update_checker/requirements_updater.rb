# typed: strict
# frozen_string_literal: true

#######################################################
# For more details on Maven version constraints, see: #
# https://maven.apache.org/pom.html#Dependencies      #
#######################################################

require "sorbet-runtime"

require "dependabot/dependency_requirement"
require "dependabot/requirements_updater/base"
require "dependabot/gradle/distributions"
require "dependabot/gradle/package/distributions_fetcher"
require "dependabot/gradle/update_checker"
require "dependabot/gradle/version"
require "dependabot/gradle/requirement"

module Dependabot
  module Gradle
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig
        extend T::Generic

        Version = type_member { { fixed: Dependabot::Gradle::Version } }
        Requirement = type_member { { fixed: Dependabot::Gradle::Requirement } }

        include Dependabot::RequirementsUpdater::Base

        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
            latest_version: T.nilable(T.any(Version, String)),
            source_url: T.nilable(String),
            properties_to_update: T::Array[String]
          )
            .void
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
          @is_distribution = T.let(Distributions.distribution_requirements?(requirements), T::Boolean)
        end

        sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
        def updated_requirements
          return requirements unless latest_version
          return updated_distribution_requirements if @is_distribution

          # NOTE: Order is important here. The FileUpdater needs the updated
          # requirement at index `i` to correspond to the previous requirement
          # at the same index.
          requirements.map do |req|
            next req if req.unfixable?

            requirement = req.requirement
            next req unless requirement
            next req if requirement.include?(",")

            property_name = metadata_string(req, :property_name)
            next req if property_name && !properties_to_update.include?(property_name)

            new_req = update_requirement(requirement)
            req.with_requirement(new_req).with_source(updated_source)
          end
        end

        private

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        attr_reader :requirements

        sig { returns(T.nilable(Version)) }
        attr_reader :latest_version

        sig { returns(T.nilable(String)) }
        attr_reader :source_url

        sig { returns(T::Array[String]) }
        attr_reader :properties_to_update

        sig { params(req_string: String).returns(String) }
        def update_requirement(req_string)
          if req_string.include?("+")
            update_dynamic_requirement(req_string)
          else
            # Since range requirements are excluded this must be exact
            update_exact_requirement(req_string)
          end
        end

        sig { params(req_string: String).returns(String) }
        def update_exact_requirement(req_string)
          old_version = requirement_class.new(req_string)
                                         .requirements.first.last
          req_string.gsub(old_version.to_s, latest_version.to_s)
        end

        sig { params(req_string: String).returns(String) }
        def update_dynamic_requirement(req_string)
          version = req_string.split(/\.?\+/).first || "+"

          precision = version.split(".")
                             .take_while { |s| !s.include?("+") }.count

          version_parts = T.must(latest_version).segments.first(precision)

          if req_string.end_with?(".+")
            version_parts.join(".") + ".+"
          else
            version_parts.join(".") + "+"
          end
        end

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        def updated_distribution_requirements
          distribution_url = T.let(nil, T.nilable(String))

          requirements.map do |req|
            source = req.source
            next req unless source

            case detail_string(source, :property)
            when "distributionUrl"
              requirement = T.must(req.requirement)
              version = update_exact_requirement(requirement)
              distribution_url = T.must(detail_string(source, :url)).gsub(requirement, version)

              req
                .with_requirement(version)
                .with_source(source.merge(url: distribution_url))
            when "distributionSha256Sum"
              checksum_url, checksum = Gradle::Package::DistributionsFetcher.resolve_checksum(T.must(distribution_url))
              req
                .with_requirement(checksum)
                .with_source(source.merge(url: checksum_url))
            else
              next req
            end
          end
        end

        sig { override.returns(T::Class[Version]) }
        def version_class
          Gradle::Version
        end

        sig { override.returns(T::Class[Requirement]) }
        def requirement_class
          Gradle::Requirement
        end

        sig { returns(Dependabot::DependencyRequirement::Details) }
        def updated_source
          { type: "maven_repo", url: source_url }
        end

        sig do
          params(
            requirement: Dependabot::DependencyRequirement,
            key: Symbol
          ).returns(T.nilable(String))
        end
        def metadata_string(requirement, key)
          value = requirement.metadata&.[](key)
          value if value.is_a?(String)
        end

        sig do
          params(
            details: Dependabot::DependencyRequirement::Details,
            key: Symbol
          ).returns(T.nilable(String))
        end
        def detail_string(details, key)
          value = details[key]
          value if value.is_a?(String)
        end
      end
    end
  end
end
