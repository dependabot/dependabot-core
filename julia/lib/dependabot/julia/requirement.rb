# typed: strong
# frozen_string_literal: true

require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module Julia
    class Requirement < Dependabot::Requirement
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Dependabot::Julia::Requirement]) }
      def self.requirements_array(requirement_string)
        return [] if requirement_string.nil?
        return [] if requirement_string == ""

        requirement_string.split(",").map do |req_string|
          Julia::Requirement.new(req_string.strip)
        rescue Gem::Requirement::BadRequirementError
          Julia::Requirement.new(normalize_version(req_string))
        end
      end

      sig { params(requirement_string: String).returns(T::Array[Dependabot::Julia::Requirement]) }
      def self.parse_requirements(requirement_string)
        reqs = requirements_array(requirement_string)
        # Julia doesn't have a merge operation for requirements yet
        # We'll just return the array for now
        reqs
      end

      sig { params(version: String).returns(String) }
      def self.normalize_version(version)
        if version.match?(/^v\d/)
          version.gsub(/^v/, "")
        elsif !version.match?(/^\d/) && version != ""
          "^#{version}" # Prepend a caret to bare requirements (e.g., '1.2.3' => '^1.2.3')
        else
          version
        end
      end

      private_class_method :normalize_version
    end
  end
end
