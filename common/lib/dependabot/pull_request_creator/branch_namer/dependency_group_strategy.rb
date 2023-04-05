# frozen_string_literal: true

module Dependabot
  class PullRequestCreator
    class BranchNamer
      class DependencyGroupStrategy
        def initialize(dependencies:, files:, target_branch:, dependency_group:,
                       separator: "/", prefix: "dependabot", max_length: nil)
          @dependencies     = dependencies
          @files            = files
          @target_branch    = target_branch
          @dependency_group = dependency_group
          @separator        = separator
          @prefix           = prefix
          @max_length       = max_length
        end

        def new_branch_name
          dependency_group.name
        end

        private

        attr_reader :dependency_group
      end
    end
  end
end
