# frozen_string_literal: true

require "dependabot/pull_request_creator/message_builder"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      class MetadataPresenter
        attr_reader :dependency, :provider, :metadata_finder

        def initialize(dependency:, provider:, metadata_finder:)
          @dependency = dependency
          @provider = provider
          @metadata_finder = metadata_finder
        end

        def to_s
          msg = ""
          msg += vulnerabilities_cascade(dep)
          msg += release_cascade(dep)
          msg += changelog_cascade(dep)
          msg += upgrade_guide_cascade(dep)
          msg += commits_cascade(dep)
          msg += maintainer_changes_cascade(dep)
          msg += break_tag unless msg == ""
          "\n" + sanitize_links_and_mentions(msg, unsafe: true)
        end

        private

        def vulnerabilities_cascade(dep)
          fixed_vulns = vulnerabilities_fixed[dep.name]
          return "" unless fixed_vulns&.any?

          msg = ""
          fixed_vulns.each { |v| msg += serialized_vulnerability_details(v) }
          msg = sanitize_template_tags(msg)
          msg = sanitize_links_and_mentions(msg)

          build_details_tag(summary: "Vulnerabilities fixed", body: msg)
        end

        def release_cascade(dep)
          return "" unless releases_text(dep) && releases_url(dep)

          msg = "*Sourced from [#{dep.display_name}'s releases]"\
                "(#{releases_url(dep)}).*\n\n"
          msg +=
            begin
              release_note_lines = releases_text(dep).split("\n").first(50)
              release_note_lines = release_note_lines.map { |line| "> #{line}\n" }
              if release_note_lines.count == 50
                release_note_lines << truncated_line
              end
              release_note_lines.join
            end
          msg = link_issues(text: msg, dependency: dep)
          msg = fix_relative_links(
            text: msg,
            base_url: source_url(dep) + "/blob/HEAD/"
          )
          msg = sanitize_template_tags(msg)
          msg = sanitize_links_and_mentions(msg)

          build_details_tag(summary: "Release notes", body: msg)
        end

        def changelog_cascade(dep)
          return "" unless changelog_url(dep) && changelog_text(dep)

          msg = "*Sourced from "\
                "[#{dep.display_name}'s changelog](#{changelog_url(dep)}).*\n\n"
          msg +=
            begin
              changelog_lines = changelog_text(dep).split("\n").first(50)
              changelog_lines = changelog_lines.map { |line| "> #{line}\n" }
              changelog_lines << truncated_line if changelog_lines.count == 50
              changelog_lines.join
            end
          msg = link_issues(text: msg, dependency: dep)
          msg = fix_relative_links(text: msg, base_url: changelog_url(dep))
          msg = sanitize_template_tags(msg)
          msg = sanitize_links_and_mentions(msg)

          build_details_tag(summary: "Changelog", body: msg)
        end

        def upgrade_guide_cascade(dep)
          return "" unless upgrade_url(dep) && upgrade_text(dep)

          msg = "*Sourced from "\
                "[#{dep.display_name}'s upgrade guide]"\
                "(#{upgrade_url(dep)}).*\n\n"
          msg +=
            begin
              upgrade_lines = upgrade_text(dep).split("\n").first(50)
              upgrade_lines = upgrade_lines.map { |line| "> #{line}\n" }
              upgrade_lines << truncated_line if upgrade_lines.count == 50
              upgrade_lines.join
            end
          msg = link_issues(text: msg, dependency: dep)
          msg = fix_relative_links(text: msg, base_url: upgrade_url(dep))
          msg = sanitize_template_tags(msg)
          msg = sanitize_links_and_mentions(msg)

          build_details_tag(summary: "Upgrade guide", body: msg)
        end

        def commits_cascade(dep)
          return "" unless commits_url(dep) && commits(dep)

          msg = ""

          commits(dep).reverse.first(10).each do |commit|
            title = commit[:message].strip.split("\n").first
            title = title.slice(0..76) + "..." if title && title.length > 80
            title = title&.gsub(/(?<=[^\w.-])([_*`~])/, '\\1')
            sha = commit[:sha][0, 7]
            msg += "- [`#{sha}`](#{commit[:html_url]}) #{title}\n"
          end

          msg = msg.gsub(/\<.*?\>/) { |tag| "\\#{tag}" }

          msg +=
            if commits(dep).count > 10
              "- Additional commits viewable in "\
              "[compare view](#{commits_url(dep)})\n"
            else
              "- See full diff in [compare view](#{commits_url(dep)})\n"
            end
          msg = link_issues(text: msg, dependency: dep)
          msg = sanitize_links_and_mentions(msg)

          build_details_tag(summary: "Commits", body: msg)
        end

        def maintainer_changes_cascade(dep)
          return "" unless maintainer_changes(dep)

          build_details_tag(
            summary: "Maintainer changes",
            body: sanitize_links_and_mentions(maintainer_changes(dep)) + "\n"
          )
        end

        def build_details_tag(summary:, body:)
          # Azure DevOps does not support <details> tag (https://developercommunity.visualstudio.com/content/problem/608769/add-support-for-in-markdown.html)
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

          if details["title"]
            msg += "> **#{details['title'].lines.map(&:strip).join(' ')}**\n"
          end

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
          %w(patched_versions unaffected_versions affected_versions).each do |tp|
            type = tp.split("_").first.capitalize
            next unless details[tp]

            versions_string = details[tp].any? ? details[tp].join("; ") : "none"
            versions_string = versions_string.gsub(/(?<!\\)~/, '\~')
            msg += "> #{type} versions: #{versions_string}\n"
          end
          msg
        end

        def truncated_line
          # Tables can spill out of truncated details, so we close them
          "></tr></table> ... (truncated)\n"
        end

        def break_tag
          source_provider_supports_html? ? "\n<br />" : "\n\n"
        end

        def source_provider_supports_html?
          !%w(azure codecommit).include?(provider)
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
