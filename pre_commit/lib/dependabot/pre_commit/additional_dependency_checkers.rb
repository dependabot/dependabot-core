# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pre_commit/additional_dependency_checkers/base"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      extend T::Sig

      @checkers = T.let({}, T::Hash[String, T.class_of(Base)])

      sig { params(language: String).returns(T.class_of(Base)) }
      def self.for_language(language)
        checker = @checkers[language.downcase]
        return checker if checker

        raise "Unsupported language for additional_dependencies: #{language}"
      end

      sig { params(language: String, checker: T.class_of(Base)).void }
      def self.register(language, checker)
        @checkers[language.downcase] = checker
      end

      sig { params(language: String).returns(T::Boolean) }
      def self.supported?(language)
        @checkers.key?(language.downcase)
      end

      sig { returns(T::Array[String]) }
      def self.supported_languages
        @checkers.keys
      end
    end
  end
end
