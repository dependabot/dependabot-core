# frozen_string_literal: true

module Dependabot
  module Config
    # Configuration for a single ecosystem
    class UpdateConfig
      attr_reader :commit_message_options

      def initialize(ignore_conditions: nil, commit_message_options: nil)
        @ignore_conditions = ignore_conditions || []
        @commit_message_options = commit_message_options
      end

      def ignored_versions_for(dep)
        @ignore_conditions.
          select { |ic| ic.dependency_name == dep.name }. # FIXME: wildcard support
          map(&:versions).
          flatten.
          compact
      end

      class IgnoreCondition
        attr_reader :dependency_name, :versions
        def initialize(dependency_name:, versions:)
          @dependency_name = dependency_name
          @versions = versions
        end
      end

      class CommitMessageOptions
        attr_reader :prefix, :prefix_development, :include

        def initialize(prefix:, prefix_development:, include:)
          @prefix = prefix
          @prefix_development = prefix_development
          @include = include
        end

        def include_scope?
          @include == "scope"
        end

        def to_h
          {
            prefix: @prefix,
            prefix_development: @prefix_development,
            include_scope: include_scope?
          }
        end
      end
    end
  end
end
