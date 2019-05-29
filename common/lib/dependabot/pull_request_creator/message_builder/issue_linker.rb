# frozen_string_literal: true

require "dependabot/pull_request_creator/message_builder"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      class IssueLinker
        TAG_REGEX = /(?<tag>(?:\#|GH-)\d+)/.freeze
        ISSUE_LINK_REGEXS = [
          /(?<=[^A-Za-z0-9\[\\]|^)\\*#{TAG_REGEX}(?=[^A-Za-z0-9\-]|$)/.freeze,
          /\[#{TAG_REGEX}\](?=[^A-Za-z0-9\-\(])/.freeze,
          /\[(?<tag>(?:\#|GH-)?\d+)\]\(\)/.freeze
        ].freeze

        attr_reader :source_url

        def initialize(source_url:)
          @source_url = source_url
        end

        def link_issues(text:)
          # Loop through each of the issue link regexes, replacing any instances
          # of them with an absolute link that uses the source URL
          ISSUE_LINK_REGEXS.reduce(text) do |updated_text, regex|
            updated_text.gsub(regex) do |issue_link|
              tag = issue_link.
                    match(/(?<tag>(?:\#|GH-)?\d+)/).
                    named_captures.fetch("tag")
              number = tag.match(/\d+/).to_s
              "[#{tag}](#{source_url}/issues/#{number})"
            end
          end
        end
      end
    end
  end
end
