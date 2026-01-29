# typed: strong
# frozen_string_literal: true

require "dependabot/pull_request_creator/message_components/pr_title"

module Dependabot
  class PullRequestCreator
    module MessageComponents
      # Generates PR titles for dependency group updates
      class GroupUpdateTitle < PrTitle
        extend T::Sig

        private

        sig { returns(String) }
        def base_title
          updates = dependencies.map(&:name).uniq.count
          group_name = dependency_group_name

          if dependencies.one?
            dep = T.must(dependencies.first)
            "#{solo_title(dep)} in the #{group_name} group#{multi_directory_suffix}"
          else
            "bump the #{group_name} group#{directory_suffix} with #{updates} update#{'s' if updates > 1}"
          end
        end

        sig { params(dep: Dependabot::Dependency).returns(String) }
        def solo_title(dep)
          "bump #{dep.display_name} " \
            "#{from_version_msg(dep.humanized_previous_version)}to #{dep.humanized_version}"
        end

        sig { params(version: T.nilable(String)).returns(String) }
        def from_version_msg(version)
          return "" unless version

          "from #{version} "
        end

        sig { returns(String) }
        def directory_suffix
          return multi_directory_suffix if multi_directory?

          dir = options[:directory]
          return "" unless dir && dir != "/"

          " in #{dir}"
        end

        sig { returns(String) }
        def multi_directory_suffix
          return "" unless multi_directory?

          directories_from_dependencies = dependencies.to_set { |dep| dep.metadata[:directory] }

          directories_with_updates = source.directories&.filter do |directory|
            directories_from_dependencies.include?(directory)
          end

          count = T.must(directories_with_updates).count
          label = count > 1 ? "directories" : "directory"

          if dependencies.one?
          end
          " across #{count} #{label}"
        end

        sig { returns(T::Boolean) }
        def multi_directory?
          !source.directories.nil? && source.directories.any?
        end

        sig { returns(String) }
        def dependency_group_name
          options[:dependency_group]&.name || "dependencies"
        end
      end
    end
  end
end
