# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/uv/version"

module Dependabot
  module Uv
    class Requirement < Dependabot::Requirement
      extend T::Sig

      OR_SEPARATOR = T.let(/(?<=[a-zA-Z0-9)*])\s*\|+/, Regexp)

      # Add equality and arbitrary-equality matchers
      OPS = T.let(OPS.merge(
                    "==" => ->(v, r) { v == r },
                    "===" => ->(v, r) { v.to_s == r.to_s }
                  ), T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)])

      quoted = OPS.keys.sort_by(&:length).reverse
                  .map { |k| Regexp.quote(k) }.join("|")
      version_pattern = Uv::Version::VERSION_PATTERN

      PATTERN_RAW = T.let("\\s*(?<op>#{quoted})?\\s*(?<version>#{version_pattern})\\s*".freeze, String)
      PATTERN = T.let(/\A#{PATTERN_RAW}\z/, Regexp)
      PARENS_PATTERN = T.let(/\A\(([^)]+)\)\z/, Regexp)

      sig { params(obj: T.any(Gem::Version, String)).returns([String, Gem::Version]) }
      def self.parse(obj)
        return ["=", Uv::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        line = obj.to_s
        if (matches = PARENS_PATTERN.match(line))
          line = matches[1]
        end

        unless (matches = PATTERN.match(line))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[:op] == ">=" && matches[:version] == "0"

        [matches[:op] || "=", Uv::Version.new(T.must(matches[:version]))]
      end

      # Returns an array of requirements. At least one requirement from the
      # returned array must be satisfied for a version to be valid.
      #
      # NOTE: Or requirements are only valid for Poetry.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        return [new(nil)] if requirement_string.nil?

        if (matches = PARENS_PATTERN.match(requirement_string))
          requirement_string = matches[1]
        end

        T.must(requirement_string).strip.split(OR_SEPARATOR).map do |req_string|
          new(req_string.strip)
        end
      end

      sig { params(requirements: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          next if req_string.nil?

          # Standard python doesn't support whitespace in requirements, but Poetry does.
          req_string = req_string.gsub(/(\d +)([<=>])/, '\1,\2')

          req_string.split(",").map(&:strip).map do |r|
            convert_python_constraint_to_ruby_constraint(r)
          end
        end

        super(requirements)
      end

      sig { params(version: T.any(Gem::Version, String)).returns(T::Boolean) }
      def satisfied_by?(version)
        version = Uv::Version.new(version.to_s)

        requirements.all? { |op, rv| T.must(OPS[op] || OPS["="]).call(version, rv) }
      end

      sig { returns(T::Boolean) }
      def exact?
        return false unless requirements.size == 1

        %w(= == ===).include?(requirements[0][0])
      end

      private

      sig { params(req_string: T.nilable(String)).returns(T.nilable(T.any(String, T::Array[String]))) }
      def convert_python_constraint_to_ruby_constraint(req_string)
        return nil if req_string.nil? || req_string.strip.empty?
        return nil if req_string == "*"

        req_string = req_string.gsub("~=", "~>")
        req_string = req_string.gsub(/(?<=\d)[<=>].*\Z/, "")

        if req_string.match?(/~[^>]/) then convert_tilde_req(req_string)
        elsif req_string.start_with?("^") then convert_caret_req(req_string)
        elsif req_string.match?(/^=?={0,2}\s*\d+\.\d+(\.\d+)?(-[a-z0-9.-]+)?(\.\*)?$/i)
          convert_exact(req_string)
        elsif req_string.include?(".*") then convert_wildcard(req_string)
        else
          req_string
        end
      end

      # Poetry uses ~ requirements.
      # https://github.com/sdispater/poetry#tilde-requirements
      sig { params(req_string: String).returns(String) }
      def convert_tilde_req(req_string)
        version = req_string.gsub(/^~\>?/, "")
        parts = version.split(".")
        parts << "0" if parts.count < 3
        "~> #{parts.join('.')}"
      end

      # Poetry uses ^ requirements
      # https://github.com/sdispater/poetry#caret-requirement
      sig { params(req_string: String).returns(T::Array[String]) }
      def convert_caret_req(req_string)
        version = req_string.gsub(/^\^/, "")
        parts = version.split(".")
        parts.fill("0", parts.length...3)
        first_non_zero = parts.find { |d| d != "0" }
        first_non_zero_index =
          first_non_zero ? parts.index(first_non_zero) : parts.count - 1
        upper_bound = parts.map.with_index do |part, i|
          if i < T.must(first_non_zero_index) then part
          elsif i == first_non_zero_index then (part.to_i + 1).to_s
          # .dev has lowest precedence: https://packaging.python.org/en/latest/specifications/version-specifiers/#summary-of-permitted-suffixes-and-relative-ordering
          elsif i > T.must(first_non_zero_index) && i == 2 then "0.dev"
          else
            "0"
          end
        end.join(".")

        [">= #{version}", "< #{upper_bound}"]
      end

      sig { params(req_string: String).returns(String) }
      def convert_wildcard(req_string)
        # NOTE: This isn't perfect. It replaces the "!= 1.0.*" case with
        # "!= 1.0.0". There's no way to model this correctly in Ruby :'(
        quoted_ops = OPS.keys.sort_by(&:length).reverse
                        .map { |k| Regexp.quote(k) }.join("|")
        op_match = req_string.match(/\A\s*(#{quoted_ops})?/)
        op = op_match&.captures&.first.to_s.strip
        exact_op = ["", "=", "==", "==="].include?(op)

        req_string.strip
                  .split(".")
                  .first(T.must(req_string.split(".").index { |s| s.include?("*") }) + 1)
                  .join(".")
                  .gsub(/\*(?!$)/, "0")
                  .gsub(/\*$/, "0.dev")
                  .tap { |s| exact_op ? s.gsub!(/^(?<!!)=*/, "~>") : s }
      end

      sig { params(req_string: String).returns(T.any(String, T::Array[String])) }
      def convert_exact(req_string)
        arbitrary_equality = req_string.start_with?("===")
        cleaned_version = req_string.gsub(/^=+/, "").strip

        return ["=== #{cleaned_version}"] if arbitrary_equality

        # Handle versions wildcarded with .*, e.g. 1.0.*
        if cleaned_version.include?(".*")
          # Remove all characters after the first .*, and the .*
          cleaned_version = cleaned_version.split(".*").first
          version = Version.new(cleaned_version)
          # Get the release segment parts [major, minor, patch]
          version_parts = version.release_segment

          if version_parts.length == 1
            major = T.must(version_parts[0])
            [">= #{major}.0.0.dev", "< #{major + 1}.0.0"]
          elsif version_parts.length == 2
            major, minor = version_parts
            "~> #{major}.#{minor}.0.dev"
          elsif version_parts.length == 3
            major, minor, patch = version_parts
            "~> #{major}.#{minor}.#{patch}.dev"
          else
            "= #{cleaned_version}"
          end
        else
          "= #{cleaned_version}"
        end
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("uv", Dependabot::Uv::Requirement)
