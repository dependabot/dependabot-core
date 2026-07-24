# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/github_actions/constants"

module Dependabot
  module GithubActions
    module Lockfile
      # Lockfile schema version this ecosystem does not understand. Hard error so we
      # never half-write an incompatible lockfile.
      class UnsupportedLockfileVersion < Dependabot::DependencyFileNotParseable
        extend T::Sig

        sig { returns(String) }
        attr_reader :found, :supported

        sig { params(found: String, supported: String).void }
        def initialize(found, supported)
          @found = found
          @supported = supported
          super(
            LOCKFILE_PATH,
            "Unsupported actions.lock version #{found.inspect}; " \
            "this version of Dependabot supports #{supported.inspect}. " \
            "Upgrade the gh-actions-lock engine or regenerate the lockfile."
          )
        end
      end

      # Engine could not resolve a dependency (often a transitive action the job
      # token cannot reach). We refuse to emit a partial lockfile.
      class UnresolvableDependency < Dependabot::DependencyFileNotResolvable
        extend T::Sig

        sig { returns(String) }
        attr_reader :dependency, :detail

        sig { params(dependency: String, detail: String).void }
        def initialize(dependency, detail)
          @dependency = dependency
          @detail = detail
          super("Could not resolve #{dependency}: #{detail}")
        end
      end

      # Engine itself failed (binary missing, tool failure, unparseable JSON).
      class EngineError < Dependabot::DependabotError; end
    end
  end
end
