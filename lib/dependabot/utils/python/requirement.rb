# frozen_string_literal: true

require "dependabot/utils/python/version"

module Dependabot
  module Utils
    module Python
      class Requirement < Gem::Requirement
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

        # For consistency with other langauges, we define a requirements array.
        # Python doesn't have an `OR` separator for requirements, so it always
        # contains a single element.
        def self.requirements_array(requirement_string)
          [new(requirement_string)]
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
          return req_string unless req_string.include?(".*")

          # Note: This isn't perfect. It replaces the "!= 1.0.*" case with
          # "!= 1.0.0". There's no way to model this correctly in Ruby :'(
          req_string.
            split(".").
            first(req_string.split(".").index("*") + 1).
            join(".").
            tr("*", "0").
            gsub(/^(?<!!)==?/, "~>")
        end
      end
    end
  end
end
