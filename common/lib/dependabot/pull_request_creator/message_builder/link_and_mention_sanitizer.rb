# frozen_string_literal: true

require "commonmarker"
require "nokogiri"
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
        # - https://github.github.com/gfm/#code-span
        #   (?<codespanopen>`+)  Capturing group marking the beginning of the span (1 or more chars)
        #   (?![^`]*?\n{2,})     Negative look-ahead to avoid empty lines inside code span
        #   (?:.|\n)*?           Non-capturing group to consume code span content (non-eager)
        #   (?>\k<codespanopen>) Atomic group marking the end of the code span (same length as opening)
        # rubocop:enable Metrics/LineLength
        CODEBLOCK_REGEX = /```|~~~/.freeze
        # End of string
        EOS_REGEX = /\z/.freeze

        attr_reader :github_redirection_service

        def initialize(github_redirection_service:)
          @github_redirection_service = github_redirection_service
        end

        def sanitize_links_and_mentions(text:)
          # We don't want to sanitize any links or mentions that are contained
          # within code blocks, so we split the text on "```" or "~~~"
          lines = []
          scan = StringScanner.new(text)
          until scan.eos?
            line = scan.scan_until(CODEBLOCK_REGEX) ||
                   scan.scan_until(EOS_REGEX)
            delimiter = line.match(CODEBLOCK_REGEX)&.to_s
            unless delimiter && lines.count { |l| l.include?(delimiter) }.odd?
              line = sanitize_mentions(line)
              line = sanitize_links(line)
            end
            lines << line
          end
          lines.join
        end

        private

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
          doc = CommonMarker.render_doc(
            text,
            :DEFAULT,
            %i(table tasklist strikethrough autolink tagfilter)
          )

          doc.walk do |node|
            if node.type == :link && node.url.match?(GITHUB_REF_REGEX)
              node.each do |subnode|
                last_match = subnode.string_content.match(GITHUB_REF_REGEX)
                if subnode.type == :text && last_match
                  number = last_match.named_captures.fetch("number")
                  repo = last_match.named_captures.fetch("repo")
                  subnode.string_content = "#{repo}##{number}"
                end

                next
              end

              node.url = node.url.gsub(
                "github.com", github_redirection_service || "github.com"
              )
            end
          end

          doc.to_html
        end
      end
    end
  end
end
