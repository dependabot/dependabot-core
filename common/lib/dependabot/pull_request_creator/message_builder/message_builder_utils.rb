# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      # MessageBuilderUtils provides shared utilities for building PR titles
      # that can be reused across different message builder implementations.
      #
      # This ensures PR title construction logic is centralized, so future
      # updates affect all builders consistently.
      module MessageBuilderUtils
        extend T::Sig

        # Builds a PR title by combining a base title with an optional prefix,
        # with support for capitalizing the first word.
        #
        # @param title [String] The base title text
        # @param prefix [String] Optional prefix to prepend (e.g., "chore: ", "[Security] ")
        # @param capitalize_first_word [Boolean] Whether to capitalize the first character of the title
        # @return [String] The constructed PR title
        #
        # @example Basic usage
        #   build_pr_title(title: "bump foo to 1.0", prefix: "chore: ")
        #   # => "chore: bump foo to 1.0"
        #
        # @example With capitalization
        #   build_pr_title(title: "bump foo to 1.0", prefix: "", capitalize_first_word: true)
        #   # => "Bump foo to 1.0"
        sig do
          params(
            title: String,
            prefix: String,
            capitalize_first_word: T::Boolean
          ).returns(String)
        end
        def self.build_pr_title(title:, prefix: "", capitalize_first_word: false)
          result_title = title.dup
          result_title[0] = T.must(result_title[0]).capitalize if capitalize_first_word && !result_title.empty?
          "#{prefix}#{result_title}"
        end

        # Builds commit message options hash from update config values.
        # This is used to configure PrNamePrefixer with the appropriate prefix settings.
        #
        # @param prefix [String, nil] The commit message prefix for production dependencies
        # @param prefix_development [String, nil] The commit message prefix for development dependencies
        # @param include_scope [Boolean, nil] Whether to include scope in the prefix
        # @return [Hash] Options hash suitable for PrNamePrefixer
        #
        # @example
        #   build_commit_message_options(
        #     prefix: "chore",
        #     prefix_development: "chore",
        #     include_scope: true
        #   )
        #   # => { prefix: "chore", prefix_development: "chore", include_scope: true }
        sig do
          params(
            prefix: T.nilable(String),
            prefix_development: T.nilable(String),
            include_scope: T.nilable(T::Boolean)
          ).returns(T::Hash[Symbol, T.untyped])
        end
        def self.build_commit_message_options(prefix: nil, prefix_development: nil, include_scope: nil)
          options = {}
          options[:prefix] = prefix if prefix && !prefix.empty?
          options[:prefix_development] = prefix_development if prefix_development && !prefix_development.empty?
          options[:include_scope] = include_scope if include_scope
          options
        end
      end
    end
  end
end
