# frozen_string_literal: true

# TODO: File and specs need to be updated

####################################################################
# For more details on Terraform version constraints, see:          #
# https://www.terraform.io/docs/modules/usage.html#module-versions #
####################################################################

require "dependabot/pub/version"
require "dependabot/pub/requirement"

module Dependabot
  module Pub
    class RequirementsUpdater
      ALLOWED_UPDATE_STRATEGIES =
        %i(widen_ranges bump_versions).freeze

      def initialize(requirements:, latest_version:, update_strategy:,
                     tag_for_latest_version:, commit_hash_for_latest_version:)
        @requirements = requirements
        @update_strategy = update_strategy
        @tag_for_latest_version = tag_for_latest_version
        @commit_hash_for_latest_version = commit_hash_for_latest_version

        check_update_strategy

        return unless latest_version
        return unless version_class.correct?(latest_version)

        @latest_version = version_class.new(latest_version)
      end

      def updated_requirements
        return requirements unless latest_version

        # NOTE: Order is important here. The FileUpdater needs the updated
        # requirement at index `i` to correspond to the previous requirement
        # at the same index.
        requirements.map do |req|
          case req.dig(:source, :type)
          when "git" then update_git_requirement(req)
          when "hosted" then update_hosted_requirement(req)
          else req
          end
        end
      end

      private

      attr_reader :requirements, :latest_version, :update_strategy,
                  :tag_for_latest_version, :commit_hash_for_latest_version

      def check_update_strategy
        return if ALLOWED_UPDATE_STRATEGIES.include?(update_strategy)

        raise "Unknown update strategy: #{update_strategy}"
      end

      def update_git_requirement(req)
        return req unless req.dig(:source, :ref)
        return req unless req.dig(:source, :resolved_ref)
        return req unless tag_for_latest_version
        return req unless commit_hash_for_latest_version

        req.merge(source: req[:source].merge(
          ref: tag_for_latest_version,
          resolved_ref: commit_hash_for_latest_version
        ))
      end

      def update_hosted_requirement(req)
        return req if req.fetch(:requirement).nil?

        string_req = req.fetch(:requirement).strip
        # ruby_req = requirement_class.new(string_req)
        # return req if ruby_req.satisfied_by?(latest_version)

        new_req =
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.run_helper_subprocess(
              command: NativeHelpers.helper_path.to_s,
              function: "requirement_updater",
              args: [
                "--requirement",
                string_req,
                "--latest-version",
                latest_version.to_s,
                "--strategy",
                update_strategy
              ]
            )
          end

        req.merge(requirement: new_req)
      end

      def version_class
        Version
      end

      def requirement_class
        Requirement
      end
    end
  end
end
