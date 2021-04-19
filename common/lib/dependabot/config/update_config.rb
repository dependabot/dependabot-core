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

      def initialize(config)
        @config = config || {}
      end

      def ignored_versions_for(dep)
        return [] unless @config[:ignore]

        @config[:ignore].
          select { |ic| ic[:"dependency-name"] == dep.name }. # FIXME: wildcard support
          map { |ic| ic[:versions] }.
          flatten
      end

      def commit_message_options
        commit_message = @config[:"commit-message"] || {}
        {
          prefix: commit_message[:prefix],
          prefix_development: commit_message[:"prefix-development"],
          include_scope: commit_message[:include] == "scope"
        }
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
    end
  end
end
