# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "base"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Strategies
        # Generates base title for grouped dependency updates
        class GroupUpdate < Base
          sig do
            params(
              dependencies: T::Array[Dependency],
              group_name: String,
              directory: T.nilable(String)
            ).void
          end
          def initialize(dependencies:, group_name:, directory: nil)
            @dependencies = dependencies
            @group_name = group_name
            @directory = directory
          end

          sig { override.returns(String) }
          def base_title
            if @dependencies.one?
              single_dependency_title
            else
              multi_dependency_title
            end
          end

          private

          sig { returns(String) }
          def single_dependency_title
            dep = T.must(@dependencies.first)
            "bump #{dep.display_name} from #{dep.humanized_previous_version} " \
              "to #{dep.humanized_version} in the #{@group_name} group#{directory_suffix}"
          end

          sig { returns(String) }
          def multi_dependency_title
            count = @dependencies.map(&:name).uniq.count
            "bump the #{@group_name} group#{directory_suffix} with #{count} update#{'s' if count > 1}"
          end

          sig { returns(String) }
          def directory_suffix
            return "" unless @directory && @directory != "/"

            " in #{@directory}"
          end
        end
      end
    end
  end
end