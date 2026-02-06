# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/name_normaliser"
require "dependabot/python/requirement"

module Dependabot
  module Python
    class RequirementParser
      extend T::Sig

      NAME = /[a-zA-Z0-9](?:[a-zA-Z0-9\-_\.]*[a-zA-Z0-9])?/
      EXTRA = /[a-zA-Z0-9\-_\.]+/
      COMPARISON = /===|==|>=|<=|<|>|~=|!=/
      VERSION = /([1-9][0-9]*!)?[0-9]+[a-zA-Z0-9\-_.*]*(\+[0-9a-zA-Z]+(\.[0-9a-zA-Z]+)*)?/

      REQUIREMENT = /(?<comparison>#{COMPARISON})\s*\\?\s*v?(?<version>#{VERSION})/
      HASH = /--hash=(?<algorithm>.*?):(?<hash>.*?)(?=\s|\\|$)/
      REQUIREMENTS = /#{REQUIREMENT}(\s*,\s*\\?\s*#{REQUIREMENT})*/
      HASHES = /#{HASH}(\s*\\?\s*#{HASH})*/
      MARKER_OP = /\s*(#{COMPARISON}|(\s*in)|(\s*not\s*in))/
      PYTHON_STR_C = %r{[a-zA-Z0-9\s\(\)\.\{\}\-_\*#:;/\?\[\]!~`@\$%\^&=\+\|<>]}
      PYTHON_STR = /('(#{PYTHON_STR_C}|")*'|"(#{PYTHON_STR_C}|')*")/
      ENV_VAR =
        /python_version|python_full_version|os_name|sys_platform|
         platform_release|platform_system|platform_version|platform_machine|
         platform_python_implementation|implementation_name|
         implementation_version/x
      MARKER_VAR = /\s*(#{ENV_VAR}|#{PYTHON_STR})/
      MARKER_EXPR_ONE = /#{MARKER_VAR}#{MARKER_OP}#{MARKER_VAR}/
      MARKER_EXPR = /(#{MARKER_EXPR_ONE}|\(\s*|\s*\)|\s+and\s+|\s+or\s+)+/

      INSTALL_REQ_WITH_REQUIREMENT =
        /\s*\\?\s*(?<name>#{NAME})
          \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
          \s*\\?\s*\(?(?<requirements>#{REQUIREMENTS})\)?
          \s*\\?\s*(;\s*(?<markers>#{MARKER_EXPR}))?
          \s*\\?\s*(?<hashes>#{HASHES})?
          \s*#*\s*(?<comment>.+)?
        /x

      INSTALL_REQ_WITHOUT_REQUIREMENT =
        /^\s*\\?\s*(?<name>#{NAME})
          \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
          \s*\\?\s*(;\s*(?<markers>#{MARKER_EXPR}))?
          \s*\\?\s*(?<hashes>#{HASHES})?
          \s*#*\s*(?<comment>.+)?$
        /x

      VALID_REQ_TXT_REQUIREMENT =
        /^\s*\\?\s*(?<name>#{NAME})
          \s*\\?\s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
          \s*\\?\s*\(?(?<requirements>#{REQUIREMENTS})?\)?
          \s*\\?\s*(;\s*(?<markers>#{MARKER_EXPR}))?
          \s*\\?\s*(?<hashes>#{HASHES})?
          \s*(\#+\s*(?<comment>.*))?$
        /x

      NAME_WITH_EXTRAS =
        /\s*\\?\s*(?<name>#{NAME})
          (\s*\\?\s*\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
        /x

      # Parses a single pip requirement string (e.g. "types-requests==2.31.0.10")
      # into a structured hash. Returns nil if the string is not a valid requirement
      # or has no version constraint.
      sig { params(dependency_string: String).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def self.parse(dependency_string)
        match = dependency_string.strip.match(VALID_REQ_TXT_REQUIREMENT)
        return nil unless match

        name = T.must(match[:name])
        requirements_string = match[:requirements]
        return nil if requirements_string.nil? || requirements_string.strip.empty?

        version = extract_pinned_version(requirements_string)
        return nil unless version

        {
          name: name,
          normalised_name: NameNormaliser.normalise(name),
          version: version,
          requirement: requirements_string,
          extras: match[:extras],
          markers: match[:markers]
        }
      end

      # Extracts the pinned or lower-bound version from a requirement string.
      # For "==2.31.0" returns "2.31.0", for ">=1.0,<2.0" returns "1.0".
      sig { params(requirements_string: String).returns(T.nilable(String)) }
      def self.extract_pinned_version(requirements_string)
        requirement = Dependabot::Python::Requirement.new(requirements_string)
        constraints = T.let(requirement.requirements, T::Array[T::Array[T.untyped]])

        exact_pin = constraints.find do |pair|
          op = T.cast(pair[0], String)
          op == "==" || op == "="
        end
        return T.cast(exact_pin[1], Gem::Version).to_s if exact_pin

        lower_bound = constraints.find { |pair| %w(>= > ~>).include?(T.cast(pair[0], String)) }
        return T.cast(lower_bound[1], Gem::Version).to_s if lower_bound

        nil
      rescue Gem::Requirement::BadRequirementError
        fallback = requirements_string.match(/(?:==|>=|~=)\s*(?<version>[^\s,<>!=]+)/)
        fallback ? fallback[:version] : nil
      end

      private_class_method :extract_pinned_version
    end
  end
end
