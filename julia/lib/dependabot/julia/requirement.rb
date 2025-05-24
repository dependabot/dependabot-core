# typed: strict
# frozen_string_literal: true

require "dependabot/requirement"

module Dependabot
  module Julia
    class Requirement < Dependabot::Requirement
      AND_SEPARATOR = /(?<=[a-zA-Z0-9*])\s*,\s*/i
      OR_SEPARATOR = /(?<=[a-zA-Z0-9*])\s*\|\|\s*/i

      def self.requirements_array(requirement_string)
        return [new(nil)] if requirement_string.nil?
        return [new(requirement_string.to_s)] if requirement_string.is_a?(Gem::Version)

        requirement_string.strip.split(OR_SEPARATOR).map do |req_string|
          reqs = req_string.strip.split(AND_SEPARATOR).map { |r| new(r) }
          reqs.length > 1 ? reqs.reduce(&:merge) : reqs.first
        end
      end

      # Overwrite the parent requirement pattern to include ~ operator
      PATTERN_RAW = "([<>]=?|=|~|\\^)?\\s*([0-9]+(?:[-\\.][A-Za-z0-9]+)*)"

      def self.normalize_version(version)
        version = version.gsub(/^v/, "") if version.is_a?(String)
        version = version.gsub(/^[=v]/, "").strip if version.is_a?(String)
        return version if version.nil? || version == ""

        version
      end

      def initialize(*requirements)
        requirements = requirements.flatten.map do |req_string|
          next if req_string.nil?

          req_string = req_string.to_s
          req_string = req_string.gsub(/^=\s*/, "")
          req_string = convert_tilde_req(req_string)
          req_string = convert_caret_req(req_string)
          req_string = convert_wildcard_req(req_string)
          req_string
        end.compact

        super(requirements)
      end

      private

      def convert_tilde_req(req_string)
        return req_string unless req_string.start_with?("~")

        version = req_string.gsub(/^~\s*/, "")
        parts = version.split(".")
        format(">= #{version}, < #{parts[0]}.#{parts[1].to_i + 1}.0")
      end

      def convert_caret_req(req_string)
        return req_string unless req_string.start_with?("^")

        version = req_string.gsub(/^\^\s*/, "")
        parts = version.split(".")

        upper_bound = if parts[0] == "0"
          ">= #{version}, < 0.#{parts[1].to_i + 1}.0"
        else
          ">= #{version}, < #{parts[0].to_i + 1}.0.0"
        end

        format(upper_bound)
      end

      def convert_wildcard_req(req_string)
        return req_string unless req_string.include?("*")

        version = req_string.gsub(/\*/, "0")
        next_version = req_string.gsub(/\*/) { |_| "1" }

        format(">= #{version}, < #{next_version}")
      end
    end
  end
end
