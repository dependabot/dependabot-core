# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"
require "dependabot/pull_request_creator/message_builder"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      class IssueLinker
        extend T::Sig

        REPO_REGEX = %r{(?<repo>[\w.-]+/(?:(?!\.git|\.\s)[\w.-])+)}
        TAG_REGEX = /(?<tag>(?:\#|GH-)\d+)/i
        ISSUE_LINK_REGEXS = T.let(
          [
            /
              (?:(?<=[^A-Za-z0-9\[\\]|^)\\*#{TAG_REGEX}(?=[^A-Za-z0-9\-]|$))|
              (?:(?<=\s|^)#{REPO_REGEX}#{TAG_REGEX}(?=[^A-Za-z0-9\-]|$))
            /x,
            /\[#{TAG_REGEX}\](?=[^A-Za-z0-9\-\(])/,
            /\[(?<tag>(?:\#|GH-)?\d+)\]\(\)/i
          ].freeze,
          T::Array[Regexp]
        )

        sig { returns(T.nilable(String)) }
        attr_reader :source_url

        sig { params(source_url: T.nilable(String)).void }
        def initialize(source_url:)
          @source_url = source_url
        end

        sig { params(text: String).returns(String) }
        def link_issues(text:)
          # Loop through each of the issue link regexes, replacing any instances
          # of them with an absolute link that uses the source URL
          ISSUE_LINK_REGEXS.reduce(text) do |updated_text, regex|
            updated_text.gsub(regex) do |issue_link|
              tag = T.must(
                T.must(
                  issue_link
                                      .match(/(?<tag>(?:\#|GH-)?\d+)/i)
                )
                     .named_captures.fetch("tag")
              )
              number = tag.match(/\d+/).to_s

              repo = issue_link
                     .match("#{REPO_REGEX}#{TAG_REGEX}")
                     &.named_captures
                     &.fetch("repo", nil)

              source = if repo
                         "#{qualified_reference_base_url}/#{repo}"
                       elsif source_url
                         source_url
                       end

              if source
                "[#{repo ? (repo + tag) : tag}](#{source}#{issue_path(source)}/#{number})"
              else
                issue_link
              end
            end
          end
        end

        private

        sig { params(source: String).returns(String) }
        def issue_path(source)
          URI.parse(source).host&.downcase == "gitlab.com" ? "/-/work_items" : "/issues"
        rescue URI::InvalidURIError
          "/issues"
        end

        sig { returns(String) }
        def qualified_reference_base_url
          return "https://github.com" unless source_url

          URI.parse(T.must(source_url)).host&.downcase == "gitlab.com" ? "https://gitlab.com" : "https://github.com"
        rescue URI::InvalidURIError
          "https://github.com"
        end
      end
    end
  end
end
