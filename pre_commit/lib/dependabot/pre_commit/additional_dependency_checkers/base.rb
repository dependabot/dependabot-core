# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/credential"

module Dependabot
  module PreCommit
    module AdditionalDependencyCheckers
      class Base
        extend T::Sig
        extend T::Helpers

        abstract!

        # Source hash from dependency requirements containing:
        # - :package_name - normalized package name
        # - :original_name - original package name as written
        # - :extras - package extras (e.g., "testing" from package[testing])
        # - :language - the language (python, node, etc.)
        # - :original_string - the full original string
        sig { returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :source

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        attr_reader :requirements

        sig { returns(T.nilable(String)) }
        attr_reader :current_version

        sig do
          params(
            source: T::Hash[Symbol, T.untyped],
            credentials: T::Array[Dependabot::Credential],
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            current_version: T.nilable(String)
          ).void
        end
        def initialize(source:, credentials:, requirements:, current_version:)
          @source = T.let(source, T::Hash[Symbol, T.untyped])
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
          @requirements = T.let(requirements, T::Array[T::Hash[Symbol, T.untyped]])
          @current_version = T.let(current_version, T.nilable(String))
        end

        sig { abstract.returns(T.nilable(String)) }
        def latest_version; end

        sig { abstract.params(latest_version: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def updated_requirements(latest_version); end

        sig { returns(T.nilable(String)) }
        def package_name
          val = source[:package_name]
          val.is_a?(String) ? val : nil
        end

        sig { returns(T.nilable(String)) }
        def original_name
          val = source[:original_name] || source[:package_name]
          val.is_a?(String) ? val : nil
        end

        sig { returns(T.nilable(String)) }
        def extras
          val = source[:extras]
          val.is_a?(String) ? val : nil
        end
      end
    end
  end
end
