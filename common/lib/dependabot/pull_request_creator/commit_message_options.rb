# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    # Typed view over the `commit_message_options` hash threaded into the PR
    # creator's title and prefix builders. The raw options arrive as a loosely
    # typed hash sourced from user config, so this parses the known keys once at
    # the boundary and lets downstream builders use typed readers instead of
    # digging an untyped hash.
    class CommitMessageOptions
      extend T::Sig

      sig { returns(T.nilable(String)) }
      attr_reader :prefix

      sig { returns(T.nilable(String)) }
      attr_reader :prefix_development

      sig { returns(T::Boolean) }
      attr_reader :include_scope

      sig do
        params(
          prefix: T.nilable(String),
          prefix_development: T.nilable(String),
          include_scope: T::Boolean
        ).void
      end
      def initialize(prefix: nil, prefix_development: nil, include_scope: false)
        @prefix = prefix
        @prefix_development = prefix_development
        @include_scope = include_scope
      end

      # Parses a raw options hash. Unknown keys are ignored, and absent or
      # non-string prefixes become nil.
      sig { params(options: T::Hash[Symbol, T.anything]).returns(CommitMessageOptions) }
      def self.from_hash(options)
        new(
          prefix: coerce_string(options[:prefix]),
          prefix_development: coerce_string(options[:prefix_development]),
          include_scope: options[:include_scope] ? true : false
        )
      end

      sig { params(value: T.anything).returns(T.nilable(String)) }
      def self.coerce_string(value)
        case value
        when String then value
        end
      end
      private_class_method :coerce_string

      # True when an explicit (non-nil) prefix was provided.
      sig { returns(T::Boolean) }
      def prefix?
        !prefix.nil?
      end

      # True when an explicit (non-nil) development prefix was provided.
      sig { returns(T::Boolean) }
      def prefix_development?
        !prefix_development.nil?
      end
    end
  end
end
