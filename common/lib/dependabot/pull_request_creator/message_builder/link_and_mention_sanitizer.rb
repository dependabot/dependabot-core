# typed: strong
# frozen_string_literal: true

require "commonmarker"
require "sorbet-runtime"
require "strscan"
require "dependabot/pull_request_creator/message_builder"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      class LinkAndMentionSanitizer
        extend T::Sig

        GITHUB_USERNAME = /[a-z0-9]+(-[a-z0-9]+)*/i
        GITHUB_REF_REGEX = %r{
          (?:https?://)?
          github\.com/(?<repo>#{GITHUB_USERNAME}/[^/\s]+)/
          (?:issue|pull)s?/(?<number>\d+)
        }x
        # [^/\s#]+ means one or more characters not matching (^) the class /, whitespace (\s), or #
        GITHUB_NWO_REGEX = %r{(?<repo>#{GITHUB_USERNAME}/[^/\s#]+)#(?<number>\d+)}
        MENTION_REGEX = %r{(?<![A-Za-z0-9`~])@#{GITHUB_USERNAME}/?}
        # regex to match a team mention on github
        TEAM_MENTION_REGEX = %r{(?<![A-Za-z0-9`~])@(?<org>#{GITHUB_USERNAME})/(?<team>#{GITHUB_USERNAME})/?}
        # End of string
        EOS_REGEX = /\z/

        # regex to match markdown headers or links
        MARKDOWN_REGEX = /\[(.+?)\]\(([^)]+)\)|\[(.+?)\]|\A#+\s+([^\s].*)/

        COMMONMARKER_OPTIONS = T.let(
          %i(GITHUB_PRE_LANG FULL_INFO_STRING).freeze,
          T::Array[Symbol]
        )
        COMMONMARKER_EXTENSIONS = T.let(
          %i(table tasklist strikethrough autolink tagfilter).freeze,
          T::Array[Symbol]
        )

        sig { returns(T.nilable(String)) }
        attr_reader :github_redirection_service

        sig { params(github_redirection_service: T.nilable(String)).void }
        def initialize(github_redirection_service:)
          @github_redirection_service = github_redirection_service
        end

        sig { params(text: String, unsafe: T::Boolean, format_html: T::Boolean).returns(String) }
        def sanitize_links_and_mentions(text:, unsafe: false, format_html: true)
          doc = CommonMarker.render_doc(
            text, :LIBERAL_HTML_TAG, COMMONMARKER_EXTENSIONS
          )

          sanitize_team_mentions(doc)
          sanitize_mentions(doc)
          sanitize_links(doc)
          sanitize_nwo_text(doc)

          render_options = if text.match?(MARKDOWN_REGEX)
                             COMMONMARKER_OPTIONS
                           else
                             COMMONMARKER_OPTIONS + [:HARDBREAKS]
                           end

          mode = unsafe ? :UNSAFE : :DEFAULT
          return doc.to_commonmark([mode] + render_options) unless format_html

          doc.to_html(([mode] + render_options), COMMONMARKER_EXTENSIONS)
        end

        private

        sig { params(doc: CommonMarker::Node).void }
        def sanitize_mentions(doc)
          doc.walk do |node|
            if node.type == :text &&
               node.string_content.match?(MENTION_REGEX)
              nodes = if parent_node_link?(node)
                        build_mention_link_text_nodes(node.string_content)
                      else
                        build_mention_nodes(node.string_content)
                      end

              nodes.each do |n|
                node.insert_before(n)
              end

              node.delete
            end
          end
        end

        # When we come across something that looks like a team mention (e.g. @dependabot/reviewers),
        # we replace it with a text node.
        # This is because there are ecosystems that have packages that follow the same pattern
        # (e.g. @angular/angular-cli), and we don't want to create an invalid link, since
        # team mentions link to `https://github.com/org/:organization_name/teams/:team_name`.
        sig { params(doc: CommonMarker::Node).void }
        def sanitize_team_mentions(doc)
          doc.walk do |node|
            if node.type == :text &&
               node.string_content.match?(TEAM_MENTION_REGEX)

              nodes = build_team_mention_nodes(node.string_content)

              nodes.each do |n|
                node.insert_before(n)
              end
              node.delete
            end
          end
        end

        sig { params(doc: CommonMarker::Node).void }
        def sanitize_links(doc)
          doc.walk do |node|
            if node.type == :link && node.url.match?(GITHUB_REF_REGEX)
              node.each do |subnode|
                unless subnode.type == :text &&
                       subnode.string_content.match?(GITHUB_REF_REGEX)
                  next
                end

                last_match = T.must(subnode.string_content.match(GITHUB_REF_REGEX))
                number = last_match.named_captures.fetch("number")
                repo = last_match.named_captures.fetch("repo")
                subnode.string_content = "#{repo}##{number}"
              end

              node.url = replace_github_host(node.url)
            elsif node.type == :text &&
                  node.string_content.match?(GITHUB_REF_REGEX)
              node.string_content = replace_github_host(node.string_content)
            end
          end
        end

        sig { params(doc: CommonMarker::Node).void }
        def sanitize_nwo_text(doc)
          doc.walk do |node|
            if node.type == :text &&
               node.string_content.match?(GITHUB_NWO_REGEX) &&
               !parent_node_link?(node)
              replace_nwo_node(node)
            end
          end
        end

        sig { params(node: CommonMarker::Node).void }
        def replace_nwo_node(node)
          match = T.must(node.string_content.match(GITHUB_NWO_REGEX))
          repo = match.named_captures.fetch("repo")
          number = match.named_captures.fetch("number")
          new_node = build_nwo_text_node("#{repo}##{number}")
          node.insert_before(new_node)
          node.delete
        end

        sig { params(text: String).returns(String) }
        def replace_github_host(text)
          return text if !github_redirection_service.nil? && text.include?(T.must(github_redirection_service))

          text.gsub(
            /(www\.)?github.com/, github_redirection_service || "github.com"
          )
        end

        sig { params(text: String).returns(T::Array[CommonMarker::Node]) }
        def build_mention_nodes(text)
          nodes = T.let([], T::Array[CommonMarker::Node])
          scan = StringScanner.new(text)

          until scan.eos?
            line = scan.scan_until(MENTION_REGEX) ||
                   scan.scan_until(EOS_REGEX)
            line_match = T.must(line).match(MENTION_REGEX)
            mention = line_match&.to_s
            text_node = CommonMarker::Node.new(:text)

            if mention && !mention.end_with?("/")
              text_node.string_content = line_match.pre_match
              nodes << text_node
              nodes << create_link_node(
                "https://github.com/#{mention.tr('@', '')}", mention.to_s
              )
            else
              text_node.string_content = line
              nodes << text_node
            end
          end

          nodes
        end

        sig { params(text: String).returns(T::Array[CommonMarker::Node]) }
        def build_team_mention_nodes(text)
          nodes = T.let([], T::Array[CommonMarker::Node])

          scan = StringScanner.new(text)
          until scan.eos?
            line = scan.scan_until(TEAM_MENTION_REGEX) ||
                   scan.scan_until(EOS_REGEX)
            line_match = T.must(line).match(TEAM_MENTION_REGEX)
            mention = line_match&.to_s
            text_node = CommonMarker::Node.new(:text)

            if mention
              text_node.string_content = line_match.pre_match
              nodes << text_node
              nodes += build_mention_link_text_nodes(mention.to_s)
            else
              text_node.string_content = line
              nodes << text_node
            end
          end

          nodes
        end

        sig { params(text: String).returns(T::Array[CommonMarker::Node]) }
        def build_mention_link_text_nodes(text)
          code_node = CommonMarker::Node.new(:code)
          code_node.string_content = insert_zero_width_space_in_mention(text)
          [code_node]
        end

        sig { params(text: String).returns(CommonMarker::Node) }
        def build_nwo_text_node(text)
          code_node = CommonMarker::Node.new(:code)
          code_node.string_content = text
          code_node
        end

        sig { params(url: String, text: String).returns(CommonMarker::Node) }
        def create_link_node(url, text)
          link_node = CommonMarker::Node.new(:link)
          code_node = CommonMarker::Node.new(:code)
          link_node.url = url
          code_node.string_content = insert_zero_width_space_in_mention(text)
          link_node.append_child(code_node)
          link_node
        end

        # NOTE: Add a zero-width space between the @ and the username to prevent
        # email replies on dependabot pull requests triggering notifications to
        # users who've been mentioned in changelogs etc. PR email replies parse
        # the content of the pull request body in plain text.
        sig { params(mention: String).returns(String) }
        def insert_zero_width_space_in_mention(mention)
          mention.sub("@", "@\u200B").encode("utf-8")
        end

        sig { params(node: CommonMarker::Node).returns(T::Boolean) }
        def parent_node_link?(node)
          node.type == :link || (!node.parent.nil? && parent_node_link?(T.must(node.parent)))
        end
      end
    end
  end
end
