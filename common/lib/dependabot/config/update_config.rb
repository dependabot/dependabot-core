# frozen_string_literal: true

module Dependabot
  module Config
    # Configuration for a single ecosystem
    class UpdateConfig
      module Interval
        DAILY = "daily"
        WEEKLY = "weekly"
        MONTHLY = "monthly"
      end

      attr_reader :commit_message_options

      def initialize(config, commit_message_options: nil)
        @config = config || {}
        @commit_message_options = commit_message_options
      end

      def ignored_versions_for(dep)
        return [] unless @config[:ignore]

        @config[:ignore].
          select { |ic| ic[:"dependency-name"] == dep.name }. # FIXME: wildcard support
          map { |ic| ic[:versions] }.
          flatten
      end

      def interval
        return unless @config[:schedule]
        return unless @config[:schedule][:interval]

        interval = @config[:schedule][:interval]
        case interval.downcase
        when Interval::DAILY, Interval::WEEKLY, Interval::MONTHLY
          interval.downcase
        else
          raise InvalidConfigError, "unknown interval: #{interval}"
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
