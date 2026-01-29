# frozen_string_literal: true

require "dependabot/pull_request_creator/pr_name_prefixer"
require "dependabot/pull_request_creator/message_builder/components/title_builder"
require "dependabot/pull_request_creator/message_builder/strategies/multi_ecosystem"

module Dependabot
  # Builds combined PR message data for multi-ecosystem updates.
  #
  # Uses shared components from dependabot-core for consistent title generation.
  class MultiEcosystemMessageBuilder
    attr_reader :pending_prs, :multi_ecosystem_config, :update_configs, :source, :credentials

    def initialize(pending_prs:, multi_ecosystem_config:, update_configs:, source:, credentials: [])
      @pending_prs = pending_prs
      @multi_ecosystem_config = multi_ecosystem_config
      @update_configs = update_configs
      @source = source
      @credentials = credentials
    end

    def build
      {
        commit_message: combined_commit_message,
        pr_title: combined_pr_title,
        pr_body: combined_pr_body,
      }
    end

    def combined_commit_message
      pending_prs.map { |pr| pr.message_data["commit_message"] }.join("\n")
    end

    def combined_pr_title
      # Use core components for consistent behavior
      strategy = PullRequestCreator::MessageBuilder::Strategies::MultiEcosystem.new(
        group_name: multi_ecosystem_config.name,
        update_count: pending_prs.size
      )

      PullRequestCreator::MessageBuilder::Components::TitleBuilder.new(
        base_title: strategy.base_title,
        prefixer: pr_name_prefixer
      ).build
    end

    def combined_pr_body
      pending_prs.map { |pr| pr.message_data["pr_body"] }.join("\n")
    end

    private

    def pr_name_prefixer
      return @pr_name_prefixer if defined?(@pr_name_prefixer)

      config = find_update_config_with_prefix
      return @pr_name_prefixer = nil unless config

      @pr_name_prefixer = PullRequestCreator::PrNamePrefixer.new(
        source: source,
        dependencies: all_dependencies,
        credentials: credentials,
        security_fix: false,
        commit_message_options: build_commit_message_options(config),
      )
    end

    def find_update_config_with_prefix
      update_configs.find do |config|
        config.commit_message_prefix.present? || config.commit_message_prefix_development.present?
      end
    end

    def all_dependencies
      @all_dependencies ||= pending_prs.flat_map(&:updated_dependencies)
    end

    def build_commit_message_options(update_config)
      options = {}
      options[:prefix] = update_config.commit_message_prefix if update_config.commit_message_prefix.present?
      if update_config.commit_message_prefix_development.present?
        options[:prefix_development] = update_config.commit_message_prefix_development
      end
      options[:include_scope] = update_config.commit_message_include_scope if update_config.commit_message_include_scope
      options
    end
  end
end