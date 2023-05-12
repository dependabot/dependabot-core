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

        # FIXME: Incorporate max_length truncation once we allow user config
        #
        # For now, we are using a placeholder DependencyGroup with a
        # fixed-length name, so we can punt on handling truncation until
        # we determine the strict validation rules for names
        def new_branch_name
          File.join(prefixes, timestamped_group_name).gsub("/", separator)
        end

        private

        attr_reader :dependencies, :dependency_group, :files, :target_branch, :separator, :prefix, :max_length

        def prefixes
          [
            prefix,
            package_manager,
            directory,
            target_branch
          ].compact
        end

        # When superseding a grouped update pull request, we will have a period
        # of time when there are two branches for the group so we use a timestamp
        # to avoid collisions.
        def timestamped_group_name
          "#{dependency_group.name}-#{Time.now.utc.to_i}"
        end

        def package_manager
          dependencies.first.package_manager
        end

        def directory
          files.first.directory.tr(" ", "-")
        end
      end
    end
  end
end
