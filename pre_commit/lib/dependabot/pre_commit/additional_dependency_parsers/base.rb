# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"

module Dependabot
  module PreCommit
    module AdditionalDependencyParsers
      # Abstract base class for language-specific additional_dependency parsers.
      # Each language implementation should inherit from this class and implement
      # the abstract methods.
      #
      # Example implementation for a new language:
      #
      #   class MyLanguage < Base
      #     def parse
      #       # Parse dep_string and return Dependabot::Dependency
      #       # Use helper methods like build_dependency_name, hook_id, repo_url, etc.
      #     end
      #   end
      #
      #   AdditionalDependencyParsers.register("my_language", MyLanguage)
      #
      class Base
        extend T::Sig
        extend T::Helpers

        abstract!

        sig { params(dep_string: String, hook_id: String, repo_url: String, file_name: String).void }
        def initialize(dep_string:, hook_id:, repo_url:, file_name:)
          @dep_string = dep_string
          @hook_id = hook_id
          @repo_url = repo_url
          @file_name = file_name
        end

        # Parse the dependency string and return a Dependabot::Dependency
        # Returns nil if the dependency string cannot be parsed
        sig { abstract.returns(T.nilable(Dependabot::Dependency)) }
        def parse; end

        # Class method for convenient parsing without instantiation
        sig do
          params(
            dep_string: String,
            hook_id: String,
            repo_url: String,
            file_name: String
          ).returns(T.nilable(Dependabot::Dependency))
        end
        def self.parse(dep_string:, hook_id:, repo_url:, file_name:)
          new(
            dep_string: dep_string,
            hook_id: hook_id,
            repo_url: repo_url,
            file_name: file_name
          ).parse
        end

        private

        sig { returns(String) }
        attr_reader :dep_string

        sig { returns(String) }
        attr_reader :hook_id

        sig { returns(String) }
        attr_reader :repo_url

        sig { returns(String) }
        attr_reader :file_name

        # Build a unique dependency name that includes context
        # Format: repo_url::hook_id::package_name
        #
        # This ensures that the same package in different hooks can be updated independently:
        # - https://github.com/pre-commit/mirrors-mypy::mypy::flake8
        # - https://github.com/psf/black::black::flake8
        sig { params(package_name: String).returns(String) }
        def build_dependency_name(package_name)
          "#{repo_url}::#{hook_id}::#{package_name}"
        end
      end
    end
  end
end
