# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    module MessageComponents
      # Base class for all message components
      # Provides common interface and shared functionality
      class Base
        extend T::Sig
        extend T::Helpers

        abstract!

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            source: Dependabot::Source,
            credentials: T::Array[Dependabot::Credential],
            files: T::Array[Dependabot::DependencyFile],
            vulnerabilities_fixed: T::Hash[String, T.untyped],
            commit_message_options: T.nilable(T::Hash[Symbol, T.untyped]),
            dependency_group: T.nilable(Dependabot::DependencyGroup)
          )
            .void
        end
        def initialize(
          dependencies:,
          source:,
          credentials:,
          files: [],
          vulnerabilities_fixed: {},
          commit_message_options: nil,
          dependency_group: nil
        )
          @dependencies = dependencies
          @source = source
          @credentials = credentials
          @files = files
          @vulnerabilities_fixed = vulnerabilities_fixed
          @commit_message_options = commit_message_options
          @dependency_group = dependency_group
        end

        sig { abstract.returns(String) }
        def build; end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(Dependabot::Source) }
        attr_reader :source

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :files

        sig { returns(T::Hash[String, T.untyped]) }
        attr_reader :vulnerabilities_fixed

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        attr_reader :commit_message_options

        sig { returns(T.nilable(Dependabot::DependencyGroup)) }
        attr_reader :dependency_group
      end
    end
  end
end
