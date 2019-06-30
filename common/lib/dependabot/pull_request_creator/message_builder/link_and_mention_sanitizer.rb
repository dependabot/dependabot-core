# frozen_string_literal: true

require "dependabot/pull_request_creator/message_builder"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      class LinkAndMentionSanitizer
        GITHUB_REF_REGEX = %r{
          (?:https?://)?
          github\.com/[^/\s]+/[^/\s]+/
          (?:issue|pull)s?/(?<number>\d+)
        }x.freeze

        # Note that we're being deliberately careful about not matching
        # different length strings of what look like code block quotes. By
        # doing so we err on the side of sanitizing, which is *much* better
        # than accidentally not sanitizing.
        #
        # rubocop:disable Style/RegexpLiteral
        CODEBLOCK_REGEX = %r{
          (?=[\s]`{3}[^`])|(?=[\s]`{3}\Z)|(?=\A`{3}[^`])|
          (?=[\s]~{3}[^~])|(?=[\s]~{3}\Z)|(?=\A~{3}[^~])
        }x.freeze
        # rubocop:enable Style/RegexpLiteral

        attr_reader :github_redirection_service

        def initialize(github_redirection_service:)
          @github_redirection_service = github_redirection_service
        end

        def sanitize_links_and_mentions(text:)
          # We don't want to sanitize any links or mentions that are contained
          # within code blocks, so we split the text on "```"
          snippets = text.split(CODEBLOCK_REGEX)
          if snippets.first&.start_with?(CODEBLOCK_REGEX)
            snippets = ["", *snippets]
          end

          snippets.map.with_index do |snippet, index|
            next snippet if index.odd?

            snippet = sanitize_mentions(snippet)
            sanitize_links(snippet)
          end.join
        end

        private

        def sanitize_mentions(text)
          text.gsub(%r{(?<![A-Za-z0-9`~])@[\w][\w.-/]*}) do |mention|
            next mention if mention.include?("/")

            last_match = Regexp.last_match

            sanitized_mention = mention.gsub("@", "@&#8203;")
            if last_match.pre_match.chars.last == "[" &&
               last_match.post_match.chars.first == "]"
              sanitized_mention
            else
              "[#{sanitized_mention}]"\
              "(https://github.com/#{mention.tr('@', '')})"
            end
          end
        end

        def sanitize_links(text)
          text.gsub(GITHUB_REF_REGEX) do |ref|
            last_match = Regexp.last_match
            previous_char = last_match.pre_match.chars.last
            next_char = last_match.post_match.chars.first

            sanitized_url =
              ref.gsub("github.com", github_redirection_service || "github.com")
            if (previous_char.nil? || previous_char.match?(/\s/)) &&
               (next_char.nil? || next_char.match?(/\s/))
              "[##{last_match.named_captures.fetch('number')}]"\
              "(#{sanitized_url})"
            else
              sanitized_url
            end
          end
        end
      end
    end
  end
end
