# typed: strict
# frozen_string_literal: true

#######################################################
# For more details on Maven version constraints, see: #
# https://maven.apache.org/pom.html#Dependencies      #
#######################################################

require "dependabot/dependency_requirement"
require "dependabot/requirements_updater/base"
require "dependabot/maven/update_checker"
require "dependabot/maven/version"
require "dependabot/maven/requirement"
require "dependabot/maven/distributions"

module Dependabot
  module Maven
    class UpdateChecker
      class RequirementsUpdater
        extend T::Sig
        extend T::Generic

        Version = type_member { { fixed: Dependabot::Maven::Version } }
        Requirement = type_member { { fixed: Dependabot::Maven::Requirement } }

        include Dependabot::RequirementsUpdater::Base

        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
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
          @requirements = T.let(
            requirements.map { |req| Dependabot::DependencyRequirement.create(req) },
            T::Array[Dependabot::DependencyRequirement]
          )
          @source_url = source_url
          @properties_to_update = properties_to_update
          return unless latest_version

          @latest_version = T.let(version_class.new(latest_version), Version)
        end

        sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
        def updated_requirements
          return requirements unless latest_version

          # NOTE: Order is important here. The FileUpdater needs the updated
          # requirement at index `i` to correspond to the previous requirement
          # at the same index.
          requirements.map do |req|
            # Wrapper property requirements (distributionUrl, wrapperVersion,
            # wrapperUrl) live in maven-wrapper.properties, not in a pom.xml.
            # They must not go through POM XML update logic; instead we bump the
            # requirement and keep the version metadata / artifact URL the
            # FileUpdater reads in sync with it.
            if req.dig(:source, :type) == Distributions::DISTRIBUTION_DEPENDENCY_TYPE
              next bump_distribution_requirement(req)
            end

            next req if req.fetch(:requirement).nil?
            next req if req.fetch(:requirement).include?(",")

            property_name = req.dig(:metadata, :property_name)
            next req if property_name && !properties_to_update.include?(property_name)

            new_req = update_requirement(req[:requirement])
            next req if new_req == req[:requirement]

            Dependabot::DependencyRequirement.create(req.merge(requirement: new_req, source: updated_source))
          end
        end

        private

        sig { returns(T::Array[Dependabot::DependencyRequirement]) }
        attr_reader :requirements

        # Bumps a wrapper (maven-wrapper.properties) requirement. As well as the requirement
        # string, it updates the fields the FileUpdater actually reads so a real update regenerates
        # the *new* release rather than the old one:
        #   - distributionUrl  -> metadata[:distribution_version] and the versioned source url
        #   - wrapperVersion   -> metadata[:wrapper_version]
        # The wrapperUrl tag-along requirement (present only on the distribution dependency) is left
        # otherwise untouched, since bumping the distribution does not change the wrapper JAR.
        sig do
          params(req: Dependabot::DependencyRequirement)
            .returns(Dependabot::DependencyRequirement)
        end
        def bump_distribution_requirement(req)
          new_version = T.must(latest_version).to_s
          old_version = req.requirement_string
          updated = Dependabot::DependencyRequirement.create(req.merge(requirement: new_version))

          case req.source_string("property")
          when "distributionUrl"
            updated = merge_metadata_version(updated, :distribution_version, new_version)
            updated = merge_source_url(updated, old_version, new_version)
          when "wrapperVersion"
            updated = merge_metadata_version(updated, :wrapper_version, new_version)
          end

          Dependabot::DependencyRequirement.create(updated)
        end

        sig do
          params(req: Dependabot::DependencyRequirement, key: Symbol, new_version: String)
            .returns(Dependabot::DependencyRequirement)
        end
        def merge_metadata_version(req, key, new_version)
          metadata = req.metadata
          return req unless metadata

          Dependabot::DependencyRequirement.create(req.merge(metadata: metadata.merge(key => new_version)))
        end

        sig do
          params(req: Dependabot::DependencyRequirement, old_version: T.nilable(String), new_version: String)
            .returns(Dependabot::DependencyRequirement)
        end
        def merge_source_url(req, old_version, new_version)
          source = req.source_hash
          url = req.source_string("url")
          return req unless source && url && old_version && !old_version.empty?

          Dependabot::DependencyRequirement.create(
            req.merge(source: source.merge(url: url.sub(old_version, new_version)))
          )
        end

        sig { returns(T.nilable(Version)) }
        attr_reader :latest_version

        sig { returns(T.nilable(String)) }
        attr_reader :source_url

        sig { returns(T::Array[String]) }
        attr_reader :properties_to_update

        sig { params(req_string: String).returns(String) }
        def update_requirement(req_string)
          # Since range requirements are excluded this must be exact
          update_exact_requirement(req_string)
        end

        sig { params(req_string: String).returns(String) }
        def update_exact_requirement(req_string)
          old_version = requirement_class.new(req_string)
                                         .requirements.first.last
          req_string.gsub(old_version.to_s, latest_version.to_s)
        end

        sig { override.returns(T::Class[Version]) }
        def version_class
          Maven::Version
        end

        sig { override.returns(T::Class[Requirement]) }
        def requirement_class
          Maven::Requirement
        end

        sig { returns(T::Hash[Symbol, String]) }
        def updated_source
          { type: "maven_repo", url: source_url }
        end
      end
    end
  end
end
