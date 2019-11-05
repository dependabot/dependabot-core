# frozen_string_literal: true

require "strscan"
require "dependabot/pull_request_creator/message_builder"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      class LinkAndMentionSanitizer
        GITHUB_USERNAME = /[a-z0-9]+(-[a-z0-9]+)*/i.freeze
        GITHUB_REF_REGEX = %r{
          (?:https?://)?
          github\.com/(?<repo>#{GITHUB_USERNAME}/[^/\s]+)/
          (?:issue|pull)s?/(?<number>\d+)
        }x.freeze
        # rubocop:disable Metrics/LineLength
        # Context:
        # - https://github.github.com/gfm/#fenced-code-block (``` or ~~~)
        #   (?<=\n|^)         Positive look-behind to ensure we start at a line start
        #   (?>`{3,}|~{3,})   Atomic group marking the beginning of the block (3 or more chars)
        #   (?>\k<fenceopen>) Atomic group marking the end of the code block (same length as opening)
        FENCED_CODEBLOCK_REGEX =
          /(?<=\n|^)(?<fenceopen>(?>`{3,}|~{3,})).*?(?>\k<fenceopen>)/xm.freeze
        # Context:
        # - https://github.github.com/gfm/#code-span
        #   (?<codespanopen>`+)  Capturing group marking the beginning of the span (1 or more chars)
        #   (?![^`]*?\n{2,})     Negative look-ahead to avoid empty lines inside code span
        #   (?:.|\n)*?           Non-capturing group to consume code span content (non-eager)
        #   (?>\k<codespanopen>) Atomic group marking the end of the code span (same length as opening)
        # rubocop:enable Metrics/LineLength
        CODESPAN_REGEX =
          /(?<codespanopen>`+)(?![^`]*?\n{2,})(?:.|\n)*?(?>\k<codespanopen>)
          /xm.freeze
        # End of string
        EOS_REGEX = /\z/.freeze

        attr_reader :github_redirection_service

        def initialize(github_redirection_service:)
          @github_redirection_service = github_redirection_service
        end

        def sanitize_links_and_mentions(text:)
          # We don't want to sanitize any links or mentions that are contained
          # within code blocks, so we split the text on "```" or "~~~"
          sanitized_text = []
          scan = StringScanner.new(text)
          expressions = [FENCED_CODEBLOCK_REGEX, CODESPAN_REGEX]
          until scan.eos?
            match = find_next_match(scan, *expressions)
            block = match[:block] || scan.scan_until(EOS_REGEX)
            sanitized_text <<
              sanitize_links_and_mentions_in_block(block, match[:regex])
          end
          sanitized_text.join
        end

        private

        # Find the earliest occurrence in a StringScanner within
        # an array of regular expressions
        def find_next_match(scan, *expressions)
          # Try all different regular expressions
          matches = expressions.map do |regex|
            block = scan.scan_until(regex)
            val = { pos: scan.pos, block: block, regex: regex }
            scan.unscan if block
            val
          end

          # Select the one with the earliest starting position
          match = matches.
                  select { |m| m[:block] }.
                  min { |m| m[:pos] - m[:block].length }
          return { regex: expressions[0] } unless match

          # Reset the scanner position
          scan.pos = match[:pos] if match[:block]

          match
        end

        def sanitize_links_and_mentions_in_block(block, regex)
          # Handle code blocks one by one
          normal_text = block
          verbatim_text = ""
          match = block.match(regex)
          if match
            # Part leading up to start of code block
            normal_text = match.pre_match
            # Entire code block copied verbatim
            verbatim_text = match.to_s
          end
          normal_text = sanitize_mentions(normal_text)
          normal_text = sanitize_links(normal_text)
          normal_text + verbatim_text
        end

        def sanitize_mentions(text)
          text.gsub(%r{(?<![A-Za-z0-9`~])@#{GITHUB_USERNAME}/?}) do |mention|
            next mention if mention.end_with?("/")

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
              number = last_match.named_captures.fetch("number")
              repo = last_match.named_captures.fetch("repo")
              "[#{repo}##{number}]"\
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
