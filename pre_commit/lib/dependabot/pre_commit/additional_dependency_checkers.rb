# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pre_commit/additional_dependency_checkers/base"

module Dependabot
  module PreCommit
    # Registry for additional_dependency update checkers by language.
    # Similar pattern to Dependabot::UpdateCheckers but for pre-commit hook languages.
    #
    # Usage:
    #   checker = AdditionalDependencyCheckers.for_language("python")
    #   latest_version = checker.new(source: source, credentials: credentials).latest_version
    #
    module AdditionalDependencyCheckers
      extend T::Sig

      @checkers = T.let({}, T::Hash[String, T.class_of(Base)])

      sig { params(language: String).returns(T.class_of(Base)) }
      def self.for_language(language)
        checker = @checkers[language]
        return checker if checker

        raise "Unsupported language for additional_dependencies: #{language}"
      end

      sig { params(language: String, checker: T.class_of(Base)).void }
      def self.register(language, checker)
        @checkers[language] = checker
      end

      sig { params(language: String).returns(T::Boolean) }
      def self.supported?(language)
        @checkers.key?(language)
      end

      sig { returns(T::Array[String]) }
      def self.supported_languages
        @checkers.keys
      end
    end
  end
end
