# frozen_string_literal: true

require "dependabot/utils/php/version"

module Dependabot
  module Utils
    module Php
      class Requirement < Gem::Requirement
        AND_SEPARATOR = /(?<=[a-zA-Z0-9*])(?<!\sas)[\s,]+(?![\s,]*[|-]|as)/

        def self.parse(obj)
          new_obj = obj.gsub(/@\w+/, "").gsub(/[a-z0-9\-_\.]*\sas\s+/i, "")
          super(new_obj)
        end

        def initialize(*requirements)
          requirements =
            requirements.flatten.
            flat_map { |req_string| req_string.split(AND_SEPARATOR) }.
            flat_map { |req| convert_php_constraint_to_ruby_constraint(req) }

          super(requirements)
        end

        private

        def convert_php_constraint_to_ruby_constraint(req_string)
          req_string = req_string.gsub(/v(?=\d)/, "")

          if req_string.start_with?("*") then ">= 0"
          elsif req_string.include?("*") then convert_wildcard_req(req_string)
          elsif req_string.match?(/^~[^>]/) then convert_tilde_req(req_string)
          elsif req_string.start_with?("^") then convert_caret_req(req_string)
          elsif req_string.match?(/\s-\s/) then convert_hyphen_req(req_string)
          else req_string
          end
        end

        def convert_wildcard_req(req_string)
          version = req_string.gsub(/^~/, "").gsub(/(?:\.|^)\*/, "")
          "~> #{version}.0"
        end

        def convert_tilde_req(req_string)
          version = req_string.gsub(/^~/, "")
          "~> #{version}"
        end

        def convert_caret_req(req_string)
          version = req_string.gsub(/^\^/, "")
          parts = version.split(".")
          first_non_zero = parts.find { |d| d != "0" }
          first_non_zero_index =
            first_non_zero ? parts.index(first_non_zero) : parts.count - 1
          upper_bound = parts.map.with_index do |part, i|
            if i < first_non_zero_index then part
            elsif i == first_non_zero_index then (part.to_i + 1).to_s
            else 0
            end
          end.join(".")

          [">= #{version}", "< #{upper_bound}"]
        end

        def convert_hyphen_req(req_string)
          req_string = req_string
          lower_bound, upper_bound = req_string.split(/\s+-\s+/)
          if upper_bound.split(".").count < 3
            upper_bound_parts = upper_bound.split(".")
            upper_bound_parts[-1] = (upper_bound_parts[-1].to_i + 1).to_s
            upper_bound = upper_bound_parts.join(".")

            [">= #{lower_bound}", "< #{upper_bound}"]
          else
            [">= #{lower_bound}", "<= #{upper_bound}"]
          end
        end
      end
    end
  end
end
