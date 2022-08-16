# frozen_string_literal: true

require "dependabot/pull_request_creator/message_builder"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      class MetadataPresenter
        extend Forwardable

        attr_reader :dependency, :source, :metadata_finder,
                    :vulnerabilities_fixed, :github_redirection_service

        def_delegators :metadata_finder,
                       :changelog_url,
                       :changelog_text,
                       :commits_url,
                       :commits,
                       :maintainer_changes,
                       :releases_url,
                       :releases_text,
                       :source_url,
                       :upgrade_guide_url,
                       :upgrade_guide_text

        def initialize(dependency:, source:, metadata_finder:,
                       vulnerabilities_fixed:, github_redirection_service:)
          @dependency = dependency
          @source = source
          @metadata_finder = metadata_finder
          @vulnerabilities_fixed = vulnerabilities_fixed
          @github_redirection_service = github_redirection_service
        end

        def to_s
          msg = ""
          msg += vulnerabilities_cascade
          msg += release_cascade
          msg += changelog_cascade
          msg += upgrade_guide_cascade
          msg += commits_cascade
          msg += maintainer_changes_cascade
          msg += break_tag unless msg == ""
          "\n" + sanitize_links_and_mentions(msg, unsafe: true)
        end

        private

        def vulnerabilities_cascade
          return "" unless vulnerabilities_fixed&.any?

          msg = ""
          vulnerabilities_fixed.each do |v|
            msg += serialized_vulnerability_details(v)
          end

          msg = sanitize_template_tags(msg)
          msg = sanitize_links_and_mentions(msg)

          build_details_tag(summary: "Vulnerabilities fixed", body: msg)
        end

        def release_cascade
          return "" unless releases_text && releases_url

          msg = "*Sourced from [#{dependency.display_name}'s releases]"\
                "(#{releases_url}).*\n\n"
          msg += quote_and_truncate(releases_text)
          msg = link_issues(text: msg)
          msg = fix_relative_links(
            text: msg,
            base_url: source_url + "/blob/HEAD/"
          )
          msg = sanitize_template_tags(msg)
          msg = sanitize_links_and_mentions(msg)

          build_details_tag(summary: "Release notes", body: msg)
        end

        def changelog_cascade
          return "" unless changelog_url && changelog_text

          msg = "*Sourced from "\
                "[#{dependency.display_name}'s changelog]"\
                "(#{changelog_url}).*\n\n"
          msg += quote_and_truncate(changelog_text)
          msg = link_issues(text: msg)
          msg = fix_relative_links(text: msg, base_url: changelog_url)
          msg = sanitize_template_tags(msg)
          msg = sanitize_links_and_mentions(msg)

          build_details_tag(summary: "Changelog", body: msg)
        end

        def upgrade_guide_cascade
          return "" unless upgrade_guide_url && upgrade_guide_text

          msg = "*Sourced from "\
                "[#{dependency.display_name}'s upgrade guide]"\
                "(#{upgrade_guide_url}).*\n\n"
          msg += quote_and_truncate(upgrade_guide_text)
          msg = link_issues(text: msg)
          msg = fix_relative_links(text: msg, base_url: upgrade_guide_url)
          msg = sanitize_template_tags(msg)
          msg = sanitize_links_and_mentions(msg)

          build_details_tag(summary: "Upgrade guide", body: msg)
        end

        def commits_cascade
          return "" unless commits_url && commits

          msg = ""

          commits.reverse.first(10).each do |commit|
            title = commit[:message].strip.split("\n").first
            title = title.slice(0..76) + "..." if title && title.length > 80
            title = title&.gsub(/(?<=[^\w.-])([_*`~])/, '\\1')
            sha = commit[:sha][0, 7]
            msg += "- [`#{sha}`](#{commit[:html_url]}) #{title}\n"
          end

          msg = msg.gsub(/\<.*?\>/) { |tag| "\\#{tag}" }

          msg +=
            if commits.count > 10
              "- Additional commits viewable in "\
              "[compare view](#{commits_url})\n"
            else
              "- See full diff in [compare view](#{commits_url})\n"
            end
          msg = link_issues(text: msg)
          msg = sanitize_links_and_mentions(msg)

          build_details_tag(summary: "Commits", body: msg)
        end

        def maintainer_changes_cascade
          return "" unless maintainer_changes

          build_details_tag(
            summary: "Maintainer changes",
            body: sanitize_links_and_mentions(maintainer_changes) + "\n"
          )
        end

        def build_details_tag(summary:, body:)
          # Azure DevOps does not support <details> tag (https://developercommunity.visualstudio.com/content/problem/608769/add-support-for-in-markdown.html)
          # Bitbucket does not support <details> tag (https://jira.atlassian.com/browse/BCLOUD-20231)
          # CodeCommit does not support the <details> tag (no url available)
          if source_provider_supports_html?
            msg = "<details>\n<summary>#{summary}</summary>\n\n"
            msg += body
            msg + "</details>\n"
          else
            "\n\##{summary}\n\n#{body}"
          end
        end

        def serialized_vulnerability_details(details)
          msg = vulnerability_source_line(details)

          msg += "> **#{details['title'].lines.map(&:strip).join(' ')}**\n" if details["title"]

          if (description = details["description"])
            description.strip.lines.first(20).each { |line| msg += "> #{line}" }
            msg += truncated_line if description.strip.lines.count > 20
          end

          msg += "\n" unless msg.end_with?("\n")
          msg += "> \n"
          msg += vulnerability_version_range_lines(details)
          msg + "\n"
        end

        def vulnerability_source_line(details)
          if details["source_url"] && details["source_name"]
            "*Sourced from [#{details['source_name']}]"\
            "(#{details['source_url']}).*\n\n"
          elsif details["source_name"]
            "*Sourced from #{details['source_name']}.*\n\n"
          else
            ""
          end
        end

        def vulnerability_version_range_lines(details)
          msg = ""
          %w(
            patched_versions
            unaffected_versions
            affected_versions
          ).each do |tp|
            type = tp.split("_").first.capitalize
            next unless details[tp]

            versions_string = details[tp].any? ? details[tp].join("; ") : "none"
            versions_string = versions_string.gsub(/(?<!\\)~/, '\~')
            msg += "> #{type} versions: #{versions_string}\n"
          end
          msg
        end

        def link_issues(text:)
          IssueLinker.
            new(source_url: source_url).
            link_issues(text: text)
        end

        def fix_relative_links(text:, base_url:)
          text.gsub(/\[.*?\]\([^)]+\)/) do |link|
            next link if link.include?("://")

            relative_path = link.match(/\((.*?)\)/).captures.last
            base = base_url.split("://").last.gsub(%r{[^/]*$}, "")
            path = File.join(base, relative_path)
            absolute_path =
              base_url.sub(
                %r{(?<=://).*$},
                Pathname.new(path).cleanpath.to_s
              )
            link.gsub(relative_path, absolute_path)
          end
        end

        def quote_and_truncate(text, limit: 50)
          lines = text.split("\n")
          lines.first(limit).tap do |limited_lines|
            limited_lines.map! { |line| "> #{line}\n" }
            limited_lines << truncated_line if lines.count > limit
          end.join
        end

        def truncated_line
          # Tables can spill out of truncated details, so we close them
          "></tr></table> \n ... (truncated)\n"
        end

        def break_tag
          source_provider_supports_html? ? "\n<br />" : "\n\n"
        end

        def source_provider_supports_html?
          !%w(azure bitbucket codecommit).include?(source.provider)
        end

        def sanitize_links_and_mentions(text, unsafe: false)
          return text unless source.provider == "github"

          LinkAndMentionSanitizer.
            new(github_redirection_service: github_redirection_service).
            sanitize_links_and_mentions(text: text, unsafe: unsafe)
        end

        def sanitize_template_tags(text)
          text.gsub(/\<.*?\>/) do |tag|
            tag_contents = tag.match(/\<(.*?)\>/).captures.first.strip

            # Unclosed calls to template overflow out of the blockquote block,
            # wrecking the rest of our PRs. Other tags don't share this problem.
            next "\\#{tag}" if tag_contents.start_with?("template")

            tag
          end
        end
      end
    end
  end
end
