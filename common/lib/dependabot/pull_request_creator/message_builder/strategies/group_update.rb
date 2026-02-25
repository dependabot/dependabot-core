# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/source"
require "dependabot/pull_request_creator/message_builder/strategies/base"
require "dependabot/pull_request_creator/message_builder/strategies/single_update"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Strategies
        # Builds the base PR title for a grouped dependency update.
        class GroupUpdate < Base
          extend T::Sig

          sig { returns(T::Array[Dependabot::Dependency]) }
          attr_reader :dependencies

          sig { returns(T::Array[Dependabot::DependencyFile]) }
          attr_reader :files

          sig { returns(Dependabot::DependencyGroup) }
          attr_reader :dependency_group

          sig { returns(Dependabot::Source) }
          attr_reader :source

          sig do
            params(
              dependencies: T::Array[Dependabot::Dependency],
              files: T::Array[Dependabot::DependencyFile],
              dependency_group: Dependabot::DependencyGroup,
              source: Dependabot::Source
            ).void
          end
          def initialize(dependencies:, files:, dependency_group:, source:)
            @dependencies = dependencies
            @files = files
            @dependency_group = dependency_group
            @source = source
          end

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
              "#{solo_base_title} in the #{dependency_group.name} group"
            else
              "bump the #{dependency_group.name} group#{pr_name_directory} " \
                "with #{updates} update#{'s' if updates > 1}"
            end
          end

          sig { returns(String) }
          def grouped_directory_name
            updates = dependencies.map(&:name).uniq.count
            dir_count = directories_with_updates_count

            if dependencies.one?
              "#{solo_base_title} in the #{dependency_group.name} group across " \
                "#{dir_count} directory"
            else
              dir_label = dir_count > 1 ? "directories" : "directory"
              "bump the #{dependency_group.name} group across #{dir_count} " \
                "#{dir_label} with #{updates} update#{'s' if updates > 1}"
            end
          end

          sig { returns(Integer) }
          def directories_with_updates_count
            dirs_from_deps = dependencies.to_set { |dep| dep.metadata[:directory] }
            T.must(source.directories&.filter { |dir| dirs_from_deps.include?(dir) }).count
          end

          sig { returns(String) }
          def solo_base_title
            SingleUpdate.new(dependencies: dependencies, files: files).base_title
          end

          sig { returns(String) }
          def pr_name_directory
            directory = T.must(files.first).directory
            return "" if directory == "/"

            " in #{directory}"
          end
        end
      end
    end
  end
end
