# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class GitCommitChecker
    # Typed view over the source hash attached to a git dependency.
    class SourceDetails < T::ImmutableStruct
      extend T::Sig

      const :type, T.nilable(String)
      const :url, T.nilable(String)
      const :branch, T.nilable(String)
      const :ref, T.nilable(String)

      sig do
        params(details: T::Hash[T.any(String, Symbol), Object]).returns(SourceDetails)
      end
      def self.from_hash(details)
        new(
          type: string_value(details, :type),
          url: string_value(details, :url),
          branch: string_value(details, :branch),
          ref: string_value(details, :ref)
        )
      end

      sig do
        params(
          details: T::Hash[T.any(String, Symbol), Object],
          key: Symbol
        ).returns(T.nilable(String))
      end
      def self.string_value(details, key)
        value = details.key?(key) ? details[key] : details[key.to_s]
        value.is_a?(String) ? value : nil
      end
      private_class_method :string_value
    end
  end
end
