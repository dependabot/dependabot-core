# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/github_actions/lockfile/types"

module Dependabot
  module GithubActions
    module Lockfile
      # Injectable boundary to the gh-actions-pin resolver/rewriter. {CliEngine} is
      # the only implementation; hermetic tests stub {Engine.build} at this boundary.
      class Engine
        extend T::Sig
        extend T::Helpers

        abstract!

        sig do
          params(credentials: T::Array[Dependabot::Credential])
            .returns(Engine)
        end
        def self.build(credentials)
          CliEngine.new(credentials)
        end

        sig { params(credentials: T::Array[Dependabot::Credential]).void }
        def initialize(credentials)
          @credentials = credentials
        end

        # Re-pin the lockfile to match the refs already written into `workflow_files`.
        # Dependabot rewrites the workflow `uses:` refs itself (the regex path) first;
        # the engine only resolves those refs to SHAs and regenerates the lock. No
        # `dependency` target: the engine reads each workflow's actual ref, so divergent
        # per-workflow precision is preserved. Raises {UnresolvableDependency} rather
        # than returning a partial lockfile.
        sig do
          abstract
            .params(
              workflow_files: T::Array[Dependabot::DependencyFile],
              lockfile: Dependabot::DependencyFile
            )
            .returns(RelockResult)
        end
        def relock(workflow_files:, lockfile:); end

        private

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
      end
    end
  end
end
