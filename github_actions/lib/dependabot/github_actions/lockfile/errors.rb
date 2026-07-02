# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"

module Dependabot
  module GithubActions
    module Lockfile
      # Lockfile schema version this ecosystem does not understand. Hard error so we
      # never half-write an incompatible lockfile.
      class UnsupportedLockfileVersion < Dependabot::DependabotError
        extend T::Sig

        sig { returns(String) }
        attr_reader :found, :supported

        sig { params(found: String, supported: String).void }
        def initialize(found, supported)
          @found = found
          @supported = supported
          super(
            "Unsupported actions.lock version #{found.inspect}; " \
            "this version of Dependabot supports #{supported.inspect}. " \
            "Upgrade the gh-actions-pin engine or regenerate the lockfile."
          )
        end
      end

      # Engine could not resolve a dependency (often a transitive action the job
      # token cannot reach). We refuse to emit a partial lockfile.
      class UnresolvableDependency < Dependabot::DependabotError
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

      # Translates gh-actions-pin finding categories into Dependabot errors at the
      # relock gate. `findings` is the PRE-fix diagnosis, so a finding's presence does
      # not mean it survived fix-mode: ref-changed/stale/etc. are already resolved on
      # disk. Only impostor-commit and lockfile-forgery (the locked SHA is
      # untrustworthy) block → UnresolvableDependency; everything else returns nil.
      # Blocking is gated on `severity: "error"`.
      module FindingMapper
        extend T::Sig

        # The only categories fix-mode cannot resolve: locked SHA is untrustworthy,
        # so the relock must fail loud. Sole blocking categories at the relock gate.
        UNRESOLVABLE_CATEGORIES = T.let(
          %w(
            impostor-commit
            lockfile-forgery
          ).freeze,
          T::Array[String]
        )

        # Diagnostic categories a `check` fix-mode pass auto-resolves (re-pin / prune /
        # normalize) or refuses-as-skip; non-blocking. Kept as vocabulary docs.
        FIX_MODE_RESOLVED_CATEGORIES = T.let(
          %w(
            not-pinned
            sha-as-ref
            stale
            ref-changed
            ref-moved
            misleading-sha
          ).freeze,
          T::Array[String]
        )

        # Skip-and-log signal, not a blocking category: a targeted workflow has no
        # entry in actions.lock and --no-onboard refuses to add one mid-run.
        ONBOARDING_REQUIRED = "onboarding-required"

        sig { params(finding: T::Hash[String, T.untyped]).returns(T.nilable(Dependabot::DependabotError)) }
        def self.error_for(finding)
          category = category_of(finding)
          return nil unless category

          # onboarding-required is severity:"error" but is a skip; guard before the
          # severity gate so it can never be promoted to a blocking error.
          return nil if onboarding_required?(finding)
          return nil unless blocking_severity?(finding)

          normalized = category.downcase
          dependency = finding["dependency"] || finding["action"] || "unknown"
          detail = detail_of(finding, category)

          return UnresolvableDependency.new(dependency, detail) if UNRESOLVABLE_CATEGORIES.include?(normalized)

          nil
        end

        # severity:"error" but a skip, not a failure: the workflow is simply untracked.
        sig { params(finding: T::Hash[String, T.untyped]).returns(T::Boolean) }
        def self.onboarding_required?(finding)
          category_of(finding)&.downcase == ONBOARDING_REQUIRED
        end

        # Only `error`-severity findings block; a missing field falls back to the
        # category check so known-hard categories still block.
        sig { params(finding: T::Hash[String, T.untyped]).returns(T::Boolean) }
        def self.blocking_severity?(finding)
          severity = finding["severity"]
          return true if severity.nil?

          severity.to_s.casecmp?("error")
        end

        sig { params(finding: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
        def self.category_of(finding)
          value = finding["category"] || finding["kind"] || finding["type"]
          value&.to_s
        end

        sig { params(finding: T::Hash[String, T.untyped], category: String).returns(String) }
        def self.detail_of(finding, category)
          finding["detail"] || finding["details"] || finding["unreachable_detail"] || category
        end
      end
    end
  end
end
