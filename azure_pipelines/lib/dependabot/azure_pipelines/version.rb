# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module AzurePipelines
    # Azure Pipelines task versions are `major.minor.patch`, but the minor segment is
    # the sprint the task shipped in rather than a semantic minor. Pipelines normally
    # pin only the major (`Maven@4`) and let the agent pick up newer minors and patches
    # on its own, so most versions we deal with have a single segment.
    class Version < Dependabot::Version
      extend T::Sig

      # The number of dot-separated segments, which is how precisely a pipeline has
      # pinned a task. `4` has a precision of 1, `0.3.1` a precision of 3.
      sig { returns(Integer) }
      def precision
        to_semver.split(".").length
      end

      # Drop segments beyond the given precision. Comparing and rendering candidates at
      # the precision of the existing pin is what stops `Maven@4` being "updated" to
      # `Maven@4` just because the newest release happens to be `4.277.0`.
      sig { params(precision: Integer).returns(Dependabot::AzurePipelines::Version) }
      def truncate(precision)
        return self if precision >= self.precision

        Version.new(to_semver.split(".").first(precision).join("."))
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::AzurePipelines::Version) }
      def self.new(version)
        T.cast(super, Dependabot::AzurePipelines::Version)
      end
    end
  end
end

Dependabot::Utils.register_version_class("azure_pipelines", Dependabot::AzurePipelines::Version)
