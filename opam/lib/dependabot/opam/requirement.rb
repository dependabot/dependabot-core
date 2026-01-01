# typed: strict
# frozen_string_literal: true

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/opam/version"

module Dependabot
  module Opam
    # OCaml opam requirement class
    # Handles version constraints in opam format
    # Examples: >= "4.08", < "5.0", >= "1.0" & < "2.0"
    class Requirement < Dependabot::Requirement
      extend T::Sig

      # Opam supports: =, !=, <, <=, >, >=
      OPS = T.let(
        {
          "=" => ->(v, r) { v == r },
          "!=" => ->(v, r) { v != r },
          ">" => ->(v, r) { v > r },
          "<" => ->(v, r) { v < r },
          ">=" => ->(v, r) { v >= r },
          "<=" => ->(v, r) { v <= r }
        }.freeze,
        T::Hash[String, T.proc.params(v: Dependabot::Version, r: Dependabot::Version).returns(T::Boolean)]
      )

      # Mapping from opam operators to Gem::Requirement operators
      OPERATOR_MAPPING = T.let(
        {
          "=" => "=",
          "!=" => "!=",
          ">" => ">",
          "<" => "<",
          ">=" => ">=",
          "<=" => "<="
        }.freeze,
        T::Hash[String, String]
      )

      sig { override.params(obj: T.untyped).returns(T::Array[Dependabot::Opam::Requirement]) }
      def self.requirements_array(obj)
        case obj
        when Gem::Requirement
          obj.requirements.map { |r| new(r.join(" ")) }
        when String
          [new(obj)]
        else
          [new("= #{obj}")]
        end
      end

      sig { params(string: String).returns(T::Array[[String, Dependabot::Version]]) }
      def self.parse_requirements_string(string)
        # Remove quotes from opam requirements
        string = string.delete('"').strip

        # Split on & for AND conditions
        requirements = string.split("&").map(&:strip)

        requirements.map do |req|
          req = req.strip
          match = req.match(/^([><=!]+)\s*(.+)$/)

          if match
            operator = match[1]
            version = match[2].strip

            # Map opam operator to Gem::Requirement operator
            gem_operator = OPERATOR_MAPPING[operator] || operator
            [gem_operator, Dependabot::Opam::Version.new(version)]
          else
            # No operator means exact version
            ["=", Dependabot::Opam::Version.new(req)]
          end
        end
      end

      sig { override.params(requirements: T.nilable(T.any(String, T::Array[T.untyped]))).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          # Split on both comma and ampersand (opam uses & for AND)
          req_string.split(/[,&]/).map(&:strip)
        end

        # Filter out platform/os constraints (e.g., "!= win32", "os != macos")
        # Only keep version constraints that match pattern: operator + optional quotes + version number
        requirements = requirements.select do |req|
          req.match?(/^[><=!]+\s*"?\d+/)
        end

        # Remove quotes from version constraints (opam uses quotes, Gem::Requirement doesn't)
        requirements = requirements.map { |req| req.delete('"') }

        # If no valid version requirements, default to ">= 0"
        requirements = [">= 0"] if requirements.empty?

        super(requirements)
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("opam", Dependabot::Opam::Requirement)
