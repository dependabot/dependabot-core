# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Components
        # Builds PR titles with consistent prefix and capitalization handling.
        # Designed to be reusable across all message builder types.
        #
        # @example
        #   TitleBuilder.new(
        #     base_title: "bump lodash from 4.0 to 5.0",
        #     prefixer: pr_name_prefixer
        #   ).build
        #   # => "chore(deps): Bump lodash from 4.0 to 5.0"
        #
        class TitleBuilder
          extend T::Sig

          sig do
            params(
              base_title: String,
              prefixer: T.nilable(PrNamePrefixer)
            ).void
          end
          def initialize(base_title:, prefixer: nil)
            @base_title = base_title
            @prefixer = prefixer
          end

          sig { returns(String) }
          def build
            title = @base_title.dup
            title = capitalize_first_word(title) if should_capitalize?
            "#{prefix}#{title}"
          end

          private

          sig { returns(String) }
          def prefix
            @prefixer&.pr_name_prefix || ""
          end

          sig { returns(T::Boolean) }
          def should_capitalize?
            @prefixer&.capitalize_first_word? || false
          end

          sig { params(title: String).returns(String) }
          def capitalize_first_word(title)
            return title if title.empty?

            result = title.dup
            result[0] = T.must(result[0]).capitalize
            result
          end
        end
      end
    end
  end
end