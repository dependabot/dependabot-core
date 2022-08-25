# frozen_string_literal: true

####################################################################
# For more details on Terraform version constraints, see:          #
# https://www.terraform.io/docs/modules/usage.html#module-versions #
####################################################################

require "dependabot/terraform/version"
require "dependabot/terraform/requirement"

module Dependabot
  module Terraform
    # Takes an array of `requirements` hashes for a dependency at the old
    # version and a new version, and generates a set of new `requirements`
    # hashes at the new version.
    #
    # A requirements hash is a basic description of a dependency at a certain
    # version constraint, and it includes the data that is needed to update the
    # manifest (i.e. the `.tf` file) with the new version.
    #
    # A requirements hash looks like this for a registry hosted requirement:
    # ```ruby
    # {
    #   requirement: "~> 0.2.1",
    #   groups: [],
    #   file: "main.tf",
    #   source: {
    #     type: "registry",
    #     registry_hostname: "registry.terraform.io",
    #     module_identifier: "hashicorp/consul/aws"
    #   }
    # }
    #
    # And like this for a git requirement:
    # ```ruby
    # {
    #   requirement: nil,
    #   groups: [],
    #   file: "main.tf",
    #   source: {
    #     type: "git",
    #     url: "https://github.com/cloudposse/terraform-null-label.git",
    #     branch: nil,
    #     ref: nil
    #   }
    # }
    class RequirementsUpdater
      # @param requirements [Hash{Symbol => String, Array, Hash}]
      # @param latest_version [Dependabot::Terraform::Version]
      # @param tag_for_latest_version [String, NilClass]
      def initialize(requirements:, latest_version:, tag_for_latest_version:)
        @requirements = requirements
        @tag_for_latest_version = tag_for_latest_version

        return unless latest_version
        return unless version_class.correct?(latest_version)

        @latest_version = version_class.new(latest_version)
      end

      # @return requirements [Hash{Symbol => String, Array, Hash}]
      #   * requirement [String, NilClass] the updated version constraint
      #   * groups [Array] no-op for terraform
      #   * file [String] the file that specified this dependency
      #   * source [Hash{Symbol => String}] The updated git or registry source details
      def updated_requirements
        return requirements unless latest_version

        # NOTE: Order is important here. The FileUpdater needs the updated
        # requirement at index `i` to correspond to the previous requirement
        # at the same index.
        requirements.map do |req|
          case req.dig(:source, :type)
          when "git" then update_git_requirement(req)
          when "registry", "provider" then update_registry_requirement(req)
          else req
          end
        end
      end

      private

      attr_reader :requirements, :latest_version, :tag_for_latest_version

      def update_git_requirement(req)
        return req unless req.dig(:source, :ref)
        return req unless tag_for_latest_version

        req.merge(source: req[:source].merge(ref: tag_for_latest_version))
      end

      def update_registry_requirement(req)
        return req if req.fetch(:requirement).nil?

        string_req = req.fetch(:requirement).strip
        ruby_req = requirement_class.new(string_req)
        return req if ruby_req.satisfied_by?(latest_version)

        new_req =
          if ruby_req.exact? then latest_version.to_s
          elsif string_req.start_with?("~>")
            update_twiddle_version(string_req).to_s
          else
            update_range(string_req).map(&:to_s).join(", ")
          end

        req.merge(requirement: new_req)
      end

      # Updates the version in a "~>" constraint to allow the given version
      def update_twiddle_version(req_string)
        old_version = requirement_class.new(req_string).
                      requirements.first.last
        updated_version = at_same_precision(latest_version, old_version)
        req_string.sub(old_version.to_s, updated_version)
      end

      def update_range(req_string)
        requirement_class.new(req_string).requirements.flat_map do |r|
          ruby_req = requirement_class.new(r.join(" "))
          next ruby_req if ruby_req.satisfied_by?(latest_version)

          case op = ruby_req.requirements.first.first
          when "<", "<=" then [update_greatest_version(ruby_req, latest_version)]
          when "!=" then []
          else raise "Unexpected operation for unsatisfied req: #{op}"
          end
        end
      end

      def at_same_precision(new_version, old_version)
        release_precision =
          old_version.to_s.split(".").grep(/^\d+$/).count
        prerelease_precision =
          old_version.to_s.split(".").count - release_precision

        new_release =
          new_version.to_s.split(".").first(release_precision)
        new_prerelease =
          new_version.to_s.split(".").
          drop_while { |i| i.match?(/^\d+$/) }.
          first([prerelease_precision, 1].max)

        [*new_release, *new_prerelease].join(".")
      end

      # Updates the version in a "<" or "<=" constraint to allow the given
      # version
      def update_greatest_version(requirement, version_to_be_permitted)
        if version_to_be_permitted.is_a?(String)
          version_to_be_permitted =
            version_class.new(version_to_be_permitted)
        end
        op, version = requirement.requirements.first
        version = version.release if version.prerelease?

        index_to_update =
          version.segments.map.with_index { |seg, i| seg.zero? ? 0 : i }.max

        new_segments = version.segments.map.with_index do |_, index|
          if index < index_to_update
            version_to_be_permitted.segments[index]
          elsif index == index_to_update
            version_to_be_permitted.segments[index] + 1
          else
            0
          end
        end

        requirement_class.new("#{op} #{new_segments.join('.')}")
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
