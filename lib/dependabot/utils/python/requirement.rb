# frozen_string_literal: true

require "dependabot/utils/python/version"

module Dependabot
  module Utils
    module Python
      class Requirement < Gem::Requirement
        OR_SEPARATOR = /(?<=[a-zA-Z0-9*])\s*\|+/

        # Add equality and arbitrary-equality matchers
        OPS["=="] = ->(v, r) { v == r }
        OPS["==="] = ->(v, r) { v.to_s == r.to_s }

        quoted = OPS.keys.sort_by(&:length).reverse.
                 map { |k| Regexp.quote(k) }.join("|")
        version_pattern = Utils::Python::Version::VERSION_PATTERN

        PATTERN_RAW = "\\s*(#{quoted})?\\s*(#{version_pattern})\\s*"
        PATTERN = /\A#{PATTERN_RAW}\z/

        def self.parse(obj)
          if obj.is_a?(Gem::Version)
            return ["=", Utils::Python::Version.new(obj.to_s)]
          end

          unless (matches = PATTERN.match(obj.to_s))
            msg = "Illformed requirement [#{obj.inspect}]"
            raise BadRequirementError, msg
          end

          return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"
          [matches[1] || "=", Utils::Python::Version.new(matches[2])]
        end

        # Returns an array of requirements. At least one requirement from the
        # returned array must be satisfied for a version to be valid.
        #
        # NOTE: Or requirements are only valid for Poetry.
        def self.requirements_array(requirement_string)
          return [new(nil)] if requirement_string.nil?
          requirement_string.strip.split(OR_SEPARATOR).map do |req_string|
            new(req_string.strip)
          end
        end

        def initialize(*requirements)
          requirements = requirements.flatten.flat_map do |req_string|
            next if req_string.nil?
            req_string.split(",").map do |r|
              convert_python_constraint_to_ruby_constraint(r)
            end
          end

          super(requirements)
        end

        def satisfied_by?(version)
          version = Utils::Python::Version.new(version.to_s)
          super
        end

        def exact?
          return false unless @requirements.size == 1
          %w(= == ===).include?(@requirements[0][0])
        end

        private

        def convert_python_constraint_to_ruby_constraint(req_string)
          return nil if req_string.nil?
          return nil if req_string == "*"
          req_string = req_string.gsub("~=", "~>")
          req_string = req_string.gsub(/(?<=\d)[<=>].*/, "")

          if req_string.match?(/~[^>]/) then convert_tilde_req(req_string)
          elsif req_string.start_with?("^") then convert_caret_req(req_string)
          elsif req_string.include?(".*") then convert_wildcard(req_string)
          else req_string
          end
        end

        # Poetry uses ~ requirements.
        # https://github.com/sdispater/poetry#tilde-requirements
        def convert_tilde_req(req_string)
          version = req_string.gsub(/^~\>?/, "")
          parts = version.split(".")
          parts << "0" if parts.count < 3
          "~> #{parts.join('.')}"
        end

        # Poetry uses ^ requirements
        # https://github.com/sdispater/poetry#caret-requirement
        def convert_caret_req(req_string)
          version = req_string.gsub(/^\^/, "")
          parts = version.split(".")
          parts = parts.fill(0, parts.length...3)
          first_non_zero = parts.find { |d| d != "0" }
          first_non_zero_index =
            first_non_zero ? parts.index(first_non_zero) : parts.count - 1
          upper_bound = parts.map.with_index do |part, i|
            if i < first_non_zero_index then part
            elsif i == first_non_zero_index then (part.to_i + 1).to_s
            elsif i > first_non_zero_index && i == 2 then "0.a"
            else 0
            end
          end.join(".")

          [">= #{version}", "< #{upper_bound}"]
        end

        def convert_wildcard(req_string)
          # Note: This isn't perfect. It replaces the "!= 1.0.*" case with
          # "!= 1.0.0". There's no way to model this correctly in Ruby :'(
          req_string.
            split(".").
            first(req_string.split(".").index("*") + 1).
            join(".").
            tr("*", "0").
            gsub(/^(?<!!)=*/, "~>")
        end
      end
    end
  end
end
