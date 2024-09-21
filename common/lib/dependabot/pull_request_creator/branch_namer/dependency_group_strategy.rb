# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/pull_request_creator/branch_namer/base"

module Dependabot
  class PullRequestCreator
    class BranchNamer
      class DependencyGroupStrategy < Base
        extend T::Sig

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            files: T::Array[Dependabot::DependencyFile],
            target_branch: T.nilable(String),
            dependency_group: Dependabot::DependencyGroup,
            includes_security_fixes: T::Boolean,
            existing_branches: T::Array[String],
            separator: String,
            prefix: String,
            max_length: T.nilable(Integer)
          )
            .void
        end
        def initialize(dependencies:, files:, target_branch:, dependency_group:, includes_security_fixes:,
                       existing_branches: [], separator: "/", prefix: "dependabot", max_length: nil)
          super(
            dependencies: dependencies,
            files: files,
            target_branch: target_branch,
            existing_branches: existing_branches,
            separator: separator,
            prefix: prefix,
            max_length: max_length,
          )

          @dependency_group = dependency_group
          @includes_security_fixes = includes_security_fixes
        end

        sig { override.returns(String) }
        def new_branch_name
          sanitize_branch_name(File.join(prefixes, group_name_with_dependency_digest))
        end

        private

        sig { returns(Dependabot::DependencyGroup) }
        attr_reader :dependency_group

        sig { returns(T::Array[String]) }
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
        sig { returns(String) }
        def group_name_with_dependency_digest
          if @includes_security_fixes
            "group-security-#{package_manager}-#{dependency_digest}"
          else
            "#{dependency_group.name}-#{dependency_digest}"
          end
        end

        sig { returns(T.nilable(String)) }
        def dependency_digest
          @dependency_digest ||= T.let(
            Digest::MD5.hexdigest(dependencies.map do |dependency|
                                    "#{dependency.name}-#{dependency.removed? ? 'removed' : dependency.version}"
                                  end.sort.join(",")).slice(0, 10),
            T.nilable(String)
          )
        end

        sig { returns(String) }
        def package_manager
          T.must(dependencies.first).package_manager
        end

        sig { returns(String) }
        def directory
          T.must(files.first).directory.tr(" ", "-")
        end
      end
    end
  end
end
