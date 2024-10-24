# typed: strong
# frozen_string_literal: true

require "digest"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_creator/branch_namer/solo_strategy"
require "dependabot/pull_request_creator/branch_namer/dependency_group_strategy"

module Dependabot
  class PullRequestCreator
    class BranchNamer
      extend T::Sig

      sig { returns(T::Array[Dependabot::Dependency]) }
      attr_reader :dependencies

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :files

      sig { returns(T.nilable(String)) }
      attr_reader :target_branch

      sig { returns(T::Array[String]) }
      attr_reader :existing_branches

      sig { returns(String) }
      attr_reader :separator

      sig { returns(String) }
      attr_reader :prefix

      sig { returns(T.nilable(Integer)) }
      attr_reader :max_length

      sig { returns(T.nilable(Dependabot::DependencyGroup)) }
      attr_reader :dependency_group

      sig { returns(T::Boolean) }
      attr_reader :includes_security_fixes

      sig do
        params(
          dependencies: T::Array[Dependabot::Dependency],
          files: T::Array[Dependabot::DependencyFile],
          target_branch: T.nilable(String),
          dependency_group: T.nilable(Dependabot::DependencyGroup),
          existing_branches: T::Array[String],
          separator: String,
          prefix: String,
          max_length: T.nilable(Integer),
          includes_security_fixes: T::Boolean
        )
          .void
      end
      def initialize(dependencies:, files:, target_branch:, dependency_group: nil, existing_branches: [],
                     separator: "/", prefix: "dependabot", max_length: nil, includes_security_fixes: false)
        @dependencies  = dependencies
        @files         = files
        @target_branch = target_branch
        @dependency_group = dependency_group
        @existing_branches = existing_branches
        @separator     = separator
        @prefix        = prefix
        @max_length    = max_length
        @includes_security_fixes = includes_security_fixes
      end

      sig { returns(String) }
      def new_branch_name
        strategy.new_branch_name
      end

      private

      sig { returns(Dependabot::PullRequestCreator::BranchNamer::Base) }
      def strategy
        if Dependabot::Experiments.enabled?(:dedup_branch_names) && existing_branches
          Dependabot.logger.info(
            "Dependabot::PullRequestCreator::strategy : #{existing_branches}"
          )
        end

        @strategy ||= T.let(
          if dependency_group.nil?
            SoloStrategy.new(
              dependencies: dependencies,
              files: files,
              target_branch: target_branch,
              existing_branches: existing_branches,
              separator: separator,
              prefix: prefix,
              max_length: max_length
            )
          else
            DependencyGroupStrategy.new(
              dependencies: dependencies,
              files: files,
              target_branch: target_branch,
              dependency_group: T.must(dependency_group),
              includes_security_fixes: includes_security_fixes,
              existing_branches: existing_branches,
              separator: separator,
              prefix: prefix,
              max_length: max_length
            )
          end,
          T.nilable(Dependabot::PullRequestCreator::BranchNamer::Base)
        )
      end
    end
  end
end
