# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pre_commit/additional_dependency_parsers/base"

module Dependabot
  module PreCommit
    # Registry for additional_dependency parsers by language.
    # Similar pattern to AdditionalDependencyCheckers but for parsing dependency strings.
    #
    # Usage:
    #   parser = AdditionalDependencyParsers.for_language("python")
    #   dependency = parser.parse(dep_string: "flake8>=3.0", ...)
    #
    module AdditionalDependencyParsers
      extend T::Sig

      @parsers = T.let({}, T::Hash[String, T.class_of(Base)])

      sig { params(language: String).returns(T.class_of(Base)) }
      def self.for_language(language)
        parser = @parsers[language.downcase]
        return parser if parser

        raise "Unsupported language for additional_dependencies parsing: #{language}"
      end

      sig { params(language: String, parser: T.class_of(Base)).void }
      def self.register(language, parser)
        @parsers[language.downcase] = parser
      end

      sig { params(language: String).returns(T::Boolean) }
      def self.supported?(language)
        @parsers.key?(language.downcase)
      end

      sig { returns(T::Array[String]) }
      def self.supported_languages
        @parsers.keys
      end
    end
  end
end
