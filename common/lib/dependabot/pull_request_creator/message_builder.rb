# frozen_string_literal: true

require "pathname"
require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/metadata_finders"
require "dependabot/pull_request_creator"

# rubocop:disable Metrics/ClassLength
module Dependabot
  class PullRequestCreator
    class MessageBuilder
      ANGULAR_PREFIXES = %w(build chore ci docs feat fix perf refactor style
                            test).freeze
      ESLINT_PREFIXES  = %w(Breaking Build Chore Docs Fix New Update
                            Upgrade).freeze
      GITMOJI_PREFIXES = %w(alien ambulance apple arrow_down arrow_up art beers
                            bento bookmark boom bug building_construction bulb
                            busts_in_silhouette camera_flash card_file_box
                            chart_with_upwards_trend checkered_flag
                            children_crossing clown_face construction
                            construction_worker egg fire globe_with_meridians
                            green_apple green_heart hankey heavy_minus_sign
                            heavy_plus_sign iphone lipstick lock loud_sound memo
                            mute ok_hand package page_facing_up pencil2 penguin
                            pushpin recycle rewind robot rocket rotating_light
                            see_no_evil sparkles speech_balloon tada truck
                            twisted_rightwards_arrows whale wheelchair
                            white_check_mark wrench zap).freeze
      ISSUE_TAG_REGEX =
        /(?<=[^A-Za-z0-9\[\\]|^)\\*(?<tag>(?:\#|GH-)\d+)(?=[^A-Za-z0-9\-]|$)/.
        freeze
      GITHUB_REF_REGEX = %r{
        (?:https?://)?
        github\.com/[^/\s]+/[^/\s]+/
        (?:issue|pull)s?/(?<number>\d+)
      }x.freeze

      attr_reader :source, :dependencies, :files, :credentials,
                  :pr_message_footer, :author_details, :vulnerabilities_fixed,
                  :github_link_proxy

      def initialize(source:, dependencies:, files:, credentials:,
                     pr_message_footer: nil, author_details: nil,
                     vulnerabilities_fixed: {}, github_link_proxy: nil)
        @dependencies          = dependencies
        @files                 = files
        @source                = source
        @credentials           = credentials
        @pr_message_footer     = pr_message_footer
        @author_details        = author_details
        @vulnerabilities_fixed = vulnerabilities_fixed
        @github_link_proxy     = github_link_proxy
      end

      def pr_name
        return library_pr_name if library?

        application_pr_name
      end

      def pr_message
        commit_message_intro + metadata_cascades + prefixed_pr_message_footer
      end

      def commit_message
        message = commit_subject + "\n\n"
        message += commit_message_intro
        message += metadata_links
        message += "\n\n" + message_trailers if message_trailers
        message
      end

      private

      def commit_subject
        subject = pr_name.gsub("⬆️", ":arrow_up:").gsub("🔒", ":lock:")
        return subject unless subject.length > 72

        subject = subject.gsub(/ from [^\s]*? to [^\s]*/, "")
        return subject unless subject.length > 72

        subject.split(" in ").first
      end

      def commit_message_intro
        return requirement_commit_message_intro if library?

        version_commit_message_intro
      end

      def prefixed_pr_message_footer
        return "" unless pr_message_footer

        "\n\n#{pr_message_footer}"
      end

      def message_trailers
        return unless on_behalf_of_message || signoff_message

        [on_behalf_of_message, signoff_message].compact.join("\n")
      end

      def signoff_message
        return unless author_details.is_a?(Hash)
        return unless author_details[:name] && author_details[:email]

        "Signed-off-by: #{author_details[:name]} <#{author_details[:email]}>"
      end

      def on_behalf_of_message
        return unless author_details.is_a?(Hash)
        return unless author_details[:org_name] && author_details[:org_email]

        "On-behalf-of: @#{author_details[:org_name]} "\
        "<#{author_details[:org_email]}>"
      end

      def library_pr_name
        pr_name = pr_name_prefix

        pr_name +=
          if dependencies.count == 1
            "#{dependencies.first.display_name} requirement "\
            "from #{old_library_requirement(dependencies.first)} "\
            "to #{new_library_requirement(dependencies.first)}"
          else
            names = dependencies.map(&:name)
            "requirements for #{names[0..-2].join(', ')} and #{names[-1]}"
          end

        return pr_name if files.first.directory == "/"

        pr_name + " in #{files.first.directory}"
      end

      # rubocop:disable Metrics/AbcSize
      def application_pr_name
        pr_name = pr_name_prefix

        pr_name +=
          if dependencies.count == 1
            dependency = dependencies.first
            "#{dependency.display_name} from #{previous_version(dependency)} "\
            "to #{new_version(dependency)}"
          elsif updating_a_property?
            dependency = dependencies.first
            "#{property_name} from #{previous_version(dependency)} "\
            "to #{new_version(dependency)}"
          elsif updating_a_dependency_set?
            dependency = dependencies.first
            "#{dependency_set.fetch(:group)} dependency set "\
            "from #{previous_version(dependency)} "\
            "to #{new_version(dependency)}"
          else
            names = dependencies.map(&:name)
            "#{names[0..-2].join(', ')} and #{names[-1]}"
          end

        return pr_name if files.first.directory == "/"

        pr_name + " in #{files.first.directory}"
      end
      # rubocop:enable Metrics/AbcSize

      def pr_name_prefix
        prefix = commit_prefix.to_s
        prefix += security_prefix if includes_security_fixes?
        prefix + pr_name_first_word
      end

      def commit_prefix
        # If there is a previous Dependabot commit, and it used a known style,
        # use that as our model for subsequent commits
        case last_dependabot_commit_style
        when :gitmoji then "⬆️ "
        when :conventional_prefix then "#{last_dependabot_commit_prefix}: "
        when :conventional_prefix_with_scope
          "#{last_dependabot_commit_prefix}(#{scope}): "
        else
          # Otherwise we need to detect the user's preferred style from the
          # existing commits on their repo
          build_commit_prefix_from_previous_commits
        end
      end

      def security_prefix
        return "🔒 " if commit_prefix == "⬆️ "

        capitalize_first_word? ? "[Security] " : "[security] "
      end

      def pr_name_first_word
        first_word = library? ? "update " : "bump "
        capitalize_first_word? ? first_word.capitalize : first_word
      end

      def capitalize_first_word?
        case last_dependabot_commit_style
        when :gitmoji then true
        when :conventional_prefix, :conventional_prefix_with_scope
          last_dependabot_commit_message.match?(/: (\[Security\] )?(B|U)/)
        else
          if using_angular_commit_messages? || using_eslint_commit_messages?
            prefixes = ANGULAR_PREFIXES + ESLINT_PREFIXES
            semantic_msgs = recent_commit_messages.select do |message|
              prefixes.any? { |pre| message.match?(/#{pre}[:(]/i) }
            end

            return true if semantic_msgs.all? { |m| m.match?(/:\s+\[?[A-Z]/) }
            return false if semantic_msgs.all? { |m| m.match?(/:\s+\[?[a-z]/) }
          end

          !commit_prefix&.match(/^[a-z]/)
        end
      end

      def build_commit_prefix_from_previous_commits
        if using_angular_commit_messages?
          "#{angular_commit_prefix}(#{scope}): "
        elsif using_eslint_commit_messages?
          # https://eslint.org/docs/developer-guide/contributing/pull-requests
          "Upgrade: "
        elsif using_gitmoji_commit_messages?
          "⬆️ "
        elsif using_prefixed_commit_messages?
          "build(#{scope}): "
        end
      end

      def scope
        dependencies.any?(&:production?) ? "deps" : "deps-dev"
      end

      def last_dependabot_commit_style
        return unless (msg = last_dependabot_commit_message)

        return :gitmoji if msg.start_with?("⬆️")
        return :conventional_prefix if msg.match?(/^(chore|build|upgrade):/i)
        return unless msg.match?(/^(chore|build|upgrade)\(/i)

        :conventional_prefix_with_scope
      end

      def last_dependabot_commit_prefix
        last_dependabot_commit_message&.split(/[:(]/)&.first
      end

      def requirement_commit_message_intro
        msg = "Updates the requirements on "

        msg +=
          if dependencies.count == 1
            "#{dependency_links.first} "
          else
            "#{dependency_links[0..-2].join(', ')} and #{dependency_links[-1]} "
          end

        msg + "to permit the latest version."
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def version_commit_message_intro
        if dependencies.count > 1 && updating_a_property?
          return multidependency_property_intro
        end

        if dependencies.count > 1 && updating_a_dependency_set?
          return dependency_set_intro
        end

        return multidependency_intro if dependencies.count > 1

        dependency = dependencies.first
        msg = "Bumps #{dependency_links.first} "\
              "from #{previous_version(dependency)} "\
              "to #{new_version(dependency)}."

        if switching_from_ref_to_release?(dependency)
          msg += " This release includes the previously tagged commit."
        end

        if vulnerabilities_fixed[dependency.name]&.any?
          msg += " **This update includes security fixes.**"
        end

        msg
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      def multidependency_property_intro
        dependency = dependencies.first

        "Bumps `#{property_name}` "\
        "from #{previous_version(dependency)} "\
        "to #{new_version(dependency)}."
      end

      def dependency_set_intro
        dependency = dependencies.first

        "Bumps `#{dependency_set.fetch(:group)}` "\
        "dependency set from #{previous_version(dependency)} "\
        "to #{new_version(dependency)}."
      end

      def multidependency_intro
        "Bumps #{dependency_links[0..-2].join(', ')} "\
        "and #{dependency_links[-1]}. These "\
        "dependencies needed to be updated together."
      end

      def updating_a_property?
        dependencies.first.
          requirements.
          any? { |r| r.dig(:metadata, :property_name) }
      end

      def updating_a_dependency_set?
        dependencies.first.
          requirements.
          any? { |r| r.dig(:metadata, :dependency_set) }
      end

      def property_name
        @property_name ||= dependencies.first.requirements.
                           find { |r| r.dig(:metadata, :property_name) }&.
                           dig(:metadata, :property_name)

        raise "No property name!" unless @property_name

        @property_name
      end

      def dependency_set
        @dependency_set ||= dependencies.first.requirements.
                            find { |r| r.dig(:metadata, :dependency_set) }&.
                            dig(:metadata, :dependency_set)

        raise "No dependency set!" unless @dependency_set

        @dependency_set
      end

      def dependency_links
        dependencies.map do |dependency|
          if source_url(dependency)
            "[#{dependency.display_name}](#{source_url(dependency)})"
          elsif homepage_url(dependency)
            "[#{dependency.display_name}](#{homepage_url(dependency)})"
          else
            dependency.display_name
          end
        end
      end

      def metadata_links
        if dependencies.count == 1
          return metadata_links_for_dep(dependencies.first)
        end

        dependencies.map do |dep|
          "\n\nUpdates `#{dep.display_name}` from #{previous_version(dep)} to "\
          "#{new_version(dep)}"\
          "#{metadata_links_for_dep(dep)}"
        end.join
      end

      def metadata_links_for_dep(dep)
        msg = ""
        msg += "\n- [Release notes](#{releases_url(dep)})" if releases_url(dep)
        msg += "\n- [Changelog](#{changelog_url(dep)})" if changelog_url(dep)
        msg += "\n- [Upgrade guide](#{upgrade_url(dep)})" if upgrade_url(dep)
        msg += "\n- [Commits](#{commits_url(dep)})" if commits_url(dep)
        msg
      end

      def metadata_cascades
        if dependencies.count == 1
          return metadata_cascades_for_dep(dependencies.first)
        end

        dependencies.map do |dep|
          msg = "\n\nUpdates `#{dep.display_name}` from "\
                "#{previous_version(dep)} to #{new_version(dep)}"
          if vulnerabilities_fixed[dep.name]&.any?
            msg += ". **This update includes security fixes.**"
          end
          msg + metadata_cascades_for_dep(dep)
        end.join
      end

      def metadata_cascades_for_dep(dep)
        msg = ""
        msg += vulnerabilities_cascade(dep)
        msg += release_cascade(dep)
        msg += changelog_cascade(dep)
        msg += upgrade_guide_cascade(dep)
        msg += commits_cascade(dep)
        msg += maintainer_changes_cascade(dep)
        msg += "\n<br />" unless msg == ""
        sanitize_links_and_mentions(msg)
      end

      def vulnerabilities_cascade(dep)
        fixed_vulns = vulnerabilities_fixed[dep.name]
        return "" unless fixed_vulns&.any?

        msg = ""
        fixed_vulns.each { |v| msg += serialized_vulnerability_details(v) }
        msg = sanitize_template_tags(msg)

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

        build_details_tag(summary: "Upgrade guide", body: msg)
      end

      def commits_cascade(dep)
        return "" unless commits_url(dep) && commits(dep)

        msg = ""

        commits(dep).reverse.first(10).each do |commit|
          title = commit[:message].strip.split("\n").first
          title = title.slice(0..76) + "..." if title && title.length > 80
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

        build_details_tag(summary: "Commits", body: msg)
      end

      def maintainer_changes_cascade(dep)
        return "" unless maintainer_changes(dep)

        build_details_tag(
          summary: "Maintainer changes",
          body: maintainer_changes(dep) + "\n"
        )
      end

      def build_details_tag(summary:, body:)
        msg = "\n<details>\n<summary>#{summary}</summary>\n\n"
        msg += body
        msg + "</details>"
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

      def releases_url(dependency)
        metadata_finder(dependency).releases_url
      end

      def releases_text(dependency)
        metadata_finder(dependency).releases_text
      end

      def changelog_url(dependency)
        metadata_finder(dependency).changelog_url
      end

      def changelog_text(dependency)
        metadata_finder(dependency).changelog_text
      end

      def upgrade_url(dependency)
        metadata_finder(dependency).upgrade_guide_url
      end

      def upgrade_text(dependency)
        metadata_finder(dependency).upgrade_guide_text
      end

      def commits_url(dependency)
        metadata_finder(dependency).commits_url
      end

      def commits(dependency)
        metadata_finder(dependency).commits
      end

      def maintainer_changes(dependency)
        metadata_finder(dependency).maintainer_changes
      end

      def source_url(dependency)
        metadata_finder(dependency).source_url
      end

      def homepage_url(dependency)
        metadata_finder(dependency).homepage_url
      end

      def metadata_finder(dependency)
        @metadata_finder ||= {}
        @metadata_finder[dependency.name] ||=
          MetadataFinders.
          for_package_manager(dependency.package_manager).
          new(dependency: dependency, credentials: credentials)
      end

      def previous_version(dependency)
        if dependency.previous_version.match?(/^[0-9a-f]{40}$/)
          return previous_ref(dependency) if ref_changed?(dependency)

          "`#{dependency.previous_version[0..6]}`"
        elsif dependency.version == dependency.previous_version &&
              package_manager == "docker"
          digest =
            dependency.previous_requirements.
            map { |r| r.dig(:source, "digest") || r.dig(:source, :digest) }.
            compact.first
          "`#{digest.split(':').last[0..6]}`"
        else
          dependency.previous_version
        end
      end

      def new_version(dependency)
        if dependency.version.match?(/^[0-9a-f]{40}$/)
          return new_ref(dependency) if ref_changed?(dependency)

          "`#{dependency.version[0..6]}`"
        elsif dependency.version == dependency.previous_version &&
              package_manager == "docker"
          digest =
            dependency.requirements.
            map { |r| r.dig(:source, "digest") || r.dig(:source, :digest) }.
            compact.first
          "`#{digest.split(':').last[0..6]}`"
        else
          dependency.version
        end
      end

      def previous_ref(dependency)
        dependency.previous_requirements.map do |r|
          r.dig(:source, "ref") || r.dig(:source, :ref)
        end.compact.first
      end

      def new_ref(dependency)
        dependency.requirements.map do |r|
          r.dig(:source, "ref") || r.dig(:source, :ref)
        end.compact.first
      end

      def old_library_requirement(dependency)
        old_reqs =
          dependency.previous_requirements - dependency.requirements

        gemspec =
          old_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
        return gemspec.fetch(:requirement) if gemspec

        req = old_reqs.first.fetch(:requirement)
        return req if req
        return previous_ref(dependency) if ref_changed?(dependency)

        raise "No previous requirement!"
      end

      def new_library_requirement(dependency)
        updated_reqs =
          dependency.requirements - dependency.previous_requirements

        gemspec =
          updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
        return gemspec.fetch(:requirement) if gemspec

        req = updated_reqs.first.fetch(:requirement)
        return req if req
        return new_ref(dependency) if ref_changed?(dependency)

        raise "No new requirement!"
      end

      def link_issues(text:, dependency:)
        updated_text = text.gsub(ISSUE_TAG_REGEX) do |mention|
          number = mention.split("#").last.gsub("GH-", "")
          "[#{mention}](#{source_url(dependency)}/issues/#{number})"
        end

        updated_text.gsub(/\[(?<tag>(?:\#|GH-)?\d+)\]\(\)/) do |mention|
          mention = mention.match(/(?<=\[)(.*)(?=\])/).to_s
          number = mention.match(/\d+/).to_s
          "[#{mention}](#{source_url(dependency)}/issues/#{number})"
        end
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

      def sanitize_links_and_mentions(text)
        text = sanitize_mentions(text)
        sanitize_links(text)
      end

      def sanitize_mentions(text)
        text.gsub(%r{(?<![A-Za-z0-9`])@[\w][\w.-/]*}) do |mention|
          next mention if mention.include?("/")

          last_match = Regexp.last_match

          sanitized_mention = mention.gsub("@", "@&#8203;")
          if last_match.pre_match.chars.last == "[" &&
             last_match.post_match.chars.first == "]"
            sanitized_mention
          else
            "[#{sanitized_mention}](https://github.com/#{mention.tr('@', '')})"
          end
        end
      end

      def sanitize_links(text)
        text.gsub(GITHUB_REF_REGEX) do |ref|
          last_match = Regexp.last_match
          previous_char = last_match.pre_match.chars.last
          next_char = last_match.post_match.chars.first

          sanitized_url =
            ref.gsub("github.com", github_link_proxy || "github.com")
          if (previous_char.nil? || previous_char.match?(/\s/)) &&
             (next_char.nil? || next_char.match?(/\s/))
            "[##{last_match.named_captures.fetch('number')}](#{sanitized_url})"
          else
            sanitized_url
          end
        end
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

      def ref_changed?(dependency)
        return false unless previous_ref(dependency)

        previous_ref(dependency) != new_ref(dependency)
      end

      def library?
        return true if files.map(&:name).any? { |nm| nm.end_with?(".gemspec") }

        dependencies.none?(&:appears_in_lockfile?)
      end

      def switching_from_ref_to_release?(dependency)
        return false unless dependency.previous_version.match?(/^[0-9a-f]{40}$/)

        Gem::Version.correct?(dependency.version)
      end

      def includes_security_fixes?
        vulnerabilities_fixed.values.flatten.any?
      end

      def using_angular_commit_messages?
        return false if recent_commit_messages.none?

        angular_messages = recent_commit_messages.select do |message|
          ANGULAR_PREFIXES.any? { |pre| message.match?(/#{pre}[:(]/i) }
        end

        # Definitely not using Angular commits if < 30% match angular commits
        if angular_messages.count.to_f / recent_commit_messages.count < 0.3
          return false
        end

        eslint_only_pres = ESLINT_PREFIXES.map(&:downcase) - ANGULAR_PREFIXES
        angular_only_pres = ANGULAR_PREFIXES - ESLINT_PREFIXES.map(&:downcase)

        uses_eslint_only_pres =
          recent_commit_messages.
          any? { |m| eslint_only_pres.any? { |pre| m.match?(/#{pre}[:(]/i) } }

        uses_angular_only_pres =
          recent_commit_messages.
          any? { |m| angular_only_pres.any? { |pre| m.match?(/#{pre}[:(]/i) } }

        # If using any angular-only prefixes, return true
        # (i.e., we assume Angular over ESLint when both are present)
        return true if uses_angular_only_pres
        return false if uses_eslint_only_pres

        true
      end

      def using_eslint_commit_messages?
        return false if recent_commit_messages.none?

        semantic_messages = recent_commit_messages.select do |message|
          ESLINT_PREFIXES.any? { |pre| message.start_with?(/#{pre}[:(]/) }
        end

        semantic_messages.count.to_f / recent_commit_messages.count > 0.3
      end

      def using_prefixed_commit_messages?
        return false if using_gitmoji_commit_messages?
        return false if recent_commit_messages.none?

        prefixed_messages = recent_commit_messages.select do |message|
          message.start_with?(/[a-z][^\s]+:/)
        end

        prefixed_messages.count.to_f / recent_commit_messages.count > 0.3
      end

      def angular_commit_prefix
        raise "Not using angular commits!" unless using_angular_commit_messages?

        recent_commits_using_chore =
          recent_commit_messages.
          any? { |msg| msg.start_with?("chore", "Chore") }

        recent_commits_using_build =
          recent_commit_messages.
          any? { |msg| msg.start_with?("build", "Build") }

        commit_prefix =
          if recent_commits_using_chore && !recent_commits_using_build
            "chore"
          else
            "build"
          end

        if capitalize_angular_commit_prefix?
          commit_prefix = commit_prefix.capitalize
        end

        commit_prefix
      end

      def capitalize_angular_commit_prefix?
        semantic_messages = recent_commit_messages.select do |message|
          ANGULAR_PREFIXES.any? { |pre| message.match?(/#{pre}[:(]/i) }
        end

        if semantic_messages.none?
          return last_dependabot_commit_message&.match?(/^A-Z/)
        end

        capitalized_msgs = semantic_messages.select { |m| m.match?(/^[A-Z]/) }
        capitalized_msgs.count.to_f / semantic_messages.count > 0.5
      end

      def using_gitmoji_commit_messages?
        return false unless recent_commit_messages.any?

        gitmoji_messages =
          recent_commit_messages.
          select { |m| GITMOJI_PREFIXES.any? { |pre| m.match?(/:#{pre}:/i) } }

        gitmoji_messages.count / recent_commit_messages.count.to_f > 0.3
      end

      def recent_commit_messages
        case source.provider
        when "github" then recent_github_commit_messages
        when "gitlab" then recent_gitlab_commit_messages
        else raise "Unsupported provider: #{source.provider}"
        end
      end

      def recent_github_commit_messages
        recent_github_commits.
          reject { |c| c.author&.type == "Bot" }.
          reject { |c| c.commit&.message&.start_with?("Merge") }.
          map(&:commit).
          map(&:message).
          compact.
          map(&:strip)
      end

      def recent_gitlab_commit_messages
        @recent_gitlab_commit_messages ||=
          gitlab_client_for_source.commits(source.repo)

        @recent_gitlab_commit_messages.
          reject { |c| c.author_email == "support@dependabot.com" }.
          reject { |c| c.message&.start_with?("merge !") }.
          map(&:message).
          compact.
          map(&:strip)
      end

      def last_dependabot_commit_message
        case source.provider
        when "github" then last_github_dependabot_commit_message
        when "gitlab" then last_gitlab_dependabot_commit_message
        else raise "Unsupported provider: #{source.provider}"
        end
      end

      def last_github_dependabot_commit_message
        recent_github_commits.
          reject { |c| c.commit&.message&.start_with?("Merge") }.
          find { |c| c.commit.author&.name == "dependabot[bot]" }&.
          commit&.
          message&.
          strip
      end

      def recent_github_commits
        @recent_github_commits ||=
          github_client_for_source.commits(source.repo, per_page: 100)
      rescue Octokit::Conflict
        @recent_github_commits ||= []
      end

      def last_gitlab_dependabot_commit_message
        @recent_gitlab_commit_messages ||=
          gitlab_client_for_source.commits(source.repo)

        @recent_gitlab_commit_messages.
          find { |c| c.author_email == "support@dependabot.com" }&.
          message&.
          strip
      end

      def github_client_for_source
        @github_client_for_source ||=
          Dependabot::Clients::GithubWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def gitlab_client_for_source
        @gitlab_client_for_source ||=
          Dependabot::Clients::GitlabWithRetries.for_source(
            source: source,
            credentials: credentials
          )
      end

      def package_manager
        @package_manager ||= dependencies.first.package_manager
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
