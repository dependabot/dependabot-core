# typed: true
# frozen_string_literal: true

# Resolves the Bundler version constraint that the native helper should use
# at activation time. Honors DEPENDABOT_BUNDLER_VERSION_CONSTRAINT, falling
# back to BUNDLER_VERSION_CONSTRAINT, and finally to the supplied default.
#
# Used by both `run.rb` (for activation via `gem`) and the helper specs so
# the rollback/staged-rollout behavior is exercised by real code.
module BundlerVersionConstraint
  DEFAULT_ACTIVATION_CONSTRAINT = ">= 4, < 5"

  def self.resolve(env: ENV, default: DEFAULT_ACTIVATION_CONSTRAINT)
    env.fetch(
      "DEPENDABOT_BUNDLER_VERSION_CONSTRAINT",
      env.fetch("BUNDLER_VERSION_CONSTRAINT", default)
    )
  end

  # Splits a comma-separated requirement string into the individual clauses
  # accepted by Kernel#gem (e.g. ">= 2.4, < 5" -> [">= 2.4", "< 5"]).
  def self.activation_clauses(constraint)
    constraint.split(",").map(&:strip)
  end
end
