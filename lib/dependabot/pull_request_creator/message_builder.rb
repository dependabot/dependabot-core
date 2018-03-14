# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/pull_request_creator"

# rubocop:disable Metrics/ClassLength
module Dependabot
  class PullRequestCreator
    class MessageBuilder
      SEMANTIC_PREFIXES = %w(build chore ci docs feat fix perf refactor style
                             test).freeze
      attr_reader :repo_name, :dependencies, :files, :github_client,
                  :pr_message_footer, :author_details

      def initialize(repo_name:, dependencies:, files:, github_client:,
                     pr_message_footer: nil, author_details: nil)
        @dependencies = dependencies
        @files = files
        @repo_name = repo_name
        @github_client = github_client
        @pr_message_footer = pr_message_footer
        @author_details = author_details
      end

      def pr_name
        return library_pr_name if library?
        application_pr_name
      end

      def pr_message
        commit_message_intro + metadata_cascades + prefixed_pr_message_footer
      end

      def commit_message
        message =  pr_name + "\n\n"
        message += commit_message_intro
        message += metadata_links
        message += "\n\n" + signoff_message if signoff_message
        message
      end

      private

      def commit_message_intro
        return requirement_commit_message_intro if library?
        version_commit_message_intro
      end

      def prefixed_pr_message_footer
        return "" unless pr_message_footer
        "\n\n#{pr_message_footer}"
      end

      def signoff_message
        return unless author_details.is_a?(Hash)
        return unless author_details[:name] && author_details[:email]
        "Signed-off-by: #{author_details[:name]} <#{author_details[:email]}>"
      end

      def library_pr_name
        pr_name = using_semantic_commit_messages? ? "build: update " : "Update "

        pr_name +=
          if dependencies.count == 1
            "#{dependencies.first.name} requirement to "\
            "#{new_library_requirement(dependencies.first)}"
          else
            names = dependencies.map(&:name)
            "requirements for #{names[0..-2].join(', ')} and #{names[-1]}"
          end

        return pr_name if files.first.directory == "/"

        pr_name + " in #{files.first.directory}"
      end

      def application_pr_name
        pr_name = using_semantic_commit_messages? ? "build: bump " : "Bump "

        pr_name +=
          if dependencies.count == 1
            dependency = dependencies.first
            "#{dependency.name} from #{previous_version(dependency)} "\
            "to #{new_version(dependency)}"
          else
            names = dependencies.map(&:name)
            "#{names[0..-2].join(', ')} and #{names[-1]}"
          end

        return pr_name if files.first.directory == "/"

        pr_name + " in #{files.first.directory}"
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

      def version_commit_message_intro
        if dependencies.count > 1
          return "Bumps #{dependency_links[0..-2].join(', ')} "\
                 "and #{dependency_links[-1]}. These "\
                 "dependencies needed to be updated together."
        end

        dependency = dependencies.first
        msg = "Bumps #{dependency_links.first} "\
              "from #{previous_version(dependency)} "\
              "to #{new_version(dependency)}."

        if switching_from_ref_to_release?(dependency)
          msg += " This release includes the previously tagged commit."
        end

        msg
      end

      def dependency_links
        dependencies.map do |dependency|
          if source_url(dependency)
            "[#{dependency.name}](#{source_url(dependency)})"
          elsif homepage_url(dependency)
            "[#{dependency.name}](#{homepage_url(dependency)})"
          else
            dependency.name
          end
        end
      end

      def metadata_links
        if dependencies.count == 1
          return metadata_links_for_dep(dependencies.first)
        end

        dependencies.map do |dep|
          "\n\nUpdates `#{dep.name}` from #{previous_version(dep)} to "\
          "#{new_version(dep)}"\
          "#{metadata_links_for_dep(dep)}"
        end.join
      end

      def metadata_links_for_dep(dep)
        msg = ""
        msg += "\n- [Release notes](#{release_url(dep)})" if release_url(dep)
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
          "\n\nUpdates `#{dep.name}` from #{previous_version(dep)} to "\
          "#{new_version(dep)}"\
          "#{metadata_cascades_for_dep(dep)}"
        end.join
      end

      def metadata_cascades_for_dep(dep)
        return metadata_links_for_dep(dep) if upgrade_url(dep)

        msg = ""
        msg += release_cascade(dep)
        msg += changelog_cascade(dep)
        msg += commits_cascade(dep)
        msg += "\n<br />" unless msg == ""
        msg
      end

      def commits_cascade(dep)
        return "" unless commits_url(dep) && commits(dep)

        msg = "\n<details>\n<summary>Commits</summary>\n\n"

        commits(dep).first(10).each do |commit|
          title = commit[:message].split("\n").first
          title = title.slice(0..76) + "..." if title.length > 80
          sha = commit[:sha][0, 7]
          msg += "- [`#{sha}`](#{commit[:html_url]}) #{delink_mention(title)}\n"
        end

        msg +=
          if commits(dep).count > 10
            "- Additional commits viewable in "\
            "[compare view](#{commits_url(dep)})\n"
          else
            "- See full diff in [compare view](#{commits_url(dep)})\n"
          end

        msg + "</details>"
      end

      def changelog_cascade(dep)
        return "" unless changelog_url(dep) && changelog_text(dep)

        msg = "\n<details>\n<summary>Changelog</summary>\n\n"
        msg += "*Sourced from [this file](#{changelog_url(dep)})*\n\n"
        msg +=
          begin
            changelog_lines = changelog_text(dep).split("\n").first(50)
            changelog_lines = changelog_lines.map { |line| "> #{line}\n" }
            if changelog_lines.count == 50
              changelog_lines << "> ... (truncated)"
            end
            changelog_lines.join
          end
        msg = delink_mention(msg)
        msg + "</details>"
      end

      def release_cascade(dep)
        return "" unless release_text(dep) || release_url(dep)

        msg = "\n<details>\n<summary>Release notes</summary>\n\n"
        msg +=
          if release_text(dep)
            text =
              release_text(dep).split("\n").
              map { |line| "> #{line}\n" }.join
            delink_mention(text)
          else
            "- [See all GitHub releases](#{release_url(dep)})\n"
          end
        msg + "</details>"
      end

      def release_url(dependency)
        metadata_finder(dependency).release_url
      end

      def release_text(dependency)
        metadata_finder(dependency).release_text
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

      def commits_url(dependency)
        metadata_finder(dependency).commits_url
      end

      def commits(dependency)
        metadata_finder(dependency).commits
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
          dependency.previous_version[0..5]
        else
          dependency.previous_version
        end
      end

      def new_version(dependency)
        if dependency.version.match?(/^[0-9a-f]{40}$/)
          return new_ref(dependency) if ref_changed?(dependency)
          dependency.version[0..5]
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

      def new_library_requirement(dependency)
        updated_reqs =
          dependency.requirements - dependency.previous_requirements

        gemspec =
          updated_reqs.find { |r| r[:file].match?(%r{^[^/]*\.gemspec$}) }
        return gemspec[:requirement] if gemspec
        updated_reqs.first[:requirement]
      end

      def delink_mention(text)
        text.gsub(/(?<![A-Za-z0-9])@[A-Za-z0-9]+/) do |mention|
          "[**#{mention.tr('@', '')}**]"\
          "(https://github.com/#{mention.tr('@', '')})"
        end
      end

      def ref_changed?(dependency)
        previous_ref(dependency) && new_ref(dependency) &&
          previous_ref(dependency) != new_ref(dependency)
      end

      def library?
        filenames = files.map(&:name)
        return true if filenames.any? { |nm| nm.match?(%r{^[^/]*\.gemspec$}) }
        dependencies.none?(&:appears_in_lockfile?)
      end

      def switching_from_ref_to_release?(dependency)
        return false unless dependency.previous_version.match?(/^[0-9a-f]{40}$/)
        Gem::Version.correct?(dependency.version)
      end

      def using_semantic_commit_messages?
        return false if recent_commit_messages.none?

        semantic_messages = recent_commit_messages.select do |message|
          SEMANTIC_PREFIXES.any? { |pre| message.match?(/#{pre}[:(]/i) }
        end

        semantic_messages.count.to_f / recent_commit_messages.count > 0.3
      end

      def recent_commit_messages
        @recent_commit_messages ||=
          github_client.commits(repo_name).
          reject { |c| c.author&.type == "Bot" }.
          map(&:commit).
          map(&:message).
          compact
      end

      def credentials
        [
          {
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => github_client.access_token
          }
        ]
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
