# typed: strong
# frozen_string_literal: true

require "digest"
require "sorbet-runtime"

require "dependabot/metadata_finders"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_creator/branch_namer/solo_strategy"
require "dependabot/pull_request_creator/branch_namer/dependency_group_strategy"
require "dependabot/pull_request_creator/branch_namer/multi_ecosystem_strategy"
require "dependabot/pull_request_creator/branch_name_template"

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

      sig { returns(String) }
      attr_reader :separator

      sig { returns(String) }
      attr_reader :prefix

      sig { returns(T.nilable(Integer)) }
      attr_reader :max_length

      sig { returns(T.nilable(String)) }
      attr_reader :word_separator

      sig { returns(T.nilable(String)) }
      attr_reader :branch_name_case

      sig { returns(T.nilable(String)) }
      attr_reader :template

      sig { returns(T.nilable(Dependabot::DependencyGroup)) }
      attr_reader :dependency_group

      sig { returns(T::Boolean) }
      attr_reader :includes_security_fixes

      sig { returns(T.nilable(String)) }
      attr_reader :multi_ecosystem_name

      sig do
        params(
          dependencies: T::Array[Dependabot::Dependency],
          files: T::Array[Dependabot::DependencyFile],
          target_branch: T.nilable(String),
          dependency_group: T.nilable(Dependabot::DependencyGroup),
          separator: String,
          prefix: String,
          max_length: T.nilable(Integer),
          word_separator: T.nilable(String),
          branch_name_case: T.nilable(String),
          template: T.nilable(String),
          includes_security_fixes: T::Boolean,
          multi_ecosystem_name: T.nilable(String)
        )
          .void
      end
      def initialize(
        dependencies:,
        files:,
        target_branch:,
        dependency_group: nil,
        separator: "/",
        prefix: "dependabot",
        max_length: nil,
        word_separator: nil,
        branch_name_case: nil,
        template: nil,
        includes_security_fixes: false,
        multi_ecosystem_name: nil
      )
        @dependencies  = dependencies
        @files         = files
        @target_branch = target_branch
        @dependency_group = dependency_group
        @separator     = separator
        @prefix        = prefix
        @max_length    = max_length
        @word_separator = word_separator
        @branch_name_case = branch_name_case
        @template = template
        @includes_security_fixes = includes_security_fixes
        @multi_ecosystem_name = multi_ecosystem_name
      end

      sig { returns(String) }
      def new_branch_name
        strategy.new_branch_name
      end

      private

      sig { returns(Dependabot::PullRequestCreator::BranchNamer::Base) }
      def strategy
        @strategy ||= T.let(
          if multi_ecosystem_name
            build_multi_ecosystem_strategy
          elsif dependency_group.nil?
            build_solo_strategy
          else
            build_dependency_group_strategy
          end,
          T.nilable(Dependabot::PullRequestCreator::BranchNamer::Base)
        )
      end

      sig { returns(Dependabot::PullRequestCreator::BranchNamer::MultiEcosystemStrategy) }
      def build_multi_ecosystem_strategy
        MultiEcosystemStrategy.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch,
          includes_security_fixes: includes_security_fixes,
          separator: separator,
          prefix: prefix,
          max_length: max_length,
          word_separator: word_separator,
          branch_name_case: branch_name_case,
          template: template,
          multi_ecosystem_name: T.must(multi_ecosystem_name)
        )
      end

      sig { returns(Dependabot::PullRequestCreator::BranchNamer::SoloStrategy) }
      def build_solo_strategy
        SoloStrategy.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch,
          separator: separator,
          prefix: prefix,
          max_length: max_length,
          word_separator: word_separator,
          branch_name_case: branch_name_case,
          template: template
        )
      end

      sig { returns(Dependabot::PullRequestCreator::BranchNamer::DependencyGroupStrategy) }
      def build_dependency_group_strategy
        DependencyGroupStrategy.new(
          dependencies: dependencies,
          files: files,
          target_branch: target_branch,
          dependency_group: T.must(dependency_group),
          includes_security_fixes: includes_security_fixes,
          separator: separator,
          prefix: prefix,
          max_length: max_length,
          word_separator: word_separator,
          branch_name_case: branch_name_case,
          template: template
        )
      end
    end
  end
end
