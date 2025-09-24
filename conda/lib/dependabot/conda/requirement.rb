# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirement"
require "dependabot/python/version"
require "dependabot/conda/version"

module Dependabot
  module Conda
    class Requirement < Dependabot::Requirement
      extend T::Sig

      # Conda uses different operators than pip:
      # conda: =, >=, >, <, <=, !=, ~
      # pip: ==, >=, >, <, <=, !=, ~=

      # Support both conda and pip operators
      OPS = T.let(
        OPS.merge(
          "=" => ->(v, r) { v == r },         # conda equality
          "==" => ->(v, r) { v == r },        # pip equality
          "~=" => ->(v, r) { v >= r && v.release < r.bump } # pip compatible release
        ),
        T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)]
      )

      quoted = OPS.keys.sort_by(&:length).reverse
                  .map { |k| Regexp.quote(k) }.join("|")
      # Use Python version pattern since conda version inherits from it
      version_pattern = Dependabot::Python::Version::VERSION_PATTERN

      PATTERN_RAW = T.let("\\s*(?<op>#{quoted})?\\s*(?<version>#{version_pattern})\\s*".freeze, String)
      PATTERN = T.let(/\A#{PATTERN_RAW}\z/, Regexp)

      sig { params(obj: T.any(Gem::Version, String)).returns([String, Gem::Version]) }
      def self.parse(obj)
        return ["=", obj] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[:op] == ">=" && matches[:version] == "0"

        [matches[:op] || "=", Dependabot::Conda::Version.new(T.must(matches[:version]))]
      end

      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        return [new(nil)] if requirement_string.nil?

        # Handle complex requirements like ">=1.0.0,<2.0.0"
        requirement_string.strip.split(",").map do |req_string|
          new(req_string.strip)
        end
      end

      sig { params(requirements: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(*requirements)
        @original_string = T.let(requirements.first&.to_s, T.nilable(String))

        requirements = requirements.flatten.flat_map do |req_string|
          next if req_string.nil?

          # Handle complex requirements and convert to Ruby-compatible format
          req_string.split(",").map(&:strip).map do |r|
            convert_conda_constraint_to_ruby_constraint(r)
          end
        end.compact

        super(requirements)
      end

      sig { params(version: T.any(Gem::Version, String)).returns(T::Boolean) }
      def satisfied_by?(version)
        version = Dependabot::Conda::Version.new(version.to_s)

        requirements.all? { |op, rv| T.must(OPS[op] || OPS["="]).call(version, rv) }
      end

      sig { returns(T::Boolean) }
      def exact?
        return false unless requirements.size == 1

        %w(= == ===).include?(requirements[0][0])
      end

      sig { returns(String) }
      def to_s
        @original_string || super
      end

      private

      sig { params(req_string: String).returns(T.nilable(T.any(String, T::Array[String]))) }
      def convert_conda_constraint_to_ruby_constraint(req_string)
        return nil if req_string.strip.empty?
        return nil if req_string == "*"

        # Handle conda wildcard patterns like "=1.2.*"
        return convert_wildcard_requirement(req_string) if req_string.match?(/=\s*\d+(\.\d+)*\.\*/)

        # Handle pip-style compatible release operator
        req_string = req_string.gsub("~=", "~>") if req_string.include?("~=")

        # Convert conda single = to Ruby = for internal processing
        req_string
      end

      sig { params(req_string: String).returns(T.any(String, T::Array[String])) }
      def convert_wildcard_requirement(req_string)
        # Convert "=1.2.*" to appropriate range constraints
        version_part = req_string.gsub(/^=\s*/, "").gsub(/\.\*$/, "")
        parts = version_part.split(".")

        if parts.length == 1
          # "=1.*" becomes ">= 1.0.0, < 2.0.0"
          major = parts[0].to_i
          [">= #{major}.0.0", "< #{major + 1}.0.0"]
        elsif parts.length == 2
          # "=1.2.*" becomes ">= 1.2.0, < 1.3.0"
          major = parts[0].to_i
          minor = parts[1].to_i
          [">= #{major}.#{minor}.0", "< #{major}.#{minor + 1}.0"]
        else
          # Fallback to exact match without wildcard
          "= #{version_part}.0"
        end
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("conda", Dependabot::Conda::Requirement)
