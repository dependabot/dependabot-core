# typed: strict
# frozen_string_literal: true

require "dependabot/pull_request_creator/message_components/pr_title"
require "dependabot/pull_request_creator/message_components/single_update_title"

module Dependabot
  class PullRequestCreator
    module MessageComponents
      # Builds PR title for grouped dependency updates
      class GroupUpdateTitle < PrTitle
        extend T::Sig

        sig { override.returns(String) }
        def base_title
          if source.directories
            grouped_directory_name
          else
            grouped_name
          end
        end

        private

        sig { returns(String) }
        def grouped_name
          updates = dependencies.map(&:name).uniq.count
          if dependencies.one?
            "#{solo_pr_name} in the #{T.must(dependency_group).name} group"
          else
            "bump the #{T.must(dependency_group).name} group#{pr_name_directory} " \
              "with #{updates} update#{'s' if updates > 1}"
          end
        end

        sig { returns(String) }
        def grouped_directory_name
          updates = dependencies.map(&:name).uniq.count

          directories_from_dependencies = dependencies.to_set { |dep| dep.metadata[:directory] }

          directories_with_updates = source.directories&.filter do |directory|
            directories_from_dependencies.include?(directory)
          end

          if dependencies.one?
            "#{solo_pr_name} in the #{T.must(dependency_group).name} group across " \
              "#{T.must(directories_with_updates).count} directory"
          else
            "bump the #{T.must(dependency_group).name} group across #{T.must(directories_with_updates).count} " \
              "#{T.must(directories_with_updates).count > 1 ? 'directories' : 'directory'} " \
              "with #{updates} update#{'s' if updates > 1}"
          end
        end

        sig { returns(String) }
        def solo_pr_name
          # Reuse SingleUpdateTitle for individual dependency names
          single_title_builder = SingleUpdateTitle.new(
            dependencies: dependencies,
            source: source,
            credentials: credentials,
            files: files,
            vulnerabilities_fixed: vulnerabilities_fixed,
            commit_message_options: commit_message_options,
            dependency_group: nil
          )
          single_title_builder.base_title
        end
      end
    end
  end
end
