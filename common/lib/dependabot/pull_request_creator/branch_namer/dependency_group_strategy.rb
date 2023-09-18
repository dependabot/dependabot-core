# typed: true
# frozen_string_literal: true

require "dependabot/pull_request_creator/branch_namer/base"

module Dependabot
  class PullRequestCreator
    class BranchNamer
      class DependencyGroupStrategy < Base
        def initialize(dependencies:, files:, target_branch:, dependency_group:,
                       separator: "/", prefix: "dependabot", max_length: nil)
          super(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            separator: separator,
            prefix: prefix,
            max_length: max_length
          )

          @dependency_group = dependency_group
        end

        def new_branch_name
          sanitize_branch_name(File.join(prefixes, group_name_with_dependency_digest))
        end

        private

        attr_reader :dependency_group

        def prefixes
          [
            prefix,
            package_manager,
            directory,
            target_branch
          ].compact
        end

        # Group pull requests will generally include too many dependencies to include
        # in the branch name, but we rely on branch names being deterministic for a
        # given set of dependency changes.
        #
        # Let's append a short hash digest of the dependency changes so that we can
        # meet this guarantee.
        def group_name_with_dependency_digest
          "#{dependency_group.name}-#{dependency_digest}"
        end

        def dependency_digest
          @dependency_digest ||= Digest::MD5.hexdigest(dependencies.map do |dependency|
            "#{dependency.name}-#{dependency.removed? ? 'removed' : dependency.version}"
          end.sort.join(",")).slice(0, 10)
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
