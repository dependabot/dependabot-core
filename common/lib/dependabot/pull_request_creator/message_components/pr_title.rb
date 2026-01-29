# typed: strong
# frozen_string_literal: true

require "dependabot/pull_request_creator/message_components/base"
require "dependabot/pull_request_creator/pr_name_prefixer"

module Dependabot
  class PullRequestCreator
    module MessageComponents
      # Base class for PR title generation
      # Handles prefix application and capitalization logic
      class PrTitle < Base
        extend T::Sig

        sig { returns(String) }
        def build
          title = base_title
          title = capitalize_first_word(title) if should_capitalize?
          "#{prefix}#{title}"
        end

        private

        sig { returns(String) }
        def base_title
          raise NotImplementedError, "Subclasses must implement #base_title"
        end

        sig { returns(String) }
        def prefix
          @prefix ||= T.let(prefixer.pr_name_prefix, T.nilable(String))
        end

        sig { returns(T::Boolean) }
        def should_capitalize?
          prefixer.capitalize_first_word?
        end

        sig { returns(Dependabot::PullRequestCreator::PrNamePrefixer) }
        def prefixer
          @prefixer ||= T.let(
            PrNamePrefixer.new(
              source: source,
              dependencies: dependencies,
              credentials: credentials,
              security_fix: T.cast(options[:security_fix], T::Boolean) || false,
              commit_message_options: options[:commit_message_options] || {}
            ),
            T.nilable(Dependabot::PullRequestCreator::PrNamePrefixer)
          )
        end

        sig { params(title: String).returns(String) }
        def capitalize_first_word(title)
          return title if title.empty?

          title_copy = title.dup
          title_copy[0] = T.must(title_copy[0]).upcase
          title_copy
        end
      end
    end
  end
end
