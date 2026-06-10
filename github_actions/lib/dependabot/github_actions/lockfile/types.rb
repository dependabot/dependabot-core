# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module GithubActions
    module Lockfile
      # A workflow the engine refused to act on this run, surfaced for observability
      # rather than raised. Today the only reason is `onboarding-required`: no entry
      # in `actions.lock` and no-onboard forbids creating one mid-run. Not a failure.
      class SkippedWorkflow < T::Struct
        extend T::Sig

        const :workflow, String
        const :reason, String
        const :detail, String, default: ""

        sig { params(finding: T::Hash[String, T.untyped]).returns(SkippedWorkflow) }
        def self.from_finding(finding)
          new(
            workflow: (finding["workflow"] || finding["dependency"] || "unknown").to_s,
            reason: (finding["category"] || finding["kind"] || "unknown").to_s,
            detail: (finding["detail"] || finding["details"] || "").to_s
          )
        end
      end

      # Result of regenerating the lockfile. The CLI is the sole writer of the lock and
      # Dependabot owns the workflow YAML, so only lockfile_content comes back.
      # `skipped_workflows` carries un-onboarded workflows the engine declined to touch.
      class RelockResult < T::Struct
        const :lockfile_content, String
        const :skipped_workflows, T::Array[SkippedWorkflow], default: []
      end
    end
  end
end
